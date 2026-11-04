// Pets v3 no mapa: os pets que já chegaram andam no pátio de pedra na frente da Casa.
// Arte nova (Cachorro e Papagaio): 5 quadros de andar (3×2, 32×32, olham para a esquerda) e um quadro parado fixo.
// O Gato usa a arte antiga (2 quadros) até chegar a dele: parado fica num quadro só; andando alterna com um pulinho.
// Passo quase de lado (nunca anda "de costas"), espelha para a direita, cada pet com seu espaço (não se amontoam).
// Achado pronto = balão de pixel em cima com o ícone (baú do Cachorro, raio do Gato, moeda do Papagaio).
// O clique no pet é tratado pela cena (hitTest).
import Phaser from 'phaser';
import { ANIM, type Pt } from '../data';
import { clearPath, randomFreePoint } from '../farm/life';
import { petFindLeft } from '../farm/rules';
import { petSprite } from '../farm/art';
import { store } from '../farm/store';
import type { FarmState } from '../net/farmApi';

const P = ANIM.pets_map;
type PetArt = { walk?: string; idle?: string; idle_frame?: number; scale: number; walk_fps?: number; old_idle?: boolean };
const ART = P.sprites as Record<string, PetArt>;
const depthOf = (y: number) => 1 + y / 10000;
const rnd = () => Math.random();
const between = ([a, b]: number[]) => a + rnd() * (b - a);
const EMOJI: Record<string, string> = { cachorro: '🐶', gato: '🐱', papagaio: '🦜' };

type PetWalker = {
  id: string; img: Phaser.GameObjects.Sprite | Phaser.GameObjects.Text;
  mode: 'sheet' | 'old' | 'emoji'; art: PetArt;
  at: Pt; to: Pt | null; speed: number; until: number; r: number; height: number;
  oldFrame: 1 | 2; nextFrame: number;
  bubble: Phaser.GameObjects.Container | null;
};

export class PetLayer {
  private pets = new Map<string, PetWalker>();
  private area = P.area as Pt[];

  constructor(private scene: Phaser.Scene, private calm: boolean) {
    // animação de andar de cada pet com arte nova
    for (const a of Object.values(ART)) {
      if (!a.walk || !scene.textures.exists(a.walk) || scene.anims.exists(`${a.walk}_walk`)) continue;
      scene.anims.create({ key: `${a.walk}_walk`, frames: scene.anims.generateFrameNumbers(a.walk, { start: 0, end: 4 }), frameRate: a.walk_fps ?? 8, repeat: -1 });
    }
  }

  /** cria os pets que chegaram e tira os que não existem mais (visita mostra os da outra fazenda) */
  apply(s: FarmState): void {
    const ids = new Set(s.pets.map((p) => p.pet_id));
    for (const [id, w] of this.pets) if (!ids.has(id)) { w.img.destroy(); w.bubble?.destroy(); this.pets.delete(id); }
    for (const p of s.pets) if (!this.pets.has(p.pet_id)) this.pets.set(p.pet_id, this.spawn(p.pet_id));
    this.refreshBubbles(s);
  }

  private spawn(id: string): PetWalker {
    const art = ART[id] ?? { scale: 1, old_idle: true };
    const r = P.personal_space_px * art.scale;
    let at = randomFreePoint(this.area, [], rnd, 2);
    for (let k = 0; k < 40 && this.crowded(at, r, null); k++) at = randomFreePoint(this.area, [], rnd, 2);
    let img: PetWalker['img'];
    let mode: PetWalker['mode'];
    if (art.walk && this.scene.textures.exists(art.walk)) {
      mode = 'sheet';
      img = this.scene.add.sprite(at[0], at[1], art.walk, art.idle_frame ?? 0).setOrigin(0.5, 1).setScale(art.scale);
    } else if (petSprite(store.manifest, id, 1) && this.scene.textures.exists(petSprite(store.manifest, id, 1)!)) {
      mode = 'old';
      img = this.scene.add.sprite(at[0], at[1], petSprite(store.manifest, id, 1)!).setOrigin(0.5, 1).setScale(art.scale);
    } else {
      mode = 'emoji';
      img = this.scene.add.text(at[0], at[1], EMOJI[id] ?? '🐾', { fontSize: '14px' }).setOrigin(0.5, 1);
    }
    const w: PetWalker = { id, img, mode, art, at, to: null, speed: between(P.speed_px_s), until: this.scene.time.now + between(P.idle_ms), r,
      height: img.displayHeight, oldFrame: 1, nextFrame: 0, bubble: null };
    if (img instanceof Phaser.GameObjects.Sprite) img.setFlipX(rnd() < 0.5);
    this.still(w);
    img.setDepth(depthOf(at[1]));
    return w;
  }

