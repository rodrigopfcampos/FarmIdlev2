// Regras da progressão do lado do cliente (o servidor tem os testes em supabase/tests/phase2_test.sql).
import { describe, expect, it } from 'vitest';
import { CROPS, LEVELS, PURCHASES, itemInfo } from '../src/data';
import {
  animalLook, cleanupMinutes, collectUnits, feedPerCycle, hireCost, hoursToNext, isNeighbor, lotOffer, orchardFruits, petFactor, petLevel, petNextIn, petFindLeft, plotCrops, plotLook,
  rareSeeds, accountEffect, accountPoints, passiveState, tendCount, treeLook, xpProgress,
} from '../src/farm/rules';

describe('compra de lotes', () => {
  const start = new Set(['A1']);
  it('1ª compra: lote vizinho do A1 no nível 2 pelo preço da tabela', () => {
    const o = lotOffer('A3', start, 2, 1_000_000)!;
    expect(o.n).toBe(1);
    expect(o.cost).toBe(PURCHASES[0].cost);
    expect(o.needLevel).toBe(2);
    expect(o.problems).toEqual([]);
  });
  it('lote que não divide lado com um lote seu é recusado', () => {
    expect(isNeighbor('A2', start)).toBe(false);
    expect(lotOffer('A2', start, 50, 1e9)!.problems).toContain('vizinho');
  });
  it('Galinheiro e Celeiro podem ser comprados de longe, Lago não', () => {
    expect(isNeighbor('C1', start)).toBe(true);
    expect(isNeighbor('C2', start)).toBe(true);
    expect(isNeighbor('L', start)).toBe(false);
  });
  it('nível: o maior entre o da compra e o piso do tipo (pomar 10)', () => {
    const o = lotOffer('P1', start, 2, 1e9)!;
    expect(o.needLevel).toBe(10);
    expect(o.problems).toEqual(['nivel']);
  });
  it('v3: a 19ª compra pede só nível e ouro (sem Escritura)', () => {
    const owned = new Set(['A1', 'A3', 'A4', 'A2', 'A5', 'A6', 'A7', 'A8', 'A10', 'A11', 'A12', 'A13', 'A14', 'A15', 'A16', 'A17', 'P2', 'P3', 'P1']);
    const o = lotOffer('P5', owned, 50, 1e12)!;
    expect(o.n).toBe(19);
    expect(o.problems).toEqual([]);
  });
  it('limpeza: 1 h + 12 min × n, em dobro sem Ferreiro', () => {
    expect(cleanupMinutes(1, true)).toBe(24); // com o Ferreiro em campo, 3× mais rápido
    expect(cleanupMinutes(1)).toBe(72);
  });
  it('lote seu não aparece à venda', () => {
    expect(lotOffer('A1', start, 50, 1e9)).toBeNull();
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

// ---------- fase 3: personagens, pets, habilidades e sementes raras ----------

describe('personagens (fase 3)', () => {
  it('contratação = 1,5 × R do nível em que a classe libera', () => {
    expect(hireCost('rancheira')).toBe(1.5 * LEVELS[2].reference_income_per_day);
    expect(hireCost('botanica')).toBe(1.5 * LEVELS[19].reference_income_per_day);
  });
  it('próximo nível do personagem pede 10 + 1,5 × nível horas; no 30 para', () => {
    expect(hoursToNext(1)).toBe(11.5);
    expect(hoursToNext(30)).toBeNull();
  });
  it('passivas: 1 ponto por nível do 2 em diante; Ultimate custa 5', () => {
    expect(accountPoints(12, { labia: 5, logistica: 3 })).toEqual({ total: 11, spent: 8, free: 3 });
    expect(accountPoints(50, { contrabando: 1 }).spent).toBe(5); // Ultimate custa 5
    expect(accountPoints(50, {}).total).toBe(49);
    expect(accountEffect({ folha: 5 }, 'salary_pct')).toBe(-15);
    expect(accountEffect({ carinho_animal: 5 }, 'feed_cost_pct')).toBe(-20);
  });
  it('caminho: A abre B e C; B ou C com 3 abre D; Ultimate pede 15 no ramo', () => {
    expect(passiveState('logistica', {}, 10).state).toBe('locked');
    expect(passiveState('logistica', { labia: 1 }, 10).state).toBe('available');
    expect(passiveState('rotas', { labia: 1, logistica: 2 }, 10).state).toBe('locked');
    expect(passiveState('rotas', { labia: 1, manutencao: 3 }, 10).state).toBe('available');
    expect(passiveState('contrabando', { labia: 5, logistica: 3, rotas: 1 }, 10).why).toContain('15 pontos no caminho');
    expect(passiveState('contrabando', { labia: 5, logistica: 5, rotas: 5 }, 5).state).toBe('available');
    expect(passiveState('contrabando', { labia: 5, logistica: 5, rotas: 5 }, 4).state).toBe('locked');
  });
  it('peixe do Lago no Silo tem nome e preço do próprio peixe', () => {
    expect(itemInfo('fish_truta').name_pt).toBe('Truta Arco-Íris');
    expect(itemInfo('fish_truta').price).toBeGreaterThan(0);
  });
  it('limpeza: com o Ferreiro em campo 3× mais rápida; nó Limpeza reduz', () => {
    expect(cleanupMinutes(1, true)).toBe(24);
    expect(cleanupMinutes(1, false)).toBe(72);
    expect(cleanupMinutes(28, false)).toBe(396);
    expect(cleanupMinutes(1, true, -0.25)).toBeCloseTo(18);
  });
});

describe('pets (fase 3)', () => {
  it('nível pela afinidade: 4, 10, 18 e 30 carinhos', () => {
    expect([0, 3, 4, 9, 10, 18, 29, 30, 99].map(petLevel)).toEqual([1, 1, 2, 2, 3, 4, 4, 5, 5]);
    expect(petNextIn(0)).toBe(4);
    expect(petNextIn(30)).toBeNull();
  });
  it('efeito de 40% no nível 1 a 100% no nível 5', () => {
    expect(petFactor(1)).toBeCloseTo(0.4);
    expect(petFactor(3)).toBeCloseTo(0.7);
    expect(petFactor(5)).toBeCloseTo(1);
  });
  it('pets v3: achado pronto depois das horas de cada pet', () => {
    expect(petFindLeft('papagaio', 0, 3 * 3600)).toBe(0);
    expect(petFindLeft('cachorro', 0, 3600)).toBe(5 * 3600);
    expect(petFindLeft('gato', null, 99999)).toBe(Infinity);
  });

});

describe('sementes raras e pomar (fase 3)', () => {
  it('lê as sementes raras do inventário', () => {
    expect(rareSeeds({ deed: 1, 'seed:alface:rare': 2, 'seed:maca:mythic': 1, 'seed:batata:uncommon': 0 }, 'alface')).toEqual([{ crop: 'alface', rarity: 'rare', qty: 2 }]);
    expect(rareSeeds({ 'seed:alface:rare': 2, 'seed:maca:mythic': 1 })).toHaveLength(2);
  });
  it('árvore com 1º crescimento mais curto (habilidade) ainda aparece como muda no começo', () => {
    const g = CROPS.maca.grow_minutes * 60 * 0.8;
    expect(treeLook({ lot_id: 'P1', slot: 1, fruit_id: 'maca', planted_at: 0, ready_at: g }, g * 0.1)).toBe('sapling');
    expect(treeLook({ lot_id: 'P1', slot: 1, fruit_id: 'maca', planted_at: 0, ready_at: g }, g * 0.9)).toBe('fruit');
  });
});

describe('animais (fase 4)', () => {
  it('pronto, produzindo ou com fome', () => {
    expect(animalLook({ state: 'growing', ready_at: 100 }, 150)).toBe('ready');
    expect(animalLook({ state: 'growing', ready_at: 200 }, 150)).toBe('growing');
    expect(animalLook({ state: 'hungry', ready_at: null }, 150)).toBe('hungry');
  });
  it('ração por ciclo = ração/dia × duração do ciclo', () => {
    expect(feedPerCycle(740, 120)).toBeCloseTo(61.67, 2);
    expect(feedPerCycle(1000, 240, 0.4)).toBeCloseTo(100, 2);
  });
  it('produção: raridade × (1 + bônus), Lago só nas aves, teto de 60%', () => {
    expect(collectUnits(3, 0, 0.6, true, 0.1)).toBeCloseTo(3.3);
    expect(collectUnits(1, 0.7, 0.6, false, 0.1)).toBeCloseTo(1.6);
  });
  it('itens do Silo: cultivo ou produto animal', () => {
    expect(itemInfo('ovo')).toMatchObject({ name_pt: 'Ovo', price: 410 });
    expect(itemInfo('alface').emoji).toBeNull();
  });
  it('conta animais prontos no botão Colher e plantar', () => {
    expect(tendCount({ plots: [], trees: [], lots: [], animals: [{ state: 'growing', ready_at: 10 }, { state: 'hungry', ready_at: null }] }, 20)).toBe(1);
  });
});
