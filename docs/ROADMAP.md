# Village Idle Farm — mapa do projeto (23/10/2026, fase 2)

## A. Feito

| Área | Entrega | Onde |
| --- | --- | --- |
| Documento | GDD v2, seções 1–15, com raridade global, cartas, ferramentas e resultados do simulador | `docs/GDD.md` |
| Mapa | 30 lotes, início no A1, 4 zonas, fundo sem árvores | `config/mapConfig.json`, `public/assets/map/` |
| Terreno | 29 compras: 0,28 × 1,10^(n−1) × R(⌈1,46 n⌉), Escritura da 20ª em diante, limpeza até 6 h 48 | `config/lots.json` |
| Níveis | Níveis 1–50 com R remedido pelo simulador (versão 2) | `config/levels.json` |
| Cultivos e animais | 50 cultivos, 10 animais, capacidade de trabalho 2,67/h | `config/crops.json`, `config/animals.json` |
| Cartas | 10 cartas (carta 6 = Tempestade), 5 raridades, garantia, Armory | `config/cards.json` |
| Ferramentas e itens | 5 materiais, desgaste 2,5/h, roupas, amuletos, lanches | `config/tools_and_items.json` |
| Raridade global | ×1 / ×1,2 / ×1,5 / ×2 / ×3; animais 75/18/5/1,5/0,5%; veículos ×capacidade, velocidade e segurança | `config/rarity.json` |
| Personagens, expedições, missões, clima | Números das seções 7, 8, 10 e 11 em config | `config/characters.json`, `expeditions.json`, `missions.json`, `weather.json` |
| Artes | 14 pranchas recortadas em 190 sprites + manifest | `npm run assets`, `public/assets/sprites/` |
| **Fase 1** | Mapa vivo com 4 zonas, A1, Agricultor, `advance_farm`, limite offline 8 h, Silo, Barraca, painel do admin com 2FA | aprovada pelo dono (vídeo, 23/10) |
| **Fase 2** | XP e níveis 1–50, 50 cultivos (lavoura, recorrentes e pomar), compra e limpeza dos lotes, Escritura pelo painel, Enxada em 5 materiais, pomar com troca grátis; depois do 1º teste: plantio e colheita por clique, começo rápido (nível 2 em ~10 min), painel com nível e ouro para testes | `supabase/migrations/…500` e `…600`, `src/farm/rules.ts` |
| **Fase 0** | Repositório, Supabase teste/produção (São Paulo), login com e-mail, 18+, ouro inicial, ledger e audit_log imutáveis, RLS, deploy automático no Cloudflare, CI no GitHub, simulador completo | ver seção D |
| Testes | `balance:check` (config × GDD × simulador), vitest (jogo e artes), testes do banco | CI a cada push |

## B. Decisões tomadas
- 🆕 (23/10, teste da fase 2) Com o jogo aberto, plantar e colher por clique é grátis; fora do jogo, o Agricultor faz tudo (0,5 para plantar, 0,5 para colher). Começo rápido: nível 2 em ~10 min, 5 em ~1 h, 10 no 1º dia; nível 50 continua no dia ~113. Painel do admin dá nível e ouro para testes.
- Navegador primeiro; mercado decidido antes da fase 8. Público 18+.
- 30 lotes, início A1, vizinhança por lado (Galinheiro e Celeiro isentos). Garagem à esquerda do A5.
- Carta 6 = Tempestade. Semente rara vale 1 plantio. Trigo, Girassol e Algodão guardados sem uso.
- Veículos: raridade multiplica capacidade, velocidade e segurança. Animais: raridade sorteada na compra.
- Ferramenta perde 2,5/h. Hospedagem: Cloudflare (Workers Builds). Supabase grátis em São Paulo.

## C. Pendências do dono
1. ✅ Cloudflare com as variáveis do Supabase; site em https://farmidlev2.2mailife.workers.dev (conectado ao projeto de produção).
2. ✅ Supabase (produção): Site URL = endereço do site.
3. ✅ Teste em produção (23/10): conta criada e confirmada, entrada feita, 2.000 de ouro no ledger e na carteira, auditoria registrada.
4. ✅ "ok" da fase 0.
6. ✅ Teste da fase 1 (vídeo de 23/10).
7. Testar a fase 2 em produção (lista na seção G) e dar o "ok".
5. Antes do beta: escolher um serviço de e-mail (SMTP) — o e-mail grátis do Supabase só envia para a equipe do projeto.

## D. Fases (GDD seção 13)

