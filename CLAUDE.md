# Village Idle Farm v2 — guia para novas sessões

O dono não programa: decide o design, gera as artes com IA, faz deploy e testa. Responda em português do Brasil, curto, e pergunte em vez de adivinhar. Antes de pedir uma arte, passe tamanho, formato, fundo e grade.

## Fonte da verdade
- `docs/GDD.md` (v2) e `docs/ROADMAP.md` (feito, pendente, fases 0–11).
- Números só em `config/*.json`; o código nunca tem número de balanceamento fixo.
- `npm run balance:check` tem de terminar em "tudo verde" (roda no CI junto com `npm test` e `npm run build`).
- Mudou número de economia? Rode `npm run sim -- --calibrate --write`, depois `python3 tools/balance/gdd_tables.py`, e copie a config nova para o banco com `tools/db/config-sql.ts`.

## Regras
- Servidor manda (Supabase); ledger nunca é apagado; toda regra tem teste automático.
- Comentários em português, nomes de código em inglês, textos do jogo em pt-BR.
- Sem serviço pago ou biblioteca nova sem perguntar. Nenhuma chave secreta (service_role, senha) no cliente ou no repositório, que é público; a chave publicável do Supabase entra só pelo build.
- Uma fase por vez; a próxima só começa quando o dono disser "ok".

## Infra
- Supabase (plano grátis, São Paulo): teste `vfuomlgnhvhfeygeegqm`, produção `saijxytudvsyvhfnwnpb`. Migrações em `supabase/migrations` (aplicar no teste, rodar `supabase/tests`, depois na produção).
- Cloudflare Workers Builds (`wrangler.jsonc`): `npm run build` → `dist/`. Variáveis de build `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY`.
- Artes: pranchas em `assets/raw`, grade em `tools/assets/sheets.json`, `npm run assets`.
- Repositório antigo (v1, só referência): rodrigopfcampos/Villageidlefarm.
