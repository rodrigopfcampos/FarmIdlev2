// Estado falso da fazenda, só para desenvolvimento e screenshots (nunca entra no build de produção).
import { CHARS, CROPS, MAP_RULES, PETS, SNACKS, TOOL_MATERIALS } from '../data';
import { cleanupMinutes, lotOffer } from '../farm/rules';
import type { CharacterState, FarmState, PlotState } from './farmApi';

const now = new Date().toISOString();
const T = 50_000; // tempo da fazenda no começo do mock (s)
const START = performance.now();
const empty = (id: string): PlotState => ({ plot_id: id, crop_id: null, state: 'empty', planted_crop_id: null, planted_at: null, ready_at: null, harvests_done: 0, stalled_reason: null });
const growing = (id: string, crop: string, startAgo: number): PlotState => {
  const g = CROPS[crop].grow_minutes * 60;
  return { plot_id: id, crop_id: crop, state: 'growing', planted_crop_id: crop, planted_at: T - startAgo, ready_at: T - startAgo + g, harvests_done: 0, stalled_reason: null };
};

const char = (id: string, extra: Partial<CharacterState> = {}): CharacterState => ({
  class_id: id, slot: 'field', energy: 100, parked: false, level: 1, work_hours: 0, skills: {}, skill_choice: null, reset_week: null,
  debt: 0, unpaid_days: 0, snack_id: null, snack_qty: 0, cloth_id: null, amulet_id: null, material: 'wood', durability: 100,
  rate: id === 'agricultor' || id === 'rancheira' ? 2.67 : 1.6, energy_max: 100, energy_use: 12.5, energy_rest: 25, active: true, salary: id === 'agricultor' ? 0 : 1950, ...extra,
});

const state: FarmState = {
  server_now: now, farm_time: T, synced_at: now, last_activity_at: now, offline_cap_hours: 8,
  labor_bank: 1.9, labor_per_hour: 2.67, labor_cap_hours: 1, nickname: 'Rodrigo', is_admin: false, gold: 64_300,
  level: 11, xp: 2100, xp_to_next: 3400,
  lots: [{ lot_id: 'A1', ready_at: 0, purchase_n: null }, { lot_id: 'A3', ready_at: T + 50 * 60, purchase_n: 1 }, { lot_id: 'P1', ready_at: 0, purchase_n: 2 }, { lot_id: 'C1', ready_at: 0, purchase_n: 3 }],
  plots: [
    growing('A1-1', 'batata', 3700), growing('A1-2', 'batata', 500), growing('A1-3', 'cenoura', 1700), growing('A1-4', 'alface', 100),
    growing('A1-5', 'espinafre', 300), growing('A1-6', 'morango', 4000), empty('A1-7'), { ...empty('A1-8'), crop_id: 'tomate', stalled_reason: 'sem_ouro' },
    ...Array.from({ length: 8 }, (_, i) => ({ ...empty(`A3-${i + 1}`), crop_id: 'alface' })),
  ],
  trees: [
    { lot_id: 'P1', slot: 1, fruit_id: 'maca', planted_at: T - 30_000, ready_at: T - 30_000 + 43_200 },
    { lot_id: 'P1', slot: 2, fruit_id: 'maca', planted_at: T - 3_000, ready_at: T - 3_000 + 43_200 },
    { lot_id: 'P1', slot: 3, fruit_id: 'maca', planted_at: T - 60_000, ready_at: T + 2_000 },
    { lot_id: 'P1', slot: 4, fruit_id: null, planted_at: null, ready_at: null },
  ],
  silo: { batata: 6, cenoura: 3, alface: 9, maca: 4 },
  inventory: { deed: 1 },
  tools: { agricultor: 'wood', rancheira: 'wood', ferreiro: 'wood' },
  game_day: new Date().toISOString().slice(0, 10), labor_nominal: 6.94, last_payday: null, boosted_sale_day: null, pet_swapped_at: null,
  auto_sell: ['batata'],
  characters: [
    char('agricultor', { energy: 62.5, level: 4, work_hours: 6.2, skills: { 'cultivo.a': 2 }, snack_id: 'snack_coffee', snack_qty: 3, durability: 71 }),
    char('rancheira', { energy: 38, level: 2, work_hours: 3 }),
    char('ferreiro', { energy: 12, parked: true, debt: 1950, unpaid_days: 1, rate: 0.8 }),
  ],
  pets: [{ pet_id: 'gato', affinity: 5, last_care: null, active: true, linked_class: 'agricultor' }],
  pet: { id: 'gato', level: 2, factor: 0.55, linked: 'agricultor' },
  snack_prices: Object.fromEntries(SNACKS.map((x) => [x.id, Math.round(96000 * x.price_R_ratio)])),
  fx: { stall_ratio: 0.7, seed_discount: 0, sales_gold: 0, shop_discount: 0, auto_sell: false, auto_pay: false, rare_seed: 0, seed_refund: 0,
    gerente_cut: 0, early_unlock: null, daily_boost: 0, growth_crop: 0.02, growth_orchard: 0, tree_initial: 0, cleanup: 0, tool_cost: 0, harvest_xp: 0, golden: 0 },
};
state.inventory['seed:alface:rare'] = 1;
state.inventory.snack_cheese_bread = 4;

