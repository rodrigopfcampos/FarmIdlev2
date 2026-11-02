// Missões e cartas na interface (v3): botões Missões e Cartas no topo, a mão em leque no rodapé com o caixote
// do baralho, painel de Cartas (Fichário, Álbum e chances) e o pacote que abre virando a carta.
import { hudIcon } from './hud-icons';
import { CARDS, MISSIONS } from '../data';
import {
  armoryLines, armoryStatus, buffLines, CARD_LIST, cardArt, cardDef, cardDuration, lifeText, missionProgress, missionText, pityLeft, RARITY_LIST, rarityInfo, rarityRank,
} from '../farm/cards';
import { store } from '../farm/store';
import { binderExpand, cardsSeen, equipCard, handAdd, handRemove, repairCard, rerollMission, sellCard, unequipCard, type CardState, type FarmState } from '../net/farmApi';
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
  return `<button type="button" class="icon-btn" data-missions title="Missões (${done}/${daily.length})" aria-label="Missões">${hudIcon('missions')}<span class="badge ${done === daily.length ? 'ok' : ''}">${done}/${daily.length}</span></button>
    <button type="button" class="icon-btn" data-cards title="Cartas" aria-label="Cartas">${hudIcon('cards')}${fresh}</button>`;
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
    <p class="status">As 5 do dia: <strong>1 pacote com ${packCards(s.level)} carta${packCards(s.level) > 1 ? 's' : ''}</strong> ${s.pack_today ? '✓ recebido hoje' : ''} · ${s.mission_week.daily_packs} de ${maxPacks} pacotes nesta semana.
      ${s.reroll_used ? 'Troca grátis de hoje já usada.' : '1 troca grátis por dia.'}</p>
    <h3>Semanais <small class="muted">renovam na segunda à meia-noite</small></h3>
    <ul class="missions">${weekly.map(row).join('')}</ul>
    <p class="status">${wd >= 3 ? '✓' : '○'} 3 completas: 1 carta · ${wd >= 5 ? '✓' : '○'} as 5: +1 carta</p>
    <p class="hint">As metas são medidas na sua própria produção por hora (${formatGold(s.prod_ref.value_h)} em valor da Feira). O que a equipe faz sozinha também conta.</p>`;
}

/** cartas no pacote das diárias, pelo nível */
function packCards(level: number): number {
  return MISSIONS.daily.pack_cards_by_level.filter(([lv]) => lv <= level).reduce((n, [, c]) => c, 1);
}

// ---------- a mão (rodapé) ----------
let handOpen = true;
let lastHand: string[] = [];
/** cartas da mão (paradas, esperando "Usar") e buffs (cartas em uso, contando o tempo) */
type HandItem = { serial: number; card_id: string; rarity: string; active: boolean; left: number; full: number };
function handItems(s: FarmState): HandItem[] {
  return s.cards.filter((c) => c.state === 'hand').map((c) => ({ serial: c.serial, card_id: c.card_id, rarity: c.rarity, active: false, left: c.life_s ?? c.full_s ?? 0, full: c.full_s ?? 0 }));
}
function buffItems(s: FarmState): HandItem[] {
  const ms = store.clock.serverNow();
  return s.buffs.map((b) => ({ serial: b.serial ?? 0, card_id: b.card_id, rarity: b.rarity, active: true, left: (Date.parse(b.ends_at) - ms) / 1000, full: b.full_s ?? 0 }));
}
const cardTitle = (h: HandItem) => `${cardDef(h.card_id)?.name_pt} ${rarityInfo(h.rarity)?.name_pt}: ${buffLines(h.card_id, h.rarity).join(', ')}`;

/** mão em leque no canto inferior direito do mapa (só cartas paradas) e buffs no canto superior esquerdo */
export function renderHand(ctx: CardsCtx, s: FarmState): void {
  let dock = ctx.root.querySelector<HTMLElement>('.hand-dock');
  if (!dock) { dock = document.createElement('div'); dock.className = 'hand-dock'; ctx.root.appendChild(dock); }
  let bar = ctx.root.querySelector<HTMLElement>('.buff-bar');
  if (!bar) { bar = document.createElement('div'); bar.className = 'buff-bar'; ctx.root.appendChild(bar); }
  if (!s.missions || store.visit) { dock.hidden = true; bar.hidden = true; return; }
  dock.hidden = false; bar.hidden = false;
  const slots = s.hand_slots ?? 3;
  const hand = handItems(s), buffs = buffItems(s);
  const n = Math.max(slots, hand.length);
  const mid = (n - 1) / 2;
  const items = Array.from({ length: n }, (_, i) => {
    const h = hand[i];
    const rot = (i - mid) * 7, lift = Math.abs(i - mid) * 6;
    const style = `--rot:${rot}deg;--lift:${lift}px;--i:${i}`;
    if (!h) return `<button type="button" class="hand-card empty" style="${style}" data-open-binder title="Vaga livre: escolher carta">+</button>`;
    return `<button type="button" class="hand-card" style="${style};--rc:${rarityInfo(h.rarity)?.color_hex}" data-hand="${h.serial}"
        title="${ctx.esc(`Clique para usar · ${cardTitle(h)}`)}">${art(cardArt(h.card_id, h.rarity), 84)}<small>Usar</small></button>`;
  }).join('');
  dock.className = `hand-dock ${handOpen ? '' : 'closed'}`;
  dock.innerHTML = `<div class="hand-tab">
      <button type="button" class="hand-binder" data-open-binder title="Fichário: todas as suas cartas">Fichário</button>
      <button type="button" class="hand-toggle" data-toggle-hand title="${handOpen ? 'Recolher a mão' : 'Abrir a mão'}">${art('deck_toggle', 22)}</button>
    </div><div class="hand-fan">${items}</div>`;
  dock.querySelector('[data-toggle-hand]')?.addEventListener('click', () => { handOpen = !handOpen; renderHand(ctx, store.state!); });
  dock.querySelectorAll('[data-open-binder]').forEach((b) => b.addEventListener('click', () => openCards(ctx)));
  dock.querySelectorAll<HTMLButtonElement>('[data-hand]').forEach((b) => b.addEventListener('click', () => openHandCard(ctx, Number(b.dataset.hand))));
  // buffs: carta pequena com o tempo que falta
  bar.innerHTML = buffs.map((h) => `<button type="button" class="buff-card" style="--rc:${rarityInfo(h.rarity)?.color_hex}" data-buff="${h.serial}"
      title="${ctx.esc(`Em uso · ${cardTitle(h)}`)}">${art(cardArt(h.card_id, h.rarity), 46)}<small>${lifeText(h.left)}</small></button>`).join('')
    + (buffs.length ? `<span class="buff-count">${buffs.length}/${slots}</span>` : '');
  bar.querySelectorAll<HTMLButtonElement>('[data-buff]').forEach((b) => b.addEventListener('click', () => openHandCard(ctx, Number(b.dataset.buff))));
  // carta passou a valer: flash branco, partículas da cor da raridade e tremor no buff novo
  const now = buffs.map((h) => String(h.serial));
  if (!calm()) buffs.forEach((h, i) => { if (lastHand.length && !lastHand.includes(String(h.serial))) snapFx(bar!.querySelectorAll<HTMLElement>('.buff-card')[i], rarityInfo(h.rarity)?.color_hex ?? '#fff'); });
  lastHand = now.length ? now : ['-'];
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

/** carta da mão: parada (Usar · Voltar ao fichário) ou em uso (quanto falta · Pausar depois de 1 dia) */
function openHandCard(ctx: CardsCtx, serial: number): void {
  ctx.show('Carta na mão', () => {
    const s = store.state!, h = [...handItems(s), ...buffItems(s)].find((x) => x.serial === serial);
    if (!h) return '<p>Essa carta saiu da mão.</p>';
    const ms = store.clock.serverNow(), r = rarityInfo(h.rarity)!;
    const b = s.buffs.find((x) => x.serial === serial);
    const locked = b?.locked_until ? Date.parse(b.locked_until) > ms : false;
    const head = `<div class="card-detail">${cardHtml(ctx, h.card_id, h.rarity, 150)}
      <div class="grow"><h3 style="color:${r.color_hex}">${ctx.esc(cardDef(h.card_id)?.name_pt ?? h.card_id)} ${ctx.esc(r.name_pt)}</h3>
        <ul class="eff">${buffLines(h.card_id, h.rarity).map((l) => `<li>${ctx.esc(l)}</li>`).join('')}</ul>`;
    if (!h.active) return `${head}
        <p>Parada na mão: <strong>${lifeText(h.left)}</strong> guardados ${lifeBar(h.left, h.full || h.left)}</p>
        <div class="row"><button type="button" class="primary" data-use>Usar</button>
          <button type="button" class="secondary" data-back>Voltar ao fichário</button></div>
        <p class="hint">Parada, a carta não vale e não gasta tempo. Ao usar, ela sai da mão e vira buff (canto de cima): o bônus liga na hora e o tempo corre online ou offline, por pelo menos 1 dia.</p>
      </div></div>`;
    return `${head}
        <p>Em uso · falta <strong>${lifeText(h.left)}</strong> ${lifeBar(h.left, h.full || h.left)}</p>
        ${b && b.coin_value > 0 ? `<p>${formatGold(b.coin_value)} de ouro juntado (pago quando a carta para).</p>` : ''}
        <button type="button" class="secondary" data-pause ${locked ? 'disabled' : ''}>Pausar</button>
        <p class="hint">${locked ? `Em uso por pelo menos mais ${lifeText((Date.parse(b!.locked_until!) - ms) / 1000)}. ` : ''}Ao pausar, ela volta parada para a mão (ou para o fichário, se a mão estiver cheia) guardando o tempo que sobrou.${h.rarity === 'common' ? ' Quando acabar, a Comum fica gasta e pode ser reparada com ouro.' : ' Quando acabar, ela some (fica registrada no álbum).'}</p>
      </div></div>`;
  }, (el) => {
    const s = store.state!, h = [...handItems(s), ...buffItems(s)].find((x) => x.serial === serial);
    const go = (sel: string, fn: () => Promise<FarmState>, ok: string) => el.querySelector(sel)?.addEventListener('click', (e) => {
      (e.currentTarget as HTMLButtonElement).disabled = true;
      void ctx.act(fn, ok);
    });
    go('[data-use]', () => equipCard(serial), 'Carta em uso!');
    go('[data-back]', () => handRemove(serial), 'Carta de volta ao fichário.');
    if (h) go('[data-pause]', () => unequipCard(h.card_id), 'Carta pausada na mão.');
  });
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
  const inBinder = s.cards.filter((c) => c.state !== 'inbox' && c.state !== 'hand'), inbox = s.cards.filter((c) => c.state === 'inbox');
  const slots = s.hand_slots ?? 3;
  const list = sorted(s.cards.filter((c) => c.state !== 'hand'));
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
    const hand = handItems(s);
    const worn = c.state === 'worn' || life <= 0;
    const whyHand = worn ? 'Carta gasta.' : hand.some((h) => h.card_id === c.card_id) ? 'Essa carta já está na mão.' : hand.length >= slots ? `A mão está cheia (${slots} cartas).` : '';
    const whyUse = worn ? 'Carta gasta.' : s.buffs.some((b) => b.card_id === c.card_id) ? 'Essa carta já está em uso.' : s.buffs.length >= slots ? `Já tem ${slots} cartas em uso.` : '';
    const why = whyHand && whyUse ? whyHand : '';
    const repair = c.rarity === 'common' && life < full;
    detail = `<div class="card-detail">${cardHtml(ctx, c.card_id, c.rarity, 150)}
      <div class="grow"><h3 style="color:${r.color_hex}">${ctx.esc(d.name_pt)} ${ctx.esc(r.name_pt)}</h3>
        <p>${ctx.esc(d.description_pt)}</p>
        <ul class="eff">${buffLines(c.card_id, c.rarity).map((l) => `<li>${ctx.esc(l)}</li>`).join('')}</ul>
        <p>Vida: <strong>${lifeText(life)}</strong> de ${cardDuration(c.rarity)} ${lifeBar(life, full)}</p>
        <div class="row">
          <button type="button" class="primary small" data-hand-add="${c.serial}" ${whyHand ? 'disabled' : ''}>Colocar na mão</button>
          <button type="button" class="secondary" data-equip="${c.serial}" ${whyUse ? 'disabled' : ''}>Usar agora</button>
          ${repair ? `<button type="button" class="secondary" data-repair="${c.serial}">Reparar (+${CARDS.rarities.common.repair.restores_days} dias · ${formatGold(s.repair_cost ?? 0)})</button>` : ''}
          <button type="button" class="secondary" data-sell="${c.serial}">Vender (${formatGold(s.collector[c.rarity] ?? 0)})</button>
        </div>
        <p class="hint">${why ? `${why} ` : ''}Na mão a carta fica parada e não gasta tempo; ao usar, vira buff e gasta os dias online ou offline (pelo menos 1 dia). ${c.rarity === 'common' ? 'A Comum gasta volta com reparo em ouro.' : 'Gasta, ela some (fica no álbum).'} Nº de série ${c.serial}${c.state === 'inbox' && c.inbox_until ? ` · na caixa de entrada até ${new Date(c.inbox_until).toLocaleDateString('pt-BR')}` : ''}.</p>
      </div></div>`;
  }
  const canGrow = s.binder_slots + CARDS.binder.expansion_slots <= CARDS.binder.max_slots;
  return `<p class="status">Mão: ${handItems(s).length} de ${slots} · em uso: ${s.buffs.length} de ${slots} · fichário ${inBinder.length} de ${s.binder_slots}${inbox.length ? ` · <strong>${inbox.length} na caixa de entrada</strong> (o Colecionador compra sozinho depois de ${CARDS.binder.inbox_overflow_retention_days} dias)` : ''}
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
    <p class="hint">O álbum registra sozinho cada carta e raridade na primeira vez que ela é usada. As 5 raridades trocam o bônus parcial pelo completo.</p>`;
}

function oddsBody(s: FarmState): string {
  const p = pityLeft(s.pity);
  const rates = RARITY_LIST.map((r) => `<li><span style="color:${rarityInfo(r)?.color_hex}">■</span> ${rarityInfo(r)?.name_pt}: ${pctTxt((CARDS.gacha.base_rates as Record<string, number>)[r])} <small>(com a garantia, ${pctTxt((CARDS.gacha.effective_rates_with_pity as Record<string, number>)[r])}) · vale ${cardDuration(r)} na mão</small></li>`).join('');
  return `<h3>Chance de cada raridade</h3><ul class="eff">${rates}</ul>
    <p>Dentro da raridade, as ${CARD_LIST.length} cartas têm a mesma chance.</p>
    <h3>Garantia</h3>
    <ul class="eff"><li>Rara ou melhor em até <strong>${p.rare}</strong> cartas</li><li>Lendária ou melhor em até <strong>${p.legendary}</strong></li><li>Mítica em até <strong>${p.mythic}</strong></li></ul>
    <p class="hint">Cartas vêm do presente de boas-vindas, dos níveis ${CARDS.rules.supply.level_up_cards.from_level} a ${CARDS.rules.supply.level_up_cards.to_level} (1 por nível), das missões (1 pacote por dia nas diárias, com 2 cartas do nível ${MISSIONS.daily.pack_cards_by_level[1][0]} em diante, e 2 cartas das semanais), da Encomenda da Vila e, depois do nível 50, das Estrelas. Nunca à venda por dinheiro.</p>`;
}

function bindCards(ctx: CardsCtx, el: HTMLElement): void {
  const rerender = () => ctx.show('Cartas', () => cardsBody(ctx), (e) => bindCards(ctx, e));
  el.querySelectorAll<HTMLButtonElement>('[data-ctab]').forEach((b) => b.addEventListener('click', () => { tab = b.dataset.ctab as typeof tab; picked = null; rerender(); }));
  el.querySelectorAll<HTMLButtonElement>('[data-pick]').forEach((b) => b.addEventListener('click', () => { const n = Number(b.dataset.pick); picked = picked === n ? null : n; rerender(); }));
  const one = (sel: string, attr: string, fn: (n: number) => Promise<FarmState>, ok: string) => el.querySelector<HTMLButtonElement>(sel)?.addEventListener('click', (e) => {
    const b = e.currentTarget as HTMLButtonElement; b.disabled = true;
    void ctx.act(() => fn(Number(b.getAttribute(attr))), ok).then(() => { picked = null; });
  });
  one('[data-hand-add]', 'data-hand-add', handAdd, 'Carta na mão!');
  one('[data-equip]', 'data-equip', equipCard, 'Carta em uso!');
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
  const ORIGIN: Record<string, string> = { daily_pack: 'Pacote das missões do dia', weekly_3: '3 missões semanais', weekly_5: '5 missões semanais', admin: 'Presente do painel', starter: 'Presente de boas-vindas', level_up: 'Prêmio de nível', encomenda: 'Prêmio da Encomenda da Vila', estrelas: 'Pacote comprado com Estrelas' };
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
