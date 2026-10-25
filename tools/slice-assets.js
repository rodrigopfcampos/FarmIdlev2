// Recorta as pranchas de arte (assets/raw) em PNGs transparentes no tamanho final do jogo.
// Uso: node tools/slice-assets.js [--preview pasta] [--only nomeDaPrancha]
// As pranchas e as grades ficam em tools/assets/sheets.json; a saída vai para public/assets/sprites
// junto com manifest.json (chave → arquivo, tamanho, âncora).
import sharp from 'sharp';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const cfg = JSON.parse(readFileSync(join(root, 'tools', 'assets', 'sheets.json'), 'utf8'));
const args = process.argv.slice(2);
const previewDir = args.includes('--preview') ? args[args.indexOf('--preview') + 1] : null;
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null;
const outRoot = join(root, cfg.output_dir);

// ---------- leitura e remoção do fundo ----------
async function loadSheet(sheet) {
  const { data, info } = await sharp(join(root, cfg.raw_dir, sheet.file)).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const W = info.width, H = info.height;
  // cor do fundo = mediana da borda de 3 px
  const rs = [], gs = [], bs = [];
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (x > 2 && y > 2 && x < W - 3 && y < H - 3) continue;
    const i = (y * W + x) * 4; rs.push(data[i]); gs.push(data[i + 1]); bs.push(data[i + 2]);
  }
  const med = (a) => a.sort((p, q) => p - q)[a.length >> 1];
  const bg = [med(rs), med(gs), med(bs)];
  const tol = sheet.tolerance ?? cfg.default_tolerance;
  const bgLike = new Uint8Array(W * H);
  for (let p = 0; p < W * H; p++) {
    const i = p * 4;
    const d = Math.max(Math.abs(data[i] - bg[0]), Math.abs(data[i + 1] - bg[1]), Math.abs(data[i + 2] - bg[2]));
    // sombras escuras e neutras perto do fundo também saem (as IAs desenham sombra projetada)
    const lum = (data[i] + data[i + 1] + data[i + 2]) / 3;
    const chroma = Math.max(data[i], data[i + 1], data[i + 2]) - Math.min(data[i], data[i + 1], data[i + 2]);
    bgLike[p] = d <= tol || (sheet.remove_dark_shadow && lum <= bg[0] + 4 && chroma <= 6) ? 1 : 0;
  }
  // remove por inundação a partir da borda: o que é escuro mas está dentro do contorno fica
  const removed = new Uint8Array(W * H);
  const stack = [];
  const push = (p) => { if (bgLike[p] && !removed[p]) { removed[p] = 1; stack.push(p); } };
  for (let x = 0; x < W; x++) { push(x); push((H - 1) * W + x); }
  for (let y = 0; y < H; y++) { push(y * W); push(y * W + W - 1); }
  const flood = () => {
    while (stack.length) {
      const p = stack.pop(), x = p % W, y = (p / W) | 0;
      if (x > 0) push(p - 1); if (x < W - 1) push(p + 1);
      if (y > 0) push(p - W); if (y < H - 1) push(p + W);
    }
  };
  flood();
  // molduras vazadas: buracos grandes da cor do fundo também viram transparência
  if (sheet.holes_min_area) {
    const seen = new Uint8Array(W * H);
    for (let p = 0; p < W * H; p++) {
      if (!bgLike[p] || removed[p] || seen[p]) continue;
      const comp = [p]; seen[p] = 1;
      for (let k = 0; k < comp.length; k++) {
        const q = comp[k], x = q % W, y = (q / W) | 0;
        for (const n of [x > 0 ? q - 1 : -1, x < W - 1 ? q + 1 : -1, y > 0 ? q - W : -1, y < H - 1 ? q + W : -1])
          if (n >= 0 && bgLike[n] && !removed[n] && !seen[n]) { seen[n] = 1; comp.push(n); }
      }
      if (comp.length >= sheet.holes_min_area) for (const q of comp) removed[q] = 1;
    }
  }
  const fg = new Uint8Array(W * H);
  for (let p = 0; p < W * H; p++) fg[p] = removed[p] ? 0 : 1;
  despeckle(fg, W, H, sheet.min_speck ?? cfg.default_min_speck);
  return { data, W, H, fg, bg, kernel: sheet.kernel };
}