| Fase | Entrega | Situação |
| --- | --- | --- |
| 0 Base | Repo, Supabase teste/produção, login, deploy automático, config, ledger, audit_log, script das artes, simulador | **feito e testado em produção** |
| 1 Fazenda mínima | Mapa com 4 zonas, A1, Agricultor, 4 cultivos, `advance_farm`, offline 8 h, Silo, Barraca, painel básico | **feito e aprovado** (23/10) |
| 2 Progressão | XP/níveis, 50 cultivos, compra e limpeza dos lotes, Escritura, ferramentas, pomar | **feito** (23/10); falta o teste do dono em produção |
| 3 Personagens | 6 classes, energia, salário, desgaste, inventário, habilidades, pets | — |
| 4 Animais | Galinheiro, Celeiro, Lago, ampliações, 10 animais com raridade, ração | — |
| 5 Expedições | Garagem, 4 veículos × 5 raridades, 5 rotas, minigame, seguro, relatório | — |
| 6 Clima e evento | Agenda por fuso, evento 19–21 h, filtros visuais | — |
| 7 Missões e cartas | Missões, pacotes, 10 cartas, Armory, fichário, Colecionador | — |
| 8 Multiplayer | Amigos, visitas, ranking, mercado (conteúdo a decidir) | — |
| 9 Painel e antitrapaça | Todas as guias, regras da seção 12, alertas | — |
| 10 Beta fechado | 20–50 jogadores, carga 500, segurança, adequação legal | — |
| 11 Lançamento | Página, termos, privacidade, monitoramento, rollback | — |

## E. Artes que faltam
- (fase 1) recortadas também: estágios de 27 cultivos (pranchas Planta 2, 3 e 4), 40 ícones de produto, o Agricultor (parado + 3 quadros de ação) e a moeda da interface.
- Estágios e ícone: Beterraba, Batata-doce, Mandioca, Pepino, Quiabo, Maracujá.
- Ícone 32×32: Tomate, Mamão, Goiaba, Acerola, Jabuticaba.
- 2 medalhões de rota: Capital e Exportação.
- Ícones da interface (HUD).
- Cerca dos lotes à venda (o GDD cita cerca + placa + entulho; hoje só placa e entulho).
- Opcional: Celeiro com telhado de telhas vermelhas; molduras de carta na proporção 2:3.

## F. Regras provisórias da fase 2 (mudam na fase 3)
- Sem Ferreiro, a limpeza leva o dobro (1 h + 12 min × n, × 2): da 16ª compra em diante passa de 8 h e precisa de mais de uma volta do jogador. Com o Ferreiro (fase 3) volta ao tempo da tabela.
- O Agricultor faz tudo: lavoura, colheitas extras dos recorrentes e o pomar, sem gastar energia.
- Escritura, nível, limpeza de lote e ouro para testes pelo painel do admin (guia Fazenda); missões e expedições entram nas fases 5 e 7.
- A Enxada não se desgasta ainda; desgaste e conserto na fase 3.
- Lote do Galinheiro/Celeiro/Lago pode ser comprado; os animais chegam na fase 4.

## G. Teste da fase 2 (dono, em produção)
1. Conta nova: escolha Alface num canteiro vazio (planta na hora) e "Alface no lote A1 inteiro". Em 10 min os canteiros pulam maduros; clique num deles (colhe e replanta) ou em "Colher e plantar (N)". Aparece "Nível 2!".
2. No nível 2, compre o A3 (vizinho do A1). O lote clareia e mostra "Limpeza 2 h 24"; escolha o cultivo e ele planta quando a limpeza acaba.
3. Lote não vizinho (ex.: A2) e lote acima do nível mostram o motivo e o botão fica desligado.
4. Painel do admin, guia Fazenda: mude o nível da sua conta para 12, dê ouro (ex.: 50.000) e use "Terminar limpeza" para não esperar.
5. Galinheiro (C1) pode ser comprado mesmo longe; depois da limpeza aparece o prédio.
6. Pomar (nível 10): plante uma Maçã, veja a muda; "Derrubar (grátis)" e plante outra fruta.
7. Forja (nível 8): melhore a Enxada para Cobre; o trabalho por hora sobe 40%.
8. Dê 1 Escritura pelo painel e veja o número no topo do jogo.

## H. Riscos e pontos em aberto
- 🆕 Clique sem limite: um robô que clica sem parar vira um jogador sempre online (e sem o limite offline). Tratar no antitrapaça (fase 9): frequência de cliques, horas seguidas online.
- Chance de semente rara (Lupa, pacotes, eventos): definir nas fases 3, 6 e 7; hoje o balanceamento supõe Comum.
- Depois do mapa completo sobra ouro: drenos de fim de jogo antes da fase 8 (seção 9).
- Plano grátis do Supabase: sem backup diário, sem recuperação por horário (o GDD pede) e sem bloqueio de senhas vazadas; avaliar o plano pago antes do beta.
- Legal: ECA Digital e LGPD (seção 15) com advogado antes de cobrar qualquer coisa.
