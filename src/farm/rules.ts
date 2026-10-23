// Regras da progressão como o cliente mostra (o servidor confere tudo de novo).
// Tudo sai da config: preço e nível por nº da compra, piso de nível por tipo, vizinhança e limpeza.
import { CROP_LIST, CROPS, FARM, LEVELS, LOT_RULES, MAP_RULES, PURCHASES, type Crop } from '../data';

export type LotOffer = {
  lot: string; type: string; n: number; cost: number; needLevel: number; needsDeed: boolean;
  neighbor: boolean; cleanupMinutes: number; daysOfIncome: number;
  problems: ('vizinho' | 'nivel' | 'escritura' | 'ouro' | 'fim')[];
};

/** minutos de limpeza da nª compra (sem Ferreiro até a fase 3: outra classe leva o multiplicador) */
export function cleanupMinutes(n: number, hasBlacksmith = false): number {
  const c = LOT_RULES.cleanup;
  return (c.base_minutes + c.per_purchase_minutes * n) * (hasBlacksmith ? 1 : c.other_class_multiplier);
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
export function lotOffer(lot: string, owned: Set<string>, level: number, deeds: number, gold: number): LotOffer | null {
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
    cleanupMinutes: cleanupMinutes(n), daysOfIncome: row.cost / income, problems,
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

export type TreeState = { lot_id: string; slot: number; fruit_id: string | null; planted_at: number | null; ready_at: number | null };

/** visual da árvore: muda no começo do 1º crescimento, adulta depois, com fruta perto da colheita */
export function treeLook(t: TreeState, now: number): 'empty' | 'sapling' | 'adult' | 'fruit' {
  if (!t.fruit_id || t.ready_at === null || t.planted_at === null) return 'empty';
  const c = CROPS[t.fruit_id];
  const [, mid, ripe] = FARM.visual.stage_thresholds;
  const firstGrowth = Math.abs(t.ready_at - t.planted_at - c.grow_minutes * 60) < 1;
  const cycle = firstGrowth ? c.grow_minutes * 60 : (c.regrow_minutes ?? c.grow_minutes) * 60;
  const progress = (now - (t.ready_at - cycle)) / cycle;
  if (firstGrowth && progress < mid) return 'sapling';
  return progress >= ripe ? 'fruit' : 'adult';
}

/** progresso de XP no nível atual, de 0 a 1 */
export function xpProgress(xp: number, toNext: number | null): number {
  if (!toNext) return 1;
  return Math.max(0, Math.min(1, xp / toNext));
}
