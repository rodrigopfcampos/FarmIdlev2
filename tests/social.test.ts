import { describe, expect, it } from 'vitest';
import { MISSIONS, SOCIAL } from '../src/data';
import { missionText } from '../src/farm/cards';

describe('amigos e visitas (config)', () => {
  it('recado só com emojis da lista, até 3', () => {
    expect(SOCIAL.notes.emojis.length).toBeGreaterThanOrEqual(6);
    expect(new Set(SOCIAL.notes.emojis).size).toBe(SOCIAL.notes.emojis.length);
    expect(SOCIAL.notes.max_emojis).toBe(3);
  });
  it('limites de ajuda do GDD: 10 dadas e 10 recebidas por dia, +10% por 1 h', () => {
    expect(SOCIAL.help.given_per_day).toBe(10);
    expect(SOCIAL.help.received_per_day).toBe(10);
    expect(SOCIAL.help.growth_pct).toBe(10);
    expect(SOCIAL.help.growth_minutes).toBe(60);
    expect(SOCIAL.help.xp_minutes_of_production).toBe(10);
  });
  it('missões de ajudar vizinhos no banco', () => {
    const ids = [...MISSIONS.bank.daily, ...MISSIONS.bank.weekly].filter((m) => m.metric === 'neighbors_helped').map((m) => m.id);
    expect(ids).toEqual(['d_ajudar', 'w_ajudar']);
    expect(missionText('d_ajudar', 2)).toBe('Ajude 2 vizinhos');
  });
  it('motivos de denúncia com texto', () => {
    for (const r of SOCIAL.report_reasons) expect(r.text_pt.length).toBeGreaterThan(3);
  });
});
