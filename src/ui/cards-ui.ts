// Missões e cartas na interface: botões e slots de buff no topo, painel de Missões, painel de Cartas
// (Fichário, Armory e chances) e o pacote que abre virando a carta.
import { CARDS } from '../data';
import {
  armoryLines, armoryStatus, buffDuration, buffLines, CARD_LIST, cardDef, cardFaceLines, missionProgress, missionText, pityLeft, RARITY_LIST, rarityInfo, rarityRank,
} from '../farm/cards';
import { store } from '../farm/store';
import { armoryPlace, binderExpand, cardsSeen, rerollMission, sellCard, useCard, type CardState, type FarmState } from '../net/farmApi';
import { formatGold } from './format';

export type CardsCtx = {
  show: (title: string, body: () => string, bind?: (el: HTMLElement) => void) => void;
  act: (fn: () => Promise<FarmState>, ok?: string) => Promise<void>;
  sprite: (key: string | null, scale?: number, cls?: string, filter?: string) => string;
  esc: (s: string) => string;
  root: HTMLElement;
};

const nf = new Intl.NumberFormat('pt-BR');
const pctTxt = (x: number) => `${new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 2 }).format(x * 100)}%`;
const left = (iso: string, ms: number) => {
  const m = Math.max(0, Math.ceil((Date.parse(iso) - ms) / 60_000));
  return m >= 60 ? `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')}` : `${m} min`;
};

/** carta desenhada: ilustração 44×64 por baixo e a moldura da raridade por cima (escala inteira) */
export function cardHtml(ctx: CardsCtx, cardId: string, rarity: string, scale = 1, extra = ''): string {
  const d = cardDef(cardId);
  const frame = (CARDS.frames as Record<string, string>)[rarity];
  const [w, h] = CARDS.dimensions.card_base, [aw, ah] = CARDS.dimensions.center_illustration;
  return `<span class="tcard r-${rarity} ${extra}" style="width:${w * scale}px;height:${h * scale}px" title="${ctx.esc(`${d?.name_pt ?? cardId} ${rarityInfo(rarity)?.name_pt ?? ''}`)}">
    <span class="tc-art" style="left:${((w - aw) / 2) * scale}px;top:${((h - ah) / 2) * scale}px">${ctx.sprite(d?.sprite_key ?? null, scale)}</span>
    <span class="tc-frame">${ctx.sprite(frame, scale)}</span>${scale >= 2 ? faceText(ctx, cardId, rarity, scale) : ''}</span>`;
}

/** efeito escrito no quadro da carta, com a fonte que couber (o quadro tem 38×12 da carta de 64×96) */
function faceText(ctx: CardsCtx, cardId: string, rarity: string, scale: number): string {
  const lines = cardFaceLines(cardId, rarity);
  const w = 38 * scale, h = 12 * scale;
  let f = scale * 4;
  const rows = (size: number) => lines.reduce((n, l) => n + Math.ceil((l.length * size * 0.6) / w), 0);
  while (f > 4.5 && rows(f) * f * 1.1 > h) f -= 0.25;
  return `<span class="tc-name" style="font-size:${f}px">${lines.map((l) => `<span>${ctx.esc(l)}</span>`).join('')}</span>`;
}

/** botões do topo e os 3 slots de buff (ícone da carta e o tempo que falta) */
export function hudCards(ctx: CardsCtx, s: FarmState, ms: number): string {
  if (!s.missions) return '';
  const daily = s.missions.filter((m) => m.kind === 'daily');
  const done = daily.filter((m) => m.done).length;
  const max = CARDS.rules.max_active_buffs;
  const slots = Array.from({ length: max }, (_, i) => {
    const b = s.buffs[i];
    if (!b) return '<span class="buff-slot empty" title="Slot de carta livre"></span>';
    const d = cardDef(b.card_id);
    return `<span class="buff-slot" style="--rc:${rarityInfo(b.rarity)?.color_hex}" title="${ctx.esc(`${d?.name_pt} ${rarityInfo(b.rarity)?.name_pt}: ${buffLines(b.card_id, b.rarity).join(', ')}`)}">${ctx.sprite(d?.icon_key ?? null, 2)}<small>${left(b.ends_at, ms)}</small></span>`;
  }).join('');
  const fresh = s.new_cards.length ? '<span class="dot" title="Carta nova"></span>' : '';
  return `<button type="button" class="hud-btn ghost" data-missions title="Missões">Missões <small>${done}/${daily.length}</small></button>
    <button type="button" class="hud-btn ghost" data-cards title="Cartas">Cartas${fresh}</button>
    <span class="buff-slots" data-cards>${slots}</span>`;
}

