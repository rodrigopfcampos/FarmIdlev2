// Mapa vivo da fazenda: fundo em escala inteira; lotes que não são seus escurecidos, com placa e entulho;
// lote comprado mostra o entulho e o tempo de limpeza até ficar pronto; 6 mudas por canteiro com vento
// e pulinho na troca de estágio; canteiro maduro pula esperando o clique; canteiro vazio com cultivo escolhido
// mostra o ícone do cultivo; árvores do pomar (muda, adulta, com fruta); prédio dos pastos; zonas clicáveis.
import Phaser from 'phaser';
import { bus } from '../core/bus';
import { ANIM, ANIMAL_BY_ID, ANIMAL_EMOJI, CROPS, FARM, HOUSE_NAMES, LOT_TYPE_NAMES, LOTS, ZONES, type Lot, type Pt } from '../data';
import { petSprite, stageSprite } from '../farm/art';
import { vehicleStatus } from '../farm/expeditions';
import { cameraBounds, pointInPolygon, stageFor } from '../farm/geometry';
import { bakeSway } from '../anim/bake';
import { frameAt, phaseOf, reducedMotion, tableAt } from '../anim/frames';
import { animalLook, lotOffer, plotLook, treeLook } from '../farm/rules';
import { store } from '../farm/store';
import type { FarmState } from '../net/farmApi';
import { duration, formatGold } from '../ui/format';

const MAP_W = 1672;
const MAP_H = 940;
const ZONE_NAMES: Record<string, string> = {
  casa_principal: 'Casa', oficina_ferreiro: 'Forja', barraca_comerciante: 'Barraca', garagem_expedicao: 'Garagem',
};
const depthOf = (y: number) => 1 + y / 10000;

type PlotView = { id: string; polygon: Pt[]; center: Pt; sprites: Phaser.GameObjects.Image[]; base: Pt[]; stage: number; crop: string | null; marker: Phaser.GameObjects.Image; markerKey: string;
  phase: number[]; tex: string; growAt: number };
type Grain = { img: Phaser.GameObjects.Image; x: number; y: number; dx: number; born: number };
type TreeView = { lot: string; slot: number; tree: Phaser.GameObjects.Image; fruit: Phaser.GameObjects.Image; look: string };
type LotDecor = { lot: Lot; sign?: Phaser.GameObjects.Image; debris: Phaser.GameObjects.Image[]; timer: Phaser.GameObjects.Text; building?: Phaser.GameObjects.Image; badge?: Phaser.GameObjects.Text; badgeIcon?: Phaser.GameObjects.Image };
type Hit = { kind: 'zone' | 'plot' | 'locked' | 'orchard' | 'pasture' | 'pet'; id: string; poly?: Pt[]; rect?: number[] };

export class FarmScene extends Phaser.Scene {
  private plots: PlotView[] = [];
  private grains: Grain[] = [];             // terra que pula quando a muda cresce
  private calm = reducedMotion();
  private trees: TreeView[] = [];
  private decor: LotDecor[] = [];
  private shade!: Phaser.GameObjects.Graphics;
  private hover!: Phaser.GameObjects.Graphics;
  private label!: Phaser.GameObjects.Text;
  private downAt: { x: number; y: number } | null = null;
  private owned = new Set<string>();
  private cleaning = new Map<string, number>(); // lote → fim da limpeza (tempo da fazenda)
  private lastSecond = -1;
  private pointer: { x: number; y: number } | null = null; // última posição do mouse no mapa
  private pet: Phaser.GameObjects.Text | null = null;       // pet ativo sem arte (emoji provisório)
  private petImg: Phaser.GameObjects.Image | null = null;   // pet ativo com arte (2 quadros parados)
  private petFrame: 1 | 2 = 1;
  private petAt: Pt | null = null;
  private veh: Phaser.GameObjects.Sprite | null = null;     // veículo ativo na vaga da Garagem
  private vehLabel: Phaser.GameObjects.Text | null = null;  // contador da viagem ou "Receber"
  private vehKey = '';
  private hoverLot = ''; // lote com o mouse em cima (mostra o cultivo planejado dos canteiros vazios)

