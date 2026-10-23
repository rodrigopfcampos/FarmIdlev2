# Atualiza no GDD as tabelas que vêm da config: lotes (seção 5), contratação e salário (seção 7)
# e níveis/R (seção 9). Uso: python3 tools/balance/gdd_tables.py  (depois rode npm run balance:check)
import json, math, re

root = __file__.rsplit('/tools/', 1)[0]
cfg = lambda n: json.load(open(f'{root}/config/{n}.json'))
levels, lots, chars = cfg('levels'), cfg('lots'), cfg('characters')
R = {l['level']: l['reference_income_per_day'] for l in levels['levels']}
XPN = {l['level']: l['xp_to_next'] for l in levels['levels']}
gdd_path = f'{root}/docs/GDD.md'
s = open(gdd_path).read()

def br(x):  # 1234567 -> 1.234.567 ; 2,5 decimal
    if isinstance(x, float) and not x.is_integer():
        return f'{x:,.1f}'.replace(',', 'X').replace('.', ',').replace('X', '.')
    return f'{int(round(x)):,}'.replace(',', '.')

def round2(x):
    p = 10 ** (math.floor(math.log10(x)) - 1)
    return round(x / p) * p

TYPE = {'lavoura': 'Lavoura', 'pomar': 'Pomar', 'pasto_galinheiro': 'Galinheiro', 'pasto_celeiro': 'Celeiro', 'pasto_lago': 'Lago'}

def replace_rows(text, header_start, make_rows):
    i = text.index(header_start)
    j = text.index('\n', text.index('\n', i) + 1) + 1  # depois da linha de separação
    k = j
    while k < len(text) and text[k] == '|':
        k = text.index('\n', k) + 1
    return text[:j] + make_rows() + text[k:]

# seção 5: tabela de compras
def lot_rows():
    out = []
    for o in lots['simulated_order']:
        m = o['cleanup_minutes_blacksmith']
        out.append(f"| {o['n']} | {o['lot_id']} | {TYPE[o['type']]} | {o['min_level']} | {br(o['cost'])} | {'Sim' if o['requires_deed'] else 'Não'} | {m // 60} h {m % 60:02d} | {br(float(o['regular_day'])) if not float(o['regular_day']).is_integer() else br(o['regular_day'])} |")
    return '\n'.join(out) + '\n'
s = replace_rows(s, '| Compra n | Lote (ordem simulada) |', lot_rows)

# seção 7: contratação
classes = {c['name_pt']: c for c in chars['classes']}
def hire_cell(m):
    name = m.group(1)
    c = classes[name]
    cost = 'grátis' if c.get('hired') else br(round2(chars['hire_cost']['multiplier'] * R[c['unlock_level']]))
    return f"{m.group(0).rsplit('|', 2)[0]}| {cost} |"
s = re.sub(r'^\| (Agricultor|Rancheira|Ferreiro|Comerciante|Gerente|Botânica) \| (?:Enxada|Regador|Martelo|Balança|Prancheta|Lupa) \| [^|]+ \| [^|]+ \| [^|]+ \|$', hire_cell, s, flags=re.M)

# seção 7: salário base por nível da conta
sal = [br(round2(chars['salary']['share_of_R'] * R[L])) for L in range(5, 51, 5)]
s = re.sub(r'^\| Salário base/dia \(ouro\) \|.*$', '| Salário base/dia (ouro) | ' + ' | '.join(sal) + ' |', s, flags=re.M)

# seção 9: níveis e R (duas colunas: 1–25 e 26–50)
def level_rows():
    out = []
    for L in range(1, 26):
        M = L + 25
        out.append(f"| {L} | {br(XPN[L])} | {br(R[L])} | | {M} | {br(XPN[M]) if XPN[M] else '—'} | {br(R[M])} |")
    return '\n'.join(out) + '\n'
s = replace_rows(s, '| Nível | XP para o próximo | R (ouro/dia) |', level_rows)

# fórmula do lote (seção 5)
ru = lots['rules']
k = str(ru['min_level']['k']).replace('.', ',')
g = f"{ru['cost']['growth']:.2f}".replace('.', ',')
b = f"{ru['cost']['base']:.2f}".replace('.', ',')
s = re.sub(r'custo\(n\) = [\d,]+ × [\d,]+\^\(n−1\) × R\(⌈[\d,]+ × n⌉\)', f'custo(n) = {b} × {g}^(n−1) × R(⌈{k} × n⌉)', s)
s = re.sub(r'no nível ⌈[\d,]+ × n⌉, sem o piso', f'no nível ⌈{k} × n⌉, sem o piso', s)
s = re.sub(r'arredondar para cima \([\d,]+ × n\)', f'arredondar para cima ({k} × n)', s)
open(gdd_path, 'w').write(s)
print('GDD atualizado: lotes, contratação, salários e níveis')
