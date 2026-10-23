// Procura os parâmetros da tabela de lotes para 29 compras (30 lotes) que mantêm as metas da seção 14.
// Usa o modelo calibrado na tabela antiga (calibration.json). Saída: ranking e a tabela escolhida.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { makeTable, levelTimesFor, R, type LotRow } from './land-model.ts';

const here = dirname(fileURLToPath(import.meta.url));
const cal = JSON.parse(readFileSync(join(here, 'calibration.json'), 'utf8'));
const share: number = cal.landShare;

// Versão por eventos (exata e rápida) da mesma regra de compra do land-model.run
export function runFast(table: LotRow[], xp: number, gold: number) {
  const tl = levelTimesFor(xp);
  const C: number[] = [0, 0]; // renda acumulada para terreno no início de cada nível
  for (let L = 1; L < 50; L++) C[L + 1] = C[L] + share * R[L] * gold * (tl[L + 1] - tl[L]);
  const cumAt = (t: number) => {
    let L = 1;
    while (L < 50 && tl[L + 1] <= t) L++;
    return C[L] + share * R[L] * gold * (t - tl[L]);
  };
  const timeFor = (amount: number, from: number) => {
    // primeiro t >= from com renda acumulada >= amount
    if (cumAt(from) >= amount) return from;
    for (let L = 1; L <= 50; L++) {
      const end = L < 50 ? tl[L + 1] : Infinity;
      if (end <= from) continue;
      const startVal = cumAt(Math.max(from, tl[L]));
      const endVal = L < 50 ? C[L + 1] : Infinity;
      if (endVal >= amount) return Math.max(from, tl[L]) + (amount - startVal) / (share * R[L] * gold);
    }
    return Infinity;
  };
  let spent = 0, prev = 0, maxGoldWait = 0;
  const days: number[] = [];
  for (const row of table) {
    const available = Math.max(prev, tl[row.minLevel]);
    const t = timeFor(spent + row.cost, available);
    maxGoldWait = Math.max(maxGoldWait, t - available);
    spent += row.cost;
    days.push(t);
    prev = t;
  }
  return { complete: prev, maxGoldWait, days };
}

const P = cal.profiles;
export function evaluate(table: LotRow[]) {
  const reg = runFast(table, P.regular.xp, P.regular.gold);
  const cas = runFast(table, P.casual.xp, P.casual.gold);
  const ded = runFast(table, P.dedicated.xp, P.dedicated.gold);
  const pen = (x: number, lim: number) => Math.max(0, x - lim) ** 2;
  const score =
    ((reg.complete - 77) / 2) ** 2 + ((cas.complete - 108) / 4) ** 2 + ((ded.complete - 71) / 2) ** 2 +
    4 * pen(reg.maxGoldWait, 3.2) + 2 * pen(cas.maxGoldWait, 6.5) + 4 * pen(ded.maxGoldWait, 2.2);
  return { reg, cas, ded, score };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const results: any[] = [];
  for (let k = 1.4; k <= 1.5001; k += 0.01)
    for (let growth = 1.06; growth <= 1.1601; growth += 0.005)
      for (let base = 0.2; base <= 0.3601; base += 0.01) {
        const params = { k: +k.toFixed(2), growth: +growth.toFixed(3), base: +base.toFixed(2), purchases: 29 };
        const ev = evaluate(makeTable(params));
        results.push({ params, ...ev });
      }
  results.sort((a, b) => a.score - b.score);
  for (const r of results.slice(0, 15))
    console.log(JSON.stringify(r.params), 'nota', r.score.toFixed(3),
      `| reg ${r.reg.complete.toFixed(1)}d espera ${r.reg.maxGoldWait.toFixed(1)}`,
      `| cas ${r.cas.complete.toFixed(1)}d espera ${r.cas.maxGoldWait.toFixed(1)}`,
      `| ded ${r.ded.complete.toFixed(1)}d espera ${r.ded.maxGoldWait.toFixed(1)}`);
}
