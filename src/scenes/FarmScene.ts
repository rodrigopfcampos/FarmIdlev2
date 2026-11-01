// Mapa vivo da fazenda (v3): fundo em escala inteira; lotes que não são seus escurecidos, com placa e mato;
// lote comprado mostra o mato e o tempo de limpeza; na hora que fica pronto o mato some com partículas; 6 mudas por canteiro com vento
// e pulinho na troca de estágio; canteiro maduro pula esperando o clique; canteiro vazio com cultivo escolhido
// mostra o ícone do cultivo; árvores do pomar (muda, adulta, com fruta); prédio dos pastos; zonas clicáveis.
import Phaser from 'phaser';
import { bus } from '../core/bus';
import { mapView } from '../core/mapView';
import { ANIM, ANIMAL_BY_ID, ANIMAL_EMOJI, CROPS, FARM, HOUSE_NAMES, LOT_TYPE_NAMES, LOTS, MAP, ZONES, type Lot, type Pt } from '../data';
import { orchardLook } from '../farm/life';
import { vehicleLook } from '../farm/cards';
import { LifeLayer } from './lifeLayer';
import { petSprite, stageSprite } from '../farm/art';
import { vehicleStatus } from '../farm/expeditions';
import { cameraBounds, pointInPolygon, stageFor } from '../farm/geometry';
import { bakeSway } from '../anim/bake';
import { frameAt, phaseOf, reducedMotion, tableAt } from '../anim/frames';
import { animalLook, lotOffer, plotLook } from '../farm/rules';
import { store } from '../farm/store';
import type { FarmState } from '../net/farmApi';
import { duration, formatGold } from '../ui/format';
import { WeatherLayer } from './weatherLayer';

const MAP_W = 1672;
const MAP_H = 940;
const ZONE_NAMES: Record<string, string> = {
  casa_principal: 'Casa', oficina_ferreiro: 'Forja', barraca_comerciante: 'Barraca', garagem_expedicao: 'Garagem',
};
const depthOf = (y: number) => 1 + y / 10000;

type PlotView = { id: string; polygon: Pt[]; center: Pt; sprites: Phaser.GameObjects.Image[]; base: Pt[]; stage: number; crop: string | null; marker: Phaser.GameObjects.Image; markerKey: string;
  phase: number[]; tex: string; growAt: number };
type Grain = { img: Phaser.GameObjects.Image; x: number; y: number; dx: number; born: number };
type TreeView = { lot: string; slot: number; tree: Phaser.GameObjects.Image; look: string };
type LotDecor = { lot: Lot; sign?: Phaser.GameObjects.Image; overlay?: Phaser.GameObjects.Graphics; overlayW: number; overlayOn: boolean | null; timer: Phaser.GameObjects.Text; building?: Phaser.GameObjects.Image; badge?: Phaser.GameObjects.Text; badgeIcon?: Phaser.GameObjects.Image };
type Hit = { kind: 'zone' | 'plot' | 'locked' | 'orchard' | 'pasture' | 'pet'; id: string; poly?: Pt[]; rect?: number[] };

export class FarmScene extends Phaser.Scene {
  private plots: PlotView[] = [];
  private grains: Grain[] = [];             // terra que pula quando a muda cresce
  private calm = reducedMotion();
  private trees: TreeView[] = [];
  private decor: LotDecor[] = [];
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
  private wx!: WeatherLayer; // clima e noite por cima do mapa
  private hoverLot = ''; // lote com o mouse em cima (mostra o cultivo planejado dos canteiros vazios)
  private life!: LifeLayer; // animais nos pastos e peixes no lago
  private vehDrive: { tween: Phaser.Tweens.Tween; moving: boolean } | null = null; // veículo saindo ou chegando
  private vehWas = '';          // situação anterior do veículo (para animar só a mudança vista ao vivo)
  private vehMotor = false;     // veículo a motor (balança, fumaça) ou carroça com cavalo
  private fxAt = 0;             // último fumacinha/poeira
  private dustAt = 0;

  constructor() { super('farm'); }

