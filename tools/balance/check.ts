// Checagens automáticas da config de mapa e lotes. Sai com erro se alguma regra quebrar.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { round2, R } from './land-model.ts';
import { buildMapRules } from '../db/map-rules.ts';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p: string) => JSON.parse(readFileSync(join(root, p), 'utf8'));
const levels = read('config/levels.json');
const lots = read('config/lots.json');
const map = read('config/mapConfig.json');
const farm = read('config/farm.json');
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

// ---------- cartas (seção 11) ----------
const cards = read('config/cards.json');
check(cards.cards.length === 10 && new Set(cards.cards.map((c: any) => c.illustration_slot)).size === 10, '10 cartas, cada uma com 1 ilustração');
const pct = (v: number) => `${v}%`;
let cardsOk = true;
for (const c of cards.cards) {
  // primeiro número de cada raridade na linha da carta no GDD (ex.: "| Sol de Verão | ... | +15% | +20% |")
  const line = gdd.split('\n').find((l) => l.startsWith(`| ${c.name_pt} `) && l.split('|').length >= 9);
  if (!line) { cardsOk = false; console.log('   carta sem linha no GDD:', c.name_pt); continue; }
  const cellsTxt = line.split('|').slice(3, 8).map((t) => t.trim());
  const rar = ['common', 'uncommon', 'rare', 'legendary', 'mythic'];
  rar.forEach((r, k) => {
    const first = Object.values(c.buff_effects[r])[0] as number;
    const nums = (cellsTxt[k].match(/\d+/g) ?? []).map(Number);
    const special = cellsTxt[k].includes('sem'); // "sem perda" / "sem gasto" = 100
    if (!(nums.includes(first) || (special && first === 100))) { cardsOk = false; console.log(`   ${c.name_pt} ${r}: config ${pct(first)} x GDD "${cellsTxt[k]}"`); }
  });
}
check(cardsOk, 'buffs de config/cards.json batem com a tabela da seção 11');
check(cards.rarities.common.duration_minutes === 60 && cards.rarities.mythic.duration_minutes === 150, 'duração dos buffs: Comum 1 h, Mítico 2 h 30');

// ---------- ferramentas e itens (seção 7) ----------
const tools = read('config/tools_and_items.json');
let toolsOk = true;
for (const m of tools.tool_materials) {
  const row = new RegExp(`\\| ${m.name_pt} \\| ${m.unlock_level} \\| ×${m.work_capacity_multiplier.toFixed(1).replace(".", ",")} \\| ${m.upgrade_cost_gold ? fmt(m.upgrade_cost_gold).replace(/\./g, '\\.') : 'inicial'} \\|`);
  if (!row.test(gdd)) { toolsOk = false; console.log('   material diferente no GDD:', m.name_pt); }
}
check(toolsOk, 'materiais das ferramentas batem com a tabela da seção 7');
check(tools.tool_durability_rules.loss_per_work_hour === 2.5, 'ferramenta perde 2,5 de durabilidade por hora');

// ---------- raridade global (seção 9) ----------
const rarity = read('config/rarity.json');
const multTxt = rarity.tiers.map((t: any) => `| ${t.name_pt} | ${t.color_hex} | ×${String(t.multiplier).replace('.', ',')} |`);
check(multTxt.every((t: string) => gdd.includes(t)), 'multiplicadores de raridade batem com a seção 9');
const odds = Object.values(rarity.animals.purchase_odds) as number[];
check(Math.abs(odds.reduce((a, b) => a + b, 0) - 1) < 1e-9, 'chances de raridade dos animais somam 100%');
const avg = rarity.tiers.reduce((s: number, t: any) => s + t.multiplier * rarity.animals.purchase_odds[t.id], 0);
check(gdd.includes(`×${avg.toFixed(2).replace('.', ',')}`), `média dos animais ×${avg.toFixed(3)} citada no GDD`);

// ---------- artes: toda chave usada na config existe no manifest ----------
const sprites = read('public/assets/sprites/manifest.json').sprites;
const keys = [
  ...cards.cards.flatMap((c: any) => [c.sprite_key, c.icon_key]), ...Object.values(cards.frames),
  ...tools.class_tool_cards.flatMap((t: any) => tools.tool_materials.map((m: any) => `${t.id}_${m.id}`)),
  ...['clothing_cards', 'amulet_cards', 'snack_cards'].flatMap((k) => tools[k].map((i: any) => i.id)),
  ...crops.flatMap((c: any) => [c.art.ready_sprite, c.art.seed_bag].filter(Boolean)),
  ...['carroca', 'carro', 'picape', 'caminhao'].flatMap((v) => [`vehicle_${v}_idle`, ...rarity.tiers.map((t: any) => `vehicle_${v}_${t.id}`)]),
  'building_celeiro', 'building_galinheiro', 'tree_leafy_sapling', 'tree_leafy_adult', 'tree_palm_sapling', 'tree_palm_adult',
  'lot_sign', 'item_deed', ...farm.visual.debris_sprites, ...tools.tool_materials.map((m: any) => `tool_hoe_${m.id}`),
];
const missing = keys.filter((k: string) => !sprites[k]);
if (missing.length) console.log('   faltam:', missing.join(', '));
check(!missing.length, `as ${keys.length} artes citadas na config existem em public/assets/sprites`);

