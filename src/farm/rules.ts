// Regras da progressão como o cliente mostra (o servidor confere tudo de novo).
// Tudo sai da config: preço e nível por nº da compra, piso de nível por tipo, vizinhança e limpeza.
import { CHARS, CLASSES, CROP_LIST, CROPS, FARM, LEVELS, LOT_RULES, MAP_RULES, PETS, PURCHASES, SKILL_TREE, type Crop } from '../data';

export type LotOffer = {
  lot: string; type: string; n: number; cost: number; needLevel: number; needsDeed: boolean;
  neighbor: boolean; cleanupMinutes: number; daysOfIncome: number;
  problems: ('vizinho' | 'nivel' | 'escritura' | 'ouro' | 'fim')[];
};

/** minutos de limpeza da nª compra: sem Ferreiro contratado, o dobro; o ramo Obras reduz (cleanupFx negativo) */
export function cleanupMinutes(n: number, hasBlacksmith = false, cleanupFx = 0): number {
  const c = LOT_RULES.cleanup;
  return (c.base_minutes + c.per_purchase_minutes * n) * (hasBlacksmith ? 1 : c.other_class_multiplier) * (1 + cleanupFx);
}

export function isNeighbor(lot: string, owned: Set<string>): boolean {
  const def = MAP_RULES.lots.find((l) => l.id === lot);
  if (!def) return false;
  return MAP_RULES.exempt_types.includes(def.type) || def.neighbors.some((nb) => owned.has(nb));
}

export function lotNeedLevel(type: string, purchaseMinLevel: number): number {
  const floors = LOT_RULES.min_level.type_floor as Record<string, number>;
  return Math.max(purchaseMinLevel, floors[type] ?? 0);
}

/** o que custa comprar o lote agora: o lote inicial conta, então com k lotes a próxima é a kª compra */
export function lotOffer(lot: string, owned: Set<string>, level: number, deeds: number, gold: number, hasBlacksmith = false, cleanupFx = 0): LotOffer | null {
  const def = MAP_RULES.lots.find((l) => l.id === lot);
  if (!def || owned.has(lot)) return null;
  const n = owned.size;
  const row = PURCHASES[n - 1];
  if (!row) return { lot, type: def.type, n, cost: 0, needLevel: 0, needsDeed: false, neighbor: false, cleanupMinutes: 0, daysOfIncome: 0, problems: ['fim'] };
  const needLevel = lotNeedLevel(def.type, row.min_level);
  const neighbor = isNeighbor(lot, owned);
  const problems: LotOffer['problems'] = [];
  if (!neighbor) problems.push('vizinho');
  if (level < needLevel) problems.push('nivel');
  if (row.requires_deed && deeds < 1) problems.push('escritura');
  if (gold < row.cost) problems.push('ouro');
  const income = LEVELS[Math.min(level, LEVELS.length) - 1].reference_income_per_day;
  return {
    lot, type: def.type, n, cost: row.cost, needLevel, needsDeed: row.requires_deed, neighbor,
    cleanupMinutes: cleanupMinutes(n, hasBlacksmith, cleanupFx), daysOfIncome: row.cost / income, problems,
  };
}

/** cultivos de canteiro (lavoura e recorrentes) liberados e os próximos ainda bloqueados */
export function plotCrops(level: number): { open: Crop[]; next: Crop[] } {
  const all = CROP_LIST.filter((c) => c.kind !== 'orchard');
  return {
    open: all.filter((c) => c.unlock_level <= level),
    next: all.filter((c) => c.unlock_level > level).slice(0, FARM.ui.locked_crops_preview),
  };
}

export function orchardFruits(level: number): { open: Crop[]; next: Crop[] } {
  const all = CROP_LIST.filter((c) => c.kind === 'orchard');
  return {
    open: all.filter((c) => c.unlock_level <= level),
    next: all.filter((c) => c.unlock_level > level).slice(0, FARM.ui.locked_crops_preview),
  };
}

