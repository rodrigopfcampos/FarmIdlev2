// Cliente do Supabase. URL e chave publicável vêm das variáveis de ambiente do build
// (a chave publicável é feita para ficar no navegador; quem protege os dados é o RLS do banco).
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

export const configMissing = !url || !key;
export const supabase: SupabaseClient | null = configMissing
  ? null
  : createClient(url!, key!, { auth: { persistSession: true, autoRefreshToken: true } });

export type PlayerState = { nickname: string; gold: number };

// lê o perfil e o ouro do jogador logado (o RLS só devolve as linhas dele)
export async function loadPlayer(): Promise<PlayerState> {
  if (!supabase) throw new Error('Servidor não configurado.');
  const [{ data: profile, error: e1 }, { data: wallet, error: e2 }] = await Promise.all([
    supabase.from('profiles').select('nickname').single(),
    supabase.from('wallets').select('gold').single(),
  ]);
  if (e1 || e2) throw new Error('Não foi possível carregar sua fazenda.');
  return { nickname: profile.nickname, gold: Number(wallet.gold) };
}
