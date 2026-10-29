// Amigos e visitas na interface: botão Amigos no topo, painel (amigos, novidades, busca, bloqueados),
// e o modo visita (topo da visita, Ajudar num lote, Curtir, recado de emojis e voltar).
import { LOTS, SOCIAL } from '../data';
import { applyVisit, leaveVisit, store } from '../farm/store';
import {
  blockPlayer, friendRemove, friendRequest, friendRespond, getSocial, helpLot, likeFarm, reportPlayer, searchPlayers, sendNote, socialSeen, visitFarm,
  type PlayerCard, type SocialActivity, type SocialState, type VisitView,
} from '../net/farmApi';

export type SocialCtx = {
  show: (title: string, body: () => string, bind?: (el: HTMLElement) => void) => void;
  close: () => void;
  toast: (msg: string, seconds?: number) => void;
  esc: (s: string) => string;
};

const LOT_TYPE_PT: Record<string, string> = { lavoura: 'Lavoura', pomar: 'Pomar', pasto_galinheiro: 'Galinheiro', pasto_celeiro: 'Celeiro' };
const ago = (iso: string) => {
  const m = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 60_000));
  if (m < 1) return 'agora';
  if (m < 60) return `há ${m} min`;
  if (m < 1440) return `há ${Math.round(m / 60)} h`;
  return `há ${Math.round(m / 1440)} d`;
};
const left = (iso: string) => {
  const m = Math.max(0, Math.ceil((Date.parse(iso) - Date.now()) / 60_000));
  return m >= 60 ? `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')}` : `${m} min`;
};

// ---------- botão do topo ----------
/** botão Amigos com o ponto vermelho quando há pedido ou novidade */
export function hudSocial(): string {
  const s = store.state?.social;
  const n = (s?.incoming ?? 0) + (s?.unseen ?? 0);
  return `<button type="button" class="hud-btn ghost" data-social title="Amigos e visitas">Amigos${n ? `<span class="dot" title="${n} novidade${n > 1 ? 's' : ''}"></span>` : ''}</button>`;
}

// ---------- painel Amigos ----------
let tab: 'friends' | 'news' | 'search' | 'blocked' = 'friends';
let social: SocialState | null = null;
let results: PlayerCard[] | null = null;
let query = '';
let reporting: string | null = null; // jogador com o formulário de denúncia aberto

export async function openSocial(ctx: SocialCtx, start: typeof tab = (store.state?.social?.unseen ? 'news' : 'friends')): Promise<void> {
  tab = start; results = null; reporting = null;
  try { social = await getSocial(); } catch (e) { ctx.toast(e instanceof Error ? e.message : 'Não deu certo.'); return; }
  if (tab === 'news') void markSeen();
  render(ctx);
}

async function markSeen(): Promise<void> {
  if (!social?.activity.some((a) => a.new)) return;
  try { await socialSeen(); if (store.state?.social) store.state.social.unseen = 0; } catch { /* sem importância */ }
}

function render(ctx: SocialCtx): void {
  ctx.show('Amigos', () => body(ctx), (el) => bind(ctx, el));
}

function body(ctx: SocialCtx): string {
  const s = social!;
  const newN = s.activity.filter((a) => a.new).length;
  const tabs = ([['friends', `Amigos${s.incoming.length ? ` (${s.incoming.length})` : ''}`], ['news', `Novidades${newN ? ` (${newN})` : ''}`], ['search', 'Buscar'], ['blocked', 'Bloqueados']] as const)
    .map(([k, n]) => `<button type="button" role="tab" data-stab="${k}" aria-selected="${tab === k}">${n}</button>`).join('');
  const lim = `<p class="status">Ajudas hoje: <strong>${s.helps_given}/${SOCIAL.help.given_per_day}</strong> dadas · ${s.helps_received}/${SOCIAL.help.received_per_day} recebidas · ❤️ ${s.likes} curtidas na sua fazenda</p>`;
  let inner = '';
  if (tab === 'friends') inner = friendsTab(ctx, s);
  else if (tab === 'news') inner = newsTab(ctx, s);
  else if (tab === 'search') inner = searchTab(ctx);
  else inner = blockedTab(ctx, s);
  return `<div class="chips" role="tablist">${tabs}</div>${lim}${inner}`;
}

