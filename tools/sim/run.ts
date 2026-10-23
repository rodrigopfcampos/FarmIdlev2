// Roda o simulador, calibra a curva de XP e remede a Renda de Referência (R) com os 30 lotes.
// A capacidade de trabalho do Agricultor (C) fica fixa na config; com o jogo aberto o jogador colhe e planta por clique.
// Uso: npm run sim            → só mostra o resultado com a config atual
//      npm run sim -- --calibrate          → calibra as escalas de XP e R (ponto fixo) e mostra
//      npm run sim -- --calibrate --write  → grava levels.json (XP e R), lots.json (preços) e tools/sim/report.json
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { simulate, armoryPartialWeek, xpTable, CFG, SIM, type SimResult } from './model.ts';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const args = process.argv.slice(2);
const round2 = (x: number) => { const p = Math.pow(10, Math.floor(Math.log10(x)) - 1); return Math.round(x / p) * p; };
const SEEDS = [7, 11, 23, 42, 99];

let R: number[] = [];
for (const l of CFG.levels.levels) R[l.level] = l.reference_income_per_day;
const C: number = CFG.crops.rules.work_units.per_character_per_hour;
const BANDS = CFG.levels.xp_curve.bands as { levels: [number, number]; scale: number; target: string }[];
let SCALES: number[] = BANDS.map((b) => b.scale);

const avg = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;
function runMany(profile: string, c: number, r: number[], scales = SCALES) {
  const xpNext = xpTable(scales);
  const rs = SEEDS.map((seed) => simulate(profile, { workPerHour: c, R: r, seed, xpNext }));
  const lvDay = (L: number) => avg(rs.map((x) => x.levelDay[L] ?? 999));
  return { rs, lvDay, level10: lvDay(10), level30: avg(rs.map((x) => x.levelDay[30] ?? 999)), level50: avg(rs.map((x) => x.levelDay[50] ?? 999)),
    map: avg(rs.map((x) => x.mapCompleteDay)), wait: avg(rs.map((x) => x.maxGoldWait)),
    salaries: avg(rs.map((x) => x.salaries / x.income)), repairs: avg(rs.map((x) => x.toolRepairs / x.income)) };
}

// escalas de XP, uma por faixa: cada uma põe o regular no nível seguinte ao fim da faixa no dia-alvo
function bisect(f: (k: number) => number, target: number): number {
  let lo = 0.05, hi = 20;
  for (let i = 0; i < 22; i++) { const mid = Math.sqrt(lo * hi); if (f(mid) > target) hi = mid; else lo = mid; }
  return +Math.sqrt(lo * hi).toFixed(3);
}
function calibrateScales(r: number[]): void {
  BANDS.forEach((b, i) => {
    SCALES[i] = bisect((k) => { const s = [...SCALES]; s[i] = k; return runMany('regular', C, r, s).lvDay(b.levels[1] + 1); }, SIM.targets.regular[b.target]);
  });
}

// R medido: renda média por dia em cada nível (regular), suavizada e sempre crescente
function measureR(rs: SimResult[]): number[] {
  const out: number[] = [];
  const raw: number[] = [], w: number[] = [];
  for (let L = 1; L <= 50; L++) {
    const inc = avg(rs.map((x) => x.incomeByLevel[L])), d = avg(rs.map((x) => x.daysByLevel[L]));
    raw[L] = d >= SIM.r_min_days_at_level ? inc / d : NaN; w[L] = d;
  }
  // níveis que passam rápido demais (o começo) não dão medida: interpola em escala log entre os vizinhos medidos
  const ok = (L: number) => raw[L] > 0;
  for (let L = 1; L <= 50; L++) {
    if (ok(L)) continue;
    let a = L - 1; while (a >= 1 && !ok(a)) a--;
    let b = L + 1; while (b <= 50 && !ok(b)) b++;
    if (a >= 1 && b <= 50) { raw[L] = Math.exp(Math.log(raw[a]) + ((L - a) / (b - a)) * (Math.log(raw[b]) - Math.log(raw[a]))); w[L] = SIM.r_min_days_at_level; }
  }
  for (let L = 1; L <= 50; L++) {
    // média geométrica ponderada pelos dias em L−1, L e L+1
    let s = 0, ws = 0;
    for (const k of [L - 1, L, L + 1]) if (k >= 1 && k <= 50 && raw[k] > 0) { const ww = Math.max(w[k], 0.05) * (k === L ? 2 : 1); s += ww * Math.log(raw[k]); ws += ww; }
    out[L] = ws ? Math.exp(s / ws) : out[L - 1];
  }
  for (let L = 2; L <= 50; L++) if (!(out[L] >= out[L - 1])) out[L] = out[L - 1];
  return out.map((x) => (x ? round2(x) : x));
}

