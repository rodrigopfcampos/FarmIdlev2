// Carrega o manifest das artes e só os sprites que a fase atual usa.
import Phaser from 'phaser';
import { UNLOCKED_CROPS } from '../data';
import type { Manifest } from '../farm/art';
import { store } from '../farm/store';

export class BootScene extends Phaser.Scene {
  constructor() { super('boot'); }

  preload(): void {
    this.load.json('manifest', 'assets/sprites/manifest.json');
    this.load.image('farm_base_map', 'assets/map/farm_base_map.png');
  }

  create(): void {
    const m = this.cache.json.get('manifest').sprites as Manifest;
    store.manifest = m;
    const keys = new Set<string>(['crop_generic_stage1', 'crop_generic_stage2', 'crop_generic_stage3', 'ui_coin']);
    for (const c of UNLOCKED_CROPS) for (const k of [`crop_${c.id}_stage1`, `crop_${c.id}_stage2`, `crop_${c.id}_stage3`, `crop_${c.id}_ready`, `icon_${c.id}`]) if (m[k]) keys.add(k);
    for (const k of Object.keys(m)) if (k.startsWith('char_agricultor_')) keys.add(k);
    for (const k of keys) this.load.image(k, `assets/${m[k].file}`);
    const cart = m.vehicle_carroca_idle;
    this.load.spritesheet('vehicle_carroca_idle', `assets/${cart.file}`, { frameWidth: cart.frame_size![0], frameHeight: cart.frame_size![1] });
    this.load.once('complete', () => this.scene.start('farm'));
    this.load.start();
  }
}
