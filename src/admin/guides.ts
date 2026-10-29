// Guias do painel (fase 9): visão geral, antitrapaça, denúncias, economia, progresso, expedições, cartas, missões,
// balanceamento e auditoria. Só leitura e as ações de revisão; o servidor confere o papel (Leitor, Moderador, Admin) e o 2FA.
import { supabase } from '../net/supabase';
import { formatGold } from '../ui/format';
import { ANTICHEAT as ANTI } from '../data';

type Ctx = { box: HTMLElement; esc: (s: unknown) => string; when: (s: string | null) => string; openPlayer: (id: string) => void };

const pct = (x: number | null | undefined) => (x === null || x === undefined ? '—' : `${(Number(x) * 100).toFixed(1)}%`);
const nf = (x: unknown) => Number(x ?? 0).toLocaleString('pt-BR', { maximumFractionDigits: 2 });
const ruleName = (r: string) => (ANTI.rules as Record<string, { name_pt: string }>)[r]?.name_pt ?? (r === 'test' ? 'Teste do Discord' : r);

export const GUIDES = [
  ['overview', 'Visão geral'], ['alerts', 'Antitrapaça'], ['reports', 'Denúncias'], ['economy', 'Economia'], ['progress', 'Progresso'],
  ['expeditions', 'Expedições'], ['cards', 'Cartas'], ['missions', 'Missões'], ['balance', 'Balanceamento'], ['audit', 'Auditoria'],
] as const;
export type Guide = (typeof GUIDES)[number][0];

async function call<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase!.rpc(fn, args);
  if (error) throw new Error(error.message);
  return data as T;
}

export async function renderGuide(g: Guide, ctx: Ctx, msg = ''): Promise<void> {
  const { box, esc } = ctx;
  box.innerHTML = '<div class="card">Carregando…</div>';
  try {
    const html = await ({ overview, alerts, reports, economy, progress, expeditions, cards, missions, balance, audit } as Record<Guide, (c: Ctx) => Promise<string>>)[g](ctx);
    box.innerHTML = `<div class="card">${msg ? `<p class="msg">${esc(msg)}</p>` : ''}${html}</div>`;
    bind(g, ctx);
  } catch (e) {
    box.innerHTML = `<div class="card">${esc(e instanceof Error ? e.message : e)}</div>`;
  }
}

async function overview({ esc }: Ctx): Promise<string> {
  const o = await call<any>('admin_overview');
  const k = (label: string, v: string) => `<div class="kpi"><small>${esc(label)}</small><strong>${v}</strong></div>`;
  return `<h2>Visão geral</h2><div class="kpis">
    ${k('Online agora (5 min)', nf(o.online))}${k('Ativos hoje', nf(o.dau))}${k('Ativos 7 dias', nf(o.wau))}${k('Ativos 30 dias', nf(o.mau))}
    ${k('Contas', nf(o.players))}${k('Novos hoje', nf(o.new_today))}${k('Novos 7 dias', nf(o.new_7d))}
    ${k('Retenção D1', pct(o.retention?.D1))}${k('Retenção D7', pct(o.retention?.D7))}${k('Retenção D30', pct(o.retention?.D30))}
    ${k('Ouro criado hoje', formatGold(Number(o.gold_created_today)))}${k('Ouro destruído hoje', formatGold(Number(o.gold_destroyed_today)))}
    ${k('Ouro em circulação', formatGold(Number(o.gold_circulating)))}${k('Alertas abertos', nf(o.alerts_open))}
    ${k(`Contas para revisar (risco ${ANTI.review_from}+)`, nf(o.alerts_review))}${k('Denúncias abertas', nf(o.reports_open))}</div>
    <p class="hint">Dias em UTC. Ouro criado não conta presentes do painel e de teste.</p>
    <button type="button" class="secondary" data-test-alert>Mandar alerta de teste para o Discord</button>
    <button type="button" class="secondary" data-run-ac>Rodar o antitrapaça agora (todas as contas ativas)</button>`;
}

