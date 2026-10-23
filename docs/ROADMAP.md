# Village Idle Farm — mapa do projeto (22/10/2026)

## A. Feito (design e balanceamento)

| Área | Entrega | Onde |
| --- | --- | --- |
| Documento | GDD v2, seções 1–15 completas, 🆕 marca o que mudou | `docs/GDD.md` |
| Mapa | 30 lotes (21 lavouras, 6 pomares, Galinheiro, Celeiro, Lago), início no A1, 4 zonas (Casa com Silo, Forja, Barraca, Garagem), fundo sem árvores | `config/mapConfig.json`, `assets/map/` |
| Terreno | Tabela de 29 compras, preço e nível por fórmula, Escritura da 20ª em diante, limpeza até 8 h, vizinhança por lado | `config/lots.json` |
| Níveis | Níveis 1–50, XP e renda de referência (R) | `config/levels.json` |
| Cultivos | 50 cultivos (lavoura, recorrentes, árvores), ouro/h alvo 60×1,07^(n−1), sementes e XP | `config/crops.json` |
| Animais | 10 animais, ampliações de Galinheiro/Celeiro, Lago (+10% aves, +2 vagas) | `config/animals.json` |
| Testes | Checagens automáticas (mapa, lotes, fórmula, cultivos, animais, documento × config), terminam em "tudo verde" | `npm run balance:check` |
| Modelo | Modelo reduzido de terreno calibrado na simulação antiga | `tools/balance/` |

## B. Decisões já tomadas
- Navegador primeiro; Steam e mercado depois.
- Mercado entre jogadores: conteúdo decidido antes da fase 8.
- 30 lotes, início A1, vizinhança só por lado (Galinheiro/Celeiro isentos).
- Garagem à esquerda do A5; só o veículo usado aparece, animado.
- XP dos recorrentes = plantio inteiro; derrubar árvore grátis; Lago +10% e +2 vagas.

## C. Pendências do dono (antes da fase 0)
1. Acesso ao repositório rodrigopfcampos/Villageidlefarm.
2. ✅ Supabase (grátis, São Paulo): teste `vfuomlgnhvhfeygeegqm`, produção `saijxytudvsyvhfnwnpb`.
3. Hospedagem: Cloudflare Pages ou Vercel.
4. Mapear as 8 ilustrações às 10 cartas (faltam 2).
5. Gerar 3 artes: muda folhosa 24×32, muda de palmeira 24×32, Celeiro 112×112 (1024×1024, fundo #FF00FF).

## D. Falta fazer (GDD seção 13)

| Fase | Entrega | Teste de aceite |
| --- | --- | --- |
| 0 Base | Repo, Supabase teste/produção, login, deploy automático, config, ledger, audit_log, script das artes, simulador completo (remedir R com 30 lotes, calibrar capacidade de trabalho) | Criar conta/entrar/sair; simulador a até 10% da seção 14 |
| 1 Fazenda mínima | Mapa com 4 zonas, lote A1, Agricultor, 4 cultivos, `advance_farm`, offline 8 h, Silo, Barraca, painel básico | Plantar, fechar 2 h, colher; hora do celular não interfere |
| 2 Progressão | XP/níveis, 50 cultivos, compra e limpeza dos lotes, Escritura, ferramentas, pomar | Lote vizinho ok; não vizinho/sem nível recusado |
| 3 Personagens | 6 classes, energia, salário, Desmotivado, inventário, habilidades, pets | Sem ouro → Desmotivado; pagar → normal |
| 4 Animais | Galinheiro, Celeiro, Lago, ampliações, 10 animais, ração | Sem ração para; Lago dá 2 vagas de aves |
| 5 Expedições | Garagem animada, 4 veículos, 5 rotas, raridade, minigame, seguro, relatório | Garantia contra azar, seguro, minigame |
| 6 Clima e evento | Agenda por fuso, evento 19–21 h, filtros visuais | 2 contas, 2 fusos |
| 7 Missões e cartas | Missões, pacotes, 10 cartas, Armory, fichário, Colecionador | Garantia, bônus parcial, tetos |
| 8 Multiplayer | Amigos, visitas, ranking, mercado (conteúdo a decidir) | 2 contas no mesmo celular não negociam |
| 9 Painel e antitrapaça | Todas as guias, regras da seção 12, alertas | Forçar cada regra e receber alerta |
| 10 Beta fechado | 20–50 jogadores, 2 semanas, carga 500, segurança, adequação legal | Comparar com simulação, ajustar só pela config |
| 11 Lançamento | Página, termos, privacidade, monitoramento, rollback | Checklist final |

## E. Artes ainda por produzir
- 14 cultivos sem estágios de 16×16 (Cenoura, Batata, Morango + 11 marcados com asterisco).
- 2 mudas de árvore 24×32 e árvores adultas 48×64 (base folhosa e palmeira).
- Celeiro 112×112.
- Veículos: tiras de espera 384×64 (4 quadros de 96×64) e máscaras de raridade.
- 2 ilustrações de carta; itens.
- Revisão final do fundo do mapa (retoque das árvores removidas) na IA de imagens.

## F. Riscos e pontos em aberto
- Capacidade de trabalho por personagem/hora: só o simulador da fase 0 define.
- R precisa ser remedido com 30 lotes; os preços acompanham sozinhos, mas as metas têm de continuar valendo.
- Conteúdo do mercado entre jogadores (fase 8) muda a meta do Armory.
- Legal: ECA Digital e LGPD (seção 15), validar com advogado antes de cobrar algo; pacotes de cartas nunca vendidos.
- Fora do escopo agora: VIP, passe de batalha, skins, Steam.
