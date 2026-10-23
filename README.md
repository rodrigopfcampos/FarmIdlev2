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

## Hospedagem

Cloudflare Pages: comando `npm run build`, pasta `dist`, variáveis `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY`
(Production = projeto de produção, Preview = projeto de teste).
