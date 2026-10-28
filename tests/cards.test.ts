import { describe, expect, it } from 'vitest';
import { armoryLines, armoryStatus, buffDuration, buffLines, CARD_LIST, cardFaceLines, missionProgress, missionText, pityLeft } from '../src/farm/cards';
import { CARDS, MISSIONS } from '../src/data';

describe('cartas no cliente', () => {
  it('as 10 cartas têm buff em 5 raridades e bônus do Armory com texto', () => {
    expect(CARD_LIST).toHaveLength(10);
    for (const c of CARD_LIST) {
      for (const r of ['common', 'uncommon', 'rare', 'legendary', 'mythic']) {
        const lines = buffLines(c.id, r);
        expect(lines.length).toBeGreaterThan(0);
        for (const l of lines) expect(l).not.toMatch(/_pct|_pts/); // nenhum efeito sem texto
      }
      for (const l of [...armoryLines(c.id, 'partial'), ...armoryLines(c.id, 'complete')]) expect(l).not.toMatch(/_pct|_pts/);
    }
  });
  it('a carta mostra o efeito, não o nome', () => {
    expect(cardFaceLines('cesta_dourada', 'common')).toEqual(['+10% chance de Colheita Dourada']);
    expect(cardFaceLines('estrada_livre', 'common')).toEqual(['+3 de sucesso', '−10% de perda']); // efeito 0 não aparece
    for (const c of CARD_LIST) for (const r of ['common', 'uncommon', 'rare', 'legendary', 'mythic']) {
      const lines = cardFaceLines(c.id, r);
      expect(lines.length).toBeGreaterThan(0);
      for (const l of lines) { expect(l).not.toMatch(/_pct|_pts/); expect(l).not.toContain(c.name_pt); }
    }
  });
  it('duração do buff por raridade', () => {
    expect(buffDuration('common')).toBe('1 h');
    expect(buffDuration('uncommon')).toBe('1 h 20');
    expect(buffDuration('mythic')).toBe('2 h 30');
  });
  it('Armory: parcial com Comum+Incomum+Raro, completo com as 5', () => {
    const a = [{ card_id: 'sol_de_verao', rarity: 'common' }, { card_id: 'sol_de_verao', rarity: 'uncommon' }];
    expect(armoryStatus(a, 'sol_de_verao').level).toBe('none');
    a.push({ card_id: 'sol_de_verao', rarity: 'rare' });
    expect(armoryStatus(a, 'sol_de_verao').level).toBe('partial');
    a.push({ card_id: 'sol_de_verao', rarity: 'legendary' }, { card_id: 'sol_de_verao', rarity: 'mythic' });
    expect(armoryStatus(a, 'sol_de_verao').level).toBe('complete');
    expect(armoryStatus(a, 'ampulheta').level).toBe('none');
  });
  it('missões: texto com a meta e progresso', () => {
    for (const m of [...MISSIONS.bank.daily, ...MISSIONS.bank.weekly]) expect(missionText(m.id, 3)).not.toContain('{n}');
    expect(missionText('d_expedicoes', 2)).toBe('Envie 2 expedições');
    expect(missionProgress('field3_hours', 0.5, 2)).toEqual({ pct: 0.25, text: '0,5 h de 2 h' });
    expect(missionProgress('stall_gold', 5000, 2500).pct).toBe(1);
  });
  it('garantia: quanto falta', () => {
    const t = CARDS.gacha.pity_thresholds;
    expect(pityLeft({ rare: 3, legendary: 10, mythic: 100 })).toEqual({ rare: t.rare_or_better - 3, legendary: t.legendary_or_better - 10, mythic: t.mythic - 100 });
  });
});