function who(ctx: SocialCtx, p: PlayerCard): string {
  return `<span class="who"><strong>${ctx.esc(p.nickname)}</strong> <small>Nv ${p.level} · ❤️ ${p.likes}</small></span>`;
}

function reportForm(ctx: SocialCtx, p: PlayerCard): string {
  if (reporting !== p.id) return '';
  const opts = SOCIAL.report_reasons.map((r) => `<option value="${r.id}">${ctx.esc(r.text_pt)}</option>`).join('');
  return `<div class="report-form"><label>Motivo <select data-reason>${opts}</select></label>
    <button type="button" class="primary small" data-report-send="${p.id}">Enviar denúncia</button>
    <button type="button" class="secondary" data-report-cancel>Cancelar</button></div>`;
}

function more(p: PlayerCard): string {
  return `<button type="button" class="secondary" data-block="${p.id}" title="Bloquear: desfaz a amizade e um não vê mais o outro">Bloquear</button>
    <button type="button" class="secondary" data-report="${p.id}">Denunciar</button>`;
}

function friendsTab(ctx: SocialCtx, s: SocialState): string {
  const inc = s.incoming.map((p) => `<li class="prow">${who(ctx, p)}<span class="acts">
      <button type="button" class="primary small" data-accept="${p.id}">Aceitar</button>
      <button type="button" class="secondary" data-reject="${p.id}">Recusar</button></span>${reportForm(ctx, p)}</li>`).join('');
  const fr = s.friends.map((p) => `<li class="prow">${who(ctx, p)}<span class="acts">
      <button type="button" class="primary small" data-visit="${p.id}">Visitar</button>
      <button type="button" class="secondary" data-remove="${p.id}">Desfazer</button>${more(p)}</span>${reportForm(ctx, p)}</li>`).join('');
  const out = s.outgoing.map((p) => `<li class="prow">${who(ctx, p)}<span class="acts"><small>pedido enviado</small>
      <button type="button" class="secondary" data-remove="${p.id}">Cancelar</button></span></li>`).join('');
  return `<p><button type="button" class="primary small" data-random>Visitar uma fazenda aleatória</button></p>
    ${inc ? `<h3>Pedidos de amizade</h3><ul class="plist">${inc}</ul>` : ''}
    <h3>Amigos (${s.friends.length}/${SOCIAL.friends.max_friends})</h3>
    ${fr ? `<ul class="plist">${fr}</ul>` : '<p class="hint">Nenhum amigo ainda. Use a guia Buscar com o apelido de alguém, ou visite uma fazenda aleatória.</p>'}
    ${out ? `<h3>Esperando resposta</h3><ul class="plist">${out}</ul>` : ''}
    <p class="hint">Na visita você pode Ajudar (+${SOCIAL.help.growth_pct}% de crescimento por 1 h num lote, ou −${SOCIAL.help.cleanup_pct}% na limpeza), Curtir e deixar um recado de emojis. Ajudar dá XP igual a ${SOCIAL.help.xp_minutes_of_production} min da sua produção.</p>`;
}

function activityText(ctx: SocialCtx, a: SocialActivity): string {
  const n = `<strong>${ctx.esc(a.from.nickname)}</strong>`;
  if (a.kind === 'help') return a.help === 'cleanup' ? `${n} ajudou na limpeza do lote ${ctx.esc(a.lot ?? '')} (−${a.pct}% do tempo)` : `${n} ajudou o lote ${ctx.esc(a.lot ?? '')} (+${a.pct}% de crescimento por 1 h)`;
  if (a.kind === 'like') return `${n} curtiu sua fazenda`;
  return `${n} deixou um recado: <span class="emojis">${(a.emojis ?? []).map(ctx.esc).join(' ')}</span>`;
}

