// Geometria dos canteiros (isométrico 2:1) e estágio visual das mudas.
import type { Pt } from '../data';

/** 6 mudas por canteiro (3 ao longo do lado comprido × 2 fileiras), já em ordem de profundidade (y). */
export function seedlingPositions(poly: Pt[]): Pt[] {
  const [p0, p1, , p3] = poly; // esquerda, cima, direita, baixo
  const out: Pt[] = [];
  for (let j = 0; j < 2; j++) for (let i = 0; i < 3; i++) {
    const u = (i + 0.5) / 3, v = (j + 0.5) / 2;
    out.push([
      Math.round(p0[0] + u * (p3[0] - p0[0]) + v * (p1[0] - p0[0])),
      Math.round(p0[1] + u * (p3[1] - p0[1]) + v * (p1[1] - p0[1])) + 3,
    ]);
  }
  return out.sort((a, b) => a[1] - b[1] || a[0] - b[0]);
}

export function pointInPolygon(x: number, y: number, poly: Pt[]): boolean {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/** 0 semente, 1 broto, 2 crescendo, 3 pronto */
export function stageFor(progress: number, thresholds: number[]): number {
  let s = 0;
  for (const t of thresholds) if (progress >= t) s++;
  return Math.min(3, s);
}

/** deslocamento do vento em pixels inteiros (−força..+força) */
export function windOffset(timeS: number, x: number, speed: number, strength: number): number {
  return Math.round(Math.sin(timeS * speed + x * 0.4) * strength);
}

/** Limites da câmera: no lado em que o mapa cabe na tela, a área cresce igual para os dois lados,
 *  assim o mapa fica centralizado; no lado em que não cabe, dá para arrastar até a borda do mapa. */
export function cameraBounds(mapW: number, mapH: number, viewW: number, viewH: number, zoom: number): [number, number, number, number] {
  const w = Math.max(mapW, viewW / zoom), h = Math.max(mapH, viewH / zoom);
  return [(mapW - w) / 2, (mapH - h) / 2, w, h];
}
