// Modelo de terreno: substituto do simulador completo enquanto a seção 6 (cultivos e animais) não chega.
// Ele usa só o que a simulação antiga já mediu (XP por nível e Renda de Referência R),
// calibra-se nos resultados publicados da tabela antiga (24 compras) e testa a tabela nova (29 compras).
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const levelsCfg = JSON.parse(readFileSync(join(root, 'config', 'levels.json'), 'utf8'));
const XP: number[] = []; // XP para passar do nível L para L+1 (índice = nível)
const R: number[] = []; // Renda de Referência por dia (índice = nível)
for (const l of levelsCfg.levels) {
  XP[l.level] = l.xp_to_next ?? Infinity;
  R[l.level] = l.reference_income_per_day;
}
const MAX_LEVEL = levelsCfg.max_level as number;

// ---------- Curva de nível x dia ----------
// XP por dia no nível L = a * R(L)^b * fator do perfil. a e b saem das metas publicadas:
// jogador regular no nível 30 no dia 33 e no nível 50 no dia 113.
function sumDays(a: number, b: number, upTo: number, factor = 1): number {
  let d = 0;
  for (let L = 1; L < upTo; L++) d += XP[L] / (a * Math.pow(R[L], b) * factor);
  return d;
}
function fitXpCurve(): { a: number; b: number } {
  let lo = 0, hi = 2;
  for (let i = 0; i < 80; i++) {
    const b = (lo + hi) / 2;
    const ratio = sumDays(1, b, 50) / sumDays(1, b, 30); // não depende de a
    if (ratio > 113 / 33) lo = b; else hi = b;
  }
  const b = (lo + hi) / 2;
  const a = sumDays(1, b, 30) / 33;
  return { a, b };
}
export const XP_CURVE = fitXpCurve();

export type Profile = { name: string; factor: number };
function levelTimes(factor: number): number[] {
  const t: number[] = [0, 0];
  for (let L = 1; L < MAX_LEVEL; L++) t[L + 1] = t[L] + XP[L] / (XP_CURVE.a * Math.pow(R[L], XP_CURVE.b) * factor);
  return t;
}

// ---------- Compra de lotes ----------
export type LotRow = { n: number; minLevel: number; cost: number };
export type RunResult = {
  complete: number; // dia da última compra
  maxGoldWait: number; // maior espera por ouro de um lote (dias)
  maxStuck: number; // maior intervalo entre duas compras (dias)
  buys: { n: number; day: number; level: number; goldWait: number }[];
};

/** share = fração da renda que vai para terreno (calibrada); xpFactor/incomeFactor = ritmo do perfil. */
export function run(table: LotRow[], share: number, xpFactor: number, incomeFactor = xpFactor, dt = 0.005): RunResult {
  const factor = incomeFactor;
  const tl = levelTimes(xpFactor);
  const levelAt = (t: number) => {
    let L = 1;
    while (L < MAX_LEVEL && tl[L + 1] <= t) L++;
    return L;
  };
  let budget = 0, t = 0, i = 0, prev = 0, maxStuck = 0, maxGoldWait = 0;
  const buys: RunResult['buys'] = [];
  while (i < table.length && t < 400) {
    const L = levelAt(t);
    budget += share * R[L] * factor * dt;
    t += dt;
    while (i < table.length) {
      const row = table[i];
      const L2 = levelAt(t);
      if (L2 < row.minLevel || budget < row.cost) break;
      budget -= row.cost;
      const available = Math.max(prev, tl[Math.min(row.minLevel, MAX_LEVEL)]);
      const goldWait = t - available;
      maxGoldWait = Math.max(maxGoldWait, goldWait);
      maxStuck = Math.max(maxStuck, t - prev);
      buys.push({ n: row.n, day: +t.toFixed(2), level: L2, goldWait: +goldWait.toFixed(2) });
      prev = t;
      i++;
    }
  }
  return { complete: i === table.length ? prev : Infinity, maxGoldWait, maxStuck, buys };
}

