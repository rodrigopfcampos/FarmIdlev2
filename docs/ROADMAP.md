# Village Idle Farm — mapa do projeto (29/10/2026, fase 8a)

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
| **Fase 4** | Galinheiro e Celeiro com vagas e ampliação, Lago (+10% e +2 vagas de ave), 10 animais com raridade sorteada, ração por ciclo com fome, coleta por clique ou pela equipe, produtos no Silo e na Barraca, ramos de fase 4 (Criação, Mestria de Obras), Gato na produção, tetos de bônus; painel termina o ciclo dos animais | `supabase/migrations/…25000100`, `supabase/tests/phase4_test.sql` |
| **Fase 5** | Garagem com 4 veículos (Carroça inicial, compra, veículo ativo na vaga com contador), 5 rotas, minigame de setas conferido no servidor (tempo, erro −0,5 s, robô), comboio, sorteio na volta (crítico, sucesso, falha parcial), seguro, garantia contra azar, repetição automática com os mesmos produtos, clique em Receber com relatório narrado, desgaste, conserto e reforma com Kits na Forja, itens (vestimenta e amuleto) equipáveis e 3→1, Escrituras, demanda do dia igual para todos, Gerente conduzindo, Cachorro e ramos de expedição; painel traz as viagens de volta e dá itens | `supabase/migrations/…26000100`, `supabase/tests/phase5_test.sql`, `src/ui/garage.ts` |
| **Fase 6** | Clima por fuso em blocos de 3 h (sorteado e guardado, igual para todos do mesmo fuso), dia/entardecer/noite, evento noturno de 45 min entre 19:00 e 21:00 locais (nunca o mesmo da noite anterior, 1 por conta a cada 20 h), bônus no servidor (Sol forte e Calor Dourado aceleram lavoura e pomar a cada passo; chuva/neblina/eventos dão XP; noite +5% e Lua Cheia +40% com teto R ÷ 24), expedições −4/−8/−2, salário à meia-noite do fuso da conta, troca de fuso 1 vez a cada 30 dias (vale à meia-noite), ramo Clima da Botânica e aviso de 30 min do Papagaio; mapa com noite, chuva com respingo e terra molhada, neblina, brilho do sol forte e vagalumes; selo do clima, faixa do evento e painel com previsão; painel do admin vê a agenda e força/cancela eventos | `supabase/migrations/…27000100`, `supabase/tests/phase6_test.sql`, `src/scenes/weatherLayer.ts`, `src/ui/weather-ui.ts` |
| **Fase 7** | 5 missões diárias e 5 semanais sorteadas de um banco (só sistemas já liberados), metas pela produção do próprio jogador (média por hora, com piso pelo R), ouro e XP fixados no sorteio, 1 troca grátis por dia; as 5 diárias dão 1 pacote (até 4 por semana), 3 semanais dão 1 carta e as 5 dão +1 carta e 1 Escritura; tudo conta, inclusive equipe e fora do jogo. 10 cartas × 5 raridades com número de série, garantia (Raro+ a cada 10, Lendário+ a cada 40, Mítico a cada 120), pacote abrindo com a carta virando, até 3 buffs (a mesma carta só troca por raridade igual ou maior), Moeda da Sorte paga no fim, Estrada Livre e Trevo gravados na expedição, Armory (parcial e completo), fichário de 60 com ampliação e caixa de entrada, Colecionador da Vila; botões Missões e Cartas no topo com os 3 buffs; painel do admin dá carta e completa missões | `supabase/migrations/…28000100`, `supabase/tests/phase7_test.sql`, `src/ui/cards-ui.ts`, `src/farm/cards.ts` |
| **Fase 8a** | Amigos (busca pelo começo do apelido, pedido, aceite, desfazer), visita à fazenda de um amigo ou aleatória (no horário e clima do dono, sem ouro, Silo, inventário, cartas e missões), Ajudar (+10% de crescimento por 1 h no lote, ou −10% do que falta da limpeza; 1 por lote por hora; 10 dadas e 10 recebidas por dia; XP de 10 min da própria produção; Ferreiro Obras B do dono aumenta), Curtir (1 por dia), recado só com 12 emojis (até 3), bloqueio e denúncia, novidades com aviso no botão Amigos, missões "Ajude X vizinhos"; painel do admin mostra as denúncias | `supabase/migrations/…29000100`, `supabase/tests/phase8a_test.sql`, `src/ui/social-ui.ts` |
| **Fase 0** | Repositório, Supabase teste/produção (São Paulo), login com e-mail, 18+, ouro inicial, ledger e audit_log imutáveis, RLS, deploy automático no Cloudflare, CI no GitHub, simulador completo | ver seção D |
| Testes | `balance:check` (config × GDD × simulador), vitest (jogo e artes), testes do banco | CI a cada push |

