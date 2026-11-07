// Carrega o manifest das artes e os sprites que o mapa usa; gera as frutas das árvores na cor de cada fruta
// e as árvores adultas do pomar v3 (fruta vermelha da arte pintada na cor de cada fruta; sem fruta, folha).
import Phaser from 'phaser';
import { ANIM, CROP_LIST, FARM } from '../data';
import { isFruitPixel, recolor } from '../farm/life';
import { TREE_FOOT } from '../farm/art';
import { SIGN_SHADOW, SIGN_SHADOW_ALPHA, signPixels } from '../farm/signs';
import type { Manifest } from '../farm/art';
import { store } from '../farm/store';
import { bus } from '../core/bus';

const MAP_PREFIXES = ['crop_', 'tree_', 'debris_', 'building_', 'char_agricultor_', 'icon_', 'pet_', 'vehicle_', 'animal_', 'fish_', 'orchard_'];
const MAP_KEYS = ['ui_coin', 'lot_sign', 'result_chest']; // result_chest: baú do achado do Cachorro no balão

export class BootScene extends Phaser.Scene {
  constructor() { super('boot'); }

  preload(): void {
    this.load.json('manifest', 'assets/sprites/manifest.json');
    this.load.image('farm_base_map', 'assets/map/farm_base_map.png');
  }

  create(): void {
    const m = this.cache.json.get('manifest').sprites as Manifest;
    store.manifest = m;
    bus.emit('art:ready'); // a interface redesenha os ícones que dependem do manifest
    for (const k of Object.keys(m)) {
      if (m[k].frames || m[k].file.includes('/extras/')) continue;
      if (MAP_KEYS.includes(k) || MAP_PREFIXES.some((p) => k.startsWith(p))) this.load.image(k, `assets/${m[k].file}`);
    }
    // tiras de animação (veículos parados, cavalo, animais andando)
    for (const k of Object.keys(m)) {
      const strip = m[k];
      if (strip.frames && strip.frame_size && MAP_PREFIXES.some((p) => k.startsWith(p))) this.load.spritesheet(k, `assets/${strip.file}`, { frameWidth: strip.frame_size[0], frameHeight: strip.frame_size[1] });
    }
    this.load.once('complete', () => { this.makeFruitTextures(); this.makeOrchardTextures(); this.makeBits(); this.scene.start('farm'); });
    this.load.start();
  }

  /** pedacinhos desenhados por código para as animações (pixel a pixel) */
  private makeBits(): void {
    const g = this.make.graphics({}, false);
    g.fillStyle(0x3a2416, 1).fillRect(0, 0, 2, 2).fillStyle(0xd8b07a, 1).fillRect(0, 0, 1, 1);
    g.generateTexture('dirt_grain', 2, 2);
    // plaquinhas do mapa (cadeado = à venda; árvore = pomar)
    const k = ANIM.map_marks.sign_pixel;
    for (const icon of ['lock', 'tree'] as const) {
      const px = signPixels(icon);
      g.clear();
      px.forEach((row, y) => row.forEach((c, x) => { if (c !== null) g.fillStyle(c, y >= 17 && c === SIGN_SHADOW ? SIGN_SHADOW_ALPHA : 1).fillRect(x * k, y * k, k, k); }));
      g.generateTexture(`lot_sign_${icon}`, px[0].length * k, px.length * k);
    }
    g.destroy();
  }