  constructor() { super('farm'); }

  create(): void {
    this.add.image(0, 0, 'farm_base_map').setOrigin(0, 0);
    this.shade = this.add.graphics().setDepth(0.5);
    this.hover = this.add.graphics().setDepth(5);
    this.label = this.text().setDepth(20).setVisible(false);

    for (const lot of LOTS) {
      // canteiros de todas as lavouras (as mudas só aparecem nos lotes que são seus)
      for (const p of lot.plots ?? []) {
        // 1 planta grande por canteiro (grade limpa 4×2 no lote), pé no centro do canteiro, ordem pelo Y
        const base: Pt[] = [[p.center[0], p.center[1] + 3]];
        const sprites = base.map(([x, y]) => this.add.image(x, y, 'crop_generic_stage1').setOrigin(0.5, 0.9).setVisible(false).setDepth(depthOf(y)));
        // ícone do cultivo escolhido num canteiro vazio: só aparece com o mouse em cima do lote
        const marker = this.add.image(p.center[0], p.center[1], 'crop_generic_stage1').setOrigin(0.5, 0.9).setAlpha(0.85).setVisible(false).setDepth(depthOf(p.center[1]));
        this.plots.push({ id: p.id, polygon: p.polygon, center: p.center, sprites, base, stage: -1, crop: null, marker, markerKey: '',
          phase: base.map(([x, y]) => phaseOf(x, y)), tex: '', growAt: -1 });
      }
      // vagas de árvore do pomar
      (lot.tree_slots ?? []).forEach(([x, y], i) => {
        const tree = this.add.image(x, y, 'tree_leafy_sapling').setOrigin(0.5, 1).setVisible(false).setDepth(depthOf(y));
        const fruit = this.add.image(x, y, 'tree_leafy_sapling').setOrigin(0.5, 1).setVisible(false).setDepth(depthOf(y) + 0.00001);
        this.trees.push({ lot: lot.id, slot: i + 1, tree, fruit, look: '' });
      });
      // placa, entulho, contador da limpeza e prédio do pasto
      const debris = (FARM.visual.no_debris_types.includes(lot.type) ? [] : lot.debris_anchors ?? []).map(([x, y], i) =>
        this.add.image(x, y, FARM.visual.debris_sprites[i % FARM.visual.debris_sprites.length]).setOrigin(0.5, 1).setDepth(depthOf(y)).setVisible(false));
      const sign = lot.sign_anchor ? this.add.image(lot.sign_anchor[0], lot.sign_anchor[1], 'lot_sign').setOrigin(0.5, 1).setDepth(depthOf(lot.sign_anchor[1])).setVisible(false) : undefined;
      const timer = this.text().setOrigin(0.5, 0.5).setPosition(lot.center[0], lot.center[1] - 26).setDepth(19).setVisible(false);
      const building = lot.building && lot.building_anchor
        ? this.add.image(lot.building_anchor[0], lot.building_anchor[1], `building_${lot.building}`).setOrigin(0.5, 1).setDepth(depthOf(lot.building_anchor[1])).setVisible(false)
        : undefined;
      // aviso em cima da casa dos animais: produto pronto (emoji do animal) ou fome (!)
      const badge = building && lot.building_anchor
        ? this.add.text(lot.building_anchor[0], lot.building_anchor[1] - 46, '', { fontFamily: 'system-ui, sans-serif', fontSize: '12px', fontStyle: 'bold', backgroundColor: '#000000aa', padding: { x: 3, y: 1 } })
          .setOrigin(0.5, 1).setResolution(2).setDepth(21).setVisible(false)
        : undefined;
      // arte do animal pronto ao lado do aviso
      const badgeIcon = badge ? this.add.image(lot.building_anchor![0] - 14, lot.building_anchor![1] - 46, '__DEFAULT').setOrigin(1, 1).setDepth(21).setVisible(false) : undefined;
      if (badge) this.tweens.add({ targets: [badge, badgeIcon], y: badge.y - 3, duration: 500, yoyo: true, repeat: -1, ease: 'Sine.InOut' });
      this.decor.push({ lot, sign, debris, timer, building, badge, badgeIcon });
    }

    // Carroça parada na vaga da Garagem, com a animação de parado
    const garage = ZONES.find((z) => z.id === 'garagem_expedicao');
    if (garage?.parked_vehicle_anchor) {
      for (const v of ['carroca', 'carro', 'picape', 'caminhao']) {
        if (this.textures.exists(`vehicle_${v}_idle`)) this.anims.create({ key: `${v}_idle`, frames: this.anims.generateFrameNumbers(`vehicle_${v}_idle`, { start: 0, end: 3 }), frameRate: FARM.visual.vehicle_idle_fps, repeat: -1 });
      }
      const [x, y] = garage.parked_vehicle_anchor;
      this.veh = this.add.sprite(x, y, 'vehicle_carroca_idle').setOrigin(0.5, 1).setDepth(2).play('carroca_idle');
      this.vehLabel = this.text().setOrigin(0.5, 1).setPosition(x, y - 40).setDepth(19).setVisible(false);
    }

    // ponto do pet na frente da Casa
    const house = ZONES.find((z) => z.id === 'casa_principal') as (typeof ZONES)[number] & { pet_anchor?: Pt };
    if (house?.pet_anchor) {
      this.petAt = house.pet_anchor;
      this.pet = this.add.text(house.pet_anchor[0], house.pet_anchor[1], '', { fontSize: '16px' }).setOrigin(0.5, 1).setDepth(depthOf(house.pet_anchor[1])).setVisible(false);
      this.tweens.add({ targets: this.pet, y: house.pet_anchor[1] - 2, duration: 700, yoyo: true, repeat: -1, ease: 'Sine.InOut' });
      this.petImg = this.add.image(house.pet_anchor[0], house.pet_anchor[1], '__DEFAULT').setOrigin(0.5, 1).setDepth(depthOf(house.pet_anchor[1])).setVisible(false);
      // alterna os 2 quadros parados
      this.time.addEvent({ delay: 650, loop: true, callback: () => {
        const id = store.state?.pet?.id;
        const key = id ? petSprite(store.manifest, id, this.petFrame === 1 ? 2 : 1) : null;
        if (key && this.petImg?.visible && this.textures.exists(key)) { this.petFrame = this.petFrame === 1 ? 2 : 1; this.petImg.setTexture(key); }
      } });
    }

    this.setupCamera();
    this.setupInput();
    bus.on('farm:state', (s: FarmState) => this.applyState(s));
    bus.on('fx:harvest', (items: { plot: string; text: string }[]) => this.floatTexts(items));
    if (store.state) this.applyState(store.state);
  }

