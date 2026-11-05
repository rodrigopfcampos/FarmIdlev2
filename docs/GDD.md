# Village Idle Farm — Documento do Jogo (GDD) v2

Versão 2 · 19/10/2026, atualizada em 20/10/2026 (seção 6 completa), 22/10/2026 (raridade global, cartas, ferramentas e artes recortadas) e 23/10/2026 (simulador completo: R e capacidade de trabalho calibrados; depois do teste da fase 2, plantio e colheita por clique e começo rápido). Junta o documento atual (seções 1 a 6) com a ideia anterior (seções 7 a 15), adaptada à ideia atual. **🆕** marca o que é novo ou mudou nesta versão.

## O que mudou na v2

| Tema | Antes | Agora |
| --- | --- | --- |
| Lotes | 25 (1 inicial + 24 compras) | **30** (1 inicial + 29 compras): 21 lavouras, 6 pomares, Galinheiro, Celeiro e Lago |
| Lote inicial | — | **A1**, ao lado da barraca |
| Preço do lote | 0,28 × 1,14^(n−1) × R(⌈1,75 n⌉) | **0,28 × 1,10^(n−1) × R(⌈1,46 n⌉)** sobre o R remedido com 30 lotes; mesmas metas de dias (seção 14) |
| Nível do último lote | 42 | **43** (o nível máximo continua 50) |
| Escritura | da 15ª compra em diante (10 no total) | da **20ª** compra em diante (continuam 10) |
| Limpeza | 1 h + 15 min × n (até 7 h) | **1 h + 12 min × n** (até 6 h 48): nunca passa do limite offline de 8 h |
| Vizinhança | "lote vizinho" | divide um lado, sem diagonal; **Galinheiro e Celeiro** podem ser comprados sem ser vizinhos |
| Mapa | grade quadrada 3/4, 1920×1080 | **isométrico 2:1, 1672×940**, contornos medidos em `config/mapConfig.json` |
| Zonas do mapa | — | **Casa** (com o Silo), **Forja**, **Barraca** e **Garagem** (à esquerda do A5) |
| Garagem | — | mostra o veículo que está em casa (o ativo primeiro; se ele viajou, outro que ficou); o clique abre os 5 veículos |
| Pomar | 1 árvore desenhada no fundo | fundo sem árvores; o jogo desenha as 4 árvores (muda → adulta) |
| Mudas no mapa | 32×32 | **16×16** (cada canteiro mede ~73×37 px); 32×32 fica para ícones |
| Plataforma | navegador (PWA) | confirmado: **navegador primeiro** |
| Mercado entre jogadores | regras definidas | regras mantidas como **proposta**; o que pode ser negociado será decidido antes da fase 8 |
| Comerciante, ramo Mercado | — | só funciona a partir da fase 8; sem perda, porque os pontos completam só 2 dos 3 ramos |
| Lanches | "da loja" | comprados na **Barraca** |
| Seção 6 | parava no Morango | **completa:** 50 cultivos e 10 animais (`config/crops.json`, `config/animals.json`) |
| XP dos recorrentes | número da tabela lido como "por colheita" (5× mais XP) | o número era do **plantio inteiro**: por colheita = ÷ 5 |
| Árvore do pomar | permanente | permanente, mas pode ser **derrubada de graça** para trocar de fruta |
| Lago | +10% nas aves | **+10% nas aves e +2 vagas no Galinheiro** (só aves) |
| Capacidade de trabalho | não definida | **2,67 unidades por personagem por hora** (ferramenta de Madeira), usada quando o jogador está fora; com o jogo aberto, plantar e colher por clique é grátis 🆕 |
| Renda de Referência (R) | medida com 25 lotes | **remedida com 30 lotes** pelo simulador completo (`tools/sim`): começo mais lento (R do nível 1 = 1.500), fim mais rico |
| Arte das árvores do pomar | uma árvore por fruta | 2 bases que já existem (folhosa e palmeira) + frutas desenhadas por código |
| Cartas | 8 ilustrações para 10 cartas | **10 ilustrações** + 5 molduras + verso; a carta 6 passa a se chamar **Tempestade** (mesmo efeito da antiga Lua Prateada) |
| Raridade | só cartas, veículos e itens | **raridade global** também em sementes, mudas e animais: ×1 / ×1,2 / ×1,5 / ×2 / ×3 (seção 9) |
| Raridade dos veículos | +2 a +8 pontos de sucesso e menos desgaste | **capacidade, velocidade e segurança ×1,2 a ×3** (seção 8) |
| Animais | sempre iguais | raridade sorteada na compra: 75% / 18% / 5% / 1,5% / 0,5% (média ×1,09 na produção) |
| Ferramentas | sem desgaste | **durabilidade**: −2,5 por hora de trabalho; abaixo de 30% trabalha a 50%; conserto na Forja |
| Hospedagem | Cloudflare Pages ou Vercel | **Cloudflare Pages** (deploy automático pelo GitHub) |

## Pendências para fechar o documento

1. **Artes que ainda faltam** (seção 4): estágios e ícone de Beterraba, Batata-doce, Mandioca, Pepino, Quiabo e Maracujá; ícone de Tomate, Mamão, Goiaba, Acerola e Jabuticaba; 2 medalhões de rota (Capital e Exportação).
2. **Chance de semente rara:** quanto cai na pesquisa da Lupa, nos pacotes e nos eventos (fases 3, 6 e 7). Até lá o balanceamento supõe tudo Comum.
3. **Mercado entre jogadores:** decidir o que pode ser negociado, antes da fase 8.

## 1. Seu papel e suas regras

Você é um time sênior de jogos (game designer, backend, frontend Phaser, segurança e QA) construindo o **Village Idle Farm**: um jogo idle de gerenciamento de fazenda e recursos, multiplayer online, em pixel art, combinando a atmosfera acolhedora do Stardew Valley com a mecânica de estações, slots e retroalimentação econômica do Farmers World. O dono do projeto não programa: ele descreve o processo, faz o deploy e testa em produção.

- Trabalhe uma fase por vez (seção 13). Não comece a próxima sem o "ok" do dono.
- Quando faltar informação, pergunte. Nunca invente regra de jogo nem chute um número.
- O servidor manda em tudo. O cliente só envia intenções; tempo, sorteios, preços e recompensas são calculados no servidor.
- Todo número de balanceamento fica em arquivos versionados (`config/*.json`), editáveis pelo painel admin. Nada fixo no código.
- Toda mudança de ouro, XP, item, carta ou Escritura passa por um livro-razão (ledger) que nunca é apagado.
- Cada regra tem teste automático. Construa também um simulador de economia (seção 14) e rode-o a cada mudança de balanceamento. Fase só termina com tudo verde.
- Ao fim de cada fase entregue: o que mudou, como fazer o deploy e um checklist de teste em produção escrito para quem não programa.
- TypeScript em tudo. Comentários em português, nomes no código em inglês. Textos do jogo em português do Brasil, preparados para tradução.
- Nenhum serviço pago e nenhuma biblioteca nova sem perguntar. Nenhuma chave ou senha no cliente ou no repositório.
- Inspire-se nas mecânicas do Stardew Valley e Farmers World, mas nunca copie artes, nomes, textos ou músicas deles.
- **Regra visual estrita (zero pathfinding + diorama vivo):** personagens, animais e veículos não caminham pelo mapa. Eles operam em Slots de Estação fixos na interface e nos prédios, enquanto o mapa central funciona como um diorama vivo em pixel art (canteiros com 6 mudas balançando ao vento, solo que escurece e encharca na chuva, partículas de clima e iluminação noturna), com escala inteira obrigatória (`pixelArt: true`, `roundPixels: true`).

## 2. O jogo, a retroalimentação e o que aproveitamos do Stardew Valley

O jogador começa com 1 lote (A1) e 1 personagem no slot de operação, e cresce até ocupar o mapa inteiro com **30 lotes 🆕**, 6 personagens, 50 cultivos, 10 animais e 4 veículos. A fazenda trabalha sozinha enquanto ele está fora (até 8 h). Cada jogador tem sua própria fazenda; o multiplayer é visitar fazendas e, mais tarde, negociar no mercado.

### Modelo de interface e ciclo de retroalimentação (estações e slots)

O jogo não tem bonecos andando pela fazenda. A tela principal mostra o **Mapa Interativo da Fazenda** (30 lotes em visão isométrica) no centro e **Painéis de Slots** nas bordas.

- **Produção e custo operacional:** os canteiros (6 mudas visíveis por canteiro) e os animais produzem em tempo real e offline (até 8 h). Cada ciclo consome Energia e Durabilidade da Ferramenta dos personagens nos 3 Slots de Campo Ativo, além de Sementes (no replantio automático) e Ração (nos animais).
- **Escoamento e risco:** toda a colheita vai para o Silo (que fica na Casa 🆕). Para transformar produção em ouro, o jogador despacha os produtos nos Slots de Veículos pelas 5 Rotas de Expedição (com minigame de partida, risco de perda parcial e chance de itens, Kits de Reforma e Escrituras) ou vende sem risco na Barraca a 70% do valor.
- **Manutenção e retroalimentação:** o ouro volta para a máquina:
  - salário diário dos contratados às 00:00 (evita o estado Desmotivado);
  - Lanches para a energia dos operadores, comprados na Barraca 🆕;
  - Ferreiro para reparar ou melhorar Ferramentas (Madeira → Cobre → Ferro → Ouro → Cristal) e consertar ou reformar Veículos;
  - compra e limpeza de Lotes (com Escritura da 20ª compra em diante 🆕).
- **3 Slots de Cartas Mágicas Ativas** no topo da interface, com as cartas ativadas (círculo mágico girando na cor da raridade), que dão buffs de 1 h a 2 h 30 em toda a fazenda.

| Sistema | No Stardew Valley | No Village Idle Farm (slots e diorama) |
| --- | --- | --- |
| Tempo | Dias acelerados, 4 estações de 28 dias | Relógio real do fuso de cada jogador; produção offline até 8 h |
| Operação e energia | Uma barra do fazendeiro andando pelo mapa | Sem bonecos andando; 6 operadores em 3 Slots de Campo e 3 Slots de Banco (descanso), com rodízio automático |
| Ferramentas | Gastam energia, sem desgaste | 1 ferramenta por classe em 5 materiais, com durabilidade e reparo pago na Forja |
| Cultivos | Por estação; colheita única ou que rebrota; estrelas | 50 cultivos por nível: lavoura, recorrente (5 colheitas) e pomar (árvore permanente); 6 mudas vivas por canteiro; Colheita Dourada (2,5×) |
| Venda | Caixa que paga na manhã seguinte | Expedições em 5 rotas com risco, Barraca segura a 70% e, mais tarde, mercado entre jogadores |
| Automação | Irrigadores e máquinas | Operadores nos slots trabalham e replantam sozinhos; ferramenta melhor = mais capacidade |
| Animais | Galinheiro e celeiro; amizade melhora o produto | 10 animais nos slots do Galinheiro e do Celeiro (4 → 8 → 12 vagas; +2 para aves com o Lago 🆕), cuidados pela Rancheira |
| Habilidades | 5 perícias com profissão nos níveis 5 e 10 | Árvore única por personagem com 3 ramos; os pontos só completam 2 |
| Clima | Chuva rega; sorte do dia | Clima pelo fuso de cada jogador (terra encharcada, folhas agitadas) + 1 evento noturno por dia (19h–21h local) |
| Coleções | Pacotes do Centro Comunitário | Armory de Cartas Mágicas e, no futuro, Álbum da Vila |
| Multiplayer | Cooperativo na mesma fazenda | Fazendas separadas; visitas com ajuda; mercado com conteúdo a decidir 🆕 |

Ideias para fases futuras (não construir agora): processamento de produtos (queijo, geleia, vinho), Álbum da Vila com coleções premiadas, amizade com animais, festivais mensais da comunidade e estações do ano.

## 3. Tecnologia, arquitetura e segurança

O jogo roda no **navegador** (PC e celular), instalável como app (PWA), e todo o cálculo de jogo acontece no servidor. 🆕 Decisão confirmada: navegador primeiro; lojas e o que será negociado entre jogadores ficam para depois.

| Parte | Tecnologia |
| --- | --- |
| Jogo | Phaser 4 (versão estável mais recente) + TypeScript + Vite, PWA |
| Servidor e banco | Supabase: Postgres, Auth, Row Level Security, Edge Functions, Realtime, Storage, pg_cron |
| Painel admin | App web separado (React + Vite) no mesmo Supabase, só para contas admin com 2FA |
| Hospedagem do jogo | Site estático no **Cloudflare Pages** 🆕 (`npm run build` → pasta `dist`, deploy a cada push na `main`) |
| Alertas | Webhook do painel para Discord, Telegram ou n8n |

Toda ação passa pelas funções do servidor; o banco só aceita escrita vinda delas.

### Como o servidor manda no jogo (modelo idle)

- O estado da fazenda é salvo com horários. Em toda ação, o servidor primeiro roda `advance_farm(farm_id, agora)`: avança a fazenda até agora, no máximo 8 h depois da última atividade do jogador, de forma determinística (colheitas, gasto de energia nos slots, desgaste de ferramentas, lanches consumidos, rodízio de operadores e limpeza de lotes). Só depois aplica a ação.
- 🆕 **Relógio da fazenda (fase 1):** cada fazenda guarda o próprio tempo (`farm_time`, em segundos de tempo ativo). Ele anda junto com o relógio do servidor até 8 h depois da última ação do jogador e então para; quando o jogador volta, continua de onde parou (o que estava crescendo termina depois). O jogo no aparelho só usa o horário que o servidor manda e o cronômetro do navegador, nunca a hora do aparelho.
- 🆕 **Trabalho guardado:** o trabalho que o Agricultor não usa fica guardado até o equivalente a 1 h (conta nova começa com 1 h). Fora do jogo ele faz tudo numa fila só, na ordem em que as tarefas ficaram prontas: plantar gasta 0,5 e colher gasta 0,5 (inclusive colheita extra de recorrente e de árvore). Sem ouro para a semente, o canteiro para até o jogador vender algo.
- 🆕 **Clique do jogador (fase 2):** com o jogo aberto, clicar num canteiro maduro colhe e replanta na hora; escolher um cultivo num canteiro vazio planta na hora; o botão "Colher e plantar (N)" faz isso na fazenda inteira. O clique não gasta trabalho do Agricultor, só a semente. A colheita não é mais automática: o canteiro maduro espera o clique ou o Agricultor.
- O cliente envia só intenções: `plant(canteiro, cultura)`, `repair_tool(personagem)`, `send_expedition(veiculo, rota, carga, seguro)`, `buy_lot(lote)`, `hire(classe)` etc. Nunca envia ouro, tempo ou resultado.
- Todo sorteio (expedição, cartas, clima, itens) é feito no servidor com gerador criptográfico e gravado antes de aparecer na tela.
- Escrita no banco só por funções RPC com validação. Row Level Security bloqueia escrita direta em todas as tabelas; cada jogador lê só os próprios dados (mais perfis públicos e, quando existir, anúncios do mercado).
- Compras e mercado em transação com trava de linha (`SELECT … FOR UPDATE`) contra gasto duplo; toda ação leva `idempotency_key`.
- Limite de requisições: 10 ações/s por conta e 30 tentativas de login/min por IP.
- Virada do dia pelo fuso de cada conta (seção 10): na primeira ação depois da meia-noite local, o servidor roda a virada (missões, salários, clima e evento). Tarefas agendadas (pg_cron) cuidam só do que é global em UTC: ranking semanal e Encomendas da Vila.

### Segurança e dados

- HTTPS, login por e-mail verificado ou Google (Supabase Auth); 2FA obrigatório para admins.
- Segredos só em variáveis de ambiente do servidor. CSP e CORS restritos ao domínio do jogo.
- Backup diário + recuperação para qualquer momento (point-in-time).
- Logs de auditoria imutáveis, inclusive das ações dos admins.
- Dados mínimos: e-mail, apelido, data de nascimento (regra de idade da seção 15), dispositivo e IP para antitrapaça. Exportar e apagar conta pelo próprio jogo.

### Tabelas principais