// apaga pontinhos soltos (ruído de JPG) menores que minArea
function despeckle(fg, W, H, minArea) {
  const seen = new Uint8Array(W * H);
  for (let p = 0; p < W * H; p++) {
    if (!fg[p] || seen[p]) continue;
    const comp = [p]; seen[p] = 1;
    for (let k = 0; k < comp.length; k++) {
      const q = comp[k], x = q % W, y = (q / W) | 0;
      for (const n of [x > 0 ? q - 1 : -1, x < W - 1 ? q + 1 : -1, y > 0 ? q - W : -1, y < H - 1 ? q + W : -1])
        if (n >= 0 && fg[n] && !seen[n]) { seen[n] = 1; comp.push(n); }
      if (comp.length > minArea) break;
    }
    if (comp.length <= minArea) for (const q of comp) fg[q] = 0;
  }
}

// ---------- grade automática: faixas de linhas e colunas com conteúdo ----------
function bands(counts, from, expected, minGap, label) {
  let runs = [];
  let start = -1, gap = 0;
  for (let i = 0; i <= counts.length; i++) {
    const on = i < counts.length && counts[i] > 0;
    if (on) { if (start < 0) start = i; gap = 0; }
    else if (start >= 0) {
      gap++;
      if (gap >= minGap || i === counts.length) { runs.push([start, i - gap + 1]); start = -1; gap = 0; }
    }
  }
  // junta as faixas mais próximas até sobrar o número esperado
  while (runs.length > expected) {
    let best = 0, bestGap = Infinity;
    for (let k = 0; k < runs.length - 1; k++) { const g = runs[k + 1][0] - runs[k][1]; if (g < bestGap) { bestGap = g; best = k; } }
    runs.splice(best, 2, [runs[best][0], runs[best + 1][1]]);
  }
  if (runs.length !== expected) throw new Error(`${label}: esperava ${expected} faixas e achei ${runs.length} (${JSON.stringify(runs.map((r) => r.map((v) => v + from)))})`);
  return runs.map(([a, b]) => [a + from, b + from]);
}

function detectCells(img, region) {
  const [x0, y0, x1, y1] = region.rect ?? [0, 0, img.W, img.H];
  const rowCounts = new Array(y1 - y0).fill(0);
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) if (img.fg[y * img.W + x]) rowCounts[y - y0]++;
  // linhas iguais quando os sprites de linhas vizinhas se encostam (ex.: folhas de banana)
  const rows = region.uniform_rows
    ? Array.from({ length: region.rows }, (_, k) => [y0 + Math.round(((y1 - y0) * k) / region.rows), y0 + Math.round(((y1 - y0) * (k + 1)) / region.rows)])
    : bands(rowCounts, y0, region.rows, region.min_gap ?? 8, `${region.name} linhas`);
  return rows.map(([ra, rb], r) => {
    const colCounts = new Array(x1 - x0).fill(0);
    for (let y = ra; y < rb; y++) for (let x = x0; x < x1; x++) if (img.fg[y * img.W + x]) colCounts[x - x0]++;
    const nCols = Array.isArray(region.cols) ? region.cols[r] : region.cols;
    const cols = region.uniform_cols
      ? Array.from({ length: nCols }, (_, k) => [x0 + Math.round(((x1 - x0) * k) / nCols), x0 + Math.round(((x1 - x0) * (k + 1)) / nCols)])
      : bands(colCounts, x0, nCols, region.min_gap ?? 8, `${region.name} colunas da linha ${r + 1}`);
    if (region.drop_edge_fragments) for (const [ca, cb] of cols) dropEdgeFragments(img, ca, ra, cb, rb);
    return cols.map(([ca, cb]) => tightBox(img, ca, ra, cb, rb));
  });
}

// em células de tamanho fixo, pedaços do sprite vizinho que entram pela borda são apagados
function dropEdgeFragments(img, xa, ya, xb, yb) {
  const W = img.W, seen = new Set(), comps = [];
  for (let y = ya; y < yb; y++) for (let x = xa; x < xb; x++) {
    const p = y * W + x;
    if (!img.fg[p] || seen.has(p)) continue;
    const comp = [p]; seen.add(p); let edge = false;
    for (let k = 0; k < comp.length; k++) {
      const q = comp[k], qx = q % W, qy = (q / W) | 0;
      if (qx === xa || qx === xb - 1) edge = true;
      for (const [nx, ny] of [[qx - 1, qy], [qx + 1, qy], [qx, qy - 1], [qx, qy + 1]]) {
        if (nx < xa || nx >= xb || ny < ya || ny >= yb) continue;
        const n = ny * W + nx;
        if (img.fg[n] && !seen.has(n)) { seen.add(n); comp.push(n); }
      }
    }
    comps.push({ comp, edge });
  }
  const total = comps.reduce((s, c) => s + c.comp.length, 0);
  for (const c of comps) if (c.edge && c.comp.length < total * 0.05) for (const q of c.comp) img.fg[q] = 0;
}

