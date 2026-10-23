// Gera config/map_rules.json a partir de config/mapConfig.json: só o que o servidor precisa
// (tipo, vizinhos, canteiros e vagas de árvore de cada lote). O check.ts confere se está em dia.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export function buildMapRules() {
  const m = JSON.parse(readFileSync(join(root, 'config', 'mapConfig.json'), 'utf8'));
  return {
    version: m.version,
    source: 'gerado de config/mapConfig.json por tools/db/map-rules.ts',
    start_lot: m.start_lot,
    exempt_types: m.adjacency.exempt_types,
    lots: m.lots.map((l: any) => ({
      id: l.id, type: l.type, neighbors: l.neighbors,
      plots: (l.plots ?? []).map((p: any) => p.id),
      tree_slots: (l.tree_slots ?? []).length,
    })),
  };
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  writeFileSync(join(root, 'config', 'map_rules.json'), JSON.stringify(buildMapRules(), null, 2) + '\n');
  console.log('config/map_rules.json gerado');
}