function show(label: string, c: number, r: number[]) {
  console.log(`\n${label} · C = ${c} unidades por personagem por hora (Madeira) · XP por faixa ×${SCALES.join(' / ×')}`);
  const res: Record<string, ReturnType<typeof runMany>> = {};
  for (const p of ['casual', 'regular', 'dedicated']) {
    res[p] = runMany(p, c, r);
    const m = res[p];
    console.log(`  ${SIM.profiles[p].name_pt.padEnd(9)} Armory parcial nas 10: semana ${medianWeek(p)} (mediana) ·`);
    console.log(`  ${SIM.profiles[p].name_pt.padEnd(9)} nível 10 dia ${m.level10.toFixed(2)} · nível 30 dia ${m.level30.toFixed(1)} · nível 50 dia ${m.level50.toFixed(1)} · mapa completo dia ${m.map.toFixed(1)} · maior espera ${m.wait.toFixed(1)} d · salários ${(100 * m.salaries).toFixed(1)}% · consertos ${(100 * m.repairs).toFixed(1)}%`);
  }
  return res;
}

if (!args.includes('--calibrate')) {
  show('Config atual', C, R);
} else {
  for (let it = 1; it <= 15; it++) {
    calibrateScales(R);
    const reg = runMany('regular', C, R);
    const Rn = measureR(reg.rs);
    const change = Math.max(...Rn.slice(1).map((x, i) => Math.abs(x / R[i + 1] - 1)));
    console.log(`iteração ${it}: XP ×${SCALES.join(' / ×')} · nível 10 dia ${reg.level10.toFixed(2)} · nível 50 dia ${reg.level50.toFixed(1)} · mapa dia ${reg.map.toFixed(1)} · R muda até ${(change * 100).toFixed(1)}%`);
    R = R.map((x, L) => (L ? round2(Math.sqrt(x * Rn[L])) : x)); // amortecido
    // arredondar R em 2 algarismos faz um nível oscilar até ~10%: isso já é convergência
    if (change < 0.03 || (it >= 4 && change <= 0.105)) break;
  }
  calibrateScales(R);
  const res = show('Calibrado', C, R);
  if (args.includes('--dump-r')) console.log('R=' + JSON.stringify(R));
  if (args.includes('--write')) write(res);
}

// mediana de 1.000 sorteios só de cartas
function medianWeek(p: string): number {
  const w = Array.from({ length: 1000 }, (_, i) => armoryPartialWeek(p, i + 1)).sort((a, b) => a - b);
  return w[500];
}

function write(res: Record<string, ReturnType<typeof runMany>>) {
  // levels.json: nova versão com R remedido e a curva de XP calibrada
  const lv = JSON.parse(readFileSync(join(root, 'config', 'levels.json'), 'utf8'));
  lv.version += 1;
  lv.source = 'GDD v2 seção 9 · R e curva de XP calibrados pelo simulador (tools/sim), com plantio e colheita por clique';
  lv.xp_curve.bands.forEach((b: any, i: number) => { b.scale = SCALES[i]; });
  const xp = xpTable(SCALES);
  for (const l of lv.levels) { l.reference_income_per_day = R[l.level]; l.xp_to_next = Number.isFinite(xp[l.level]) ? xp[l.level] : null; }
  writeFileSync(join(root, 'config', 'levels.json'), JSON.stringify(lv, null, 2) + '\n');
  // lots.json: preços com o R novo e resultado do simulador completo
  const lots = JSON.parse(readFileSync(join(root, 'config', 'lots.json'), 'utf8'));
  const ru = lots.rules;
  const cost = (n: number) => round2(ru.cost.base * Math.pow(ru.cost.growth, n - 1) * R[Math.min(50, Math.ceil(ru.min_level.k * n - 1e-9))]);
  for (const p of lots.purchases) { p.reference_income = R[p.reference_income_level]; p.cost = cost(p.n); }
  const reg = res.regular.rs[0];
  for (const o of lots.simulated_order) { o.cost = cost(o.n); o.regular_day = +(reg.buys.find((b) => b.n === o.n)?.day ?? 0).toFixed(1); }
  lots.version += 1;
  lots.source = 'GDD v2 seção 5 · preços sobre o R remedido pelo simulador (tools/sim)';
  lots.model_check = Object.fromEntries(['regular', 'casual', 'dedicated'].map((p) => [p, { map_complete_day: +res[p].map.toFixed(1), max_gold_wait_days: +res[p].wait.toFixed(1) }]));
  lots.model_check.source = 'tools/sim (simulador completo, média de 5 sementes)';
  writeFileSync(join(root, 'config', 'lots.json'), JSON.stringify(lots, null, 2) + '\n');
  // relatório
  const report = {
    generated_by: 'tools/sim/run.ts', work_per_character_hour: C,
    profiles: Object.fromEntries(Object.entries(res).map(([p, m]) => [p, {
      level10_day: +m.level10.toFixed(2), level30_day: +m.level30.toFixed(1), level50_day: +m.level50.toFixed(1), map_complete_day: +m.map.toFixed(1),
      max_gold_wait_days: +m.wait.toFixed(1), salaries_share: +m.salaries.toFixed(3), tool_repairs_share: +m.repairs.toFixed(3),
      armory_bonus_day160: +avg(m.rs.map((x) => x.armoryBonus)).toFixed(3),
      armory_all_partial_week_median: medianWeek(p), cards: +avg(m.rs.map((x) => x.cards)).toFixed(1),
      vehicles: m.rs[0].vehicleRarity,
    }])),
  };
  writeFileSync(join(root, 'tools', 'sim', 'report.json'), JSON.stringify(report, null, 2) + '\n');
  console.log('\ngravado: config/levels.json, config/lots.json, tools/sim/report.json');
}
