// Vida no mapa v3: animais andando nos pastos (parado 4 FPS, andando 6 FPS, espelha para a direita, ordem pelo Y)
// e peixes nadando no Lago em curva (seno), meio transparentes, com anel na água quando viram. Só visual.
import Phaser from 'phaser';
import { ANIM, LOTS, type Lot, type Pt } from '../data';
import { clearPath, fishCount, randomFreePoint, unlockedFish, walkSpriteFor, type Rect } from '../farm/life';
import type { FarmState } from '../net/farmApi';

const W = ANIM.animals_wander, F = ANIM.lake_fish;
const depthOf = (y: number) => 1 + y / 10000;
type Area = { poly: Pt[]; avoid: Rect[] };
type Walker = { spr: Phaser.GameObjects.Sprite; key: string; area: Area; at: Pt; to: Pt | null; speed: number; until: number; frame0: number };
type Fish = { img: Phaser.GameObjects.Image; at: Pt; to: Pt; speed: number; phase: number; dir: number; right: boolean };

const rnd = () => Math.random();
const between = ([a, b]: number[]) => a + rnd() * (b - a);

export class LifeLayer {
  private walkers = new Map<string, Walker[]>(); // lote do pasto → animais visíveis
  private fish: Fish[] = [];
  private fishKey = '';
  private ripples!: Phaser.GameObjects.Graphics;
  private rings: { x: number; y: number; born: number }[] = [];
  private lake = LOTS.find((l) => l.type === 'pasto_lago') as (Lot & { water?: { polygon: Pt[]; margin_px: number; avoid: Rect[] } }) | undefined;

  constructor(private scene: Phaser.Scene, private calm: boolean) {
    for (const k of ['cow', 'chicken', 'duck', 'rabbit']) {
      const tex = `animal_walk_${k}`;
      if (!scene.textures.exists(tex)) continue;
      scene.anims.create({ key: `${tex}_walk`, frames: scene.anims.generateFrameNumbers(tex, { frames: W.walk_frames }), frameRate: W.walk_fps, repeat: -1 });
      scene.anims.create({ key: `${tex}_idle`, frames: scene.anims.generateFrameNumbers(tex, { frames: W.idle_frames }), frameRate: W.idle_fps, repeat: -1 });
    }
    this.ripples = scene.add.graphics().setDepth(depthOf(this.lake?.center[1] ?? 0) - 0.001);
  }

  /** quantos e quais animais aparecem em cada pasto (até o máximo por pasto) */
  apply(s: FarmState): void {
    for (const lot of LOTS) {
      const area = (lot as Lot & { wander?: { polygon: Pt[]; avoid: Rect[] } }).wander;
      if (!area) continue;
      const house = Object.entries(s.houses).find(([, h]) => h.lot === lot.id)?.[0];
      const ids = house ? s.animals.filter((a) => a.house_id === house).map((a) => a.animal_id).slice(0, W.max_per_pasture) : [];
      const want = ids.map(walkSpriteFor).filter((k) => this.scene.textures.exists(k));
      const have = this.walkers.get(lot.id) ?? [];
      if (have.map((w) => w.key).join() === want.join()) continue;
      have.forEach((w) => w.spr.destroy());
      this.walkers.set(lot.id, want.map((key) => this.makeWalker(key, { poly: area.polygon, avoid: area.avoid })));
    }
    this.applyFish(s);
  }

  private makeWalker(key: string, area: Area): Walker {
    const at = randomFreePoint(area.poly, area.avoid, rnd, W.edge_margin_px);
    const kind = key.replace('animal_walk_', '') as keyof typeof W.speed_px_s;
    // tamanho de cada bicho em relação à vaca (galinha, pato e coelho bem menores)
    const size = W.scale * ((W.scale_by_sprite as Record<string, number>)[kind] ?? 1);
    const spr = this.scene.add.sprite(at[0], at[1], key, 0).setOrigin(0.5, 1).setScale(size).setDepth(depthOf(at[1]));
    if (!this.calm) spr.play({ key: `${key}_idle`, startFrame: Math.floor(rnd() * W.idle_frames.length) });
    return { spr, key, area, at, to: null, speed: W.speed_px_s[kind] ?? 12, until: performance.now() + between(W.idle_ms), frame0: 0 };
  }

