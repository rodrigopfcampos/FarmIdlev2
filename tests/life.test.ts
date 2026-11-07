// Vida no mapa v3 (só visual): pontos livres nos pastos e no lago, peixes por nível, pomar e cor da fruta.
import { describe, expect, it } from 'vitest';
import { ANIM, ANIMAL_RULES, ANIMALS, LOTS, type Pt } from '../src/data';
import { clearPath, isFree, isFruitPixel, orchardLook, randomFreePoint, recolor, walkSpriteFor } from '../src/farm/life';

const seq = (() => { let s = 7; return () => ((s = (s * 16807) % 2147483647) / 2147483647); })();

describe('mapa v3', () => {
  it('tem 20 lavouras, 6 pomares, Celeiro em cima (C1) e Galinheiro embaixo (C2), sem o A9', () => {
    expect(LOTS.filter((l) => l.type === 'lavoura').length).toBe(20);
    expect(LOTS.filter((l) => l.type === 'pomar').length).toBe(6);
    expect(LOTS.find((l) => l.id === 'A9')).toBeUndefined();
    expect(LOTS.find((l) => l.id === 'C1')!.type).toBe('pasto_celeiro');
    expect(LOTS.find((l) => l.id === 'C2')!.type).toBe('pasto_galinheiro');
  });
  it('animais sorteiam pontos dentro do pasto e fora do prédio desenhado', () => {
    for (const id of ['C1', 'C2']) {
      const w = (LOTS.find((l) => l.id === id) as any).wander as { polygon: Pt[]; avoid: number[][] };
      for (let k = 0; k < 50; k++) {
        const [x, y] = randomFreePoint(w.polygon, w.avoid, seq);
        expect(isFree(x, y, w.polygon, w.avoid)).toBe(true);
      }
    }
  });
  it('peixe não atravessa o píer', () => {
    const w = (LOTS.find((l) => l.id === 'L') as any).water as { polygon: Pt[]; avoid: number[][] };
    const [x0, y0, x1, y1] = w.avoid[0];
    expect(clearPath([x0 - 20, (y0 + y1) / 2], [x1 + 20, (y0 + y1) / 2], w.polygon, w.avoid)).toBe(false);
  });
  it('peixes do Lago (04/11): 5 espécies com arte e o Pescador como especialista', () => {
    const fish = ANIMALS.filter((a) => a.house === 'lago');
    expect(fish).toHaveLength(5);
    expect(fish.every((f) => (f as { is_fish?: boolean }).is_fish && /^fish_\d$/.test(f.product.art))).toBe(true);
    expect(ANIMAL_RULES.collector_efficiency.specialist_by_house.lago).toBe('pescador');
  });
  it('os 10 animais têm cada um a sua arte andando', () => {
    expect(walkSpriteFor('vaca')).toBe('animal_walk_cow');
    expect(walkSpriteFor('pato')).toBe('animal_walk_duck');
    expect(walkSpriteFor('peru')).toBe('animal_walk_turkey');
    expect(walkSpriteFor('ovelha')).toBe('animal_walk_sheep');
    expect(new Set(['galinha', 'coelho', 'vaca', 'pato', 'ovelha', 'porco', 'cabra', 'ganso', 'peru', 'alpaca'].map(walkSpriteFor)).size).toBe(10);
  });
  it('pomar: cova, broto, jovem, adulta e com fruta', () => {
    const t = (planted: number, ready: number) => ({ lot_id: 'P1', slot: 1, fruit_id: 'maca', planted_at: planted, ready_at: ready });
    expect(orchardLook(undefined, 0, true)).toBe('pit');
    expect(orchardLook(undefined, 0, false)).toBe('empty');
    expect(orchardLook(t(0, 1000), 100, true)).toBe('sprout');
    expect(orchardLook(t(0, 1000), 400, true)).toBe('young');
    expect(orchardLook(t(0, 1000), 700, true)).toBe('adult');
    expect(orchardLook(t(0, 1000), 900, true)).toBe('fruit');
  });
  it('fruta vermelha vira a cor da fruta; tronco marrom e folhas ficam', () => {
    expect(isFruitPixel(182, 14, 49)).toBe(true);
    expect(isFruitPixel(244, 98, 100)).toBe(true);
    expect(isFruitPixel(135, 61, 41)).toBe(false); // tronco
    expect(isFruitPixel(73, 125, 51)).toBe(false); // folha
    expect(isFruitPixel(200, 40, 40)).toBe(true); // maçã da arte nova
    expect(isFruitPixel(160, 90, 60)).toBe(false); // tronco da arte nova
    expect(recolor(ANIM.orchard.fruit_ref_red, [10, 20, 30])).toEqual([10, 20, 30]);
  });
});