// ---------- missões ----------
export function openMissions(ctx: CardsCtx): void {
  ctx.show('Missões', () => missionsBody(ctx), (el) => {
    el.querySelectorAll<HTMLButtonElement>('[data-reroll]').forEach((b) => b.addEventListener('click', () => {
      b.disabled = true;
      void ctx.act(() => rerollMission(Number(b.dataset.reroll)), 'Missão trocada.');
    }));
  });
}

function missionsBody(ctx: CardsCtx): string {
  const s = store.state;
  if (!s) return '<p>Carregando…</p>';
  const row = (m: FarmState['missions'][number]) => {
    const p = missionProgress(m.metric, m.progress, m.target);
    const reward = m.kind === 'daily' ? `+${formatGold(m.reward.gold ?? 0)} ouro · +${nf.format(Math.round(m.reward.xp ?? 0))} XP` : '';
    return `<li class="mission ${m.done ? 'done' : ''}">
      <div class="m-top"><span>${m.done ? '✓ ' : ''}${ctx.esc(missionText(m.id, m.target))}</span>
        ${m.kind === 'daily' && !m.done && !s.reroll_used ? `<button type="button" class="secondary small" data-reroll="${m.slot}">Trocar</button>` : ''}</div>
      <span class="m-bar"><span style="width:${Math.round(p.pct * 100)}%"></span></span>
      <small>${p.text}${reward ? ` · ${reward}` : ''}</small></li>`;
  };
  const daily = s.missions.filter((m) => m.kind === 'daily'), weekly = s.missions.filter((m) => m.kind === 'weekly');
  const wd = weekly.filter((m) => m.done).length, maxPacks = CARDS.rules.weekly_mission_packs.max_daily_packs_per_week;
  return `<h3>Diárias <small class="muted">renovam à meia-noite do seu fuso</small></h3>
    <ul class="missions">${daily.map(row).join('')}</ul>
    <p class="status">As 5 do dia: <strong>1 pacote com 1 carta</strong> ${s.pack_today ? '✓ recebido hoje' : ''} · ${s.mission_week.daily_packs} de ${maxPacks} pacotes nesta semana.
      ${s.reroll_used ? 'Troca grátis de hoje já usada.' : '1 troca grátis por dia.'}</p>
    <h3>Semanais <small class="muted">renovam na segunda à meia-noite</small></h3>
    <ul class="missions">${weekly.map(row).join('')}</ul>
    <p class="status">${wd >= 3 ? '✓' : '○'} 3 completas: 1 carta · ${wd >= 5 ? '✓' : '○'} as 5: +1 carta e 1 Escritura</p>
    <p class="hint">As metas são medidas na sua própria produção por hora (${formatGold(s.prod_ref.value_h)} em valor da Feira). O que a equipe faz sozinha também conta.</p>`;
}

// ---------- cartas ----------
let tab: 'binder' | 'armory' | 'odds' = 'binder';
let picked: string | null = null; // "carta:raridade" escolhida no fichário

export function openCards(ctx: CardsCtx, start: 'binder' | 'armory' | 'odds' = 'binder'): void {
  tab = start; picked = null;
  ctx.show('Cartas', () => cardsBody(ctx), (el) => bindCards(ctx, el));
}