export type TreeState = { lot_id: string; slot: number; fruit_id: string | null; planted_at: number | null; ready_at: number | null; rarity?: string | null; rare_left?: number };

/** visual da árvore: muda no começo do 1º crescimento, adulta depois, com fruta perto da colheita */
export function treeLook(t: TreeState, now: number): 'empty' | 'sapling' | 'adult' | 'fruit' {
  if (!t.fruit_id || t.ready_at === null || t.planted_at === null) return 'empty';
  const c = CROPS[t.fruit_id];
  const [, mid, ripe] = FARM.visual.stage_thresholds;
  // 1º crescimento: do plantio até a 1ª colheita (pode ser mais curto com habilidades); depois, ciclos de rebrota
  const firstGrowth = t.ready_at - t.planted_at <= c.grow_minutes * 60 + 1;
  const cycle = firstGrowth ? t.ready_at - t.planted_at : (c.regrow_minutes ?? c.grow_minutes) * 60;
  const progress = (now - (t.ready_at - cycle)) / cycle;
  if (firstGrowth && progress < mid) return 'sapling';
  return progress >= ripe ? 'fruit' : 'adult';
}

/** progresso de XP no nível atual, de 0 a 1 */
export function xpProgress(xp: number, toNext: number | null): number {
  if (!toNext) return 1;
  return Math.max(0, Math.min(1, xp / toNext));
}

// ---------- clique do jogador ----------
export type PlotLike = { plot_id: string; crop_id: string | null; state: 'empty' | 'growing'; ready_at: number | null; stalled_reason: string | null };
export type PlotLook = 'ready' | 'growing' | 'planned' | 'cleanup' | 'stalled' | 'empty';

/** o que o canteiro mostra e o que o clique faz: maduro colhe, planejado planta, vazio abre a escolha */
export function plotLook(p: PlotLike, now: number, lotReadyAt: number): PlotLook {
  if (p.state === 'growing') return p.ready_at !== null && p.ready_at <= now ? 'ready' : 'growing';
  if (!p.crop_id) return 'empty';
  if (lotReadyAt > now) return 'cleanup';
  if (p.stalled_reason) return 'stalled';
  return 'planned';
}

/** quantas coisas o botão "Colher e plantar" resolve agora (canteiros maduros ou à espera e árvores maduras) */
export function tendCount(s: { plots: PlotLike[]; trees: TreeState[]; lots: { lot_id: string; ready_at: number }[]; animals?: AnimalLike[] }, now: number): number {
  const ready = new Map(s.lots.map((l) => [l.lot_id, l.ready_at]));
  let n = 0;
  for (const p of s.plots) {
    const look = plotLook(p, now, ready.get(p.plot_id.split('-')[0]) ?? 0);
    if (look === 'ready' || look === 'planned') n++;
  }
  for (const t of s.trees) if (t.fruit_id && t.ready_at !== null && t.ready_at <= now) n++;
  for (const a of s.animals ?? []) if (animalLook(a, now) === 'ready') n++;
  return n;
}

// ---------- personagens (fase 3) ----------
export const classDef = (id: string) => CLASSES.find((c) => c.id === id)!;
const R = (level: number) => LEVELS[Math.min(Math.max(level, 1), LEVELS.length) - 1].reference_income_per_day;

/** contratação = 1,5 × Renda de Referência do nível em que a classe libera */
export function hireCost(classId: string): number {
  return Math.round(CHARS.hire_cost.multiplier * R(classDef(classId).unlock_level) * 100) / 100;
}

/** horas de trabalho do nível atual para o próximo (10 + 1,5 × nível) */
export function hoursToNext(level: number): number | null {
  const cl = CHARS.character_level;
  return level >= cl.max ? null : cl.base_hours + cl.per_level_hours * level;
}

