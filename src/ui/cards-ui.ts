// Missões e cartas na interface (v3): botões Missões e Cartas no topo, a mão em leque no rodapé com o caixote
// do baralho, painel de Cartas (Fichário, Álbum e chances) e o pacote que abre virando a carta.
import { CARDS } from '../data';
import {
  armoryLines, armoryStatus, buffLines, CARD_LIST, cardArt, cardDef, cardDuration, lifeText, missionProgress, missionText, pityLeft, RARITY_LIST, rarityInfo, rarityRank,
} from '../farm/cards';
import { store } from '../farm/store';
import { binderExpand, cardsSeen, equipCard, repairCard, rerollMission, sellCard, unequipCard, type CardState, type FarmState } from '../net/farmApi';
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
const calm = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/** arte (imagem inteira) pela largura em px; a altura segue a proporção da arte */
function art(key: string, width: number, cls = ''): string {
  const m = store.manifest[key];
  if (!m) return '';
  return `<img class="${cls}" src="assets/${m.file}" width="${width}" height="${Math.round((width * m.size[1]) / m.size[0])}" alt="" draggable="false">`;
}

/** carta: a arte inteira da raridade (moldura, ilustração e texto) */
export function cardHtml(ctx: CardsCtx, cardId: string, rarity: string, width = 70, extra = ''): string {
  const d = cardDef(cardId);
  return `<span class="tcard r-${rarity} ${extra}" style="--rc:${rarityInfo(rarity)?.color_hex}" title="${ctx.esc(`${d?.name_pt ?? cardId} ${rarityInfo(rarity)?.name_pt ?? ''}`)}">${art(cardArt(cardId, rarity), width)}</span>`;
}

/** barra de vida da carta (dias que sobram) */
function lifeBar(left: number, full: number): string {
  const pct = full > 0 ? Math.max(0, Math.min(1, left / full)) : 0;
  return `<span class="life"><span style="width:${Math.round(pct * 100)}%"></span></span>`;
}