function newsTab(ctx: SocialCtx, s: SocialState): string {
  if (!s.activity.length) return `<p class="hint">Nada nos últimos ${SOCIAL.activity_days} dias. Quando alguém ajudar, curtir ou deixar recado, aparece aqui.</p>`;
  const icon = { help: '🤝', like: '❤️', note: '💬' };
  return `<ul class="plist">${s.activity.map((a) => `<li class="prow ${a.new ? 'new' : ''}"><span class="who">${icon[a.kind]} ${activityText(ctx, a)} <small>${ago(a.at)}</small></span>
    <span class="acts"><button type="button" class="secondary" data-visit="${a.from.id}">Visitar</button>${more(a.from)}</span>${reportForm(ctx, a.from)}</li>`).join('')}</ul>`;
}

function searchTab(ctx: SocialCtx): string {
  const label: Record<string, string> = { friend: 'amigo', sent: 'pedido enviado', blocked: 'bloqueado' };
  const list = results === null ? '' : results.length ? `<ul class="plist">${results.map((p) => `<li class="prow">${who(ctx, p)}<span class="acts">
      ${p.status === 'none' ? `<button type="button" class="secondary" data-add="${p.id}">Pedir amizade</button>` : ''}
      ${p.status === 'received' ? `<button type="button" class="primary small" data-accept="${p.id}">Aceitar pedido</button>` : ''}
      ${label[p.status ?? ''] ? `<small>${label[p.status!]}</small>` : ''}
      ${p.status !== 'blocked' ? `<button type="button" class="primary small" data-visit="${p.id}">Visitar</button>` : ''}</span></li>`).join('')}</ul>`
    : '<p class="hint">Ninguém com esse apelido.</p>';
  return `<form class="row search" data-search><label style="flex:1">Apelido<input name="q" minlength="${SOCIAL.search.min_chars}" maxlength="20" required value="${ctx.esc(query)}" placeholder="começo do apelido"></label>
    <button type="submit" class="primary small">Buscar</button></form>${list}`;
}

function blockedTab(ctx: SocialCtx, s: SocialState): string {
  if (!s.blocked.length) return '<p class="hint">Ninguém bloqueado. Quem você bloqueia não te acha, não visita sua fazenda e não manda recado.</p>';
  return `<ul class="plist">${s.blocked.map((p) => `<li class="prow">${who(ctx, p)}<span class="acts"><button type="button" class="secondary" data-unblock="${p.id}">Desbloquear</button></span></li>`).join('')}</ul>`;
}

function bind(ctx: SocialCtx, el: HTMLElement): void {
  const run = async (fn: () => Promise<SocialState>, ok?: string) => {
    try { social = await fn(); reporting = null; if (ok) ctx.toast(ok); render(ctx); } catch (e) { ctx.toast(e instanceof Error ? e.message : 'Não deu certo.'); }
  };
  const on = (sel: string, f: (id: string, b: HTMLButtonElement) => void) =>
    el.querySelectorAll<HTMLButtonElement>(`[${sel}]`).forEach((b) => b.addEventListener('click', () => f(b.getAttribute(sel)!, b)));
  on('data-stab', (k) => { tab = k as typeof tab; reporting = null; if (tab === 'news') void markSeen(); render(ctx); });
  on('data-accept', (id) => void run(() => friendRespond(id, true), 'Agora vocês são amigos.'));
  on('data-reject', (id) => void run(() => friendRespond(id, false)));
  on('data-remove', (id) => void run(() => friendRemove(id)));
  on('data-add', (id) => void run(async () => { const s = await friendRequest(id); if (results) results = results.map((p) => (p.id === id ? { ...p, status: s.friends.some((f) => f.id === id) ? 'friend' : 'sent' } : p)); return s; }, 'Pedido enviado.'));
  on('data-block', (id) => void run(() => blockPlayer(id, true), 'Jogador bloqueado.'));
  on('data-unblock', (id) => void run(() => blockPlayer(id, false), 'Desbloqueado.'));
  on('data-report', (id) => { reporting = id; render(ctx); });
  el.querySelector('[data-report-cancel]')?.addEventListener('click', () => { reporting = null; render(ctx); });
  on('data-report-send', (id) => {
    const reason = el.querySelector<HTMLSelectElement>('[data-reason]')!.value;
    void run(() => reportPlayer(id, reason), 'Denúncia enviada. Obrigado.');
  });
  on('data-visit', (id, b) => { b.disabled = true; void startVisit(ctx, id); });
  el.querySelector('[data-random]')?.addEventListener('click', (e) => { (e.currentTarget as HTMLButtonElement).disabled = true; void startVisit(ctx, null); });
  el.querySelector<HTMLFormElement>('[data-search]')?.addEventListener('submit', (e) => {
    e.preventDefault();
    query = new FormData(e.currentTarget as HTMLFormElement).get('q') as string;
    void searchPlayers(query).then((r) => { results = r; render(ctx); }).catch((err) => ctx.toast(err instanceof Error ? err.message : 'Não deu certo.'));
  });
}

