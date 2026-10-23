// Simulador de economia (fase 0): 160 dias, hora a hora, para os perfis casual, regular e dedicado.
// Lê só config/*.json e tools/sim/profiles.json. O que é modelado em detalhe: lotes e limpeza, escolha de
// cultivo pela mão de obra, pomar, animais (com raridade), personagens (energia, salário, nível, ferramenta e
// desgaste), venda por expedição ou Barraca (rotas, veículos, raridade, Gerente, Escrituras, kits), missões,
// cartas (sorteio com garantia, buff ou Armory) e pet. Clima e evento noturno entram pela média da seção 10.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const cfg = (name: string) => JSON.parse(readFileSync(join(root, 'config', `${name}.json`), 'utf8'));
export const CFG = {
  levels: cfg('levels'), crops: cfg('crops'), animals: cfg('animals'), lots: cfg('lots'), chars: cfg('characters'),
  exp: cfg('expeditions'), missions: cfg('missions'), weather: cfg('weather'), cards: cfg('cards'),
  tools: cfg('tools_and_items'), rarity: cfg('rarity'),
};
export const SIM = JSON.parse(readFileSync(join(root, 'tools', 'sim', 'profiles.json'), 'utf8'));

/** XP para o próximo nível a partir da curva da config: começo fixo e uma escala por faixa de níveis */
export function xpTable(scales: number[] = CFG.levels.xp_curve.bands.map((b: any) => b.scale)): number[] {
  const c = CFG.levels.xp_curve, out: number[] = [];
  for (const l of CFG.levels.levels) {
    if (l.xp_base == null) { out[l.level] = Infinity; continue; }
    const early = c.early[String(l.level)];
    const band = c.bands.findIndex((b: any) => l.level >= b.levels[0] && l.level <= b.levels[1]);
    out[l.level] = early ?? Math.round((l.xp_base * (band >= 0 ? scales[band] : 1)) / 10) * 10;
    // nunca pede menos XP que o nível anterior (a troca de faixa não pode fazer degrau para baixo)
    if (l.level > 1 && Number.isFinite(out[l.level - 1])) out[l.level] = Math.max(out[l.level], out[l.level - 1]);
  }
  return out;
}

const round2 = (x: number) => { const p = Math.pow(10, Math.floor(Math.log10(x)) - 1); return Math.round(x / p) * p; };

// ---------- cultivos: ouro, trabalho e XP por canteiro-hora ----------
type CropRate = { id: string; level: number; gold: number; work: number; xp: number; units: number; seed: number };
const WU = CFG.crops.rules.work_units;
function cropRates(): CropRate[] {
  return CFG.crops.crops.filter((c: any) => c.kind !== 'orchard').map((c: any) => {
    const v = c.units_per_harvest * c.fair_price_per_unit;
    if (c.kind === 'crop') {
      const h = c.grow_minutes / 60;
      return { id: c.id, level: c.unlock_level, gold: (v - c.seed_cost) / h, work: WU.plant_and_harvest / h, xp: c.xp_per_harvest / h, units: c.units_per_harvest / h, seed: c.seed_cost / h };
    }
    const h = (c.grow_minutes + 4 * c.regrow_minutes) / 60;
    return { id: c.id, level: c.unlock_level, gold: (5 * v - c.seed_cost) / h, work: (WU.plant_and_harvest + 4 * WU.extra_harvest_recurring_or_tree) / h, xp: (5 * c.xp_per_harvest) / h, units: (5 * c.units_per_harvest) / h, seed: c.seed_cost / h };
  });
}
const CROPS = cropRates();
const FRUITS = CFG.crops.crops.filter((c: any) => c.kind === 'orchard').map((c: any) => ({
  id: c.id, level: c.unlock_level, grow_h: c.grow_minutes / 60, regrow_h: c.regrow_minutes / 60,
  gold: (c.units_per_harvest * c.fair_price_per_unit) / (c.regrow_minutes / 60), units: c.units_per_harvest / (c.regrow_minutes / 60),
  xp: c.xp_per_harvest / (c.regrow_minutes / 60), work: WU.extra_harvest_recurring_or_tree / (c.regrow_minutes / 60), sapling: c.sapling_cost,
}));