function tightBox(img, xa, ya, xb, yb) {
  let minX = Infinity, minY = Infinity, maxX = -1, maxY = -1;
  for (let y = ya; y < yb; y++) for (let x = xa; x < xb; x++) if (img.fg[y * img.W + x]) {
    if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y;
  }
  return { x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1 };
}

// ---------- recorte, redução e montagem ----------
function cropRGBA(img, b) {
  const out = Buffer.alloc(b.w * b.h * 4);
  for (let y = 0; y < b.h; y++) for (let x = 0; x < b.w; x++) {
    const p = (b.y + y) * img.W + (b.x + x), i = p * 4, o = (y * b.w + x) * 4;
    if (!img.fg[p]) continue;
    out[o] = img.data[i]; out[o + 1] = img.data[i + 1]; out[o + 2] = img.data[i + 2]; out[o + 3] = 255;
  }
  return out;
}

// pixel art: redução com "nearest" (sem filtro suave, sem borda cinza); em tamanho nativo nada é redimensionado
async function scaled(img, b, w, h, kernel) {
  const src = cropRGBA(img, b);
  if (w === b.w && h === b.h) return src;
  const { data } = await sharp(src, { raw: { width: b.w, height: b.h, channels: 4 } })
    .resize(w, h, { fit: 'fill', kernel }).raw().toBuffer({ resolveWithObject: true });
  // pixel art: alfa binário, sem borda semitransparente
  for (let i = 3; i < data.length; i += 4) data[i] = data[i] >= 110 ? 255 : 0;
  return data;
}

function blit(canvas, CW, src, w, h, ox, oy) {
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const tx = ox + x, ty = oy + y;
    if (tx < 0 || ty < 0 || tx >= CW) continue;
    const s = (y * w + x) * 4, t = (ty * CW + tx) * 4;
    if (src[s + 3] === 0) continue;
    canvas[t] = src[s]; canvas[t + 1] = src[s + 1]; canvas[t + 2] = src[s + 2]; canvas[t + 3] = 255;
  }
}

const manifest = {};
const previews = [];

async function renderRegion(img, region) {
  const cells = region.cells ? region.cells.map((r) => r.map(([x, y, w, h]) => tightBox(img, x, y, x + w, y + h))) : detectCells(img, region);
  const sizeOf = (r, c) => region.sizes?.[r]?.[c] ?? region.sizes_by_col?.[c] ?? region.size;
  // escala comum por linha (estágios de crescimento, quadros de animação) ou por célula
  const scaleFor = (b, [W, H]) => Math.min(W / b.w, H / b.h);
  const rowScale = cells.map((row, r) => Math.min(...row.map((b, c) => scaleFor(b, sizeOf(r, c)))));
  const allScale = Math.min(...rowScale);
  for (let r = 0; r < cells.length; r++) {
    const frames = [];
    for (let c = 0; c < cells[r].length; c++) {
      const name = region.names[r][c];
      if (!name) continue;
      const b = cells[r][c];
      const [W, H] = sizeOf(r, c);
      let w, h;
      if (region.fit === 'fill') { w = W; h = H; }
      else if (region.native) { w = b.w; h = b.h; } // resolução original da prancha (retratos da interface)
      else {
        let s = region.scale === 'row' ? rowScale[r] : region.scale === 'all' ? allScale : scaleFor(b, [W, H]);
        // estágios pequenos ficam maiores (sem passar da célula), para a muda aparecer no canteiro
        if (region.col_boost?.[c]) s = Math.min(s * region.col_boost[c], scaleFor(b, [W, H]));
        w = Math.max(1, Math.round(b.w * s)); h = Math.max(1, Math.round(b.h * s));
      }
      const px = await scaled(img, b, w, h, region.kernel ?? img.kernel ?? cfg.default_kernel ?? 'nearest');
      const canvas = Buffer.alloc(W * H * 4);
      const align = region.align ?? 'bottom';
      let ox = Math.floor((W - w) / 2), oy = align === 'center' ? Math.floor((H - h) / 2) : H - h;
      if (region.align_x === 'left_common') {
        // animação: mesma origem à esquerda em todos os quadros da linha, para não tremer
        const ws = cells[r].map((bb) => Math.round(bb.w * rowScale[r]));
        ox = Math.floor((W - Math.max(...ws)) / 2);
      }
      blit(canvas, W, px, w, h, ox, oy);
      frames.push({ name, canvas, W, H });
      previews.push({ name, canvas, W, H });
    }
    if (region.strip) {
      // tira horizontal com todos os quadros da linha
      const { W, H } = frames[0];
      const strip = Buffer.alloc(W * frames.length * H * 4);
      frames.forEach((f, k) => blit(strip, W * frames.length, f.canvas, W, H, k * W, 0));
      await save(region.strip[r], strip, W * frames.length, H, region, { frames: frames.length, frame_size: [W, H] });
    } else {
      for (const f of frames) await save(f.name, f.canvas, f.W, f.H, region);
    }
  }
}