## B. Decisões tomadas
- 🆕 (29/10, fase 8a) A ajuda de crescimento vale para lavoura e pomar (não para o pasto); a de limpeza tira 10% do que falta na hora. O Ferreiro em campo na fazenda AJUDADA aumenta o efeito (Obras B). Bloqueio vale dos dois lados (um não acha, não visita e não manda nada ao outro). Denúncia com motivo da lista; o painel mostra, a análise fica para a fase 9.
- 🆕 (29/10, antes da fase 8) Fase 7 aprovada (o visual das cartas o dono melhora depois). Mercado negocia produtos e cartas (regras da proposta do GDD). Drenos de fim de jogo: Encomendas da Vila e Estrelas da Vila (decorações ficam para depois). Fase 8 em 3 partes, com teste e "ok" em cada: 8a amigos e visitas; 8b ranking, Encomendas e Estrelas; 8c mercado.
- 🆕 (27/10, fase 7) Fase 6 aprovada. Missões e Cartas em botões no topo, com os 3 buffs ativos ao lado; banco de missões montado dos exemplos do GDD só com sistemas prontos (vizinhos e mercado entram na fase 8); tudo conta para as missões (cliques, equipe e fora do jogo); o pacote abre com a carta virando.
- 🆕 (26/10, fase 6) Fase 5 aprovada. Sol forte e Calor Dourado valem para lavoura e pomar; a Lua Cheia conta a expedição pela hora em que o veículo volta. Ícones do clima desenhados no código até chegar a arte (a prancha "Cards do climas" é a das 10 cartas da fase 7).
- 🆕 (24/10, fase 5) Fase 4 aprovada. Expedições: o veículo volta e espera o clique em Receber; a repetição automática (até 2×) sai sozinha com os mesmos produtos e também fica guardada; demanda do dia igual para todos (meia-noite de Brasília); comboio com 1 minigame só. Molduras novas das cartas e prancha dos 6 personagens.
- (24/10, fase 4) Fase 3 aprovada. Animais: coleta igual à lavoura (clique grátis; equipe gasta 0,5, 100% com Rancheira e 60% sem), casas mistas, ração cobrada no começo de cada ciclo.
- (23/10, fase 3) Funções de Comerciante, Gerente e Botânica antes das fases 4 e 5; lanches a 1% / 1,6% / 2,8% de R; carinho diário dos pets (4/10/18/30) com bônus no personagem vinculado; 2º e 3º pet a 1 dia de R; salário à meia-noite de Brasília até a fase 6 (detalhes no GDD, seção 7).
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
8. ✅ Teste da fase 3 e "ok" (24/10).
10. ✅ Teste da fase 4 e "ok" (24/10).
11. ✅ Teste da fase 5 e "ok" (26/10).
13. ✅ Teste da fase 6 e "ok" (27/10).
14. ✅ Teste da fase 7 e "ok" (29/10).
15. Testar a fase 8a em produção (lista na seção G) e dar o "ok". Antes da 8b: escolher o critério do ranking, o prêmio da Encomenda e o que as Estrelas compram (sugestões enviadas em 29/10).
9. ✅ Artes dos animais, pets, personagens e molduras novas (24/10).
12. ⏸️ Animações refeitas com a skill animacao-vif (pausado pelo dono em 25/10, voltar depois): 1 cultivos ✅; faltam colheita, árvores, animais, personagens, pets, veículos e vida do mapa.
5. Antes do beta: escolher um serviço de e-mail (SMTP) — o e-mail grátis do Supabase só envia para a equipe do projeto.

