// Painel básico do admin: entrar, 2FA (aplicativo autenticador), buscar jogador e ver ledger, auditoria e fazenda.
// O servidor só responde para admin com 2FA; aqui é só a tela.
import { supabase, configMissing } from '../net/supabase';
import { formatGold } from '../ui/format';

const root = document.getElementById('admin')!;
const esc = (s: unknown) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
const when = (s: string | null) => (s ? new Date(s).toLocaleString('pt-BR') : '—');

function screen(html: string): void { root.innerHTML = `<h1>Painel do admin</h1>${html}`; }

async function start(): Promise<void> {
  if (configMissing) { screen('<div class="card">Servidor não configurado.</div>'); return; }
  const { data } = await supabase!.auth.getSession();
  if (!data.session) return login();
  const who = (await supabase!.rpc('admin_whoami')).data as { is_admin: boolean; aal: string } | null;
  if (!who?.is_admin) {
    screen('<div class="card">Esta conta não é de admin. <button type="button" class="secondary" id="out">Sair</button></div>');
    root.querySelector('#out')!.addEventListener('click', async () => { await supabase!.auth.signOut(); void start(); });
    return;
  }
  if (who.aal !== 'aal2') return mfa();
  return panel();
}

function login(): void {
  screen(`<form class="card" id="f" style="max-width:360px">
    <label>E-mail<input name="email" type="email" autocomplete="email" required></label>
    <label>Senha<input name="password" type="password" autocomplete="current-password" required></label>
    <p class="msg" role="status"></p><button class="primary" type="submit">Entrar</button></form>`);
  const f = root.querySelector<HTMLFormElement>('#f')!;
  f.addEventListener('submit', async (e) => {
    e.preventDefault();
    const d = new FormData(f);
    const { error } = await supabase!.auth.signInWithPassword({ email: String(d.get('email')), password: String(d.get('password')) });
    if (error) { f.querySelector('.msg')!.textContent = 'E-mail ou senha incorretos.'; return; }
    void start();
  });
}

async function mfa(): Promise<void> {
  const { data: factors } = await supabase!.auth.mfa.listFactors();
  let factorId = factors?.totp.find((x) => x.status === 'verified')?.id;
  let qr = '';
  if (!factorId) {
    // primeira vez: cadastra o aplicativo autenticador
    for (const old of factors?.all.filter((x) => x.status !== 'verified') ?? []) await supabase!.auth.mfa.unenroll({ factorId: old.id });
    const { data, error } = await supabase!.auth.mfa.enroll({ factorType: 'totp', friendlyName: 'Village Idle Farm', issuer: 'Village Idle Farm' });
    if (error || !data) { screen(`<div class="card">Não foi possível ativar o 2FA: ${esc(error?.message)}</div>`); return; }
    factorId = data.id;
    qr = `<p>Escaneie no aplicativo autenticador (Google Authenticator, Microsoft Authenticator…):</p>
      <div class="qr"><img alt="QR code do 2FA" src="${data.totp.qr_code}" width="180" height="180"></div>
      <p>Ou digite a chave: <code>${esc(data.totp.secret)}</code></p>`;
  }
  screen(`<form class="card" id="f" style="max-width:420px">${qr}
    <label>Código de 6 dígitos<input name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" required></label>
    <p class="msg" role="status"></p><button class="primary" type="submit">Confirmar</button></form>`);
  const f = root.querySelector<HTMLFormElement>('#f')!;
  f.addEventListener('submit', async (e) => {
    e.preventDefault();
    const code = String(new FormData(f).get('code')).trim();
    const { error } = await supabase!.auth.mfa.challengeAndVerify({ factorId: factorId!, code });
    if (error) { f.querySelector('.msg')!.textContent = 'Código inválido. Tente o próximo.'; return; }
    void start();
  });
}

type Player = { user_id: string; nickname: string; email: string; gold: number; created_at: string; last_activity_at: string | null };