  /** texto que sobe e some em cima do que foi colhido (+3 Alface) */
  private floatTexts(items: { plot: string; text: string }[]): void {
    for (const it of items) {
      const v = this.plots.find((x) => x.id === it.plot);
      const lot = LOTS.find((l) => l.id === it.plot);
      const [x, y] = v ? v.center : lot ? lot.center : [0, 0];
      const t = this.add.text(x, y - 10, it.text, { fontFamily: 'system-ui, sans-serif', fontSize: '12px', fontStyle: 'bold', color: '#fff3a0', stroke: '#2b2118', strokeThickness: 2 })
        .setOrigin(0.5, 1).setResolution(2).setDepth(30);
      this.tweens.add({ targets: t, y: y - 28, duration: 1400, ease: 'Quad.Out', onComplete: () => t.destroy() });
      this.tweens.add({ targets: t, alpha: 0, delay: 800, duration: 600 });
    }
  }

  private text(): Phaser.GameObjects.Text {
    return this.add.text(0, 0, '', { fontFamily: 'system-ui, sans-serif', fontSize: '12px', color: '#f3e3c3', backgroundColor: '#000000aa', padding: { x: 4, y: 2 } }).setResolution(2);
  }

  private applyState(s: FarmState): void {
    this.owned = new Set(s.lots.map((l) => l.lot_id));
    this.cleaning = new Map(s.lots.filter((l) => l.ready_at > store.clock.farmNow()).map((l) => [l.lot_id, l.ready_at]));
    // lotes que ainda não são seus ficam escurecidos
    this.shade.clear().fillStyle(0x140c08, 0.5);
    for (const lot of LOTS) if (!this.owned.has(lot.id)) this.shade.fillPoints(lot.polygon.map(([x, y]) => new Phaser.Math.Vector2(x, y)), true);
    this.refreshDecor();
    const PET_EMOJI: Record<string, string> = { cachorro: '🐶', gato: '🐱', papagaio: '🦜' };
    const petKey = s.pet ? petSprite(store.manifest, s.pet.id, this.petFrame) : null;
    const hasArt = !!petKey && this.textures.exists(petKey);
    if (hasArt) this.petImg?.setTexture(petKey!);
    this.petImg?.setVisible(!!s.pet && hasArt);
    this.pet?.setText(s.pet ? PET_EMOJI[s.pet.id] ?? '' : '').setVisible(!!s.pet && !hasArt);
    this.refreshGarage(s);
    if (this.pointer) this.showHover(this.pointer.x, this.pointer.y); // o rótulo do lote muda depois da compra
  }

