# Village Idle Farm

Jogo idle de fazenda em pixel art, no navegador (Phaser 4 + TypeScript + Vite) com servidor no Supabase.

- `docs/GDD.md`: documento do jogo (fonte da verdade). `docs/ROADMAP.md`: o que está feito e o que falta.
- `config/`: todos os números do jogo. Nada de número fixo no código.
- `src/`: o jogo. `public/assets/`: mapa e sprites recortados (`sprites/manifest.json`).
- `assets/raw/`: pranchas originais das artes. `tools/assets/sheets.json`: grade de cada prancha.
- `supabase/migrations/`: banco (aplicar no teste, depois na produção). `supabase/tests/`: testes do banco.
- `tools/balance/`: modelo de terreno e checagens. `tools/sim/`: simulador de economia.

## Comandos (Node 22)

- `npm run dev`: jogo local (precisa de `.env.local`, veja `.env.example`)
- `npm run build`: build de produção em `dist/` (é o que o Cloudflare Pages roda)
- `npm test`: testes do jogo e das artes
- `npm run assets`: recorta as pranchas de `assets/raw` em `public/assets/sprites`
- `npm run balance:check`: confere mapa, lotes, cultivos, animais, cartas, ferramentas, raridade, artes e documento (tem de terminar em "tudo verde")
- `npm run sim`: simulador de economia (seção 14 do GDD)
- `npx tsx tools/db/config-sql.ts levels ...`: gera o SQL que copia a config para a tabela `game_config`
- `npx tsx tools/db/map-rules.ts`: gera `config/map_rules.json` (lotes, vizinhos, canteiros e árvores que o servidor usa) a partir do `mapConfig.json`

## Hospedagem

Cloudflare (Workers Builds, `wrangler.jsonc`): comando `npm run build`, pasta `dist`, variáveis de build `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY`.
Site: https://farmidlev2.2mailife.workers.dev (projeto de produção do Supabase).

## Painel do admin

`/admin.html`: entra com e-mail e senha de uma conta admin e o código do aplicativo autenticador (2FA). Busca jogadores e mostra ledger, auditoria e fazenda. Na guia Fazenda dá para dar Escritura (fica na auditoria com a justificativa).

## Testes do banco

`supabase/tests/*.sql`: rodar no projeto de teste (resultado esperado: erro `TESTES_OK`, tudo é desfeito).
