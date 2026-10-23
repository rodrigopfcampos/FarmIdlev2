// Chamadas da fazenda ao servidor. O cliente só manda intenções; o servidor calcula e devolve o estado.
import { supabase } from './supabase';
import type { TreeState } from '../farm/rules';

export type PlotState = {
  plot_id: string; crop_id: string | null; state: 'empty' | 'growing'; planted_crop_id: string | null;
  planted_at: number | null; ready_at: number | null; harvests_done: number; stalled_reason: string | null;
};
export type LotState = { lot_id: string; ready_at: number; purchase_n: number | null };
export type FarmState = {
  server_now: string; farm_time: number; synced_at: string; last_activity_at: string; offline_cap_hours: number;
  labor_bank: number; labor_per_hour: number; labor_cap_hours: number;
  nickname: string; is_admin: boolean; gold: number; level: number; xp: number; xp_to_next: number | null;
  lots: LotState[]; plots: PlotState[]; trees: TreeState[];
  silo: Record<string, number>; inventory: Record<string, number>; tools: Record<string, string>;
};

const ERRORS: Record<string, string> = {
  'cultivo não liberado': 'Esse cultivo ainda não está liberado no seu nível.',
  'cultivo inválido': 'Esse cultivo não vai em canteiro.',
  'canteiro não encontrado': 'Esse canteiro não é seu.',
  'quantidade maior que o Silo': 'Você não tem tudo isso no Silo.',
  'precisa estar logado': 'Sua sessão terminou. Entre de novo.',
  'ouro insuficiente': 'Falta ouro.',
  'lote não é vizinho': 'Só dá para comprar um lote vizinho de um lote seu.',
  'nível insuficiente': 'Seu nível ainda não chega.',
  'precisa de Escritura': 'Essa compra precisa de 1 Escritura.',
  'esse lote já é seu': 'Esse lote já é seu.',
  'todos os lotes já foram comprados': 'Você já comprou todos os lotes.',
  'lote ainda em limpeza': 'O lote ainda está em limpeza.',
  'vaga de árvore não encontrada': 'Essa vaga de árvore não é sua.',
  'fruta inválida': 'Isso não é uma muda de árvore.',
  'ferramenta já está no máximo': 'A ferramenta já está no material mais alto.',
};

function normalize(s: FarmState): FarmState {
  s.gold = Number(s.gold);
  s.xp = Number(s.xp);
  s.xp_to_next = s.xp_to_next === null ? null : Number(s.xp_to_next);
  s.lots ??= []; s.trees ??= []; s.inventory ??= {}; s.tools ??= {};
  return s;
}

async function rpc(fn: string, args: Record<string, unknown> = {}): Promise<FarmState> {
  if (mock) return normalize(await mock.rpc(fn, args));
  const { data, error } = await supabase!.rpc(fn, args);
  if (error) throw new Error(ERRORS[error.message] ?? 'Não deu certo. Tente de novo.');
  return normalize(data as FarmState);
}

export const getFarm = () => rpc('get_farm');
export const setCrop = (target: string, crop: string | null) => rpc('set_crop', { p_target: target, p_crop: crop });
export const sellAtStall = (item: string, qty: number) =>
  rpc('sell_at_stall', { p_item: item, p_qty: qty, p_idempotency_key: crypto.randomUUID() });
export const buyLot = (lot: string) => rpc('buy_lot', { p_lot: lot });
export const plantTree = (lot: string, slot: number, fruit: string) => rpc('plant_tree', { p_lot: lot, p_slot: slot, p_fruit: fruit });
export const chopTree = (lot: string, slot: number) => rpc('chop_tree', { p_lot: lot, p_slot: slot });
export const upgradeTool = (cls: string) => rpc('upgrade_tool', { p_class: cls });

// modo de demonstração só no desenvolvimento (?mock=1): estado falso para conferir a tela sem servidor
let mock: { rpc: (fn: string, args: Record<string, unknown>) => Promise<FarmState> } | null = null;
export async function enableMockIfAsked(): Promise<boolean> {
  if (!import.meta.env.DEV || !new URLSearchParams(location.search).has('mock')) return false;
  mock = (await import('./mockFarm')).mockFarm;
  return true;
}
