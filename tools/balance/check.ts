// Checagens automáticas da config de mapa e lotes. Sai com erro se alguma regra quebrar.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { round2, R } from './land-model.ts';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p: string) => JSON.parse(readFileSync(join(root, p), 'utf8'));
const levels = read('config/levels.json');
const lots = read('config/lots.json');
const map = read('config/mapConfig.json');
const gdd = readFileSync(join(root, 'docs', 'GDD.md'), 'utf8');

let fails = 0;
const check = (ok: boolean, msg: string) => {
  console.log(`${ok ? 'ok  ' : 'FALHA'} ${msg}`);
  if (!ok) fails++;
};

// níveis
check(levels.levels.length === 50 && levels.max_level === 50, 'levels.json tem os níveis 1 a 50');

// mapa
const byId = new Map<string, any>(map.lots.map((l: any) => [l.id, l]));
const count = (t: string) => map.lots.filter((l: any) => l.type === t).length;
check(map.lots.length === 30, 'mapa tem 30 lotes');
check(count('lavoura') === 21 && count('pomar') === 6 && count('pasto_galinheiro') === 1 && count('pasto_celeiro') === 1 && count('pasto_lago') === 1,
  '21 lavouras, 6 pomares, Galinheiro, Celeiro e Lago');
check(map.lots.every((l: any) => l.neighbors.every((n: string) => byId.get(n)?.neighbors.includes(l.id))), 'vizinhança é simétrica');
check(map.lots.filter((l: any) => l.type === 'lavoura').every((l: any) => l.plots.length === 8), 'toda lavoura tem 8 canteiros');
check(map.lots.filter((l: any) => l.type === 'pomar').every((l: any) => l.tree_slots.length === 4), 'todo pomar tem 4 vagas de árvore');
const zones = map.functional_zones.map((z: any) => z.id).sort().join(',');
check(zones === 'barraca_comerciante,casa_principal,garagem_expedicao,oficina_ferreiro', 'zonas: casa, forja, barraca e garagem');

// tabela de compras
const { rules, purchases, simulated_order: order, model_check: mc } = lots;
check(purchases.length === 29, '29 compras');
let formulaOk = true, increasing = true;
purchases.forEach((p: any, i: number) => {
  const L = Math.min(50, Math.ceil(rules.min_level.k * p.n - 1e-9));
  const cost = round2(rules.cost.base * Math.pow(rules.cost.growth, p.n - 1) * R[L]);
  if (p.min_level !== L || p.cost !== cost) formulaOk = false;
  if (i > 0 && p.cost <= purchases[i - 1].cost) increasing = false;
});
check(formulaOk, 'cada custo e nível batem com a fórmula');
check(increasing, 'custo sobe a cada compra');
check(purchases[28].min_level <= 50, `última compra pede nível ${purchases[28].min_level} (máximo 50)`);
check(purchases.filter((p: any) => p.requires_deed).length === 10, '10 Escrituras no total');
check(Math.max(...purchases.map((p: any) => p.cleanup_minutes_blacksmith)) <= 480, 'nenhuma limpeza passa de 8 h');

// ordem simulada: vizinhança, pisos e todos os lotes
const owned = new Set([rules.start_lot]);
const exempt = new Set(rules.adjacency.exempt_types);
let adjOk = true, floorOk = true;
for (const o of order) {
  const lot = byId.get(o.lot_id);
  if (!exempt.has(lot.type) && !lot.neighbors.some((n: string) => owned.has(n))) adjOk = false;
  if ((rules.min_level.type_floor[lot.type] ?? 0) > o.min_level) floorOk = false;
  owned.add(o.lot_id);
}
check(adjOk, 'ordem simulada respeita a vizinhança a partir do A1');
check(floorOk, 'ordem simulada respeita os pisos de nível por tipo');
check(owned.size === 30, 'ordem simulada compra todos os 29 lotes');

// metas da seção 14 no modelo
check(mc.regular.map_complete_day >= 65 && mc.regular.map_complete_day <= 85, `regular completa o mapa no dia ${mc.regular.map_complete_day} (65 a 85)`);
check(mc.regular.max_gold_wait_days <= 4, `regular espera no máximo ${mc.regular.max_gold_wait_days} dias por um lote (até 4)`);
check(mc.casual.max_gold_wait_days <= 8, `casual espera no máximo ${mc.casual.max_gold_wait_days} dias (até 8)`);

// documento x config
const fmt = (x: number) => x.toLocaleString('pt-BR');
let docOk = true;
for (const o of order) {
  const row = new RegExp(`\\| ${o.n} \\| ${o.lot_id} \\| [^|]+ \\| ${o.min_level} \\| ${fmt(o.cost).replace(/\./g, '\\.')} \\|`);
  if (!row.test(gdd)) { docOk = false; console.log('   linha diferente no GDD: compra', o.n); }
}
check(docOk, 'tabela da seção 5 do GDD bate com config/lots.json');

// ---------- cultivos (seção 6) ----------
const cropsCfg = read('config/crops.json');
const crops: any[] = cropsCfg.crops;
const target = (L: number) => 60 * Math.pow(1.07, L - 1);
check(crops.length === 50, '50 cultivos');
check(new Set(crops.map((c) => c.unlock_level)).size === 49 && crops.filter((c) => c.unlock_level === 1).length === 2,
  '1 cultivo novo por nível (2 no nível 1)');