  /** só o veículo ativo aparece na vaga; viajando, a vaga fica vazia com o contador até a volta */
  private refreshGarage(s: FarmState): void {
    if (!this.veh || !this.vehLabel) return;
    const v = s.vehicles.find((x) => x.active) ?? s.vehicles[0];
    if (!v) { this.veh.setVisible(false); this.vehLabel.setVisible(false); return; }
    const now = store.clock.farmNow();
    const st = vehicleStatus(s, v, now);
    const anyBack = s.expeditions.some((x) => x.status === 'back');
    const parked = st.status === 'idle' || st.status === 'back';
    this.veh.setVisible(parked);
    if (parked) {
      const key = v.rarity === 'common' && this.anims.exists(`${v.vehicle_id}_idle`) ? `${v.vehicle_id}_idle` : `vehicle_${v.vehicle_id}_${v.rarity}`;
      if (key !== this.vehKey) {
        this.vehKey = key;
        if (key.endsWith('_idle')) this.veh.play(key);
        else if (this.textures.exists(key)) this.veh.stop().setTexture(key);
      }
    }
    const text = st.status === 'travel' ? `Volta em ${duration(st.until! - now)}` : st.status === 'refurb' ? `Reforma: ${duration(st.until! - now)}` : anyBack ? 'Receber!' : '';
    this.vehLabel.setText(text).setVisible(!!text);
  }

