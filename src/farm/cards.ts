// Cartas e missões no cliente: só textos e contas para mostrar; quem decide tudo é o servidor.
import { CARDS, MISSIONS } from '../data';

export type Rarity = 'common' | 'uncommon' | 'rare' | 'legendary' | 'mythic';
export const RARITY_LIST: Rarity[] = ['common', 'uncommon', 'rare', 'legendary', 'mythic'];
export type CardDef = (typeof CARDS.cards)[number];

export const CARD_LIST = CARDS.cards as CardDef[];
export const cardDef = (id: string): CardDef | undefined => CARD_LIST.find((c) => c.id === id);
export const rarityInfo = (r: string) => (CARDS.rarities as Record<string, { name_pt: string; color_hex: string; duration_minutes: number }>)[r];
export const rarityRank = (r: string) => RARITY_LIST.indexOf(r as Rarity);

const fmt = (v: number) => new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 }).format(v);

/** texto de cada efeito (buff ou Armory), lido da config */
const EFFECT_TEXT: Record<string, (v: number) => string> = {
  crop_and_orchard_growth_speed_pct: (v) => `+${fmt(v)}% crescimento da lavoura e do pomar`,
  golden_harvest_chance_pct: (v) => `+${fmt(v)}% chance de Colheita Dourada`,
  animal_production_pct: (v) => `+${fmt(v)}% produção animal`,
  account_and_character_xp_pct: (v) => `+${fmt(v)}% XP da conta e dos personagens`,
  account_xp_pct: (v) => `+${fmt(v)}% XP da conta`,
  all_speed_pct: (v) => `+${fmt(v)}% velocidade de lavoura, pomar, animais e limpeza`,
  crop_orchard_animal_speed_pct: (v) => `+${fmt(v)}% velocidade de lavoura, pomar e animais`,
  weather_and_night_event_boost_pct: (v) => `+${fmt(v)}% nos bônus de clima e do evento noturno`,
  expedition_success_pts: (v) => `+${fmt(v)} pontos de sucesso nas expedições`,
  expedition_loss_reduction_pct: (v) => (v >= 100 ? 'sem perda na falha' : `−${fmt(v)}% de perda na falha`),
  expedition_crit_pts: (v) => `+${fmt(v)} pontos de crítico`,
  expedition_crit_value_pct: (v) => `+${fmt(v)}% no valor do crítico`,
  item_and_kit_drop_boost_pct: (v) => `+${fmt(v)}% chance de item e kit`,
  item_drop_boost_pct: (v) => `+${fmt(v)}% chance de item`,
  energy_cost_reduction_pct: (v) => (v >= 100 ? 'sem gasto de energia em campo' : `−${fmt(v)}% gasto de energia em campo`),
  energy_recovery_boost_pct: (v) => `+${fmt(v)}% recuperação de energia no banco`,
  character_xp_pct: (v) => `+${fmt(v)}% XP dos personagens`,
  production_gold_bonus_pct: (v) => `${fmt(v)}% do valor produzido vira ouro, pago no fim`,
  sales_gold_pct: (v) => `+${fmt(v)}% ouro em vendas`,
};
export function effectLines(eff: Record<string, number> | undefined): string[] {
  return Object.entries(eff ?? {}).filter(([, v]) => v !== 0).map(([k, v]) => EFFECT_TEXT[k]?.(v) ?? `${k} ${v}`);
}

/** versão curta do efeito, para caber no quadro de texto da própria carta */
const EFFECT_SHORT: Record<string, (v: number) => string> = {
  crop_and_orchard_growth_speed_pct: (v) => `+${fmt(v)}% crescimento lavoura e pomar`,
  golden_harvest_chance_pct: (v) => `+${fmt(v)}% chance de Colheita Dourada`,
  animal_production_pct: (v) => `+${fmt(v)}% produção animal`,
  account_and_character_xp_pct: (v) => `+${fmt(v)}% XP da conta e dos personagens`,
  all_speed_pct: (v) => `+${fmt(v)}% velocidade de tudo`,
  weather_and_night_event_boost_pct: (v) => `+${fmt(v)}% nos bônus de clima e evento`,
  expedition_success_pts: (v) => `+${fmt(v)} de sucesso`,
  expedition_loss_reduction_pct: (v) => (v >= 100 ? 'sem perda na falha' : `−${fmt(v)}% de perda`),
  expedition_crit_pts: (v) => `+${fmt(v)} de crítico`,
  expedition_crit_value_pct: (v) => `+${fmt(v)}% valor do crítico`,
  item_and_kit_drop_boost_pct: (v) => `+${fmt(v)}% item e kit`,
  energy_cost_reduction_pct: (v) => (v >= 100 ? 'sem gasto de energia' : `−${fmt(v)}% gasto de energia`),
  energy_recovery_boost_pct: (v) => `+${fmt(v)}% recuperação`,
  character_xp_pct: (v) => `+${fmt(v)}% XP dos personagens`,
  production_gold_bonus_pct: (v) => `${fmt(v)}% da produção vira ouro`,
};