function groups(cards: CardState[]): { key: string; card_id: string; rarity: string; list: CardState[] }[] {
  const m = new Map<string, CardState[]>();
  for (const c of cards) { const k = `${c.card_id}:${c.rarity}`; m.set(k, [...(m.get(k) ?? []), c]); }
  return [...m.entries()].map(([key, list]) => ({ key, card_id: list[0].card_id, rarity: list[0].rarity, list }))
    .sort((a, b) => rarityRank(b.rarity) - rarityRank(a.rarity) || CARD_LIST.findIndex((c) => c.id === a.card_id) - CARD_LIST.findIndex((c) => c.id === b.card_id));
}

function cardsBody(ctx: CardsCtx): string {
  const s = store.state;
  if (!s) return '<p>Carregando…</p>';
  const tabs = ([['binder', 'Fichário'], ['armory', 'Armory'], ['odds', 'Chances']] as const)
    .map(([k, n]) => `<button type="button" role="tab" data-ctab="${k}" aria-selected="${tab === k}">${n}</button>`).join('');
  let body = '';
  if (tab === 'binder') body = binderBody(ctx, s);
  else if (tab === 'armory') body = armoryBody(ctx, s);
  else body = oddsBody(s);
  return `<div class="chips" role="tablist">${tabs}</div>${body}`;
}

function binderBody(ctx: CardsCtx, s: FarmState): string {
  const inBinder = s.cards.filter((c) => c.state === 'binder'), inbox = s.cards.filter((c) => c.state === 'inbox');
  const ms = store.clock.serverNow();
  const gs = groups(s.cards);
  const grid = gs.length ? gs.map((g) => `<button type="button" class="card-btn ${picked === g.key ? 'on' : ''}" data-pick="${g.key}">
      ${cardHtml(ctx, g.card_id, g.rarity, 1)}${g.list.length > 1 ? `<span class="count">×${g.list.length}</span>` : ''}
      ${g.list.some((c) => c.state === 'inbox') ? '<span class="tag">caixa</span>' : ''}</button>`).join('')
    : '<p class="hint">Nenhuma carta ainda. Complete as 5 missões do dia para ganhar um pacote.</p>';
  let detail = '';
  const g = gs.find((x) => x.key === picked);
  if (g) {
    const d = cardDef(g.card_id)!, r = rarityInfo(g.rarity)!;
    const c = g.list[0];
    const active = s.buffs.find((b) => b.card_id === g.card_id);
    const full = !active && s.buffs.length >= CARDS.rules.max_active_buffs;
    const lower = active && rarityRank(g.rarity) < rarityRank(active.rarity);
    const inArmory = armoryStatus(s.armory, g.card_id).has.has(g.rarity);
    detail = `<div class="card-detail">${cardHtml(ctx, g.card_id, g.rarity, 2)}
      <div class="grow"><h3 style="color:${r.color_hex}">${ctx.esc(d.name_pt)} ${ctx.esc(r.name_pt)}</h3>
        <p>${ctx.esc(d.description_pt)}</p>
        <ul class="eff">${buffLines(g.card_id, g.rarity).map((l) => `<li>${ctx.esc(l)}</li>`).join('')}</ul>
        <p class="hint">Dura ${buffDuration(g.rarity)} e continua com o jogo fechado. Nº de série ${c.serial}${c.state === 'inbox' && c.inbox_until ? ` · na caixa de entrada até ${new Date(c.inbox_until).toLocaleDateString('pt-BR')}` : ''}.</p>
        <div class="row">
          <button type="button" class="primary small" data-use="${c.serial}" ${full || lower ? 'disabled' : ''}>Usar</button>
          <button type="button" class="secondary" data-armory="${c.serial}" ${inArmory ? 'disabled' : ''}>Pôr no Armory</button>
          <button type="button" class="secondary" data-sell="${c.serial}">Vender (${formatGold(s.collector[g.rarity] ?? 0)})</button>
        </div>
        <p class="hint">${full ? 'Já tem 3 cartas ativas. ' : ''}${lower ? 'Essa carta já está ativa com raridade maior. ' : ''}${active && !lower ? 'Usar agora troca o buff ativo e reinicia o tempo. ' : ''}${inArmory ? 'Essa raridade já está no Armory. ' : 'No Armory a carta fica para sempre e dá bônus permanente (não dá mais para usar nem vender). '}</p>
      </div></div>`;
  }
  const canGrow = s.binder_slots + CARDS.binder.expansion_slots <= CARDS.binder.max_slots;
  return `<p class="status">${inBinder.length} de ${s.binder_slots} espaços${inbox.length ? ` · <strong>${inbox.length} na caixa de entrada</strong> (o Colecionador compra sozinho depois de ${CARDS.binder.inbox_overflow_retention_days} dias)` : ''}
      ${canGrow ? ` · <button type="button" class="secondary small" data-expand>+${CARDS.binder.expansion_slots} espaços (${formatGold(s.binder_expand_cost)})</button>` : ''}</p>
    ${detail}<div class="card-grid">${grid}</div>
    ${s.buffs.length ? `<h3>Ativas</h3><ul class="eff">${s.buffs.map((b) => `<li><strong>${ctx.esc(cardDef(b.card_id)?.name_pt ?? b.card_id)} ${ctx.esc(rarityInfo(b.rarity)?.name_pt ?? '')}</strong> · falta ${left(b.ends_at, ms)}${b.coin_value > 0 ? ` · ${formatGold(b.coin_value)} de ouro juntado` : ''}</li>`).join('')}</ul>` : ''}`;
}

