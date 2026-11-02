// Funções do banco num lugar só.
// A versão atual de cada função fica em supabase/functions/<nome>.sql (uma por arquivo). Para mudar uma regra do
// servidor: edite o arquivo da função e rode `npm run db:migration -- nome-curto`; o script cria a migração nova
// só com as funções que mudaram. Assim ninguém edita uma cópia velha de uma função que já foi alterada depois.
//
//   npm run db:functions            grava supabase/functions/ com a última versão de cada função das migrações
//   npm run db:migration -- nome    cria supabase/migrations/<número>_nome.sql com as funções que mudaram
//   npm run db:check                confere que supabase/functions/ é igual à última versão nas migrações (CI)
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const MIG = join(ROOT, 'supabase', 'migrations');
const FN = join(ROOT, 'supabase', 'functions');

/** última definição de cada função (texto exato do "create or replace function" até o ";" do corpo), na ordem das migrações */
export function latestFromMigrations(): Map<string, { sql: string; file: string }> {
  const out = new Map<string, { sql: string; file: string }>();
  for (const file of readdirSync(MIG).filter((f) => f.endsWith('.sql')).sort()) {
    const s = readFileSync(join(MIG, file), 'utf8');
    // criações e remoções na ordem em que aparecem no arquivo
    const events: { at: number; kind: 'create' | 'drop'; name: string; end?: number }[] = [];
    for (const m of s.matchAll(/create\s+or\s+replace\s+function\s+public\.([a-z_0-9]+)\s*\(/gi)) {
      const start = m.index!;
      // corpo entre $tag$ ... $tag$ (o 1º tag depois do "create" abre; o mesmo tag fecha)
      const tag = /\$[A-Za-z_]*\$/.exec(s.slice(start))!;
      const open = start + tag.index;
      const close = s.indexOf(tag[0], open + tag[0].length);
      const semi = s.indexOf(';', close + tag[0].length);
      events.push({ at: start, kind: 'create', name: m[1].toLowerCase(), end: semi + 1 });
    }
    for (const m of s.matchAll(/drop\s+function\s+(?:if\s+exists\s+)?public\.([a-z_0-9]+)\s*\(/gi)) {
      events.push({ at: m.index!, kind: 'drop', name: m[1].toLowerCase() });
    }
    events.sort((a, b) => a.at - b.at);
    for (const e of events) {
      if (e.kind === 'drop') out.delete(e.name);
      else out.set(e.name, { sql: s.slice(e.at, e.end), file });
    }
  }
  return out;
}

function readFunctionsDir(): Map<string, string> {
  const out = new Map<string, string>();
  if (!existsSync(FN)) return out;
  for (const f of readdirSync(FN).filter((x) => x.endsWith('.sql'))) out.set(f.replace(/\.sql$/, ''), readFileSync(join(FN, f), 'utf8'));
  return out;
}

const norm = (s: string) => s.replace(/\r\n/g, '\n').trim();

function writeAll(): void {
  mkdirSync(FN, { recursive: true });
  const latest = latestFromMigrations();
  for (const [name, { sql, file }] of latest) {
    writeFileSync(join(FN, `${name}.sql`), `-- versão atual (veio de supabase/migrations/${file})\n${sql}\n`);
  }
  console.log(`${latest.size} funções gravadas em supabase/functions/`);
}

/** corpo da função sem o comentário de origem da 1ª linha */
const body = (text: string) => norm(text.replace(/^-- versão atual[^\n]*\n/, ''));

function diff(): { changed: string[]; missing: string[]; extra: string[] } {
  const latest = latestFromMigrations();
  const files = readFunctionsDir();
  const changed: string[] = [], missing: string[] = [], extra: string[] = [];
  for (const [name, { sql }] of latest) {
    const f = files.get(name);
    if (f === undefined) missing.push(name);
    else if (body(f) !== norm(sql)) changed.push(name);
  }
  for (const name of files.keys()) if (!latest.has(name)) extra.push(name);
  return { changed, missing, extra };
}

/** argumentos da função como o "drop function" pede (tira os valores padrão) */
function signature(sql: string): string {
  const open = sql.indexOf('(');
  let depth = 0, end = open;
  for (let i = open; i < sql.length; i++) {
    if (sql[i] === '(') depth++;
    else if (sql[i] === ')' && --depth === 0) { end = i; break; }
  }
  return sql.slice(open + 1, end).split(',').map((a) => a.replace(/\s+default\s+.*$/is, '').replace(/\s*=\s*.*$/s, '').trim()).filter(Boolean).join(', ');
}

function makeMigration(slug: string): void {
  if (!/^[a-z0-9_]+$/.test(slug)) throw new Error('use um nome curto com letras minúsculas, números e _ (ex.: v3_pets_ajuste)');
  const { changed, missing, extra } = diff();
  const toWrite = [...changed, ...extra].sort();
  // arquivo apagado = função removida: vira "drop function" com a assinatura da última versão
  const latest = latestFromMigrations();
  const drops = missing.sort().map((n) => `drop function if exists public.${n}(${signature(latest.get(n)!.sql)});`);
  if (!toWrite.length && !drops.length) { console.log('Nenhuma função mudou: nada a fazer.'); return; }
  const files = readFunctionsDir();
  const last = readdirSync(MIG).filter((f) => /^\d{14}_/.test(f)).map((f) => Number(f.slice(0, 14))).sort((a, b) => a - b).pop() ?? 20261023000000;
  const name = `${last + 100}_${slug}.sql`;
  const text = [`-- Gerada por "npm run db:migration" a partir de supabase/functions/ (mudam: ${toWrite.join(', ') || 'nenhuma'}; saem: ${missing.join(', ') || 'nenhuma'}).`,
    ...toWrite.map((n) => body(files.get(n)!)), ...(drops.length ? [drops.join('\n')] : [])].join('\n\n') + '\n';
  writeFileSync(join(MIG, name), text);
  console.log(`Criada supabase/migrations/${name}: ${toWrite.length} função(ões) nova(s) ou mudada(s), ${drops.length} removida(s)`);
}

function check(): void {
  const { changed, missing, extra } = diff();
  const problems = [
    ...changed.map((n) => `supabase/functions/${n}.sql mudou e não tem migração (rode npm run db:migration -- nome)`),
    ...extra.map((n) => `supabase/functions/${n}.sql não existe em nenhuma migração (rode npm run db:migration -- nome)`),
    ...missing.map((n) => `a função ${n} está nas migrações mas falta supabase/functions/${n}.sql (para removê-la rode npm run db:migration -- nome; para trazer de volta, npm run db:functions)`),
  ];
  if (problems.length) { console.error(problems.join('\n')); process.exit(1); }
  console.log(`funções do banco: ${latestFromMigrations().size} em dia com as migrações`);
}

/** para os testes: o que está diferente entre supabase/functions/ e as migrações */
export const functionsDiff = diff;
export const dropSignature = signature;

const [cmd, arg] = fileURLToPath(import.meta.url) === process.argv[1] ? process.argv.slice(2) : [];
if (cmd === 'write') writeAll();
else if (cmd === 'migration') makeMigration(arg ?? '');
else if (cmd === 'check') check();
else if (cmd) { console.error('uso: write | migration <nome> | check'); process.exit(1); }