async function alerts({ esc, when }: Ctx): Promise<string> {
  const list = await call<any[]>('admin_alerts', { p_status: filter.alerts, p_limit: 200 });
  const sel = ['open', 'escalated', 'archived', 'all'].map((s) => `<option value="${s}" ${filter.alerts === s ? 'selected' : ''}>${({ open: 'Abertos', escalated: 'Escalados', archived: 'Arquivados', all: 'Todos' } as Record<string, string>)[s]}</option>`).join('');
  const rows = list.map((a) => `<tr><td>${a.id}</td><td>${when(a.at)}</td><td><a href="#" data-player="${a.user_id}">${esc(a.nickname)}</a></td>
    <td>${esc(ruleName(a.rule))}</td><td>${a.score}</td><td class="${a.risk >= ANTI.review_from ? 'neg' : ''}">${a.risk}</td>
    <td><code>${esc(JSON.stringify(a.evidence))}</code></td><td>${a.notified ? 'Discord ✔' : ''}${a.note ? `<br><small>${esc(a.note)}</small>` : ''}</td>
    <td class="row">${a.status !== 'archived' ? `<button type="button" class="secondary" data-alert="${a.id}" data-set="archived">Arquivar</button>` : ''}
      ${a.status !== 'escalated' ? `<button type="button" class="secondary" data-alert="${a.id}" data-set="escalated">Escalar</button>` : ''}
      ${a.status !== 'open' ? `<button type="button" class="secondary" data-alert="${a.id}" data-set="open">Reabrir</button>` : ''}</td></tr>`).join('');
  return `<h2>Antitrapaça</h2><div class="row"><label>Mostrar <select data-filter="alerts">${sel}</select></label></div>
    <p class="hint">Cada alerta soma pontos na nota de risco da conta (0 a 100, últimos ${ANTI.risk_window_days} dias). Risco ${ANTI.review_from}+ entra na fila e vai para o Discord; ${ANTI.freeze_market_from}+ congela o mercado da conta. Nunca bane sozinho.</p>
    <div class="table-wrap"><table><thead><tr><th>#</th><th>Quando</th><th>Jogador</th><th>Regra</th><th>Pontos</th><th>Risco</th><th>Evidência</th><th></th><th>Ações</th></tr></thead>
    <tbody>${rows || '<tr><td colspan="9">Nenhum alerta.</td></tr>'}</tbody></table></div>`;
}

async function reports({ esc, when }: Ctx): Promise<string> {
  const list = await call<any[]>('admin_reports', { p_status: filter.reports });
  const sel = ['open', 'closed', 'all'].map((s) => `<option value="${s}" ${filter.reports === s ? 'selected' : ''}>${({ open: 'Abertas', closed: 'Fechadas', all: 'Todas' } as Record<string, string>)[s]}</option>`).join('');
  const rows = list.map((r) => `<tr><td>${r.id}</td><td>${when(r.at)}</td><td>${esc(r.reporter)}</td><td><a href="#" data-player="${r.target}">${esc(r.target_nick)}</a> <small>(${r.against} no total)</small></td>
    <td>${esc(r.reason)}</td><td>${r.status === 'open' ? `<button type="button" class="secondary" data-report="${r.id}">Fechar</button>` : `fechada${r.note ? `: ${esc(r.note)}` : ''}`}</td></tr>`).join('');
  return `<h2>Denúncias</h2><div class="row"><label>Mostrar <select data-filter="reports">${sel}</select></label></div>
    <div class="table-wrap"><table><thead><tr><th>#</th><th>Quando</th><th>Quem denunciou</th><th>Denunciado</th><th>Motivo</th><th></th></tr></thead>
    <tbody>${rows || '<tr><td colspan="6">Nenhuma denúncia.</td></tr>'}</tbody></table></div>`;
}

async function economy({ esc }: Ctx): Promise<string> {
  const e = await call<any>('admin_economy', { p_days: 14 });
  const days = [...new Set((e.by_reason as any[]).map((x) => x.day))];
  const dayRows = days.map((d) => {
    const xs = (e.by_reason as any[]).filter((x) => x.day === d);
    const inn = xs.reduce((s, x) => s + Number(x.in), 0), out = xs.reduce((s, x) => s + Number(x.out), 0);
    return `<tr><td>${esc(d)}</td><td class="pos">${formatGold(inn)}</td><td class="neg">${formatGold(out)}</td><td>${out > 0 ? (inn / out).toFixed(2) : '—'}</td></tr>`;
  }).join('');
  const reasons = new Map<string, { in: number; out: number }>();
  for (const x of e.by_reason as any[]) { const r = reasons.get(x.reason) ?? { in: 0, out: 0 }; r.in += Number(x.in); r.out += Number(x.out); reasons.set(x.reason, r); }
  const reasonRows = [...reasons.entries()].sort((a, b) => b[1].in + b[1].out - a[1].in - a[1].out)
    .map(([k, v]) => `<tr><td>${esc(k)}</td><td class="pos">${v.in ? formatGold(v.in) : ''}</td><td class="neg">${v.out ? formatGold(v.out) : ''}</td></tr>`).join('');
  const lv = (e.income_by_level as any[]).map((x) => `<tr><td>${x.level}</td><td>${x.players}</td><td>${formatGold(Number(x.p50))}</td><td>${formatGold(Number(x.p90))}</td><td>${formatGold(Number(x.R))}</td></tr>`).join('');
  return `<h2>Economia (14 dias)</h2><p>Ouro em circulação: <strong>${formatGold(Number(e.circulating))}</strong></p>
    <h3>Por dia</h3><div class="table-wrap"><table><thead><tr><th>Dia (UTC)</th><th>Entrou</th><th>Saiu (dreno)</th><th>Entrou ÷ saiu</th></tr></thead><tbody>${dayRows}</tbody></table></div>
    <h3>Por motivo</h3><div class="table-wrap"><table><thead><tr><th>Motivo</th><th>Fonte</th><th>Dreno</th></tr></thead><tbody>${reasonRows}</tbody></table></div>
    <h3>Ouro ganho nas últimas 24 h, por nível</h3><div class="table-wrap"><table><thead><tr><th>Nível</th><th>Jogadores</th><th>Mediana</th><th>90%</th><th>R do nível</th></tr></thead><tbody>${lv}</tbody></table></div>`;
}