// ---------- visita ----------
export async function startVisit(ctx: SocialCtx, id: string | null): Promise<void> {
  try { const v = await visitFarm(id); ctx.close(); applyVisit(v); ctx.toast(`Visitando a fazenda de ${v.owner.nickname}. Clique num lote para ajudar.`, 4); }
  catch (e) { ctx.toast(e instanceof Error ? e.message : 'Não deu certo.'); }
}

async function visitAct(ctx: SocialCtx, fn: () => Promise<VisitView>, ok?: string): Promise<void> {
  try { applyVisit(await fn()); if (ok) ctx.toast(ok); } catch (e) { ctx.toast(e instanceof Error ? e.message : 'Não deu certo.'); }
}

/** topo durante a visita: dono, curtir, recado, ajudas e voltar */
export function visitHud(ctx: SocialCtx, v: VisitView): string {
  const o = v.owner, l = v.limits;
  return `<span class="visit-tag">Visitando <strong>${ctx.esc(o.nickname)}</strong> · Nv ${o.level} · ❤️ ${o.likes}</span>
    <span class="wx-slot"></span>
    <span class="visit-lim" title="Suas ajudas de hoje">🤝 ${l.given}/${l.given_max}</span>
    <button type="button" class="hud-btn ghost" data-like ${l.liked ? 'disabled' : ''}>${l.liked ? 'Curtido ❤️' : 'Curtir ❤️'}</button>
    <button type="button" class="hud-btn ghost" data-note ${l.noted ? 'disabled' : ''}>${l.noted ? 'Recado deixado' : 'Recado 💬'}</button>
    ${o.status === 'none' ? '<button type="button" class="hud-btn ghost" data-friend>Pedir amizade</button>' : ''}
    ${o.status === 'received' ? '<button type="button" class="hud-btn ghost" data-friend-accept>Aceitar amizade</button>' : ''}
    <button type="button" class="hud-btn" data-leave>Voltar para minha fazenda</button>`;
}

export function bindVisitHud(ctx: SocialCtx, hud: HTMLElement, v: VisitView): void {
  const id = v.owner.id;
  hud.querySelector('[data-leave]')?.addEventListener('click', () => { leaveVisit(); });
  hud.querySelector('[data-like]')?.addEventListener('click', () => void visitAct(ctx, () => likeFarm(id), 'Curtiu ❤️'));
  hud.querySelector('[data-note]')?.addEventListener('click', () => openNote(ctx, v));
  hud.querySelector('[data-friend]')?.addEventListener('click', () => void friendRequest(id).then(() => visitAct(ctx, () => visitFarm(id), 'Pedido de amizade enviado.')).catch((e) => ctx.toast(e.message)));
  hud.querySelector('[data-friend-accept]')?.addEventListener('click', () => void friendRespond(id, true).then(() => visitAct(ctx, () => visitFarm(id), 'Agora vocês são amigos.')).catch((e) => ctx.toast(e.message)));
}