  /** parado: um quadro fixo (sem mexer as pernas) */
  private still(w: PetWalker): void {
    if (!(w.img instanceof Phaser.GameObjects.Sprite)) return;
    w.img.stop();
    if (w.mode === 'sheet') {
      if (w.art.idle && this.scene.textures.exists(w.art.idle)) w.img.setTexture(w.art.idle);
      else w.img.setTexture(w.art.walk!, w.art.idle_frame ?? 0);
    } else if (w.mode === 'old') {
      w.oldFrame = 1;
      w.img.setTexture(petSprite(store.manifest, w.id, 1)!);
    }
  }

  private walk(w: PetWalker): void {
    if (!(w.img instanceof Phaser.GameObjects.Sprite)) return;
    w.img.setFlipX(w.to![0] > w.at[0]); // a arte olha para a esquerda
    if (w.mode === 'sheet') w.img.setTexture(w.art.walk!).play(`${w.art.walk}_walk`, true);
  }

  /** p invade o espaço de outro pet (elipse achatada, como o chão visto de lado)? */
  private crowded(p: Pt, r: number, self: PetWalker | null): boolean {
    for (const o of this.pets.values()) {
      if (o === self) continue;
      const gap = r + o.r;
      for (const q of o.to ? [o.at, o.to] : [o.at]) {
        const dx = p[0] - q[0], dy = (p[1] - q[1]) * P.personal_space_dy_weight;
        if (dx * dx + dy * dy < gap * gap) return true;
      }
    }
    return false;
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
      // parado um pouco; depois um passo quase de lado que não sai do pátio nem entra no espaço de outro pet
      if (!w.to && time >= w.until && !this.calm) {
        for (let k = 0; k < 16 && !w.to; k++) {
          const len = between(P.step_px ?? [16, 44]) * (k < 8 ? 1 : 0.5), side = rnd() < 0.5 ? -1 : 1; // sem lugar: passo mais curto
          const p: Pt = [Math.round(w.at[0] + side * len), Math.round(w.at[1] + (rnd() * 2 - 1) * len * P.max_step_slope)];
          if (clearPath(w.at, p, this.area, [], 2) && !this.crowded(p, w.r, w)) w.to = p;
        }
        if (w.to) this.walk(w);
        else w.until = time + between(P.idle_ms);
      }
      let moving = false;
      if (w.to) {
        const dx = w.to[0] - w.at[0], dy = w.to[1] - w.at[1], d = Math.hypot(dx, dy), step = (w.speed * delta) / 1000;
        if (d <= step) { w.at = w.to; w.to = null; w.until = time + between(P.idle_ms); this.still(w); }
        else { w.at = [w.at[0] + (dx / d) * step, w.at[1] + (dy / d) * step]; moving = true; }
      }
      // arte antiga: alterna os 2 quadros só enquanto anda, com um pulinho
      if (w.mode === 'old' && moving && time >= w.nextFrame && w.img instanceof Phaser.GameObjects.Sprite) {
        w.oldFrame = w.oldFrame === 1 ? 2 : 1; w.nextFrame = time + P.frame_ms;
        const key = petSprite(store.manifest, w.id, w.oldFrame);
        if (key && this.scene.textures.exists(key)) w.img.setTexture(key);
      }
      const hop = w.mode === 'old' && moving && w.oldFrame === 2 ? P.hop_px : 0;
      const x = Math.round(w.at[0]), y = Math.round(w.at[1]);
      w.img.setPosition(x, y - hop).setDepth(depthOf(y));
      // balão balança 2 px para chamar atenção (parado no Modo calmo)
      const bob = this.calm ? 0 : Math.round(Math.sin((time / P.bubble_bob_ms) * Math.PI) * P.bubble_bob_px);
      w.bubble?.setPosition(x, y - Math.round(w.height) - 2 + bob);
    }
  }

  /** pet sob o ponteiro (o de cima ganha) */
  hit(x: number, y: number): { id: string; rect: number[] } | null {
    let best: { id: string; rect: number[]; y: number } | null = null;
    for (const w of this.pets.values()) {
      const [px, py] = w.at;
      const half = Math.max(P.hit_half_w, w.img.displayWidth / 2);
      const top = py - Math.max(P.hit_h, w.height) - (w.bubble ? 16 : 0);
      if (Math.abs(x - px) <= half && y <= py + 2 && y >= top && (!best || py > best.y)) best = { id: w.id, rect: [px - half, top, px + half, py + 2], y: py };
    }
    return best ? { id: best.id, rect: best.rect } : null;
  }
}
