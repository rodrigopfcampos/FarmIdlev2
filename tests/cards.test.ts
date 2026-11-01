import { describe, expect, it } from 'vitest';
import { armoryLines, armoryStatus, buffLines, CARD_LIST, cardArt, cardDuration, handSlots, lifeText, missionProgress, missionText, pityLeft, vehicleLook } from '../src/farm/cards';
import manifest from '../public/assets/sprites/manifest.json';
import { CARDS, MISSIONS } from '../src/data';

describe('cartas no cliente', () => {
  it('as 20 cartas têm efeito em 5 raridades, bônus do álbum com texto e a arte de cada raridade', () => {
    expect(CARD_LIST).toHaveLength(20);
    const sprites = (manifest as { sprites: Record<string, unknown> }).sprites;
    for (const c of CARD_LIST) {
      for (const r of ['common', 'uncommon', 'rare', 'legendary', 'mythic']) {
        const lines = buffLines(c.id, r);
        expect(lines.length).toBeGreaterThan(0);
        for (const l of lines) expect(l).not.toMatch(/_pct|_pts/); // nenhum efeito sem texto
        expect(sprites[cardArt(c.id, r)]).toBeTruthy();
      }
      for (const l of [...armoryLines(c.id, 'partial'), ...armoryLines(c.id, 'complete')]) expect(l).not.toMatch(/_pct|_pts/);
    }
  });
  it('vida na mão por raridade e tempo em texto', () => {
    expect(cardDuration('common')).toBe('2 dias');
    expect(cardDuration('rare')).toBe('3 dias');
    expect(cardDuration('mythic')).toBe('4 dias');
    expect(lifeText(86400 + 4 * 3600)).toBe('1 d 4 h');
    expect(lifeText(3 * 3600 + 20 * 60)).toBe('3 h 20');
    expect(lifeText(12 * 60)).toBe('12 min');
  });
  it('mão de 3, 4 no nível 15 e 5 no 30; veículo da carta por raridade', () => {
    expect([handSlots(1), handSlots(14), handSlots(15), handSlots(29), handSlots(30), handSlots(50)]).toEqual([3, 3, 4, 4, 5, 5]);
    expect(vehicleLook('common')).toBe('carroca');
    expect(vehicleLook('mythic')).toBe('caminhao');
  });
  it('Armory: parcial com Comum+Incomum+Raro, completo com as 5', () => {
    const a = [{ card_id: 'sol', rarity: 'common' }, { card_id: 'sol', rarity: 'uncommon' }];
    expect(armoryStatus(a, 'sol').level).toBe('none');
    a.push({ card_id: 'sol', rarity: 'rare' });
    expect(armoryStatus(a, 'sol').level).toBe('partial');
    a.push({ card_id: 'sol', rarity: 'legendary' }, { card_id: 'sol', rarity: 'mythic' });
    expect(armoryStatus(a, 'sol').level).toBe('complete');
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
