// Painel básico do admin: entrar, 2FA (aplicativo autenticador), buscar jogador e ver ledger, auditoria e fazenda.
// O servidor só responde para admin com 2FA; aqui é só a tela.
import { supabase, configMissing } from '../net/supabase';
import { formatGold } from '../ui/format';
import { CARDS, EQUIP_CARDS, RARITY_BY_ID, WEATHER } from '../data';
import { condName } from '../farm/weather';

// itens que o admin pode dar: Kits de Reforma e vestimentas/amuletos em cada raridade
const ITEM_OPTIONS = [
  ...['uncommon', 'rare', 'legendary', 'mythic'].map((r) => `<option value="kit:${r}">Kit de Reforma ${RARITY_BY_ID[r].name_pt}</option>`),
  ...EQUIP_CARDS.flatMap((c) => ['common', 'uncommon', 'rare', 'legendary', 'mythic'].map((r) => `<option value="${c.id}:${r}">${c.name_pt} ${RARITY_BY_ID[r].name_pt}</option>`)),
].join('');

// cartas que o admin pode dar: as 10 em cada raridade
const CARD_OPTIONS = CARDS.cards.flatMap((c) => ['common', 'uncommon', 'rare', 'legendary', 'mythic'].map((r) =>
  `<option value="${c.id}:${r}">${c.name_pt} ${(CARDS.rarities as Record<string, { name_pt: string }>)[r].name_pt}</option>`)).join('');

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
    <div id="results"></div><div id="detail"></div><div id="weather"></div>`);
  root.querySelector('#out')!.addEventListener('click', async () => { await supabase!.auth.signOut(); void start(); });
  const s = root.querySelector<HTMLFormElement>('#s')!;
  s.addEventListener('submit', (e) => { e.preventDefault(); void search(String(new FormData(s).get('q') ?? '')); });
  void search('');
  void weather('America/Sao_Paulo', new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Sao_Paulo' }));
}

type WxDay = { day: string; offset_min: number; blocks: string[]; event_id: string | null; event_local: string | null; forced: boolean };
const EVENT_NAME = (id: string | null) => (id ? WEATHER.night_event.events.find((e) => e.id === id)?.name_pt ?? id : 'sem evento');

/** clima e evento noturno: agenda de ontem, hoje e amanhã num fuso; forçar ou cancelar o evento (fica registrado) */
async function weather(tz: string, day: string, msg = ''): Promise<void> {
  const box = root.querySelector<HTMLElement>('#weather')!;
  const { data, error } = await supabase!.rpc('admin_weather', { p_tz: tz, p_day: day });
  const days = (data as { days: WxDay[] } | null)?.days ?? [];
  const rows = days.map((d) => `<tr><td>${esc(d.day)}</td><td>${d.blocks.map((b, i) => `${String(i * 3).padStart(2, '0')}h ${esc(condName(b))}`).join(' · ')}</td>
    <td>${esc(EVENT_NAME(d.event_id))}${d.event_local ? ` às ${esc(d.event_local)}` : ''}${d.forced ? ' (forçado)' : ''}</td></tr>`).join('');
  const opts = WEATHER.night_event.events.map((e) => `<option value="${e.id}">${esc(e.name_pt)}</option>`).join('');
  box.innerHTML = `<div class="card"><h2>Clima e evento noturno</h2>
    <form class="search" id="wxq"><input name="tz" value="${esc(tz)}" aria-label="Fuso (ex.: America/Sao_Paulo)"><input name="day" type="date" value="${esc(day)}" aria-label="Dia">
      <button class="secondary" type="submit">Ver agenda</button></form>
    ${error ? `<p>${esc(error.message)}</p>` : `<div class="table-wrap"><table><thead><tr><th>Dia</th><th>Clima (blocos de 3 h)</th><th>Evento</th></tr></thead><tbody>${rows}</tbody></table></div>`}
    <form class="grant" id="wxf"><select name="event"><option value="">Cancelar o evento do dia</option>${opts}</select>
      <input name="start" placeholder="Início HH:MM (vazio = mantém)" aria-label="Início">
      <input name="reason" placeholder="Justificativa" aria-label="Justificativa" required>
      <button class="primary small" type="submit">Aplicar em ${esc(day)}</button></form>
    <p class="hint">Vale para todos do mesmo fuso. Para testar agora, use o horário atual arredondado para 5 min. ${esc(msg)}</p></div>`;
  box.querySelector<HTMLFormElement>('#wxq')!.addEventListener('submit', (e) => {
    e.preventDefault(); const d = new FormData(e.currentTarget as HTMLFormElement);
    void weather(String(d.get('tz')), String(d.get('day')));
  });
  box.querySelector<HTMLFormElement>('#wxf')!.addEventListener('submit', async (e) => {
    e.preventDefault(); const d = new FormData(e.currentTarget as HTMLFormElement);
    const ev = String(d.get('event') ?? ''), st = String(d.get('start') ?? '').trim();
    const r = await supabase!.rpc('admin_force_event', { p_tz: tz, p_day: day, p_event: ev || null, p_start_hm: st || null, p_reason: String(d.get('reason') ?? '') });
    void weather(tz, day, r.error ? r.error.message : 'Feito e registrado.');
  });
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

async function detail(id: string, tab: 'ledger' | 'audit' | 'farm' | 'reports'): Promise<void> {
  const box = root.querySelector('#detail')!;
  const tabs = [['ledger', 'Ledger'], ['audit', 'Auditoria'], ['farm', 'Fazenda'], ['reports', 'Denúncias']]
    .map(([k, n]) => `<button type="button" role="tab" data-tab="${k}" aria-selected="${tab === k}">${n}</button>`).join('');
  let body = '';
  if (tab === 'ledger') {
    const { data, error } = await supabase!.rpc('admin_player_ledger', { p_user: id, p_limit: 200 });
    body = error ? esc(error.message) : `<table><thead><tr><th>#</th><th>Quando</th><th>Motivo</th><th>Valor</th><th>Saldo</th><th>Detalhe</th></tr></thead><tbody>${
      (data as any[]).map((l) => `<tr><td>${l.id}</td><td>${when(l.created_at)}</td><td>${esc(l.reason)}</td>
        <td class="${Number(l.amount) < 0 ? 'neg' : 'pos'}">${Number(l.amount).toLocaleString('pt-BR')}</td><td>${Number(l.balance_after).toLocaleString('pt-BR')}</td>
        <td><code>${esc(JSON.stringify(l.ref))}</code></td></tr>`).join('')}</tbody></table>`;
  }
  if (tab === 'reports') {
    const { data, error } = await supabase!.rpc('admin_player_reports', { p_user: id });
    const list = (data ?? []) as any[];
    body = error ? esc(error.message) : list.length ? `<table><thead><tr><th>#</th><th>Quando</th><th>Quem denunciou</th><th>Motivo</th><th>Situação</th></tr></thead><tbody>${
      list.map((r) => `<tr><td>${r.id}</td><td>${when(r.at)}</td><td>${esc(r.reporter)}</td><td>${esc(r.reason)}</td><td>${r.status === 'open' ? 'aberta' : 'fechada'}</td></tr>`).join('')}</tbody></table>`
      : '<p>Nenhuma denúncia contra este jogador.</p>';
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
      <form class="row grant" data-kind="cleanup"><strong>Terminar limpeza</strong>
        <label>Lote<select name="value">${f.lots.filter((l: any) => l.ready_at > f.farm_time).map((l: any) => `<option value="${esc(l.lot_id)}">${esc(l.lot_id)} (falta ${Math.ceil((l.ready_at - f.farm_time) / 60)} min)</option>`).join('') || '<option value="">nenhum em limpeza</option>'}${f.lots.filter((l: any) => l.ready_at > f.farm_time).length > 1 ? '<option value="*">todos</option>' : ''}</select></label>
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: testar o pomar"></label>
        <button class="primary small" type="submit">Terminar</button><span class="msg" role="status"></span></form>
      <form class="row grant" data-kind="payday"><strong>Cobrar salário agora</strong>
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: testar o Desmotivado"></label>
        <input name="value" type="hidden" value="1">
        <button class="primary small" type="submit">Cobrar</button><span class="msg" role="status"></span></form>
      <form class="row grant" data-kind="animals"><strong>Terminar ciclo dos animais</strong>
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: testar a coleta"></label>
        <input name="value" type="hidden" value="1">
        <button class="primary small" type="submit">Terminar</button><span class="msg" role="status"></span></form>
      <form class="row grant" data-kind="trips"><strong>Trazer as viagens de volta</strong>
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: testar o Receber"></label>
        <input name="value" type="hidden" value="1">
        <button class="primary small" type="submit">Trazer</button><span class="msg" role="status"></span></form>
      <form class="row grant" data-kind="item"><strong>Dar item</strong>
        <label>Item<select name="item">${ITEM_OPTIONS}</select></label>
        <label>Quantidade<input name="value" type="number" min="-10" max="10" value="1" required style="width:90px"></label>
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: testar a reforma"></label>
        <button class="primary small" type="submit">Dar</button><span class="msg" role="status"></span></form>
      <form class="row grant" data-kind="card"><strong>Dar carta</strong>
        <label>Carta<select name="item">${CARD_OPTIONS}</select></label>
        <input name="value" type="hidden" value="1">
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: testar o buff"></label>
        <button class="primary small" type="submit">Dar</button><span class="msg" role="status"></span></form>
      <form class="row grant" data-kind="missions"><strong>Completar missões</strong>
        <label>Quais<select name="item"><option value="daily">Diárias de hoje</option><option value="weekly">Semanais</option></select></label>
        <input name="value" type="hidden" value="1">
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: testar o pacote"></label>
        <button class="primary small" type="submit">Completar</button><span class="msg" role="status"></span></form>
      <form class="row grant" data-kind="stars"><strong>Dar Estrelas</strong>
        <label>Quantidade<input name="value" type="number" min="-1000" max="1000" value="10" required style="width:90px"></label>
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: testar a loja de Estrelas"></label>
        <button class="primary small" type="submit">Dar</button><span class="msg" role="status"></span></form>
      <form class="row grant" data-kind="village"><strong>Encerrar a Encomenda da semana</strong> <small>(vale para todos; os prêmios saem no próximo acesso de cada um)</small>
        <input name="value" type="hidden" value="1">
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: testar os prêmios"></label>
        <button class="primary small" type="submit">Encerrar</button><span class="msg" role="status"></span></form>
      <form class="row grant" data-kind="gold"><strong>Dar ouro</strong>
        <label>Valor<input name="value" type="number" min="-1000000000" max="1000000000" step="1" value="10000" required style="width:140px"></label>
        <label style="flex:1">Justificativa<input name="reason" minlength="5" required placeholder="ex.: testar a compra de lotes"></label>
        <button class="primary small" type="submit">Dar</button><span class="msg" role="status"></span></form></div>
      <p>Veículos: ${(f.vehicles ?? []).map((v: any) => `${esc(v.vehicle_id)} (${esc(v.rarity)}, ${Number(v.durability).toFixed(0)}%${v.refurb_rarity ? `, reforma → ${esc(v.refurb_rarity)}` : ''})`).join(' · ') || '—'}
        · Viagens: ${(f.expeditions ?? []).map((x: any) => `${esc(x.vehicle_id)} → ${esc(x.route_id)} ${x.status === 'back' ? '(voltou)' : `(volta em ${Math.max(0, Math.ceil((x.returns_at - f.farm_time) / 60))} min)`}${x.seq ? ` rep. ${x.seq}` : ''}`).join(' · ') || '—'} · falhas seguidas: ${f.exp_fail_streak ?? 0}</p>
      <p>Animais: ${(f.animals ?? []).map((a: any) => `${esc(a.house_id)}-${a.slot} ${esc(a.animal_id)} (${esc(a.rarity)}${a.state === 'hungry' ? ', com fome' : ''})`).join(' · ') || '—'}</p>
      <p>Personagens: ${(f.characters ?? []).map((c: any) => `${esc(c.class_id)} Nv ${c.level} (${esc(c.slot === 'field' ? 'campo' : 'banco')}, energia ${Number(c.energy).toFixed(0)}${Number(c.debt) > 0 ? `, deve ${formatGold(Number(c.debt))} há ${c.unpaid_days} dia(s)` : ''})`).join(' · ') || '—'}
        · Pets: ${(f.pets ?? []).map((p: any) => `${esc(p.pet_id)} (afinidade ${p.affinity}${p.active ? ', ativo' : ''})`).join(' · ') || '—'} · último salário: ${esc(f.last_payday ?? '—')}</p>
      ${f.trees.length ? `<p>Árvores: ${f.trees.map((t: any) => `${esc(t.lot_id)}-${t.slot}: ${esc(t.fruit_id ?? 'vazia')}`).join(' · ')}</p>` : ''}
      <table><thead><tr><th>Canteiro</th><th>Cultivo</th><th>Estado</th><th>Pronto em (tempo da fazenda)</th><th>Parado</th></tr></thead><tbody>${
      f.plots.map((p: any) => `<tr><td>${esc(p.plot_id)}</td><td>${esc(p.crop_id ?? '—')}</td><td>${esc(p.state)}</td><td>${p.ready_at ? (p.ready_at / 3600).toFixed(2) + ' h' : '—'}</td><td>${esc(p.stalled_reason ?? '')}</td></tr>`).join('')}</tbody></table>`;
  }
  box.innerHTML = `<div class="card"><div class="tabs" role="tablist">${tabs}</div><div class="table-wrap">${body}</div></div>`;
  box.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach((b) => b.addEventListener('click', () => void detail(id, b.dataset.tab as 'ledger' | 'audit' | 'farm' | 'reports')));
  // ferramentas de teste (Escritura, nível, limpeza, salário e ouro): o servidor exige 2FA e registra tudo na auditoria
  box.querySelectorAll<HTMLFormElement>('form.grant').forEach((form) => form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const d = new FormData(form);
    const msg = form.querySelector('.msg')!;
    const raw = String(d.get('value') ?? ''), value = Number(raw), reason = String(d.get('reason'));
    if (form.dataset.kind === 'cleanup' && !raw) { msg.textContent = 'Nenhum lote em limpeza.'; return; }
    const call = form.dataset.kind === 'trips' ? supabase!.rpc('admin_finish_expeditions', { p_user: id, p_reason: reason })
      : form.dataset.kind === 'card' ? supabase!.rpc('admin_grant_card', { p_user: id, p_card: String(d.get('item')).split(':')[0], p_rarity: String(d.get('item')).split(':')[1], p_reason: reason })
      : form.dataset.kind === 'stars' ? supabase!.rpc('admin_grant_stars', { p_user: id, p_amount: value, p_reason: reason })
      : form.dataset.kind === 'village' ? supabase!.rpc('admin_close_village', { p_reason: reason })
      : form.dataset.kind === 'missions' ? supabase!.rpc('admin_complete_missions', { p_user: id, p_kind: String(d.get('item')), p_reason: reason })
      : form.dataset.kind === 'item' ? supabase!.rpc('admin_grant_item', { p_user: id, p_item: String(d.get('item')), p_qty: value, p_reason: reason })
      : form.dataset.kind === 'animals' ? supabase!.rpc('admin_finish_animals', { p_user: id, p_reason: reason })
      : form.dataset.kind === 'payday' ? supabase!.rpc('admin_force_payday', { p_user: id, p_reason: reason })
      : form.dataset.kind === 'cleanup' ? supabase!.rpc('admin_finish_cleanup', { p_user: id, p_lot: raw === '*' ? null : raw, p_reason: reason })
      : form.dataset.kind === 'deed' ? supabase!.rpc('admin_grant_item', { p_user: id, p_item: 'deed', p_qty: value, p_reason: reason })
      : form.dataset.kind === 'level' ? supabase!.rpc('admin_set_level', { p_user: id, p_level: value, p_reason: reason })
      : supabase!.rpc('admin_grant_gold', { p_user: id, p_amount: value, p_reason: reason });
    const { error } = await call;
    if (error) { msg.textContent = error.message; return; }
    void detail(id, 'farm');
  }));
}

void start();