/** botões do topo (a mão fica no rodapé) */
export function hudCards(ctx: CardsCtx, s: FarmState): string {
  if (!s.missions) return '';
  const daily = s.missions.filter((m) => m.kind === 'daily');
  const done = daily.filter((m) => m.done).length;
  const fresh = s.new_cards.length ? '<span class="dot" title="Carta nova"></span>' : '';
  return `<button type="button" class="hud-btn ghost" data-missions title="Missões">Missões <small>${done}/${daily.length}</small></button>
    <button type="button" class="hud-btn ghost" data-cards title="Cartas">Cartas${fresh}</button>`;
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

// ---------- a mão (rodapé) ----------
let handOpen = true;
let lastHand: string[] = [];
/** mão em leque no canto direito do rodapé, vagas vazias e uma aba com Fichário e recolher (animação elástica) */
export function renderHand(ctx: CardsCtx, s: FarmState): void {
  let dock = ctx.root.querySelector<HTMLElement>('.hand-dock');
  if (!dock) { dock = document.createElement('div'); dock.className = 'hand-dock'; ctx.root.appendChild(dock); }
  if (!s.missions || store.visit) { dock.hidden = true; return; }
  dock.hidden = false;
  const slots = s.hand_slots ?? 3;
  const ms = store.clock.serverNow();
  const n = Math.max(slots, s.buffs.length);
  const mid = (n - 1) / 2;
  const items = Array.from({ length: n }, (_, i) => {
    const b = s.buffs[i];
    const rot = (i - mid) * 7, lift = Math.abs(i - mid) * 6;
    const style = `--rot:${rot}deg;--lift:${lift}px;--i:${i}`;
    if (!b) return `<button type="button" class="hand-card empty" style="${style}" data-open-binder title="Vaga livre: escolher carta">+</button>`;
    const left = (Date.parse(b.ends_at) - ms) / 1000;
    return `<button type="button" class="hand-card" style="${style};--rc:${rarityInfo(b.rarity)?.color_hex}" data-hand="${b.card_id}" data-serial="${b.serial ?? ''}"
        title="${ctx.esc(`${cardDef(b.card_id)?.name_pt} ${rarityInfo(b.rarity)?.name_pt}: ${buffLines(b.card_id, b.rarity).join(', ')}`)}">
      ${art(cardArt(b.card_id, b.rarity), 84)}<small>${lifeText(left)}</small></button>`;
  }).join('');
  dock.className = `hand-dock ${handOpen ? '' : 'closed'}`;
  dock.innerHTML = `<div class="hand-tab">
      <button type="button" class="hand-binder" data-open-binder title="Fichário: todas as suas cartas">Fichário</button>
      <button type="button" class="hand-toggle" data-toggle-hand title="${handOpen ? 'Recolher a mão' : 'Abrir a mão'}">${art('deck_toggle', 22)}</button>
    </div><div class="hand-fan">${items}</div>`;
  dock.querySelector('[data-toggle-hand]')?.addEventListener('click', () => { handOpen = !handOpen; renderHand(ctx, store.state!); });
  dock.querySelectorAll('[data-open-binder]').forEach((b) => b.addEventListener('click', () => openCards(ctx)));
  dock.querySelectorAll<HTMLButtonElement>('[data-hand]').forEach((b) => b.addEventListener('click', () => openHandCard(ctx, b.dataset.hand!)));
  // carta nova na mão: flash branco, partículas da cor da raridade e tremor na vaga
  const now = s.buffs.map((b) => `${b.card_id}:${b.serial}`);
  if (!calm()) now.forEach((k, i) => { if (lastHand.length && !lastHand.includes(k)) snapFx(dock!.querySelectorAll<HTMLElement>('.hand-card')[i], rarityInfo(s.buffs[i].rarity)?.color_hex ?? '#fff'); });
  lastHand = now;
}

function snapFx(slot: HTMLElement | undefined, color: string): void {
  if (!slot) return;
  slot.classList.add('snap');
  window.setTimeout(() => slot.classList.remove('snap'), 420);
  for (let k = 0; k < 20; k++) {
    const p = document.createElement('i');
    p.className = 'spark';
    const a = (k / 20) * Math.PI * 2, d = 30 + Math.random() * 30;
    p.style.cssText = `--dx:${Math.round(Math.cos(a) * d)}px;--dy:${Math.round(Math.sin(a) * d)}px;background:${color}`;
    slot.appendChild(p);
    window.setTimeout(() => p.remove(), 650);
  }
}

/** carta da mão: o que faz, quanto falta, trava de 1 dia e Tirar */
function openHandCard(ctx: CardsCtx, cardId: string): void {
  ctx.show('Carta na mão', () => {
    const s = store.state!, b = s.buffs.find((x) => x.card_id === cardId);
    if (!b) return '<p>Essa carta saiu da mão.</p>';
    const ms = store.clock.serverNow(), r = rarityInfo(b.rarity)!, left = (Date.parse(b.ends_at) - ms) / 1000;
    const locked = b.locked_until ? Date.parse(b.locked_until) > ms : false;
    return `<div class="card-detail">${cardHtml(ctx, b.card_id, b.rarity, 150)}
      <div class="grow"><h3 style="color:${r.color_hex}">${ctx.esc(cardDef(b.card_id)?.name_pt ?? b.card_id)} ${ctx.esc(r.name_pt)}</h3>
        <ul class="eff">${buffLines(b.card_id, b.rarity).map((l) => `<li>${ctx.esc(l)}</li>`).join('')}</ul>
        <p>Falta <strong>${lifeText(left)}</strong> ${lifeBar(left, b.full_s ?? left)}</p>
        ${b.coin_value > 0 ? `<p>${formatGold(b.coin_value)} de ouro juntado (pago quando a carta sai da mão).</p>` : ''}
        <button type="button" class="secondary" data-unequip ${locked ? 'disabled' : ''}>Tirar da mão</button>
        <p class="hint">${locked ? `Presa na mão por mais ${lifeText((Date.parse(b.locked_until!) - ms) / 1000)}. ` : ''}Ao tirar, a carta volta ao fichário guardando o tempo que sobrou.${b.rarity === 'common' ? ' Quando acabar, a Comum fica gasta e pode ser reparada com ouro.' : ' Quando acabar, ela some (fica registrada no álbum).'}</p>
      </div></div>`;
  }, (el) => el.querySelector('[data-unequip]')?.addEventListener('click', (e) => {
    (e.currentTarget as HTMLButtonElement).disabled = true;
    void ctx.act(() => unequipCard(cardId), 'Carta de volta ao fichário.');
  }));
}

// ---------- painel de cartas ----------
let tab: 'binder' | 'armory' | 'odds' = 'binder';
let picked: number | null = null; // nº de série escolhido no fichário

export function openCards(ctx: CardsCtx, start: 'binder' | 'armory' | 'odds' = 'binder'): void {
  tab = start; picked = null;
  ctx.show('Cartas', () => cardsBody(ctx), (el) => bindCards(ctx, el));
}

function sorted(cards: CardState[]): CardState[] {
  return [...cards].sort((a, b) => Number(a.state === 'worn') - Number(b.state === 'worn') || rarityRank(b.rarity) - rarityRank(a.rarity)
    || CARD_LIST.findIndex((c) => c.id === a.card_id) - CARD_LIST.findIndex((c) => c.id === b.card_id) || a.serial - b.serial);
}

function cardsBody(ctx: CardsCtx): string {
  const s = store.state;
  if (!s) return '<p>Carregando…</p>';
  const tabs = ([['binder', 'Fichário'], ['armory', 'Álbum'], ['odds', 'Chances']] as const)
    .map(([k, n]) => `<button type="button" role="tab" data-ctab="${k}" aria-selected="${tab === k}">${n}</button>`).join('');
  const body = tab === 'binder' ? binderBody(ctx, s) : tab === 'armory' ? armoryBody(ctx, s) : oddsBody(s);
  return `<div class="chips" role="tablist">${tabs}</div>${body}`;
}

function binderBody(ctx: CardsCtx, s: FarmState): string {
  const inBinder = s.cards.filter((c) => c.state !== 'inbox'), inbox = s.cards.filter((c) => c.state === 'inbox');
  const slots = s.hand_slots ?? 3;
  const list = sorted(s.cards);
  const grid = list.length ? list.map((c) => {
    const full = c.full_s ?? 1, life = c.life_s ?? full;
    return `<button type="button" class="card-btn ${picked === c.serial ? 'on' : ''} ${c.state === 'worn' ? 'worn' : ''}" data-pick="${c.serial}">
      ${cardHtml(ctx, c.card_id, c.rarity, 70)}${lifeBar(life, full)}
      ${c.state === 'worn' ? '<span class="tag">gasta</span>' : c.state === 'inbox' ? '<span class="tag">caixa</span>' : ''}</button>`;
  }).join('') : '<p class="hint">Nenhuma carta no fichário. Complete as 5 missões do dia para ganhar um pacote.</p>';
  let detail = '';
  const c = list.find((x) => x.serial === picked);
  if (c) {
    const d = cardDef(c.card_id)!, r = rarityInfo(c.rarity)!;
    const full = c.full_s ?? 1, life = c.life_s ?? full;
    const inHand = s.buffs.some((b) => b.card_id === c.card_id);
    const handFull = s.buffs.length >= slots;
    const worn = c.state === 'worn' || life <= 0;
    const why = worn ? 'Carta gasta.' : inHand ? 'Essa carta já está na mão.' : handFull ? `A mão está cheia (${slots} cartas).` : '';
    const repair = c.rarity === 'common' && life < full;
    detail = `<div class="card-detail">${cardHtml(ctx, c.card_id, c.rarity, 150)}
      <div class="grow"><h3 style="color:${r.color_hex}">${ctx.esc(d.name_pt)} ${ctx.esc(r.name_pt)}</h3>
        <p>${ctx.esc(d.description_pt)}</p>
        <ul class="eff">${buffLines(c.card_id, c.rarity).map((l) => `<li>${ctx.esc(l)}</li>`).join('')}</ul>
        <p>Vida: <strong>${lifeText(life)}</strong> de ${cardDuration(c.rarity)} ${lifeBar(life, full)}</p>
        <div class="row">
          <button type="button" class="primary small" data-equip="${c.serial}" ${why ? 'disabled' : ''}>Colocar na mão</button>
          ${repair ? `<button type="button" class="secondary" data-repair="${c.serial}">Reparar (+${CARDS.rarities.common.repair.restores_days} dias · ${formatGold(s.repair_cost ?? 0)})</button>` : ''}
          <button type="button" class="secondary" data-sell="${c.serial}">Vender (${formatGold(s.collector[c.rarity] ?? 0)})</button>
        </div>
        <p class="hint">${why ? `${why} ` : ''}Na mão a carta gasta os dias online ou offline e fica presa pelo menos 1 dia. ${c.rarity === 'common' ? 'A Comum gasta volta com reparo em ouro.' : 'Gasta, ela some (fica no álbum).'} Nº de série ${c.serial}${c.state === 'inbox' && c.inbox_until ? ` · na caixa de entrada até ${new Date(c.inbox_until).toLocaleDateString('pt-BR')}` : ''}.</p>
      </div></div>`;
  }
  const canGrow = s.binder_slots + CARDS.binder.expansion_slots <= CARDS.binder.max_slots;
  return `<p class="status">Mão: ${s.buffs.length} de ${slots} · fichário ${inBinder.length} de ${s.binder_slots}${inbox.length ? ` · <strong>${inbox.length} na caixa de entrada</strong> (o Colecionador compra sozinho depois de ${CARDS.binder.inbox_overflow_retention_days} dias)` : ''}
      ${canGrow ? ` · <button type="button" class="secondary small" data-expand>+${CARDS.binder.expansion_slots} espaços (${formatGold(s.binder_expand_cost)})</button>` : ''}</p>
    ${detail}<div class="card-grid">${grid}</div>`;
}

function armoryBody(ctx: CardsCtx, s: FarmState): string {
  const rows = CARD_LIST.map((d) => {
    const st = armoryStatus(s.armory, d.id);
    const frames = RARITY_LIST.map((r) => `<span class="arm-slot ${st.has.has(r) ? 'on' : ''}" title="${rarityInfo(r)?.name_pt}">${cardHtml(ctx, d.id, r, 40, st.has.has(r) ? '' : 'ghost')}</span>`).join('');
    const bonus = st.level === 'none' ? `<small>Parcial (Comum + Incomum + Rara): ${ctx.esc(armoryLines(d.id, 'partial').join(', '))}</small>`
      : `<small class="${st.level}">${st.level === 'complete' ? 'Completo' : 'Parcial'}: ${ctx.esc(armoryLines(d.id, st.level).join(', '))}</small>`;
    return `<li class="arm-row"><strong>${ctx.esc(d.name_pt)}</strong>${bonus}<div class="arm-slots">${frames}</div></li>`;
  }).join('');
  const done = CARD_LIST.filter((d) => armoryStatus(s.armory, d.id).level === 'complete').length;
  return `<p class="status">Bônus permanentes da coleção · ${done} de ${CARD_LIST.length} cartas completas</p>
    <ul class="armory">${rows}</ul>
    <p class="hint">O álbum registra sozinho cada carta e raridade na primeira vez que ela entra na mão. As 5 raridades trocam o bônus parcial pelo completo.</p>`;
}

function oddsBody(s: FarmState): string {
  const p = pityLeft(s.pity);
  const rates = RARITY_LIST.map((r) => `<li><span style="color:${rarityInfo(r)?.color_hex}">■</span> ${rarityInfo(r)?.name_pt}: ${pctTxt((CARDS.gacha.base_rates as Record<string, number>)[r])} <small>(com a garantia, ${pctTxt((CARDS.gacha.effective_rates_with_pity as Record<string, number>)[r])}) · vale ${cardDuration(r)} na mão</small></li>`).join('');
  return `<h3>Chance de cada raridade</h3><ul class="eff">${rates}</ul>
    <p>Dentro da raridade, as ${CARD_LIST.length} cartas têm a mesma chance.</p>
    <h3>Garantia</h3>
    <ul class="eff"><li>Rara ou melhor em até <strong>${p.rare}</strong> cartas</li><li>Lendária ou melhor em até <strong>${p.legendary}</strong></li><li>Mítica em até <strong>${p.mythic}</strong></li></ul>
    <p class="hint">Cartas vêm das missões (até ${CARDS.rules.weekly_mission_packs.max_daily_packs_per_week} pacotes por semana das diárias e 2 cartas das semanais), da Encomenda da Vila e, depois do nível 50, das Estrelas. Nunca à venda por dinheiro.</p>`;
}

function bindCards(ctx: CardsCtx, el: HTMLElement): void {
  const rerender = () => ctx.show('Cartas', () => cardsBody(ctx), (e) => bindCards(ctx, e));
  el.querySelectorAll<HTMLButtonElement>('[data-ctab]').forEach((b) => b.addEventListener('click', () => { tab = b.dataset.ctab as typeof tab; picked = null; rerender(); }));
  el.querySelectorAll<HTMLButtonElement>('[data-pick]').forEach((b) => b.addEventListener('click', () => { const n = Number(b.dataset.pick); picked = picked === n ? null : n; rerender(); }));
  const one = (sel: string, attr: string, fn: (n: number) => Promise<FarmState>, ok: string) => el.querySelector<HTMLButtonElement>(sel)?.addEventListener('click', (e) => {
    const b = e.currentTarget as HTMLButtonElement; b.disabled = true;
    void ctx.act(() => fn(Number(b.getAttribute(attr))), ok).then(() => { picked = null; });
  });
  one('[data-equip]', 'data-equip', equipCard, 'Carta na mão!');
  one('[data-repair]', 'data-repair', repairCard, 'Carta reparada.');
  one('[data-sell]', 'data-sell', sellCard, 'Vendida ao Colecionador da Vila.');
  el.querySelector('[data-expand]')?.addEventListener('click', () => void ctx.act(binderExpand, 'Fichário ampliado.'));
}

// ---------- pacote: a carta vira ----------
let opening = false;
export function maybeOpenPack(ctx: CardsCtx, s: FarmState): void {
  if (opening || !s.new_cards?.length) return;
  if (!store.manifest.card_back_v3) return; // as artes ainda estão carregando: abre quando chegarem
  opening = true;
  const cards = [...s.new_cards];
  let i = 0;
  const ov = document.createElement('div');
  ov.className = 'pack-overlay';
  const still = calm();
  const ORIGIN: Record<string, string> = { daily_pack: 'Pacote das missões do dia', weekly_3: '3 missões semanais', weekly_5: '5 missões semanais', admin: 'Presente do painel', encomenda: 'Prêmio da Encomenda da Vila', estrelas: 'Pacote comprado com Estrelas' };
  const draw = () => {
    const c = cards[i];
    const r = rarityInfo(c.rarity)!;
    ov.innerHTML = `<div class="pack" role="dialog" aria-label="Carta nova">
      <p class="muted">${ctx.esc(ORIGIN[c.origin] ?? 'Carta nova')}${cards.length > 1 ? ` · ${i + 1} de ${cards.length}` : ''}</p>
      <div class="flip ${still ? 'flipped' : ''}" style="--rc:${r.color_hex}">
        <div class="face back">${art('card_back_v3', 150)}</div>
        <div class="face front">${art(cardArt(c.card_id, c.rarity), 150)}</div>
      </div>
      <h3 class="pack-name" style="color:${r.color_hex}">${ctx.esc(cardDef(c.card_id)?.name_pt ?? c.card_id)} · ${ctx.esc(r.name_pt)}</h3>
      <ul class="eff">${buffLines(c.card_id, c.rarity).map((l) => `<li>${ctx.esc(l)}</li>`).join('')}</ul>
      <p class="hint">Vale ${cardDuration(c.rarity)} na mão.</p>
      <button type="button" class="primary small" data-next>${i + 1 < cards.length ? 'Próxima carta' : 'Guardar no fichário'}</button></div>`;
    const f = ov.querySelector('.flip')!;
    if (!still) window.setTimeout(() => f.classList.add('flipped'), 450); // o verso aparece e vira
    ov.querySelector('[data-next]')!.addEventListener('click', () => {
      i++;
      if (i < cards.length) draw();
      else { ov.remove(); void ctx.act(cardsSeen).finally(() => { opening = false; }); }
    });
  };
  ctx.root.appendChild(ov);
  draw();
}
