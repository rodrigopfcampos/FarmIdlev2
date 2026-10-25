// Captura quadros do jogo rodando, com o relógio travado, para CONFERIR uma animação olhando a imagem.
// Uso: node tools/anim/capture.mjs <nome> <x> <y> <largura> <altura> [ms_total=1600] [passo_ms=100] [zoom=4] [preview=chuva]
import { createRequire } from 'node:module';
import sharp from 'sharp';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
const require = createRequire(import.meta.url);
const { chromium } = (() => { for (const p of ['playwright', '/opt/npm-tools/node_modules/playwright', '/usr/local/lib/node_modules/playwright', '/usr/lib/node_modules/playwright']) { try { return require(p); } catch {} } throw new Error('Playwright não encontrado'); })();

const [name, X, Y, W, H, TOTAL = '1600', STEP = '100', ZOOM = '4', PREVIEW = ''] = process.argv.slice(2);
if (!name || !H) { console.error('uso: node tools/anim/capture.mjs <nome> <x> <y> <w> <h> [ms] [passo] [zoom] [ver]'); process.exit(1); }
const [x, y, w, h, total, step, zoom] = [X, Y, W, H, TOTAL, STEP, ZOOM].map(Number);
const url = `http://127.0.0.1:${process.env.PORT ?? 5199}/?mock=1${PREVIEW ? `&ver=${PREVIEW}` : ''}`;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1672, height: 940 }, deviceScaleFactor: 1 });
await page.clock.install({ time: 0 });                 // relógio falso: o jogo só anda quando mandamos
await page.goto(url);
await page.clock.runFor(4000);                          // carrega artes e entra na cena
await page.waitForFunction(() => window.game?.scene?.isActive('farm'), null, { timeout: 15000 }).catch(() => {});
await page.evaluate(() => { const u = document.getElementById('ui'); if (u) u.style.display = 'none'; }); // só o mapa
await page.clock.runFor(500);

const origin = await page.evaluate(() => { const c = window.game.scene.getScene('farm').cameras.main; return { sx: c.worldView.x, sy: c.worldView.y, zoom: c.zoom }; });
const clip = { x: Math.round((x - origin.sx) * origin.zoom), y: Math.round((y - origin.sy) * origin.zoom), width: w * origin.zoom, height: h * origin.zoom };

const frames = [];
for (let t = 0; t < total; t += step) { frames.push(await page.screenshot({ clip })); await page.clock.runFor(step); }
await browser.close();

mkdirSync('tools/anim/out', { recursive: true });
const cell = { width: clip.width * zoom / origin.zoom, height: clip.height * zoom / origin.zoom };
const cols = Math.min(frames.length, Math.max(1, Math.floor(1800 / (cell.width + 6))));
const rows = Math.ceil(frames.length / cols);
const comps = [];
for (let i = 0; i < frames.length; i++) {
  const buf = await sharp(frames[i]).resize(cell.width, cell.height, { kernel: 'nearest' }).toBuffer();
  comps.push({ input: buf, left: (i % cols) * (cell.width + 6), top: Math.floor(i / cols) * (cell.height + 6) });
}
await sharp({ create: { width: cols * (cell.width + 6), height: rows * (cell.height + 6), channels: 3, background: '#202020' } })
  .composite(comps).png().toFile(`tools/anim/out/${name}.png`);
writeFileSync(`tools/anim/out/${name}.json`, JSON.stringify({ name, frames: frames.length, step_ms: step, cols, rows }));
const dir = `tools/anim/out/${name}_frames`;
rmSync(dir, { recursive: true, force: true }); mkdirSync(dir, { recursive: true });
for (let i = 0; i < frames.length; i++) await sharp(frames[i]).resize(cell.width, cell.height, { kernel: 'nearest' }).png().toFile(`${dir}/${String(i).padStart(3, '0')}.png`);
try {
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-framerate', String(1000 / step), '-i', `${dir}/%03d.png`,
    '-vf', 'split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=none', `tools/anim/out/${name}.gif`]);
  console.log(`gif: tools/anim/out/${name}.gif`);
} catch { console.log('(sem ffmpeg: só a tira PNG)'); }
rmSync(dir, { recursive: true, force: true });
console.log(`ok: tools/anim/out/${name}.png (${frames.length} quadros de ${step} ms)`);