let goldOk = true, seedOk = true;
const xpRate: { L: number; kind: string; rate: number }[] = [];
for (const c of crops) {
  const v = c.units_per_harvest * c.fair_price_per_unit; // valor de 1 colheita
  let goldH: number, seedRatio: number, xpH: number;
  if (c.kind === 'crop') {
    const h = c.grow_minutes / 60;
    goldH = (v - c.seed_cost) / h; seedRatio = c.seed_cost / (0.25 * v); xpH = c.xp_per_harvest / h;
  } else if (c.kind === 'recurring') {
    const h = (c.grow_minutes + 4 * c.regrow_minutes) / 60;
    goldH = (5 * v - c.seed_cost) / h; seedRatio = c.seed_cost / v; xpH = (5 * c.xp_per_harvest) / h;
  } else {
    const h = c.regrow_minutes / 60; // árvore = 2 canteiros
    goldH = v / h / 2; seedRatio = c.sapling_cost / (6 * v); xpH = c.xp_per_harvest / h / 2;
  }
  const dev = goldH / target(c.unlock_level) - 1;
  if (Math.abs(dev) > 0.15) { goldOk = false; console.log(`   ${c.name_pt}: ouro/h ${(dev * 100).toFixed(1)}% do alvo`); }
  if (Math.abs(seedRatio - 1) > 0.05) { seedOk = false; console.log(`   ${c.name_pt}: semente/muda fora da regra`); }
  xpRate.push({ L: c.unlock_level, kind: c.kind, rate: xpH });
}
check(goldOk, 'ouro/h de cada cultivo dentro de ±15% do alvo 60 × 1,07^(n−1)');
check(seedOk, 'sementes e mudas dentro da regra (até 5%)');
// XP/h da lavoura: ajuste exponencial; recorrentes e árvores têm de ficar a ±10%
const lav = xpRate.filter((x) => x.kind === 'crop');
const n = lav.length, sx = lav.reduce((s, x) => s + x.L, 0), sy = lav.reduce((s, x) => s + Math.log(x.rate), 0);
const sxx = lav.reduce((s, x) => s + x.L * x.L, 0), sxy = lav.reduce((s, x) => s + x.L * Math.log(x.rate), 0);
const b = (n * sxy - sx * sy) / (n * sxx - sx * sx), a = (sy - b * sx) / n;
const worstXp = Math.max(...xpRate.filter((x) => x.kind !== 'crop').map((x) => Math.abs(x.rate / Math.exp(a + b * x.L) - 1)));
check(worstXp <= 0.10, `XP/h de recorrentes e árvores a até ${(worstXp * 100).toFixed(1)}% da lavoura do mesmo nível (limite 10%)`);
check(cropsCfg.rules.orchard.remove_tree_cost === 0, 'derrubar árvore é grátis');

// ---------- animais ----------
const an = read('config/animals.json');
check(an.animals.length === 10, '10 animais');
let anOk = true;
for (const x of an.animals) {
  const perH = x.product.fair_price_per_unit / (x.produce_every_minutes / 60);
  const plots = perH / target(x.unlock_level), feed = x.feed_cost_per_day / 24 / perH;
  if (plots < 2.8 || plots > 3.2 || feed < 0.13 || feed > 0.17 || x.buy_cost !== 10 * x.feed_cost_per_day) {
    anOk = false; console.log(`   ${x.name_pt}: ${plots.toFixed(2)} canteiros, ração ${(feed * 100).toFixed(1)}%`);
  }
}
check(anOk, 'cada animal ≈ 3 canteiros, ração 13–17%, compra = 10 dias de ração');
check(an.rules.lake_bonus.bird_production === 0.1 && an.rules.lake_bonus.extra_galinheiro_slots === 2, 'Lago: +10% nas aves e +2 vagas');
// pisos de nível dos pastos e pomar = primeiro animal/fruta da casa
const firstLevel = (pred: (x: any) => boolean, list: any[]) => Math.min(...list.filter(pred).map((x) => x.unlock_level));
const floors = rules.min_level.type_floor;
check(floors.pasto_galinheiro === firstLevel((x) => x.house === 'galinheiro', an.animals)
  && floors.pasto_celeiro === firstLevel((x) => x.house === 'celeiro', an.animals)
  && floors.pomar === firstLevel((x) => x.kind === 'orchard', crops)
  && floors.pasto_lago === firstLevel((x) => x.name_pt === 'Pato', an.animals),
  'pisos dos lotes = nível do 1º animal/fruta (Galinheiro 3, Celeiro 8, Pomar 10, Lago 11)');

// ---------- seção 6 do GDD x config ----------
let s6ok = true;
const fmtN = (x: number) => (Number.isInteger(x) ? x.toLocaleString('pt-BR') : x.toLocaleString('pt-BR', { maximumFractionDigits: 1 }));
for (const c of crops) {
  const seed = c.seed_cost ?? c.sapling_cost;
  const esc = (t: string) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const row = new RegExp(`\\| ${esc(c.name_pt)}( \\*)? \\| ${c.unlock_level} \\|.*\\| ${esc(fmtN(c.units_per_harvest))} \\| ${esc(fmtN(c.fair_price_per_unit))} \\| ${esc(fmtN(seed))} \\| ${esc(fmtN(c.xp_per_harvest))} \\|`);
  if (!row.test(gdd)) { s6ok = false; console.log('   linha diferente no GDD:', c.name_pt); }
}
check(s6ok, 'tabela de cultivos da seção 6 do GDD bate com config/crops.json');

if (fails) { console.log(`\n${fails} falha(s)`); process.exit(1); }
console.log('\ntudo verde');