function armoryBody(ctx: CardsCtx, s: FarmState): string {
  const rows = CARD_LIST.map((d) => {
    const st = armoryStatus(s.armory, d.id);
    const frames = RARITY_LIST.map((r) => `<span class="arm-slot ${st.has.has(r) ? 'on' : ''}" title="${rarityInfo(r)?.name_pt}">${st.has.has(r) ? cardHtml(ctx, d.id, r, 1) : cardHtml(ctx, d.id, r, 1, 'ghost')}</span>`).join('');
    const bonus = st.level === 'none' ? `<small>Parcial (Comum + Incomum + Raro): ${ctx.esc(armoryLines(d.id, 'partial').join(', '))}</small>`
      : `<small class="${st.level}">${st.level === 'complete' ? 'Completo' : 'Parcial'}: ${ctx.esc(armoryLines(d.id, st.level).join(', '))}</small>`;
    return `<li class="arm-row"><strong>${ctx.esc(d.name_pt)}</strong>${bonus}<div class="arm-slots">${frames}</div></li>`;
  }).join('');
  const done = CARD_LIST.filter((d) => armoryStatus(s.armory, d.id).level === 'complete').length;
  return `<p class="status">Bônus permanentes da coleção · ${done} de ${CARD_LIST.length} cartas completas</p>
    <ul class="armory">${rows}</ul>
    <p class="hint">Pôr uma carta no Armory consome a cópia: ela fica exposta para sempre. As 5 raridades substituem o bônus parcial pelo completo.</p>`;
}

function oddsBody(s: FarmState): string {
  const p = pityLeft(s.pity);
  const rates = RARITY_LIST.map((r) => `<li><span style="color:${rarityInfo(r)?.color_hex}">■</span> ${rarityInfo(r)?.name_pt}: ${pctTxt((CARDS.gacha.base_rates as Record<string, number>)[r])} <small>(com a garantia, ${pctTxt((CARDS.gacha.effective_rates_with_pity as Record<string, number>)[r])})</small></li>`).join('');
  return `<h3>Chance de cada raridade</h3><ul class="eff">${rates}</ul>
    <p>Dentro da raridade, as ${CARD_LIST.length} cartas têm a mesma chance.</p>
    <h3>Garantia</h3>
    <ul class="eff"><li>Raro ou melhor em até <strong>${p.rare}</strong> cartas</li><li>Lendário ou melhor em até <strong>${p.legendary}</strong></li><li>Mítico em até <strong>${p.mythic}</strong></li></ul>
    <p class="hint">Cartas só vêm das missões: até ${CARDS.rules.weekly_mission_packs.max_daily_packs_per_week} pacotes por semana das diárias e 2 cartas das semanais. Não existe pacote à venda.</p>`;
}

