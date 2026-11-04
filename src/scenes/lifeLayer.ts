// Vida no mapa v3: animais andando nos pastos (parado num quadro fixo, andando 6 FPS, passo quase de lado para nunca
// andar de costas, espelha para a direita, cada um com seu espaço para não se amontoar, ordem pelo Y)
// e o Lago com sombras de peixe submersas (rumo que gira suave), ondulações na superfície e o "beliscão" quando a rede
// tem peixe para recolher (a sombra para, pisca e solta 3 anéis). Só visual.
import Phaser from 'phaser';
import { ANIM, LOTS, type Lot, type Pt } from '../data';
import { clearPath, fishCount, randomFreePoint, unlockedFish, walkSpriteFor, type Rect } from '../farm/life';
import type { FarmState } from '../net/farmApi';
import { fishCycles } from '../farm/rules';
import { store } from '../farm/store';

const W = ANIM.animals_wander, F = ANIM.lake_fish;
const depthOf = (y: number) => 1 + y / 10000;
type Area = { poly: Pt[]; avoid: Rect[] };
type Walker = { spr: Phaser.GameObjects.Sprite; key: string; area: Area; at: Pt; to: Pt | null; speed: number; until: number; r: number; mates: Walker[] };
type Fish = { at: Pt; to: Pt; ang: number; speed: number; len: number; nextRipple: number; blink: number };

const rnd = () => Math.random();

/** o ponto p invade o espaço de algum outro bicho? (elipse: um pouco mais larga que alta; o bicho de trás
 *  precisa ficar bem mais acima para não sumir atrás do da frente, porque a arte é alta)
 *  aheadOnly: só conta quem está na frente do movimento, para quem já está perto conseguir se afastar */
function crowded(p: Pt, r: number, mates: Walker[], self: Walker | null, aheadOnly = false): boolean {
  for (const o of mates) {
    if (o === self) continue;
    const gap = r + o.r;
    for (const q of o.to ? [o.at, o.to] : [o.at]) {
      const dx = p[0] - q[0], dy = (p[1] - q[1]) * W.personal_space_dy_weight;
      if (dx * dx + dy * dy >= gap * gap) continue;
      if (!aheadOnly || !self) return true;
      // anda para longe de q? então deixa
      const mx = p[0] - self.at[0], my = p[1] - self.at[1];
      if (mx * (q[0] - self.at[0]) + my * (q[1] - self.at[1]) > 0) return true;
    }
  }
  return false;
}

/** o caminho de a até b passa por dentro do espaço de outro bicho? */
function pathCrowded(a: Pt, b: Pt, self: Walker): boolean {
  for (let t = 0.25; t < 1; t += 0.25) if (crowded([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t], self.r, self.mates, self)) return true;
  return false;
}
const between = ([a, b]: number[]) => a + rnd() * (b - a);

export class LifeLayer {
  private walkers = new Map<string, Walker[]>(); // lote do pasto → animais visíveis
  private fish: Fish[] = [];
  private fishKey = '';
  private ripples!: Phaser.GameObjects.Graphics;
  private shadows!: Phaser.GameObjects.Graphics;
  private rings: { x: number; y: number; born: number; ms: number; r: number[]; a: number }[] = [];
  private nextBite = 0;
  private lake = LOTS.find((l) => l.type === 'pasto_lago') as (Lot & { water?: { polygon: Pt[]; margin_px: number; avoid: Rect[] } }) | undefined;