/** pontos de habilidade: 1 por nível acima do 1º; quantos já foram gastos */
export function skillPoints(level: number, skills: Record<string, number>): { total: number; spent: number; free: number } {
  const total = (level - 1) * CHARS.character_level.skill_points_per_level;
  const spent = Object.values(skills).reduce((a, b) => a + b, 0);
  return { total, spent, free: Math.max(0, total - spent) };
}

/** o que dá para fazer num nó: máximo, se a Mestria está trancada e se o efeito só liga numa fase futura */
export function skillNodeState(classId: string, branchId: string, part: 'a' | 'b' | 'm', skills: Record<string, number>) {
  const br = SKILL_TREE[classId].find((b) => b.id === branchId)!;
  const node = part === 'm' ? br.mastery : br[part];
  const max = part === 'm' ? CHARS.skills.mastery_points : CHARS.skills.node_max;
  const pts = skills[`${branchId}.${part}`] ?? 0;
  const locked = part === 'm' && ((skills[`${branchId}.a`] ?? 0) < CHARS.skills.node_max || (skills[`${branchId}.b`] ?? 0) < CHARS.skills.node_max);
  const future = (node.phase ?? 0) > CHARS.active_phase ? node.phase! : null;
  return { node, max, pts, locked, full: pts >= max, future };
}

/** nível do pet pela afinidade acumulada (1 carinho por dia) e o fator do efeito (40% → 100%) */
export function petLevel(affinity: number): number {
  return 1 + PETS.affinity_to_level.filter((a) => affinity >= a).length;
}
export function petFactor(level: number): number {
  return PETS.effect_at_level_1 + ((PETS.effect_at_level_5 - PETS.effect_at_level_1) * (level - 1)) / 4;
}
/** carinhos que faltam para o próximo nível (null no 5) */
export function petNextIn(affinity: number): number | null {
  const next = PETS.affinity_to_level.find((a) => a > affinity);
  return next === undefined ? null : next - affinity;
}

/** dias de espera que faltam para trocar o pet ativo */
export function petSwapWaitDays(swappedAt: string | null, now: Date): number {
  if (!swappedAt) return 0;
  const left = new Date(swappedAt).getTime() + PETS.swap_wait_days * 86_400_000 - now.getTime();
  return left > 0 ? Math.ceil(left / 86_400_000) : 0;
}

/** sementes raras no inventário: chave seed:<cultivo>:<raridade> */
export function rareSeeds(inventory: Record<string, number>, crop?: string): { crop: string; rarity: string; qty: number }[] {
  return Object.entries(inventory).filter(([k, q]) => k.startsWith('seed:') && q > 0)
    .map(([k, qty]) => { const [, c, rarity] = k.split(':'); return { crop: c, rarity, qty }; })
    .filter((x) => !crop || x.crop === crop);
}

// ---------- animais (fase 4) ----------
export type AnimalLike = { state: 'growing' | 'hungry'; ready_at: number | null };
/** pronto (espera o clique ou a equipe), produzindo ou com fome (sem ouro para a ração) */
export function animalLook(a: AnimalLike, now: number): 'ready' | 'growing' | 'hungry' {
  if (a.state === 'hungry') return 'hungry';
  return a.ready_at !== null && a.ready_at <= now ? 'ready' : 'growing';
}

/** ração de 1 ciclo do animal (ração/dia × duração do ciclo, com desconto) */
export function feedPerCycle(feedPerDay: number, cycleMinutes: number, discount = 0): number {
  return Math.round(feedPerDay * cycleMinutes / 1440 * (1 - discount) * 100) / 100;
}

/** valor esperado de 1 coleta: raridade × (1 + bônus com teto, Lago nas aves) */
export function collectUnits(rarityMult: number, bonus: number, cap: number, lakeBird: boolean, lakeBonus: number): number {
  return rarityMult * (1 + Math.min(cap, bonus + (lakeBird ? lakeBonus : 0)));
}