## D. Fases (GDD seção 13)

| Fase | Entrega | Situação |
| --- | --- | --- |
| 0 Base | Repo, Supabase teste/produção, login, deploy automático, config, ledger, audit_log, script das artes, simulador | **feito e testado em produção** |
| 1 Fazenda mínima | Mapa com 4 zonas, A1, Agricultor, 4 cultivos, `advance_farm`, offline 8 h, Silo, Barraca, painel básico | **feito e aprovado** (23/10) |
| 2 Progressão | XP/níveis, 50 cultivos, compra e limpeza dos lotes, Escritura, ferramentas, pomar | **feito e aprovado** (23/10) |
| 3 Personagens | 6 classes, energia, salário, desgaste, inventário, habilidades, pets | **feito e aprovado** (24/10) |
| 4 Animais | Galinheiro, Celeiro, Lago, ampliações, 10 animais com raridade, ração | **feito e aprovado** (24/10) |
| 5 Expedições | Garagem, 4 veículos × 5 raridades, 5 rotas, minigame, seguro, relatório | **feito e aprovado** (26/10) |
| 6 Clima e evento | Agenda por fuso, evento 19–21 h, filtros visuais | **feito e aprovado** (27/10) |
| 7 Missões e cartas | Missões, pacotes, 10 cartas, Armory, fichário, Colecionador | **feito e aprovado** (29/10) |
| 8 Multiplayer | 8a amigos e visitas · 8b ranking, Encomendas e Estrelas da Vila · 8c mercado (produtos e cartas) | 8a **feita** (29/10); falta o teste do dono |
| 9 Painel e antitrapaça | Todas as guias, regras da seção 12, alertas | — |
| 10 Beta fechado | 20–50 jogadores, carga 500, segurança, adequação legal | — |
| 11 Lançamento | Página, termos, privacidade, monitoramento, rollback | — |

## E. Artes que faltam
- (25/10) 1 cultivo e 1 estágio por lote: o dono escolhe o cultivo do lote inteiro; 1 planta grande (32×32, sem esticar) por canteiro, numa grade 4×2; a muda planejada só aparece com o mouse em cima. Recortes com `nearest` (sem borrão). Retratos dos personagens no tamanho nativo (176×180) nos cards; Comerciante só com as colunas 1, 3, 4, 7, 8, 10, 11 e 12 da linha 5.
- (fase 4) 10 animais recortados das pranchas "Animais 1" e "Animais 2" (6 quadros cada, 32×32). Produtos: 7 ícones recortados da prancha "Produtos dos Animais" (Leite de cabra, Ovo de ganso e Lã de alpaca usam o ícone base com outra cor).
- (fase 4) prancha "Imagem dos personagens": os 6 personagens (parado + 3 quadros de ação, 32×48) e 6 retratos 48×48; o Agricultor antigo foi trocado por este para manter o mesmo estilo. Molduras das cartas trocadas pela prancha nova "Moldura e parte de traz dos cards".
- (fase 4) recortados também: 3 pets (2 quadros parados, 24×24) e os insumos Ração, Combustível e Chave (para as próximas fases).
- (fase 1) recortadas também: estágios de 27 cultivos (pranchas Planta 2, 3 e 4), 40 ícones de produto, o Agricultor (parado + 3 quadros de ação) e a moeda da interface.
- Estágios e ícone: Beterraba, Batata-doce, Mandioca, Pepino, Quiabo, Maracujá.
- Ícone 32×32: Tomate, Mamão, Goiaba, Acerola, Jabuticaba.
- 2 medalhões de rota: Capital e Exportação.
- Ícones da interface (HUD).
- Ícones do clima (hoje desenhados no código): 1 prancha PNG 1024×512, fundo #1C1C1C, grade 5×2 — Ensolarado, Sol forte, Nublado, Chuva, Neblina / Noite, Chuva de Bênçãos, Calor Dourado, Neblina Mística, Lua Cheia.
- Luz amarela nas janelas à noite (GDD seção 4): precisa da posição das janelas ou de uma versão noturna das casas.
- Cerca dos lotes à venda (o GDD cita cerca + placa + entulho; hoje só placa e entulho).
- Opcional: Celeiro com telhado de telhas vermelhas; molduras de carta na proporção 2:3.

