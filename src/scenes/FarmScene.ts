// Mapa vivo da fazenda: fundo em escala inteira; lotes que não são seus escurecidos, com placa e entulho;
// lote comprado mostra o entulho e o tempo de limpeza até ficar pronto; 6 mudas por canteiro com vento
// e pulinho na troca de estágio; árvores do pomar (muda, adulta, com fruta); prédio dos pastos; zonas clicáveis.
import Phaser from 'phaser';
import { bus } from '../core/bus';
import { CROPS, FARM, LOT_TYPE_NAMES, LOTS, ZONES, type Lot, type Pt } from '../data';
import { stageSprite } from '../farm/art';
import { pointInPolygon, seedlingPositions, stageFor, windOffset } from '../farm/geometry';
import { lotOffer, treeLook } from '../farm/rules';
import { store } from '../farm/store';
import type { FarmState } from '../net/farmApi';
import { duration, formatGold } from '../ui/format';

const MAP_W = 1672;
const MAP_H = 940;
const ZONE_NAMES: Record<string, string> = {
  casa_principal: 'Casa', oficina_ferreiro: 'Forja', barraca_comerciante: 'Barraca', garagem_expedicao: 'Garagem',
};
const depthOf = (y: number) => 1 + y / 10000;

type PlotView = { id: string; polygon: Pt[]; sprites: Phaser.GameObjects.Image[]; base: Pt[]; stage: number; crop: string | null };
type TreeView = { lot: string; slot: number; tree: Phaser.GameObjects.Image; fruit: Phaser.GameObjects.Image; look: string };
type LotDecor = { lot: Lot; sign?: Phaser.GameObjects.Image; debris: Phaser.GameObjects.Image[]; timer: Phaser.GameObjects.Text; building?: Phaser.GameObjects.Image };
type Hit = { kind: 'zone' | 'plot' | 'locked' | 'orchard' | 'pasture'; id: string; poly?: Pt[]; rect?: number[] };

export class FarmScene extends Phaser.Scene {
  private plots: PlotView[] = [];
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

  constructor() { super('farm'); }

  create(): void {
    this.add.image(0, 0, 'farm_base_map').setOrigin(0, 0);
    this.shade = this.add.graphics().setDepth(0.5);
    this.hover = this.add.graphics().setDepth(5);
    this.label = this.text().setDepth(20).setVisible(false);

    for (const lot of LOTS) {
      // canteiros de todas as lavouras (as mudas só aparecem nos lotes que são seus)
      for (const p of lot.plots ?? []) {
        const base = seedlingPositions(p.polygon);
        const sprites = base.map(([x, y]) => this.add.image(x, y, 'crop_generic_stage1').setOrigin(0.5, 1).setVisible(false).setDepth(depthOf(y)));
        this.plots.push({ id: p.id, polygon: p.polygon, sprites, base, stage: -1, crop: null });
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
      this.decor.push({ lot, sign, debris, timer, building });
    }

    // Carroça parada na vaga da Garagem, com a animação de parado
    const garage = ZONES.find((z) => z.id === 'garagem_expedicao');
    if (garage?.parked_vehicle_anchor) {
      this.anims.create({ key: 'carroca_idle', frames: this.anims.generateFrameNumbers('vehicle_carroca_idle', { start: 0, end: 3 }), frameRate: FARM.visual.vehicle_idle_fps, repeat: -1 });
      const [x, y] = garage.parked_vehicle_anchor;
      this.add.sprite(x, y, 'vehicle_carroca_idle').setOrigin(0.5, 1).setDepth(2).play('carroca_idle');
    }

    this.setupCamera();
    this.setupInput();
    bus.on('farm:state', (s: FarmState) => this.applyState(s));
    if (store.state) this.applyState(store.state);
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
    if (this.pointer) this.showHover(this.pointer.x, this.pointer.y); // o rótulo do lote muda depois da compra
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
    }
  }