/** o que vai escrito na carta: o efeito do buff nessa raridade */
export function cardFaceLines(cardId: string, rarity: string): string[] {
  const eff = (cardDef(cardId)?.buff_effects as Record<string, Record<string, number>> | undefined)?.[rarity] ?? {};
  return Object.entries(eff).filter(([, v]) => v !== 0).map(([k, v]) => EFFECT_SHORT[k]?.(v) ?? EFFECT_TEXT[k]?.(v) ?? `${k} ${v}`);
}

/** o que o buff da carta faz nessa raridade */
export function buffLines(cardId: string, rarity: string): string[] {
  return effectLines((cardDef(cardId)?.buff_effects as Record<string, Record<string, number>> | undefined)?.[rarity]);
}

/** duração do buff em texto (1 h, 1 h 20, 2 h 30) */
export function buffDuration(rarity: string): string {
  const m = rarityInfo(rarity)?.duration_minutes ?? 0;
  const h = Math.floor(m / 60), r = m % 60;
  return r ? `${h} h ${String(r).padStart(2, '0')}` : `${h} h`;
}

/** situação de uma carta no Armory: quais raridades estão expostas e qual bônus vale */
export function armoryStatus(armory: { card_id: string; rarity: string }[], cardId: string): { has: Set<string>; level: 'none' | 'partial' | 'complete' } {
  const has = new Set(armory.filter((a) => a.card_id === cardId).map((a) => a.rarity));
  const level = has.size === 5 ? 'complete' : ['common', 'uncommon', 'rare'].every((r) => has.has(r)) ? 'partial' : 'none';
  return { has, level };
}

/** bônus do Armory dessa carta (parcial ou completo) */
export function armoryLines(cardId: string, level: 'partial' | 'complete'): string[] {
  const a = cardDef(cardId)?.armory_bonus as Record<string, Record<string, number>> | undefined;
  return effectLines(a?.[level === 'complete' ? 'complete_gold' : 'partial_silver']);
}

type BankEntry = { id: string; metric: string; text_pt: string; target: { type: string } };
const BANK: Record<string, BankEntry> = Object.fromEntries(
  [...MISSIONS.bank.daily, ...MISSIONS.bank.weekly].map((m) => [m.id, m as unknown as BankEntry]),
);
const GOLD_METRICS = new Set(['harvest_value', 'stall_gold', 'gold_earned']);

/** texto da missão com a meta no lugar de {n} */
export function missionText(id: string, target: number): string {
  const m = BANK[id];
  if (!m) return id;
  const n = GOLD_METRICS.has(m.metric) || m.metric === 'xp_earned' ? new Intl.NumberFormat('pt-BR').format(Math.round(target)) : fmt(target);
  return m.text_pt.replace('{n}', n);
}

/** progresso para a barra (0 a 1) e o texto "x de y" */
export function missionProgress(metric: string, progress: number, target: number): { pct: number; text: string } {
  const pct = target > 0 ? Math.min(1, progress / target) : 0;
  const f = (v: number) => (metric === 'field3_hours' ? `${fmt(v)} h` : new Intl.NumberFormat('pt-BR', { maximumFractionDigits: GOLD_METRICS.has(metric) ? 0 : 1 }).format(v));
  return { pct, text: `${f(progress)} de ${f(target)}` };
}

/** quanto falta para a próxima garantia (Raro+, Lendário+, Mítico) */
export function pityLeft(p: { rare: number; legendary: number; mythic: number }): { rare: number; legendary: number; mythic: number } {
  const t = CARDS.gacha.pity_thresholds;
  return { rare: t.rare_or_better - p.rare, legendary: t.legendary_or_better - p.legendary, mythic: t.mythic - p.mythic };
}
