// Carrega o manifest das artes e os sprites que o mapa usa; gera as frutas das árvores na cor de cada fruta.
import Phaser from 'phaser';
import { CROP_LIST, FARM } from '../data';
import type { Manifest } from '../farm/art';
import { store } from '../farm/store';
import { bus } from '../core/bus';

const MAP_PREFIXES = ['crop_', 'tree_', 'debris_', 'building_', 'char_agricultor_', 'icon_', 'pet_', 'vehicle_', 'animal_'];
const MAP_KEYS = ['ui_coin', 'lot_sign'];

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
    for (const v of ['carroca', 'carro', 'picape', 'caminhao']) {
      const strip = m[`vehicle_${v}_idle`];
      if (strip) this.load.spritesheet(`vehicle_${v}_idle`, `assets/${strip.file}`, { frameWidth: strip.frame_size![0], frameHeight: strip.frame_size![1] });
    }
    this.load.once('complete', () => { this.makeFruitTextures(); this.scene.start('farm'); });
    this.load.start();
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
