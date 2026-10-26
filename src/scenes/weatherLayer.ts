// Clima no mapa (GDD seções 4 e 10): filtro de noite e entardecer, nuvens, chuva em diagonal com respingo,
// terra molhada com poças, neblina que passa devagar, brilho do sol forte e vagalumes nos eventos noturnos.
// Tudo em pixels inteiros e tempo por quadro; números em config/weather.json (visual).
import Phaser from 'phaser';
import { WEATHER, type Pt } from '../data';
import { condAt, eventStatus, localMinutes, partAt, type WeatherView } from '../farm/weather';

const V = WEATHER.visual;
const hex = (c: string) => Phaser.Display.Color.HexStringToColor(c).color;
// números pseudoaleatórios fixos (o mesmo desenho a cada abertura, sem depender do relógio)
const rnd = (i: number, k: number) => { const x = Math.sin(i * 127.1 + k * 311.7) * 43758.5453; return x - Math.floor(x); };

type Drop = { img: Phaser.GameObjects.Image; x0: number; y0: number; land: number; speed: number; off: number };
type Dot = { img: Phaser.GameObjects.Image; x: number; y: number; off: number };

export class WeatherLayer {
  private tint: Phaser.GameObjects.Rectangle;
  private evTint: Phaser.GameObjects.Rectangle;
  private wet: Phaser.GameObjects.Graphics;
  private fog: Phaser.GameObjects.Graphics;
  private drops: Drop[] = [];
  private splashes: Phaser.GameObjects.Image[] = [];
  private sparks: Dot[] = [];
  private flies: Dot[] = [];
  private key = '';

  constructor(private scene: Phaser.Scene, private w: number, private h: number, private plots: Pt[][], private calm: boolean) {
    WeatherLayer.textures(scene);
    this.wet = scene.add.graphics().setDepth(0.6).setVisible(false);
    this.drawWet();
    const r = V.rain;
    for (let i = 0; i < r.drops; i++) {
      const img = scene.add.image(0, 0, 'wx_drop').setOrigin(0, 1).setDepth(13.6).setAlpha(r.alpha).setVisible(false); // por cima do filtro da noite
      this.drops.push({ img, x0: Math.floor(rnd(i, 1) * (w + h * r.slant)) - h * r.slant, y0: -Math.floor(rnd(i, 2) * h), land: Math.floor(h * (0.15 + 0.85 * rnd(i, 3))),
        speed: r.speed_px * (0.85 + 0.3 * rnd(i, 4)), off: Math.floor(rnd(i, 5) * 4000) });
      this.splashes.push(scene.add.image(0, 0, 'wx_splash').setOrigin(0.5, 1).setDepth(13.6).setAlpha(r.alpha).setVisible(false));
    }
    this.fog = scene.add.graphics().setDepth(12).setVisible(false);
    this.tint = scene.add.rectangle(0, 0, w, h, 0x000000, 0).setOrigin(0, 0).setDepth(13);
    this.evTint = scene.add.rectangle(0, 0, w, h, 0x000000, 0).setOrigin(0, 0).setDepth(13.5);
    for (let i = 0; i < V.sparkle.count; i++) {
      const p = plots[Math.floor(rnd(i, 7) * plots.length)];
      const c = p ? centerOf(p) : [w / 2, h / 2];
      this.sparks.push({ img: scene.add.image(0, 0, 'wx_spark').setDepth(10).setVisible(false), x: Math.round(c[0] + (rnd(i, 8) - 0.5) * 30), y: Math.round(c[1] - 6 - rnd(i, 9) * 14), off: Math.floor(rnd(i, 10) * 3000) });
    }
    for (let i = 0; i < V.fireflies.count; i++) {
      this.flies.push({ img: scene.add.image(0, 0, 'wx_fly').setDepth(14).setVisible(false), x: Math.round(60 + rnd(i, 11) * (w - 120)), y: Math.round(80 + rnd(i, 12) * (h - 160)), off: Math.floor(rnd(i, 13) * 5000) });
    }
  }

  /** texturas de 1 a 2 pixels: gota 1×4 em diagonal, respingo de 2 px, brilho e vagalume 2×2 */
  static textures(scene: Phaser.Scene): void {
    const make = (key: string, w: number, h: number, px: [number, number, string][]) => {
      if (scene.textures.exists(key)) return;
      const g = scene.make.graphics({ x: 0, y: 0 }, false);
      for (const [x, y, c] of px) { g.fillStyle(hex(c), 1); g.fillRect(x, y, 1, 1); }
      g.generateTexture(key, w, h); g.destroy();
    };
    // gota em diagonal no mesmo sentido em que cai: 1 px de largura, comprimento e inclinação da config
    const drop = V.rain.color, len = V.rain.length_px, sw = Math.ceil(len * V.rain.slant) + 1;
    make('wx_drop', sw, len, Array.from({ length: len }, (_, k) => [Math.floor(k * V.rain.slant), k, drop] as [number, number, string]));
    make('wx_splash', 3, 1, [[0, 0, drop], [2, 0, drop]]);
    make('wx_spark', 1, 1, [[0, 0, V.sparkle.color]]);
    make('wx_fly', 2, 2, [[0, 0, V.fireflies.color], [1, 0, V.fireflies.color], [0, 1, V.fireflies.color], [1, 1, V.fireflies.color]]);
  }

