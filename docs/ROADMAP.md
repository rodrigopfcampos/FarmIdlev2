# Village Idle Farm — mapa do projeto (24/10/2026, fase 3)

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
| **Fase 3** | 6 classes com contratação, Slots de Campo e Banco, energia e rodízio, lanches na Barraca, salário à meia-noite com Desmotivado e parada, nível e árvore de habilidades com reset, ferramenta de cada classe com desgaste e conserto, Comerciante/Gerente/Botânica em campo, Sementes Raras, pets com carinho diário; painel do admin cobra salário para testes | `supabase/migrations/…24000100`, `supabase/tests/phase3_test.sql` |
| **Fase 0** | Repositório, Supabase teste/produção (São Paulo), login com e-mail, 18+, ouro inicial, ledger e audit_log imutáveis, RLS, deploy automático no Cloudflare, CI no GitHub, simulador completo | ver seção D |
| Testes | `balance:check` (config × GDD × simulador), vitest (jogo e artes), testes do banco | CI a cada push |

## B. Decisões tomadas
- 🆕 (23/10, fase 3) Funções de Comerciante, Gerente e Botânica antes das fases 4 e 5; lanches a 1% / 1,6% / 2,8% de R; carinho diário dos pets (4/10/18/30) com bônus no personagem vinculado; 2º e 3º pet a 1 dia de R; salário à meia-noite de Brasília até a fase 6 (detalhes no GDD, seção 7).
- 🆕 (23/10) Fase 2 aprovada pelo dono (vídeo). Mapa agora fica centralizado mesmo quando a altura da tela é menor que o mapa.
- (23/10, teste da fase 2) Com o jogo aberto, plantar e colher por clique é grátis; fora do jogo, o Agricultor faz tudo (0,5 para plantar, 0,5 para colher). Começo rápido: nível 2 em ~10 min, 5 em ~1 h, 10 no 1º dia; nível 50 continua no dia ~113. Painel do admin dá nível e ouro para testes.
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
7. ✅ Teste da fase 2 e "ok" (23/10).
8. Testar a fase 3 em produção (lista na seção G) e dar o "ok".
9. Gerar as artes da seção E (personagens e pets); até lá o jogo usa o Agricultor com outra cor e um emoji no lugar do pet.
5. Antes do beta: escolher um serviço de e-mail (SMTP) — o e-mail grátis do Supabase só envia para a equipe do projeto.

## D. Fases (GDD seção 13)

| Fase | Entrega | Situação |
| --- | --- | --- |
| 0 Base | Repo, Supabase teste/produção, login, deploy automático, config, ledger, audit_log, script das artes, simulador | **feito e testado em produção** |
| 1 Fazenda mínima | Mapa com 4 zonas, A1, Agricultor, 4 cultivos, `advance_farm`, offline 8 h, Silo, Barraca, painel básico | **feito e aprovado** (23/10) |
| 2 Progressão | XP/níveis, 50 cultivos, compra e limpeza dos lotes, Escritura, ferramentas, pomar | **feito e aprovado** (23/10) |
| 3 Personagens | 6 classes, energia, salário, desgaste, inventário, habilidades, pets | **feito** (24/10); falta o teste do dono em produção |
| 4 Animais | Galinheiro, Celeiro, Lago, ampliações, 10 animais com raridade, ração | — |
| 5 Expedições | Garagem, 4 veículos × 5 raridades, 5 rotas, minigame, seguro, relatório | — |
| 6 Clima e evento | Agenda por fuso, evento 19–21 h, filtros visuais | — |
| 7 Missões e cartas | Missões, pacotes, 10 cartas, Armory, fichário, Colecionador | — |
| 8 Multiplayer | Amigos, visitas, ranking, mercado (conteúdo a decidir) | — |
| 9 Painel e antitrapaça | Todas as guias, regras da seção 12, alertas | — |
| 10 Beta fechado | 20–50 jogadores, carga 500, segurança, adequação legal | — |
| 11 Lançamento | Página, termos, privacidade, monitoramento, rollback | — |

