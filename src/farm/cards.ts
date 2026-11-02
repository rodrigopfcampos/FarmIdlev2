// Cartas e missões no cliente: só textos e contas para mostrar; quem decide tudo é o servidor.
import { CARDS, MISSIONS } from '../data';

export type Rarity = 'common' | 'uncommon' | 'rare' | 'legendary' | 'mythic';
export const RARITY_LIST: Rarity[] = ['common', 'uncommon', 'rare', 'legendary', 'mythic'];
export type CardDef = (typeof CARDS.cards)[number];

export const CARD_LIST = CARDS.cards as CardDef[];
export const cardDef = (id: string): CardDef | undefined => CARD_LIST.find((c) => c.id === id);
export const rarityInfo = (r: string) => (CARDS.rarities as Record<string, { name_pt: string; color_hex: string; duration_days: number; repairable: boolean }>)[r];
export const rarityRank = (r: string) => RARITY_LIST.indexOf(r as Rarity);

const fmt = (v: number) => new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 }).format(v);

/** texto de cada efeito (carta na mão ou álbum), lido da config */
const EFFECT_TEXT: Record<string, (v: number) => string> = {
  crop_and_orchard_growth_speed_pct: (v) => `+${fmt(v)}% crescimento da lavoura e do pomar`,
  golden_harvest_chance_pct: (v) => `+${fmt(v)}% chance de Colheita Dourada`,
  animal_production_pct: (v) => `+${fmt(v)}% produção dos animais`,
  account_and_character_xp_pct: (v) => `+${fmt(v)}% XP da conta e dos personagens`,
  account_xp_pct: (v) => `+${fmt(v)}% XP da conta`,
  all_speed_pct: (v) => `+${fmt(v)}% velocidade de lavoura, pomar, animais e limpeza`,
  crop_orchard_animal_speed_pct: (v) => `+${fmt(v)}% velocidade de lavoura, pomar e animais`,
  weather_and_night_event_boost_pct: (v) => `+${fmt(v)}% nos bônus de clima e do evento noturno`,
  expedition_success_pts: (v) => `+${fmt(v)} pontos de sucesso nas expedições`,
  expedition_loss_reduction_pct: (v) => (v >= 100 ? 'sem perda na falha' : `−${fmt(v)}% de perda na falha`),
  expedition_crit_pts: (v) => `+${fmt(v)} pontos de crítico nas expedições`,
  expedition_crit_value_pct: (v) => `+${fmt(v)}% no valor do crítico`,
  item_and_kit_drop_boost_pct: (v) => `+${fmt(v)}% chance de carta na expedição`,
  item_drop_boost_pct: (v) => `+${fmt(v)}% chance de carta na expedição`,
  energy_cost_reduction_pct: (v) => `−${fmt(v)}% gasto de energia em campo`,
  energy_recovery_boost_pct: (v) => `+${fmt(v)}% recuperação de energia no banco`,
  character_xp_pct: (v) => `+${fmt(v)}% XP dos personagens`,
  production_gold_bonus_pct: (v) => `${fmt(v)}% do valor produzido vira ouro (pago quando a carta sai da mão)`,
  sales_gold_pct: (v) => `+${fmt(v)}% ouro nas vendas`,
  harvest_yield_pct: (v) => `+${fmt(v)}% unidades em cada colheita`,
  team_capacity_pct: (v) => `+${fmt(v)}% trabalho por hora da equipe`,
  team_auto_capacity_pct: (v) => `+${fmt(v)}% trabalho automático da equipe`,
  vehicle_wear_reduction_pct: (v) => `−${fmt(v)}% desgaste dos veículos`,
  fishing_profit_pct: (v) => `+${fmt(v)}% lucro na pesca`,
  animal_orchard_work_pct: (v) => `−${fmt(v)}% trabalho para coletar animais e colher o pomar`,
  crop_work_pct: (v) => `−${fmt(v)}% trabalho para plantar e colher a lavoura`,
  cleanup_tool_vehicle_pct: (v) => `+${fmt(v)}% limpeza de lote e −${fmt(v)}% desgaste de ferramentas e veículos`,
  rare_seed_chance_pct: (v) => `+${fmt(v)}% chance de Semente Rara`,
  expedition_duration_reduction_pct: (v) => `−${fmt(v)}% tempo de viagem`,
  vehicle_cargo_profit_pct: (v) => `+${fmt(v)}% carga e lucro nas expedições`,
  theft_reduction_pct: (v) => `−${fmt(v)}% de roubo (perda na falha)`,
  jackpot_pts: (v) => `+${fmt(v)} pontos de jackpot (crítico)`,
};
export function effectLines(eff: Record<string, number> | undefined): string[] {
  return Object.entries(eff ?? {}).filter(([, v]) => v !== 0).map(([k, v]) => EFFECT_TEXT[k]?.(v) ?? `${k} ${v}`);
}

/** arte inteira da carta (moldura, ilustração e texto) */
export const cardArt = (cardId: string, rarity: string) => `card_full_${cardId}_${rarity}`;

/** o que a carta faz nessa raridade */
export function buffLines(cardId: string, rarity: string): string[] {
  return effectLines((cardDef(cardId)?.buff_effects as Record<string, Record<string, number>> | undefined)?.[rarity]);
}

/** quantos dias a carta vale na mão */
export function cardDuration(rarity: string): string {
  const d = rarityInfo(rarity)?.duration_days ?? 0;
  return `${d} dia${d === 1 ? '' : 's'}`;
}

/** tempo em texto curto: "1 d 4 h", "3 h 20", "12 min" */
export function lifeText(seconds: number): string {
  const m = Math.max(0, Math.round(seconds / 60));
  const d = Math.floor(m / 1440), h = Math.floor((m % 1440) / 60), mm = m % 60;
  if (d) return `${d} d${h ? ` ${h} h` : ''}`;
  if (h) return `${h} h${mm ? ` ${String(mm).padStart(2, '0')}` : ''}`;
  return `${mm} min`;
}

/** cartas que cabem na mão no nível (3, 4 no 15, 5 no 30) */
export function handSlots(level: number): number {
  return CARDS.rules.hand.slots_by_level.filter(([lv]) => lv <= level).reduce((n, [, k]) => Math.max(n, k), 0);
}

/** veículo que aparece na Garagem com a carta de Veículo na mão */
export function vehicleLook(rarity: string): string | null {
  const d = cardDef('veiculo') as (CardDef & { vehicle_look_by_rarity?: Record<string, string> }) | undefined;
  return d?.vehicle_look_by_rarity?.[rarity] ?? null;
}

/** situação de uma carta no álbum: quais raridades já passaram pela mão e qual bônus vale */
export function armoryStatus(armory: { card_id: string; rarity: string }[], cardId: string): { has: Set<string>; level: 'none' | 'partial' | 'complete' } {
  const has = new Set(armory.filter((a) => a.card_id === cardId).map((a) => a.rarity));
  const level = has.size === 5 ? 'complete' : ['common', 'uncommon', 'rare'].every((r) => has.has(r)) ? 'partial' : 'none';
  return { has, level };
}

/** bônus do álbum dessa carta (parcial ou completo) */
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
