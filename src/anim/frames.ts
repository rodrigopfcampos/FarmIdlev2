// Tempo por quadro: cada quadro tem a sua duração (nunca um fps único). Só visual.
export type Frame = { key: string | number; ms: number };

/** índice do quadro no instante elapsedMs (com loop ou parando no último) */
export function frameAt(frames: { ms: number }[], elapsedMs: number, loop = true): number {
  const total = frames.reduce((s, f) => s + f.ms, 0);
  if (total <= 0) return 0;
  let t = loop ? ((elapsedMs % total) + total) % total : Math.max(0, Math.min(elapsedMs, total - 1));
  for (let i = 0; i < frames.length; i++) { if (t < frames[i].ms) return i; t -= frames[i].ms; }
  return frames.length - 1;
}

/** posição numa tabela de passos iguais (ms por passo), com loop */
export function tableAt(table: number[], stepMs: number, elapsedMs: number): number {
  const i = Math.floor(elapsedMs / stepMs);
  return table[((i % table.length) + table.length) % table.length];
}

/** fase fixa de cada instância a partir da posição (nunca Math.random por quadro) */
export function phaseOf(x: number, y: number): number {
  return (((Math.round(x) * 7 + Math.round(y) * 13) % 97) + 97) % 97;
}

/** o jogador pediu menos movimento no sistema */
export function reducedMotion(): boolean {
  return typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
}
