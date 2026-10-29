import { describe, expect, it } from 'vitest';
import { CROP_LIST, VILLAGE } from '../src/data';

describe('Vila (config)', () => {
  it('cada faixa de pedidos tem cultivos de lavoura para sortear', () => {
    for (const [lo, hi] of VILLAGE.encomenda.requested_tiers) {
      const pool = CROP_LIST.filter((c) => c.unlock_level >= lo && c.unlock_level <= hi && VILLAGE.encomenda.requested_kinds.includes(c.kind));
      expect(pool.length).toBeGreaterThan(0);
    }
  });
  it('prêmio da Encomenda: no máximo 2 cartas por semana a mais', () => {
    const r = VILLAGE.encomenda.reward;
    expect(r.card_if_goal_and_qualified + r.card_if_top).toBeLessThanOrEqual(2);
    expect(VILLAGE.encomenda.min_points_to_qualify).toBeGreaterThan(0);
  });
  it('Estrelas: sem Mítico na compra direta, tudo custa ouro também, limite por semana', () => {
    expect(Object.keys(VILLAGE.stars.seed.rarities)).not.toContain('mythic');
    expect(VILLAGE.stars.pack.gold_R_ratio).toBeGreaterThan(0);
    for (const p of Object.values(VILLAGE.stars.seed.rarities)) expect(p.gold_R_ratio).toBeGreaterThan(0);
    expect(VILLAGE.stars.pack.per_week).toBeGreaterThan(0);
    expect(VILLAGE.stars.unlock_level).toBe(50);
  });
});
