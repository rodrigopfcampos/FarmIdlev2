import { describe, expect, it } from 'vitest';
import { ANTICHEAT } from '../src/data';

describe('antitrapaça (config)', () => {
  it('todas as regras da GDD seção 12 que não dependem do mercado estão na config', () => {
    for (const r of ['income', 'progress', 'cards', 'luck', 'robot', 'refusals', 'minigame_robot', 'clock', 'timezone']) {
      expect(ANTICHEAT.rules).toHaveProperty(r);
    }
  });
  it('limites da GDD: revisão a partir de 70, congela mercado a partir de 90, sessão de 30 min', () => {
    expect(ANTICHEAT.review_from).toBe(70);
    expect(ANTICHEAT.freeze_market_from).toBe(90);
    expect(ANTICHEAT.admin_session_minutes).toBe(30);
  });
  it('o dedicado da simulação sobe de nível com o tempo (pontos em ordem)', () => {
    const pts = ANTICHEAT.rules.progress.dedicated_level_days;
    for (let i = 1; i < pts.length; i++) { expect(pts[i][0]).toBeGreaterThan(pts[i - 1][0]); expect(pts[i][1]).toBeGreaterThan(pts[i - 1][1]); }
  });
});
