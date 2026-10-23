# Gera o texto da seção 6 do GDD a partir de config/crops.json e config/animals.json
import json, sys
crops = json.load(open('config/crops.json'))['crops']
an = json.load(open('config/animals.json'))
def br(x):
    s = f'{x:,.1f}' if isinstance(x, float) and not float(x).is_integer() else f'{int(x):,}'
    return s.replace(',', 'X').replace('.', ',').replace('X', '.')
def dur(m):
    if m is None: return '—'
    if m < 60: return f'{m} min'
    h = m / 60
    return f'{br(h) if not h.is_integer() else int(h)} h'
KIND = {'crop': 'Lavoura', 'recurring': 'Recorrente', 'orchard': 'Pomar'}
L = []
L.append('## 6. Cultivos e animais 🆕 (completa)\n')
L.append('Um cultivo novo libera a cada nível, do 1 ao 49 (o nível 1 tem 2: Alface e Cenoura), 50 no lançamento. O melhor cultivo de cada nível rende cerca de 60 × 1,07^(nível−1) de ouro por hora por canteiro, já descontada a semente (1 árvore = 2 canteiros, então 4 árvores = 1 lote de 8 canteiros). Novos cultivos e animais entram depois só pela config (`config/crops.json` e `config/animals.json`).\n')
L.append('- **Lavoura:** 1 colheita por plantio. Semente = 25% do valor da colheita.')
L.append('- **Recorrente:** 5 colheitas por plantio (a 1ª em "Cresce", as outras a cada "Rebrota"). Semente = valor de 1 colheita. 🆕 O XP da tabela abaixo é por colheita: o número original era do plantio inteiro e foi dividido por 5 (ex.: Morango 190 por plantio = 38 por colheita). Lido como "por colheita", os recorrentes davam 5× mais XP por hora que os outros cultivos.')
L.append('- **Pomar:** árvore permanente, só em lote de pomar (4 vagas por terraço); produz a cada "Rebrota" depois de crescer. Muda = 6 colheitas. 🆕 O jogador pode **derrubar uma árvore de graça** para plantar outra fruta; a nova muda é paga e cresce do zero. Sem isso, uma Maçã do nível 10 ocuparia para sempre a vaga de uma Jabuticaba (14× mais ouro por hora).')
L.append('- **Trabalho:** cada plantio + colheita gasta 1 unidade de trabalho; colheita extra de recorrente ou de árvore gasta 0,5. Culturas curtas rendem um pouco mais ouro por hora, mas gastam muito mais trabalho; as longas vencem em fazendas grandes e offline. Essa troca é o coração da escolha do que plantar. Com 30 lotes há 168 canteiros e 24 árvores (antes 136 e 20). 🆕 Quantas unidades de trabalho um personagem faz por hora (ferramenta de Madeira) é calibrado no simulador da fase 0 para bater as metas da seção 14.')
L.append('- **Colheita Dourada:** chance pequena (cartas e habilidades) de a colheita valer 2,5×. Máximo 20% somando os bônus permanentes e 60% com cartas e evento (tetos da seção 11).')
L.append('- Preço por unidade = preço base na Feira da Vila (expedição nível 1). Os operadores nos slots replantam sozinhos o último cultivo escolhido em cada canteiro, comprando semente automaticamente.\n')
L.append('**Conferência automática** (`npm run balance:check`): ouro por hora de todos os cultivos entre −12% e +13% do alvo (curtas, até 2 h: +4% em média; longas, 6 h ou mais: −9%); sementes e mudas 100% dentro da regra; XP por hora de recorrentes e árvores igual ao da lavoura do mesmo nível (±3%).\n')
L.append('| Cultivo | Nível | Tipo | Cresce | Rebrota | Unid./colheita | Preço/unid. | Semente ou muda | XP/colheita |')
L.append('| --- | --- | --- | --- | --- | --- | --- | --- | --- |')
for c in crops:
    name = c['name_pt'] + (' *' if not c['art']['icon'] else '')
    seed = c.get('seed_cost', c.get('sapling_cost'))
    L.append(f"| {name} | {c['unlock_level']} | {KIND[c['kind']]} | {dur(c['grow_minutes'])} | {dur(c['regrow_minutes'])} | {c['units_per_harvest']} | {br(c['fair_price_per_unit'])} | {br(seed)} | {br(c['xp_per_harvest'])} |")
L.append('\n\\* arte ainda não existe (seção 4).\n')
L.append('### Animais\n')
L.append('Cada animal rende cerca de 3 canteiros (2,9 a 3,1, valor bruto). A Rancheira em campo coleta a 100%; outra classe, a 60%. A ração (≈15% da produção) é descontada sozinha; sem ouro para ração, o animal para de produzir (nunca morre). Comprar um animal custa 10 dias de ração. Cada casa começa com 4 vagas e amplia para 8 e 12.\n')
L.append('**Lago 🆕:** +10% na produção das aves do Galinheiro (Galinha, Pato, Ganso e Peru) e **+2 vagas no Galinheiro, só para aves** (4 → 6, 8 → 10, 12 → 14). Só com o +10% o Lago valia 0,37 de um lote de lavoura comprado no mesmo momento (0,20 se comprado por último); com as vagas passa a 0,89, sem passar do teto de produção animal (+60%).\n')
L.append('| Animal | Nível | Casa | Produto | A cada | Preço do produto | Ração/dia | Compra | XP/coleta |')
L.append('| --- | --- | --- | --- | --- | --- | --- | --- | --- |')
for a in an['animals']:
    L.append(f"| {a['name_pt']} | {a['unlock_level']} | {a['house'].capitalize()} | {a['product']['name_pt']} | {dur(a['produce_every_minutes'])} | {br(a['product']['fair_price_per_unit'])} | {br(a['feed_cost_per_day'])} | {br(a['buy_cost'])} | {br(a['xp_per_collect'])} |")
L.append('')
g, c = an['houses']['galinheiro']['slots'], an['houses']['celeiro']['slots']
L.append('| Ampliação | Galinheiro | Celeiro |')
L.append('| --- | --- | --- |')
for i in (1, 2):
    L.append(f"| {g[i]['slots']} vagas | nível {g[i]['min_level']} · {br(g[i]['cost'])} | nível {c[i]['min_level']} · {br(c[i]['cost'])} |")
L.append('\nAs ampliações custam 0,8 R (8 vagas) e 1,6 R (12 vagas), sobre a Renda de Referência do nível exigido.\n')
sys.stdout.write('\n'.join(L) + '\n')
