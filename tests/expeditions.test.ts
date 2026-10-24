// Regras das expedições no cliente (as mesmas contas do servidor, usadas na prévia)
import { describe, expect, it } from 'vitest';
import { RARITIES } from '../src/data';
import {
  canReach, capacity, cargoValue, evalMinigame, insuranceCost, rarityMult, refurbCost, refurbNext, repairCost, splitCargo, tripChance, tripHours, vehicleStatus,
} from '../src/farm/expeditions';
import type { FarmState, LeadInfo, VehicleState } from '../src/net/farmApi';

const veh = (id: string, rarity = 'common', durability = 100): VehicleState => ({ vehicle_id: id, rarity, durability, active: true, refurb_rarity: null, refurb_until: null });
const lead: LeadInfo = { available: true, leading: false, vehicles: 1, success_pts: 8, duration_mult: 0.9, capacity_pct: 0, loss_pct: 0, insurance_pct: -30, item_pct: 0, deed_pct: 0, crit_pts: 0, extra_seconds: 1 };

describe('veículos e rotas', () => {
  it('a Carroça vai só até a Cidade Vizinha; o Caminhão grande vai a todas', () => {
    expect(canReach('carroca', 'cidade')).toBe(true);
    expect(canReach('carroca', 'capital')).toBe(false);
    expect(canReach('caminhao', 'exportacao')).toBe(true);
  });
  it('raridade multiplica capacidade e divide a duração', () => {
    expect(capacity(veh('carroca', 'uncommon'), rarityMult('uncommon', RARITIES))).toBe(72);
    expect(capacity(veh('caminhao', 'mythic'), rarityMult('mythic', RARITIES))).toBe(1500);
    expect(tripHours(veh('caminhao', 'mythic'), 3, 'exportacao', null)).toBeCloseTo(8 / 3);
    expect(tripHours(veh('carroca'), 1, 'feira', lead)).toBeCloseTo(0.5 * 1.3 * 0.9);
  });
  it('chance: base + segurança + minigame + Gerente, com teto de 95% e garantia contra azar', () => {
    const base = { v: veh('carro'), mult: 1, route: 'capital', lead: null, minigamePts: 0, expSuccess: 0, failStreak: 0 };
    expect(tripChance(base)).toBeCloseTo(0.85 + 0.03);
    expect(tripChance({ ...base, minigamePts: -10 })).toBeCloseTo(0.78);
    expect(tripChance({ ...base, failStreak: 2 })).toBe(0.95);
    expect(tripChance({ ...base, lead })).toBe(0.95);
    expect(tripChance({ ...base, v: veh('carro', 'common', 20) })).toBeCloseTo(0.83);
  });
});

describe('carga, seguro e conserto', () => {
  it('produto da demanda vale +20% na rota', () => {
    const a = cargoValue({ batata: 10 }, 'cidade');
    expect(cargoValue({ batata: 10 }, 'cidade', ['batata'])).toBeCloseTo(a * 1.2);
  });
  it('seguro é % da carga e o Gerente com Mestria Carga tira 30%', () => {
    expect(insuranceCost(1000, 'feira')).toBe(0);
    expect(insuranceCost(1000, 'cidade')).toBe(24);
    expect(insuranceCost(1000, 'cidade', lead)).toBeCloseTo(16.8);
  });
  it('o comboio enche os veículos na ordem escolhida', () => {
    expect(splitCargo({ batata: 150 }, [120, 60])).toEqual([{ batata: 120 }, { batata: 30 }]);
    expect(splitCargo({ alface: 50, batata: 50 }, [60, 60])).toEqual([{ alface: 50, batata: 10 }, { batata: 40 }]);
  });
  it('conserto proporcional e reforma pela tabela', () => {
    expect(repairCost('carroca', 50)).toBe(1650);
    expect(refurbNext('common')?.rarity).toBe('uncommon');
    expect(refurbNext('mythic')).toBeNull();
    expect(refurbCost('caminhao', 'common')).toBe(1_680_000);
  });
});

describe('minigame', () => {
  const arrows = ['up', 'left', 'down', 'right'];
  const keys = (ts: number[], seq = arrows) => seq.slice(0, ts.length).map((k, i) => ({ k, t: ts[i] }));
  it('sem erro e com 30% do tempo sobrando = Perfeita (não no Modo calmo)', () => {
    expect(evalMinigame(arrows, keys([300, 700, 1100, 1500]), 6000, false).result).toBe('perfect');
    expect(evalMinigame(arrows, keys([300, 700, 1100, 1500]), 6000, true).result).toBe('done');
  });
  it('erro custa 0,5 s e não volta ao início', () => {
    const k = [{ k: 'up', t: 300 }, { k: 'up', t: 500 }, { k: 'left', t: 800 }, { k: 'down', t: 1100 }, { k: 'right', t: 5600 }];
    expect(evalMinigame(arrows, k, 6000, false).result).toBe('incomplete');
    expect(evalMinigame(arrows, k.map((x, i) => (i === 4 ? { ...x, t: 4000 } : x)), 6000, false).result).toBe('done');
  });
  it('tempo acabou: metade feita = Incompleta; menos = Falhou', () => {
    expect(evalMinigame(arrows, keys([300, 700]), 6000, false).result).toBe('incomplete');
    expect(evalMinigame(arrows, keys([300]), 6000, false).result).toBe('failed');
  });
});

describe('estado do veículo', () => {
  const s = { expeditions: [{ vehicle_id: 'carro', status: 'travel', returns_at: 500 }, { vehicle_id: 'carroca', status: 'back', returns_at: 10 }] } as unknown as FarmState;
  it('viajando, esperando Receber, na reforma ou livre', () => {
    expect(vehicleStatus(s, veh('carro'), 100).status).toBe('travel');
    expect(vehicleStatus(s, veh('carroca'), 100).status).toBe('back');
    expect(vehicleStatus(s, { ...veh('picape'), refurb_rarity: 'uncommon', refurb_until: 900 }, 100).status).toBe('refurb');
    expect(vehicleStatus(s, veh('picape'), 100).status).toBe('idle');
  });
});