export function solveFor(target: number, f: (x: number) => number, lo: number, hi: number): number {
  // f crescente em x? usamos bisseção sobre f(x) - target com f decrescente (mais ouro = termina antes)
  for (let k = 0; k < 60; k++) {
    const m = (lo + hi) / 2;
    if (f(m) > target) lo = m; else hi = m;
  }
  return (lo + hi) / 2;
}

// ---------- Tabelas ----------
export const OLD_TABLE: LotRow[] = [
  [2, 2400], [4, 4000], [6, 7900], [7, 12000], [10, 23000], [11, 46000], [13, 90000], [14, 130000],
  [16, 250000], [18, 410000], [20, 620000], [21, 810000], [23, 1200000], [25, 1900000], [27, 2800000],
  [28, 3600000], [30, 5100000], [32, 7200000], [34, 11000000], [35, 14000000], [37, 21000000],
  [39, 30000000], [41, 38000000], [42, 47000000],
].map(([minLevel, cost], k) => ({ n: k + 1, minLevel, cost }));

export const round2 = (x: number) => {
  const p = Math.pow(10, Math.floor(Math.log10(x)) - 1);
  return Math.round(x / p) * p;
};
export type Params = { k: number; growth: number; base: number; purchases: number };
export function makeTable(p: Params): LotRow[] {
  const rows: LotRow[] = [];
  for (let n = 1; n <= p.purchases; n++) {
    const L = Math.min(MAX_LEVEL, Math.ceil(p.k * n - 1e-9));
    rows.push({ n, minLevel: L, cost: round2(p.base * Math.pow(p.growth, n - 1) * R[L]) });
  }
  return rows;
}
export const levelTimesFor = levelTimes;
export { R, XP };

// ---------- Execução direta: calibra e mostra ----------
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { a, b } = XP_CURVE;
  const tl = levelTimes(1);
  console.log(`curva de XP: a=${a.toExponential(3)} b=${b.toFixed(4)} | regular: nível 20 no dia ${tl[20].toFixed(1)}, 30 no dia ${tl[30].toFixed(1)}, 42 no dia ${tl[42].toFixed(1)}, 50 no dia ${tl[50].toFixed(1)}`);
  // 1) parcela da renda que vai para terreno: o regular termina o mapa antigo no dia 77
  const share = solveFor(77, (s) => run(OLD_TABLE, s, 1).complete, 0.05, 1.5);
  // 2) casual e dedicado: fator de XP e de ouro que reproduzem dia do mapa e maior espera publicados
  const fit = (tc: number, tw: number) => {
    let best = { xp: 1, gold: 1, err: Infinity };
    for (let xp = 0.6; xp <= 1.3001; xp += 0.01)
      for (let gold = 0.6; gold <= 1.3001; gold += 0.01) {
        const r = run(OLD_TABLE, share, xp, gold, 0.02);
        const err = ((r.complete - tc) / 3) ** 2 + ((r.maxGoldWait - tw) / 0.5) ** 2;
        if (err < best.err) best = { xp: +xp.toFixed(2), gold: +gold.toFixed(2), err };
      }
    return { xp: best.xp, gold: best.gold };
  };
  const profiles = { casual: fit(108, 6.5), regular: { xp: 1, gold: 1 }, dedicated: fit(71, 2.2) };
  console.log(`parcela da renda para terreno (calibrada): ${(share * 100).toFixed(1)}%`);
  const pub = { casual: [108, 6.5], regular: [77, 3.2], dedicated: [71, 2.2] } as const;
  for (const [nm, f] of Object.entries(profiles)) {
    const r = run(OLD_TABLE, share, f.xp, f.gold);
    const p = pub[nm as keyof typeof pub];
    console.log(`${nm} (xp ×${f.xp}, ouro ×${f.gold}): mapa no dia ${r.complete.toFixed(1)} (publicado ${p[0]}) | maior espera por ouro ${r.maxGoldWait.toFixed(1)} d (publicado ${p[1]})`);
  }
  writeFileSync(join(root, 'tools', 'balance', 'calibration.json'),
    JSON.stringify({ xpCurve: XP_CURVE, landShare: share, profiles }, null, 2) + '\n');
}