async function progress({ esc }: Ctx): Promise<string> {
  const list = await call<any[]>('admin_progress');
  const rows = list.map((p) => `<tr class="${p.fast ? 'flag' : ''}"><td><a href="#" data-player="${p.id}">${esc(p.nickname)}</a></td><td>${p.level}</td><td>${p.lots}/30</td>
    <td>${nf(p.age_days)}</td><td>${nf(p.dedicated_day)}</td><td>${p.fast ? 'acima do dedicado' : ''}</td></tr>`).join('');
  return `<h2>Progresso</h2><p class="hint">O dedicado da simulação chega ao nível 10 no dia 0,8, ao 30 no dia 30 e ao 50 no dia 103. Quem chega antes (com 10% de folga) fica marcado.</p>
    <div class="table-wrap"><table><thead><tr><th>Jogador</th><th>Nível</th><th>Lotes</th><th>Dias de conta</th><th>Dia do dedicado nesse nível</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

async function expeditions({ esc }: Ctx): Promise<string> {
  const list = await call<any[]>('admin_expeditions');
  const rows = list.map((x) => `<tr><td>${esc(x.route)}</td><td>${esc(x.vehicle)}</td><td>${x.trips}</td><td>${pct(x.expected)}</td><td>${pct(x.real)}</td><td>${pct(x.crit)}</td></tr>`).join('');
  return `<h2>Expedições</h2><p class="hint">Sucesso real (sucesso + crítico) × a chance média calculada na saída. Com poucas viagens a diferença é normal.</p>
    <div class="table-wrap"><table><thead><tr><th>Rota</th><th>Veículo</th><th>Viagens</th><th>Chance média</th><th>Sucesso real</th><th>Crítico</th></tr></thead><tbody>${rows || '<tr><td colspan="6">Nenhuma viagem ainda.</td></tr>'}</tbody></table></div>`;
}

async function cards({ esc }: Ctx): Promise<string> {
  const c = await call<any>('admin_cards');
  const rows = (c.by_rarity as any[]).map((x) => `<tr><td>${esc(x.rarity)}</td><td>${x.n}</td><td>${pct(x.share)}</td><td>${pct(x.expected)}</td></tr>`).join('');
  const orig = Object.entries(c.by_origin ?? {}).map(([k, v]) => `${esc(k)}: ${v}`).join(' · ');
  return `<h2>Cartas</h2><div class="table-wrap"><table><thead><tr><th>Raridade</th><th>Tiradas (sem o painel)</th><th>Real</th><th>Esperado (com garantia)</th></tr></thead><tbody>${rows}</tbody></table></div>
    <p>Por origem: ${orig || '—'}</p><p>Cartas completas no Armory (5 raridades): ${c.armory_complete} · vendidas ao Colecionador: ${c.sold_to_collector}</p>`;
}

async function missions({ esc }: Ctx): Promise<string> {
  const list = await call<any[]>('admin_missions');
  const rows = list.map((m) => `<tr><td>${m.kind === 'daily' ? 'diária' : 'semanal'}</td><td>${esc(m.id)}</td><td>${m.drawn}</td><td>${m.done}</td><td>${pct(m.rate)}</td><td>${m.avg_hours ?? '—'}</td></tr>`).join('');
  return `<h2>Missões</h2><div class="table-wrap"><table><thead><tr><th>Tipo</th><th>Missão</th><th>Sorteada</th><th>Completa</th><th>Taxa</th><th>Horas até completar</th></tr></thead><tbody>${rows || '<tr><td colspan="6">—</td></tr>'}</tbody></table></div>`;
}

async function balance({ esc, when }: Ctx): Promise<string> {
  const list = await call<any[]>('admin_config_versions', { p_name: null });
  const rows = list.map((c) => `<tr><td>${esc(c.name)}</td><td>${c.version}</td><td>${when(c.created_at)}</td><td><small>${esc(c.source ?? '')}</small></td><td><code>${esc(String(c.md5).slice(0, 8))}</code></td>
    <td><button type="button" class="secondary" data-restore="${esc(c.name)}" data-version="${c.version}">Voltar para esta</button></td></tr>`).join('');
  return `<h2>Balanceamento</h2><p class="hint">O jogo usa sempre a versão mais alta de cada config. "Voltar para esta" cria uma versão nova igual à escolhida (só Admin; nada é apagado). Números novos entram pelo repositório (config/*.json) e pelo simulador.</p>
    <form class="row" data-restore-form><label style="flex:1">Justificativa para voltar versão<input name="reason" minlength="5" placeholder="ex.: a versão nova deixou a renda alta demais"></label></form>
    <div class="table-wrap"><table><thead><tr><th>Config</th><th>Versão</th><th>Criada</th><th>Origem</th><th>md5</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

async function audit({ esc, when }: Ctx): Promise<string> {
  const list = await call<any[]>('admin_audit_admins', { p_limit: 300 });
  const rows = list.map((a) => `<tr><td>${a.id}</td><td>${when(a.at)}</td><td>${esc(a.admin ?? '—')}</td><td>${esc(a.action)}</td>
    <td>${a.target ? `<a href="#" data-player="${a.target}">ver</a>` : ''}</td><td><code>${esc(JSON.stringify(a.data))}</code></td></tr>`).join('');
  return `<h2>Auditoria dos admins</h2><p class="hint">Tudo o que cada admin fez. Não pode ser apagado.</p>
    <div class="table-wrap"><table><thead><tr><th>#</th><th>Quando</th><th>Admin</th><th>Ação</th><th>Jogador</th><th>Dados</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

const filter = { alerts: 'open', reports: 'open' };

function bind(g: Guide, ctx: Ctx): void {
  const { box } = ctx;
  const again = (msg = '') => void renderGuide(g, ctx, msg);
  box.querySelectorAll<HTMLElement>('[data-player]').forEach((a) => a.addEventListener('click', (e) => { e.preventDefault(); ctx.openPlayer(a.dataset.player!); }));
  box.querySelectorAll<HTMLSelectElement>('[data-filter]').forEach((s) => s.addEventListener('change', () => { filter[s.dataset.filter as 'alerts' | 'reports'] = s.value; again(); }));
  box.querySelectorAll<HTMLButtonElement>('[data-alert]').forEach((b) => b.addEventListener('click', async () => {
    const note = prompt('Nota da revisão (opcional)') ?? '';
    try { await call('admin_alert_set', { p_id: Number(b.dataset.alert), p_status: b.dataset.set, p_note: note }); again('Feito e registrado.'); } catch (e) { again(String((e as Error).message)); }
  }));
  box.querySelectorAll<HTMLButtonElement>('[data-report]').forEach((b) => b.addEventListener('click', async () => {
    const note = prompt('O que foi feito? (fica registrado)') ?? '';
    try { await call('admin_report_close', { p_id: Number(b.dataset.report), p_note: note }); again('Denúncia fechada.'); } catch (e) { again(String((e as Error).message)); }
  }));
  box.querySelector('[data-test-alert]')?.addEventListener('click', async () => {
    try { const r = await call<{ sent: boolean }>('admin_test_alert'); again(r.sent ? 'Alerta enviado: confira o canal do Discord.' : 'Não enviou: o segredo "discord_alerts_webhook" ainda não está no Vault deste projeto.'); }
    catch (e) { again(String((e as Error).message)); }
  });
  box.querySelector('[data-run-ac]')?.addEventListener('click', async () => {
    try { const r = await call<{ accounts: number; alerts: number }>('admin_run_anticheat', { p_user: null }); again(`Conferidas ${r.accounts} contas; ${r.alerts} alertas novos.`); }
    catch (e) { again(String((e as Error).message)); }
  });
  box.querySelectorAll<HTMLButtonElement>('[data-restore]').forEach((b) => b.addEventListener('click', async () => {
    const reason = box.querySelector<HTMLInputElement>('[data-restore-form] input')!.value;
    try { await call('admin_config_restore', { p_name: b.dataset.restore, p_version: Number(b.dataset.version), p_reason: reason }); again('Versão nova criada.'); }
    catch (e) { again(String((e as Error).message)); }
  }));
}
