// Chamadas da fazenda ao servidor. O cliente só manda intenções; o servidor calcula e devolve o estado.
import { supabase } from './supabase';

export type PlotState = {
  plot_id: string; crop_id: string | null; state: 'empty' | 'growing'; planted_crop_id: string | null;
  planted_at: number | null; ready_at: number | null; stalled_reason: string | null;
};
export type FarmState = {
  server_now: string; farm_time: number; synced_at: string; last_activity_at: string; offline_cap_hours: number;
  labor_bank: number; labor_per_hour: number; labor_cap_hours: number;
  nickname: string; gold: number; lots: string[]; plots: PlotState[]; silo: Record<string, number>;
};

const ERRORS: Record<string, string> = {
  'cultivo não liberado': 'Esse cultivo ainda não está liberado.',
  'canteiro não encontrado': 'Esse canteiro não é seu.',
  'quantidade maior que o Silo': 'Você não tem tudo isso no Silo.',
  'precisa estar logado': 'Sua sessão terminou. Entre de novo.',
};

async function rpc(fn: string, args: Record<string, unknown> = {}): Promise<FarmState> {
  if (mock) return mock.rpc(fn, args);
  const { data, error } = await supabase!.rpc(fn, args);
  if (error) throw new Error(ERRORS[error.message] ?? 'Não deu certo. Tente de novo.');
  const s = data as FarmState;
  s.gold = Number(s.gold);
  return s;
}

export const getFarm = () => rpc('get_farm');
export const setCrop = (target: string, crop: string | null) => rpc('set_crop', { p_target: target, p_crop: crop });
export const sellAtStall = (item: string, qty: number) =>
  rpc('sell_at_stall', { p_item: item, p_qty: qty, p_idempotency_key: crypto.randomUUID() });

// modo de demonstração só no desenvolvimento (?mock=1): estado falso para conferir a tela sem servidor
let mock: { rpc: (fn: string, args: Record<string, unknown>) => Promise<FarmState> } | null = null;
export async function enableMockIfAsked(): Promise<boolean> {
  if (!import.meta.env.DEV || !new URLSearchParams(location.search).has('mock')) return false;
  mock = (await import('./mockFarm')).mockFarm;
  return true;
}
