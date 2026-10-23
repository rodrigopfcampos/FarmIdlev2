# Village Idle Farm v2 — guia para novas sessões

O dono não programa: decide o design, gera as artes com IA, faz deploy e testa. Responda em português do Brasil, curto, e pergunte em vez de adivinhar. Antes de pedir uma arte, passe tamanho, formato, fundo e grade.

## Fonte da verdade
- `docs/GDD.md` (v2) e `docs/ROADMAP.md` (feito, pendente, fases 0–11).
- Números só em `config/*.json`; o código nunca tem número de balanceamento fixo.
- `npm run balance:check` tem de terminar em "tudo verde".

## Regras
- Servidor manda (Supabase); ledger nunca é apagado; toda regra tem teste automático.
- Comentários em português, nomes de código em inglês, textos do jogo em pt-BR.
- Sem serviço pago ou biblioteca nova sem perguntar. Sem chave ou senha no cliente ou no repositório (o repositório é público).
- Uma fase por vez; a próxima só começa quando o dono disser "ok".

## Infra
- Supabase (plano grátis, São Paulo): teste `vfuomlgnhvhfeygeegqm`, produção `saijxytudvsyvhfnwnpb`.
- Repositório antigo (v1, só referência): rodrigopfcampos/Villageidlefarm.
