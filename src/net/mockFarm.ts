// Estado falso da fazenda, só para desenvolvimento e screenshots (nunca entra no build de produção).
import { WEATHER, ANIMAL_BY_ID, CHARS, CROPS, EXP, MAP_RULES, PETS, ROUTE_BY_ID, SNACKS, TOOL_MATERIALS, VEHICLE_BY_ID } from '../data';
import { cargoValue, evalMinigame } from '../farm/expeditions';
import { localMinutes } from '../farm/weather';
import { cleanupMinutes, lotOffer } from '../farm/rules';
import type { CharacterState, CollectedTrip, FarmState, PlayerCard, PlotState, SocialState, VillageState, VisitView } from './farmApi';

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
    // 1 cultivo por lote: A1 inteiro de batata, em idades diferentes (um canteiro vazio esperando)
    growing('A1-1', 'batata', 3700), growing('A1-2', 'batata', 500), growing('A1-3', 'batata', 1700), growing('A1-4', 'batata', 100),
    growing('A1-5', 'batata', 3000), growing('A1-6', 'batata', 4000), growing('A1-7', 'batata', 84), { ...empty('A1-8'), crop_id: 'batata' },
    ...Array.from({ length: 8 }, (_, i) => ({ ...empty(`A3-${i + 1}`), crop_id: 'alface' })),
  ],
  trees: [
    { lot_id: 'P1', slot: 1, fruit_id: 'maca', planted_at: T - 30_000, ready_at: T - 30_000 + 43_200 },
    { lot_id: 'P1', slot: 2, fruit_id: 'maca', planted_at: T - 3_000, ready_at: T - 3_000 + 43_200 },
    { lot_id: 'P1', slot: 3, fruit_id: 'maca', planted_at: T - 60_000, ready_at: T + 2_000 },
    { lot_id: 'P1', slot: 4, fruit_id: null, planted_at: null, ready_at: null },
  ],
  silo: { batata: 6, cenoura: 3, alface: 9, maca: 4, ovo: 3, trufa: 1, la_de_alpaca: 2, leite_de_cabra: 1 },
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
    gerente_cut: 0, early_unlock: null, daily_boost: 0, growth_crop: 0.02, growth_orchard: 0, tree_initial: 0, cleanup: 0, tool_cost: 0, harvest_xp: 0, golden: 0,
    feed_discount: 0, animal_production: 0.055, animal_cap: 0.6, animal_double: 0, expansion_cost: 0, rancheira: true,
    exp_success: 0, exp_duration: 0, vehicle_wear: 0, dog_recover: 0 },
  animals: [
    { house_id: 'galinheiro', slot: 1, animal_id: 'galinha', rarity: 'common', state: 'growing', cycle_start: T - 7300, ready_at: T - 100 },
    { house_id: 'galinheiro', slot: 2, animal_id: 'galinha', rarity: 'rare', state: 'growing', cycle_start: T - 3000, ready_at: T + 4200 },
    { house_id: 'galinheiro', slot: 3, animal_id: 'coelho', rarity: 'mythic', state: 'hungry', cycle_start: T - 100, ready_at: null },
  ],
  houses: { galinheiro: { owned: true, tier: 0, slots: 4, bird_slots: 0, lot: 'C1' }, celeiro: { owned: false, tier: 0, slots: 4, bird_slots: 0, lot: 'C2' } },
  lake: false,
  vehicles: [{ vehicle_id: 'carroca', rarity: 'common', durability: 88, active: true, refurb_rarity: null, refurb_until: null },
    { vehicle_id: 'carro', rarity: 'uncommon', durability: 100, active: false, refurb_rarity: null, refurb_until: null }],
  expeditions: [{ id: 'm1', convoy_id: 'c1', vehicle_id: 'carro', route_id: 'cidade', cargo: { batata: 80, alface: 40 }, insurance: 120, led: false, minigame: 'done',
    started_at: T - 600, returns_at: T + 2400, seq: 0, repeat_left: 2, status: 'travel' }],
  exp_fail_streak: 0,
  lead: null,
  demand: { feira: ['batata', 'ovo', 'maca'], cidade: ['alface', 'leite', 'tomate'], capital: ['milho', 'la', 'uva'], porto: ['cafe', 'trufa', 'manga'], exportacao: ['cacau', 'la_de_alpaca', 'kiwi'] },
  demand_tomorrow: null,
  weather: mockWeather(),
  missions: [
    { kind: 'daily', slot: 1, id: 'd_colher', metric: 'harvest_value', target: 9000, progress: 6200, done: false, reward: { gold: 1700, xp: 700 } },
    { kind: 'daily', slot: 2, id: 'd_barraca', metric: 'stall_gold', target: 3000, progress: 3000, done: true, reward: { gold: 1700, xp: 700 } },
    { kind: 'daily', slot: 3, id: 'd_expedicoes', metric: 'expeditions_sent', target: 2, progress: 1, done: false, reward: { gold: 1700, xp: 700 } },
    { kind: 'daily', slot: 4, id: 'd_xp', metric: 'xp_earned', target: 2100, progress: 400, done: false, reward: { gold: 1700, xp: 700 } },
    { kind: 'daily', slot: 5, id: 'd_plantar_nivel', metric: 'plant_top', target: 8, progress: 8, done: true, reward: { gold: 1700, xp: 700 } },
    { kind: 'weekly', slot: 1, id: 'w_expedicoes', metric: 'expeditions_sent', target: 10, progress: 4, done: false, reward: {} },
    { kind: 'weekly', slot: 2, id: 'w_ouro', metric: 'gold_earned', target: 130000, progress: 130000, done: true, reward: {} },
    { kind: 'weekly', slot: 3, id: 'w_nivel', metric: 'char_level', target: 1, progress: 0, done: false, reward: {} },
    { kind: 'weekly', slot: 4, id: 'w_eventos', metric: 'night_events', target: 3, progress: 1, done: false, reward: {} },
    { kind: 'weekly', slot: 5, id: 'w_colher', metric: 'harvest_value', target: 63000, progress: 20000, done: false, reward: {} },
  ],
  mission_week: { daily_packs: 2, weekly_rewards: 0 }, reroll_used: false, pack_today: false,
  cards: [
    { serial: 101, card_id: 'sol_de_verao', rarity: 'common', state: 'binder', inbox_until: null, seen: true, origin: 'daily_pack' },
    { serial: 102, card_id: 'sol_de_verao', rarity: 'common', state: 'binder', inbox_until: null, seen: true, origin: 'daily_pack' },
    { serial: 103, card_id: 'ampulheta', rarity: 'rare', state: 'binder', inbox_until: null, seen: true, origin: 'weekly_3' },
    { serial: 104, card_id: 'moeda_da_sorte', rarity: 'legendary', state: 'binder', inbox_until: null, seen: true, origin: 'daily_pack' },
    { serial: 105, card_id: 'trevo_quatro_folhas', rarity: 'uncommon', state: 'binder', inbox_until: null, seen: true, origin: 'daily_pack' },
    { serial: 106, card_id: 'tempestade', rarity: 'mythic', state: 'binder', inbox_until: null, seen: true, origin: 'weekly_5' },
  ],
  new_cards: new URLSearchParams(location.search).get('ver') === 'pacote' ? [{ serial: 107, card_id: 'coruja_sabia', rarity: 'legendary', origin: 'daily_pack' }] : [],
  buffs: [{ card_id: 'rebanho_feliz', rarity: 'rare', started_at: new Date(Date.now() - 20 * 60_000).toISOString(), ends_at: new Date(Date.now() + 80 * 60_000).toISOString(), coin_value: 0 }],
  armory: [{ card_id: 'sol_de_verao', rarity: 'common' }, { card_id: 'sol_de_verao', rarity: 'uncommon' }, { card_id: 'sol_de_verao', rarity: 'rare' }, { card_id: 'folego', rarity: 'common' }],
  pity: { rare: 4, legendary: 21, mythic: 63 }, binder_slots: 60, prod_ref: { value_h: 4500, xp_h: 1400 },
  collector: { common: 200, uncommon: 400, rare: 800, legendary: 1300, mythic: 2300 }, binder_expand_cost: 50000,
  village: { title: 'Ajudante da Vila', stars: 0 },
  social: { incoming: 1, unseen: 2, likes: 7, helps: [{ lot_id: 'A1', kind: 'growth', pct: 10, ends_at: new Date(Date.now() + 40 * 60_000).toISOString(), from: 'Joana' }] },
};

