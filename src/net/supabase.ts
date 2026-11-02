// Cliente do Supabase. URL e chave publicável vêm das variáveis de ambiente do build
// (a chave publicável é feita para ficar no navegador; quem protege os dados é o RLS do banco).
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

export const configMissing = !url || !key;
export const supabase: SupabaseClient | null = configMissing
  ? null
  : createClient(url!, key!, { auth: { persistSession: true, autoRefreshToken: true } });