## F. Regras provisórias (mudam nas próximas fases)
- 🆕 Números novos da fase 7 que o GDD não fixava (ajustáveis em `config/missions.json` e `config/cards.json`): meta = horas da produção do próprio jogador (média móvel do valor da Feira por hora, peso 30% no dia novo, piso de 25% de R ÷ 24); prêmio da diária = 0,4 h de renda em ouro + 0,5 h de XP; missão nova "Ganhe XP com a produção" (para a troca grátis sempre ter opção); Negócios B do Comerciante dá +5% por ponto no ouro das missões; carta na caixa de entrada por 7 dias e depois vendida sozinha ao Colecionador (o jogador não perde o valor). O simulador ainda não conta missões nem cartas.
- Números novos da fase 6 que o GDD não fixava: previsão sem Botânica = 1 h (+1 h por ponto, até 6 h); o clima conta no teto permanente e o evento no absoluto; o +40% da Lua Cheia tem teto próprio (R ÷ 24 por evento). O aviso de fuso diferente do aparelho por 7 dias (alerta no painel) fica para a fase 9.
- Números novos da fase 5 que o GDD não fixava (ajustáveis na config): conserto do veículo = 10% do preço de 0 a 100%; raridade dos itens que caem = mesma tabela dos Kits da rota; o simulador ainda não conta a demanda +20% nem o conserto.
- O sorteio da expedição acontece na volta (a chance fica fixada na saída), para a garantia contra azar contar só viagens que já voltaram.
- Salário vira à meia-noite do fuso da conta; carinho do pet, demanda do dia e venda 1,5× ainda viram à meia-noite de Brasília.
- Escritura, nível, limpeza de lote, salário e ouro para testes pelo painel do admin (guia Fazenda).
- Correção: fora do jogo, quando faltava trabalho, a fila descontava a espera duas vezes (a fazenda andava mais devagar que o simulador). Corrigido na fase 3.

## G. Teste da fase 8a (dono, em produção)
Precisa de 2 contas (ex.: uma no computador e outra no celular, em janela anônima).
1. Conta A: botão **Amigos** no topo → Buscar → 3 letras do apelido da conta B → **Pedir amizade**.
2. Conta B: o botão Amigos ganha um ponto vermelho; em Amigos, **Aceitar**.
3. Conta A: **Visitar** a B. O topo vira "Visitando …" com Curtir, Recado e "Voltar para minha fazenda"; o mapa mostra a fazenda da B (sem ouro, Silo nem cartas).
4. Clique num lote com plantas crescendo → **Ajudar**: aparece +XP; o mesmo lote fica "ajudado há pouco" por 1 h. Um lote em limpeza também aceita ajuda (−10% do tempo).
5. **Curtir** (1 por dia) e **Recado** (até 3 emojis). Volte para a sua fazenda.
6. Conta B: Amigos → **Novidades** mostra a ajuda, a curtida e o recado; o mouse em cima do lote ajudado diz "ajuda de … (+10%)".
7. **Bloquear** a A na conta B: a A não acha mais a B na busca e não consegue visitar. **Denunciar** aparece no painel do admin (jogador → guia Denúncias).
8. Amigos → **Visitar uma fazenda aleatória** (precisa de outra conta nível 2+ ativa na semana).

## H. Riscos e pontos em aberto
- 🆕 Clique sem limite: um robô que clica sem parar vira um jogador sempre online (e sem o limite offline). Tratar no antitrapaça (fase 9): frequência de cliques, horas seguidas online.
- Chance de semente rara (Lupa, pacotes, eventos): definir nas fases 3, 6 e 7; hoje o balanceamento supõe Comum.
- Depois do mapa completo sobra ouro: drenos de fim de jogo antes da fase 8 (seção 9).
- Plano grátis do Supabase: sem backup diário, sem recuperação por horário (o GDD pede) e sem bloqueio de senhas vazadas; avaliar o plano pago antes do beta.
- Legal: ECA Digital e LGPD (seção 15) com advogado antes de cobrar qualquer coisa.
