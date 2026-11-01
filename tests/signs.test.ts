import { describe, expect, it } from 'vitest';
import { signPixels } from '../src/farm/signs';

describe('plaquinhas do mapa', () => {
  it('cadeado e árvore têm a mesma tábua 18 × 20 e ícones diferentes', () => {
    const a = signPixels('lock'), b = signPixels('tree');
    expect(a.length).toBe(20);
    expect(a.every((r) => r.length === 18)).toBe(true);
    expect(a[0]).toEqual(b[0]);
    expect(a[4]).not.toEqual(b[4]);
  });
});