  /** placa só nos lotes à venda; entulho até o fim da limpeza; prédio do pasto depois dela */
  private refreshDecor(): void {
    const now = store.clock.farmNow();
    for (const d of this.decor) {
      const mine = this.owned.has(d.lot.id);
      const end = this.cleaning.get(d.lot.id);
      const inCleanup = end !== undefined && end > now;
      d.sign?.setVisible(!mine);
      d.debris.forEach((x) => x.setVisible(!mine || inCleanup));
      d.building?.setVisible(mine && !inCleanup);
      d.timer.setVisible(inCleanup);
      if (inCleanup) d.timer.setText(`Limpeza ${duration(end! - now)}`);
      if (end !== undefined && !inCleanup) this.cleaning.delete(d.lot.id);
      if (d.badge) {
        const s = store.state;
        const house = s ? Object.entries(s.houses).find(([, h]) => h.lot === d.lot.id)?.[0] : undefined;
        const mine = house ? s!.animals.filter((a) => a.house_id === house) : [];
        const ready = mine.filter((a) => animalLook(a, now) === 'ready');
        const hungry = mine.some((a) => a.state === 'hungry');
        const art = ready.length ? `animal_${ready[0].animal_id}_f1` : '';
        const hasArt = !!art && this.textures.exists(art);
        const txt = ready.length ? `${hasArt ? '' : `${ANIMAL_EMOJI[ready[0].animal_id] ?? ''} `}${ready.length} pronto${ready.length > 1 ? 's' : ''}` : hungry ? 'Sem ração!' : '';
        d.badge.setText(txt).setVisible(!!txt && !inCleanup);
        if (hasArt) d.badgeIcon?.setTexture(art);
        d.badgeIcon?.setVisible(hasArt && !inCleanup).setX(d.badge.x - d.badge.displayWidth / 2 - 1);
      }
    }
  }

  update(time: number): void {
    const s = store.state;
    if (!s) return;
    const now = store.clock.farmNow();
    const t = time / 1000;
    const second = Math.floor(t);
    if (second !== this.lastSecond) { this.lastSecond = second; this.refreshDecor(); this.updateTrees(s, now); this.refreshGarage(s); }
    this.updateGrains(time);
    const byId = new Map(s.plots.map((p) => [p.plot_id, p]));
    const lotReady = new Map(s.lots.map((l) => [l.lot_id, l.ready_at]));
    // 1 estágio por lote: as mudas que ainda crescem mostram o estágio da mais nova do lote; as maduras, o final
    const lotStage = new Map<string, number>();
    for (const p of s.plots) {
      if (p.state !== 'growing' || p.planted_at === null || p.ready_at === null || p.ready_at <= now) continue;
      const lot = p.plot_id.split('-')[0];
      const st = stageFor((now - p.planted_at) / (p.ready_at - p.planted_at), FARM.visual.stage_thresholds);
      lotStage.set(lot, Math.min(lotStage.get(lot) ?? st, st));
    }
    for (const v of this.plots) {
      const p = byId.get(v.id);
      const look = p ? plotLook(p, now, lotReady.get(v.id.split('-')[0]) ?? 0) : 'empty';
      // ícone do cultivo planejado (vermelho quando falta ouro para a semente)
      const mk = look === 'planned' || look === 'cleanup' || look === 'stalled' ? `${look}:${p!.crop_id}` : '';
      if (mk !== v.markerKey) {
        v.markerKey = mk;
        // fantasma da muda (arte do 1º estágio do cultivo), não o ícone de item
        const icon = mk ? stageSprite(store.manifest, p!.crop_id!, 0) : '';
        v.marker.setVisible(false);
        if (mk && this.textures.exists(icon)) v.marker.setTexture(icon).setTint(look === 'stalled' ? 0xff7070 : 0xffffff).setAlpha(look === 'planned' ? 0.6 : 0.4);
      }
      v.marker.setVisible(!!v.markerKey && this.hoverLot === v.id.split('-')[0] && v.marker.texture.key !== '__MISSING');
      if (!p || p.state !== 'growing' || p.planted_at === null || p.ready_at === null) {
        if (v.stage !== -1) { v.sprites.forEach((sp) => sp.setVisible(false)); v.stage = -1; }
        continue;
      }
      const stage = p.ready_at <= now ? stageFor(1, FARM.visual.stage_thresholds) : lotStage.get(v.id.split('-')[0]) ?? 0;
      if (stage !== v.stage || p.planted_crop_id !== v.crop) {
        const key = stageSprite(store.manifest, p.planted_crop_id!, stage);
        // vento por faixas: quadros pré-assados da própria arte (a raiz fica, a ponta inclina)
        const sway = `sway_${key}`;
        v.tex = !this.calm && bakeSway(this, key, sway, ANIM.crop_sway.tip_px, ANIM.crop_sway.curve) ? sway : key;
        v.sprites.forEach((sp) => sp.setTexture(v.tex, v.tex === sway ? 0 : undefined).setVisible(true));
        if (v.stage !== -1 && v.crop === p.planted_crop_id && !this.calm) { v.growAt = time; this.dirt(v, time); } // cresceu: abaixa, sobe e assenta
        v.stage = stage; v.crop = p.planted_crop_id;
      }
      this.animatePlot(v, look === 'ready', time);
    }
  }

