// Estado falso da fazenda, só para desenvolvimento e screenshots (nunca entra no build de produção).
import { CROPS, MAP_RULES, TOOL_MATERIALS } from '../data';
import { cleanupMinutes, lotOffer } from '../farm/rules';
import type { FarmState, PlotState } from './farmApi';

const now = new Date().toISOString();
const T = 50_000; // tempo da fazenda no começo do mock (s)
const START = performance.now();
const empty = (id: string): PlotState => ({ plot_id: id, crop_id: null, state: 'empty', planted_crop_id: null, planted_at: null, ready_at: null, harvests_done: 0, stalled_reason: null });
const growing = (id: string, crop: string, startAgo: number): PlotState => {
  const g = CROPS[crop].grow_minutes * 60;
  return { plot_id: id, crop_id: crop, state: 'growing', planted_crop_id: crop, planted_at: T - startAgo, ready_at: T - startAgo + g, harvests_done: 0, stalled_reason: null };
};

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
  tools: { agricultor: 'wood' },
};

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
    return structuredClone({ ...state, server_now: new Date().toISOString(), last_activity_at: new Date().toISOString() });
  },
};