// Vila do mock (?ver=estrelas mostra a loja liberada)
const village: VillageState = {
  order: { id: 7, name: 'Festa da Colheita', items: ['batata', 'melao', 'gengibre'], goal: 120, ends_at: new Date(Date.now() + 3 * 86400_000 + 5 * 3600_000).toISOString(), players: 15 },
  mine: { points: 3.2, total: 71.5, donors: 9, goal_reached: false, qualified: true, rank: 4, top: false },
  per_unit: { batata: 0.0109, cenoura: 0.0035, alface: 0.0013, maca: 0.02, ovo: 0.01, trufa: 0.3, la_de_alpaca: 0.2, leite_de_cabra: 0.05 },
  gold_per_point: 4000,
  last: { name: 'Quermesse da Vila', result: { points: 6.4, total: 140, donors: 12, goal_reached: true, qualified: true, rank: 3, top: false }, reward: { cards: 1, title: 'Ajudante da Vila', points: 6.4 } },
  title: 'Ajudante da Vila',
  stars: { unlocked: new URLSearchParams(location.search).get('ver') === 'estrelas', stars: 12, xp: 520_000, per_star: 876_110, packs_week: 1, seeds_week: 2, R: 96_000 },
};

// amigos e visitas do mock
const P = (id: string, nickname: string, level: number, likes: number, status?: PlayerCard['status']): PlayerCard => ({ id, nickname, level, likes, status });
const ago = (min: number) => new Date(Date.now() - min * 60_000).toISOString();
const social: SocialState = {
  friends: [P('u1', 'Joana', 14, 22), P('u2', 'Tião da Roça', 9, 5)],
  incoming: [P('u3', 'Marcela', 6, 1)], outgoing: [P('u4', 'Beto', 21, 40)], blocked: [],
  activity: [
    { kind: 'help', from: P('u1', 'Joana', 14, 22), at: ago(20), new: true, lot: 'A1', help: 'growth', pct: 10 },
    { kind: 'note', from: P('u2', 'Tião da Roça', 9, 5), at: ago(95), new: true, emojis: ['🌻', '👍'] },
    { kind: 'like', from: P('u5', 'Lia', 3, 0), at: ago(60 * 26), new: false },
  ],
  helps_given: 3, helps_received: 1, likes: 7,
};
const visit = { liked: false, noted: false, given: 3, cooldowns: {} as Record<string, string> };
function visitView(id: string): VisitView {
  const o = [...social.friends, P('u5', 'Lia', 3, 0), P('u6', 'Fazenda Sol', 12, 9)].find((p) => p.id === id) ?? P('u6', 'Fazenda Sol', 12, 9);
  const st = structuredClone({ ...state, nickname: o.nickname, level: o.level, server_now: new Date().toISOString() });
  return {
    owner: { ...o, status: social.friends.some((f) => f.id === o.id) ? 'friend' : 'none' },
    state: { ...st, helps: Object.entries(visit.cooldowns).map(([lot_id, e]) => ({ lot_id, kind: 'growth' as const, pct: 10, ends_at: e, from: 'Rodrigo' })) },
    cooldowns: visit.cooldowns,
    limits: { given: visit.given, given_max: 10, received: 2, received_max: 10, liked: visit.liked, noted: visit.noted, notes_today: 0, help_xp: 230 },
  };
}
// clima do mock: ?ver=chuva|neblina|nublado|sol|solforte|noite|entardecer|lua|bencaos|calor|mistica|aviso
function mockWeather(): FarmState['weather'] {
  const ver = new URLSearchParams(location.search).get('ver') ?? 'sol';
  const cond = ({ chuva: 'rain', neblina: 'fog', nublado: 'cloudy', solforte: 'hot_sun' } as Record<string, FarmState['weather']['cond']>)[ver] ?? 'sunny';
  const ev = ({ lua: 'lua_cheia', bencaos: 'chuva_de_bencaos', calor: 'calor_dourado', mistica: 'neblina_mistica', aviso: 'lua_cheia' } as Record<string, string>)[ver];
  // fuso em que agora é noite (eventos e "noite"), entardecer ou dia
  const want = ver === 'entardecer' ? 18 * 60 + 20 : ev || ver === 'noite' ? 21 * 60 : 11 * 60;
  let tz = 'America/Sao_Paulo', best = 1e9;
  for (let n = -12; n <= 12; n++) {
    const z = n === 0 ? 'Etc/GMT' : `Etc/GMT${n > 0 ? '+' : '-'}${Math.abs(n)}`;
    const m = localMinutes(z, Date.now());
    const d = Math.min(Math.abs(m - want), 1440 - Math.abs(m - want));
    if (d < best) { best = d; tz = z; }
  }
  const t = Date.now(), iso = (ms: number) => new Date(ms).toISOString();
  const start = ver === 'aviso' ? t + 6 * 60_000 : t - 10 * 60_000;
  const name = ev ? WEATHER.night_event.events.find((e) => e.id === ev)!.name_pt : '';
  return {
    tz, cond, part: 'day', forecast_hours: 1, warn_minutes: 10,
    forecast: [{ from: iso(t - 3600_000), to: iso(t + 2 * 3600_000), cond }, { from: iso(t + 2 * 3600_000), to: iso(t + 5 * 3600_000), cond: 'cloudy' }],
    event: ev ? { id: ev, name_pt: name, start: iso(start), end: iso(start + 45 * 60_000), active: ver !== 'aviso', forced: false } : null,
    bonus: { growth: cond === 'hot_sun' ? 0.1 : 0, account_xp: cond === 'rain' || cond === 'fog' ? 0.1 : 0, char_xp: cond === 'fog' ? 0.1 : 0, sales: ev || ver === 'noite' ? 0.05 : 0, moon: ev === 'lua_cheia' && ver !== 'aviso' ? 0.4 : 0 },
    account: { timezone: tz, confirmed: true, pending: null, pending_at: null, can_change_at: null },
  };
}