  /** vento (quadro por fase), pulinho do maduro e o pulo de crescer — tudo em pixels inteiros e tempo por quadro */
  private animatePlot(v: PlotView, ready: boolean, time: number): void {
    const sw = ANIM.crop_sway, hop = ANIM.crop_ready_hop, grow = ANIM.crop_grow;
    const swaying = v.tex.startsWith('sway_');
    v.sprites.forEach((sp, i) => {
      if (swaying) {
        const f = Math.floor((time + v.phase[i] * sw.phase_ms_per_unit) / sw.ms) % sw.tip_px.length;
        if (Number(sp.frame.name) !== f) sp.setFrame(f);
      }
      let up = 0;
      if (ready && !this.calm) up = tableAt(hop.up_px, hop.ms, time - (v.phase[i] % 16) * hop.stagger_ms);
      if (v.growAt >= 0) {
        const el = time - v.growAt - (Number(v.id.split('-')[1]) - 1) * grow.stagger_ms;
        const total = grow.frames.reduce((s, f) => s + f.ms, 0);
        if (el >= 0 && el < total) up = grow.frames[frameAt(grow.frames, el, false)].up_px;
      }
      sp.setPosition(v.base[i][0], v.base[i][1] - up);
    });
    if (v.growAt >= 0 && time - v.growAt > grow.frames.reduce((s, f) => s + f.ms, 0) + grow.stagger_ms * v.sprites.length) v.growAt = -1;
  }

  /** 3 grãos de terra 1×1/2×1 que pulam do canteiro quando as mudas crescem */
  private dirt(v: PlotView, time: number): void {
    const n = ANIM.crop_grow.dirt_grains;
    for (let k = 0; k < n; k++) {
      const [bx, y] = v.base[(k * 2 + 1) % v.base.length];
      const dx = k % 2 === 0 ? -1 : 1, x = bx + dx * 5; // ao lado da muda, onde a terra aparece
      const img = this.add.image(x, y, 'dirt_grain').setOrigin(0.5, 1).setDepth(9).setVisible(false);
      this.grains.push({ img, x, y, dx, born: time + k * ANIM.crop_grow.stagger_ms });
    }
  }

  private updateGrains(time: number): void {
    const g = ANIM.crop_grow;
    this.grains = this.grains.filter((d) => {
      const i = Math.floor((time - d.born) / g.dirt_ms);
      if (i >= g.dirt_up_px.length) { d.img.destroy(); return false; }
      const k = Math.max(0, i);
      d.img.setPosition(d.x + d.dx * Math.floor(k / 2), d.y - g.dirt_up_px[k]).setVisible(i >= 0);
      return true;
    });
  }

  private updateTrees(s: FarmState, now: number): void {
    const byKey = new Map(s.trees.map((x) => [`${x.lot_id}:${x.slot}`, x]));
    for (const v of this.trees) {
      const tr = byKey.get(`${v.lot}:${v.slot}`);
      const look = tr ? treeLook(tr, now) : 'empty';
      const key = `${look}:${tr?.fruit_id ?? ''}`;
      if (key === v.look) continue;
      const base = tr?.fruit_id ? CROPS[tr.fruit_id].tree_base ?? 'leafy' : 'leafy';
      v.tree.setVisible(look !== 'empty');
      if (look !== 'empty') v.tree.setTexture(`tree_${base}_${look === 'sapling' ? 'sapling' : 'adult'}`);
      v.fruit.setVisible(look === 'fruit');
      if (look === 'fruit') v.fruit.setTexture(`fruit_${tr!.fruit_id}`);
      if (v.look !== '' && look !== 'empty') { // pulinho quando a árvore muda
        v.tree.setScale(1, 0.85);
        this.tweens.add({ targets: v.tree, scaleY: 1, duration: 260, ease: 'Back.Out' });
      }
      v.look = key;
    }
  }

