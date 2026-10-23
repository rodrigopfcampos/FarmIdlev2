// Gera o SQL que copia config/<nome>.json para a tabela game_config (versão = campo "version" do arquivo).
// Uso: npx tsx tools/db/config-sql.ts levels crops ... > saida.sql  (rodar no projeto de teste e depois no de produção)
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const names = process.argv.slice(2);
if (!names.length) { console.error('informe os nomes: levels crops animals ...'); process.exit(1); }
for (const name of names) {
  const data = JSON.parse(readFileSync(join(root, 'config', `${name}.json`), 'utf8'));
  if (!Number.isInteger(data.version)) throw new Error(`${name}.json sem "version" inteiro`);
  const json = JSON.stringify(data);
  if (json.includes('$cfg$')) throw new Error('texto proibido no json');
  console.log(`insert into public.game_config (name, version, data) values ('${name}', ${data.version}, $cfg$${json}$cfg$::jsonb) on conflict (name, version) do nothing;`);
}
