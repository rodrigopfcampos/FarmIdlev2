// Ícones do clima em pixel art, desenhados no código (16×16, pixels inteiros) até chegar a arte final.
// Cada ícone vira uma imagem PNG em memória e aparece ampliada sem borrão (image-rendering: pixelated).
import { WEATHER } from '../data';

type Px = (x: number, y: number, c: string) => void;
const OUT = '#2a1d12';

function disc(px: Px, cx: number, cy: number, r: number, fill: string, edge = OUT): void {
  for (let y = -r - 1; y <= r + 1; y++) for (let x = -r - 1; x <= r + 1; x++) {
    const d = x * x + y * y;
    if (d <= r * r) px(cx + x, cy + y, fill);
    else if (d <= (r + 1) * (r + 1)) px(cx + x, cy + y, edge);
  }
}
function rays(px: Px, cx: number, cy: number, r: number, c: string, long = false): void {
  const pts: [number, number][] = [[0, -1], [0, 1], [-1, 0], [1, 0], [-1, -1], [1, 1], [-1, 1], [1, -1]];
  for (const [dx, dy] of pts) {
    const diag = dx !== 0 && dy !== 0;
    const n = long && !diag ? 3 : 2;
    for (let k = 0; k < n; k++) px(cx + dx * (r + 2 + k - (diag ? 1 : 0)), cy + dy * (r + 2 + k - (diag ? 1 : 0)), c);
  }
}
function cloud(px: Px, ox: number, oy: number, fill: string, shade: string): void {
  disc(px, ox + 4, oy + 4, 3, fill); disc(px, ox + 8, oy + 3, 4, fill); disc(px, ox + 11, oy + 5, 2, fill);
  for (let x = ox + 2; x <= ox + 13; x++) { px(x, oy + 7, fill); px(x, oy + 8, OUT); }
  for (let x = ox + 3; x <= ox + 12; x++) px(x, oy + 7, shade);
}
function drops(px: Px, y0: number, c: string): void {
  for (const x of [4, 8, 12]) { px(x, y0, c); px(x - 1, y0 + 1, c); px(x - 1, y0 + 2, OUT); }
  for (const x of [6, 10]) { px(x, y0 + 2, c); px(x - 1, y0 + 3, c); }
}
function fogLines(px: Px, c: string, edge: string): void {
  for (const [y, a, b] of [[4, 2, 11], [7, 4, 14], [10, 1, 12], [13, 3, 13]] as const) {
    for (let x = a; x <= b; x++) { px(x, y, c); px(x, y + 1, edge); }
  }
}
function star(px: Px, x: number, y: number, c: string): void {
  px(x, y, '#ffffff'); px(x - 1, y, c); px(x + 1, y, c); px(x, y - 1, c); px(x, y + 1, c);
}
function moon(px: Px, full: boolean): void {
  disc(px, 8, 8, 5, '#eef0ff');
  for (const [x, y] of [[6, 6], [9, 10], [10, 6], [7, 11]]) px(x, y, '#c4c9e6');
  if (!full) disc(px, 11, 6, 4, 'transparent', 'transparent');
}

const DRAW: Record<string, (px: Px) => void> = {
  sunny: (px) => { disc(px, 8, 8, 3, '#f2c230'); rays(px, 8, 8, 3, '#f2c230'); px(7, 7, '#fff3b0'); },
  hot_sun: (px) => { disc(px, 8, 8, 4, '#f28a1e'); rays(px, 8, 8, 4, '#e8521e', true); px(6, 6, '#ffd36b'); px(7, 6, '#ffd36b'); px(6, 7, '#ffd36b'); },
  cloudy: (px) => cloud(px, 0, 4, '#e3e8ee', '#b4bdc9'),
  rain: (px) => { cloud(px, 0, 1, '#b4bdc9', '#8e98a8'); drops(px, 11, '#4a90d9'); },
  fog: (px) => fogLines(px, '#d7dde3', '#9aa4b0'),
  night: (px) => moon(px, false),
  chuva_de_bencaos: (px) => { drops(px, 4, '#6fb6ff'); drops(px, 9, '#6fb6ff'); star(px, 12, 3, '#bfe1ff'); star(px, 3, 12, '#bfe1ff'); },
  calor_dourado: (px) => { disc(px, 8, 8, 3, '#f2c230'); rays(px, 8, 8, 3, '#ffe27a', true); star(px, 13, 2, '#f2c230'); },
  neblina_mistica: (px) => { fogLines(px, '#c9b0ff', '#7d5cc4'); star(px, 12, 2, '#e2d4ff'); star(px, 3, 13, '#e2d4ff'); },
  lua_cheia: (px) => { moon(px, true); star(px, 2, 2, '#e8ecff'); star(px, 14, 13, '#e8ecff'); },
};

const cache = new Map<string, string>();

/** imagem PNG (data URL) do ícone; vazio se não existir */
export function weatherIconUrl(id: string): string {
  if (cache.has(id)) return cache.get(id)!;
  const draw = DRAW[id];
  if (!draw || typeof document === 'undefined') return '';
  const n = WEATHER.visual.icon_px;
  const cv = document.createElement('canvas');
  cv.width = n; cv.height = n;
  const g = cv.getContext('2d')!;
  draw((x, y, c) => {
    if (x < 0 || y < 0 || x >= n || y >= n) return;
    if (c === 'transparent') g.clearRect(x, y, 1, 1);
    else { g.fillStyle = c; g.fillRect(x, y, 1, 1); }
  });
  const url = cv.toDataURL('image/png');
  cache.set(id, url);
  return url;
}

/** <img> do ícone em escala inteira */
export function weatherIcon(id: string, scale = 2, title = ''): string {
  const url = weatherIconUrl(id);
  const n = WEATHER.visual.icon_px * scale;
  return url ? `<img class="wx-icon" src="${url}" width="${n}" height="${n}" alt="${title}" ${title ? `title="${title}"` : ''}>` : '';
}