export const mockFarm = {
  async rpc(fn: string, args: Record<string, unknown>): Promise<FarmState> {
    state.farm_time = T + (performance.now() - START) / 1000; // o mock anda junto com o relógio do cliente
    const t = state.farm_time;
    const inTarget = (id: string) => args.p_target == null || id === args.p_target || id.startsWith(`${args.p_target}-`);
    const lotReady = (id: string) => (state.lots.find((l) => l.lot_id === id.split('-')[0])?.ready_at ?? 0) <= t;
    const plantNow = () => {
      for (const p of state.plots) if (inTarget(p.plot_id) && p.state === 'empty' && p.crop_id && lotReady(p.plot_id)) {
        const c = CROPS[p.crop_id];
        Object.assign(p, { state: 'growing', planted_crop_id: c.id, planted_at: t, ready_at: t + c.grow_minutes * 60, harvests_done: 0 });
        state.gold -= c.seed_cost ?? 0;
      }
    };
    if (fn === 'set_crop') { for (const p of state.plots) if (inTarget(p.plot_id)) p.crop_id = args.p_crop as string | null; plantNow(); }
    if (fn === 'tend_farm') {
      for (const p of state.plots) if (inTarget(p.plot_id) && p.state === 'growing' && p.ready_at! <= t) {
        const c = CROPS[p.planted_crop_id!];
        state.silo[c.id] = (state.silo[c.id] ?? 0) + c.units_per_harvest; state.xp += c.xp_per_harvest;
        Object.assign(p, { state: 'empty', planted_crop_id: null, planted_at: null, ready_at: null });
      }
      for (const tr of state.trees) if ((args.p_target == null || tr.lot_id === args.p_target) && tr.fruit_id && tr.ready_at! <= t) {
        const c = CROPS[tr.fruit_id];
        state.silo[c.id] = (state.silo[c.id] ?? 0) + c.units_per_harvest; tr.ready_at = t + (c.regrow_minutes ?? 0) * 60;
      }
      plantNow();
    }
    if (fn === 'sell_at_stall') { state.silo[args.p_item as string] -= args.p_qty as number; state.gold += 10; }
    if (fn === 'buy_lot') {
      const lot = args.p_lot as string;
      const offer = lotOffer(lot, new Set(state.lots.map((l) => l.lot_id)), state.level, state.inventory.deed ?? 0, state.gold);
      if (!offer || offer.problems.length) throw new Error('Não dá para comprar esse lote.');
      state.gold -= offer.cost;
      const ready = t + cleanupMinutes(offer.n) * 60;
      state.lots.push({ lot_id: lot, ready_at: ready, purchase_n: offer.n });
      const def = MAP_RULES.lots.find((l) => l.id === lot)!;
      for (const id of def.plots) state.plots.push(empty(id));
      for (let k = 1; k <= def.tree_slots; k++) state.trees.push({ lot_id: lot, slot: k, fruit_id: null, planted_at: null, ready_at: null });
    }
    if (fn === 'plant_tree' || fn === 'chop_tree') {
      const tr = state.trees.find((x) => x.lot_id === args.p_lot && x.slot === args.p_slot)!;
      if (fn === 'chop_tree') Object.assign(tr, { fruit_id: null, planted_at: null, ready_at: null });
      else { const c = CROPS[args.p_fruit as string]; state.gold -= c.sapling_cost ?? 0; Object.assign(tr, { fruit_id: c.id, planted_at: t, ready_at: t + c.grow_minutes * 60 }); }
    }
    if (fn === 'upgrade_tool') {
      const i = TOOL_MATERIALS.findIndex((m) => m.id === state.tools.agricultor);
      const next = TOOL_MATERIALS[i + 1];
      state.gold -= next.upgrade_cost_gold; state.tools.agricultor = next.id; state.labor_per_hour = 2.67 * next.work_capacity_multiplier;
    }
    const ch = (id: unknown) => state.characters.find((c) => c.class_id === id);
    if (fn === 'hire') { state.characters.push(char(args.p_class as string, { slot: state.characters.filter((c) => c.slot === 'field').length < CHARS.field_slots ? 'field' : 'bench' })); state.tools[args.p_class as string] = 'wood'; }
    if (fn === 'set_slot') ch(args.p_class)!.slot = args.p_slot as 'field' | 'bench';
    if (fn === 'pay_salaries') for (const c of state.characters) { state.gold -= c.debt; c.debt = 0; c.unpaid_days = 0; }
    if (fn === 'skill_add') { const c = ch(args.p_class)!; c.skills[args.p_node as string] = (c.skills[args.p_node as string] ?? 0) + 1; }
    if (fn === 'skill_reset') ch(args.p_class)!.skills = {};
    if (fn === 'buy_snack') state.inventory[args.p_snack as string] = (state.inventory[args.p_snack as string] ?? 0) + (args.p_qty as number);
    if (fn === 'equip_snack') { const c = ch(args.p_class)!; c.snack_id = args.p_snack as string | null; c.snack_qty = args.p_snack ? 5 : 0; }
    if (fn === 'repair_tool') ch(args.p_class)!.durability = 100;
    if (fn === 'set_auto_sell') state.auto_sell = args.p_on ? [...state.auto_sell, args.p_item as string] : state.auto_sell.filter((x) => x !== args.p_item);
    if (fn === 'adopt_pet') state.pets.push({ pet_id: args.p_pet as string, affinity: 0, last_care: null, active: false, linked_class: null });
    if (fn === 'care_pet') { const p = state.pets.find((x) => x.pet_id === args.p_pet)!; p.affinity++; p.last_care = state.game_day; }
    if (fn === 'link_pet') { state.pets.find((x) => x.active)!.linked_class = args.p_class as string; state.pet!.linked = args.p_class as string; }
    void PETS;
    return structuredClone({ ...state, server_now: new Date().toISOString(), last_activity_at: new Date().toISOString() });
  },
};