function openNote(ctx: SocialCtx, v: VisitView): void {
  const picked: string[] = [];
  const bodyHtml = () => `<p>Escolha até ${SOCIAL.notes.max_emojis} emojis para ${ctx.esc(v.owner.nickname)} (sem texto livre).</p>
    <div class="emoji-grid">${SOCIAL.notes.emojis.map((e) => `<button type="button" class="emoji-btn ${picked.includes(e) ? 'on' : ''}" data-emo="${e}">${e}</button>`).join('')}</div>
    <p class="status">Recado: <span class="emojis">${picked.join(' ') || '—'}</span></p>
    <button type="button" class="primary small" data-send ${picked.length ? '' : 'disabled'}>Deixar recado</button>`;
  const draw = () => ctx.show('Recado', bodyHtml, (el) => {
    el.querySelectorAll<HTMLButtonElement>('[data-emo]').forEach((b) => b.addEventListener('click', () => {
      const e = b.dataset.emo!;
      const i = picked.indexOf(e);
      if (i >= 0) picked.splice(i, 1); // clicar de novo tira
      else if (picked.length < SOCIAL.notes.max_emojis) picked.push(e);
      draw();
    }));
    el.querySelector('[data-send]')?.addEventListener('click', () => { ctx.close(); void visitAct(ctx, () => sendNote(v.owner.id, picked), 'Recado deixado.'); });
  });
  draw();
}

/** clique num lote da fazenda visitada: o que a ajuda faz ali */
export function openHelp(ctx: SocialCtx, lot: string): void {
  const v = store.visit, s = store.state;
  if (!v || !s) return;
  const def = LOTS.find((l) => l.id === lot);
  const owned = s.lots.find((l) => l.lot_id === lot);
  if (!def || !owned) { ctx.toast('Esse lote ainda não é da fazenda.'); return; }
  const now = store.clock.farmNow();
  const cleaning = owned.ready_at > now;
  const growing = s.plots.some((p) => p.plot_id.startsWith(`${lot}-`) && p.state === 'growing') || s.trees.some((t) => t.lot_id === lot && t.fruit_id);
  const cd = v.cooldowns[lot];
  const help = (v.state.helps ?? []).find((h) => h.lot_id === lot);
  let what = '', can = true;
  if (cleaning) what = `Limpeza: −${SOCIAL.help.cleanup_pct}% do tempo que falta.`;
  else if ((def.type === 'lavoura' || def.type === 'pomar') && growing) what = `+${SOCIAL.help.growth_pct}% de crescimento por 1 h em todo o lote.`;
  else { what = 'Nada para ajudar aqui agora (sem plantas crescendo nem limpeza).'; can = false; }
  if (cd && Date.parse(cd) > Date.now()) { can = false; what += ` Já ajudado há pouco: libera em ${left(cd)}.`; }
  const l = v.limits;
  if (l.given >= l.given_max) { can = false; what += ' Suas ajudas de hoje acabaram.'; }
  else if (l.received >= l.received_max) { can = false; what += ' Essa fazenda já recebeu todas as ajudas de hoje.'; }
  ctx.show(`${LOT_TYPE_PT[def.type] ?? 'Lote'} ${lot}`, () => `<p>${what}</p>
    ${help ? `<p class="hint good">Ajuda de ${ctx.esc(help.from)} valendo: +${help.pct}% até acabar em ${left(help.ends_at)}.</p>` : ''}
    <p class="hint">Você ganha ${l.help_xp} XP (10 min da sua produção). Ajudas hoje: ${l.given}/${l.given_max}.</p>
    <button type="button" class="primary small" data-help ${can ? '' : 'disabled'}>Ajudar</button>`, (el) => {
    el.querySelector('[data-help]')?.addEventListener('click', (e) => {
      (e.currentTarget as HTMLButtonElement).disabled = true;
      ctx.close();
      void visitAct(ctx, () => helpLot(v.owner.id, lot), `Ajudou o lote ${lot}! +${l.help_xp} XP`);
    });
  });
}