// melhor uso de P canteiros com L unidades de trabalho/h (no máximo 2 cultivos, como num problema linear com 1 restrição)
export function bestPlan(level: number, P: number, L: number): { gold: number; xp: number; units: number; seed: number } {
  const avail = CROPS.filter((c) => c.level <= level);
  let best = { gold: 0, xp: 0, units: 0, seed: 0 };
  const consider = (g: number, x: number, u: number, sd: number) => { if (g > best.gold) best = { gold: g, xp: x, units: u, seed: sd }; };
  for (const a of avail) {
    const n = Math.min(P, L / a.work);
    consider(n * a.gold, n * a.xp, n * a.units, n * a.seed);
    for (const b of avail) {
      if (b.work >= a.work || b.gold >= a.gold) continue; // a: mais trabalho e mais ouro; b: mais leve
      if (L < P * b.work || L > P * a.work) continue;
      const x = (L - P * b.work) / (a.work - b.work);
      consider(x * a.gold + (P - x) * b.gold, x * a.xp + (P - x) * b.xp, x * a.units + (P - x) * b.units, x * a.seed + (P - x) * b.seed);
    }
  }
  return best;
}

// ---------- sorteio determinístico ----------
function rng(seed: number) {
  let s = seed >>> 0;
  return () => { s += 0x6d2b79f5; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

export type SimParams = { workPerHour: number; R: number[]; seed?: number; recordIncome?: boolean; xpNext?: number[] };
export type SimResult = {
  profile: string; levelDay: number[]; mapCompleteDay: number; maxGoldWait: number; buys: { n: number; day: number; wait: number; deedWait: number }[];
  spend: Record<string, number>; atMapComplete: Record<string, number> | null; income: number; salaries: number; toolRepairs: number; feed: number; seeds: number; incomeByLevel: number[]; daysByLevel: number[];
  armoryBonus: number; armoryAllPartialDay: number; cards: number; finalLevel: number; lotsOwned: number; vehicleRarity: Record<string, string>;
};

const RAR = CFG.rarity.tiers.map((t: any) => t.id) as string[];
const RAR_MULT: Record<string, number> = Object.fromEntries(CFG.rarity.tiers.map((t: any) => [t.id, t.multiplier]));
const ANIMAL_AVG = CFG.rarity.tiers.reduce((s: number, t: any) => s + t.multiplier * CFG.rarity.animals.purchase_odds[t.id], 0);

export function simulate(profileId: string, p: SimParams): SimResult {
  const prof = SIM.profiles[profileId];
  const XP_NEXT = p.xpNext ?? xpTable();
  const rand = rng(p.seed ?? 7);
  const R = (L: number) => p.R[Math.min(50, Math.max(1, L))];
  const days = SIM.days;
  const sessions = new Set<number>();
  for (let d = 0; d < days; d++) for (const h of prof.sessions) sessions.add(d * 24 + h);
  const sessionList = [...sessions].sort((a, b) => a - b);

  // ----- estado -----
  let gold = CFG.levels.starting_gold as number;
  let level = 1, xp = 0;
  const levelDay: number[] = []; levelDay[1] = 0;
  const lotsRules = CFG.lots.rules;
  const order = CFG.lots.simulated_order as any[];
  const lotCost = (n: number) => round2(lotsRules.cost.base * Math.pow(lotsRules.cost.growth, n - 1) * R(Math.min(50, Math.ceil(lotsRules.min_level.k * n - 1e-9))));
  const lotLevel = (o: any) => Math.max(Math.min(50, Math.ceil(lotsRules.min_level.k * o.n - 1e-9)), lotsRules.min_level.type_floor[o.type] ?? 0);
  let nextLot = 0;
  let plots = 8, farmlandPending: { at: number; type: string }[] = [];
  const houses: Record<string, { owned: boolean; slots: number; tier: number; animal: any | null; count: number }> = {
    galinheiro: { owned: false, slots: 0, tier: 0, animal: null, count: 0 },
    celeiro: { owned: false, slots: 0, tier: 0, animal: null, count: 0 },
  };
  let lake = false;
  const orchards: { fruit: any | null; readyAt: number }[] = [];
  let deeds = 0;
  const buys: { n: number; day: number; wait: number; deedWait: number }[] = [];
  let prevBuyT = 0;
  let deedReadyT = -1; // quando o próximo lote passou a ter Escritura

  type Char = { id: string; role: string; hired: boolean; unlock: number; mat: number; dura: number; hours: number; lvl: number };
  const chars: Char[] = CFG.chars.classes.map((c: any) => ({ id: c.id, role: c.role, hired: !!c.hired, unlock: c.unlock_level, mat: 0, dura: 100, hours: 0, lvl: 1 }));
  const mats = CFG.tools.tool_materials;
  const dur = CFG.tools.tool_durability_rules;
  const has = (id: string) => chars.find((c) => c.id === id)!.hired;

  type Veh = { def: any; owned: boolean; rarity: number };
  const vehicles: Veh[] = CFG.exp.vehicles.map((v: any) => ({ def: v, owned: v.cost === 0, rarity: 0 }));
  const kits: number[] = [0, 0, 0, 0, 0]; // por raridade (índice 1..4)

  // cartas
  const armory: boolean[][] = CFG.cards.cards.map(() => [false, false, false, false, false]);
  const pity = { rare: 0, legendary: 0, mythic: 0 };
  let cardsDrawn = 0;
  let armoryAllPartialDay = Infinity;
  let pendingBuffGold = 0;

  // contabilidade
  let income = 0, salaries = 0, toolRepairs = 0, feed = 0, seeds = 0;
  const spend: Record<string, number> = { lots: 0, hires: 0, tools: 0, vehicles: 0, refurbish: 0, animals: 0, houses: 0 };
  let atMapComplete: Record<string, number> | null = null; // fotografia dos gastos no dia do último lote
  const incomeByLevel: number[] = new Array(51).fill(0), hoursByLevel: number[] = new Array(51).fill(0);
  let silo = { value: 0, units: 0 };
  let lastSession = -999;
  let freePerHour = 0; // trabalho grátis do jogador (cliques na sessão), espalhado até a próxima sessão
  let hourlyIncomeEMA = 300, hourlyXpEMA = 50;
  let petSince = -1;
  let dayIncome = 0, dayXp = 0;
  let weekMissions = 0;

  const weatherIncome = 1 + CFG.weather.average_bonus.income;
  const weatherXp = 1 + CFG.weather.average_bonus.xp;
  const armoryBonus = () => armory.reduce((s, a) => s + (a.every(Boolean) ? 0.05 : a[0] && a[1] && a[2] ? 0.02 : 0), 0);
  const skillBonus = () => chars.filter((c) => c.hired).reduce((s, c) => s + ((c.lvl - 1) / CFG.chars.skills.points_per_branch / CFG.chars.skills.branches) * CFG.chars.skills.full_tree_income_estimate, 0);
  const petFactor = (t: number) => (petSince < 0 ? 0 : Math.min(1, 0.4 + 0.6 * ((t - petSince) / 24) / CFG.chars.pets.days_to_max));
  const salesBonus = (t: number) => 1 + 0.04 * petFactor(t); // Papagaio
  const incomeMult = (t: number) => weatherIncome * (1 + armoryBonus() + skillBonus()) * salesBonus(t);

  const upkeepPerDay = () => {
    let s = 0;
    for (const c of chars) if (c.hired && c.id !== 'agricultor') s += CFG.chars.salary.share_of_R * R(level) * (1 + CFG.chars.salary.per_character_level * c.lvl);
    for (const h of Object.values(houses)) if (h.animal) s += h.count * h.animal.feed_cost_per_day;
    return s;
  };
  const reserve = () => upkeepPerDay() * SIM.reserve_days_of_upkeep;

  // capacidade de trabalho por hora (rodízio: no máximo 3 em campo, cada um trabalha 2/3 do tempo)
  const workCapacity = () => {
    const hired = chars.filter((c) => c.hired);
    const caps = hired.map((c) => p.workPerHour * mats[c.mat].work_capacity_multiplier
      * (c.role === 'crops' || c.role === 'animals_orchard' ? 1 : CFG.chars.off_role_efficiency)
      * (c.dura < dur.low_durability_threshold ? dur.low_durability_capacity_penalty_multiplier : 1));
    const working = Math.min(CFG.chars.field_slots, (hired.length * 2) / 3);
    return { total: working * (caps.reduce((a, b) => a + b, 0) / hired.length), frac: working / hired.length };
  };

  const nextSessionAfter = (t: number) => { for (const s of sessionList) if (s > t) return s; return t + 24; };

  // ----- decisões numa sessão -----
  function session(t: number) {
    const day = Math.floor(t / 24);
    // consertar ferramentas abaixo de 50% (até a próxima sessão não cai abaixo de 30%)
    for (const c of chars) if (c.hired && c.dura < 50) {
      const cost = c.mat === 0 ? dur.wood_repair_flat_cost_gold : mats[c.mat].upgrade_cost_gold * dur.repair_cost_ratio_of_material_cost;
      if (gold >= cost) { gold -= cost; toolRepairs += cost; c.dura = 100; }
    }
    sell(t);
    // missões e cartas: uma vez por dia, na primeira sessão
    if (sessionList.find((s) => Math.floor(s / 24) === day) === t) dailyMissions(t, day);
    buyStuff(t);
    lastSession = t;
    // jogo aberto: o jogador colhe e planta tudo com cliques, sem gastar trabalho do Agricultor.
    // Isso vale 1 ciclo por canteiro e 1 colheita por árvore até a próxima sessão (no máximo o limite offline).
    const gap = Math.min(nextSessionAfter(t) - t, SIM.offline_cap_hours);
    freePerHour = SIM.click_play ? (plots * WU.plant_and_harvest + 4 * orchards.length * WU.harvest) / gap : 0;
  }

  function sell(t: number) {
    if (silo.units <= 0) return;
    const gap = nextSessionAfter(t) - t;
    const manager = has('gerente');
    let remainingUnits = silo.units;
    const perUnit = silo.value / silo.units;
    let revenue = 0;
    const owned = vehicles.filter((v) => v.owned).sort((a, b) => b.def.capacity - a.def.capacity);
    owned.forEach((v, i) => {
      if (remainingUnits <= 0) return;
      const mult = RAR_MULT[RAR[v.rarity]];
      const maxIdx = CFG.exp.routes.findIndex((r: any) => r.id === v.def.max_route);
      let bestVal = 0, bestRoute: any = null, bestTrips = 0;
      CFG.exp.routes.forEach((r: any, k: number) => {
        if (k > maxIdx || r.unlock_level > level) return;
        const useMgr = manager && i === 0;
        const pts = v.def.safety_pts * mult + (useMgr ? CFG.exp.manager.success_pts : 0) + prof.minigame_pts + SIM.weather_success_pts_avg
          + (petSince >= 0 ? 0 : 0);
        const ps = Math.min(CFG.exp.success_cap, r.success + pts / 100);
        const pc = CFG.exp.crit.chance;
        const loss = (r.loss[0] + r.loss[1]) / 2;
        const ev = r.price_multiplier * ((ps - pc) + pc * (1 + CFG.exp.crit.bonus_value) + (1 - ps) * (1 - loss));
        const hours = r.hours * v.def.duration_multiplier / mult * (useMgr ? CFG.exp.manager.duration_multiplier : 1);
        const trips = Math.min(1 + CFG.exp.auto_repeat_max, gap / hours);
        const units = Math.min(remainingUnits, v.def.capacity * mult * trips);
        // valor esperado contra vender o mesmo na Barraca
        const gain = units * (ev - CFG.exp.stall_price_ratio);
        if (gain > bestVal) { bestVal = gain; bestRoute = { r, ev, units, trips: units / (v.def.capacity * mult) }; bestTrips = trips; }
      });
      if (!bestRoute) return;
      revenue += bestRoute.units * perUnit * bestRoute.ev;
      remainingUnits -= bestRoute.units;
      const tr = bestRoute.trips;
      deeds += tr * bestRoute.r.deed_chance;
      for (const [rar, share] of Object.entries(bestRoute.r.kit_rarity)) kits[RAR.indexOf(rar)] += tr * bestRoute.r.kit_chance * (share as number);
    });
    revenue += remainingUnits * perUnit * CFG.exp.stall_price_ratio;
    const got = revenue * incomeMult(t);
    gold += got; income += got; dayIncome += got; incomeByLevel[level] += got;
    silo = { value: 0, units: 0 };
  }

  let nowH = 0;
  function drawCard(): void {
    cardsDrawn++;
    let r: number;
    const u = rand();
    const odds = CFG.cards.gacha.base_rates;
    r = u < odds.mythic ? 4 : u < odds.mythic + odds.legendary ? 3 : u < odds.mythic + odds.legendary + odds.rare ? 2 : u < 1 - odds.common ? 1 : 0;
    const th = CFG.cards.gacha.pity_thresholds;
    if (pity.mythic + 1 >= th.mythic) r = 4; else if (pity.legendary + 1 >= th.legendary_or_better) r = Math.max(r, 3); else if (pity.rare + 1 >= th.rare_or_better) r = Math.max(r, 2);
    pity.rare = r >= 2 ? 0 : pity.rare + 1; pity.legendary = r >= 3 ? 0 : pity.legendary + 1; pity.mythic = r >= 4 ? 0 : pity.mythic + 1;
    const card = Math.floor(rand() * armory.length);
    if (!armory[card][r]) { // Armory primeiro
      armory[card][r] = true;
      if (armoryAllPartialDay === Infinity && armory.every((a) => a[0] && a[1] && a[2])) armoryAllPartialDay = nowH / 24;
      return;
    }
    const minutes = CFG.cards.rarities[RAR[r]].target_production_minutes_value;
    pendingBuffGold += (minutes / 60) * hourlyIncomeEMA;
  }

  function dailyMissions(t: number, day: number) {
    const done = rand() < prof.daily_missions_done_prob;
    const n = done ? CFG.missions.daily.count : SIM.missions_done_on_other_days;
    const g = n * CFG.missions.daily.gold_hours_of_income * hourlyIncomeEMA;
    gold += g; income += g; incomeByLevel[level] += g; dayIncome += g;
    addXp(n * CFG.missions.daily.xp_hours_of_production * hourlyXpEMA, t);
    if (done && weekMissions < CFG.missions.daily.max_packs_per_week) { weekMissions++; drawCard(); }
    if (day % 7 === 6) { // fim da semana
      if (rand() < prof.weekly_3_prob) drawCard();
      if (rand() < prof.weekly_5_prob) { drawCard(); deeds += CFG.missions.weekly.deed_at_5; }
      weekMissions = 0;
    }
    if (pendingBuffGold > 0) { gold += pendingBuffGold; income += pendingBuffGold; incomeByLevel[level] += pendingBuffGold; pendingBuffGold = 0; }
  }

  function addXp(amount: number, t: number) {
    xp += amount;
    while (level < 50 && xp >= XP_NEXT[level]) {
      xp -= XP_NEXT[level]; level++; levelDay[level] = t / 24;
      if (level >= CFG.chars.pets.unlock_level && petSince < 0) petSince = t;
    }
  }

  function buyStuff(t: number) {
    let guard = 0;
    while (guard++ < 50) {
      const res = reserve();
      // 1. contratar
      const nextHire = chars.find((c) => !c.hired && c.unlock <= level);
      if (nextHire) {
        const cost = CFG.chars.hire_cost.multiplier * R(nextHire.unlock);
        if (gold - cost >= res) { gold -= cost; spend.hires += cost; nextHire.hired = true; continue; }
      }
      // 2. lote
      let lotBlockedByLevel = true;
      if (nextLot < order.length) {
        const o = order[nextLot];
        const needDeed = o.n >= lotsRules.deed.required_from_purchase;
        if (lotLevel(o) <= level && (!needDeed || deeds >= 1) && deedReadyT < 0) deedReadyT = t;
        if (lotLevel(o) <= level && (!needDeed || deeds >= 1)) {
          lotBlockedByLevel = false;
          const cost = lotCost(o.n);
          if (gold - cost >= res) {
            gold -= cost; spend.lots += cost; if (needDeed) deeds -= 1;
            const avail = Math.max(prevBuyT, levelDay[lotLevel(o)] * 24);
            // espera por ouro conta a partir de quando havia nível e Escritura; o resto foi espera por Escritura
            buys.push({ n: o.n, day: t / 24, wait: (t - Math.max(avail, deedReadyT)) / 24, deedWait: Math.max(0, deedReadyT - avail) / 24 });
            deedReadyT = -1;
            prevBuyT = t;
            const cleanupH = (lotsRules.cleanup.base_minutes + lotsRules.cleanup.per_purchase_minutes * o.n) / 60 * (has('ferreiro') ? 1 : lotsRules.cleanup.other_class_multiplier);
            farmlandPending.push({ at: t + cleanupH, type: o.type });
            nextLot++;
            if (nextLot >= order.length) atMapComplete = { ...spend, income: income + seeds, seeds, salaries, repairs: toolRepairs, feed, goldLeft: gold };
            continue;
          }
        }
      }
      const secondaryOk = (cost: number) => gold - cost >= res && (lotBlockedByLevel || cost <= SIM.secondary_purchase_max_share_of_gold * gold);
      // 3. animais: encher vagas e trocar pelo melhor liberado
      let did = false;
      for (const [hid, h] of Object.entries(houses)) {
        if (!h.owned) continue;
        const best = CFG.animals.animals.filter((a: any) => a.house === hid && a.unlock_level <= level).pop();
        if (!best) continue;
        const slots = h.slots + (lake && hid === 'galinheiro' && best.is_bird ? CFG.animals.rules.lake_bonus.extra_galinheiro_slots : 0);
        if (h.animal !== best) {
          const cost = best.buy_cost * slots;
          if (secondaryOk(cost) || (!h.animal && gold - cost >= res)) { gold -= cost; spend.animals += cost; h.animal = best; h.count = slots; did = true; }
        } else if (h.count < slots && gold - best.buy_cost >= res) { gold -= best.buy_cost; spend.animals += best.buy_cost; h.count++; did = true; }
        // ampliação da casa
        const up = CFG.animals.houses[hid].slots[h.tier + 1];
        if (up && up.min_level <= level && secondaryOk(up.cost)) { gold -= up.cost; spend.houses += up.cost; h.tier++; h.slots = up.slots; did = true; }
      }
      if (did) continue;
      // 4. pomar: trocar pela melhor fruta liberada
      for (const o of orchards) {
        const best = FRUITS.filter((f: any) => f.level <= level).pop();
        if (best && (!o.fruit || best.gold >= SIM.orchard_replant_gain * o.fruit.gold)) {
          const cost = 4 * best.sapling;
          if (secondaryOk(cost) || (!o.fruit && gold - cost >= res)) { gold -= cost; seeds += cost; o.fruit = best; o.readyAt = t + best.grow_h; did = true; }
        }
      }
      if (did) continue;
      // 5. veículos e reforma
      const nextVeh = vehicles.find((v) => !v.owned && v.def.unlock_level <= level);
      if (nextVeh && secondaryOk(nextVeh.def.cost)) { gold -= nextVeh.def.cost; spend.vehicles += nextVeh.def.cost; nextVeh.owned = true; continue; }
      for (const v of vehicles) {
        if (!v.owned || v.rarity >= 4) continue;
        const rf = CFG.exp.refurbish[v.rarity];
        // kits iguais viram 1 da raridade acima
        for (let k = 1; k < 4; k++) while (kits[k] >= CFG.exp.kit_merge) { kits[k] -= CFG.exp.kit_merge; kits[k + 1] += 1; }
        const cost = rf.cost_ratio * (v.def.cost || v.def.reference_cost);
        if (rf.min_level <= level && kits[v.rarity + 1] >= 1 && secondaryOk(cost)) { gold -= cost; spend.refurbish += cost; kits[v.rarity + 1] -= 1; v.rarity++; did = true; }
      }
      if (did) continue;
      // 6. ferramentas: melhorar o material de quem trabalha mais na fazenda
      const cand = chars.filter((c) => c.hired && c.mat < 4 && mats[c.mat + 1].unlock_level <= level)
        .sort((a, b) => a.mat - b.mat || (a.role === 'crops' || a.role === 'animals_orchard' ? -1 : 1));
      if (cand.length && secondaryOk(mats[cand[0].mat + 1].upgrade_cost_gold)) { gold -= mats[cand[0].mat + 1].upgrade_cost_gold; spend.tools += mats[cand[0].mat + 1].upgrade_cost_gold; cand[0].mat++; cand[0].dura = 100; continue; }
      break;
    }
  }

  // ----- relógio -----
  const totalH = days * 24;
  for (let t = 0; t < totalH; t++) {
    nowH = t;
    // lotes que terminaram a limpeza
    farmlandPending = farmlandPending.filter((f) => {
      if (f.at > t) return true;
      if (f.type === 'lavoura') plots += 8;
      else if (f.type === 'pomar') orchards.push({ fruit: null, readyAt: Infinity });
      else if (f.type === 'pasto_lago') lake = true;
      else { const h = houses[f.type === 'pasto_galinheiro' ? 'galinheiro' : 'celeiro']; h.owned = true; h.slots = CFG.animals.houses[f.type === 'pasto_galinheiro' ? 'galinheiro' : 'celeiro'].slots[0].slots; }
      return false;
    });
    if (sessions.has(t)) session(t);
    // salário à meia-noite
    if (t % 24 === 0 && t > 0) {
      for (const c of chars) if (c.hired && c.id !== 'agricultor') {
        const s = CFG.chars.salary.share_of_R * R(level) * (1 + CFG.chars.salary.per_character_level * c.lvl);
        const paid = Math.min(gold, s); gold -= paid; salaries += paid;
      }
      hourlyIncomeEMA = 0.7 * hourlyIncomeEMA + 0.3 * (dayIncome / 24);
      hourlyXpEMA = 0.7 * hourlyXpEMA + 0.3 * (dayXp / 24);
      dayIncome = 0; dayXp = 0;
    }
    hoursByLevel[level]++;
    if (t - lastSession >= SIM.offline_cap_hours) continue; // limite offline de 8 h
    // produção desta hora
    const cap = workCapacity();
    let labor = cap.total + freePerHour;
    let value = 0, units = 0, gainXp = 0;
    for (const o of orchards) if (o.fruit && t >= o.readyAt) {
      const need = 4 * o.fruit.work;
      const f = Math.min(1, labor / need); labor -= need * f;
      value += 4 * o.fruit.gold * f; units += 4 * o.fruit.units * f; gainXp += 4 * o.fruit.xp * f;
    }
    const plan = bestPlan(level, plots, Math.max(0, labor));
    value += plan.gold; units += plan.units; gainXp += plan.xp; seeds += plan.seed;
    const rancheira = has('rancheira');
    for (const [hid, h] of Object.entries(houses)) if (h.animal && h.count > 0) {
      const a = h.animal;
      const perH = (a.product.fair_price_per_unit / (a.produce_every_minutes / 60)) * ANIMAL_AVG
        * (rancheira ? CFG.animals.rules.collector_efficiency.rancheira : CFG.animals.rules.collector_efficiency.other_class)
        * (lake && hid === 'galinheiro' && a.is_bird ? 1 + CFG.animals.rules.lake_bonus.bird_production : 1);
      value += h.count * perH; units += h.count / (a.produce_every_minutes / 60);
      gainXp += h.count * a.xp_per_collect / (a.produce_every_minutes / 60);
      const f = h.count * a.feed_cost_per_day / 24; gold -= Math.min(gold, f); feed += f;
    }
    silo.value += value; silo.units += units;
    const x = gainXp * weatherXp * 1.15; // +15% de XP das expedições
    addXp(x, t); dayXp += x;
    // personagens: horas, nível e desgaste
    for (const c of chars) if (c.hired) {
      c.hours += cap.frac;
      while (c.lvl < CFG.chars.character_level.max && c.hours >= CFG.chars.character_level.base_hours + CFG.chars.character_level.per_level_hours * c.lvl) {
        c.hours -= CFG.chars.character_level.base_hours + CFG.chars.character_level.per_level_hours * c.lvl; c.lvl++;
      }
      c.dura = Math.max(0, c.dura - dur.loss_per_work_hour * cap.frac);
    }
  }

  const daysByLevel = hoursByLevel.map((h) => h / 24);
  const vehicleRarity = Object.fromEntries(vehicles.filter((v) => v.owned).map((v) => [v.def.id, RAR[v.rarity]]));
  return {
    profile: profileId, levelDay, mapCompleteDay: nextLot >= order.length ? buys[buys.length - 1].day : Infinity,
    maxGoldWait: Math.max(...buys.map((b) => b.wait)), buys, spend, atMapComplete, income, salaries, toolRepairs, feed, seeds,
    incomeByLevel, daysByLevel, armoryBonus: armoryBonus(), armoryAllPartialDay, cards: cardsDrawn, finalLevel: level, lotsOwned: 1 + nextLot, vehicleRarity,
  };
}

// Só cartas: em que semana o jogador fecha o bônus parcial (Comum + Incomum + Raro) nas 10 cartas, sem mercado.
// Usa a mesma regra de sorteio e garantia; guarda no Armory primeiro.
export function armoryPartialWeek(profileId: string, seed: number, maxWeeks = 156): number {
  const prof = SIM.profiles[profileId];
  const rand = rng(seed);
  const odds = CFG.cards.gacha.base_rates, th = CFG.cards.gacha.pity_thresholds;
  const armory: boolean[][] = CFG.cards.cards.map(() => [false, false, false, false, false]);
  const pity = { rare: 0, legendary: 0, mythic: 0 };
  const draw = () => {
    const u = rand();
    let r = u < odds.mythic ? 4 : u < odds.mythic + odds.legendary ? 3 : u < odds.mythic + odds.legendary + odds.rare ? 2 : u < 1 - odds.common ? 1 : 0;
    if (pity.mythic + 1 >= th.mythic) r = 4; else if (pity.legendary + 1 >= th.legendary_or_better) r = Math.max(r, 3); else if (pity.rare + 1 >= th.rare_or_better) r = Math.max(r, 2);
    pity.rare = r >= 2 ? 0 : pity.rare + 1; pity.legendary = r >= 3 ? 0 : pity.legendary + 1; pity.mythic = r >= 4 ? 0 : pity.mythic + 1;
    armory[Math.floor(rand() * armory.length)][r] = true;
  };
  for (let w = 1; w <= maxWeeks; w++) {
    let packs = 0;
    for (let d = 0; d < 7; d++) if (rand() < prof.daily_missions_done_prob && packs < CFG.missions.daily.max_packs_per_week) { packs++; draw(); }
    if (rand() < prof.weekly_3_prob) draw();
    if (rand() < prof.weekly_5_prob) draw();
    if (armory.every((a) => a[0] && a[1] && a[2])) return w;
  }
  return Infinity;
}