  // ---------- câmera: zoom inteiro, mapa centralizado e arrastar quando ele não cabe ----------
  private setupCamera(): void {
    const fit = () => {
      const { width, height } = this.scale.gameSize;
      const zoom = Math.max(1, Math.floor(Math.min(width / MAP_W, height / MAP_H)));
      const cam = this.cameras.main.setZoom(zoom).setRoundPixels(true);
      // antes, quando só a altura não cabia, os limites prendiam o mapa na esquerda (vídeo da fase 2)
      cam.setBounds(...cameraBounds(MAP_W, MAP_H, width, height, zoom));
      cam.centerOn(MAP_W / 2, MAP_H / 2);
    };
    fit();
    this.scale.on('resize', fit);
  }

  // ---------- clique: zonas, canteiros e lotes; arrastar não conta como clique ----------
  private setupInput(): void {
    const cam = this.cameras.main;
    this.input.on('pointerdown', (p: Phaser.Input.Pointer) => { this.downAt = { x: p.x, y: p.y }; });
    this.input.on('pointermove', (p: Phaser.Input.Pointer) => {
      if (p.isDown) {
        cam.scrollX -= (p.x - p.prevPosition.x) / cam.zoom;
        cam.scrollY -= (p.y - p.prevPosition.y) / cam.zoom;
      }
      this.pointer = { x: p.worldX, y: p.worldY };
      this.showHover(p.worldX, p.worldY);
    });
    this.input.on('pointerup', (p: Phaser.Input.Pointer) => {
      if (!this.downAt || Math.hypot(p.x - this.downAt.x, p.y - this.downAt.y) > 6) { this.downAt = null; return; }
      this.downAt = null;
      const hit = this.hitTest(p.worldX, p.worldY);
      if (hit) bus.emit(`ui:${hit.kind}`, hit.id);
    });
  }

  private hitTest(x: number, y: number): Hit | null {
    if ((this.pet?.visible || this.petImg?.visible) && this.petAt && Math.abs(x - this.petAt[0]) <= 10 && y <= this.petAt[1] + 2 && y >= this.petAt[1] - 20) {
      return { kind: 'pet', id: 'pet', rect: [this.petAt[0] - 10, this.petAt[1] - 20, this.petAt[0] + 10, this.petAt[1] + 2] };
    }
    for (const z of ZONES) for (const r of z.hit_rects) if (x >= r[0] && x <= r[2] && y >= r[1] && y <= r[3]) return { kind: 'zone', id: z.id, rect: r };
    for (const v of this.plots) {
      const lot = v.id.split('-')[0];
      if (this.owned.has(lot) && pointInPolygon(x, y, v.polygon)) return { kind: 'plot', id: v.id, poly: v.polygon };
    }
    for (const lot of LOTS) {
      if (!pointInPolygon(x, y, lot.polygon)) continue;
      if (!this.owned.has(lot.id)) return { kind: 'locked', id: lot.id, poly: lot.polygon };
      if (lot.type === 'pomar') return { kind: 'orchard', id: lot.id, poly: lot.polygon };
      if (lot.type.startsWith('pasto')) return { kind: 'pasture', id: lot.id, poly: lot.polygon };
    }
    return null;
  }

