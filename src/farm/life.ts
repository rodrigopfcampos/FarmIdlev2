// Regras puras da vida no mapa v3 (animais andando, peixes, pomar): sem Phaser, para testar.
import { ANIM, CROPS, FARM, type Pt } from '../data';
import { pointInPolygon } from './geometry';
import type { TreeState } from './rules';

export type Rect = number[]; // [x0, y0, x1, y1]

function distToSegment(x: number, y: number, [ax, ay]: Pt, [bx, by]: Pt): number {
  const dx = bx - ax, dy = by - ay;
  const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy || 1)));
  return Math.hypot(x - (ax + t * dx), y - (ay + t * dy));
}

/** ponto livre: dentro do polígono, longe da borda (margem) e fora dos retângulos (prédios e píer desenhados no fundo) */
export function isFree(x: number, y: number, poly: Pt[], avoid: Rect[] = [], margin = 0): boolean {
  if (!pointInPolygon(x, y, poly)) return false;
  if (avoid.some(([x0, y0, x1, y1]) => x >= x0 && x <= x1 && y >= y0 && y <= y1)) return false;
  if (margin > 0) for (let i = 0; i < poly.length; i++) if (distToSegment(x, y, poly[i], poly[(i + 1) % poly.length]) < margin) return false;
  return true;
}

/** sorteia um ponto livre (tentativas no retângulo do polígono); sem achar, devolve o centro */
export function randomFreePoint(poly: Pt[], avoid: Rect[], rnd: () => number, margin = 0): Pt {
  const xs = poly.map((p) => p[0]), ys = poly.map((p) => p[1]);
  const [x0, x1, y0, y1] = [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)];
  for (let k = 0; k < 200; k++) {
    const x = Math.round(x0 + rnd() * (x1 - x0)), y = Math.round(y0 + rnd() * (y1 - y0));
    if (isFree(x, y, poly, avoid, margin)) return [x, y];
  }
  return [Math.round(xs.reduce((a, b) => a + b) / xs.length), Math.round(ys.reduce((a, b) => a + b) / ys.length)];
}

/** o caminho reto de a até b passa só por pontos livres? (amostra a cada 4 px) */
export function clearPath(a: Pt, b: Pt, poly: Pt[], avoid: Rect[], margin = 0): boolean {
  const n = Math.max(1, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / 4));
  for (let i = 1; i <= n; i++) if (!isFree(a[0] + ((b[0] - a[0]) * i) / n, a[1] + ((b[1] - a[1]) * i) / n, poly, avoid, margin)) return false;
  return true;
}

/** sprite de animação de um animal (os 10 animais usam as 4 artes: elas mostram que o pasto está produzindo) */
export function walkSpriteFor(animalId: string): string {
  const m = ANIM.animals_wander.sprite_by_animal as Record<string, string>;
  return `animal_walk_${m[animalId] ?? 'chicken'}`;
}

/** espécies do lago liberadas no nível (1 nova a cada 10 níveis) */
export function unlockedFish(level: number): string[] {
  return ANIM.lake_fish.species.filter((s) => level >= s.level).map((s) => s.sprite);
}

/** quantos peixes nadam: de 6 (só a primeira espécie) até 12 (todas) */
export function fishCount(level: number): number {
  const f = ANIM.lake_fish, total = f.species.length, have = Math.max(1, unlockedFish(level).length);
  return Math.round(f.count_min + ((f.count_max - f.count_min) * (have - 1)) / Math.max(1, total - 1));
}

export type OrchardLook = 'empty' | 'pit' | 'sprout' | 'young' | 'adult' | 'fruit';

/** visual de uma vaga do pomar: cova (lote seu, sem árvore), broto, jovem, adulta e adulta com fruta */
export function orchardLook(t: TreeState | undefined, now: number, owned: boolean): OrchardLook {
  if (!t || !t.fruit_id || t.ready_at === null || t.planted_at === null) return owned ? 'pit' : 'empty';
  const c = CROPS[t.fruit_id];
  const [, mid, ripe] = FARM.visual.stage_thresholds;
  const firstGrowth = t.ready_at - t.planted_at <= c.grow_minutes * 60 + 1;
  const cycle = firstGrowth ? t.ready_at - t.planted_at : (c.regrow_minutes ?? c.grow_minutes) * 60;
  const progress = (now - (t.ready_at - cycle)) / cycle;
  if (firstGrowth && progress < ANIM.orchard.sprout_until) return 'sprout';
  if (firstGrowth && progress < mid) return 'young';
  return progress >= ripe ? 'fruit' : 'adult';
}

/** pixel da fruta vermelha da arte "Árvore Adulta" (o tronco é marrom: verde/vermelho perto de 0,45 e azul baixo) */
export function isFruitPixel(r: number, g: number, b: number): boolean {
  if (r < 60) return false;
  if (g / r < 0.33 && b > g) return true;
  return r > 200 && g / r < 0.45 && b >= g * 0.95;
}

/** cor nova de um pixel da fruta: a cor-base escurecida/clareada na mesma proporção do vermelho original */
export function recolor(r: number, base: [number, number, number]): [number, number, number] {
  const k = r / ANIM.orchard.fruit_ref_red;
  return base.map((v) => Math.max(0, Math.min(255, Math.round(v * k)))) as [number, number, number];
}
