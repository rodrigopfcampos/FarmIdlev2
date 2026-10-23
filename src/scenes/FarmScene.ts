// Mapa vivo da fazenda: fundo em escala inteira, lotes que ainda não são seus escurecidos,
// 6 mudas por canteiro com vento e pulinho na troca de estágio, as 4 zonas clicáveis e a Carroça parada.
import Phaser from 'phaser';
import { bus } from '../core/bus';
import { FARM, LOTS, ZONES, type Pt } from '../data';
import { stageSprite } from '../farm/art';
import { pointInPolygon, seedlingPositions, stageFor, windOffset } from '../farm/geometry';
import { store } from '../farm/store';
import type { FarmState } from '../net/farmApi';

const MAP_W = 1672;
const MAP_H = 940;
const ZONE_NAMES: Record<string, string> = {
  casa_principal: 'Casa', oficina_ferreiro: 'Forja', barraca_comerciante: 'Barraca', garagem_expedicao: 'Garagem',
};

type PlotView = { id: string; polygon: Pt[]; sprites: Phaser.GameObjects.Image[]; base: Pt[]; stage: number; crop: string | null };

export class FarmScene extends Phaser.Scene {
  private plots: PlotView[] = [];
  private shade!: Phaser.GameObjects.Graphics;
  private hover!: Phaser.GameObjects.Graphics;
  private label!: Phaser.GameObjects.Text;
  private downAt: { x: number; y: number } | null = null;
  private owned = new Set<string>();

  constructor() { super('farm'); }

  create(): void {
    this.add.image(0, 0, 'farm_base_map').setOrigin(0, 0);
    this.shade = this.add.graphics();
    this.hover = this.add.graphics().setDepth(5);
    this.label = this.add.text(0, 0, '', { fontFamily: 'system-ui, sans-serif', fontSize: '12px', color: '#f3e3c3', backgroundColor: '#000000aa', padding: { x: 4, y: 2 } })
      .setDepth(20).setVisible(false).setResolution(2);

    // canteiros de todas as lavouras (as mudas só aparecem nos lotes que são seus)
    for (const lot of LOTS) for (const p of lot.plots ?? []) {
      const base = seedlingPositions(p.polygon);
      const sprites = base.map(([x, y]) => this.add.image(x, y, 'crop_generic_stage1').setOrigin(0.5, 1).setVisible(false).setDepth(1 + y / 10000));
      this.plots.push({ id: p.id, polygon: p.polygon, sprites, base, stage: -1, crop: null });
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

  private applyState(s: FarmState): void {
    this.owned = new Set(s.lots);
    // lotes que ainda não são seus ficam escurecidos
    this.shade.clear().fillStyle(0x140c08, 0.5);
    for (const lot of LOTS) if (!this.owned.has(lot.id)) this.shade.fillPoints(lot.polygon.map(([x, y]) => new Phaser.Math.Vector2(x, y)), true);
  }

  update(time: number): void {
    const s = store.state;
    if (!s) return;
    const now = store.clock.farmNow();
    const t = time / 1000;
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

  // ---------- clique: zonas e canteiros; arrastar não conta como clique ----------
  private setupInput(): void {
    const cam = this.cameras.main;
    this.input.on('pointerdown', (p: Phaser.Input.Pointer) => { this.downAt = { x: p.x, y: p.y }; });
    this.input.on('pointermove', (p: Phaser.Input.Pointer) => {
      if (p.isDown) {
        cam.scrollX -= (p.x - p.prevPosition.x) / cam.zoom;
        cam.scrollY -= (p.y - p.prevPosition.y) / cam.zoom;
      }
      this.showHover(p.worldX, p.worldY);
    });
    this.input.on('pointerup', (p: Phaser.Input.Pointer) => {
      if (!this.downAt || Math.hypot(p.x - this.downAt.x, p.y - this.downAt.y) > 6) { this.downAt = null; return; }
      this.downAt = null;
      const hit = this.hitTest(p.worldX, p.worldY);
      if (hit?.kind === 'zone') bus.emit('ui:zone', hit.id);
      if (hit?.kind === 'plot') bus.emit('ui:plot', hit.id);
      if (hit?.kind === 'locked') bus.emit('ui:locked', hit.id);
    });
  }

  private hitTest(x: number, y: number): { kind: 'zone' | 'plot' | 'locked'; id: string; poly?: Pt[]; rect?: number[] } | null {
    for (const z of ZONES) for (const r of z.hit_rects) if (x >= r[0] && x <= r[2] && y >= r[1] && y <= r[3]) return { kind: 'zone', id: z.id, rect: r };
    for (const v of this.plots) {
      const lot = v.id.split('-')[0];
      if (this.owned.has(lot) && pointInPolygon(x, y, v.polygon)) return { kind: 'plot', id: v.id, poly: v.polygon };
    }
    for (const lot of LOTS) if (!this.owned.has(lot.id) && pointInPolygon(x, y, lot.polygon)) return { kind: 'locked', id: lot.id, poly: lot.polygon };
    return null;
  }

  private showHover(x: number, y: number): void {
    const hit = this.hitTest(x, y);
    this.hover.clear();
    this.input.setDefaultCursor(hit && hit.kind !== 'locked' ? 'pointer' : 'default');
    if (!hit) { this.label.setVisible(false); return; }
    this.hover.lineStyle(1, hit.kind === 'locked' ? 0x9e9e9e : 0xf2c230, 1);
    if (hit.poly) this.hover.strokePoints(hit.poly.map(([px, py]) => new Phaser.Math.Vector2(px, py)), true, true);
    if (hit.rect) this.hover.strokeRect(hit.rect[0], hit.rect[1], hit.rect[2] - hit.rect[0], hit.rect[3] - hit.rect[1]);
    const text = hit.kind === 'zone' ? ZONE_NAMES[hit.id] : hit.kind === 'plot' ? `Canteiro ${hit.id}` : `Lote ${hit.id} (fase 2)`;
    this.label.setText(text).setPosition(Math.round(x + 10), Math.round(y - 22)).setVisible(true);
  }
}