## E. Artes que faltam
- 🆕 (fase 3) 5 personagens: Rancheira, Ferreiro, Comerciante, Gerente e Botânica — mesma prancha do Agricultor (parado + 3 quadros de ação, 32×48 cada depois do recorte).
- 🆕 (fase 3) 3 pets: Cachorro, Gato e Papagaio — parado em frente à Casa (2 quadros, 24×24 depois do recorte).
- (fase 1) recortadas também: estágios de 27 cultivos (pranchas Planta 2, 3 e 4), 40 ícones de produto, o Agricultor (parado + 3 quadros de ação) e a moeda da interface.
- Estágios e ícone: Beterraba, Batata-doce, Mandioca, Pepino, Quiabo, Maracujá.
- Ícone 32×32: Tomate, Mamão, Goiaba, Acerola, Jabuticaba.
- 2 medalhões de rota: Capital e Exportação.
- Ícones da interface (HUD).
- Cerca dos lotes à venda (o GDD cita cerca + placa + entulho; hoje só placa e entulho).
- Opcional: Celeiro com telhado de telhas vermelhas; molduras de carta na proporção 2:3.

## F. Regras provisórias (mudam nas próximas fases)
- Vestimenta e amuleto: os espaços existem, mas os itens só caem nas expedições (fase 5).
- Lote do Galinheiro/Celeiro/Lago pode ser comprado; os animais chegam na fase 4. A Rancheira trabalha no pomar e na lavoura até lá.
- Salário e carinho viram à meia-noite de Brasília até a fase 6 (fuso de cada conta).
- Escritura, nível, limpeza de lote, salário e ouro para testes pelo painel do admin (guia Fazenda).
- Correção: fora do jogo, quando faltava trabalho, a fila descontava a espera duas vezes (a fazenda andava mais devagar que o simulador). Corrigido na fase 3.

## G. Teste da fase 3 (dono, em produção)
1. Abra a Casa → Operadores: o Agricultor está no campo com a barra de energia. No topo, ao lado do nível, aparecem os personagens em campo (clique neles para abrir a Casa).
2. Painel do admin (guia Fazenda): nível 14 e 2.000.000 de ouro. Contrate Rancheira, Ferreiro e Comerciante: os 3 primeiros ficam no campo e o 4º no banco.
3. Saia do jogo por 1 h e volte: a energia de quem estava em campo caiu e a ferramenta desgastou um pouco (Casa → Equipamentos).
4. Barraca: compre 5 Cafés; em Equipamentos ponha no espaço de lanche do Agricultor.
5. Ponha o Comerciante no campo (mande alguém para o banco antes): a Barraca passa a pagar 71% e aparece a "Venda automática" em cada item.
6. Salário: no painel, dê ouro negativo até zerar o seu ouro e use "Cobrar salário agora". Na Casa aparece o aviso vermelho e quem deve fica "Desmotivado (−50%)". Venda algo e clique em "Pagar salários": volta ao normal.
7. Habilidades: o painel não dá nível de personagem; o Agricultor ganha 1 ponto por nível (≈ 11 h de trabalho). Quando tiver ponto, ponha em "Cultivo → Nó B" e veja o trabalho por hora subir 6%.
8. Pets (nível 5): adote o Gato (grátis), clique nele em frente à Casa (carinho: +5 de energia no Agricultor); o 2º clique do dia abre a guia Pets.
9. Forja: escolha o Ferreiro e melhore o Martelo; conserte a Enxada quando ela baixar de 100.
10. Compre um lote novo com o Ferreiro contratado: a limpeza é a metade do que era antes.

## H. Riscos e pontos em aberto
- 🆕 Clique sem limite: um robô que clica sem parar vira um jogador sempre online (e sem o limite offline). Tratar no antitrapaça (fase 9): frequência de cliques, horas seguidas online.
- Chance de semente rara (Lupa, pacotes, eventos): definir nas fases 3, 6 e 7; hoje o balanceamento supõe Comum.
- Depois do mapa completo sobra ouro: drenos de fim de jogo antes da fase 8 (seção 9).
- Plano grátis do Supabase: sem backup diário, sem recuperação por horário (o GDD pede) e sem bloqueio de senhas vazadas; avaliar o plano pago antes do beta.
- Legal: ECA Digital e LGPD (seção 15) com advogado antes de cobrar qualquer coisa.
