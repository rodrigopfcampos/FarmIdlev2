import { describe, expect, it } from 'vitest';
import { armoryLines, armoryStatus, buffLines, CARD_LIST, cardArt, cardUses, handSlots, usesOnText, usesText, missionProgress, missionText, pityLeft, vehicleLook } from '../src/farm/cards';
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
  it('usos por raridade (Comum 1 … Mítica 5), em texto e onde gasta', () => {
    expect(['common', 'uncommon', 'rare', 'legendary', 'mythic'].map(cardUses)).toEqual([1, 2, 3, 4, 5]);
    expect(usesText(1)).toBe('1 uso');
    expect(usesText(3)).toBe('3 usos');
    expect(usesText(0.875)).toBe('0,9 uso');
    expect(usesText(0.01)).toBe('0,1 uso');
    expect(usesText(0)).toBe('0 uso');
    expect(usesOnText('sol')).toBe('lavoura e pomar');
    expect(usesOnText('prancheta')).toBe('expedições');
    expect(usesOnText('coruja')).toBe('qualquer coleta');
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
