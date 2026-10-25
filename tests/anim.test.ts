// Animações: tempo por quadro, tabelas em pixels inteiros (skill animacao-vif)
import { describe, expect, it } from 'vitest';
import anim from '../config/animations.json';
import { frameAt, phaseOf, tableAt } from '../src/anim/frames';

describe('tempo por quadro', () => {
  const f = [{ ms: 100 }, { ms: 50 }, { ms: 200 }];
  it('acha o quadro certo nos limites e volta no loop', () => {
    expect(frameAt(f, 0)).toBe(0);
    expect(frameAt(f, 99)).toBe(0);
    expect(frameAt(f, 100)).toBe(1);
    expect(frameAt(f, 149)).toBe(1);
    expect(frameAt(f, 150)).toBe(2);
    expect(frameAt(f, 350)).toBe(0);
  });
  it('sem loop para no último quadro', () => {
    expect(frameAt(f, 10_000, false)).toBe(2);
    expect(frameAt(f, -5, false)).toBe(0);
  });
  it('tabela por passos e fase fixa por posição', () => {
    expect(tableAt([0, 1, 2], 70, 0)).toBe(0);
    expect(tableAt([0, 1, 2], 70, 140)).toBe(2);
    expect(tableAt([0, 1, 2], 70, 210)).toBe(0);
    expect(phaseOf(10, 20)).toBe(phaseOf(10, 20));
    expect(phaseOf(10, 20)).not.toBe(phaseOf(11, 20));
  });
});

describe('fichas em config/animations.json', () => {
  it('só pixels inteiros e tempos positivos', () => {
    const ints = (a: number[]) => a.every((v) => Number.isInteger(v));
    expect(ints(anim.crop_sway.tip_px)).toBe(true);
    expect(ints(anim.crop_ready_hop.up_px)).toBe(true);
    expect(ints(anim.crop_grow.dirt_up_px)).toBe(true);
    expect(anim.crop_grow.frames.every((fr) => Number.isInteger(fr.up_px) && fr.ms > 0)).toBe(true);
    expect(anim.crop_sway.ms).toBeGreaterThan(0);
    expect(anim.crop_ready_hop.ms).toBeGreaterThan(0);
  });
  it('o pulinho do maduro tem pausa longa (mais parado que pulando)', () => {
    const still = anim.crop_ready_hop.up_px.filter((v) => v === 0).length;
    expect(still).toBeGreaterThan(anim.crop_ready_hop.up_px.length / 2);
  });
});