function panel(): void {
  screen(`<form class="card search" id="s"><input name="q" placeholder="Apelido, e-mail ou id do jogador" aria-label="Buscar jogador">
    <button class="primary small" type="submit">Buscar</button><button class="secondary" type="button" id="out">Sair</button></form>
    <div id="results"></div><div id="detail"></div>`);
  root.querySelector('#out')!.addEventListener('click', async () => { await supabase!.auth.signOut(); void start(); });
  const s = root.querySelector<HTMLFormElement>('#s')!;
  s.addEventListener('submit', (e) => { e.preventDefault(); void search(String(new FormData(s).get('q') ?? '')); });
  void search('');
}

async function search(q: string): Promise<void> {
  const box = root.querySelector('#results')!;
  const { data, error } = await supabase!.rpc('admin_search_players', { p_query: q });
  if (error) { box.innerHTML = `<div class="card">${esc(error.message)}</div>`; return; }
  const rows = (data as Player[]).map((p) => `<tr class="pick" data-id="${p.user_id}"><td>${esc(p.nickname)}</td><td>${esc(p.email)}</td>
    <td>${formatGold(Number(p.gold ?? 0))}</td><td>${when(p.created_at)}</td><td>${when(p.last_activity_at)}</td></tr>`).join('');
  box.innerHTML = `<div class="card table-wrap"><table><thead><tr><th>Apelido</th><th>E-mail</th><th>Ouro</th><th>Conta criada</th><th>Última atividade</th></tr></thead>
    <tbody>${rows || '<tr><td colspan="5">Nenhum jogador.</td></tr>'}</tbody></table></div>`;
  box.querySelectorAll<HTMLElement>('tr.pick').forEach((tr) => tr.addEventListener('click', () => void detail(tr.dataset.id!, 'ledger')));
}

