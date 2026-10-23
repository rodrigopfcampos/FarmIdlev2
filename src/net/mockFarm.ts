// Estado falso da fazenda, só para desenvolvimento e screenshots (nunca entra no build de produção).
import type { FarmState } from './farmApi';

const now = new Date().toISOString();
const state: FarmState = {
  server_now: now, farm_time: 5000, synced_at: now, last_activity_at: now, offline_cap_hours: 8,
  labor_bank: 1.9, labor_per_hour: 2.67, labor_cap_hours: 1, nickname: 'Rodrigo', gold: 1934, lots: ['A1'],
  plots: [
    { plot_id: 'A1-1', crop_id: 'batata', state: 'growing', planted_crop_id: 'batata', planted_at: 4900, ready_at: 8500, stalled_reason: null },
    { plot_id: 'A1-2', crop_id: 'batata', state: 'growing', planted_crop_id: 'batata', planted_at: 3000, ready_at: 6600, stalled_reason: null },
    { plot_id: 'A1-3', crop_id: 'cenoura', state: 'growing', planted_crop_id: 'cenoura', planted_at: 4000, ready_at: 5800, stalled_reason: null },
    { plot_id: 'A1-4', crop_id: 'alface', state: 'growing', planted_crop_id: 'alface', planted_at: 4500, ready_at: 5100, stalled_reason: null },
    { plot_id: 'A1-5', crop_id: 'espinafre', state: 'growing', planted_crop_id: 'espinafre', planted_at: 4200, ready_at: 5400, stalled_reason: null },
    { plot_id: 'A1-6', crop_id: 'espinafre', state: 'growing', planted_crop_id: 'espinafre', planted_at: 3900, ready_at: 5100, stalled_reason: null },
    { plot_id: 'A1-7', crop_id: 'batata', state: 'empty', planted_crop_id: null, planted_at: null, ready_at: null, stalled_reason: null },
    { plot_id: 'A1-8', crop_id: null, state: 'empty', planted_crop_id: null, planted_at: null, ready_at: null, stalled_reason: null },
  ],
  silo: { batata: 6, cenoura: 3, alface: 9 },
};

export const mockFarm = {
  async rpc(fn: string, args: Record<string, unknown>): Promise<FarmState> {
    if (fn === 'set_crop') for (const p of state.plots) if (p.plot_id === args.p_target || p.plot_id.startsWith(`${args.p_target}-`)) p.crop_id = args.p_crop as string | null;
    if (fn === 'sell_at_stall') { state.silo[args.p_item as string] -= args.p_qty as number; state.gold += 10; }
    return structuredClone({ ...state, server_now: new Date().toISOString(), last_activity_at: new Date().toISOString() });
  },
};
