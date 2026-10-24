// Contas das expedições no cliente (só para mostrar a prévia; o servidor recalcula e sorteia tudo).
import { CROPS, EXP, ROUTE_BY_ID, ROUTES, VEHICLE_BY_ID, itemInfo } from '../data';
import type { ExpeditionState, FarmState, LeadInfo, VehicleState } from '../net/farmApi';

export const RARITY_ORDER = ['common', 'uncommon', 'rare', 'legendary', 'mythic'] as const;

export function rarityMult(r: string, tiers: { id: string; multiplier: number }[]): number {
  return tiers.find((t) => t.id === r)?.multiplier ?? 1;
}

/** o veículo vai até essa rota? */
export function canReach(vehicle: string, route: string): boolean {
  const max = ROUTES.findIndex((r) => r.id === VEHICLE_BY_ID[vehicle].max_route);
  return ROUTES.findIndex((r) => r.id === route) <= max;
}

export function capacity(v: VehicleState, mult: number, lead: LeadInfo | null = null): number {
  return Math.floor(VEHICLE_BY_ID[v.vehicle_id].capacity * mult * (1 + (lead?.capacity_pct ?? 0) / 100));
}

export function tripHours(v: VehicleState, mult: number, route: string, lead: LeadInfo | null, expDuration = 0): number {
  return ROUTE_BY_ID[route].hours * VEHICLE_BY_ID[v.vehicle_id].duration_multiplier / mult * (lead?.duration_mult ?? 1) * (1 + expDuration);
}

/** chance de sucesso (mesma conta do servidor; teto de 95%) */
export function tripChance(o: { v: VehicleState; mult: number; route: string; lead: LeadInfo | null; minigamePts: number; expSuccess: number; failStreak: number }): number {
  const r = ROUTE_BY_ID[o.route];
  const pts = VEHICLE_BY_ID[o.v.vehicle_id].safety_pts * o.mult + o.minigamePts + (o.lead?.success_pts ?? 0) + o.expSuccess
    + (o.v.durability < EXP.low_wear_threshold_pct ? EXP.low_wear_success_pts : 0)
    + (o.failStreak >= EXP.bad_luck_protection.after_failures ? EXP.bad_luck_protection.bonus_pts : 0);
  return Math.max(0, Math.min(EXP.success_cap, r.success + pts / 100));
}

/** valor da carga a preço da rota, com +20% nos produtos da demanda */
export function cargoValue(cargo: Record<string, number>, route: string, demand: string[] = []): number {
  let v = 0;
  for (const [k, q] of Object.entries(cargo)) v += q * itemInfo(k).price * ROUTE_BY_ID[route].price_multiplier * (demand.includes(k) ? 1 + EXP.daily_demand.bonus : 1);
  return Math.round(v * 100) / 100;
}

export function insuranceCost(value: number, route: string, lead: LeadInfo | null = null): number {
  const p = ROUTE_BY_ID[route].insurance_pct;
  return p === null ? 0 : Math.round(value * p / 100 * (1 + (lead?.insurance_pct ?? 0) / 100) * 100) / 100;
}

/** divide a carga pelos veículos na ordem escolhida (igual ao servidor: produtos em ordem alfabética) */
export function splitCargo(cargo: Record<string, number>, caps: number[]): Record<string, number>[] {
  const rest = { ...cargo };
  return caps.map((cap) => {
    const part: Record<string, number> = {};
    let used = 0;
    for (const k of Object.keys(rest).sort()) {
      const take = Math.min(rest[k], cap - used);
      if (take <= 0) continue;
      part[k] = take; rest[k] -= take; used += take;
      if (used >= cap) break;
    }
    return part;
  });
}

export function repairCost(vehicle: string, durability: number): number {
  const d = VEHICLE_BY_ID[vehicle];
  const price = d.cost > 0 ? d.cost : (d as { reference_cost?: number }).reference_cost ?? 0;
  return Math.round(price * EXP.vehicle_repair.cost_ratio_of_price * (100 - durability) / 100 * 100) / 100;
}

export function refurbNext(rarity: string): (typeof EXP.refurbish)[number] | null {
  const next = RARITY_ORDER[RARITY_ORDER.indexOf(rarity as (typeof RARITY_ORDER)[number]) + 1];
  return EXP.refurbish.find((r) => r.rarity === next) ?? null;
}

export function refurbCost(vehicle: string, rarity: string): number {
  const d = VEHICLE_BY_ID[vehicle];
  const price = d.cost > 0 ? d.cost : (d as { reference_cost?: number }).reference_cost ?? 0;
  const nx = refurbNext(rarity);
  return nx ? Math.round(price * nx.cost_ratio * 100) / 100 : 0;
}

export type VehicleStatus = 'idle' | 'travel' | 'back' | 'refurb';
export function vehicleStatus(s: FarmState, v: VehicleState, now: number): { status: VehicleStatus; until: number | null; trips: ExpeditionState[] } {
  const trips = s.expeditions.filter((x) => x.vehicle_id === v.vehicle_id);
  if (v.refurb_until !== null && v.refurb_until > now) return { status: 'refurb', until: v.refurb_until, trips };
  const travel = trips.find((x) => x.status === 'travel');
  if (travel) return { status: 'travel', until: travel.returns_at, trips };
  if (trips.some((x) => x.status === 'back')) return { status: 'back', until: null, trips };
  return { status: 'idle', until: null, trips };
}

/** avaliação local do minigame (a mesma regra do servidor, para mostrar o resultado na hora) */
export function evalMinigame(arrows: string[], keys: { k: string; t: number }[], limitMs: number, calm: boolean): { result: 'perfect' | 'done' | 'incomplete' | 'failed'; pos: number; errors: number } {
  const m = EXP.minigame;
  let pos = 0, errors = 0, last = 0;
  for (const k of keys) {
    if (pos >= arrows.length) break;
    if (k.k === arrows[pos]) { pos++; last = k.t; } else errors++;
  }
  if (pos === arrows.length) {
    const fin = last + errors * m.wrong_key_penalty_s * 1000;
    if (fin <= limitMs) return { result: errors === 0 && !calm && fin <= limitMs * (1 - m.perfect_time_left) ? 'perfect' : 'done', pos, errors };
  }
  return { result: pos >= arrows.length * m.incomplete_min_fraction ? 'incomplete' : 'failed', pos, errors };
}

/** produtos do Silo que podem ir na expedição (têm preço) */
export function sellable(silo: Record<string, number>): [string, number][] {
  return Object.entries(silo).filter(([k, q]) => q > 0 && (CROPS[k] || itemInfo(k).price > 0));
}