const mg: { arrows: string[]; limit: number; calm: boolean } = { arrows: [], limit: 0, calm: false };
state.inventory['seed:alface:rare'] = 1;
state.inventory.snack_cheese_bread = 4;
state.inventory['kit:uncommon'] = 3;
state.inventory['cloth_boots:rare'] = 1;
state.inventory['amulet_horseshoe:common'] = 2;

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
    // amigos e visitas
    const pid = (args.p_target ?? args.p_other) as string;
    if (['get_social', 'social_seen', 'friend_request', 'friend_respond', 'friend_remove', 'block_player', 'report_player'].includes(fn)) {
      if (fn === 'social_seen') for (const a of social.activity) a.new = false;
      if (fn === 'friend_respond') { const p = social.incoming.find((x) => x.id === pid)!; social.incoming = social.incoming.filter((x) => x !== p); if (args.p_accept) social.friends.push(p); }
      if (fn === 'friend_request') social.outgoing.push(P(pid, 'Novo amigo', 5, 0));
      if (fn === 'friend_remove') { social.friends = social.friends.filter((x) => x.id !== pid); social.outgoing = social.outgoing.filter((x) => x.id !== pid); }
      if (fn === 'block_player' && args.p_block) { social.friends = social.friends.filter((x) => x.id !== pid); social.blocked.push(P(pid, 'Bloqueado', 1, 0)); }
      if (fn === 'block_player' && !args.p_block) social.blocked = social.blocked.filter((x) => x.id !== pid);
      return structuredClone(social) as unknown as FarmState;
    }
    if (fn === 'search_players') return [P('u7', `${args.p_query}inho`, 8, 3, 'none'), P('u1', 'Joana', 14, 22, 'friend')] as unknown as FarmState;
    if (fn === 'visit_farm') return visitView((args.p_target as string) ?? 'u6') as unknown as FarmState;
    if (fn === 'like_farm') { visit.liked = true; return visitView(pid) as unknown as FarmState; }
    if (fn === 'send_note') { visit.noted = true; return visitView(pid) as unknown as FarmState; }
    if (fn === 'help_lot') { visit.given++; visit.cooldowns[args.p_lot as string] = new Date(Date.now() + 3600_000).toISOString(); return visitView(pid) as unknown as FarmState; }
    if (fn === 'get_village') return structuredClone(village) as unknown as FarmState;
    if (fn === 'village_donate') {
      const it = args.p_item as string | null, q = args.p_qty as number;
      const pts = it ? q * (village.per_unit[it] ?? 0) : q / village.gold_per_point;
      if (it) state.silo[it] -= q; else state.gold -= q;
      village.mine.points += pts; village.mine.total += pts;
      return structuredClone(village) as unknown as FarmState;
    }
    if (fn === 'star_buy') { village.stars.stars -= args.p_kind === 'pack' ? 5 : 2; if (args.p_kind === 'pack') village.stars.packs_week++; else village.stars.seeds_week++; return structuredClone(village) as unknown as FarmState; }
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
      for (const a of state.animals) if (a.state === 'growing' && a.ready_at! <= t && (args.p_target == null || state.houses[a.house_id].lot === args.p_target)) {
        const d = ANIMAL_BY_ID[a.animal_id];
        state.silo[d.product.id] = (state.silo[d.product.id] ?? 0) + 1; a.ready_at = t + d.produce_every_minutes * 60;
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
    if (fn === 'use_card' || fn === 'armory_place' || fn === 'sell_card') {
      const c = state.cards.find((x) => x.serial === args.p_serial)!;
      state.cards = state.cards.filter((x) => x !== c);
      if (fn === 'use_card') state.buffs = [...state.buffs.filter((b) => b.card_id !== c.card_id), { card_id: c.card_id, rarity: c.rarity, started_at: new Date().toISOString(), ends_at: new Date(Date.now() + 3600_000).toISOString(), coin_value: 0 }];
      if (fn === 'armory_place') state.armory.push({ card_id: c.card_id, rarity: c.rarity });
      if (fn === 'sell_card') state.gold += state.collector[c.rarity];
    }
    if (fn === 'cards_seen') { for (const n of state.new_cards) state.cards.push({ ...n, state: 'binder', inbox_until: null, seen: true }); state.new_cards = []; }
    if (fn === 'reroll_mission') state.reroll_used = true;
    if (fn === 'binder_expand') state.binder_slots += 20;
    if (fn === 'set_auto_sell') state.auto_sell = args.p_on ? [...state.auto_sell, args.p_item as string] : state.auto_sell.filter((x) => x !== args.p_item);
    if (fn === 'adopt_pet') state.pets.push({ pet_id: args.p_pet as string, affinity: 0, last_care: null, active: false, linked_class: null });
    if (fn === 'care_pet') { const p = state.pets.find((x) => x.pet_id === args.p_pet)!; p.affinity++; p.last_care = state.game_day; }
    if (fn === 'link_pet') { state.pets.find((x) => x.active)!.linked_class = args.p_class as string; state.pet!.linked = args.p_class as string; }
    if (fn === 'buy_animal') state.animals.push({ house_id: args.p_house as string, slot: args.p_slot as number, animal_id: args.p_animal as string, rarity: 'uncommon', state: 'growing', cycle_start: t, ready_at: t + 7200 });
    if (fn === 'remove_animal') state.animals = state.animals.filter((a) => !(a.house_id === args.p_house && a.slot === args.p_slot));
    if (fn === 'upgrade_house') { const h = state.houses[args.p_house as string]; h.tier++; h.slots += 4; }
    if (fn === 'start_minigame') {
      const r = args.p_route as string, n = args.p_vehicles as number;
      mg.arrows = Array.from({ length: EXP.minigame.arrows[r as keyof typeof EXP.minigame.arrows] + EXP.minigame.convoy_extra_arrows * (n - 1) }, () => ['up', 'down', 'left', 'right'][Math.floor(Math.random() * 4)]);
      mg.limit = (EXP.minigame.seconds[r as keyof typeof EXP.minigame.seconds] + EXP.minigame.convoy_extra_seconds * (n - 1) + (args.p_manager ? 1 : 0)) * 1000 * (args.p_calm ? 1.5 : 1);
      mg.calm = !!args.p_calm;
      return { id: 'mg', arrows: mg.arrows, limit_ms: mg.limit } as unknown as FarmState;
    }
    if (fn === 'launch_expedition') {
      const ev = evalMinigame(mg.arrows, args.p_keys as { k: string; t: number }[], mg.limit, mg.calm);
      const cargo = args.p_cargo as Record<string, number>;
      for (const [k, q] of Object.entries(cargo)) state.silo[k] -= q;
      for (const v of args.p_vehicles as string[]) {
        const veh = state.vehicles.find((x) => x.vehicle_id === v)!;
        const h = ROUTE_BY_ID[args.p_route as string].hours * VEHICLE_BY_ID[v].duration_multiplier;
        state.expeditions.push({ id: crypto.randomUUID(), convoy_id: 'c2', vehicle_id: v, route_id: args.p_route as string, cargo, insurance: 0, led: !!args.p_manager,
          minigame: ev.result, started_at: t, returns_at: t + h * 60, seq: 0, repeat_left: args.p_repeat ? 2 : 0, status: 'travel' }); // mock: 1 min por hora
        veh.durability -= 4;
      }
      return structuredClone({ ...state, minigame: { result: ev.result, robot: false } });
    }
    for (const x of state.expeditions) if (x.status === 'travel' && x.returns_at <= t) x.status = 'back';
    if (fn === 'collect_expeditions') {
      const got: CollectedTrip[] = [];
      for (const x of state.expeditions.filter((e) => e.status === 'back' && (args.p_vehicle == null || e.vehicle_id === args.p_vehicle))) {
        const fail = Math.random() < 0.3, gold = fail ? 0 : cargoValue(x.cargo, x.route_id, state.demand[x.route_id]);
        state.gold += gold;
        got.push({ id: x.id, vehicle_id: x.vehicle_id, route_id: x.route_id, seq: x.seq, outcome: fail ? 'fail' : 'success', gold, refund: fail ? 50 : 0, cargo: x.cargo,
          cargo_back: fail ? Object.fromEntries(Object.entries(x.cargo).map(([k, q]) => [k, Math.round(q * 0.7)])) : {}, loss_frac: fail ? 0.3 : null,
          drops: fail ? [] : ['kit:uncommon', 'amulet_clover:rare'], report: fail ? 'Um eixo quebrou e 30% da carga se perdeu.' : `Viagem tranquila até ${ROUTE_BY_ID[x.route_id].name_pt}. Carga vendida.`,
          insurance: x.insurance, minigame: x.minigame, chance: 0.9 });
      }
      state.expeditions = state.expeditions.filter((e) => !got.some((g) => g.id === e.id));
      return structuredClone({ ...state, collected: got });
    }
    if (fn === 'buy_vehicle') state.vehicles.push({ vehicle_id: args.p_vehicle as string, rarity: 'common', durability: 100, active: true, refurb_rarity: null, refurb_until: null });
    if (fn === 'repair_vehicle') state.vehicles.find((v) => v.vehicle_id === args.p_vehicle)!.durability = 100;
    if (fn === 'set_active_vehicle') for (const v of state.vehicles) v.active = v.vehicle_id === args.p_vehicle;
    void PETS;
    return structuredClone({ ...state, server_now: new Date().toISOString(), last_activity_at: new Date().toISOString() });
  },
};