  constructor(private scene: Phaser.Scene, private calm: boolean) {
    for (const k of new Set(Object.values(W.sprite_by_animal))) {
      const tex = `animal_walk_${k}`;
      if (!scene.textures.exists(tex)) continue;
      scene.anims.create({ key: `${tex}_walk`, frames: scene.anims.generateFrameNumbers(tex, { frames: W.walk_frames }), frameRate: W.walk_fps, repeat: -1 });
    }
    // sombras embaixo, anéis por cima da água (os dois abaixo do píer e das margens desenhadas no fundo)
    this.shadows = scene.add.graphics().setDepth(depthOf(this.lake?.center[1] ?? 0) - 0.002);
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
      // um de cada vez: cada novo bicho nasce fora do espaço dos que já estão no pasto
      const list: Walker[] = [];
      for (const key of want) this.makeWalker(key, { poly: area.polygon, avoid: area.avoid }, list);
      this.walkers.set(lot.id, list);
    }
    this.applyFish(s);
  }

  private makeWalker(key: string, area: Area, mates: Walker[]): Walker {
    const kind = key.replace('animal_walk_', '') as keyof typeof W.speed_px_s;
    // tamanho de cada bicho em relação à vaca (galinha, pato e coelho bem menores)
    const size = W.scale * ((W.scale_by_sprite as Record<string, number>)[kind] ?? 1);
    const r = W.personal_space_px * size;
    let at = randomFreePoint(area.poly, area.avoid, rnd, W.edge_margin_px);
    for (let k = 0; k < 40 && crowded(at, r, mates, null); k++) at = randomFreePoint(area.poly, area.avoid, rnd, W.edge_margin_px);
    const spr = this.scene.add.sprite(at[0], at[1], key, W.idle_frame).setOrigin(0.5, 1).setScale(size).setDepth(depthOf(at[1]))
      .setFlipX(rnd() < 0.5);
    const w: Walker = { spr, key, area, at, to: null, speed: W.speed_px_s[kind] ?? 12, until: performance.now() + between(W.idle_ms), r, mates };
    mates.push(w);
    return w;
  }

  private applyFish(s: FarmState): void {
    const water = this.lake?.water;
    const n = s.lake && water ? fishCount(s.level) : 0;
    const key = String(n);
    if (key === this.fishKey) return;
    this.fishKey = key;
    this.fish = [];
    if (!n || !water) { this.shadows.clear(); return; }
    const now = performance.now();
    for (let i = 0; i < n; i++) {
      const at = randomFreePoint(water.polygon, water.avoid, rnd, water.margin_px);
      this.fish.push({ at, to: this.nextFishTarget(at), ang: rnd() * Math.PI * 2, speed: between(F.speed_px_s), len: between(F.shadow_len_px),
        nextRipple: now + between(F.ripple_every_ms), blink: rnd() * Math.PI * 2 });
    }
    if (this.calm) this.drawShadows(now, false);
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
    // rede com peixe: a 1ª sombra para e pisca; de tempos em tempos, beliscão (3 anéis)
    const f = store.state?.fishing;
    const bite = !!f && !store.visit && fishCycles(f.fish_t, store.clock.farmNow()) > 0 && this.fish.length > 0;
    this.fish.forEach((x, i) => this.stepFish(x, now, dt, bite && i === 0));
    if (bite && now >= this.nextBite) {
      const b = this.fish[0];
      for (let k = 0; k < F.bite_rings; k++) this.rings.push({ x: b.at[0], y: b.at[1], born: now + k * F.bite_ring_gap_ms, ms: F.bite_ring_ms, r: F.bite_ring_radius_px, a: F.ripple_alpha });
      this.nextBite = now + F.bite_every_ms;
    }
    this.drawShadows(now, bite);
    // anéis na água: o raio cresce e a opacidade some
    this.ripples.clear();
    const col = Phaser.Display.Color.HexStringToColor(F.ripple_hex).color;
    this.rings = this.rings.filter((r) => {
      const k = (now - r.born) / r.ms;
      if (k >= 1) return false;
      if (k < 0) return true;
      const rad = r.r[0] + k * (r.r[1] - r.r[0]);
      this.ripples.lineStyle(1, col, r.a * (1 - k)).strokeEllipse(Math.round(r.x), Math.round(r.y), Math.round(rad * 2), Math.round(rad));
      return true;
    });
  }

  /** sombra em gota (corpo + rabo) virada para o rumo; um halo mais claro e maior faz o "desfoque" da água turva */
  private drawShadows(now: number, bite: boolean): void {
    const g = this.shadows, col = Phaser.Display.Color.HexStringToColor(F.shadow_hex).color;
    g.clear();
    this.fish.forEach((x, i) => {
      const blink = bite && i === 0 ? F.bite_alpha[0] + (F.bite_alpha[1] - F.bite_alpha[0]) * (0.5 + 0.5 * Math.sin(now / 1000 * F.bite_blink_hz * Math.PI * 2)) : F.shadow_alpha;
      const c = Math.cos(x.ang), sn = Math.sin(x.ang) * 0.5; // chão isométrico: o eixo y achata pela metade
      const L = x.len, Wd = x.len * F.shadow_width_ratio;
      const pt = (fwd: number, side: number) => new Phaser.Math.Vector2(x.at[0] + c * fwd - Math.sin(x.ang) * side, x.at[1] + sn * fwd + Math.cos(x.ang) * side * 0.5);
      const body = [pt(L * 0.55, 0), pt(L * 0.25, Wd * 0.5), pt(-L * 0.2, Wd * 0.42), pt(-L * 0.45, 0), pt(-L * 0.2, -Wd * 0.42), pt(L * 0.25, -Wd * 0.5)];
      const tail = [pt(-L * 0.4, 0), pt(-L * 0.62, Wd * 0.38), pt(-L * 0.62, -Wd * 0.38)];
      g.fillStyle(col, F.shadow_soft_alpha * (blink / F.shadow_alpha)).fillEllipse(x.at[0], x.at[1], L * 1.5, L * 0.75);
      g.fillStyle(col, blink).fillPoints(body, true).fillPoints(tail, true);
    });
  }

  /** parado: quadro fixo, sem mexer as pernas */
  private halt(w: Walker, now: number): void {
    w.to = null;
    w.until = now + between(W.idle_ms);
    w.spr.stop().setFrame(W.idle_frame);
  }

  private stepWalker(w: Walker, now: number, dt: number): void {
    if (!w.to) {
      if (now < w.until) return;
      // passo quase de lado (a arte olha para a frente-esquerda; subir reto parece andar de costas),
      // sem atravessar prédio, cerca ou o espaço de outro bicho
      for (let k = 0; k < 16 && !w.to; k++) {
        const len = between(W.step_px) * (k < 8 ? 1 : 0.45), side = rnd() < 0.5 ? -1 : 1; // sem lugar: passo mais curto
        const p: Pt = [Math.round(w.at[0] + side * len), Math.round(w.at[1] + (rnd() * 2 - 1) * len * W.max_step_slope)];
        if (clearPath(w.at, p, w.area.poly, w.area.avoid, W.edge_margin_px) && !crowded(p, w.r, w.mates, w) && !pathCrowded(w.at, p, w)) w.to = p;
      }
      if (!w.to) { w.until = now + between(W.idle_ms); return; }
      w.spr.setFlipX(w.to[0] > w.at[0]); // a arte olha para a esquerda
      w.spr.play(`${w.key}_walk`, true);
      return;
    }
    const dx = w.to[0] - w.at[0], dy = w.to[1] - w.at[1], d = Math.hypot(dx, dy);
    const step = (w.speed * dt) / 1000;
    if (d <= step) {
      w.at = w.to;
      this.halt(w, now);
    } else {
      const next: Pt = [w.at[0] + (dx / d) * step, w.at[1] + (dy / d) * step];
      // outro bicho entrou no caminho: para antes de encostar
      if (crowded(next, w.r, w.mates, w, true)) this.halt(w, now);
      else w.at = next;
    }
    w.spr.setPosition(Math.round(w.at[0]), Math.round(w.at[1])).setDepth(depthOf(w.at[1]));
  }

  /** nado com rumo que vira aos poucos para o alvo, mais um balanço lento (nunca linha reta); ondulação a cada 2–4 s */
  private stepFish(f: Fish, now: number, dt: number, stop: boolean): void {
    if (now >= f.nextRipple) {
      this.rings.push({ x: f.at[0], y: f.at[1], born: now, ms: F.ripple_ms, r: F.ripple_radius_px, a: F.ripple_alpha });
      f.nextRipple = now + between(F.ripple_every_ms);
    }
    if (stop) return;
    const dx = f.to[0] - f.at[0], dy = (f.to[1] - f.at[1]) * 2, d = Math.hypot(dx, dy);
    if (d < 4) { f.to = this.nextFishTarget(f.at); f.speed = between(F.speed_px_s); return; }
    const want = Math.atan2(dy, dx) + Math.sin(now / 1000 * 0.9 + f.blink) * 0.6 * (F.wander_rad_s / F.turn_rad_s);
    let diff = want - f.ang;
    while (diff > Math.PI) diff -= Math.PI * 2;
    while (diff < -Math.PI) diff += Math.PI * 2;
    f.ang += Math.max(-1, Math.min(1, diff)) * F.turn_rad_s * dt / 1000;
    const step = (f.speed * dt) / 1000;
    const nx = f.at[0] + Math.cos(f.ang) * step, ny = f.at[1] + Math.sin(f.ang) * step * 0.5;
    const w = this.lake!.water!;
    if (clearPath(f.at, [nx, ny], w.polygon, w.avoid, w.margin_px)) f.at = [nx, ny];
    else { f.ang += Math.PI * 0.5; f.to = this.nextFishTarget(f.at); } // margem: vira e escolhe outro rumo
  }
}