async function save(name, buf, W, H, region, extra = {}) {
  // o nome pode ter subpasta (ex.: "extras/crop_trigo_ready"); a chave é só o fim
  const rel = join(region.dir, `${name}.png`);
  const key = name.split('/').pop();
  mkdirSync(dirname(join(outRoot, rel)), { recursive: true });
  await sharp(buf, { raw: { width: W, height: H, channels: 4 } }).png({ compressionLevel: 9 }).toFile(join(outRoot, rel));
  manifest[key] = { file: `sprites/${rel.replace(/\\/g, '/')}`, size: [W, H], anchor: region.align === 'center' ? [0.5, 0.5] : [0.5, 1], ...extra };
}

// prévia ampliada ×3 sobre fundo xadrez, para conferir a olho
async function writePreview(sheetName) {
  if (!previewDir || !previews.length) return;
  const Z = 3, pad = 4, maxW = 1200;
  let x = 0, y = 0, rowH = 0;
  const pos = previews.map((p) => {
    const w = p.W * Z + pad, h = p.H * Z + pad;
    if (x + w > maxW) { x = 0; y += rowH; rowH = 0; }
    const at = [x, y]; x += w; rowH = Math.max(rowH, h); return at;
  });
  const CW = maxW, CH = y + rowH;
  const canvas = Buffer.alloc(CW * CH * 4);
  for (let i = 0; i < CW * CH; i++) { const cx = (i % CW) >> 3, cy = ((i / CW) | 0) >> 3; const v = (cx + cy) % 2 ? 70 : 100; canvas.fill(v, i * 4, i * 4 + 3); canvas[i * 4 + 3] = 255; }
  previews.forEach((p, k) => {
    const [px, py] = pos[k];
    for (let yy = 0; yy < p.H * Z; yy++) for (let xx = 0; xx < p.W * Z; xx++) {
      const s = (((yy / Z) | 0) * p.W + ((xx / Z) | 0)) * 4;
      if (!p.canvas[s + 3]) continue;
      const t = ((py + yy) * CW + px + xx) * 4;
      canvas[t] = p.canvas[s]; canvas[t + 1] = p.canvas[s + 1]; canvas[t + 2] = p.canvas[s + 2];
    }
  });
  mkdirSync(previewDir, { recursive: true });
  await sharp(canvas, { raw: { width: CW, height: CH, channels: 4 } }).png().toFile(join(previewDir, `${sheetName}.png`));
  previews.length = 0;
}

for (const sheet of cfg.sheets) {
  if (only && sheet.id !== only) continue;
  const img = await loadSheet(sheet);
  for (const region of sheet.regions) await renderRegion(img, region);
  await writePreview(sheet.id);
  console.log(`ok  ${sheet.id} (fundo ${img.bg.join(',')})`);
}
if (!only) {
  writeFileSync(join(outRoot, 'manifest.json'), JSON.stringify({ version: 1, generated_by: 'tools/slice-assets.js', sprites: manifest }, null, 2) + '\n');
  console.log(`${Object.keys(manifest).length} sprites em ${cfg.output_dir}`);
}