async function detail(id: string, tab: 'ledger' | 'audit' | 'farm'): Promise<void> {
  const box = root.querySelector('#detail')!;
  const tabs = [['ledger', 'Ledger'], ['audit', 'Auditoria'], ['farm', 'Fazenda']]
    .map(([k, n]) => `<button type="button" role="tab" data-tab="${k}" aria-selected="${tab === k}">${n}</button>`).join('');
  let body = '';
  if (tab === 'ledger') {
    const { data, error } = await supabase!.rpc('admin_player_ledger', { p_user: id, p_limit: 200 });
    body = error ? esc(error.message) : `<table><thead><tr><th>#</th><th>Quando</th><th>Motivo</th><th>Valor</th><th>Saldo</th><th>Detalhe</th></tr></thead><tbody>${
      (data as any[]).map((l) => `<tr><td>${l.id}</td><td>${when(l.created_at)}</td><td>${esc(l.reason)}</td>
        <td class="${Number(l.amount) < 0 ? 'neg' : 'pos'}">${Number(l.amount).toLocaleString('pt-BR')}</td><td>${Number(l.balance_after).toLocaleString('pt-BR')}</td>
        <td><code>${esc(JSON.stringify(l.ref))}</code></td></tr>`).join('')}</tbody></table>`;
  }
  if (tab === 'audit') {
    const { data, error } = await supabase!.rpc('admin_player_audit', { p_user: id, p_limit: 200 });
    body = error ? esc(error.message) : `<table><thead><tr><th>#</th><th>Quando</th><th>Ação</th><th>Quem fez</th><th>Dados</th></tr></thead><tbody>${
      (data as any[]).map((a) => `<tr><td>${a.id}</td><td>${when(a.created_at)}</td><td>${esc(a.action)}</td><td><code>${esc(a.actor_id ?? 'sistema')}</code></td>
        <td><code>${esc(JSON.stringify(a.data))}</code></td></tr>`).join('')}</tbody></table>`;
  }
  if (tab === 'farm') {
    const { data, error } = await supabase!.rpc('admin_player_farm', { p_user: id });
    const f = data as any;
    body = error ? esc(error.message) : `<p>Nível ${f.level} (${Number(f.xp).toLocaleString('pt-BR')} de ${Number(f.xp_to_next ?? 0).toLocaleString('pt-BR')} XP) · ouro ${formatGold(Number(f.gold))}
      · trabalho guardado ${Number(f.labor_bank).toFixed(2)} · tempo da fazenda ${(f.farm_time / 3600).toFixed(1)} h · última atividade ${when(f.last_activity_at)}</p>
      <p>Lotes: ${f.lots.map((l: any) => `${esc(l.lot_id)}${l.purchase_n ? ` (${l.purchase_n}ª${l.ready_at > f.farm_time ? ', em limpeza' : ''})` : ''}`).join(', ')}</p>
      <p>Silo: <code>${esc(JSON.stringify(f.silo))}</code> · Itens: <code>${esc(JSON.stringify(f.inventory))}</code> · Ferramentas: <code>${esc(JSON.stringify(f.tools))}</code></p>
      <div class="grants"><p class="hint">Ferramentas de teste: tudo fica na auditoria com a justificativa (e o ouro, no ledger).</p>
      <form class="row grant" data-kind="deed"><strong>Dar Escritura</strong>
        <label>Quantidade<input name="value" type="number" min="-10" max="10" value="1" required style="width:90px"></label>
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: teste da fase 2"></label>
        <button class="primary small" type="submit">Dar</button><span class="msg" role="status"></span></form>
      <form class="row grant" data-kind="level"><strong>Mudar nível</strong>
        <label>Nível<input name="value" type="number" min="1" max="50" value="${f.level}" required style="width:90px"></label>
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: testar o pomar"></label>
        <button class="primary small" type="submit">Mudar</button><span class="msg" role="status"></span></form>
      <form class="row grant" data-kind="gold"><strong>Dar ouro</strong>
        <label>Valor<input name="value" type="number" min="-1000000000" max="1000000000" step="1" value="10000" required style="width:140px"></label>
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: testar a compra de lotes"></label>
        <button class="primary small" type="submit">Dar</button><span class="msg" role="status"></span></form></div>
      ${f.trees.length ? `<p>Árvores: ${f.trees.map((t: any) => `${esc(t.lot_id)}-${t.slot}: ${esc(t.fruit_id ?? 'vazia')}`).join(' · ')}</p>` : ''}
      <table><thead><tr><th>Canteiro</th><th>Cultivo</th><th>Estado</th><th>Pronto em (tempo da fazenda)</th><th>Parado</th></tr></thead><tbody>${
      f.plots.map((p: any) => `<tr><td>${esc(p.plot_id)}</td><td>${esc(p.crop_id ?? '—')}</td><td>${esc(p.state)}</td><td>${p.ready_at ? (p.ready_at / 3600).toFixed(2) + ' h' : '—'}</td><td>${esc(p.stalled_reason ?? '')}</td></tr>`).join('')}</tbody></table>`;
  }
  box.innerHTML = `<div class="card"><div class="tabs" role="tablist">${tabs}</div><div class="table-wrap">${body}</div></div>`;
  box.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach((b) => b.addEventListener('click', () => void detail(id, b.dataset.tab as 'ledger' | 'audit' | 'farm')));
  // ferramentas de teste (Escritura, nível e ouro): o servidor exige 2FA e registra tudo na auditoria
  box.querySelectorAll<HTMLFormElement>('form.grant').forEach((form) => form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const d = new FormData(form);
    const msg = form.querySelector('.msg')!;
    const value = Number(d.get('value')), reason = String(d.get('reason'));
    const call = form.dataset.kind === 'deed' ? supabase!.rpc('admin_grant_item', { p_user: id, p_item: 'deed', p_qty: value, p_reason: reason })
      : form.dataset.kind === 'level' ? supabase!.rpc('admin_set_level', { p_user: id, p_level: value, p_reason: reason })
      : supabase!.rpc('admin_grant_gold', { p_user: id, p_amount: value, p_reason: reason });
    const { error } = await call;
    if (error) { msg.textContent = error.message; return; }
    void detail(id, 'farm');
  }));
}

void start();
