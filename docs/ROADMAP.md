# Village Idle Farm — mapa do projeto (24/10/2026, fase 5)

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
| **Fase 0** | Repositório, Supabase teste/produção (São Paulo), login com e-mail, 18+, ouro inicial, ledger e audit_log imutáveis, RLS, deploy automático no Cloudflare, CI no GitHub, simulador completo | ver seção D |
| Testes | `balance:check` (config × GDD × simulador), vitest (jogo e artes), testes do banco | CI a cada push |

## B. Decisões tomadas
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
11. Testar a fase 5 em produção (lista na seção G) e dar o "ok".
9. ✅ Artes dos animais, pets, personagens e molduras novas (24/10).
5. Antes do beta: escolher um serviço de e-mail (SMTP) — o e-mail grátis do Supabase só envia para a equipe do projeto.

## D. Fases (GDD seção 13)

| Fase | Entrega | Situação |
| --- | --- | --- |
| 0 Base | Repo, Supabase teste/produção, login, deploy automático, config, ledger, audit_log, script das artes, simulador | **feito e testado em produção** |
| 1 Fazenda mínima | Mapa com 4 zonas, A1, Agricultor, 4 cultivos, `advance_farm`, offline 8 h, Silo, Barraca, painel básico | **feito e aprovado** (23/10) |
| 2 Progressão | XP/níveis, 50 cultivos, compra e limpeza dos lotes, Escritura, ferramentas, pomar | **feito e aprovado** (23/10) |
| 3 Personagens | 6 classes, energia, salário, desgaste, inventário, habilidades, pets | **feito e aprovado** (24/10) |
| 4 Animais | Galinheiro, Celeiro, Lago, ampliações, 10 animais com raridade, ração | **feito e aprovado** (24/10) |
| 5 Expedições | Garagem, 4 veículos × 5 raridades, 5 rotas, minigame, seguro, relatório | **feito** (24/10); falta o teste do dono em produção |
| 6 Clima e evento | Agenda por fuso, evento 19–21 h, filtros visuais | — |
| 7 Missões e cartas | Missões, pacotes, 10 cartas, Armory, fichário, Colecionador | — |
| 8 Multiplayer | Amigos, visitas, ranking, mercado (conteúdo a decidir) | — |
| 9 Painel e antitrapaça | Todas as guias, regras da seção 12, alertas | — |
| 10 Beta fechado | 20–50 jogadores, carga 500, segurança, adequação legal | — |
| 11 Lançamento | Página, termos, privacidade, monitoramento, rollback | — |

## E. Artes que faltam
- (fase 4) 10 animais recortados das pranchas "Animais 1" e "Animais 2" (6 quadros cada, 32×32). Produtos: 7 ícones recortados da prancha "Produtos dos Animais" (Leite de cabra, Ovo de ganso e Lã de alpaca usam o ícone base com outra cor).
- (fase 4) prancha "Imagem dos personagens": os 6 personagens (parado + 3 quadros de ação, 32×48) e 6 retratos 48×48; o Agricultor antigo foi trocado por este para manter o mesmo estilo. Molduras das cartas trocadas pela prancha nova "Moldura e parte de traz dos cards".
- (fase 4) recortados também: 3 pets (2 quadros parados, 24×24) e os insumos Ração, Combustível e Chave (para as próximas fases).
- (fase 1) recortadas também: estágios de 27 cultivos (pranchas Planta 2, 3 e 4), 40 ícones de produto, o Agricultor (parado + 3 quadros de ação) e a moeda da interface.
- Estágios e ícone: Beterraba, Batata-doce, Mandioca, Pepino, Quiabo, Maracujá.
- Ícone 32×32: Tomate, Mamão, Goiaba, Acerola, Jabuticaba.
- 2 medalhões de rota: Capital e Exportação.
- Ícones da interface (HUD).
- Cerca dos lotes à venda (o GDD cita cerca + placa + entulho; hoje só placa e entulho).
- Opcional: Celeiro com telhado de telhas vermelhas; molduras de carta na proporção 2:3.

## F. Regras provisórias (mudam nas próximas fases)
- 🆕 Clima (chuva, neblina, noite) ainda não tira pontos das expedições: entra na fase 6. Cartas (Estrada Livre, Trevo) entram na fase 7.
- 🆕 Números novos da fase 5 que o GDD não fixava (ajustáveis na config): conserto do veículo = 10% do preço de 0 a 100%; raridade dos itens que caem = mesma tabela dos Kits da rota; o simulador ainda não conta a demanda +20% nem o conserto.
- 🆕 O sorteio da expedição acontece na volta (a chance fica fixada na saída), para a garantia contra azar contar só viagens que já voltaram.
- Salário e carinho viram à meia-noite de Brasília até a fase 6 (fuso de cada conta).
- Escritura, nível, limpeza de lote, salário e ouro para testes pelo painel do admin (guia Fazenda).
- Correção: fora do jogo, quando faltava trabalho, a fila descontava a espera duas vezes (a fazenda andava mais devagar que o simulador). Corrigido na fase 3.

## G. Teste da fase 5 (dono, em produção)
1. Clique na Garagem: aparecem os 4 veículos (Carroça na sua conta; os outros em silhueta com nível e preço) e a demanda do dia.
2. Tenha produtos no Silo. "Nova expedição" → Carroça, Feira da Vila, "Encher com o que vale mais" → "Partir". Faça as setas (teclado ou botões): sem erro e rápido dá **Perfeita**.
3. No mapa a vaga da Garagem fica vazia com "Volta em …". No painel do admin, "Trazer as viagens de volta": aparece "Receber!". Clique na Garagem → Receber: abre o relatório (ouro, achados, texto da viagem).
4. Minigame ruim: mande outra e deixe o tempo acabar sem tocar → "Falhou: −10 pontos".
5. Nível 6 pelo painel. Cidade Vizinha **com seguro**; se falhar, o relatório mostra a carga que voltou ao Silo e o seguro devolvendo a perda acima de 10%.
6. Garantia contra azar: depois de 2 falhas seguidas, a Garagem avisa "+25 pontos" na próxima (dá para forçar com várias viagens ou ver o teste automático).
7. Repetição: deixe "Repetir até 2×" marcado; traga de volta pelo painel: o veículo sai de novo sozinho com os mesmos produtos; ao Receber chegam as 3 viagens.
8. Compre o Carro (nível 6, 33.000) e mande os dois juntos (comboio): 1 minigame com mais setas.
9. Painel: dê 1 "Kit de Reforma Incomum" e nível 8. Forja → Veículos → Reformar a Carroça (9.900): ela fica 2 h parada ("Trazer as viagens de volta" também termina a reforma) e volta Incomum, com 72 de capacidade e o sprite verde.
10. Painel: dê "Chapéu de Palha Raro". Casa → Equipamentos → Vestimenta: equipe no Agricultor (+24 de energia máxima).

## H. Riscos e pontos em aberto
- 🆕 Clique sem limite: um robô que clica sem parar vira um jogador sempre online (e sem o limite offline). Tratar no antitrapaça (fase 9): frequência de cliques, horas seguidas online.
- Chance de semente rara (Lupa, pacotes, eventos): definir nas fases 3, 6 e 7; hoje o balanceamento supõe Comum.
- Depois do mapa completo sobra ouro: drenos de fim de jogo antes da fase 8 (seção 9).
- Plano grátis do Supabase: sem backup diário, sem recuperação por horário (o GDD pede) e sem bloqueio de senhas vazadas; avaliar o plano pago antes do beta.
- Legal: ECA Digital e LGPD (seção 15) com advogado antes de cobrar qualquer coisa.