  private hoverText(hit: Hit): string {
    const s = store.state!;
    if (hit.kind === 'zone') return ZONE_NAMES[hit.id];
    if (hit.kind === 'pet') {
      const mine = s.pets.find((p) => p.active);
      return mine && mine.last_care !== s.game_day ? 'Pet · clique para o carinho de hoje' : 'Pet';
    }
    const now = store.clock.farmNow();
    if (hit.kind === 'plot') {
      const p = s.plots.find((x) => x.plot_id === hit.id);
      if (!p) return `Canteiro ${hit.id}`;
      const name = (id: string | null) => (id ? CROPS[id].name_pt : '');
      switch (plotLook(p, now, s.lots.find((l) => l.lot_id === hit.id.split('-')[0])?.ready_at ?? 0)) {
        case 'ready': return `${name(p.planted_crop_id)} pronta · clique para colher`;
        case 'growing': return `${name(p.planted_crop_id)} · pronta em ${duration(p.ready_at! - now)}`;
        case 'planned': return `${name(p.crop_id)} · clique para plantar`;
        case 'cleanup': return `${name(p.crop_id)} · depois da limpeza`;
        case 'stalled': return `${name(p.crop_id)} · falta ouro para a semente`;
        default: return `Canteiro ${hit.id} · clique para escolher o cultivo`;
      }
    }
    if (hit.kind === 'pasture') {
      const house = Object.entries(s.houses).find(([, h]) => h.lot === hit.id)?.[0];
      if (house) {
        const mine = s.animals.filter((a) => a.house_id === house);
        const ready = mine.filter((a) => animalLook(a, now) === 'ready').length;
        if (ready) return `${HOUSE_NAMES[house]} · ${ready} pronto${ready > 1 ? 's' : ''}: clique para coletar`;
        const hungry = mine.filter((a) => a.state === 'hungry').length;
        if (hungry) return `${HOUSE_NAMES[house]} · ${hungry} com fome (falta ouro para a ração)`;
        return `${HOUSE_NAMES[house]} · ${mine.length} animal${mine.length === 1 ? '' : 'is'}${mine[0] ? ` (${ANIMAL_BY_ID[mine[0].animal_id].name_pt}…)` : ''}`;
      }
    }
    if (hit.kind === 'orchard') {
      const ripe = s.trees.filter((x) => x.lot_id === hit.id && x.fruit_id && x.ready_at !== null && x.ready_at <= now).length;
      if (ripe) return `Pomar ${hit.id} · ${ripe} com fruta: clique para colher`;
    }
    const type = LOT_TYPE_NAMES[LOTS.find((l) => l.id === hit.id)!.type];
    if (hit.kind !== 'locked') return `${type} ${hit.id}`;
    const o = lotOffer(hit.id, this.owned, s.level, s.inventory.deed ?? 0, s.gold, s.characters.some((c) => c.class_id === 'ferreiro'), s.fx.cleanup);
    if (!o || o.problems.includes('fim')) return `${type} ${hit.id}`;
    if (!o.neighbor) return `${type} ${hit.id} · precisa de um lote vizinho`;
    return `${type} ${hit.id} · ${formatGold(o.cost)} ouro · nível ${o.needLevel}${o.needsDeed ? ' · 1 Escritura' : ''}`;
  }

  private showHover(x: number, y: number): void {
    const hit = this.hitTest(x, y);
    this.hoverLot = hit?.kind === 'plot' ? hit.id.split('-')[0] : '';
    this.hover.clear();
    this.input.setDefaultCursor(hit ? 'pointer' : 'default');
    if (!hit || !store.state) { this.label.setVisible(false); return; }
    this.hover.lineStyle(1, hit.kind === 'locked' ? 0x9e9e9e : 0xf2c230, 1);
    if (hit.poly) this.hover.strokePoints(hit.poly.map(([px, py]) => new Phaser.Math.Vector2(px, py)), true, true);
    if (hit.rect) this.hover.strokeRect(hit.rect[0], hit.rect[1], hit.rect[2] - hit.rect[0], hit.rect[3] - hit.rect[1]);
    this.label.setText(this.hoverText(hit)).setPosition(Math.round(x + 10), Math.round(y - 22)).setVisible(true);
  }
}
