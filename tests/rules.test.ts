// Regras da progressão do lado do cliente (o servidor tem os testes em supabase/tests/phase2_test.sql).
import { describe, expect, it } from 'vitest';
import { CROPS, PURCHASES } from '../src/data';
import { cleanupMinutes, isNeighbor, lotOffer, plotCrops, plotLook, orchardFruits, tendCount, treeLook, xpProgress } from '../src/farm/rules';

describe('compra de lotes', () => {
  const start = new Set(['A1']);
  it('1ª compra: lote vizinho do A1 no nível 2 pelo preço da tabela', () => {
    const o = lotOffer('A3', start, 2, 0, 1_000_000)!;
    expect(o.n).toBe(1);
    expect(o.cost).toBe(PURCHASES[0].cost);
    expect(o.needLevel).toBe(2);
    expect(o.problems).toEqual([]);
  });
  it('lote que não divide lado com um lote seu é recusado', () => {
    expect(isNeighbor('A2', start)).toBe(false);
    expect(lotOffer('A2', start, 50, 0, 1e9)!.problems).toContain('vizinho');
  });
  it('Galinheiro e Celeiro podem ser comprados de longe, Lago não', () => {
    expect(isNeighbor('C1', start)).toBe(true);
    expect(isNeighbor('C2', start)).toBe(true);
    expect(isNeighbor('L', start)).toBe(false);
  });
  it('nível: o maior entre o da compra e o piso do tipo (pomar 10)', () => {
    const o = lotOffer('P1', start, 2, 0, 1e9)!;
    expect(o.needLevel).toBe(10);
    expect(o.problems).toEqual(['nivel']);
  });
  it('da 20ª compra em diante precisa de Escritura', () => {
    const owned = new Set(['A1', 'A3', 'A4', 'A2', 'A5', 'A6', 'A7', 'A8', 'A9', 'A10', 'A11', 'A12', 'A13', 'A14', 'A15', 'A16', 'A17', 'P2', 'P3', 'P1']);
    const o = lotOffer('P5', owned, 50, 0, 1e12)!;
    expect(o.n).toBe(20);
    expect(o.needsDeed).toBe(true);
    expect(o.problems).toEqual(['escritura']);
    expect(lotOffer('P5', owned, 50, 1, 1e12)!.problems).toEqual([]);
  });
  it('limpeza: 1 h + 12 min × n, em dobro sem Ferreiro', () => {
    expect(cleanupMinutes(1, true)).toBe(72);
    expect(cleanupMinutes(1)).toBe(144);
  });
  it('lote seu não aparece à venda', () => {
    expect(lotOffer('A1', start, 50, 0, 1e9)).toBeNull();
  });
});

describe('cultivos por nível', () => {
  it('nível 1: só Alface e Cenoura; os próximos aparecem bloqueados', () => {
    const { open, next } = plotCrops(1);
    expect(open.map((c) => c.id)).toEqual(['alface', 'cenoura']);
    expect(next[0].id).toBe('batata');
  });
  it('frutas do pomar não entram na lista de canteiro', () => {
    expect(plotCrops(50).open.some((c) => c.kind === 'orchard')).toBe(false);
    expect(orchardFruits(10).open.map((c) => c.id)).toEqual(['maca']);
  });
});

describe('árvore do pomar', () => {
  const g = CROPS.maca.grow_minutes * 60, r = (CROPS.maca.regrow_minutes ?? 0) * 60;
  it('muda no começo, adulta depois e com fruta perto da colheita', () => {
    const t = { lot_id: 'P1', slot: 1, fruit_id: 'maca', planted_at: 0, ready_at: g };
    expect(treeLook(t, g * 0.2)).toBe('sapling');
    expect(treeLook(t, g * 0.6)).toBe('adult');
    expect(treeLook(t, g * 0.9)).toBe('fruit');
  });
  it('depois da 1ª colheita nunca volta a ser muda', () => {
    const t = { lot_id: 'P1', slot: 1, fruit_id: 'maca', planted_at: 0, ready_at: g + r };
    expect(treeLook(t, g + 1)).toBe('adult');
    expect(treeLook(t, g + r * 0.9)).toBe('fruit');
  });
  it('vaga vazia', () => {
    expect(treeLook({ lot_id: 'P1', slot: 1, fruit_id: null, planted_at: null, ready_at: null }, 0)).toBe('empty');
  });
});

describe('barra de XP', () => {
  it('vai de 0 a 1 e fica cheia no nível máximo', () => {
    expect(xpProgress(205, 410)).toBe(0.5);
    expect(xpProgress(500, 410)).toBe(1);
    expect(xpProgress(0, null)).toBe(1);
  });
});

describe('clique do jogador', () => {
  const plot = (over: Partial<Parameters<typeof plotLook>[0]>) => ({ plot_id: 'A1-1', crop_id: 'alface', state: 'empty' as const, ready_at: null, stalled_reason: null, ...over });
  it('maduro colhe, planejado planta, vazio abre a escolha', () => {
    expect(plotLook(plot({ state: 'growing', ready_at: 100 }), 100, 0)).toBe('ready');
    expect(plotLook(plot({ state: 'growing', ready_at: 101 }), 100, 0)).toBe('growing');
    expect(plotLook(plot({}), 100, 0)).toBe('planned');
    expect(plotLook(plot({ crop_id: null }), 100, 0)).toBe('empty');
    expect(plotLook(plot({}), 100, 200)).toBe('cleanup');
    expect(plotLook(plot({ stalled_reason: 'sem_ouro' }), 100, 0)).toBe('stalled');
  });
  it('o botão conta maduros, planejados e árvores com fruta (não conta quem está sem ouro)', () => {
    const s = {
      plots: [plot({ state: 'growing', ready_at: 50 }), plot({ plot_id: 'A1-2' }), plot({ plot_id: 'A1-3', stalled_reason: 'sem_ouro' }), plot({ plot_id: 'A3-1' })],
      trees: [{ lot_id: 'P1', slot: 1, fruit_id: 'maca', planted_at: 0, ready_at: 90 }],
      lots: [{ lot_id: 'A1', ready_at: 0 }, { lot_id: 'A3', ready_at: 999 }],
    };
    expect(tendCount(s, 100)).toBe(3);
  });
});