profiles, wallets, farms, owned_lots 🆕, plots, silo 🆕, game_config 🆕, lots, plantings, trees, buildings, animals, characters, character_skills, items, character_equipment, pets, vehicles, expeditions, player_cards, card_packs, pity_counters, missions, player_missions, weather_days, market_listings, market_trades, visits, friendships, ledger, audit_log, admin_actions, anticheat_alerts, config_versions, reports.

## 4. Artes, visão do mapa e Motor de Vida em pixel art

🆕 As artes do mapa estão em **visão isométrica 2:1** (`projection: "isometric_2to1"` na config). Como não há personagens nem veículos andando, recortamos só os quadros usados nos Slots de Estação e no mapa vivo.

| Imagem enviada | O que contém | Uso |
| --- | --- | --- |
| Frutas, legumes e verduras | 40 ícones (melancia 2×: inteira e fatia) | Ícone 32×32 no Silo e na interface; no mapa, muda 16×16 🆕 (melancia inteira no canteiro, fatia no Silo) |
| Animais | 10 animais × 6 poses | 1 pose 3/4: parado + comendo, loop de 2 quadros, 48×48, no slot do Galinheiro ou Celeiro |
| Personagens | 6 classes: frente, costas, lado, andando e 2 quadros de ação | Pose frontal/3/4 parada + 2 quadros de ação (32×48) nos cards dos Slots de Campo e Banco; descartar costas e caminhada |
| Pets | Cachorro, gato e papagaio em várias poses | 1 pose em loop de 2 quadros (32×32) no ponto do pet, na frente da Casa 🆕 |
| Veículos | Carroça, carro vermelho, picape verde, caminhão amarelo; 4 ângulos | 1 ângulo 3/4 fixo (96×64) na vaga da Garagem e na faixa de Expedição, com animação de parado 🆕 |
| Mapa da fazenda | Fazenda completa | Camada de fundo: `public/assets/map/farm_base_map.png`, 1672×940, terraços do pomar já sem árvores 🆕 |
| Pranchas de 22/10 🆕 | 10 ilustrações e 10 mini-ícones de carta, 5 molduras + verso, fichário, ferramentas em 5 materiais, roupas/amuletos/lanches/Escritura/Kit, 3 estágios genéricos, árvore folhosa e palmeira (muda, adulta, com frutos), Celeiro, 14 cultivos maduros, 9 frutas (saco + 4 estágios), 4 veículos parados (4 quadros) e em 5 raridades, lotes arados, cercas, placa, entulho, 3 celeiros com silo, Galinheiro, estufa, píer, pinheiro, 3 destinos e 6 resultados de expedição | Recortadas por `npm run assets` em 190 PNGs em `public/assets/sprites` + `manifest.json` (tamanho e âncora de cada um). Trigo, Girassol e Algodão ficam guardados em `crops/extras`, sem uso |
| Estágios de crescimento (4 planilhas) 🆕 | 36 cultivos: saco de semente + 4 estágios | Mudas 16×16 no canteiro; saco de semente na Barraca e no Silo |
| Galinheiro, estufa, píer e árvores 🆕 | Galinheiro, estufa, píer, árvore folhosa, macieira, palmeira e pinheiro | Galinheiro no C1 (112×112); árvore folhosa e palmeira são a base das árvores do pomar (48×64). Estufa sem uso por enquanto |
| Produtos dos animais e insumos 🆕 | 7 produtos + galão, saco de ração e chave inglesa | Ícones 32×32 no Silo. Leite de cabra, Lã de alpaca e Ovo de ganso saem por variação de cor (script) |

**Preparação das artes (script automático, `tools/slice-assets.js` + `tools/assets/sheets.json`) 🆕:** remover o fundo escuro (cor lida na borda de cada prancha, inclusive buracos fechados como o vão das molduras e as sombras), recortar cada sprite por contorno, padronizar tamanho (ícone de cultivo 32×32, muda 16×16, árvore 48×64, prédio de pasto 112×112, personagem 32×48 por quadro, animal 48×48, pet 32×32, veículo 96×64), escalar só por número inteiro sem suavizar (NEAREST / `image-rendering: pixelated`), âncora na base inferior (`origin(0.5, 1.0)`) para não tremer, gerar spritesheets + atlas JSON e nomes padronizados (`crop_alface_ready.png`).

### Mapa 🆕

- A imagem é a camada de fundo, desenhada em escala 1 (1672×940). Por cima, `config/mapConfig.json` define, com coordenadas medidas na própria imagem:
  - os 30 lotes (contorno clicável, tipo, vizinhos), os 8 canteiros de cada lavoura, as 4 vagas de árvore de cada pomar, a posição da placa e do entulho, e o prédio de cada pasto (Galinheiro no C1, Celeiro no centro do C2, 112×112);
  - as 4 zonas funcionais: **Casa** (com o Silo: inventário, operadores e equipamentos), **Forja** (ferramentas, conserto e reforma de veículos), **Barraca** (venda rápida a 70% e compra de lanches) e **Garagem** (vaga do veículo ativo, à esquerda do A5).
- Lote bloqueado aparece escurecido, com cerca, placa de preço e entulho (pedras e tocos).

### Especificações das artes novas 🆕