  private applyFish(s: FarmState): void {
    const water = this.lake?.water;
    const kinds = s.lake && water ? unlockedFish(s.level) : [];
    const key = `${kinds.join()}:${kinds.length ? fishCount(s.level) : 0}`;
    if (key === this.fishKey) return;
    this.fishKey = key;
    this.fish.forEach((f) => f.img.destroy());
    this.fish = [];
    if (!kinds.length || !water) return;
    const n = fishCount(s.level);
    for (let i = 0; i < n; i++) {
      // espécies novas aparecem menos: a primeira é a mais comum
      const sp = kinds[Math.min(kinds.length - 1, Math.floor(Math.pow(rnd(), 1.6) * kinds.length))];
      if (!this.scene.textures.exists(sp)) continue;
      const at = randomFreePoint(water.polygon, water.avoid, rnd, water.margin_px);
      const img = this.scene.add.image(at[0], at[1], sp).setOrigin(0.5, 0.5).setAlpha(F.alpha).setScale(F.scale).setDepth(depthOf(this.lake!.center[1]));
      const right = F.species.find((x) => x.sprite === sp)?.faces === 'right';
      this.fish.push({ img, at, to: this.nextFishTarget(at), speed: between(F.speed_px_s), phase: rnd() * Math.PI * 2, dir: -1, right });
    }
  }

  private nextFishTarget(from: Pt): Pt {
    const w = this.lake!.water!;
    for (let k = 0; k < 20; k++) {
      const p = randomFreePoint(w.polygon, w.avoid, rnd, w.margin_px);
      if (clearPath(from, p, w.polygon, w.avoid, w.margin_px)) return p;
    }
    return from;
  }

  update(time: number, dt: number): void {
    if (this.calm) return;
    const now = performance.now();
    for (const list of this.walkers.values()) for (const w of list) this.stepWalker(w, now, dt);
    for (const f of this.fish) this.stepFish(f, time, dt);
    // anéis na água: crescem e somem
    this.ripples.clear();
    this.rings = this.rings.filter((r) => {
      const k = (time - r.born) / F.ripple_ms;
      if (k >= 1) return false;
      const rad = F.ripple_radius_px[0] + k * (F.ripple_radius_px[1] - F.ripple_radius_px[0]);
      this.ripples.lineStyle(1, 0xd8f3ff, 0.55 * (1 - k)).strokeEllipse(Math.round(r.x), Math.round(r.y), Math.round(rad * 2), Math.round(rad));
      return true;
    });
  }

  private stepWalker(w: Walker, now: number, dt: number): void {
    if (!w.to) {
      if (now < w.until) return;
      // escolhe um passo curto que não atravesse prédio nem cerca
      for (let k = 0; k < 12 && !w.to; k++) {
        const ang = rnd() * Math.PI * 2, len = between(W.step_px);
        const p: Pt = [Math.round(w.at[0] + Math.cos(ang) * len), Math.round(w.at[1] + Math.sin(ang) * len * 0.5)];
        if (clearPath(w.at, p, w.area.poly, w.area.avoid, W.edge_margin_px)) w.to = p;
      }
      if (!w.to) { w.until = now + between(W.idle_ms); return; }
      w.spr.setFlipX(w.to[0] > w.at[0]); // a arte olha para a esquerda
      w.spr.play(`${w.key}_walk`, true);
      return;
    }
    const dx = w.to[0] - w.at[0], dy = w.to[1] - w.at[1], d = Math.hypot(dx, dy);
    const step = (w.speed * dt) / 1000;
    if (d <= step) {
      w.at = w.to; w.to = null; w.until = now + between(W.idle_ms);
      w.spr.play(`${w.key}_idle`, true);
    } else {
      w.at = [w.at[0] + (dx / d) * step, w.at[1] + (dy / d) * step];
    }
    w.spr.setPosition(Math.round(w.at[0]), Math.round(w.at[1])).setDepth(depthOf(w.at[1]));
  }

  private stepFish(f: Fish, time: number, dt: number): void {
    const dx = f.to[0] - f.at[0], dy = f.to[1] - f.at[1], d = Math.hypot(dx, dy);
    const step = (f.speed * dt) / 1000;
    if (d <= step) {
      f.at = f.to;
      const next = this.nextFishTarget(f.at);
      const turn = Math.sign(next[0] - f.at[0]) || f.dir;
      if (turn !== f.dir) this.rings.push({ x: f.at[0], y: f.at[1], born: time }); // virou: anel na água
      f.dir = turn; f.to = next; f.speed = between(F.speed_px_s);
      return;
    }
    f.at = [f.at[0] + (dx / d) * step, f.at[1] + (dy / d) * step];
    // nado em curva: desvio de lado (perpendicular ao caminho) em seno
    const side = Math.sin(time / 1000 * F.wave_hz * Math.PI * 2 + f.phase) * F.wave_px;
    const nx = -dy / d, ny = dx / d;
    f.img.setPosition(Math.round(f.at[0] + nx * side), Math.round(f.at[1] + ny * side * 0.5)).setFlipX(f.right ? dx < 0 : dx > 0);
  }
}
