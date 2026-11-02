// Funções do banco num lugar só: supabase/functions/ tem de ser igual à última versão de cada função nas migrações.
import { describe, expect, it } from 'vitest';
import { dropSignature, functionsDiff, latestFromMigrations } from '../tools/db/functions';

describe('funções do banco (supabase/functions)', () => {
  it('cada função das migrações tem o arquivo dela, igual à última versão', () => {
    expect(functionsDiff()).toEqual({ changed: [], missing: [], extra: [] });
    expect(latestFromMigrations().size).toBeGreaterThan(200);
  });
  it('funções removidas por "drop function" saem da lista', () => {
    const fns = latestFromMigrations();
    for (const gone of ['adopt_pet', 'equip_item', 'item_effect', 'refurbish_vehicle', 'upgrade_tool']) expect(fns.has(gone)).toBe(false);
  });
  it('assinatura do drop tira os valores padrão', () => {
    expect(dropSignature('create or replace function public.advance_farm(p_user uuid, p_now timestamp with time zone DEFAULT now())\nreturns void as $$ $$;'))
      .toBe('p_user uuid, p_now timestamp with time zone');
  });
});