Todas em PNG com fundo transparente (se a ferramenta de IA não fizer transparência, fundo liso escuro #1C1C1C ou #FF00FF 🆕), sem suavização e com âncora no centro da base.

| Arte | Tamanho | Detalhes |
| --- | --- | --- |
| Muda no canteiro | 16×16 por estágio | 36 cultivos já têm 4 estágios (reduzidos das planilhas). 🆕 Cenoura, Batata, Morango e Tomate: 3 estágios genéricos + o maduro. Faltam 6 (Beterraba, Batata-doce, Mandioca, Pepino, Quiabo e Maracujá); até lá, estágios genéricos + o ícone |
| Árvore do pomar | adulta 48×64 (já existe: folhosa e palmeira); muda 24×32 (falta: 1 folhosa e 1 palmeira) | As frutas são desenhadas por código sobre a copa (pontos de 2×2 a 3×3 px, na cor do ícone de cada fruta). Banana e Mamão usam a palmeira; as outras 13 frutas, a folhosa. 4 por terraço, a 44 px uma da outra |
| Celeiro (prédio) | 112×112 no mapa | Mesma vista, luz e estilo do Galinheiro (madeira, telhado de telhas vermelhas); fica no centro do cercado C2 |
| Veículo parado | tira de 384×64 (4 quadros de 96×64) | Mesmo ângulo 3/4 nos 4 veículos; 6 quadros/s em loop. Carroça: cavalo respira (1 px) e mexe o rabo. Carro, picape e caminhão: carroceria vibra 1 px e sai uma fumacinha de 2 a 3 px do escapamento |
| ~~Máscara de raridade do veículo~~ 🆕 | — | Não é mais necessária: cada raridade tem o próprio sprite (seção 4, visual dos veículos) |

### Motor de Vida no mapa (canteiros de 6 mudas, vento e solo reativo)

O Phaser 4 desenha os canteiros e pomares com estes efeitos procedurais em pixel art:

- **6 mudas por canteiro (sub-grade 3×2):** cada um dos 8 canteiros de uma lavoura desenha 6 mudas 16×16 da cultura (2 fileiras de 3), ordenadas por profundidade (y-sort). Cada muda tem um pequeno descompasso de tempo (80 a 240 ms). Quando a planta muda de estágio (semente → broto → crescendo → pronto), as 6 dão um pulo elástico (squash & stretch) em sequência.
- **Vento em pixels inteiros:** uma onda global percorre a fazenda da esquerda para a direita: `offset = round(sin(tempo × velocidade + plotX × 0,4) × força)`. A raiz fica no solo e a metade de cima da muda desloca de −1 a +2 px no eixo X (sem rotação, pixels sempre quadrados). Na chuva, velocidade e força dobram.
- **Solo reativo:** tempo seco (ensolarado, sol forte, nublado) usa terra marrom-clara; no sol forte (+10% de crescimento) sobem pixels de brilho das folhas. Na chuva, a terra de todos os canteiros escurece 35% (#6E5644) e mostra 2 a 3 pixels azul-claros de poça.
- 🆕 **Estágios e árvores (fase 2):** os estágios trocam em 15%, 50% e 85% do crescimento (`config/farm.json`); os estágios pequenos são ampliados no recorte para a muda aparecer no canteiro. A árvore do pomar é muda até 50% do 1º crescimento, depois adulta, e mostra frutas 4×4 px na cor da fruta a partir de 85% de cada ciclo (cores e posições em `config/farm.json`). Lote comprado mostra o entulho e o contador de limpeza; depois, o prédio do pasto aparece.
- **Gotas:** partículas de 1×4 px em diagonal; ao cair num canteiro, fazem um respingo de 2 px e a muda atingida abaixa 1 px por 120 ms.
- **Noite e Colheita Dourada:** noite (19h–05h59) com filtro azul-escuro, luz amarela nas janelas e vagalumes 2×2 nos eventos noturnos. Na Colheita Dourada (2,5×), as 6 mudas ganham contorno dourado (#F2C230) e soltam estrelinhas.

**Como pedir as artes à IA 🆕:** 1 imagem quadrada de 1024×1024 por arte (ou uma prancha em grade, com espaço entre os sprites), fundo liso #1C1C1C ou #FF00FF, o objeto sozinho e centralizado ocupando cerca de 85% da largura, sem chão, sem sombra projetada e sem texto. O script recorta e reduz para o tamanho final da tabela.

**Artes que faltam** 🆕 (usar marcador provisório no mesmo estilo até ficarem prontas): estágios e ícone de Beterraba, Batata-doce, Mandioca, Pepino, Quiabo e Maracujá; ícone 32×32 de Tomate, Mamão, Goiaba, Acerola e Jabuticaba; 2 medalhões de rota (Capital e Exportação; até lá a Capital usa o da cidade e a Exportação o do porto); ícones da interface. Cenoura, Batata, Morango e Tomate usam os 3 estágios genéricos + o maduro da prancha nova.

**Observações das pranchas de 22/10:** o Celeiro veio com telhado de madeira (o Galinheiro tem telhas vermelhas); as molduras de carta vieram mais estreitas que 2:3 e foram esticadas para 64×96 (o vão fica entre 42×55 e 44×60; a ilustração 44×64 vai por baixo e a moldura cobre as bordas).

### Cores de raridade (cartas, veículos e itens)

| Raridade | Cor | Hex |
| --- | --- | --- |
| Comum | Cinza | #9E9E9E |
| Incomum | Verde | #4CAF50 |
| Raro | Azul | #2F7BE5 |
| Lendário | Amarelo (dourado) | #F2C230 |
| Mítico | Vermelho | #E5383B |

### Visual das cartas

- Inspiração: cartas mágicas elegantes no estilo de anime, como as de Sakura Card Captors. Arte original: não copiar símbolos, molduras, verso, nomes ou personagens daquele anime, só o formato e a ideia (carta vertical, ornamentada, com círculo mágico e ilustração encantada).
- Formato vertical 2:3, base 64×96 em pixel art (exibida em 2× ou 3×). Ilustração do tema no centro (44×64), círculo mágico atrás, nome numa faixa embaixo, símbolo da carta no topo.
- 🆕 Montagem no jogo: um `Container` do Phaser empilha ilustração (44×64) + moldura vazada da raridade (64×96) + nome em texto na faixa de pergaminho + cronômetro no topo. O mini-ícone 12×12 aparece no slot de buff ativo.
- Cada carta tem 1 ilustração e 5 molduras: Comum cinza simples; Incomum verde com ramos; Raro azul com estrelas; Lendário dourado com brilho animado; Mítico vermelho com aura animada e efeito holográfico. Verso único com o brasão do jogo.
- Abertura do pacote: a carta gira dentro de um círculo mágico e acende na cor da raridade; no Mítico, partículas e um tremor leve na tela.

### Visual dos veículos por raridade

🆕 Cada raridade tem o próprio sprite 96×64 (prancha 4 × 5): o veículo ganha peças (rodas reforçadas, bagageiro, faróis, estepe, carga extra) em vez de trocar de cor; a cor da raridade aparece na moldura do card e no selo. A animação de parado de 4 quadros existe para os Comuns; nas outras raridades o código faz o parado (corpo desce 1 px a cada 2 quadros e solta a fumacinha), e Lendário e Mítico ganham brilho animado. Assim a máscara de raridade deixa de ser necessária.

## 5. Mapa e expansão de terreno 🆕

O mapa tem **30 lotes**: o inicial (A1, lavoura) + 29 para comprar (20 lavouras de 8 canteiros, 6 pomares de 4 árvores e 3 pastos: Galinheiro, Celeiro e Lago). Os nomes A1–A21, P1–P6, C1, C2 e L são os de `config/mapConfig.json`. No simulador completo (seção 14), o jogador regular libera tudo no dia 78, o casual no dia 113 e o dedicado no dia 71, com espera máxima por ouro de 2,5 / 3,8 / 2,4 dias 🆕.

Regras que mantêm o equilíbrio:

- **Preço pela quantidade de lotes já comprados (n), não pela posição.** A escolha do lote é livre e o custo continua previsível.
- **Dois requisitos: nível mínimo e ouro.** Nível mínimo da n-ésima compra = arredondar para cima (1,53 × n). Pisos por tipo: Galinheiro nível 3, Celeiro 8, Pomar 10, Lago 11 (vale o maior dos dois).
- **Vizinhança:** só dá para comprar um lote que divide um lado com um lote seu (sem diagonal). As ligações exatas, inclusive pomar–lavoura, pomar–pomar e lago–lavoura, estão em `config/mapConfig.json`. **Exceção:** Galinheiro e Celeiro podem ser comprados de qualquer lugar, para os animais não ficarem presos atrás de outras compras (o início é no A1, longe dos pastos).
- **Escritura da 20ª compra em diante:** cada compra exige 1 Escritura (missão semanal completa ou expedição Capital ou mais longe). Continuam 10 no total, como antes; elas começam a acumular desde a primeira semana.
- **Limpeza:** o lote comprado vem com pedras e tocos. O Ferreiro limpa em 1 h + 12 min × n (outra classe leva o dobro; 🆕 até a fase 3 não há Ferreiro, então vale o dobro). Os canteiros já aceitam o cultivo durante a limpeza e começam quando ela acaba. Cada vizinho que ajuda corta 10% do tempo, até 5 ajudas por dia. A limpeza mais longa (6 h 48) cabe no limite offline de 8 h.
- A placa do lote mostra preço, nível exigido e "≈ X dias de renda".

**Fórmula** (R = Renda de Referência por dia, seção 9, no nível ⌈1,53 × n⌉, sem o piso do tipo; arredondado para 2 algarismos):

custo(n) = 0,27 × 1,11^(n−1) × R(⌈1,53 × n⌉)

| Compra n | Lote (ordem simulada) | Tipo | Nível mínimo | Custo (ouro) | Escritura | Limpeza (Ferreiro) | Dia (regular) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | A3 | Lavoura | 2 | 680 | Não | 0 h 24 | 0,3 |
| 2 | C2 | Galinheiro | 4 | 1.800 | Não | 0 h 28 | 0,5 |
| 3 | A4 | Lavoura | 5 | 3.000 | Não | 0 h 32 | 0,5 |
| 4 | A2 | Lavoura | 7 | 7.400 | Não | 0 h 36 | 0,9 |
| 5 | C1 | Celeiro | 8 | 12.000 | Não | 0 h 40 | 1,3 |
| 6 | A6 | Lavoura | 10 | 45.000 | Não | 0 h 44 | 1,8 |
| 7 | P1 | Pomar | 11 | 61.000 | Não | 0 h 48 | 2,3 |
| 8 | A7 | Lavoura | 13 | 120.000 | Não | 0 h 52 | 4,5 |
| 9 | A8 | Lavoura | 14 | 200.000 | Não | 0 h 56 | 5,5 |
| 10 | P2 | Pomar | 16 | 430.000 | Não | 1 h 00 | 8,3 |
| 11 | A5 | Lavoura | 17 | 590.000 | Não | 1 h 04 | 9,3 |
| 12 | A10 | Lavoura | 19 | 840.000 | Não | 1 h 08 | 11,3 |
| 13 | P3 | Pomar | 20 | 1.000.000 | Não | 1 h 12 | 12,5 |
| 14 | A11 | Lavoura | 22 | 1.800.000 | Não | 1 h 16 | 16,5 |
| 15 | A12 | Lavoura | 23 | 2.200.000 | Não | 1 h 20 | 17,8 |
| 16 | P4 | Pomar | 25 | 3.400.000 | Não | 1 h 24 | 20,8 |
| 17 | A13 | Lavoura | 27 | 5.300.000 | Não | 1 h 28 | 25,3 |
| 18 | A20 | Lavoura | 28 | 6.500.000 | Não | 1 h 32 | 27,8 |
| 19 | L | Lago | 30 | 9.700.000 | Não | 1 h 36 | 33,3 |
| 20 | P5 | Pomar | 31 | 13.000.000 | Não | 1 h 40 | 35,8 |
| 21 | A14 | Lavoura | 33 | 19.000.000 | Não | 1 h 44 | 41,3 |
| 22 | A15 | Lavoura | 34 | 21.000.000 | Não | 1 h 48 | 43,9 |
| 23 | P6 | Pomar | 36 | 30.000.000 | Não | 1 h 52 | 50,3 |
| 24 | A16 | Lavoura | 37 | 39.000.000 | Não | 1 h 56 | 53,3 |
| 25 | A17 | Lavoura | 39 | 53.000.000 | Não | 2 h 00 | 60,5 |
| 26 | A18 | Lavoura | 40 | 62.000.000 | Não | 2 h 04 | 64,3 |
| 27 | A19 | Lavoura | 42 | 77.000.000 | Não | 2 h 08 | 72,5 |
| 28 | A21 | Lavoura | 43 | 99.000.000 | Não | 2 h 12 | 77,3 |

O tipo de cada lote vem da posição no mapa. A ordem acima respeita a vizinhança a partir do A1; preço e nível dependem só de n. 🆕 Com o R remedido, o custo total dos 29 lotes é 313 mi (antes 185 mi), porque a renda do fim do jogo ficou maior; em dias de renda, é o mesmo ritmo. O regular faz 8 compras até o dia 7 e 19 até o dia 30. A ordem e os tipos estão em `config/lots.json` (`tools/balance/build-lots.ts`); os preços e os dias vêm do simulador (`npm run sim -- --calibrate --write`).

## 6. Cultivos e animais 🆕 (completa)

Um cultivo novo libera a cada nível, do 1 ao 49 (o nível 1 tem 2: Alface e Cenoura), 50 no lançamento. O melhor cultivo de cada nível rende cerca de 60 × 1,07^(nível−1) de ouro por hora por canteiro, já descontada a semente (1 árvore = 2 canteiros, então 4 árvores = 1 lote de 8 canteiros). Novos cultivos e animais entram depois só pela config (`config/crops.json` e `config/animals.json`).

- **Lavoura:** 1 colheita por plantio. Semente = 25% do valor da colheita.
- 🆕 **Raridade (seção 9):** a Barraca só vende sementes e mudas Comuns. Sementes e mudas raras caem na pesquisa da Lupa, em pacotes de missão e em eventos, e multiplicam o ouro e o XP da colheita por **um plantio** (lavoura: 1 colheita; recorrente: as 5; árvore: 6 colheitas, depois volta a Comum). No canteiro aparece uma estrelinha da cor da raridade; no inventário, a moldura da raridade.
- **Recorrente:** 5 colheitas por plantio (a 1ª em "Cresce", as outras a cada "Rebrota"). Semente = valor de 1 colheita. 🆕 O XP da tabela abaixo é por colheita: o número original era do plantio inteiro e foi dividido por 5 (ex.: Morango 190 por plantio = 38 por colheita). Lido como "por colheita", os recorrentes davam 5× mais XP por hora que os outros cultivos.
- **Pomar:** árvore permanente, só em lote de pomar (4 vagas por terraço); produz a cada "Rebrota" depois de crescer. Muda = 6 colheitas. 🆕 O jogador pode **derrubar uma árvore de graça** para plantar outra fruta; a nova muda é paga e cresce do zero. Sem isso, uma Maçã do nível 10 ocuparia para sempre a vaga de uma Jabuticaba (14× mais ouro por hora).
- **Trabalho:** cada plantio + colheita gasta 1 unidade de trabalho (🆕 0,5 para plantar e 0,5 para colher); colheita extra de recorrente ou de árvore gasta 0,5. 🆕 Isso vale para o Agricultor quando o jogador está fora; com o jogo aberto, o jogador planta e colhe por clique sem gastar trabalho. Culturas curtas rendem um pouco mais ouro por hora, mas gastam muito mais trabalho; as longas vencem em fazendas grandes e offline. Essa troca é o coração da escolha do que plantar. Com 30 lotes há 168 canteiros e 24 árvores (antes 136 e 20). 🆕 Um personagem faz **2,67 unidades de trabalho por hora** com ferramenta de Madeira (× material da ferramenta, × 60% fora da função), valor calibrado no simulador para bater as metas da seção 14. Ex.: no nível 1, o Agricultor sozinho dá conta de menos de 1 canteiro de Alface (10 min), mas de ~1 lote de cultivos de 4 a 8 h: online, cultivos curtos com clique; antes de sair, cultivos longos para o Agricultor.
- **Colheita Dourada:** chance pequena (cartas e habilidades) de a colheita valer 2,5×. Máximo 20% somando os bônus permanentes e 60% com cartas e evento (tetos da seção 11).
- Preço por unidade = preço base na Feira da Vila (expedição nível 1). Os operadores nos slots replantam sozinhos o último cultivo escolhido em cada canteiro, comprando semente automaticamente.

**Conferência automática** (`npm run balance:check`): ouro por hora de todos os cultivos entre −12% e +13% do alvo (curtas, até 2 h: +4% em média; longas, 6 h ou mais: −9%); sementes e mudas 100% dentro da regra; XP por hora de recorrentes e árvores igual ao da lavoura do mesmo nível (±3%).

| Cultivo | Nível | Tipo | Cresce | Rebrota | Unid./colheita | Preço/unid. | Semente ou muda | XP/colheita |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Alface | 1 | Lavoura | 10 min | — | 3 | 5 | 3,7 | 5,1 |
| Cenoura | 1 | Lavoura | 30 min | — | 3 | 14 | 10 | 15 |
| Batata | 2 | Lavoura | 1 h | — | 3 | 29 | 22 | 31 |
| Espinafre | 3 | Lavoura | 20 min | — | 3 | 11 | 8,1 | 11 |
| Morango | 4 | Recorrente | 1,5 h | 1 h | 2 | 51 | 100 | 38 |
| Tomate * | 5 | Recorrente | 2 h | 1,5 h | 2 | 78 | 160 | 58 |
| Cebola | 6 | Lavoura | 2 h | — | 3 | 74 | 55 | 75 |
| Milho | 7 | Lavoura | 3 h | — | 3 | 120 | 87 | 120 |
| Couve | 8 | Lavoura | 45 min | — | 3 | 33 | 25 | 31 |
| Repolho | 9 | Lavoura | 4 h | — | 3 | 170 | 130 | 170 |
| Maçã | 10 | Pomar | 12 h | 6 h | 4 | 330 | 7.900 | 530 |
| Pimentão | 11 | Recorrente | 3 h | 2 h | 2 | 160 | 320 | 102 |
| Alho | 12 | Lavoura | 1,5 h | — | 3 | 84 | 63 | 73 |
| Abóbora | 13 | Lavoura | 6 h | — | 3 | 340 | 250 | 310 |
| Beterraba * | 14 | Lavoura | 2,5 h | — | 3 | 160 | 120 | 130 |
| Laranja | 15 | Pomar | 14 h | 7 h | 4 | 540 | 13.000 | 780 |
| Mirtilo | 16 | Recorrente | 4 h | 2,5 h | 2 | 280 | 560 | 162 |
| Brócolis | 17 | Lavoura | 3 h | — | 3 | 230 | 170 | 180 |
| Pepino * | 18 | Recorrente | 2 h | 1,5 h | 2 | 190 | 380 | 102 |
| Batata-doce * | 19 | Lavoura | 5 h | — | 3 | 420 | 320 | 330 |
| Banana | 20 | Pomar | 16 h | 8 h | 4 | 870 | 21.000 | 1.100 |
| Melancia | 21 | Lavoura | 8 h | — | 3 | 760 | 570 | 580 |
| Mandioca * | 22 | Lavoura | 10 h | — | 3 | 1.000 | 750 | 760 |
| Uva | 23 | Recorrente | 6 h | 4 h | 2 | 690 | 1.400 | 340 |
| Couve-flor | 24 | Lavoura | 4 h | — | 3 | 480 | 360 | 330 |
| Pera | 25 | Pomar | 16 h | 8 h | 4 | 1.200 | 29.000 | 1.400 |
| Pimenta | 26 | Recorrente | 3 h | 2 h | 2 | 440 | 880 | 198 |
| Berinjela | 27 | Recorrente | 5 h | 3 h | 2 | 710 | 1.400 | 320 |
| Maçã verde | 28 | Pomar | 18 h | 8 h | 4 | 1.500 | 36.000 | 1.600 |
| Quiabo * | 29 | Recorrente | 2,5 h | 1,5 h | 2 | 420 | 840 | 174 |
| Abacaxi | 30 | Lavoura | 12 h | — | 3 | 2.000 | 1.500 | 1.300 |
| Limão | 31 | Pomar | 18 h | 9 h | 4 | 2.100 | 49.000 | 2.000 |
| Melão | 32 | Lavoura | 7 h | — | 3 | 1.400 | 1.100 | 820 |
| Maracujá * | 33 | Recorrente | 8 h | 5 h | 2 | 1.700 | 3.400 | 680 |
| Aipo | 34 | Lavoura | 2 h | — | 3 | 490 | 370 | 260 |
| Pêssego | 35 | Pomar | 20 h | 10 h | 4 | 3.000 | 72.000 | 2.700 |
| Amora | 36 | Recorrente | 5 h | 3 h | 2 | 1.300 | 2.600 | 480 |
| Gengibre | 37 | Lavoura | 9 h | — | 3 | 2.500 | 1.900 | 1.300 |
| Mamão * | 38 | Pomar | 20 h | 10 h | 4 | 3.700 | 88.000 | 3.100 |
| Aspargo | 39 | Recorrente | 10 h | 6 h | 2 | 3.100 | 6.200 | 1.080 |
| Manga | 40 | Pomar | 24 h | 12 h | 4 | 5.000 | 120.000 | 4.000 |
| Alho-poró | 41 | Lavoura | 3 h | — | 3 | 1.200 | 870 | 520 |
| Goiaba * | 42 | Pomar | 22 h | 11 h | 4 | 5.300 | 130.000 | 4.000 |
| Alcachofra | 43 | Lavoura | 8 h | — | 3 | 3.400 | 2.500 | 1.500 |
| Cereja | 44 | Pomar | 24 h | 12 h | 4 | 6.600 | 160.000 | 4.800 |
| Kiwi | 45 | Recorrente | 10 h | 6 h | 2 | 4.600 | 9.300 | 1.420 |
| Acerola * | 46 | Pomar | 20 h | 10 h | 4 | 6.300 | 150.000 | 4.300 |
| Figo | 47 | Pomar | 24 h | 12 h | 4 | 8.100 | 190.000 | 5.500 |
| Romã | 48 | Pomar | 24 h | 12 h | 4 | 8.700 | 210.000 | 5.700 |
| Jabuticaba * | 49 | Pomar | 24 h | 12 h | 4 | 9.300 | 220.000 | 6.000 |

\* arte ainda não existe (seção 4).

### Animais

Cada animal rende cerca de 3 canteiros (2,9 a 3,1, valor bruto). A Rancheira em campo coleta a 100%; outra classe, a 60%. 🆕 **Fase 4 (decisões do dono, 24/10):** a coleta é igual à lavoura: com o jogo aberto o clique coleta grátis e rende 100%; fora do jogo a equipe coleta na fila gastando 0,5 de trabalho (100% com a Rancheira em campo, 60% sem ela). O produto pronto espera a coleta. Cada vaga escolhe o seu animal (casas mistas). A ração é cobrada no começo de cada ciclo (ração/dia × duração do ciclo); sem ouro o animal fica com fome e volta sozinho quando entra ouro. Bônus de produção (habilidade, Gato, Lago) somam com teto de +60%; a raridade multiplica à parte. A ração (≈15% da produção) é descontada sozinha; sem ouro para ração, o animal para de produzir (nunca morre). Comprar um animal custa 10 dias de ração. Cada casa começa com 4 vagas e amplia para 8 e 12.

🆕 **Raridade do animal:** sorteada no servidor na hora da compra e fixa para sempre: Comum 75%, Incomum 18%, Raro 5%, Lendário 1,5%, Mítico 0,5%. Multiplica a produção por ciclo (×1 / ×1,2 / ×1,5 / ×2 / ×3); a ração não muda. Na média os animais produzem ×1,09. Tirar um animal da vaga não devolve ouro, para ninguém ficar comprando de novo até sair Mítico. O card do animal mostra um escudo na cor da raridade.

**Lago 🆕:** +10% na produção das aves do Galinheiro (Galinha, Pato, Ganso e Peru) e **+2 vagas no Galinheiro, só para aves** (4 → 6, 8 → 10, 12 → 14). Só com o +10% o Lago valia 0,37 de um lote de lavoura comprado no mesmo momento (0,20 se comprado por último); com as vagas passa a 0,89, sem passar do teto de produção animal (+60%).

| Animal | Nível | Casa | Produto | A cada | Preço do produto | Ração/dia | Compra | XP/coleta |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Galinha | 3 | Galinheiro | Ovo | 2 h | 410 | 740 | 7.400 | 59 |
| Coelho | 6 | Galinheiro | Pelo de coelho | 6 h | 1.500 | 910 | 9.100 | 200 |
| Vaca | 8 | Celeiro | Leite | 4 h | 1.200 | 1.000 | 10.000 | 150 |
| Pato | 11 | Galinheiro | Ovo de pata | 3 h | 1.100 | 1.300 | 13.000 | 130 |
| Ovelha | 14 | Celeiro | Lã | 8 h | 3.500 | 1.600 | 16.000 | 380 |
| Porco | 17 | Celeiro | Trufa | 6 h | 3.200 | 1.900 | 19.000 | 330 |
| Cabra | 21 | Celeiro | Leite de cabra | 5 h | 3.500 | 2.500 | 25.000 | 330 |
| Ganso | 25 | Galinheiro | Ovo de ganso | 6 h | 5.500 | 3.300 | 33.000 | 470 |
| Peru | 30 | Galinheiro | Pena de peru | 8 h | 10.000 | 4.600 | 46.000 | 770 |
| Alpaca | 35 | Celeiro | Lã de alpaca | 12 h | 22.000 | 6.500 | 65.000 | 1.400 |

| Ampliação | Galinheiro | Celeiro |
| --- | --- | --- |
| 8 vagas | nível 9 · 39.000 | nível 14 · 150.000 |
| 12 vagas | nível 15 · 400.000 | nível 20 · 960.000 |

As ampliações custam 0,8 R (8 vagas) e 1,6 R (12 vagas), sobre a Renda de Referência do nível exigido.

## 7. Personagens, energia, salário, inventário, habilidades e pets

O jogador começa com o Agricultor (o dono, sem salário) e libera os outros 5 por nível; depois paga a contratação e um salário diário. Só **3 personagens ficam nos Slots de Campo** ao mesmo tempo; os outros ficam nos 3 Slots de Banco (descanso). Os cards dos slots mostram o personagem parado com 2 quadros de ação (seção 4).

| Classe | Ferramenta | Função (100% de eficiência) | Libera no nível | Contratação (ouro) |
| --- | --- | --- | --- | --- |
| Agricultor | Enxada | Plantar e colher a lavoura | 1 (inicial) | grátis |
| Rancheira | Regador | Animais e pomar | 3 | 6.000 |
| Ferreiro | Martelo | Limpar lotes, ferramentas, consertar veículos | 6 | 20.000 |
| Comerciante | Balança | Barraca e vendas (mercado, quando existir) 🆕 | 10 | 150.000 |
| Gerente | Prancheta | Conduz expedições | 14 | 480.000 |
| Botânica | Lupa | Pesquisa e bônus de crescimento | 20 | 1.600.000 |

Fora da própria função, qualquer personagem trabalha a 60%. Contratação = 1,5 × Renda de Referência do nível de liberação.

🆕 **Fase 3 (decisões do dono, 23/10):** o trabalho de quem está em campo vai para uma fila única (lavoura e pomar): Agricultor e Rancheira a 100%, os outros a 60%. Antes das fases 4 e 5, as classes de apoio já têm função própria, sempre com o personagem num Slot de Campo ("por material" = Madeira 1 … Cristal 5):

| Classe | Função na fase 3 | Depois |
| --- | --- | --- |
| Comerciante | Venda automática na Barraca dos itens marcados no Silo; +1 ponto no preço da Barraca e −1% nas sementes por material da Balança (Barraca nunca passa de 80% somando habilidades) | lidera ou bonifica as expedições (fase 5) |
| Gerente | −5% no gasto de energia da equipe em campo, +2,5% por material acima da Madeira (Cristal −15%); paga sozinho o salário atrasado assim que entra ouro | ração e repetição de rotas (fases 4 e 5) |
| Botânica | 2% de chance por colheita (lavoura e pomar) de 1 Semente Rara do mesmo cultivo (Incomum 72%, Raro 20%, Lendário 6%, Mítico 2%; vale 1 plantio, ×1,2 / ×1,5 / ×2 / ×3 em colheita e XP; na árvore, as 6 próximas colheitas); +5% de XP nas colheitas; 10% de chance de devolver o ouro da semente | itens botânicos nas expedições (fase 5) |

- **Ferreiro contratado:** a limpeza dos lotes volta ao tempo da tabela (sem ele, o dobro). Conserto e melhoria das ferramentas de todos ficam na Forja.
- **Energia:** só gasta quando o personagem produz trabalho. Com 3 ou menos personagens, quem chega a 0 fica parado no slot descansando até 60. O servidor avança a fazenda em passos de 10 min (energia, rodízio, lanches, salário e venda automática).
- **Salário:** cobrado à meia-noite de Brasília até a fase 6 (depois, no fuso da conta). Sem ouro, o salário do dia vira dívida; com dívida o personagem fica Desmotivado (×0,5); com 3 dias devendo para de trabalhar. Paga-se no botão "Pagar salários" da Casa, ou sozinho com o Gerente em campo.
- **Lanches na Barraca:** Pão de Queijo 1%, Café 1,6% e Marmita 2,8% da Renda de Referência do nível da conta.
- **Habilidades:** os efeitos valem com o personagem em campo; nós de sistemas futuros (animais, expedições, mercado, missões, clima) ficam guardados e ligam na fase deles. A Mestria só abre com os dois nós do ramo cheios.

### Energia e rodízio

- Energia máxima 100. Trabalhando gasta 12,5 por hora (8 h de trabalho); descansando recupera 25 por hora (4 h). Oito horas de trabalho batem com o limite offline de 8 h.
- Com 4 ou mais personagens, liga o **rodízio automático** entre os Slots de Campo e de Banco: quem chega a 10% sai de campo e entra quem tem 60% ou mais, preferindo quem cobre a mesma função.
- Com 3 ou menos, o personagem sem energia fica parado no slot até recuperar.
- Na simulação a energia pesa muito no começo (1 a 3 personagens) e pouco depois do 5º: contratar é o que resolve.

### Salário

Salário diário de cada contratado = 2% da Renda de Referência do **nível da conta** × (1 + 1% × nível do personagem), cobrado às 00:00. Na simulação os salários consomem 12% da renda do jogador regular (casual 17%, dedicado 11%) 🆕. Sem ouro, o personagem fica **Desmotivado** (−50% de eficiência) até a dívida ser paga; depois de 3 dias devendo, para de trabalhar. Ele nunca vai embora.

| Nível da conta | 5 | 10 | 15 | 20 | 25 | 30 | 35 | 40 | 45 | 50 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Salário base/dia (ouro) | 180 | 2.000 | 9.000 | 22.000 | 52.000 | 110.000 | 200.000 | 340.000 | 540.000 | 640.000 |

### Nível do personagem

O personagem ganha XP por hora trabalhada: o próximo nível exige (10 + 1,5 × nível atual) horas, até o nível 30. Cada nível dá 1 ponto de habilidade (29 no total).

### Inventário: 1 ferramenta + 3 espaços

Abre pela Casa 🆕 (junto com o Silo e o painel de operadores).

- **Ferramenta** da classe, em 5 materiais. Melhora a capacidade de trabalho; quem melhora é o Ferreiro, na Forja, uma por personagem.
- 🆕 **Durabilidade da ferramenta (0 a 100):** perde 2,5 por hora de trabalho; abaixo de 30% a ferramenta trabalha a 50% da capacidade até ser consertada na Forja. O conserto custa 10% do preço do material (Madeira: 100 de ouro). Com 3 personagens em campo, os consertos custam de 3% (Cobre) a 7,5% (Cristal) da Renda de Referência por dia. Números em `config/tools_and_items.json`.
- **Vestimenta** (chapéu, botas ou luvas): energia máxima, menos gasto de energia ou mais capacidade.
- **Amuleto:** efeito especial (ex.: Ferradura +2 pontos de sucesso se conduzir; Trevo +2% colheita dupla; Relógio de Bolso +8% XP do personagem; Pena +3% produção animal).
- **Lanche:** consumível, até 5 unidades, usado sozinho quando a energia cai abaixo de 15% (Pão de Queijo +25, Café +40, Marmita +70). Vem de expedições ou é comprado na **Barraca** 🆕.

Vestimentas e amuletos caem só em expedições, em 5 raridades, nas cores da seção 4 (Comum ×1, Incomum ×1,3, Raro ×1,6, Lendário ×2, Mítico ×2,5 no efeito). Três iguais viram 1 da raridade acima. Itens não vão para o mercado.

| Material | Nível | Capacidade de trabalho | Custo por personagem (ouro) |
| --- | --- | --- | --- |
| Madeira | 1 | ×1,0 | inicial |
| Cobre | 8 | ×1,4 | 13.000 |
| Ferro | 18 | ×1,8 | 230.000 |
| Ouro | 30 | ×2,3 | 1.600.000 |
| Cristal | 42 | ×3,0 | 7.300.000 |

### Árvores de habilidade

Cada classe tem uma árvore única com 3 ramos. Cada ramo = 2 nós de 5 pontos + 1 Mestria de 3 pontos (13 pontos). Com 29 pontos o jogador completa 2 ramos e sobra pouco: é obrigado a escolher. Reset grátis 1 vez por semana; outro reset custa 50% da Renda de Referência. Orçamento: uma árvore completa ≈ +10% de renda (validar no simulador).

🆕 O ramo **Mercado** do Comerciante só tem efeito a partir da fase 8 e fica visível com o aviso "disponível quando o mercado abrir". Como os pontos completam só 2 dos 3 ramos, o Comerciante não perde força até lá.

| Classe | Ramo | Nó A (por ponto) | Nó B (por ponto) | Mestria |
| --- | --- | --- | --- | --- |
| Agricultor | Cultivo | +1% crescimento da lavoura | +6% capacidade de trabalho | +5% colheita dupla na lavoura |
| Agricultor | Resistência | +5 energia máxima | −4% gasto de energia | 1×/dia, ao zerar recupera 40 de energia |
| Agricultor | Economia | −3% custo de sementes | +1% Colheita Dourada | +15% XP de colheita |
| Rancheira | Criação | +3% produção animal | −5% custo de ração | 6% de produto duplo nos animais |
| Rancheira | Pomar | +2% velocidade do pomar | +6% capacidade de trabalho | +1 fruta em 20% das colheitas do pomar |
| Rancheira | Resistência | +5 energia máxima | −4% gasto de energia | Descanso 20% mais rápido |
| Ferreiro | Obras | −6% tempo de limpeza | +10% efeito da ajuda de vizinhos | −10% custo de ampliações |
| Ferreiro | Forja | −4% custo de ferramentas | +1% capacidade de todos em campo | Ferramentas +5% de efeito |
| Ferreiro | Oficina | −6% desgaste dos veículos | +1 ponto de sucesso nas expedições | −10% duração das expedições |
| Comerciante | Barraca | +2 pontos no preço da barraca (70% → 80%) | −3% em sementes, ração e lanches | 1 venda por dia na barraca paga 1,5× |
| Comerciante | Mercado (fase 8) 🆕 | −0,6 ponto na taxa (8% → 5%) | +1 anúncio | Seus anúncios aparecem primeiro |
| Comerciante | Negócios | +1% ouro em vendas | +5% ouro das missões | Vê a demanda das rotas de amanhã |
| Gerente | Rota | +1 ponto de sucesso quando conduz | −3% duração quando conduz | Conduz 2 veículos na mesma rota |
| Gerente | Carga | −5% perda na falha | +5% capacidade do veículo que conduz | −30% no preço do seguro |
| Gerente | Faro | +6% chance de item | +4% chance de Escritura | +5 pontos de chance de crítico |
| Botânica | Pesquisa | +1% crescimento de lavoura e pomar (em campo) | −5% tempo inicial das árvores | Libera 1 cultivo escolhido 3 níveis antes |
| Botânica | Qualidade | +1% Colheita Dourada | +2% produção das recorrentes | +10% XP da conta (em campo) |
| Botânica | Clima | +8% efeito do clima | +1 h de previsão do clima (até 6 h) | Eventos noturnos +15% para você |

### Pets

🆕 **Pets v3 (decisão do dono, 01/11):** os 3 pets **chegam sozinhos** (Cachorro no nível 5, Gato no 12, Papagaio no 20), sem adoção, sem custo e sem vínculo com personagem, e **todos valem ao mesmo tempo**. Eles andam no pátio de pedra na frente da Casa. **Achado:** de tempos em tempos cada pet traz algo (um balão aparece em cima dele); o clique no pet (ou "Pegar achado" na guia Pets) recolhe e a contagem recomeça. Só 1 achado espera por pet (a equipe não recolhe). Cachorro: baú a cada 6 h com 0,8% da renda de referência do dia (R) e 5% de chance de carta (+2 pontos por nível do pet). Gato: soneca a cada 4 h, +15 de energia para toda a equipe. Papagaio: moedas a cada 3 h com 0,4% de R. **Carinho:** 1 por dia em cada pet, +1 de afinidade; níveis 2, 3, 4 e 5 com 4, 10, 18 e 30. O efeito fixo e o achado crescem de 40% (nível 1) a 100% (nível 5); no nível 5, +1 ponto na chance de Semente Rara. Números em `config/characters.json` → pets.

| Pet | Efeito no nível 5 |
| --- | --- |
| Cachorro | +4 pontos de sucesso nas expedições e 10% de chance de recuperar a carga perdida |
| Gato | +40% recuperação de energia e +10% produção animal |
| Papagaio | +4% ouro em vendas e aviso do evento noturno 30 min antes |

## 8. Expedições e veículos

Vender é mandar a produção numa expedição: quanto mais longe, maior o preço e maior o risco, mas **a carga nunca se perde toda** e em 20 viagens nenhuma rota rendeu menos que a barraca segura na simulação.

| Rota | Nível | Duração base | Preço (× Feira) | Chance de sucesso | Perda se falhar | Chance de item | Seguro (% da carga) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Feira da Vila | 1 | 30 min | ×1,00 | 97% | 10% a 25% | 4% | não oferecido |
| Cidade Vizinha | 6 | 1 h 30 | ×1,20 | 92% | 15% a 35% | 8% | 2,4% |
| Capital | 16 | 3 h | ×1,45 | 85% | 20% a 45% | 14% | 6,9% |
| Porto | 26 | 5 h | ×1,75 | 76% | 25% a 55% | 22% | 16,9% |
| Exportação | 36 | 8 h | ×2,10 | 66% | 30% a 60% | 32% | 33% |

| Veículo | Nível | Capacidade (unid.) | Duração | Segurança | Rotas | Custo (ouro) |
| --- | --- | --- | --- | --- | --- | --- |
| Carroça | 1 | 60 | ×1,30 | +0 | até Cidade Vizinha | inicial |
| Carro | 6 | 120 | ×0,80 | +3 pontos | até Capital | 33.000 |
| Caminhão pequeno (picape) | 16 | 250 | ×0,90 | +5 pontos | até Porto | 620.000 |
| Caminhão grande | 30 | 500 | ×1,00 | +8 pontos | todas | 5.600.000 |

### Garagem 🆕

- Fica à esquerda do lote A5, na estradinha de terra (zona `garagem_expedicao` no mapConfig).
- No mapa aparece **o veículo que está em casa**: o ativo; se ele estiver viajando, outro que ficou. Na tela de expedição os veículos em viagem aparecem apagados, com a hora da volta.
- Clicar abre a **Garagem**: os 4 veículos lado a lado, todos com animação de parado, na raridade atual; os ainda não comprados aparecem em silhueta com nível e preço. Dali o jogador escolhe o veículo e abre a Expedição (rota, carga, seguro e minigame).
- Com o veículo ativo em viagem, a vaga fica vazia com um contador até a volta.

### Como uma expedição se resolve

1. O jogador escolhe veículo, rota, o que levar e se paga seguro. A **Barraca** continua sempre disponível: venda na hora, sem risco, a 70% do preço da Feira.
2. O servidor sorteia ao enviar: **crítico** (5%: paga +25% e sorteia item 2×), **sucesso** ou **falha** (perde uma parte aleatória dentro da faixa da rota; o resto volta ao Silo).
3. Chance final = base + segurança do veículo (× raridade) + minigame de partida + Gerente conduzindo (+8 pontos e −10% de duração) + cartas, habilidades e pet − clima (chuva −4, carroça na chuva −8, neblina −4, noite −2). Teto de 95%.
4. **Proteção contra azar:** depois de 2 falhas seguidas, a próxima expedição ganha +25 pontos.
5. **Seguro:** se falhar, devolve em ouro a perda acima de 10%, a preço da rota. O preço foi calculado para nunca dar lucro na média: ele troca um pouco de ganho por segurança.
6. **Repetição automática:** o veículo refaz a mesma rota até 2 vezes enquanto o jogador está fora, herdando o resultado do minigame da partida.
7. Cada viagem gasta 4% da durabilidade do veículo; o Ferreiro conserta na Forja. Com menos de 30%, −5 pontos de sucesso.
8. Itens para personagens e Escrituras só caem em expedições (Escritura: Capital 3%, Porto 5%, Exportação 8% por viagem).

### Raridade dos veículos

Todo veículo é comprado Comum e sobe de raridade na **Forja** (reforma), pagando ouro + 1 Kit de Reforma da raridade nova. A raridade muda a aparência (seção 4) e 🆕 **multiplica capacidade, velocidade e segurança** pelo multiplicador global (seção 9). O veículo fica parado durante a reforma.

| Raridade | Nível mínimo | Custo em ouro | Tempo na oficina | Multiplicador 🆕 | Exemplo: Caminhão grande na Exportação |
| --- | --- | --- | --- | --- | --- |
| Comum | 1 | (compra) | — | ×1 | 500 unid., 8 h, +8 pontos |
| Incomum | 8 | 30% do preço do veículo | 2 h | ×1,2 | 600 unid., 6 h 40, +9,6 |
| Raro | 16 | 60% | 4 h | ×1,5 | 750 unid., 5 h 20, +12 |
| Lendário | 26 | 120% | 8 h | ×2 | 1.000 unid., 4 h, +16 |
| Mítico | 36 | 240% | 12 h | ×3 | 1.500 unid., 2 h 40, +24 |

Capacidade × multiplicador; duração ÷ multiplicador; pontos de segurança do veículo × multiplicador (a Carroça tem 0 pontos, então ganha só capacidade e velocidade). O teto de 95% de sucesso continua. O desgaste por viagem é o mesmo em todas as raridades.

A Carroça usa 33.000 como preço de referência. Exemplo no Caminhão grande: 1,7 mi, 3,4 mi, 6,7 mi e 13,4 mi.

**Kits de Reforma** caem só em expedições, sem venda no mercado; 3 kits iguais viram 1 da raridade acima.

| Rota | Chance de kit por viagem | Incomum | Raro | Lendário | Mítico |
| --- | --- | --- | --- | --- | --- |
| Feira da Vila | 2% | 100% | — | — | — |
| Cidade Vizinha | 4% | 80% | 20% | — | — |
| Capital | 6% | 55% | 35% | 10% | — |
| Porto | 8% | 40% | 38% | 18% | 4% |
| Exportação | 10% | 30% | 37% | 25% | 8% |

🆕 Com a regra nova, a raridade pesa mais: o Caminhão Mítico com Gerente bate o teto de 95% até na Exportação e faz a viagem em 2 h 40. O efeito na renda é medido pelo simulador da fase 0 (seção 14); como os preços dos lotes acompanham a Renda de Referência, o ritmo do mapa se mantém.

### Minigame de partida

Para lançar uma expedição, o jogador repete uma sequência de setas (↑ ↓ ← →) antes do tempo acabar. Se não terminar, a expedição sai mesmo assim, com chance de sucesso menor.

| Rota | Setas | Tempo |
| --- | --- | --- |
| Feira da Vila | 4 | 6 s |
| Cidade Vizinha | 5 | 6 s |
| Capital | 6 | 6,5 s |
| Porto | 7 | 7 s |
| Exportação | 8 | 7,5 s |

| Resultado | Quando | Efeito na chance |
| --- | --- | --- |
| Perfeita | Sem erro e com 30% do tempo sobrando | +3 pontos |
| Concluída | Terminou no tempo | sem efeito |
| Incompleta | Acabou o tempo com metade ou mais feita | −5 pontos |
| Falhou | Acabou o tempo com menos da metade | −10 pontos |

- Controles: setas ou WASD no teclado; no celular, 4 botões grandes na tela ou deslizar o dedo.
- Seta errada: a tela treme e o jogador perde 0,5 s; a sequência não volta ao início.
- Gerente conduzindo dá +1 s. Enviar vários veículos juntos (comboio) = 1 minigame só, com +2 setas e +1,5 s por veículo extra; o resultado vale para todos.
- Repetições automáticas herdam o resultado. Fechar o jogo no meio conta como Falhou.
- Opção de acessibilidade **Modo calmo**: +50% de tempo, sem o bônus de Perfeita.
- Efeito medido no valor da viagem (Porto e Exportação com bons veículos): Perfeita +2% a +3%; Incompleta −4%; Falhou −7% a −9%. Errar custa mais do que acertar rende, o que dá motivo para jogar com atenção sem virar punição pesada.
- **Antitrapaça:** o servidor sorteia as setas, envia só na hora de começar e marca o horário; o cliente devolve cada tecla com o instante; o servidor confere o tempo total (com 400 ms de tolerância de rede) e o intervalo entre teclas. Intervalos abaixo de 90 ms ou sempre iguais = robô: a partida vale só como Concluída e gera alerta.

### Decisões da fase 5 🆕 (24/10/2026)

- **Receber com clique:** o veículo volta e espera na Garagem até o jogador clicar em Receber; só então entram o ouro, a devolução do seguro, a carga que voltou e os achados (com o relatório narrado).
- **Repetição guardada:** com "Repetir até 2×", o veículo sai de novo sozinho na volta, com os mesmos produtos da viagem (até a capacidade, com o que houver no Silo; sem nada, não repete). Tudo fica guardado até o Receber. Seguro só se houver ouro na hora.
- **Demanda do dia igual para todos:** sorteada à meia-noite de Brasília entre todos os produtos do jogo (3 por rota). A Mestria Negócios do Comerciante mostra a de amanhã.
- **Comboio:** 1 minigame só para todos os veículos; a carga enche os veículos na ordem escolhida; o Gerente conduz o primeiro (2 com a Mestria Rota).
- **Sorteio na volta:** a chance é fixada na saída (minigame, veículo, Gerente, garantia contra azar); o resultado é sorteado no servidor quando o veículo volta.
- **Números que o GDD não fixava** (config `expeditions.json`): conserto = 10% do preço do veículo de 0 a 100%; raridade dos itens = tabela de Kits da rota.

### Melhorias da mecânica (já incluídas acima ou na fase 5)

- Resultado em faixas em vez de "deu certo/deu errado".
- Quadro de demanda do dia: cada rota paga +20% por 3 produtos sorteados à meia-noite, o que dá motivo para escolher o que plantar e para onde mandar.
- Relatório narrado da viagem ("A estrada alagou perto da serra e 30 caixas de tomate estragaram").
- O Gerente pode conduzir, mas ocupa o Slot de Campo dele até voltar: troca entre produzir e vender melhor.

Simulação de 200 mil viagens por rota (carga que volta revendida a 95% da Feira): sem seguro, o pior resultado cai abaixo da barraca a partir da Capital; com seguro, nenhuma rota fica abaixo de 0,89×. A média sempre sobe com a distância, então o risco é escolha, não armadilha.

## 9. Economia, níveis, mercado e visitas

Ouro é a moeda única; o jogador começa com 2.000. A conta vai do nível 1 ao 50, e o jogador regular chega ao nível 30 no dia 33 e ao 50 no dia 113.

- **XP da conta:** colheitas e coletas (XP das tabelas da seção 6), expedições (+15% do XP de produção) e missões.
- **Renda de Referência (R):** renda diária média de um jogador regular em cada nível, medida na simulação. Custos e salários são calculados sobre ela, então tudo acompanha a economia. Fica em `config/levels.json`. 🆕 Os valores abaixo foram remedidos pelo simulador com 30 lotes e plantio e colheita por clique (`config/levels.json` versão 3); preços de lote, contratação, salários e resets se ajustaram sozinhos. 🆕 **Curva de XP (teste da fase 2):** os níveis 1 a 4 pedem pouco (40, 50, 65 e 90 XP: o nível 2 sai com 1 rodada de Alface no A1, em ~10 min, e o nível 5 em ~1 h jogando); o resto é a tabela do dono multiplicada por uma escala por faixa (níveis 5–9, 10–29 e 30–49), calibrada para o regular chegar ao nível 10 no 1º dia, ao 30 no dia 33 e ao 50 no dia 113. Os níveis que passam em poucas horas não dão medida de R: o R deles é interpolado.

| Nível | XP para o próximo | R (ouro/dia) | | Nível | XP para o próximo | R (ouro/dia) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 40 | 1.900 | | 26 | 883.080 | 3.200.000 |
| 2 | 50 | 2.500 | | 27 | 1.016.880 | 3.700.000 |
| 3 | 65 | 4.000 | | 28 | 1.190.820 | 4.100.000 |
| 4 | 90 | 6.000 | | 29 | 1.338.000 | 4.500.000 |
| 5 | 900 | 8.900 | | 30 | 1.338.000 | 5.500.000 |
| 6 | 1.320 | 13.000 | | 31 | 1.444.300 | 6.600.000 |
| 7 | 2.110 | 20.000 | | 32 | 1.666.500 | 7.700.000 |
| 8 | 3.250 | 30.000 | | 33 | 1.777.600 | 8.500.000 |
| 9 | 5.480 | 60.000 | | 34 | 1.999.800 | 8.800.000 |
| 10 | 20.070 | 99.000 | | 35 | 2.333.100 | 9.900.000 |
| 11 | 33.450 | 120.000 | | 36 | 2.666.400 | 11.000.000 |
| 12 | 48.170 | 140.000 | | 37 | 2.999.700 | 13.000.000 |
| 13 | 69.580 | 210.000 | | 38 | 3.444.100 | 14.000.000 |
| 14 | 88.310 | 320.000 | | 39 | 3.888.500 | 16.000.000 |
| 15 | 113.730 | 450.000 | | 40 | 4.332.900 | 17.000.000 |
| 16 | 147.180 | 620.000 | | 41 | 4.777.300 | 17.000.000 |
| 17 | 173.940 | 770.000 | | 42 | 5.221.700 | 19.000.000 |
| 18 | 214.080 | 890.000 | | 43 | 5.888.300 | 22.000.000 |
| 19 | 267.600 | 990.000 | | 44 | 6.443.800 | 25.000.000 |
| 20 | 321.120 | 1.100.000 | | 45 | 7.110.400 | 27.000.000 |
| 21 | 374.640 | 1.400.000 | | 46 | 7.665.900 | 28.000.000 |
| 22 | 441.540 | 1.700.000 | | 47 | 8.110.300 | 29.000.000 |
| 23 | 535.200 | 1.900.000 | | 48 | 8.554.700 | 30.000.000 |
| 24 | 642.240 | 2.200.000 | | 49 | 8.776.900 | 31.000.000 |
| 25 | 762.660 | 2.600.000 | | 50 | — | 32.000.000 |

### Raridade global 🆕

As 5 raridades das cartas valem também para sementes e mudas, animais e veículos. A **linha base é o Comum**: a progressão de 77 dias e a fórmula 60 × 1,07^(nível−1) supõem tudo Comum, e o resto entra como bônus medido no simulador.

| Raridade | Cor | Multiplicador (ouro, produção, atributos) |
| --- | --- | --- |
| Comum | #9E9E9E | ×1 |
| Incomum | #4CAF50 | ×1,2 |
| Raro | #2F7BE5 | ×1,5 |
| Lendário | #F2C230 | ×2 |
| Mítico | #E5383B | ×3 |

| Onde | Como se consegue | O que multiplica | Quanto dura |
| --- | --- | --- | --- |
| Sementes e mudas | Barraca vende só Comum; raras caem na Lupa, em pacotes e eventos (chances a definir) | ouro e XP da colheita | 1 plantio (árvore: 6 colheitas) |
| Animais | sorteada na compra: 75% / 18% / 5% / 1,5% / 0,5% | produção por ciclo (ração igual) | para sempre |
| Veículos | reforma na Forja com ouro + Kit (seção 8) | capacidade, velocidade e pontos de segurança | para sempre |

Roupas e amuletos continuam com a tabela própria (×1 / ×1,3 / ×1,6 / ×2 / ×2,5, seção 7) e as ferramentas com os 5 materiais. O multiplicador de raridade é aplicado antes dos bônus percentuais e não conta para os tetos da seção 11. Tudo em `config/rarity.json`.

### Para onde vai o ouro

🆕 No simulador, até completar o mapa o regular gasta cerca de 95% do ouro ganho: terreno 57%, salários 11%, ferramentas 10%, sementes 6%, consertos de ferramenta 5% e o resto em veículos, reformas, animais, ração e ampliações (casual: terreno 51%, salários 15%). Depois do mapa completo sobra ouro. Por isso, antes da fase de mercado, crie **drenos de fim de jogo** que absorvam pelo menos 80% da renda: decorações e reformas cosméticas pagas em ouro (preço atrelado a R), Encomendas da Vila (metas coletivas em que todos doam produção e ouro, prêmio cosmético e título) e Estrelas da Vila (o XP depois do nível 50 vira estrelas para cosméticos).

### Mercado entre jogadores 🆕 (decidido em 29/10: produtos e cartas)

Decidido antes da fase 8: o mercado negocia produtos de cultivos e animais e cartas, com as regras abaixo. Drenos de fim de jogo da fase 8: Encomendas da Vila e Estrelas da Vila (decorações ficam para depois).

- Libera no nível 12, com conta de 3 dias ou mais.
- Produtos de cultivos e animais, e cartas (regras próprias na seção 11). Itens, Escrituras, Kits de Reforma e ferramentas nunca são negociáveis.
- Preço por unidade entre 70% e 200% do preço de referência (mediana dos últimos 7 dias, travada entre 70% e 200% do preço da Feira).
- Taxa de 8% sobre a venda (Comerciante reduz até 5%) + 1% para anunciar, não devolvido. As duas taxas destroem ouro.
- Até 10 anúncios ativos (Comerciante: +5), válidos por 24 h; o que não vender volta ao Silo.
- Limite antitransferência: o valor negociado entre as mesmas 2 contas não passa de 1 × R (do nível da conta menor) por semana.
- Lista de anúncios atualizada ao vivo (Realtime). Toda compra em transação travada, registrada no ledger.

### Visitas

- Visitar amigos (pedido aceito), uma fazenda aleatória ou as fazendas do ranking semanal.
- Na visita: **Ajudar** (+10% de crescimento por 1 h em 1 lote do dono, ou −10% no tempo de limpeza), **Curtir** e deixar um recado de **emojis pré-definidos**. Sem chat livre (seção 15).
- Até 10 ajudas dadas e 10 recebidas por dia. Quem ajuda ganha XP igual a 10 min da própria produção.
- Sem presentes de ouro ou itens entre jogadores: o mercado, quando existir, é o único canal de troca.

### Decisões da fase 8a 🆕 (29/10/2026)
- Busca de amigos pelo começo do apelido (3 letras ou mais); pedido cruzado vira amizade na hora; até 50 amigos.
- Ajudar: lavoura ou pomar com algo crescendo ganha +10% de crescimento por 1 h; lote em limpeza perde 10% do tempo que falta. 1 ajuda por lote por hora. O Ferreiro em campo na fazenda ajudada soma +10% por ponto de Obras B no efeito.
- A visita mostra a fazenda do dono no horário e clima dele, sem ouro, Silo, inventário, cartas e missões.
- Curtir 1 vez por dia por fazenda; recado com até 3 dos 12 emojis da lista, 1 por dia por fazenda e 20 por dia no total.
- Bloqueio nos dois sentidos e denúncia com motivo da lista (o painel mostra; a análise entra na fase 9).

### Decisões da fase 8b 🆕 (29/10/2026)
- **Ranking semanal adiado** pelo dono; entra numa parte futura.
- **Encomenda da Vila** (semanal, segunda 00:00 UTC): 3 pedidos (um cultivo de cada faixa de nível 1–12, 13–30, 31–50) valem 1,5×; qualquer outro produto do Silo (preço da Feira) e ouro também contam. Tudo o que é doado some do jogo. Pontos = horas da renda de referência do próprio nível. Meta = 8 pontos por jogador ativo na semana (mínimo 16). Prêmio: meta batida e 2+ pontos = 1 carta e o título "Ajudante da Vila"; top 10% dos que passaram do mínimo = +1 carta e "Herói da Vila" (mesmo sem a meta). O título vale por uma semana.
- **Estrelas da Vila**: depois do nível 50, cada 10% do XP do nível 49 vira 1 Estrela. Pacote = 5 Estrelas + 1 dia de renda (2 por semana, conta para a garantia); semente Incomum/Rara/Lendária = 1/2/4 Estrelas + 0,1/0,2/0,4 dia de renda (5 por semana). Mítico não se compra.

### Reformulação v3 🆕 (01/11/2026) — expedição sem minigame
- **Fim do minigame de setas** (jogo idle): a expedição parte direto e vale como "Concluída" (0 pontos de sucesso). O servidor ainda aceita o minigame antigo de quem estiver com a tela aberta.
- **Tela nova:** mapa de pergaminho com os destinos (Feira, Cidade, Capital, Porto, Exportação) ligados por uma estrada pontilhada; clique no ícone escolhe; o mouse mostra duração, preço, risco, achados e a demanda do dia. Veículos em cartões que ligam/desligam (comboio). Carga com − / + (segurar acelera) e MÁX, barra "Carga: x/y" em cima (verde, amarela cheia, vermelha passando). Resumo: valor no destino, chance, volta, seguro. Botão "Iniciar Expedição": a tela some devagar e o veículo sai sozinho.
- **5 veículos** (5 artes de 5 quadros e as 5 raridades da carta de Veículo): Carroça (nível 1), Compacto (6), Off-Road (16), **4x4** (23; 350 de carga, até o Porto, +6 pontos, duração ×0,85) e Caminhão (30), todos liberam sozinhos no nível. R recalibrado.
- **No mapa** (ajuste do dono): o veículo sai da frente da Garagem por um trecho curto de estrada de terra, sem passar pelos canteiros, e some rápido (1,3 s); na volta aparece ali e estaciona. Veículos 18% menores; motor balança 1 px e solta fumaça; poeira nas rodas de trás. Na volta fazem o caminho ao contrário e, ao estacionar, moedas saltam em arco.

### Reformulação v3 🆕 (01/11/2026) — Árvore de Passivas
- Sai da Casa e ganha botão próprio no topo (📖 Grimório, com pontinho quando há pontos livres). Modal grande com fundo estrelado: nós em losango ligados por linhas a partir da Fazenda; só ícones, tooltip no mouse (nome, nível, efeito atual e o próximo). Bloqueado = cinza e linha pontilhada; disponível = pulsa e linha acesa; comprado = borda dourada (no máximo, com faíscas). Ao comprar: linha se enche de luz, o nó treme e toca um "pling" (som gerado pelo navegador, com botão de silenciar).
- 1 ponto por nível (49 no 50). 3 caminhos × (4 passivas de até 5 pontos + Ultimate de 5 pontos) = 25 por caminho. A abre B e C (1 ponto); B ou C com 3 abre D; Ultimate pede D e 15 pontos no caminho. 1 reset grátis por semana.
- **Natureza:** Mão Verde (+1% de chance de a semente nascer pronta) · Carinho Animal (+2% produção animal, −4% ração) · Mestre Pescador (+3% de chance de peixe Lendário, ×2) · Terra Fértil (+2% crescimento) · ★ Mutação Genética (10% das colheitas de lavoura, pomar e animais em dobro).
- **Comércio:** Lábia de Mercador (+1 ponto no preço da Barraca, até 75%) · Logística Leve (−5% desgaste dos veículos) · Manutenção Eficiente (−5% consertos, −3% desgaste das ferramentas) · Rotas Seguras (+1 ponto de sucesso) · ★ Contrabando (+25% de carga).
- **Resistência:** Café Forte (+10% no 1º lanche do dia) · Sinergia de Equipe (−3% de energia com os 3 Slots de Campo ocupados) · Fôlego de Ferro (−6% de gasto abaixo de 30% de energia) · Folha de Pagamento (−3% salários) · ★ Segundo Fôlego (1×/dia, ao zerar, volta com 30%).
- As passivas antigas (Eficiência, Energia, Descanso, Lanches, Limpeza, Aves, Comércio) saíram; os pontos voltaram. O simulador continua estimando até +15% da renda com 49 pontos.

### Reformulação v3 🆕 (01/11/2026) — ferramentas viram cartas
- As 6 cartas de ferramenta (Enxada, Forcado, Martelo, Balança, Prancheta, Lupa) substituem a raridade das ferramentas: cada personagem tem 1 ferramenta só, mostrada com a arte da carta dela, que **sobe de nível sozinha** com o nível da fazenda (nível 1 → 8 → 18 → 30 → 42, ×1 a ×3 de trabalho, como os antigos materiais). A Forja não vende mais melhoria; desgaste (2,5 por hora) e conserto com ouro continuam.
- **Vara de Pescar** (ferramenta do Lago): vem com o Lago, gasta 2,5 por ciclo recolhido (rede cheia = 10), conserta no painel do Lago pelo preço do conserto da ferramenta do nível; abaixo de 30 a pesca rende a metade. Nó Ferramentas, nó Consertos e a carta Martelo valem para ela.
- **Limpeza:** sem Ferreiro em campo 60 + 12 min por compra (1h12 a 6h36); com o Ferreiro em campo 3× mais rápida (24 min a 2h12). R recalibrado.

### 🆕 (04/11/2026, pedido do dono) — Lago igual ao Galinheiro e Pescador
- **Lago = casa de peixes** (`config/animals.json` → `houses.lago`): substitui a rede de 2 h. Começa com **4 vagas**, amplia para **8** (nível 20, 450.000) e **12** (nível 30, 2.200.000). Em cada vaga o jogador escolhe o peixe entre os liberados pelo nível; a **raridade é sorteada na compra** (mesmas chances dos animais). Cada peixe produz sozinho a cada 2 h, come ração (≈15%) e custa 10 dias de ração, como os animais: **Tilápia** nv 11 · **Truta Arco-Íris** nv 20 · **Bagre do Rio** nv 30 · **Carpa Koi** nv 40 · **Esturjão** nv 45 (cada um ≈ 3 canteiros do seu nível). O clique coleta a 100%; fora do jogo a equipe coleta pela fila.
- **Pescador** (novo personagem, nível 30): especialista do Lago. Com ele em campo a equipe coleta o Lago a 100% (sem ele, 60%), como a Rancheira no Galinheiro e no Celeiro. A **Vara de Pescar** passa a ser a ferramenta dele (sobe de nível sozinha, gasta e conserta como as outras). A carta **Pesca** soma no peixe; o Rebanho não. O Mestre Pescador (árvore da conta) dá a chance de peixe em dobro.
- **Slots de Campo: 4** (eram 3); Banco continua com 3. R recalibrado.

### Reformulação v3 🆕 (01/11/2026) — parte R3 (pesca e árvore da conta) — *a rede de pesca abaixo foi trocada pelo Lago com vagas em 04/11*
- **Pesca** (`config/fishing.json`): o Lago comprado pesca sozinho em ciclos de **2 h**; a rede guarda até **4 ciclos (8 h)** e, cheia, para. Clique no Lago/píer recolhe (ícone do peixe com "n/4" no píer). Fora do jogo a equipe recolhe a rede cheia com **60%** (gasta o trabalho de uma colheita).
- Valor de cada ciclo = **8% da renda do nível (R) ÷ 12**; vem na espécie mais alta liberada (Tilápia nv 1 · 17, Truta nv 10 · 390, Bagre nv 20 · 2.700, Koi nv 30 · 11.000, Esturjão nv 40 · 28.000 de ouro cada). XP: 0,3% do XP do nível por ciclo. Peixe vai para o Silo (Barraca ou expedição).
- **Vara de Pescar** (+6% a +20%) multiplica o valor da pesca. O Lago continua dando +2 vagas de ave; o +10% das aves virou o nó Aves.
- **Árvore de habilidades da conta** (`characters.json` → `account_tree`), substitui as 6 árvores dos personagens (os personagens mantêm o trabalho da classe): 1 ponto por nível (49 no nível 50), 12 nós de até 5, 1 reset grátis por semana (o seguinte custa 50% de R).
  - **Gestão:** Salários −3%/pt · Eficiência +2% de trabalho/pt · Comércio +1% de ouro de venda/pt · Aves +2% de produção das aves/pt
  - **Vigor:** Energia +5 máxima/pt · Fôlego −3% de gasto/pt · Descanso +6% de recuperação/pt · Lanches +5% de energia por lanche/pt
  - **Oficina:** Ferramentas −4% de desgaste/pt · Veículos −4% de desgaste/pt · Consertos −5% de custo/pt · Limpeza −5% de tempo/pt
- Simulador: a pesca entra como renda (rede de 8 h, limite offline) e a árvore como até +15% da renda com 49 pontos; R recalibrado (nível 50 do Regular no dia 113, mapa no dia ~79).

### Reformulação v3 🆕 (01/11/2026) — parte R2 (cartas)
- 20 cartas (tabela na seção 11, "As 20 cartas"): 🆕 (04/11) valem por **usos** (Comum 1 … Mítica 5), mão de 3 a 5, sem trava, guarda os usos ao sair, Comum repara com ouro (1 uso por 5% da renda de 1 dia), as outras somem; álbum registra sozinho; qualquer coleta pode trazer carta (até 4 por dia).
- **Garagem não vende**: Carro, Picape e Caminhão liberam de graça nos níveis 6, 16 e 30. A carta de Veículo dá carga, lucro, tempo, roubo e jackpot às expedições que partem com ela, e o veículo aparece com a cara da carta.
- O simulador ainda não conta as cartas; com a Garagem sem venda o R foi recalibrado (mapa completo do regular no dia ~78).

### Reformulação v3 🆕 (31/10/2026) — parte R1 (mapa e visual)
- Mapa novo `Novo mapa.png` (1672×940): 29 lotes — 20 lavouras, 6 pomares (faixa de grama à direita, 4 árvores cada), Celeiro no pasto de cima (C1, vacas), Galinheiro no de baixo (C2, aves e coelho) e Lago. O A9 deixou de existir (virou o Celeiro). Prédios já desenhados no fundo.
- 28 compras: nível ⌈1,53 n⌉, custo 0,27 × 1,11^(n−1) × R(nível); Escritura da 19ª compra em diante (10 no total). R e XP recalibrados pelo simulador (mapa completo do regular no dia ~79).
- Lote bloqueado: 1 arte de mato e pedras no centro cobrindo 85% do lote; some com partículas quando a limpeza termina.
- Animais andando nos pastos (só visual, até 6 por pasto): os 10 animais usam as 4 artes (vaca; galinha/peru; pato/ganso; coelho).
- Lago (01/11, pedido do dono): **sem sprites de peixe**. 3 a 6 sombras escuras em gota (#0A1F35, 34%, halo suave) nadam embaixo da água com rumo que vira aos poucos; a cada 2–4 s cada uma solta uma ondulação (anel branco de 2 a 12 px em 600 ms, sumindo). Rede com peixe: a sombra mais próxima para, pisca e dá o "beliscão" (3 anéis rápidos) a cada 1,7 s. Ícone do peixe com "n/4" continua no píer.
- Veículos: carroça com cavalo (5 quadros); veículos a motor balançam 1 px a cada 120 ms, soltam fumaça e poeira; saem e voltam pela estrada da Garagem.
- Números visuais em `config/animations.json` (v2).

### Decisões da fase 9 🆕 (29/10/2026)
- Papéis do painel: Leitor (só vê), Moderador (advertir, suspender até 30 dias, revisar alertas e denúncias, rodar o antitrapaça), Admin (tudo, inclusive banir, reverter lançamento, voltar versão de config e mudar papéis). Sempre 2FA; sai sozinho após 30 min parado. Ninguém muda a própria conta.
- Situação da conta: ativa, advertida (o jogador vê o texto 1 vez), suspensa (até a data) ou banida. Conta bloqueada não faz nenhuma ação no servidor. Tudo com justificativa e registro na auditoria.
- Reverter = lançar o valor contrário no ledger (nunca apagar), uma vez por lançamento.
- Antitrapaça roda dentro da ação do próprio jogador, no máximo 1 vez por hora por conta (sem serviço extra). Regras e notas em `config/anticheat.json`: renda impossível (60), progresso rápido (40), cartas a mais (80), sorte nas expedições z > 5 (50), robô (50), mais de 20 recusas em 1 h (30), minigame de robô (30), relógio diferente (0, só registra), fuso diferente por 7 dias (20). Mesmo alerta no máximo 1 vez a cada 24 h.
- Nota de risco = soma dos alertas não arquivados em 30 dias (teto 100). 70+ = revisar e aviso no Discord; 90+ = mercado travado. Nunca bane sozinho.
- Discord: webhook do canal guardado no Vault do Supabase (`discord_alerts_webhook`), envio pelo pg_net (grátis). Sem o segredo, o alerta fica só no painel.
- Regras do mercado (seção 12) ficam para quando o mercado (8c) entrar.

## 10. Clima, dia e noite e evento noturno

O clima tem duas camadas: bônus pequenos que valem o dia todo e **1 evento forte por noite, entre 19h e 21h no horário local de cada jogador**. Juntos somam cerca de +11% de renda e +7% de XP, e isso já está dentro das tabelas.

- **Dia e noite** pelo fuso horário do jogador: dia 06:00–17:59, entardecer 18:00–18:59, noite 19:00–05:59.
- **Clima por fuso** (igual para todos do mesmo fuso horário), sorteado à meia-noite local em blocos de 3 h: Ensolarado 40%, Sol forte 15% (só entre 09h e 18h), Nublado 20%, Chuva 17%, Neblina 8% (só entre 03h e 12h). Quando um tipo não pode cair no bloco, as chances dos outros são redistribuídas.

| Condição | Bônus enquanto durar |
| --- | --- |
| Sol forte | +10% velocidade de crescimento |
| Chuva | +10% XP da conta |
| Neblina | +10% XP da conta e dos personagens |
| Noite | +5% ouro nas vendas concluídas à noite |

O visual do clima no mapa (solo encharcado, vento, gotas, noite) está na seção 4.

### Evento noturno

Um por dia, sorteado à meia-noite local e nunca igual ao da noite anterior. Começa em horário aleatório entre 19:00 e 20:15 (passos de 5 min), dura 45 min e sempre termina até 21:00. Aviso 10 min antes (30 min com o Papagaio). Vale também para a produção offline de quem está dentro do limite de 8 h.

| Evento | Efeito durante 45 min | Valor no dia |
| --- | --- | --- |
| Chuva de Bênçãos | +50% XP da conta | ≈1,6% do XP diário |
| Calor Dourado | +50% velocidade de crescimento | ≈1,6% da produção diária |
| Neblina Mística | +35% XP da conta e +35% XP dos personagens | ≈1,1% de cada XP |
| Lua Cheia | +40% ouro nas vendas que chegarem no evento, limitado a R ÷ 24 por jogador | até ≈4,2% do ouro do dia |

**Por que o limite na Lua Cheia:** sem limite, o jogador pode segurar a venda do dia inteiro para chegar durante o evento. Na simulação isso dava +10% de renda total; com o limite cai para +1%, e o jogador normal ganha de 0,2% a 0,8%.

O clima também mexe no risco das expedições (seção 8). Visual: filtro de noite, partículas de chuva e neblina, faixa do evento com contagem regressiva.

### Fuso horário de cada jogador

O evento acontece das 19h às 21h **no horário de cada região**: quem mora em Lisboa, Tóquio ou Manaus joga o evento à noite, como o jogador de São Paulo.

- O fuso (padrão IANA, ex.: `America/Sao_Paulo`) vem do aparelho no cadastro e fica salvo na conta. Horário de verão é tratado pelo próprio padrão.
- Seguem o fuso da conta: dia e noite, clima, evento noturno, virada do dia (missões diárias, salários) e virada da semana (missões semanais, segunda 00:00 local).
- Jogadores do mesmo fuso veem o mesmo clima e o mesmo evento: o sorteio usa como semente a data local + o deslocamento do fuso em minutos (ex.: −180). Nada precisa ser guardado antes, mas o resultado é registrado para o painel.
- Ao visitar um amigo, a fazenda dele aparece no horário e clima dele.
- Fica em UTC o que é de todos: ranking semanal, Encomendas da Vila e o mercado (quando existir).
- **Contra abuso:** trocar o fuso só 1 vez a cada 30 dias, valendo a partir da próxima meia-noite; no máximo 1 evento por conta a cada 20 h, mesmo trocando de fuso. Fuso da conta diferente do aparelho por 7 dias seguidos gera aviso ao jogador e alerta no painel.

### Decisões da fase 6 🆕 (26/10/2026)
- A agenda do dia é sorteada no servidor (gerador criptográfico) na 1ª vez que alguém do fuso precisa dela e fica guardada; quem tem o mesmo deslocamento de fuso vê o mesmo clima e o mesmo evento.
- Sol forte e Calor Dourado aceleram lavoura **e pomar**, passo a passo enquanto duram (também fora do jogo, dentro das 8 h).
- Lua Cheia conta a expedição pela hora em que o veículo volta (não pelo clique em Receber).
- Previsão: 1 h sem Botânica, +1 h por ponto do ramo Clima (até 6 h). O evento aparece 10 min antes (30 com o Papagaio).
- O fuso vem do aparelho na 1ª entrada; depois, 1 troca a cada 30 dias, valendo na próxima meia-noite. O salário vira à meia-noite do fuso da conta.
- O painel pode forçar ou cancelar o evento de um dia num fuso, em qualquer horário (para teste), e fica registrado.

## 11. Missões e cartas de buff

São **10 cartas**, cada uma em 5 raridades (50 versões). Usar uma carta liga um buff de 1 h a 2 h 30; guardar no **Armory** dá bônus permanente; e toda carta pode ser vendida ao Colecionador da Vila (e, se o mercado incluir cartas, a outros jogadores). Cartas continuam vindo só de missões: até 4 por semana das diárias e 2 das semanais. Na simulação, o jogador regular tira a 1ª Mítica na semana 12 e completa a 1ª carta no Armory na semana 22.

### Missões

- **5 diárias** (reset 00:00) e **5 semanais** (reset segunda 00:00), sorteadas de um banco conforme o nível. Só entram missões de sistemas já liberados.
- As metas escalam com a produção do próprio jogador (ex.: "colha o equivalente a 2 h da sua produção"), então a dificuldade é igual para todos os níveis. 1 troca grátis de missão diária por dia.
- Cada diária paga ouro (≈40% de 1 h de renda) e XP (≈30 min de XP de produção). Completar as 5 do dia dá 1 pacote todo dia (sem limite semanal): 1 carta até o nível 14 e 2 do nível 15 em diante.
- 🆕 (01/11) **De onde vêm as cartas:** 3 Comuns (Sol, Cesta, Coruja) já na mão ao criar a conta; 1 carta por nível do 2 ao 10; pacote das diárias todo dia; semanais iguais. A mão de 3 gasta ~8 cartas por semana (duração média 2,6 dias): ~21 cartas na 1ª semana, ~9 por semana até o nível 14 e ~16 do 15 em diante.
- Semanais: 3 completas = 1 carta; as 5 completas = +1 carta e 1 Escritura.
- Banco de diárias (exemplos): colher X unidades; enviar 2 expedições; coletar X produtos animais; ajudar 2 vizinhos; vender na Barraca (ou no mercado, quando existir); plantar um cultivo do seu nível; manter 3 personagens em campo por 2 h; consertar um veículo.
- Banco de semanais (exemplos): 10 expedições; 1 expedição Capital ou mais longe com sucesso; ganhar X de ouro; subir 1 nível de personagem; ajudar 10 vizinhos; estar com produção ativa em 3 eventos noturnos; vender 5 anúncios no mercado (só depois da fase 8 🆕).

### As 20 cartas (v3) 🆕

🆕 **(04/11, pedido do dono) Cartas por uso.** A carta em uso vale pelas **próximas coletas** da atividade que ela melhora, online ou offline: **Comum 1 uso, Incomum 2, Rara 3, Lendária 4, Mítica 5**. 1 uso = colher um lote inteiro (8 canteiros), um pomar (4 árvores), uma casa de animais ou o lago (4 vagas), ou mandar 1 expedição (cada canteiro gasta 1/8 de uso, cada árvore, animal ou peixe 1/4). Cada carta gasta só na sua atividade: Sol e Cesta na lavoura e no pomar; Enxada e Lupa na lavoura; Rebanho nos animais; Forcado nos animais e no pomar; Pesca no lago; Ferradura, Prancheta e Veículo nas expedições (gravadas na partida); as outras em qualquer coleta. A mão começa com **3 cartas**, ganha a 4ª no nível 15 e a 5ª no nível 30, sem repetir a mesma carta. Não há trava: dá para pausar quando quiser e a carta guarda os usos que sobraram. Quando os usos acabam, a **Comum fica gasta** e volta com **reparo em ouro** (devolve 1 uso por 5% da renda de 1 dia do nível); as outras **somem**. **Carta de coleta:** cada uso tem 25% de chance de trazer uma carta nova (sorteio normal, com garantia), até **4 por dia** (dia do jogador). A fazenda, os 6 personagens e a Carroça funcionam sem cartas: elas são multiplicadores temporários.

Os valores são bem menores que os da v2 porque a carta fica dias na mão (e até 5 ao mesmo tempo). Tetos da seção abaixo continuam valendo.

| Carta | O que faz | Comum (2 d) | Incomum (3 d) | Rara (3 d) | Lendária (4 d) | Mítica (4 d) |
| --- | --- | --- | --- | --- | --- | --- |
| Sol | Fazenda: Crescimento da lavoura e do pomar | +5% | +7% | +10% | +14% | +20% |
| Ampulheta | Fazenda: Velocidade geral: lavoura, pomar, animais e limpeza | +3% | +4% | +5% | +7% | +10% |
| Cesta | Fazenda: Rendimento de colheita (unidades) | +4% | +5% | +7% | +9% | +12% |
| Rebanho | Fazenda: Produção dos animais | +6% | +8% | +10% | +14% | +20% |
| Moeda | Fazenda: % do valor produzido vira ouro (pago quando a carta sai da mão) | +3% | +4% | +5% | +7% | +10% |
| Coruja | Fazenda: XP da conta e dos heróis | +6% | +8% | +10% | +14% | +20% |
| Tempestade | Fazenda: Bônus do clima e do evento noturno | +20% | +25% | +35% | +50% | +75% |
| Ferradura | Fazenda: Expedições que partem com a carta: crítico / valor do crítico e chance de item e Kit | +2 / +5% / +5% | +3 / +7% / +7% | +4 / +10% / +10% | +6 / +14% / +14% | +9 / +20% / +20% |
| Engrenagem | Fazenda: Automação e frota: trabalho da equipe / desgaste dos veículos | +4% / −4% | +5% / −5% | +7% / −7% | +9% / −9% | +12% / −12% |
| Luvas | Trabalhadores: Trabalho por hora da equipe | +4% | +5% | +7% | +9% | +12% |
| Cantil | Trabalhadores: Gasto de energia em campo | −6% | −8% | −10% | −13% | −18% |
| Café | Trabalhadores: Recuperação de energia no banco | +8% | +10% | +13% | +17% | +25% |
| Vara de Pescar | Trabalhadores: Lucro na pesca (vale na R3) | +6% | +8% | +10% | +14% | +20% |
| Forcado | Ferramentas: Trabalho para coletar animais e colher o pomar (menos) | +4% | +5% | +7% | +9% | +12% |
| Enxada | Ferramentas: Trabalho para plantar e colher a lavoura (menos) | +4% | +5% | +7% | +9% | +12% |
| Martelo | Ferramentas: Limpeza de lote, desgaste das ferramentas e dos veículos | +8% | +10% | +13% | +17% | +25% |
| Balança | Ferramentas: Ouro nas vendas | +3% | +4% | +5% | +7% | +10% |
| Lupa | Ferramentas: Chance de Semente Rara (sobre a chance atual) | +8% | +10% | +13% | +17% | +25% |
| Prancheta | Ferramentas: Expedições que partem com a carta: sucesso / tempo de viagem | +2 / −5% | +3 / −6% | +4 / −8% | +5 / −10% | +7 / −15% |
| Veículo | Veículo: Expedições que partem com a carta (o veículo na Garagem aparece com a cara da carta) | +5% carga e lucro, −3% tempo | +10% carga e lucro, −6% tempo | +15% carga e lucro, −8% tempo, −10% roubo | +22% carga e lucro, −12% tempo, −20% roubo | +35% carga e lucro, +5 jackpot |

- **Veículo:** cada veículo libera de graça no nível dele (Carro 6, Picape 16, Caminhão 30; a Garagem não vende). A carta de Veículo dá os bônus da tabela às expedições que partem com ela na mão, e o veículo na Garagem aparece com a cara da carta (Carroça, Compacto, Off-Road, 4x4, Caminhão).
- **Moeda** paga sobre o que foi produzido, não sobre o que foi vendido; o ouro sai quando a carta deixa a mão.
- **Ferradura, Prancheta e Veículo** valem para expedições que **partem** com a carta na mão.
- **Vara de Pescar** só passa a valer quando a pesca entrar (parte R3).
- **Arte:** uma prancha por carta com as 5 raridades (moldura, ilustração e texto). Os números das artes seguem esta tabela; se o simulador mudar um número, o dono gera a arte nova.

### Armory (coleção permanente)

- 🆕 (v3) Cada carta tem 5 molduras no Armory (álbum), uma por raridade. **O álbum registra sozinho** a carta e a raridade na primeira vez que ela entra na mão; a carta continua sendo usada normalmente.
- **Bônus parcial** (selo prata): Comum + Incomum + Raro da mesma carta. **Bônus completo** (selo dourado): as 5 raridades; substitui o parcial.
- Completar as 10 cartas: título "Guardião do Armory", moldura de perfil Mítica e uma vitrine animada na Casa (só visual).

| Carta | Bônus parcial (Comum + Incomum + Raro) | Bônus completo (as 5 raridades) |
| --- | --- | --- |
| Sol de Verão | +1% crescimento | +2,5% crescimento |
| Cesta Dourada | +1,5% Colheita Dourada | +3,5% Colheita Dourada |
| Rebanho Feliz | +8% produção animal | +20% produção animal |
| Moeda da Sorte | +1,5% ouro em vendas | +3,5% ouro em vendas |
| Estrada Livre | +2 pontos de sucesso | +5 pontos de sucesso |
| Coruja Sábia | +2,5% XP da conta | +6% XP da conta |
| Ampulheta | +0,8% velocidade de lavoura, pomar e animais | +2% |
| Trevo de Quatro Folhas | +2 pontos de crítico e +10% de itens | +5 pontos e +25% |
| Tempestade | +25% nos bônus de clima e evento | +60% |
| Fôlego | +15% recuperação de energia e +10% XP de personagens | +40% e +25% |

Cada bônus parcial vale cerca de 2% de renda e cada completo cerca de 5% (medido com a simulação). O Armory inteiro chega perto de 50%, mas leva anos: é o objetivo de longo prazo do jogo. Depois do nível 50, o XP da Coruja vira Estrelas da Vila.

### Sorteio e garantia

- Chance por carta: Comum 50%, Incomum 30%, Raro 14%, Lendário 5%, Mítico 1%. Dentro da raridade, as 10 cartas têm chance igual.
- **Garantia** com contadores visíveis: Raro ou melhor a cada 10 cartas sem um; Lendário ou melhor a cada 40; Mítico a cada 120. Taxa real com a garantia: 48% / 29% / 15,5% / 5,9% / 1,55%.
- O pacote abre na hora: não existe pacote guardado nem pacote à venda. Probabilidades sempre visíveis.
- Cada carta tem um **número de série** único no servidor (dono atual, origem e histórico), o que impede duplicação.

### Fichário (inventário de cartas)

- 60 espaços no começo; +20 por ampliação (custa 50% da Renda de Referência do nível), até 200.
- Cópias iguais aparecem agrupadas, mas cada uma ocupa 1 espaço. Filtros por carta, raridade e "falta no Armory".
- Fichário cheio: a carta nova espera 7 dias numa caixa de entrada para o jogador usar, vender ou abrir espaço.

### Venda de cartas

Toda carta tem 3 destinos e a escolha é do jogador: **usar** (buff agora), **guardar** no Armory (para sempre) ou **vender** (ouro).

- **Colecionador da Vila** (venda garantida ao jogo, desde a fase 7): paga metade do valor do buff, sobre a Renda de Referência (R) do nível de quem vende: Comum 0,2% de R, Incomum 0,4%, Raro 0,8%, Lendário 1,3%, Mítico 2,3%. É o piso de preço.
- **Mercado entre jogadores** 🆕 (só se cartas entrarem no que poderá ser negociado; fase 8): libera no nível 12; carta tirada há menos de 72 h não pode ser anunciada; taxa de 8% + 1% do anúncio; preço entre 50% e 400% da mediana dos últimos 7 dias daquela carta e raridade (sem mediana ainda, a base é 3× o preço do Colecionador). O limite antitransferência entre as mesmas 2 contas vale para cartas.

### Resultado da simulação (3 anos, 3.000 jogadores por perfil)

| Resultado | Casual (4 cartas/semana) | Regular (5,5) | Máximo (6) |
| --- | --- | --- | --- |
| 1ª carta Mítica (mediana / 90% dos jogadores) | semana 15 / 30 | semana 12 / 22 | semana 10 / 20 |
| Bônus parcial nas 10 cartas, sem mercado | semana 45 | semana 33 | semana 30 |
| Bônus parcial nas 10 cartas, com mercado | semana 31 | semana 21 | semana 19 |
| 1ª carta completa no Armory | semana 30 | semana 22 | semana 20 |
| Cartas completas em 1 / 2 / 3 anos | 2 / 4 / 6 | 3 / 6 / 7 | 3 / 6 / 8 |
| Bônus do Armory em 3 / 6 / 12 meses (com mercado) | 10% / 19% / 26% | 14% / 23% / 29% | 14% / 23% / 29% |

🆕 Até o mercado existir, vale a linha "sem mercado".

### Tetos de bônus

Tudo soma, mas nunca passa destes tetos. "Permanente" = habilidades, Armory, pet, itens e clima; "absoluto" = com buffs de carta e evento noturno.

| Atributo | Teto permanente | Teto absoluto |
| --- | --- | --- |
| Velocidade de crescimento | +100% | +150% |
| XP da conta | +100% | +200% |
| Ouro em vendas | +50% | +50% (a Moeda da Sorte paga à parte) |
| Produção animal | +60% | +250% |
| Colheita dupla | 25% | 25% |
| Colheita Dourada | 20% | 60% |
| Sucesso de expedição | 95% | 95% |
| Crítico em expedição | 25% | 60% |
| Redução de salário | 40% | 40% |
| Redução de custo de sementes, mudas e ração | 40% | 40% |
| Recuperação de energia | +100% | +200% |
| Redução do gasto de energia | 40% | 100% |

### Decisões da fase 7 🆕 (27/10/2026)
- Missões e Cartas ficam em botões no topo da tela, com os 3 buffs ativos e o tempo restante ao lado.
- Banco de missões montado dos exemplos desta seção, só com o que já existe no jogo (vizinhos, mercado e encomendas entram na fase 8). Missão de animais, de 3 personagens em campo, de conserto e de expedição longe só aparecem para quem já tem o sistema.
- Metas e prêmios pela produção do próprio jogador: média móvel por hora do valor produzido (preço da Feira) e do XP, com piso pelo R do nível. Diária paga 0,4 h de renda em ouro e 0,5 h de XP, fixados no sorteio; o Comerciante (Negócios B) soma +5% por ponto no ouro.
- Tudo conta para as missões: clique, equipe e o tempo fora do jogo (dentro das 8 h).
- 1 troca grátis por dia, só de diária ainda não completa.
- O pacote abre na hora com a carta virando. Fichário cheio: a carta espera 7 dias na caixa de entrada e depois o Colecionador compra sozinho (o jogador não perde o valor).
- Estrada Livre e Trevo valem para a expedição que sai durante o buff (ficam gravados nela). A Moeda da Sorte junta a % do valor produzido durante o buff e paga quando ele acaba (ou quando é trocado).

## 12. Painel administrativo e antitrapaça

O painel é um app separado, só para contas com papel admin e 2FA, e compara cada jogador com as faixas da simulação para achar trapaça e problemas de balanceamento. 🆕 Fase 1: página `/admin.html` com entrada por 2FA (aplicativo autenticador), busca de jogador e as abas Ledger, Auditoria e Fazenda; cada consulta do admin fica registrada no audit_log.

| Guia | O que mostra | Ações |
| --- | --- | --- |
| Visão geral | Online agora, jogadores ativos por dia e mês, novos, retenção D1/D7/D30, ouro criado × destruído hoje, alertas abertos | — |
| Jogadores | Ficha completa: nível, ouro, lotes, personagens, cartas, itens, pet, veículos, ledger, logins com IP e dispositivo, contas no mesmo dispositivo | Advertir, congelar mercado, suspender, banir, reverter transação, ajustar com justificativa |
| Progresso | Nível e lotes (de 30 🆕) × dias de conta de cada jogador sobre a faixa casual–dedicado da simulação | Abrir ficha dos que saem da faixa |
| Economia | Fontes e drenos por dia, ouro em circulação, inflação, renda por hora por nível (percentis) | — |
| Mercado (fase 8 🆕) | Anúncios, negociações, pares de contas que negociam entre si, preços colados no limite | Cancelar anúncio, congelar par |
| Expedições | Sucesso real × teórico por rota, veículo e raridade; resultados do minigame por jogador; drops de itens, kits e Escrituras | — |
| Cartas | Drops reais × esperados por raridade, garantia, cartas por número de série, Armory de cada jogador, preços das cartas | Congelar pacotes |
| Missões | Conclusão e tempo médio por missão | Desativar missão |
| Clima e eventos | Agenda e histórico | Forçar ou cancelar evento (com registro) |
| Antitrapaça | Fila de alertas com nota de risco, regra, evidência | Revisar, arquivar, escalar |
| Balanceamento | Config versionada, comparação, histórico | Rodar o simulador e publicar nova versão; voltar versão; ligar recursos |
| Denúncias e suporte | Denúncias de jogadores e pedidos | Responder, encaminhar |
| Auditoria | Tudo que cada admin fez (não pode ser apagado) | — |

Papéis: **Leitor** (só vê), **Moderador** (advertir, congelar, suspender) e **Admin** (banir, reverter, mudar config). Sessão expira em 30 min.

### Regras de detecção

| Sinal | Regra | Ação automática |
| --- | --- | --- |
| Renda impossível | Ouro por hora acima de 1,5 × o percentil 99,9 do nível | Alerta alto |
| Progresso rápido demais | Nível ou lotes acima do jogador dedicado da simulação para a idade da conta, com 10% de folga | Alerta |
| Cartas a mais | Cartas recebidas acima de 6 × semanas de conta | Alerta crítico e congela pacotes |
| Sorte impossível | Sequência de expedições com chance menor que 1 em 1 milhão | Alerta (sinal de falha no servidor) |
| Robô | Intervalo entre ações quase constante (desvio < 50 ms) por 30 min | Alerta |
| Tentativa de manipular | Mais de 20 ações recusadas pela validação por hora | Alerta e limite de requisições menor |
| Multicontas (com mercado) | Contas no mesmo dispositivo ou IP negociando entre si | Bloqueia negociação entre elas e alerta |
| Lavagem no mercado (com mercado) | Mesmo par negociando em 3 dias ou mais com preço no limite da faixa | Alerta |
| Conta nova recebendo valor (com mercado) | Conta com menos de 7 dias recebendo mais de 2 × R pelo mercado | Segura o ouro por 24 h |
| Relógio do cliente | Diferença maior que 5 min | Só registra (o servidor ignora o relógio do cliente) |
| Minigame robô | Intervalo entre setas abaixo de 90 ms ou sempre igual | Partida vale só como Concluída e alerta |
| Carta duplicada | Mesmo número de série em 2 contas | Congela as 2 contas e alerta crítico |
| Troca de fuso | Mais de 1 troca em 30 dias, ou fuso da conta diferente do aparelho por 7 dias | Recusa a troca e alerta |

Cada alerta soma uma nota de risco de 0 a 100. A partir de 70 entra na fila de revisão; a partir de 90 congela o mercado da conta até um humano revisar. **Nunca banir automaticamente.** Alertas a partir de 70 também vão para um webhook (Discord, Telegram ou n8n).

## 13. Plano de construção, fase por fase

São 12 fases. Cada uma termina com deploy, testes automáticos verdes e o checklist em produção feito pelo dono.

0. **Base.** Repositório, Supabase com ambiente de teste e de produção, login, deploy automático, `config/*.json` (já começados: `levels.json`, `lots.json`, `mapConfig.json`, `crops.json`, `animals.json` 🆕), ledger, audit_log, script das artes e o simulador de economia em TypeScript, partindo do modelo de terreno de `tools/balance` e calibrando a capacidade de trabalho por personagem 🆕. *Teste:* criar conta, entrar, sair; o simulador reproduz a seção 14 com até 10% de diferença.
1. **Fazenda mínima.** Mapa com as 4 zonas (Casa com Silo, Forja, Barraca e Garagem com a Carroça parada e animada 🆕), 1 lote (A1), Agricultor, os 4 primeiros cultivos, `advance_farm`, limite offline de 8 h, Silo, Barraca, painel básico (busca de jogador, ledger, auditoria). *Teste:* plantar, fechar o jogo 2 h, voltar e colher; mudar a hora do celular não muda nada; clicar em cada zona abre o painel certo.
2. **Progressão.** XP e níveis 1–50, os 50 cultivos, compra e limpeza dos 29 lotes 🆕, Escritura da 20ª compra em diante (por enquanto dada pelo painel), ferramentas, árvores do pomar com troca grátis 🆕. *Teste:* comprar lote vizinho; lote não vizinho e lote sem nível são recusados; Galinheiro e Celeiro podem ser comprados de longe; derrubar uma árvore de graça e plantar outra fruta.
3. **Personagens.** 6 classes, energia e rodízio nos slots, contratação e salário, Desmotivado, inventário, árvores de habilidade, reset, pets. *Teste:* ficar sem ouro para salário e ver o personagem Desmotivado; pagar e ver voltar ao normal.
4. **Animais.** Galinheiro e Celeiro (prédios no mapa 🆕), Lago (+10% e +2 vagas para aves 🆕), ampliações, 10 animais, ração. *Teste:* sem ouro para ração, o animal para de produzir e volta quando há ouro; comprar o Lago e ver 2 vagas a mais no Galinheiro, que só aceitam aves.
5. **Expedições.** Garagem com os 5 veículos animados 🆕, 5 rotas, (v3: sem raridade, reforma e Kits), minigame de partida, sorteio, crítico, falha parcial, seguro, garantia contra azar, repetição, desgaste e conserto, itens, Escrituras, demanda do dia, relatório narrado. *Teste:* 2 falhas seguidas e a 3ª com +25 pontos visível; seguro devolvendo a perda; deixar o tempo do minigame acabar e ver a chance reduzida; reformar a Carroça e ver o sprite da nova raridade e a capacidade maior; com o veículo em viagem, a vaga da garagem mostra o contador.
6. **Clima e evento noturno.** Agenda diária por fuso horário, bônus, filtros visuais, aviso do evento, troca de fuso com espera de 30 dias. *Teste:* com 2 contas em fusos diferentes, cada uma vê o evento entre 19:00 e 21:00 do seu horário, sem repetir o da noite anterior; forçar um evento pelo painel.
7. **Missões e cartas.** Bancos de missões, troca diária, pacotes, garantia, 10 cartas em 5 raridades, buffs temporários, Armory, fichário, venda ao Colecionador, tetos de bônus. *Teste:* abrir pacotes e conferir a garantia; colocar Comum, Incomum e Raro da mesma carta no Armory e ver o bônus parcial; ativar 3 buffs juntos e ver o teto respeitado; vender uma carta ao Colecionador e conferir o valor.
8. **Multiplayer.** Amigos, visitas com ajuda e emojis, ranking semanal, drenos de fim de jogo e o mercado com o conteúdo que o dono decidir antes desta fase 🆕. *Teste:* duas contas no mesmo celular não conseguem negociar entre si.
9. **Painel completo e antitrapaça.** Todas as guias e regras da seção 12, alertas por webhook. *Teste:* forçar cada regra com uma conta de teste e ver o alerta chegar.
10. **Beta fechado.** 20 a 50 jogadores por 2 semanas; comparar com a simulação e ajustar só pela config; teste de carga com 500 jogadores simultâneos; revisão de segurança (RLS, RPC, limites) e adequação legal (seção 15).
11. **Lançamento.** Página do jogo no navegador, termos, política de privacidade, monitoramento e plano de rollback.

## 14. Testes de balanceamento

🆕 **Simulador completo da fase 0** (`tools/sim`, `npm run sim`): 160 dias, hora a hora, para os 3 perfis, lendo só a config. Modela lotes, vizinhança, Escrituras e limpeza; escolha de cultivo pela mão de obra (até 2 cultivos por vez); pomar com troca de fruta; animais com raridade sorteada, Lago e ampliações; personagens com contratação, energia e rodízio, salário, nível, ferramenta e desgaste; venda por expedição (rotas, veículos, raridade, Gerente, kits, Escrituras) ou Barraca; missões, pacotes com garantia, buffs e Armory; pet. Entram pela média: clima e evento noturno (+11% renda e +7% XP, seção 10), minigame (casual −1, regular +1, dedicado +2 pontos), habilidades (pontos ÷ 39 × 10% de renda por personagem) e Papagaio (+4% nas vendas).

**Calibração:** a capacidade de trabalho saiu **2,67 unidades por personagem por hora** (Madeira) na fase 0. 🆕 Desde o teste da fase 2, nas sessões o jogador colhe e planta por clique (1 ciclo grátis por canteiro e 1 colheita por árvore até a próxima sessão, no máximo 8 h); o Agricultor trabalha entre as sessões. O que se calibra agora são as escalas da curva de XP (nível 10 no dia 1, 30 no dia 33 e 50 no dia 113) e a Renda de Referência, por ponto fixo (preços dependem de R, R depende do ritmo): `levels.json` versão 3. Os parâmetros do lote foram buscados no próprio simulador: 0,28 × 1,10^(n−1) × R(⌈1,46 n⌉).

| Resultado (30 lotes, simulador, média de 5 sementes) | Casual (2 sessões/dia) | Regular (4) | Dedicado (9) |
| --- | --- | --- | --- |
| Nível 10 🆕 | dia 1,5 | dia 1,0 | dia 0,8 |
| Nível 30 | dia 46 | dia 33 | dia 30 |
| Nível 50 | dia 157 | dia 113 | dia 103 |
| Mapa completo | dia 107,7 | dia 77,0 | dia 70,0 |
| Maior espera por ouro de um lote | 3,4 dias | 2,1 dias | 2,2 dias |
| Salários sobre a renda | 17,0% | 12,3% | 11,2% |
| Consertos de ferramenta sobre a renda | 6,9% | 7,7% | 7,2% |
| Bônus parcial nas 10 cartas (mediana, sem mercado) | semana 45 | semana 33 | semana 30 |

Comparado com as metas publicadas da simulação antiga (25 lotes, abaixo), tudo fica a até 1%. O relatório completo fica em `tools/sim/report.json`, e `npm run balance:check` refaz o regular para garantir que ele está em dia com a config.

| Resultado da simulação antiga (25 lotes) | Casual (2 sessões/dia) | Regular (4) | Dedicado (9) |
| --- | --- | --- | --- |
| Mapa completo | dia 108 | dia 77 | dia 71 |
| Maior espera por ouro de um lote | 6,5 dias | 3,2 dias | 2,2 dias |
| Salários sobre a renda | 12% a 18% | 10% a 17% | 9% a 14% |

Na simulação antiga, os três perfis subiam juntos até o nível 20 (dia 13 a 18); a diferença aparecia depois, quando as expedições e o tempo online passam a pesar.


Achados da simulação antiga que mudaram o desenho:

- **Cartas e Armory pesam sem dominar:** sem nenhuma carta, o regular completaria o mapa no dia 78 e o nível 50 no dia 116. Trocar as 15 cartas antigas por 10 cartas + Armory deixou o jogo 4 dias mais lento até o mapa completo (73 → 77), ainda dentro da meta. Raridade de veículo e minigame não mudam o ritmo: as reformas custam cerca de 1% do ouro e o bônus pesa só nas rotas arriscadas.
- **Lua Cheia sem limite era uma brecha** (+10% de renda segurando vendas); com o limite, +1%.
- **Garantia contra azar:** com +25 pontos depois de 2 falhas, a chance de 3 falhas seguidas em 20 viagens para a Exportação caiu de 26% para 13%.
- **Seguro** sempre reduz a média um pouco e levanta o pior caso; na Feira não compensa, por isso não é oferecido lá.
- **Capacidade dos veículos** só aperta na 1ª semana (até metade da produção vai para a barraca antes do Carro). Depois, veículo vale pelo acesso a rotas e pela segurança; por isso nenhuma carta mexe em capacidade.
- **Energia** pesa muito com 1 a 3 personagens e pouco depois do 5º: quem resolve é contratar.

### Critérios de aceite do simulador (o build falha se sair da faixa: `npm run balance:check` no CI) 🆕

- Regular: mapa completo (30 lotes 🆕) entre os dias 65 e 85; nível 50 entre os dias 95 e 125.
- 🆕 Começo rápido: regular no nível 10 entre os dias 0,8 e 1,3; o nível 2 sai com 1 rodada de Alface no A1.
- Casual: nenhuma espera por um lote acima de 8 dias.
- Salários do regular entre 8% e 18% da renda.
- Valor médio por rota sempre crescente da Feira à Exportação; seguro nunca com média positiva.
- Valor de cada buff de carta dentro de ±15% do alvo da raridade (6, 12, 22, 38 e 65 min de produção).
- Armory: bônus parcial nas 10 cartas para o regular entre as semanas 25 e 40 sem mercado 🆕, e entre as semanas 15 e 30 quando o mercado incluir cartas.
- Minigame: Perfeita no máximo +3 pontos; não concluir custa no máximo −10.
- Ganho da Lua Cheia para quem segura vendas: no máximo 2% da renda.
- Nenhum bônus passa do teto da seção 11.
- 🆕 Nenhuma limpeza de lote passa de 8 h (limite offline).
- 🆕 Ouro por hora de cada cultivo dentro de ±15% do alvo 60 × 1,07^(nível−1) (árvore = 2 canteiros); sementes e mudas dentro da regra com até 5% de diferença.
- 🆕 XP por hora de recorrentes e árvores dentro de ±10% da lavoura do mesmo nível.
- 🆕 Cada animal entre 2,8 e 3,2 canteiros; ração entre 13% e 17% da produção; compra = 10 dias de ração.

Premissas (`tools/sim/profiles.json`): sessões às 9h e 20h (casual); 8h, 13h, 19h e 22h (regular); de 2 em 2 h das 7h às 23h (dedicado); 🆕 em cada sessão o jogador colhe e planta tudo por clique; o jogador escolhe o cultivo que mais rende para a mão de obra que tem, troca as árvores do pomar pela melhor fruta liberada, compra lote assim que pode (guardando 1 dia de salários e ração) e só faz compras secundárias (ferramenta, veículo, reforma, ampliação) quando o próximo lote espera nível ou quando custam até 25% do ouro. Missões: casual completa as 5 diárias em 43% dos dias, regular em 75%, dedicado sempre (4, 5,5 e 6 cartas por semana). 🆕 Raridade de sementes não entra (chances ainda não definidas): a curva supõe Comum.

## 15. Lei e monetização futura

Os pacotes de cartas são permitidos porque são grátis; **nunca podem ser vendidos**, nem dentro de VIP ou passe de batalha. Isto não é parecer jurídico: valide com um advogado antes de lançar e antes de cobrar qualquer coisa.

### ECA Digital (Lei 15.211/2025) e LGPD

- A lei define caixa de recompensa como a compra, **mediante pagamento**, de itens ou vantagens aleatórias (art. 2º, IV) e proíbe caixas de recompensa em jogos que menores provavelmente acessam (art. 20). Pacote ganho só em missão fica fora da definição; pacote pago, ou ganho por algo pago, entra. Vender carta avulsa por ouro entre jogadores não é sorteio e pode; por isso o ouro nunca pode ser comprado com dinheiro.
- Interação entre jogadores deve vir limitada por padrão, com consentimento dos responsáveis (art. 21). Por isso: sem chat livre, só emojis pré-definidos, com denúncia e bloqueio.
- O art. 24 pede que contas de até 16 anos fiquem vinculadas a um responsável. Peça a data de nascimento no cadastro e já prepare o vínculo com responsável e controles parentais.
- A lei está em vigor desde 17/03/2026; a ADI 7999 no STF questiona a verificação de idade e a proibição de loot boxes. Acompanhar.
- LGPD: termos e política de privacidade, dados mínimos, exportar e apagar conta, nada de perfil de comportamento de menores para publicidade.
- Pedir a classificação indicativa antes do lançamento.

### Para o VIP, o passe de batalha e as skins (fase futura)

- **Skins e decorações:** personagens, pets, veículos, casa, cercas, molduras de perfil, emojis. Só visual.
- **VIP:** conveniência sem poder (ex.: atalhos, mais espaço de decoração, selo de perfil, 3ª repetição automática de expedição). Regra: nada que aumente a renda.
- **Passe de batalha:** trilha grátis + trilha paga, com recompensas **fixas e conhecidas** (nada sorteado), principalmente cosméticas.
- **Ouro nunca é vendido por dinheiro:** protege o mercado entre jogadores e evita venda de contas.
- Já deixe pronto: tabela `entitlements` e loja cosmética desligada por feature flag.


## v3 · Achados, Forja e interface (pedido do dono em 01/11/2026) 🆕
- **Expedição traz só carta:** cada viagem tem chance de carta (Feira 1%, Cidade 2%, Capital 4%, Porto 6%, Exportação 8%; o crítico rola 2 vezes; Gerente e Ferradura aumentam). A carta é sorteada ao Receber, com as chances e a garantia normais. Acabaram os itens de funcionário (Vestimenta e Amuleto), os Kits de Reforma e as Escrituras: os lotes pedem só nível e ouro.
- **Veículos sem raridade e sem reforma:** a cara do veículo vem da carta Veículo. O conserto fica na Garagem (botão em cada veículo). A Forja cuida só das ferramentas e da Vara de Pescar.
- **Interface 16-bit:** fonte pixel (Press Start 2P, licença OFL, salva no projeto) nos títulos e números; bordas em degrau; botões de madeira que afundam no clique e brilham no hover; HUD com nível/XP e ouro à esquerda e botões quadrados só com ícone (desenhados no código); clima só com o ícone; Pets, Pomar e casas dos animais em grade de cards; Forja com a ferramenta no centro e setas dos lados; explicações longas no [?] do cabeçalho; nenhum `<select>` do navegador (seletor de madeira com setas).