  /** terra escura dos canteiros na chuva (#6E5644) e 2 a 3 pixels de poça */
  private drawWet(): void {
    const g = this.wet, ws = V.wet_soil;
    g.fillStyle(hex(ws.color), ws.alpha);
    this.plots.forEach((p) => g.fillPoints(p.map(([x, y]) => new Phaser.Math.Vector2(x, y)), true));
    g.fillStyle(hex(ws.puddle_color), 1);
    this.plots.forEach((p, i) => {
      const [cx, cy] = centerOf(p);
      for (let k = 0; k < ws.puddles_per_plot; k++) {
        const x = Math.round(cx + (rnd(i, 20 + k) - 0.5) * 34), y = Math.round(cy + (rnd(i, 30 + k) - 0.5) * 10);
        g.fillRect(x, y, 2 + (k % 2), 1);
      }
    });
  }

  update(time: number, view: WeatherView | undefined, ms: number): void {
    if (!view) return;
    const cond = condAt(view, ms);
    const part = partAt(localMinutes(view.tz, ms));
    const ev = eventStatus(view, ms);
    const active = ev?.kind === 'active' ? ev.ev.id : '';
    const key = `${cond}|${part}|${active}`;
    if (key !== this.key) {
      this.key = key;
      // filtro: noite e entardecer mandam; de dia, o do clima (nublado, chuva, neblina, sol forte)
      const t = (V.tint as Record<string, { color: string; alpha: number }>)[part !== 'day' ? part : cond];
      this.tint.setFillStyle(t ? hex(t.color) : 0, t ? t.alpha : 0);
      const et = (V.event_tint as Record<string, string>)[active];
      this.evTint.setFillStyle(et ? hex(et) : 0, et ? V.event_tint_alpha : 0);
      this.wet.setVisible(cond === 'rain' || active === 'chuva_de_bencaos');
      this.fog.setVisible(cond === 'fog' || active === 'neblina_mistica');
      const rain = cond === 'rain' || active === 'chuva_de_bencaos';
      this.drops.forEach((d) => d.img.setVisible(rain));
      if (!rain) this.splashes.forEach((s) => s.setVisible(false));
      this.sparks.forEach((s) => s.img.setVisible(false));
      this.flies.forEach((f) => f.img.setVisible(!!active && part === 'night'));
    }
    const rainOn = this.drops[0]?.img.visible;
    if (rainOn) this.rain(time);
    if (this.fog.visible) this.drawFog(time, this.key.includes('neblina_mistica'));
    if (cond === 'hot_sun' || active === 'calor_dourado') this.sparkle(time);
    if (this.flies[0]?.img.visible) this.firefly(time);
  }

  /** gotas caem em diagonal; ao tocar o chão, respingo de 2 px por um instante */
  private rain(time: number): void {
    const r = V.rain;
    this.drops.forEach((d, i) => {
      const fall = d.land - d.y0;
      const cycle = (fall / d.speed) * 1000 + r.splash_ms;
      const t = this.calm ? cycle * 0.4 : (time + d.off) % cycle;
      const sp = this.splashes[i];
      if (t * d.speed / 1000 < fall) {
        const dy = Math.floor(t * d.speed / 1000);
        d.img.setPosition(Math.round(d.x0 + dy * r.slant), d.y0 + dy).setVisible(true);
        sp.setVisible(false);
      } else {
        d.img.setVisible(false);
        sp.setPosition(Math.round(d.x0 + fall * r.slant), d.land).setVisible(true);
      }
    });
  }

  /** nuvens de neblina em degraus de pixel (mais densas no meio), passando devagar; roxas na Neblina Mística */
  private drawFog(time: number, mystic: boolean): void {
    const f = V.fog, g = this.fog, step = 4;
    const color = hex(mystic ? (V.event_tint as Record<string, string>).neblina_mistica : f.color);
    g.clear();
    for (let i = 0; i < f.bands; i++) {
      const cy = Math.round(this.h * (0.18 + 0.7 * (i / Math.max(1, f.bands - 1))));
      const len = Math.round(this.w * (0.35 + 0.25 * rnd(i, 41)));
      const span = this.w + len;
      const shift = this.calm ? 0 : Math.floor((time / 1000) * f.drift_px * (i % 2 ? 1 : -1));
      const cx = ((Math.floor(rnd(i, 40) * span) + shift) % span + span) % span - len / 2;
      const rows = Math.max(2, Math.round(f.band_h_px / step));
      for (let j = 0; j < rows; j++) {
        const t = (2 * j + 1) / rows - 1;               // −1 … 1 de cima para baixo
        const wRow = Math.round(len * Math.sqrt(1 - t * t) / step) * step;
        g.fillStyle(color, f.alpha * (1 - Math.abs(t)));
        g.fillRect(Math.round(cx - wRow / 2), cy + (j - rows / 2) * step, wRow, step);
      }
    }
  }

  /** pontinhos de brilho piscando sobre as folhas no sol forte */
  private sparkle(time: number): void {
    const ms = V.sparkle.ms;
    this.sparks.forEach((s) => s.img.setPosition(s.x, s.y).setVisible(this.calm || Math.floor((time + s.off) / ms) % 3 === 0));
  }

  /** vagalumes 2×2 que acendem e apagam e andam de pixel em pixel */
  private firefly(time: number): void {
    const f = V.fireflies;
    this.flies.forEach((d) => {
      const k = Math.floor((time + d.off) / f.blink_ms);
      const dx = this.calm ? 0 : Math.round(Math.sin((time + d.off) / 1700) * f.drift_px);
      const dy = this.calm ? 0 : Math.round(Math.cos((time + d.off) / 2300) * f.drift_px);
      d.img.setPosition(d.x + dx, d.y + dy).setAlpha(k % 3 === 0 ? 0.35 : 1);
    });
  }
}

function centerOf(p: Pt[]): Pt {
  const x = p.reduce((s, q) => s + q[0], 0) / p.length, y = p.reduce((s, q) => s + q[1], 0) / p.length;
  return [Math.round(x), Math.round(y)];
}