// ---------- fase 2: regras do mapa no servidor, pomar e cultivos por nível ----------
check(JSON.stringify(read('config/map_rules.json')) === JSON.stringify(buildMapRules()), 'config/map_rules.json em dia com mapConfig.json (rode npx tsx tools/db/map-rules.ts)');
const orchard = crops.filter((c: any) => c.kind === 'orchard');
check(orchard.every((c: any) => /^#[0-9a-f]{6}$/i.test(farm.visual.fruit_hex[c.id] ?? '') && farm.visual.fruit_dots[c.tree_base]?.length),
  `as ${orchard.length} frutas têm cor e posição das frutas na árvore (farm.json)`);
check(crops.filter((c: any) => c.kind !== 'orchard' && c.unlock_level === 1).length >= 2, 'nível 1 já tem cultivos de canteiro');

// ---------- simulador (seção 14): critérios de aceite ----------
const rep = read('tools/sim/report.json');
const P = rep.profiles;
check(P.regular.map_complete_day >= 65 && P.regular.map_complete_day <= 85, `simulador: regular completa o mapa no dia ${P.regular.map_complete_day} (65 a 85)`);
check(P.regular.level50_day >= 95 && P.regular.level50_day <= 125, `simulador: regular no nível 50 no dia ${P.regular.level50_day} (95 a 125)`);
check(P.casual.max_gold_wait_days <= 8, `simulador: casual espera no máximo ${P.casual.max_gold_wait_days} dias por um lote (até 8)`);
check(P.regular.salaries_share >= 0.08 && P.regular.salaries_share <= 0.18, `simulador: salários do regular = ${(P.regular.salaries_share * 100).toFixed(1)}% da renda (8% a 18%)`);
check(P.regular.armory_all_partial_week_median >= 25 && P.regular.armory_all_partial_week_median <= 40, `simulador: bônus parcial nas 10 cartas na semana ${P.regular.armory_all_partial_week_median} (25 a 40, sem mercado)`);
// as metas publicadas (seção 14) com até 10% de diferença
const near = (v: number, t: number) => Math.abs(v / t - 1) <= 0.1;
check(near(P.regular.map_complete_day, 77) && near(P.casual.map_complete_day, 108) && near(P.dedicated.map_complete_day, 71) && near(P.regular.level30_day, 33) && near(P.regular.level50_day, 113),
  'simulador reproduz as metas da seção 14 com até 10% de diferença');
check(crops.length > 0 && cropsCfg.rules.work_units.per_character_per_hour === rep.work_per_character_hour, `capacidade de trabalho calibrada (${rep.work_per_character_hour}) gravada em crops.json`);
// o relatório tem de ser da config atual: roda o regular de novo (1 semente) e compara
{
  const { simulate } = await import('../sim/model.ts');
  const Rnow: number[] = []; for (const l of levels.levels) Rnow[l.level] = l.reference_income_per_day;
  const r = simulate('regular', { workPerHour: rep.work_per_character_hour, R: Rnow, seed: 7 });
  check(Math.abs(r.mapCompleteDay - P.regular.map_complete_day) <= 3 && Math.abs((r.levelDay[50] ?? 999) - P.regular.level50_day) <= 3,
    `relatório do simulador está em dia com a config (regular: mapa ${r.mapCompleteDay.toFixed(1)}, nível 50 ${(r.levelDay[50] ?? 0).toFixed(1)})`);
}

// ---------- expedições (seção 8) ----------
const ex = read('config/expeditions.json');
const evRoute = (r: any) => r.price_multiplier * (r.success + (1 - r.success) * (1 - (r.loss[0] + r.loss[1]) / 2));
const evs = ex.routes.map(evRoute);
check(evs.every((v: number, i: number) => i === 0 || v > evs[i - 1]), `valor médio por rota sempre cresce da Feira à Exportação (${evs.map((v: number) => v.toFixed(2)).join(' < ')})`);
const insOk = ex.routes.filter((r: any) => r.insurance_pct).every((r: any) => {
  const fail = 1 - r.success, lossAbove = (r.loss[0] + r.loss[1]) / 2 - 0.10;
  return fail * lossAbove - r.insurance_pct / 100 < 0;
});
check(insOk, 'seguro nunca tem média positiva');
check(ex.minigame.result_pts.perfect <= 3 && ex.minigame.result_pts.failed >= -10, 'minigame: Perfeita até +3, não concluir até −10');
const lua = read('config/weather.json').night_event.events.find((e: any) => e.id === 'lua_cheia');
check((lua.sales_gold_pct / 100) * lua.cap_R_ratio <= 0.02, 'Lua Cheia rende no máximo 2% da renda para quem segura vendas');

if (fails) { console.log(`\n${fails} falha(s)`); process.exit(1); }
console.log('\ntudo verde');