function bindCards(ctx: CardsCtx, el: HTMLElement): void {
  const rerender = () => ctx.show('Cartas', () => cardsBody(ctx), (e) => bindCards(ctx, e));
  el.querySelectorAll<HTMLButtonElement>('[data-ctab]').forEach((b) => b.addEventListener('click', () => { tab = b.dataset.ctab as typeof tab; picked = null; rerender(); }));
  el.querySelectorAll<HTMLButtonElement>('[data-pick]').forEach((b) => b.addEventListener('click', () => { picked = picked === b.dataset.pick ? null : b.dataset.pick!; rerender(); }));
  const one = (sel: string, fn: (n: number) => Promise<FarmState>, ok: string) => el.querySelector<HTMLButtonElement>(sel)?.addEventListener('click', (e) => {
    const b = e.currentTarget as HTMLButtonElement; b.disabled = true;
    const serial = Number(b.dataset.use ?? b.dataset.armory ?? b.dataset.sell);
    void ctx.act(() => fn(serial), ok).then(() => { picked = null; });
  });
  one('[data-use]', useCard, 'Carta ativada!');
  one('[data-armory]', armoryPlace, 'Carta guardada no Armory.');
  one('[data-sell]', sellCard, 'Vendida ao Colecionador da Vila.');
  el.querySelector('[data-expand]')?.addEventListener('click', () => void ctx.act(binderExpand, 'Fichário ampliado.'));
}

// ---------- pacote: a carta vira ----------
let opening = false;
export function maybeOpenPack(ctx: CardsCtx, s: FarmState): void {
  if (opening || !s.new_cards?.length) return;
  if (!ctx.sprite(CARDS.frames.back, 1)) return; // as artes ainda estão carregando: abre quando chegarem
  opening = true;
  const cards = [...s.new_cards];
  let i = 0;
  const ov = document.createElement('div');
  ov.className = 'pack-overlay';
  const calm = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const ORIGIN: Record<string, string> = { daily_pack: 'Pacote das missões do dia', weekly_3: '3 missões semanais', weekly_5: '5 missões semanais', admin: 'Presente do painel' };
  const draw = () => {
    const c = cards[i];
    const r = rarityInfo(c.rarity)!;
    ov.innerHTML = `<div class="pack" role="dialog" aria-label="Carta nova">
      <p class="muted">${ctx.esc(ORIGIN[c.origin] ?? 'Carta nova')}${cards.length > 1 ? ` · ${i + 1} de ${cards.length}` : ''}</p>
      <div class="flip ${calm ? 'flipped' : ''}" style="--rc:${r.color_hex}">
        <div class="face back">${ctx.sprite(CARDS.frames.back, 3)}</div>
        <div class="face front">${cardHtml(ctx, c.card_id, c.rarity, 3)}</div>
      </div>
      <h3 class="pack-name" style="color:${r.color_hex}">${ctx.esc(cardDef(c.card_id)?.name_pt ?? c.card_id)} · ${ctx.esc(r.name_pt)}</h3>
      <ul class="eff">${buffLines(c.card_id, c.rarity).map((l) => `<li>${ctx.esc(l)}</li>`).join('')}</ul>
      <button type="button" class="primary small" data-next>${i + 1 < cards.length ? 'Próxima carta' : 'Guardar no fichário'}</button></div>`;
    const f = ov.querySelector('.flip')!;
    if (!calm) window.setTimeout(() => f.classList.add('flipped'), 450); // o verso aparece e vira
    ov.querySelector('[data-next]')!.addEventListener('click', () => {
      i++;
      if (i < cards.length) draw();
      else { ov.remove(); void ctx.act(cardsSeen).finally(() => { opening = false; }); }
    });
  };
  ctx.root.appendChild(ov);
  draw();
}