  /** pomar v3: "orchard_adult_leaf" (sem fruta) e "orchard_adult_<fruta>" (fruta na cor dela), parada e com balanço
   *  ("orchard_adult_sway_leaf", "orchard_adult_sway_<fruta>", 9 quadros); também mede onde fica o pé de cada arte */
  private makeOrchardTextures(): void {
    const rgb = (hex: string) => { const c = Phaser.Display.Color.HexStringToColor(hex); return [c.red, c.green, c.blue] as [number, number, number]; };
    const colors = FARM.visual.fruit_hex as Record<string, string>;
    const tints: [string, [number, number, number]][] = [['leaf', rgb(ANIM.orchard.leaf_hex)],
      ...CROP_LIST.filter((c) => c.kind === 'orchard').map((c) => [c.id, rgb(colors[c.id] ?? '#c6191c')] as [string, [number, number, number]])];
    const make = (src: string, prefix: string) => {
      if (!this.textures.exists(src)) return;
      const img = this.textures.get(src).getSourceImage() as HTMLImageElement;
      const frames = (store.manifest[src]?.frames ?? 1) as number;
      const fw = img.width / frames, fh = img.height;
      for (const [id, base] of tints) {
        const c = document.createElement('canvas');
        c.width = img.width; c.height = img.height;
        const ctx = c.getContext('2d')!;
        ctx.drawImage(img, 0, 0);
        const d = ctx.getImageData(0, 0, c.width, c.height);
        for (let i = 0; i < d.data.length; i += 4) {
          if (!d.data[i + 3] || !isFruitPixel(d.data[i], d.data[i + 1], d.data[i + 2])) continue;
          const [r, g, b] = recolor(d.data[i], base);
          d.data[i] = r; d.data[i + 1] = g; d.data[i + 2] = b;
        }
        ctx.putImageData(d, 0, 0);
        const key = `${prefix}_${id}`;
        const tex = this.textures.addCanvas(key, c)!;
        if (frames > 1) for (let f = 0; f < frames; f++) tex.add(f, 0, f * fw, 0, fw, fh);
      }
    };
    make('orchard_adult', 'orchard_adult');
    make('orchard_adult_sway', 'orchard_adult_sway');
    // a árvore jovem também tem fruta na arte nova: fica na cor da fruta plantada
    make('orchard_young', 'orchard_young');
    make('orchard_young_sway', 'orchard_young_sway');
    // pé de cada arte de árvore: última linha com pixel no 1º quadro (a vaga fica no pé do tronco)
    for (const k of ['orchard_sprout', 'orchard_young', 'orchard_adult', 'orchard_sprout_sway', 'orchard_young_sway', 'orchard_adult_sway']) {
      if (!this.textures.exists(k)) continue;
      const img = this.textures.get(k).getSourceImage() as HTMLImageElement;
      const fw = img.width / ((store.manifest[k]?.frames ?? 1) as number), fh = img.height;
      const c = document.createElement('canvas'); c.width = fw; c.height = fh;
      const ctx = c.getContext('2d')!; ctx.drawImage(img, 0, 0, fw, fh, 0, 0, fw, fh);
      const d = ctx.getImageData(0, 0, fw, fh).data;
      let foot = fh - 1;
      for (let y = fh - 1; y >= 0; y--) { let any = false; for (let x = 0; x < fw; x++) if (d[(y * fw + x) * 4 + 3]) { any = true; break; } if (any) { foot = y; break; } }
      TREE_FOOT[k] = (foot + 1) / fh;
    }
  }

  /** frutas 4×4 (base, brilho e sombra) por cima da árvore adulta: uma textura por fruta */
  private makeFruitTextures(): void {
    const pattern = ['.XX.', 'XHXX', 'XXXD', '.DD.'];
    const dots = FARM.visual.fruit_dots as unknown as Record<string, number[][]>;
    const colors = FARM.visual.fruit_hex as Record<string, string>;
    for (const c of CROP_LIST) {
      if (c.kind !== 'orchard') continue;
      const base = Phaser.Display.Color.HexStringToColor(colors[c.id] ?? '#c6191c');
      const shade = (k: number) => Phaser.Display.Color.GetColor(Math.min(255, base.red * k), Math.min(255, base.green * k), Math.min(255, base.blue * k));
      const ink: Record<string, number> = { X: base.color, H: shade(1.35), D: shade(0.65) };
      const g = this.make.graphics({}, false);
      for (const [cx, cy] of dots[c.tree_base ?? 'leafy'] ?? []) {
        pattern.forEach((row, j) => [...row].forEach((ch, i) => {
          if (ch === '.') return;
          g.fillStyle(ink[ch], 1).fillRect(cx - 2 + i, cy - 2 + j, 1, 1);
        }));
      }
      g.generateTexture(`fruit_${c.id}`, 48, 64);
      g.destroy();
    }
  }
}