  create(): void {
    this.add.image(0, 0, 'farm_base_map').setOrigin(0, 0);
    this.addOccluders();
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
        // arte 64×64 com a base de terra: o pé da base (y 51–60 da arte) fica na vaga
        const tree = this.add.image(x, y, 'orchard_pit').setOrigin(0.5, 0.9).setVisible(false).setDepth(depthOf(y));
        this.trees.push({ lot: lot.id, slot: i + 1, tree, look: '' });
      });
      // placa, mato (1 arte no centro cobrindo 85% do lote), contador da limpeza e aviso dos animais
      const hasOverlay = lot.type === 'lavoura' && ANIM.map_marks.locked_shade;
      const polyW = Math.max(...lot.polygon.map((p) => p[0])) - Math.min(...lot.polygon.map((p) => p[0]));
      const overlay = hasOverlay ? this.lockedOverlay(lot) : undefined;
      const sign = lot.sign_anchor && ANIM.map_marks.lot_signs ? this.add.image(lot.sign_anchor[0], lot.sign_anchor[1], 'lot_sign_lock').setOrigin(0.5, 1).setDepth(depthOf(lot.sign_anchor[1])).setVisible(false) : undefined;
      const timer = this.text().setOrigin(0.5, 0.5).setPosition(lot.center[0], lot.center[1] - 26).setDepth(19).setVisible(false);
      // Celeiro e Galinheiro já estão desenhados no mapa v3 (building_in_map): só o aviso fica por cima
      const inMap = (lot as Lot & { building_in_map?: boolean }).building_in_map;
      const building = lot.building && lot.building_anchor && !inMap
        ? this.add.image(lot.building_anchor[0], lot.building_anchor[1], `building_${lot.building}`).setOrigin(0.5, 1).setDepth(depthOf(lot.building_anchor[1])).setVisible(false)
        : undefined;
      // aviso em cima da casa dos animais: produto pronto (emoji do animal) ou fome (!)
      const badge = lot.building && lot.building_anchor
        ? this.add.text(lot.building_anchor[0], lot.building_anchor[1] - 46, '', { fontFamily: 'system-ui, sans-serif', fontSize: '12px', fontStyle: 'bold', backgroundColor: '#000000aa', padding: { x: 3, y: 1 } })
          .setOrigin(0.5, 1).setResolution(2).setDepth(21).setVisible(false)
        : undefined;
      // arte do animal pronto ao lado do aviso
      const badgeIcon = badge ? this.add.image(lot.building_anchor![0] - 14, lot.building_anchor![1] - 46, '__DEFAULT').setOrigin(1, 1).setDepth(21).setVisible(false) : undefined;
      if (badge) this.tweens.add({ targets: [badge, badgeIcon], y: badge.y - 3, duration: 500, yoyo: true, repeat: -1, ease: 'Sine.InOut' });
      this.decor.push({ lot, sign, overlay, overlayW: polyW, overlayOn: null, timer, building, badge, badgeIcon });
    }

    this.wx = new WeatherLayer(this, MAP_W, MAP_H, this.plots.map((p) => p.polygon), this.calm);
    this.life = new LifeLayer(this, this.calm);

    // Carroça parada na vaga da Garagem, com a animação de parado
    const garage = ZONES.find((z) => z.id === 'garagem_expedicao');
    if (garage?.parked_vehicle_anchor) {
      for (const v of ['carroca', 'carro', 'picape', 'caminhao']) {
        if (this.textures.exists(`vehicle_${v}_idle`)) this.anims.create({ key: `${v}_idle`, frames: this.anims.generateFrameNumbers(`vehicle_${v}_idle`, { start: 0, end: 3 }), frameRate: FARM.visual.vehicle_idle_fps, repeat: -1 });
      }
      const V = ANIM.vehicles;
      if (this.textures.exists(V.horse_sprite)) this.anims.create({ key: 'horse_walk', frames: this.anims.generateFrameNumbers(V.horse_sprite, {}), frameRate: V.horse_fps, repeat: -1 });
      const [x, y] = garage.parked_vehicle_anchor;
      this.veh = this.add.sprite(x, y, this.textures.exists(V.horse_sprite) ? V.horse_sprite : 'vehicle_carroca_idle', 0).setOrigin(0.5, 1).setDepth(depthOf(y));
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
    // sem escurecer os lotes que não são seus (o dono não quer marcação no terreno)
    this.refreshDecor();
    const PET_EMOJI: Record<string, string> = { cachorro: '🐶', gato: '🐱', papagaio: '🦜' };
    const petKey = s.pet ? petSprite(store.manifest, s.pet.id, this.petFrame) : null;
    const hasArt = !!petKey && this.textures.exists(petKey);
    if (hasArt) this.petImg?.setTexture(petKey!);
    this.petImg?.setVisible(!!s.pet && hasArt);
    this.pet?.setText(s.pet ? PET_EMOJI[s.pet.id] ?? '' : '').setVisible(!!s.pet && !hasArt);
    this.refreshGarage(s);
    this.life.apply(s);
    if (this.pointer) this.showHover(this.pointer.x, this.pointer.y); // o rótulo do lote muda depois da compra
  }

  /** só o veículo ativo aparece na vaga; viajando, a vaga fica vazia com o contador até a volta.
   *  Visto ao vivo: sai pela estrada (cavalo andando, ou motor com fumaça e poeira) e volta pelo mesmo caminho. */
  private refreshGarage(s: FarmState): void {
    if (!this.veh || !this.vehLabel) return;
    const v = s.vehicles.find((x) => x.active) ?? s.vehicles[0];
    if (!v) { this.veh.setVisible(false); this.vehLabel.setVisible(false); return; }
    const now = store.clock.farmNow();
    const st = vehicleStatus(s, v, now);
    const anyBack = s.expeditions.some((x) => x.status === 'back');
    const parked = st.status === 'idle' || st.status === 'back';
    const V = ANIM.vehicles;
    // carta de Veículo na mão: o veículo aparece com a cara da carta (Carroça, Compacto, Off-Road, 4x4, Caminhão)
    const vc = s.buffs?.find((b) => b.card_id === 'veiculo');
    const look = vc ? vehicleLook(vc.rarity) ?? v.vehicle_id : v.vehicle_id;
    const rar = vc ? vc.rarity : v.rarity;
    const horse = look === 'carroca' && rar === 'common' && this.textures.exists(V.horse_sprite);
    const key = horse ? V.horse_sprite : rar === 'common' && this.anims.exists(`${look}_idle`) ? `${look}_idle` : `vehicle_${look}_${rar}`;
    if (key !== this.vehKey) {
      this.vehKey = key;
      this.vehMotor = look !== 'carroca';
      if (horse) this.veh.stop().setTexture(key, 0);
      else if (key.endsWith('_idle')) this.veh.play(key);
      else if (this.textures.exists(key)) this.veh.stop().setTexture(key);
    }
    const state = parked ? 'parked' : 'away';
    if (this.vehWas && this.vehWas !== state && !this.calm) this.drive(state === 'away');
    else if (!this.vehDrive) this.veh.setVisible(parked);
    this.vehWas = state;
    const text = st.status === 'travel' ? `Volta em ${duration(st.until! - now)}` : st.status === 'refurb' ? `Reforma: ${duration(st.until! - now)}` : anyBack ? 'Receber!' : '';
    this.vehLabel.setText(text).setVisible(!!text);
  }

  /** prédios desenhados no mapa: recorta o contorno da arte e põe por cima do que passa atrás (veículo na estrada) */
  private addOccluders(): void {
    const src = this.textures.get('farm_base_map').getSourceImage() as HTMLImageElement;
    for (const o of (MAP as unknown as { occluders?: { id: string; polygon: Pt[]; depth_y: number }[] }).occluders ?? []) {
      const xs = o.polygon.map((p) => p[0]), ys = o.polygon.map((p) => p[1]);
      const x0 = Math.min(...xs), y0 = Math.min(...ys), w = Math.max(...xs) - x0, h = Math.max(...ys) - y0;
      const key = `occluder_${o.id}`;
      if (!this.textures.exists(key)) {
        const c = document.createElement('canvas');
        c.width = w; c.height = h;
        const g = c.getContext('2d')!;
        g.imageSmoothingEnabled = false;
        g.beginPath();
        o.polygon.forEach((p, i) => (i ? g.lineTo(p[0] - x0, p[1] - y0) : g.moveTo(p[0] - x0, p[1] - y0)));
        g.closePath();
        g.clip();
        g.drawImage(src, x0, y0, w, h, 0, 0, w, h);
        this.textures.addCanvas(key, c);
      }
      this.add.image(x0, y0, key).setOrigin(0, 0).setDepth(depthOf(o.depth_y));
    }
  }

  /** veículo saindo (vaga → fim da estrada) ou chegando (fim da estrada → vaga); some aos poucos na beira da ilha */
  private drive(out: boolean): void {
    const z = ZONES.find((x) => x.id === 'garagem_expedicao') as (typeof ZONES)[number] & { exit_path?: Pt[] };
    if (!this.veh || !z?.exit_path) return;
    const path = out ? z.exit_path : [...z.exit_path].reverse();
    const lens = path.slice(1).map((p, i) => Math.hypot(p[0] - path[i][0], p[1] - path[i][1]));
    const total = lens.reduce((a, b) => a + b, 0);
    this.vehDrive?.tween.stop();
    const obj = { t: 0 };
    this.veh.setVisible(true).setPosition(path[0][0], path[0][1]);
    if (this.vehKey === ANIM.vehicles.horse_sprite) this.veh.play('horse_walk', true);
    const tween = this.tweens.add({ targets: obj, t: 1, duration: ANIM.vehicles.drive_ms, ease: out ? 'Sine.In' : 'Sine.Out',
      onUpdate: () => {
        let d = obj.t * total, k = 0;
        while (k < lens.length - 1 && d > lens[k]) { d -= lens[k]; k++; }
        const a = path[k], b = path[k + 1], f = lens[k] ? Math.min(1, d / lens[k]) : 1;
        const x = Math.round(a[0] + (b[0] - a[0]) * f), y = Math.round(a[1] + (b[1] - a[1]) * f);
        // perto da beira some aos poucos (não entra na faixa escura fora da ilha)
        const p = out ? obj.t : 1 - obj.t, f0 = ANIM.vehicles.edge_fade_from;
        this.veh!.setPosition(x, y).setDepth(depthOf(y)).setFlipX(b[0] > a[0]).setAlpha(p <= f0 ? 1 : Math.max(0, 1 - (p - f0) / (1 - f0))); // a arte olha para a esquerda
      },
      onComplete: () => {
        this.vehDrive = null;
        const anchor = z.parked_vehicle_anchor!;
        this.veh!.setFlipX(false).setAlpha(1).setPosition(anchor[0], anchor[1]).setDepth(depthOf(anchor[1])).setVisible(!out);
        if (this.vehKey === ANIM.vehicles.horse_sprite) this.veh!.stop().setFrame(0);
        else if (this.vehKey.endsWith('_idle')) this.veh!.play(this.vehKey);
      } });
    this.vehDrive = { tween, moving: true };
  }

  /** motor: balança 1 px e solta fumaça; andando: poeira nas rodas (pedacinhos de 2×2 que sobem e somem) */
  private vehicleFx(time: number): void {
    if (!this.veh?.visible || this.calm) return;
    const V = ANIM.vehicles, anchor = (ZONES.find((x) => x.id === 'garagem_expedicao')?.parked_vehicle_anchor ?? [0, 0]) as Pt;
    const baseY = this.vehDrive ? this.veh.y : anchor[1];
    if (this.vehMotor) {
      const up = Math.floor(time / V.motor_bob_ms) % 2;
      if (!this.vehDrive) this.veh.setY(baseY - up);
      if (time - this.fxAt > V.exhaust_every_ms) {
        this.fxAt = time;
        const back = this.veh.flipX ? -1 : 1; // escapamento atrás (a arte olha para a esquerda)
        this.puff(this.veh.x + back * this.veh.displayWidth * 0.45, this.veh.y - 10, V.exhaust_color, V.exhaust_ms, -10);
      }
    }
    if (this.vehDrive && time - this.dustAt > V.dust_every_ms) {
      this.dustAt = time;
      this.puff(this.veh.x + (Math.random() - 0.5) * this.veh.displayWidth * 0.6, this.veh.y - 1, V.dust_color, V.dust_ms, -5);
    }
  }

  private puff(x: number, y: number, hex: string, ms: number, rise: number): void {
    const c = Phaser.Display.Color.HexStringToColor(hex).color;
    const r = this.add.rectangle(Math.round(x), Math.round(y), 2, 2, c, 0.8).setDepth(depthOf(y) + 0.0001);
    this.tweens.add({ targets: r, y: Math.round(y + rise), x: Math.round(x + (Math.random() - 0.5) * 6), alpha: 0, scale: 2, duration: ms, onComplete: () => r.destroy() });
  }

  /** lavoura bloqueada: a terra do canteiro escurecida (a borda de pedra fica; a placa fica por cima) */
  private lockedOverlay(lot: Lot): Phaser.GameObjects.Graphics {
    const L = ANIM.locked_overlay;
    return this.add.graphics().fillStyle(Phaser.Display.Color.HexStringToColor(L.shade_hex).color, L.shade_alpha)
      .fillPoints(((lot as Lot & { soil_polygon?: Pt[] }).soil_polygon ?? lot.polygon).map(([x, y]) => new Phaser.Math.Vector2(x, y)), true).setDepth(0.5).setVisible(false);
  }

  /** limpeza terminou: o escuro some aos poucos e solta pedacinhos de terra e folha */
  private clearFx(d: LotDecor): void {
    const o = d.overlay!, L = ANIM.locked_overlay;
    this.tweens.add({ targets: o, alpha: 0, duration: L.fade_ms, onComplete: () => o.setVisible(false).setAlpha(1) });
    for (let k = 0; k < L.particles; k++) {
      const c = Phaser.Display.Color.HexStringToColor(L.particle_colors[k % L.particle_colors.length]).color;
      const x = d.lot.center[0] + (Math.random() - 0.5) * d.overlayW * 0.8, y = d.lot.center[1] + (Math.random() - 0.5) * d.overlayW * 0.3;
      const r = this.add.rectangle(Math.round(x), Math.round(y), 2, 2, c, 1).setDepth(depthOf(y) + 0.001);
      this.tweens.add({ targets: r, x: Math.round(x + (Math.random() - 0.5) * 30), y: Math.round(y - 10 - Math.random() * 18), alpha: 0,
        duration: L.particle_ms, delay: Math.random() * 150, ease: 'Quad.Out', onComplete: () => r.destroy() });
    }
  }

  /** placa só nos lotes à venda; entulho até o fim da limpeza; prédio do pasto depois dela */
  private refreshDecor(): void {
    const now = store.clock.farmNow();
    for (const d of this.decor) {
      const mine = this.owned.has(d.lot.id);
      const end = this.cleaning.get(d.lot.id);
      const inCleanup = end !== undefined && end > now;
      // à venda: placa com cadeado; pomar comprado: placa com árvore (sinaliza o pomar)
      if (d.sign) {
        const tree = mine && d.lot.type === 'pomar';
        d.sign.setTexture(tree ? 'lot_sign_tree' : 'lot_sign_lock').setVisible(!mine || (tree && !inCleanup));
      }
      if (d.overlay) {
        const on = !mine || inCleanup;
        if (on !== d.overlayOn) {
          // ficou pronto agora (com o jogo aberto): o mato some com partículas
          if (!on && d.overlayOn && mine && !this.calm) this.clearFx(d);
          else d.overlay.setVisible(on).setAlpha(1);
          d.overlayOn = on;
        }
      }
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

  update(time: number, delta: number): void {
    this.publishMapRect();
    const s = store.state;
    if (!s) return;
    this.life.update(time, delta);
    this.vehicleFx(time);
    const now = store.clock.farmNow();
    const t = time / 1000;
    const second = Math.floor(t);
    if (second !== this.lastSecond) { this.lastSecond = second; this.refreshDecor(); this.updateTrees(s, now); this.refreshGarage(s); }
    this.updateGrains(time);
    this.wx.update(time, s.weather, store.clock.serverNow());
    const cam = this.cameras.main; // canto do mapa no canvas, para a interface
    mapView.x = cam.x - cam.worldView.x * cam.zoom; mapView.y = cam.y - cam.worldView.y * cam.zoom; mapView.gameWidth = this.scale.width;
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
      const ready = this.owned.has(v.lot) && !this.cleaning.has(v.lot);
      const look = ready ? orchardLook(tr, now, true) : 'empty';
      const key = `${look}:${tr?.fruit_id ?? ''}`;
      if (key === v.look) continue;
      const O = ANIM.orchard.sprites;
      const tex = look === 'pit' ? '' : look === 'sprout' ? O.sprout : look === 'young' ? O.young
        : look === 'adult' ? 'orchard_adult_leaf' : look === 'fruit' ? `orchard_adult_${tr!.fruit_id}` : '';
      v.tree.setVisible(!!tex && this.textures.exists(tex));
      if (tex && this.textures.exists(tex)) v.tree.setTexture(tex);
      if (v.look !== '' && look !== 'empty' && look !== 'pit' && !this.calm) { // pulinho quando a árvore muda
        v.tree.setScale(1, 0.85);
        this.tweens.add({ targets: v.tree, scaleY: 1, duration: 260, ease: 'Back.Out' });
      }
      v.look = key;
    }
  }

  /** onde a arte do mapa está na tela (a mão e os buffs ficam dentro dela, nunca na faixa de fora) */
  private mapRect = '';
  private publishMapRect(): void {
    const cam = this.cameras.main, { width, height } = this.scale.gameSize, v = cam.worldView, z = cam.zoom;
    const l = Math.max(0, Math.round(-v.x * z)), t = Math.max(0, Math.round(-v.y * z));
    const r = Math.max(0, Math.round(width - (MAP_W - v.x) * z)), b = Math.max(0, Math.round(height - (MAP_H - v.y) * z));
    const k = `${l},${t},${r},${b}`;
    if (k === this.mapRect) return;
    this.mapRect = k;
    const st = document.documentElement.style;
    st.setProperty('--map-l', `${l}px`); st.setProperty('--map-t', `${t}px`); st.setProperty('--map-r', `${r}px`); st.setProperty('--map-b', `${b}px`);
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
      // pasto com prédio no mapa: só o prédio é clicável (o gramado não)
      const r = lot.building_hit_rect;
      if (r) {
        if (x < r[0] || x > r[2] || y < r[1] || y > r[3]) continue;
        if (!this.owned.has(lot.id)) return { kind: 'locked', id: lot.id, rect: r };
        return { kind: 'pasture', id: lot.id, rect: r };
      }
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
      if (store.visit) return 'Pet';
      const mine = s.pets.find((p) => p.active);
      return mine && mine.last_care !== s.game_day ? 'Pet · clique para o carinho de hoje' : 'Pet';
    }
    const now = store.clock.farmNow();
    const lotId = hit.kind === 'plot' ? hit.id.split('-')[0] : hit.id;
    if (store.visit) {
      // visitando: o que importa é se dá para ajudar o lote
      if (hit.kind === 'locked') return `${LOT_TYPE_NAMES[LOTS.find((l) => l.id === lotId)!.type]} ${lotId} · ainda não é da fazenda`;
      const cd = store.visit.cooldowns[lotId];
      const help = (s.helps ?? []).find((h) => h.lot_id === lotId);
      const base = `${LOT_TYPE_NAMES[LOTS.find((l) => l.id === lotId)!.type]} ${lotId}`;
      if (help) return `${base} · ajudado por ${help.from} (+${help.pct}%)`;
      if (cd && Date.parse(cd) > Date.now()) return `${base} · ajudado há pouco`;
      return `${base} · clique para ajudar`;
    }
    const helped = (s.social?.helps ?? []).find((h) => h.lot_id === lotId && Date.parse(h.ends_at) > Date.now());
    const helpTxt = helped ? ` · ajuda de ${helped.from} (+${helped.pct}%)` : '';
    if (hit.kind === 'plot') {
      const p = s.plots.find((x) => x.plot_id === hit.id);
      if (!p) return `Canteiro ${hit.id}`;
      const name = (id: string | null) => (id ? CROPS[id].name_pt : '');
      switch (plotLook(p, now, s.lots.find((l) => l.lot_id === hit.id.split('-')[0])?.ready_at ?? 0)) {
        case 'ready': return `${name(p.planted_crop_id)} pronta · clique para colher`;
        case 'growing': return `${name(p.planted_crop_id)} · pronta em ${duration(p.ready_at! - now)}${helpTxt}`;
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
    if (!ANIM.map_marks.hover_outline) { this.label.setText(this.hoverText(hit)).setPosition(Math.round(x + 10), Math.round(y - 22)).setVisible(true); return; }
    this.hover.lineStyle(1, hit.kind === 'locked' ? 0x9e9e9e : 0xf2c230, 1);
    if (hit.poly) this.hover.strokePoints(hit.poly.map(([px, py]) => new Phaser.Math.Vector2(px, py)), true, true);
    if (hit.rect) this.hover.strokeRect(hit.rect[0], hit.rect[1], hit.rect[2] - hit.rect[0], hit.rect[3] - hit.rect[1]);
    this.label.setText(this.hoverText(hit)).setPosition(Math.round(x + 10), Math.round(y - 22)).setVisible(true);
  }
}
