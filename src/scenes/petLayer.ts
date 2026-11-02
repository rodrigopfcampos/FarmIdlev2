// Pets v3 no mapa: os 3 pets que já chegaram andam no pátio de pedra na frente da Casa (2 quadros parados,
// um pulinho de 1 px ao andar, espelha para a direita). Achado pronto = balão de pixel em cima com o ícone
// (baú do Cachorro, raio do Gato, moeda do Papagaio). O clique no pet é tratado pela cena (hitTest).
import Phaser from 'phaser';
import { ANIM, type Pt } from '../data';
import { randomFreePoint } from '../farm/life';
import { petFindLeft } from '../farm/rules';
import { petSprite } from '../farm/art';
import { store } from '../farm/store';
import type { FarmState } from '../net/farmApi';

const P = ANIM.pets_map;
const depthOf = (y: number) => 1 + y / 10000;
const rnd = () => Math.random();
const between = ([a, b]: number[]) => a + rnd() * (b - a);
const EMOJI: Record<string, string> = { cachorro: '🐶', gato: '🐱', papagaio: '🦜' };

type PetWalker = {
  id: string; img: Phaser.GameObjects.Image | Phaser.GameObjects.Text; art: boolean;
  at: Pt; to: Pt | null; speed: number; until: number; frame: 1 | 2; nextFrame: number;
  bubble: Phaser.GameObjects.Container | null;
};

export class PetLayer {
  private pets = new Map<string, PetWalker>();
  private area = P.area as Pt[];

  constructor(private scene: Phaser.Scene, private calm: boolean) {}

  /** cria os pets que chegaram e tira os que não existem mais (visita mostra os da outra fazenda) */
  apply(s: FarmState): void {
    const ids = new Set(s.pets.map((p) => p.pet_id));
    for (const [id, w] of this.pets) if (!ids.has(id)) { w.img.destroy(); w.bubble?.destroy(); this.pets.delete(id); }
    for (const p of s.pets) if (!this.pets.has(p.pet_id)) this.pets.set(p.pet_id, this.spawn(p.pet_id));
    this.refreshBubbles(s);
  }

  private spawn(id: string): PetWalker {
    const at = randomFreePoint(this.area, [], rnd, 2);
    const key = petSprite(store.manifest, id, 1);
    const art = !!key && this.scene.textures.exists(key);
    const img = art
      ? this.scene.add.image(at[0], at[1], key!).setOrigin(0.5, 1)
      : this.scene.add.text(at[0], at[1], EMOJI[id] ?? '🐾', { fontSize: '14px' }).setOrigin(0.5, 1);
    img.setDepth(depthOf(at[1]));
    return { id, img, art, at, to: null, speed: between(P.speed_px_s), until: this.scene.time.now + between(P.idle_ms), frame: 1, nextFrame: 0, bubble: null };
  }

  /** balão do achado: aparece quando o achado fica pronto */
  refreshBubbles(s: FarmState): void {
    const now = store.clock.farmNow();
    for (const p of s.pets) {
      const w = this.pets.get(p.pet_id);
      if (!w) continue;
      const ready = !store.visit && petFindLeft(p.pet_id, p.find_t, now) === 0;
      if (ready && !w.bubble) w.bubble = this.bubble(p.pet_id);
      if (!ready && w.bubble) { w.bubble.destroy(); w.bubble = null; }
    }
  }

  private bubble(id: string): Phaser.GameObjects.Container {
    const g = this.scene.add.graphics();
    // balão quadrado de pixel: borda escura em degrau, fundo creme, ponta embaixo
    g.fillStyle(0x2b1d12).fillRect(-8, -18, 16, 14).fillRect(-7, -19, 14, 16).fillRect(-2, -4, 4, 2).fillRect(-1, -2, 2, 1);
    g.fillStyle(0xfff3d6).fillRect(-7, -17, 14, 12).fillRect(-1, -5, 2, 2);
    const parts: Phaser.GameObjects.GameObject[] = [g];
    const icon = (P.find_icon as Record<string, string>)[id];
    if (icon === 'energy') {
      const z = this.scene.add.graphics();
      // raio amarelo 6×9
      z.fillStyle(0xf2c230).fillRect(0, -16, 3, 2).fillRect(-1, -14, 3, 2).fillRect(-2, -12, 5, 2).fillRect(0, -10, 2, 2).fillRect(-1, -8, 2, 2);
      z.fillStyle(0x8a5a00).fillRect(3, -16, 1, 2).fillRect(3, -12, 1, 2);
      parts.push(z);
    } else if (icon && this.scene.textures.exists(icon)) {
      const im = this.scene.add.image(0, -11, icon).setOrigin(0.5);
      im.setScale(Math.min(10 / im.width, 10 / im.height));
      parts.push(im);
    }
    return this.scene.add.container(0, 0, parts).setDepth(25);
  }

  update(time: number, delta: number): void {
    for (const w of this.pets.values()) {
      // anda até o alvo ou fica parado um pouco; depois escolhe outro ponto do pátio
      if (!w.to && time >= w.until && !this.calm) w.to = randomFreePoint(this.area, [], rnd, 2);
      let moving = false;
      if (w.to) {
        const dx = w.to[0] - w.at[0], dy = w.to[1] - w.at[1], d = Math.hypot(dx, dy), step = (w.speed * delta) / 1000;
        if (d <= step) { w.at = w.to; w.to = null; w.until = time + between(P.idle_ms); }
        else { w.at = [w.at[0] + (dx / d) * step, w.at[1] + (dy / d) * step]; moving = true; if (w.art) (w.img as Phaser.GameObjects.Image).setFlipX(dx > 0); }
      }
      if (w.art && time >= w.nextFrame) {
        w.frame = w.frame === 1 ? 2 : 1; w.nextFrame = time + P.frame_ms;
        const key = petSprite(store.manifest, w.id, w.frame);
        if (key && this.scene.textures.exists(key)) (w.img as Phaser.GameObjects.Image).setTexture(key);
      }
      const hop = moving && w.frame === 2 ? P.hop_px : 0;
      const x = Math.round(w.at[0]), y = Math.round(w.at[1]);
      w.img.setPosition(x, y - hop).setDepth(depthOf(y));
      // balão balança 2 px para chamar atenção (parado no Modo calmo)
      const bob = this.calm ? 0 : Math.round(Math.sin((time / P.bubble_bob_ms) * Math.PI) * P.bubble_bob_px);
      w.bubble?.setPosition(x, y - 22 + bob);
    }
  }

  /** pet sob o ponteiro (o de cima ganha) */
  hit(x: number, y: number): { id: string; rect: number[] } | null {
    let best: { id: string; rect: number[]; y: number } | null = null;
    for (const w of this.pets.values()) {
      const [px, py] = w.at;
      const top = py - P.hit_h - (w.bubble ? 16 : 0);
      if (Math.abs(x - px) <= P.hit_half_w && y <= py + 2 && y >= top && (!best || py > best.y)) best = { id: w.id, rect: [px - P.hit_half_w, top, px + P.hit_half_w, py + 2], y: py };
    }
    return best ? { id: best.id, rect: best.rect } : null;
  }
}