  update(time: number): void {
    const s = store.state;
    if (!s) return;
    const now = store.clock.farmNow();
    const t = time / 1000;
    const second = Math.floor(t);
    if (second !== this.lastSecond) { this.lastSecond = second; this.refreshDecor(); this.updateTrees(s, now); }
    const byId = new Map(s.plots.map((p) => [p.plot_id, p]));
    for (const v of this.plots) {
      const p = byId.get(v.id);
      if (!p || p.state !== 'growing' || p.planted_at === null || p.ready_at === null) {
        if (v.stage !== -1) { v.sprites.forEach((sp) => sp.setVisible(false)); v.stage = -1; }
        continue;
      }
      const progress = (now - p.planted_at) / (p.ready_at - p.planted_at);
      const stage = stageFor(progress, FARM.visual.stage_thresholds);
      if (stage !== v.stage || p.planted_crop_id !== v.crop) {
        const key = stageSprite(store.manifest, p.planted_crop_id!, stage);
        v.sprites.forEach((sp, i) => {
          sp.setTexture(key).setVisible(true);
          if (v.stage !== -1) { // pulinho em sequência quando muda de estágio
            sp.setScale(1, 0.7);
            this.tweens.add({ targets: sp, scaleY: 1, duration: 220, delay: 80 + i * 32, ease: 'Back.Out' });
          }
        });
        v.stage = stage; v.crop = p.planted_crop_id;
      }
      // vento: onda da esquerda para a direita, em pixels inteiros
      v.sprites.forEach((sp, i) => sp.setX(v.base[i][0] + windOffset(t, v.base[i][0], FARM.visual.wind_speed, FARM.visual.wind_strength_px)));
    }
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

  // ---------- câmera: zoom inteiro e arrastar quando o mapa não cabe ----------
  private setupCamera(): void {
    const fit = () => {
      const { width, height } = this.scale.gameSize;
      const zoom = Math.max(1, Math.floor(Math.min(width / MAP_W, height / MAP_H)));
      const cam = this.cameras.main.setZoom(zoom).setRoundPixels(true);
      if (MAP_W * zoom <= width && MAP_H * zoom <= height) cam.removeBounds(); else cam.setBounds(0, 0, MAP_W, MAP_H);
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
    if (hit.kind === 'zone') return ZONE_NAMES[hit.id];
    if (hit.kind === 'plot') return `Canteiro ${hit.id}`;
    const s = store.state!;
    const type = LOT_TYPE_NAMES[LOTS.find((l) => l.id === hit.id)!.type];
    if (hit.kind !== 'locked') return `${type} ${hit.id}`;
    const o = lotOffer(hit.id, this.owned, s.level, s.inventory.deed ?? 0, s.gold);
    if (!o || o.problems.includes('fim')) return `${type} ${hit.id}`;
    if (!o.neighbor) return `${type} ${hit.id} · precisa de um lote vizinho`;
    return `${type} ${hit.id} · ${formatGold(o.cost)} ouro · nível ${o.needLevel}${o.needsDeed ? ' · 1 Escritura' : ''}`;
  }

  private showHover(x: number, y: number): void {
    const hit = this.hitTest(x, y);
    this.hover.clear();
    this.input.setDefaultCursor(hit ? 'pointer' : 'default');
    if (!hit || !store.state) { this.label.setVisible(false); return; }
    this.hover.lineStyle(1, hit.kind === 'locked' ? 0x9e9e9e : 0xf2c230, 1);
    if (hit.poly) this.hover.strokePoints(hit.poly.map(([px, py]) => new Phaser.Math.Vector2(px, py)), true, true);
    if (hit.rect) this.hover.strokeRect(hit.rect[0], hit.rect[1], hit.rect[2] - hit.rect[0], hit.rect[3] - hit.rect[1]);
    this.label.setText(this.hoverText(hit)).setPosition(Math.round(x + 10), Math.round(y - 22)).setVisible(true);
  }
}
