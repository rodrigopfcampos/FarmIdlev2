// Gera config/lots.json: regras de compra, tabela das 29 compras e uma ordem simulada que respeita a vizinhança do mapa.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { makeTable, R } from './land-model.ts';
import { evaluate } from './lots-search.ts';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const map = JSON.parse(readFileSync(join(root, 'config', 'mapConfig.json'), 'utf8'));

// Parâmetros escolhidos pela busca (lots-search.ts): mesmas metas da seção 14 com 29 compras
const PARAMS = { k: 1.44, growth: 1.105, base: 0.29, purchases: 29 };
const DEED_FROM = 20; // Escritura da 20ª compra em diante: continuam 10 Escrituras no total
const TYPE_FLOOR: Record<string, number> = { pasto_galinheiro: 3, pasto_celeiro: 8, pomar: 10, pasto_lago: 11 };
const CLEANUP = { base_minutes: 60, per_purchase_minutes: 12, other_class_multiplier: 2, neighbor_help_reduction: 0.1, max_neighbor_helps_per_day: 5 };

const table = makeTable(PARAMS);
const ev = evaluate(table);

// Ordem simulada por tipo (mesmo ritmo da simulação antiga: pastos cedo, um pomar a cada ~3 compras)
const PLAN = ['lavoura', 'pasto_galinheiro', 'lavoura', 'lavoura', 'pasto_celeiro', 'lavoura', 'pomar', 'lavoura',
  'lavoura', 'pomar', 'lavoura', 'lavoura', 'pomar', 'lavoura', 'lavoura', 'pomar', 'lavoura', 'pasto_lago',
  'lavoura', 'pomar', 'lavoura', 'lavoura', 'pomar', 'lavoura', 'lavoura', 'lavoura', 'lavoura', 'lavoura', 'lavoura'];

type Lot = { id: string; type: string; neighbors: string[] };
const lots: Lot[] = map.lots;
const byId = new Map(lots.map((l) => [l.id, l]));
const exempt = new Set<string>(map.adjacency.exempt_types);
const owned = new Set<string>([map.start_lot]);
// distância (em compras) a partir do lote inicial, para escolher os lotes mais próximos primeiro
const dist = new Map<string, number>([[map.start_lot, 0]]);
const q = [map.start_lot];
while (q.length) {
  const a = q.shift()!;
  for (const b of byId.get(a)!.neighbors) if (!dist.has(b)) { dist.set(b, dist.get(a)! + 1); q.push(b); }
}
const buyable = (l: Lot) => !owned.has(l.id) && (exempt.has(l.type) || l.neighbors.some((n) => owned.has(n)));
const pending: string[] = [];
let lavDebt = 0; // lavouras compradas antes da vez (para abrir caminho até um pomar ou pasto)
const order: any[] = [];
for (let i = 0; i < PARAMS.purchases; i++) {
  const n = i + 1, row = table[i];
  if (PLAN[i] === 'lavoura' && lavDebt > 0) lavDebt--; else pending.push(PLAN[i]);
  // tenta o tipo pendente mais antigo que já possa ser comprado; senão compra uma lavoura que aproxima do pendente
  let pick: Lot | undefined;
  for (const t of pending) {
    const c = lots.filter((l) => l.type === t && buyable(l) && Math.max(row.minLevel, TYPE_FLOOR[t] ?? 0) <= row.minLevel + 0)
      .sort((a, b) => dist.get(a.id)! - dist.get(b.id)! || a.id.localeCompare(b.id, 'en', { numeric: true }));
    if (c.length && (TYPE_FLOOR[t] ?? 0) <= row.minLevel) { pick = c[0]; pending.splice(pending.indexOf(t), 1); break; }
  }
  if (!pick) {
    const targets = lots.filter((l) => pending.includes(l.type) && !owned.has(l.id));
    const near = (l: Lot) => Math.min(...targets.map((t) => (t.neighbors.includes(l.id) ? 0 : 1)), 1);
    const c = lots.filter((l) => l.type === 'lavoura' && buyable(l))
      .sort((a, b) => near(a) - near(b) || dist.get(a.id)! - dist.get(b.id)! || a.id.localeCompare(b.id, 'en', { numeric: true }));
    pick = c[0];
    const li = pending.indexOf('lavoura');
    if (li >= 0) pending.splice(li, 1); else lavDebt++;
  }
  owned.add(pick.id);
  order.push({
    n, lot_id: pick.id, type: pick.type,
    min_level: Math.max(row.minLevel, TYPE_FLOOR[pick.type] ?? 0),
    cost: row.cost, requires_deed: n >= DEED_FROM,
    cleanup_minutes_blacksmith: CLEANUP.base_minutes + CLEANUP.per_purchase_minutes * n,
    regular_day: +ev.reg.days[i].toFixed(1),
  });
}
if (pending.length) throw new Error('tipos que não couberam na ordem: ' + pending.join(', '));
if (owned.size !== lots.length) throw new Error('sobrou lote fora da ordem');

const out = {
  version: 2,
  source: 'GDD v2 seção 5 · gerado por tools/balance/build-lots.ts',
  rules: {
    start_lot: map.start_lot,
    total_lots: lots.length,
    purchases: PARAMS.purchases,
    price_by: 'purchase_count',
    adjacency: map.adjacency,
    min_level: { formula: 'ceil(k * n)', k: PARAMS.k, type_floor: TYPE_FLOOR },
    cost: { formula: 'base * growth^(n-1) * R(ceil(k * n))', base: PARAMS.base, growth: PARAMS.growth, rounding: '2_significant_digits' },
    deed: { required_from_purchase: DEED_FROM, total_needed: PARAMS.purchases - DEED_FROM + 1 },
    cleanup: CLEANUP,
  },
  purchases: table.map((r, i) => ({
    n: r.n, min_level: r.minLevel, reference_income_level: r.minLevel, reference_income: R[r.minLevel],
    cost: r.cost, requires_deed: r.n >= DEED_FROM,
    cleanup_minutes_blacksmith: CLEANUP.base_minutes + CLEANUP.per_purchase_minutes * r.n,
  })),
  simulated_order: order,
  model_check: {
    regular: { map_complete_day: +ev.reg.complete.toFixed(1), max_gold_wait_days: +ev.reg.maxGoldWait.toFixed(1) },
    casual: { map_complete_day: +ev.cas.complete.toFixed(1), max_gold_wait_days: +ev.cas.maxGoldWait.toFixed(1) },
    dedicated: { map_complete_day: +ev.ded.complete.toFixed(1), max_gold_wait_days: +ev.ded.maxGoldWait.toFixed(1) },
  },
};
writeFileSync(join(root, 'config', 'lots.json'), JSON.stringify(out, null, 2) + '\n');
for (const o of order) console.log(o.n, o.lot_id, o.type, 'nível', o.min_level, 'custo', o.cost.toLocaleString('pt-BR'), o.requires_deed ? 'Escritura' : '', 'limpeza', o.cleanup_minutes_blacksmith, 'min', 'dia', o.regular_day);
console.log(JSON.stringify(out.model_check));
