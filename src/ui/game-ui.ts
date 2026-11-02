// Interface por cima do mapa: barra do topo (nível, XP, ouro, trabalho da equipe e o botão
// "Colher e plantar") e os painéis das zonas, dos canteiros, dos lotes à venda e do pomar.
// Clique em canteiro maduro colhe e replanta na hora; em canteiro com cultivo escolhido, planta (grátis, jogo aberto).
import { bus } from '../core/bus';
import { mapView } from '../core/mapView';
import { ANIMALS, ANIMAL_BY_ID, ANIMAL_EMOJI, ANIMAL_RULES, HOUSES, HOUSE_NAMES, itemInfo, CHARS, CLASSES, CLASS_TOOLS, CROPS, CROP_LIST, FARM, LEVELS, STALL_RATIO, LOT_BY_ID, LOT_TYPE_NAMES, MAX_LEVEL, PETS, RARITY_BY_ID, FISHING, SNACKS, TOOL_MATERIALS, VEHICLES, WORK, type Crop } from '../data';
import { ICON_VARIANTS, iconSprite, petSprite } from '../farm/art';
import { openGarage } from './garage';
import {
  animalLook, classDef, collectUnits, feedPerCycle, hireCost, hoursToNext, lotOffer, orchardFruits, petFactor, petLevel, petNextIn, petFindLeft, plotCrops, plotLook, rareSeeds,
  fishCycles, fishSpecies, tendCount, treeLook, xpProgress,
} from '../farm/rules';
import { applyState, store } from '../farm/store';
import {
  buyAnimal, buyLot, removeAnimal, upgradeHouse, buySnack, carePet, collectPet, chopTree, equipSnack, hire, paySalaries, plantRareSeed, plantRareTree, plantTree, repairTool,
  sellAtStall, setAutoSell, setCrop, setSlot, collectFish, tendFarm, repairRod,
  setTimezone, clientPing, warningSeen,
  type AnimalState, type CharacterState, type FarmState, type PlotState,
} from '../net/farmApi';
import { supabase } from '../net/supabase';
import { duration, formatGold } from './format';
import { weatherBanner, weatherChip, weatherPanel } from './weather-ui';
import { hudIcon } from './hud-icons';
import { hudCards, maybeOpenPack, openCards, openMissions, renderHand, type CardsCtx } from './cards-ui';
import { hudPassives, openPassives } from './passives-ui';
import { deviceTz } from '../farm/weather';
import { bindVisitHud, hudSocial, openHelp, openSocial, visitHud, type SocialCtx } from './social-ui';
import { hudVillage, openVillage } from './village-ui';

const nf1 = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

function sprite(key: string | null, scale = 2, cls = '', filter = ''): string {
  const m = key ? store.manifest[key] : null;
  if (!m) return '';
  const [w, h] = m.frame_size ?? m.size;
  return `<span class="px ${cls}" style="width:${w * scale}px;height:${h * scale}px;background-image:url(assets/${m.file});background-size:${m.size[0] * scale}px ${m.size[1] * scale}px${filter ? `;filter:${filter}` : ''}"></span>`;
}

/** ícone de um item do Silo: arte (com a variação de cor, se houver) ou emoji provisório */
function itemIcon(id: string): string {
  const key = iconSprite(store.manifest, id);
  if (key) return sprite(key, 1, '', ICON_VARIANTS[id]?.filter ?? '');
  const e = itemInfo(id).emoji;
  return e ? `<span class="pet-face small" aria-hidden="true">${e}</span>` : '';
}

/** animal nas listas: arte ou emoji provisório */
function animalFace(id: string): string {
  const key = `animal_${id}_f1`;
  return store.manifest[key] ? `<span class="pet-face" aria-hidden="true">${sprite(key, 1.25)}</span>` : `<span class="pet-face" aria-hidden="true">${ANIMAL_EMOJI[id] ?? '🐾'}</span>`;
}

/** rosto do pet nas listas: arte ou emoji provisório */
function petFace(id: string): string {
  const key = petSprite(store.manifest, id);
  return key ? `<span class="pet-face" aria-hidden="true">${sprite(key, 1.5)}</span>` : `<span class="pet-face" aria-hidden="true">${PET_EMOJI[id]}</span>`;
}

// Até as artes chegarem, os outros personagens usam o Agricultor com outra cor (só visual)
const CLASS_HUE: Record<string, number> = { agricultor: 0, rancheira: 150, ferreiro: 200, comerciante: 280, gerente: 40, botanica: 100 };
function charSprite(cls: string, scale = 2): string {
  const key = store.manifest[`char_${cls}_idle`] ? `char_${cls}_idle` : 'char_agricultor_idle';
  const html = sprite(key, scale);
  return key === 'char_agricultor_idle' && CLASS_HUE[cls] ? html.replace('style="', `style="filter:hue-rotate(${CLASS_HUE[cls]}deg);`) : html;
}
/** retrato do personagem no tamanho nativo da arte (1:1, sem esticar nem borrar) */
function charPortrait(cls: string): string {
  const key = `char_${cls}_portrait`;
  return store.manifest[key] ? sprite(key, 1, 'portrait') : charSprite(cls, 2);
}
const className = (id: string) => classDef(id)?.name_pt ?? id;
const toolCard = (cls: string) => CLASS_TOOLS.find((t) => t.class_id === cls)!;
const matDef = (id: string) => TOOL_MATERIALS.find((m) => m.id === id) ?? TOOL_MATERIALS[0];
/** v3: a ferramenta é a carta dela (Comum) e o "nível da ferramenta" sobe sozinho com a fazenda */
const toolArt = (cls: string, scale = 0.36) => sprite(`card_full_${(toolCard(cls) as { card_id?: string }).card_id ?? 'enxada'}_common`, scale);
const toolLevel = (id: string) => TOOL_MATERIALS.findIndex((m) => m.id === id) + 1;
const nextToolTier = (level: number) => TOOL_MATERIALS.find((m) => m.unlock_level > level);
/** preço da Barraca agora (Comerciante em campo e habilidades sobem) e o bônus de ouro em vendas */
const stallRatio = () => store.state?.fx?.stall_ratio ?? STALL_RATIO;
const salesMult = () => 1 + (store.state?.fx?.sales_gold ?? 0);
const pct = (x: number) => `${nf1.format(x * 100)}%`;
const PET_EMOJI: Record<string, string> = { cachorro: '🐶', gato: '🐱', papagaio: '🦜' };

let root: HTMLElement;
let hud: HTMLElement;
let panel: HTMLElement;
let current: (() => void) | null = null; // redesenha o painel aberto quando o estado muda
let lastLevel = 0;
let ticker: number | undefined;

export function mountGameUi(el: HTMLElement): void {
  root = el;
  lastLevel = 0;
  window.clearInterval(ticker);
  ticker = window.setInterval(() => { refreshTendButton(); refreshWeather(); placeBanner(); refreshCards(); }, 1000); // maduros, clima e evento mudam com o tempo, sem esperar o servidor
  root.innerHTML = `<div class="hud" id="hud"></div><div class="wx-banner" id="wxbanner" role="status" tabindex="0" hidden></div><div class="modal" id="modal" hidden></div><div class="toast" id="toast" role="status" aria-live="polite"></div>`;
  hud = root.querySelector('#hud')!;
  panel = root.querySelector('#modal')!;
  panel.addEventListener('click', (e) => { if (e.target === panel) close(); });
  if (!wired) wire(); // ao sair e entrar de novo, os ouvintes não se repetem
  if (store.state) onState(store.state);
}

let wired = false;
function wire(): void {
  wired = true;
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
  window.addEventListener('resize', () => placeBanner());
  bus.on('farm:state', onState);
  bus.on('farm:error', (msg: string) => {
    // conta suspensa ou banida: tela fixa com o motivo e o botão Sair
    if (/suspensa|banida/.test(msg)) {
      show('Conta bloqueada', () => `<p>${esc(msg)}</p><p class="hint">Se achar que foi um engano, fale com o suporte.</p>
        <button type="button" class="secondary" data-logout>Sair</button>`, (el) => el.querySelector('[data-logout]')?.addEventListener('click', () => void supabase!.auth.signOut()));
      return;
    }
    toast(msg);
  });
  bus.on('art:ready', () => { if (store.state) onState(store.state); });
  // na visita, clicar num lote abre o Ajudar; zonas e pet não fazem nada
  const visiting = (lot?: string) => {
    if (!store.visit) return false;
    if (lot) openHelp(socialCtx(), lot); else toast('Na visita, clique num lote para ajudar.');
    return true;
  };
  bus.on('ui:zone', (id: string) => { if (!visiting()) openZone(id); });
  bus.on('ui:plot', (id: string) => { if (!visiting(id.split('-')[0])) onPlotClick(id); });
  bus.on('ui:locked', (id: string) => { if (!visiting(id)) openLot(id); });
  bus.on('ui:orchard', (id: string) => { if (!visiting(id)) onOrchardClick(id); });
  // pet no mapa: achado pronto → pega; senão, carinho do dia; senão abre a guia Pets
  bus.on('ui:pet', (id: string) => {
    if (visiting()) return;
    const s = store.state;
    const p = s?.pets.find((x) => x.pet_id === id);
    if (!s || !p) { openZone('casa_principal', 'pets'); return; }
    if (petFindLeft(p.pet_id, p.find_t, store.clock.farmNow()) === 0) void takeFind(p.pet_id);
    else if (p.last_care !== s.game_day) void act(() => carePet(p.pet_id), `${petName(p.pet_id)}: carinho feito!`);
    else openZone('casa_principal', 'pets');
  });
  bus.on('ui:pasture', (id: string) => { if (!visiting(id)) onPastureClick(id); });
}

function socialCtx(): SocialCtx {
  return { show, close, toast, esc };
}

/** topo da visita: troca a barra inteira; o resto do jogo fica parado até voltar */
function onVisitState(): void {
  const v = store.visit!;
  close();
  hud.innerHTML = visitHud(socialCtx(), v);
  hud.classList.add('visiting');
  bindVisitHud(socialCtx(), hud, v);
  wxKey = '';
  refreshWeather();
}

function onState(s: FarmState): void {
  if (store.visit) { onVisitState(); return; }
  hud.classList.remove('visiting');
  const pct = Math.round(xpProgress(s.xp, s.xp_to_next) * 100);
  const xpText = s.xp_to_next ? `${formatGold(s.xp)} de ${formatGold(s.xp_to_next)} XP` : 'nível máximo';
  // HUD 16-bit: à esquerda nível/XP e ouro com contorno grosso; à direita uma fileira de botões quadrados de ícone
  hud.innerHTML = `
    <div class="hud-left">
      <span class="lvl-badge" title="${esc(s.nickname)} · ${xpText}"><b>${s.level}</b><span class="xpbar" role="progressbar" aria-label="XP do nível" aria-valuenow="${pct}" aria-valuemin="0" aria-valuemax="100"><span style="width:${pct}%"></span></span></span>
      <span class="gold" title="Ouro">${hudIcon('coin', 20)}<b>${formatGold(s.gold)}</b></span>
      ${s.level >= MAX_LEVEL ? `<button type="button" class="stars" title="Estrelas da Vila">${hudIcon('star', 18)}<b>${s.village?.stars ?? 0}</b></button>` : ''}
    </div>
    <div class="hud-right">
      <span class="wx-slot"></span>
      ${laborMeter(s)}
      <button type="button" class="icon-btn tend" data-tend hidden></button>
      <span class="cards-slot"></span>
      ${hudSocial()}
      ${hudVillage()}
      <button type="button" class="icon-btn" data-open="casa_principal" title="Silo e Casa" aria-label="Silo e Casa">${hudIcon('silo')}</button>
      <button type="button" class="icon-btn logout" title="Sair" aria-label="Sair">${hudIcon('logout')}</button>
    </div>`;
  hud.querySelector('.logout')!.addEventListener('click', () => supabase!.auth.signOut());
  hud.querySelector('[data-open]')!.addEventListener('click', () => openZone('casa_principal', 'silo'));
  hud.querySelector('[data-tend]')!.addEventListener('click', () => void tend(null));
  hud.querySelector('[data-team]')?.addEventListener('click', () => openZone('casa_principal', 'operadores'));
  hud.querySelector('[data-social]')?.addEventListener('click', () => void openSocial(socialCtx()));
  hud.querySelector('[data-village]')?.addEventListener('click', () => void openVillage({ show, toast, esc, itemIcon }));
  hud.querySelector('.stars')?.addEventListener('click', () => void openVillage({ show, toast, esc, itemIcon }, 'stars'));
  refreshTendButton();
  wxKey = '';
  refreshWeather();
  cardsKey = '';
  refreshCards();
  maybeOpenPack(cardsCtx(), s);
  // fuso: na 1ª vez vem do aparelho (vale na hora); depois a troca é pelo painel do clima
  if (s.weather && !s.weather.account.confirmed && !tzTried) { tzTried = true; void setTimezone(deviceTz()).then(applyState).catch(() => undefined); }
  // relógio e fuso do aparelho: 1 vez por sessão (o servidor só registra)
  if (!pinged) { pinged = true; void clientPing(deviceTz()); }
  // advertência do painel: aparece uma vez
  if (s.account?.warning && !warnShown) {
    warnShown = true;
    show('Aviso da administração', () => `<p>${esc(s.account!.warning!)}</p><p class="hint">Repetir pode levar à suspensão da conta.</p>
      <button type="button" class="primary small" data-warn-ok>Entendi</button>`, (el) => {
      el.querySelector('[data-warn-ok]')?.addEventListener('click', () => { close(); void act(() => warningSeen()); });
    });
  }
  if (lastLevel && s.level > lastLevel) levelUp(lastLevel, s.level);
  lastLevel = s.level;
  current?.();
}

let cardsKey = '';
/** botões Missões e Cartas e os 3 slots de buff (o tempo que falta muda a cada minuto) */
function refreshCards(): void {
  const s = store.state;
  const slot = hud?.querySelector<HTMLElement>('.cards-slot');
  if (!s || !slot) return;
  renderHandThrottled(s);
  const html = hudCards(cardsCtx(), s) + hudPassives(s);
  if (html === cardsKey) return;
  cardsKey = html;
  slot.innerHTML = html;
  slot.querySelector('[data-missions]')?.addEventListener('click', () => openMissions(cardsCtx()));
  slot.querySelectorAll('[data-cards]').forEach((b) => b.addEventListener('click', () => openCards(cardsCtx())));
  slot.querySelector('[data-passives]')?.addEventListener('click', () => openPassives({ show, act, esc }));
}

let handKey = '';
/** mão no rodapé: redesenha quando muda a carta ou o minuto que falta */
function renderHandThrottled(s: FarmState): void {
  const k = `${!!store.manifest.deck_crate}|${s.hand_slots}|${s.buffs.map((b) => `${b.card_id}:${b.serial}:${Math.floor((Date.parse(b.ends_at) - store.clock.serverNow()) / 60_000)}`).join(',')}|${s.cards.filter((c) => c.state === 'hand').map((c) => c.serial).join(',')}|${!!store.visit}`;
  if (k === handKey) return;
  handKey = k;
  renderHand(cardsCtx(), s);
}

function cardsCtx(): CardsCtx {
  return { show, act, sprite, esc, root };
}

let wxKey = '';
let tzTried = false;
let pinged = false;
let warnShown = false;
/** selo do clima e faixa do evento (redesenha só quando o texto muda) */
function refreshWeather(): void {
  const s = store.state;
  if (!s?.weather || !hud) return;
  const ms = store.clock.serverNow();
  const chip = weatherChip(s, ms), banner = weatherBanner(s, ms);
  if (chip + banner === wxKey) return;
  wxKey = chip + banner;
  const slot = hud.querySelector<HTMLElement>('.wx-slot');
  if (slot) { slot.innerHTML = chip; slot.querySelector('[data-weather]')?.addEventListener('click', openWeather); }
  const b = root.querySelector<HTMLElement>('#wxbanner')!;
  b.innerHTML = banner; b.hidden = !banner;
  placeBanner();
}

/** o selo do evento fica dentro do mapa (canto superior esquerdo do desenho do jogo, não da janela) */
function placeBanner(): void {
  const b = root?.querySelector<HTMLElement>('#wxbanner');
  const cv = document.querySelector<HTMLCanvasElement>('#game canvas, canvas');
  if (!b || !cv || window.matchMedia('(max-width: 520px)').matches) { if (b) { b.style.left = ''; b.style.top = ''; } return; }
  const r = cv.getBoundingClientRect(), base = root.getBoundingClientRect();
  // canto da imagem do mapa na tela: a câmera pode deixar faixas escuras dos lados
  const k = mapView.gameWidth ? r.width / mapView.gameWidth : 1;
  const mx = mapView.x * k, my = mapView.y * k;
  b.style.left = `${Math.max(12, Math.round(r.left - base.left + Math.max(0, mx) + 12))}px`;
  b.style.top = `${Math.max(12, Math.round(r.top - base.top + Math.max(0, my) + 12))}px`;
}

function openWeather(): void {
  show('Clima', () => (store.state ? weatherPanel(store.state, store.clock.serverNow()) : '<p>Carregando…</p>'), (el) => {
    el.querySelector<HTMLButtonElement>('[data-tz]')?.addEventListener('click', (e) => {
      const tz = (e.currentTarget as HTMLButtonElement).dataset.tz!;
      void act(() => setTimezone(tz), 'Troca de fuso marcada. Vale a partir da meia-noite.');
    });
  });
}

/** trabalho guardado da equipe (o que ela usa fora do jogo) e aviso de salário atrasado */
function laborMeter(s: FarmState): string {
  const cap = s.labor_nominal * s.labor_cap_hours;
  const p = cap > 0 ? Math.round((Math.min(s.labor_bank, cap) / cap) * 100) : 0;
  const debt = s.characters.some((c) => c.debt > 0);
  const field = s.characters.filter((c) => c.slot === 'field');
  return `<button type="button" class="labor" data-team title="Equipe em campo: ${nf1.format(s.labor_per_hour)} de trabalho por hora agora. Trabalho guardado: ${nf1.format(s.labor_bank)} de ${nf1.format(cap)}. Eles plantam e colhem sozinhos quando você não está.">
    ${field.map((c) => `<span class="mini-char">${charSprite(c.class_id, 0.5)}<span class="ebar" style="--e:${Math.round((c.energy / c.energy_max) * 100)}%"></span></span>`).join('')}
    <span class="laborbar"><span style="width:${p}%"></span></span>${debt ? '<span class="warn" title="Salário atrasado">!</span>' : ''}</button>`;
}

/** botão "Colher e plantar (N)": aparece quando há canteiro maduro, canteiro esperando plantio ou árvore com fruta */
function refreshTendButton(): void {
  const b = hud?.querySelector<HTMLButtonElement>('[data-tend]');
  const s = store.state;
  if (!b || !s) return;
  const n = tendCount(s, store.clock.farmNow());
  b.hidden = n === 0;
  const html = `${hudIcon('tend')}<span class="badge">${n}</span>`;
  if (b.innerHTML !== html) b.innerHTML = html;
  b.title = `Colher e plantar (${n})`;
  b.setAttribute('aria-label', b.title);
}

// ---------- clique do jogador ----------
let busy = false;

/** colhe e planta (canteiro, lote ou fazenda inteira) e mostra o que entrou no Silo */
async function tend(target: string | null): Promise<void> {
  const before = store.state;
  if (!before || busy) return;
  busy = true;
  const now = store.clock.farmNow();
  const lotReady = new Map(before.lots.map((l) => [l.lot_id, l.ready_at]));
  const inTarget = (id: string) => target === null || id === target || id.startsWith(`${target}-`);
  const ripe = before.plots.filter((p) => inTarget(p.plot_id) && plotLook(p, now, lotReady.get(p.plot_id.split('-')[0]) ?? 0) === 'ready');
  const ripeTrees = before.trees.filter((t) => (target === null || t.lot_id === target) && t.fruit_id && t.ready_at !== null && t.ready_at <= now);
  try {
    const after = await tendFarm(target);
    applyState(after);
    const fx = ripe.map((p) => ({ plot: p.plot_id, text: `+${CROPS[p.planted_crop_id!].units_per_harvest} ${CROPS[p.planted_crop_id!].name_pt}` }));
    for (const t of ripeTrees) fx.push({ plot: t.lot_id, text: `+${CROPS[t.fruit_id!].units_per_harvest} ${CROPS[t.fruit_id!].name_pt}` });
    const ripeAnimals = before.animals.filter((a) => animalLook(a, now) === 'ready' && (target === null || before.houses[a.house_id]?.lot === target));
    const byHouse = new Map<string, AnimalState[]>();
    for (const a of ripeAnimals) byHouse.set(a.house_id, [...(byHouse.get(a.house_id) ?? []), a]);
    for (const [house, n] of byHouse) fx.push({ plot: before.houses[house].lot, text: `${ANIMAL_BY_ID[n[0].animal_id].name_pt}: ${n.length} coleta${n.length > 1 ? "s" : ""}` });
    const hungry = after.animals.some((a) => a.state === 'hungry');
    bus.emit('fx:harvest', fx);
    const got = Object.entries(after.silo).map(([k, q]) => [k, q - (before.silo[k] ?? 0)] as const).filter(([, d]) => d > 0);
    const planted = after.plots.filter((p) => inTarget(p.plot_id) && p.state === 'growing' && p.planted_at !== null && p.planted_at >= after.farm_time - 1).length;
    const parts: string[] = [];
    if (got.length) parts.push(`Colhido: ${got.map(([k, d]) => `${d} ${itemInfo(k).name_pt}`).join(', ')}`);
    if (planted) parts.push(`${planted} plantado${planted > 1 ? 's' : ''}`);
    const stalled = after.plots.some((p) => inTarget(p.plot_id) && p.state === 'empty' && p.stalled_reason === 'sem_ouro');
    if (stalled) parts.push('falta ouro para algumas sementes');
    if (hungry && ripeAnimals.length) parts.push('falta ouro para a ração de algum animal');
    toast(parts.join(' · ') || 'Nada para colher ou plantar agora.');
  } catch (e) {
    toast(e instanceof Error ? e.message : 'Não deu certo.');
  } finally {
    busy = false;
  }
}

function onPlotClick(id: string): void {
  const s = store.state;
  const p = s?.plots.find((x) => x.plot_id === id);
  if (!s || !p) return;
  const look = plotLook(p, store.clock.farmNow(), s.lots.find((l) => l.lot_id === id.split('-')[0])?.ready_at ?? 0);
  if (look === 'ready' || look === 'planned') void tend(id);
  else openPlot(id);
}

function onOrchardClick(lot: string): void {
  const s = store.state;
  const now = store.clock.farmNow();
  if (s?.trees.some((t) => t.lot_id === lot && t.fruit_id && t.ready_at !== null && t.ready_at <= now)) void tend(lot);
  else openOrchard(lot);
}

function levelUp(from: number, to: number): void {
  const news = CROP_LIST.filter((c) => c.unlock_level > from && c.unlock_level <= to).map((c) => c.name_pt);
  const tools = TOOL_MATERIALS.filter((m) => m.unlock_level > from && m.unlock_level <= to).map((m) => `ferramentas de ${m.name_pt}`);
  const hires = CLASSES.filter((c) => c.unlock_level > from && c.unlock_level <= to).map((c) => `contratar ${c.name_pt}`);
  const pets = PETS.list.filter((p) => p.unlock_level > from && p.unlock_level <= to).map((p) => `${p.name_pt} chegou à fazenda`);
  const animals = ANIMALS.filter((a) => a.unlock_level > from && a.unlock_level <= to).map((a) => a.name_pt);
  const extra = [...news, ...animals, ...tools, ...hires, ...pets];
  toast(`Nível ${to}!${extra.length ? ` Liberado: ${extra.join(', ')}.` : ''}`, FARM.ui.level_up_toast_seconds);
}

function toast(msg: string, seconds = 3.5): void {
  const t = root.querySelector<HTMLElement>('#toast')!;
  t.textContent = msg;
  t.classList.add('show');
  window.clearTimeout(Number(t.dataset.timer));
  t.dataset.timer = String(window.setTimeout(() => t.classList.remove('show'), seconds * 1000));
}

function show(title: string, body: () => string, bind?: (el: HTMLElement) => void): void {
  let again = false; // o [?] aberto continua aberto só quando o mesmo painel redesenha
  const render = () => {
    const scroll = panel.querySelector('.body')?.scrollTop ?? 0;
    const helpOpen = again && !!panel.querySelector('.help-pop:not([hidden])');
    again = true;
    panel.innerHTML = `<div class="panel game-panel" role="dialog" aria-label="${esc(title)}">
      <header><h2>${esc(title)}</h2><button type="button" class="help-btn" aria-label="Ajuda" title="Como funciona" hidden>${hudIcon('help', 18)}</button><button type="button" class="close" aria-label="Fechar">×</button></header>
      <div class="help-pop" role="note" hidden></div>
      <div class="body">${body()}</div></div>`;
    panel.querySelector('.close')!.addEventListener('click', close);
    tidyPanel(panel, helpOpen);
    panel.querySelector('.body')!.scrollTop = scroll;
    bind?.(panel);
  };
  current = render;
  panel.hidden = false;
  panel.querySelector('.body')?.scrollTo(0, 0);
  render();
}

function close(): void { panel.hidden = true; current = null; }

/** UI 16-bit: as explicações longas (.hint) saem da tela e vão para o [?] do cabeçalho;
 *  todo <select> vira um seletor de madeira (lista própria), mantendo o select escondido para o código de sempre */
export function tidyPanel(el: HTMLElement, helpOpen = false): void {
  const body = el.querySelector<HTMLElement>('.body');
  const pop = el.querySelector<HTMLElement>('.help-pop');
  const btn = el.querySelector<HTMLButtonElement>('.help-btn');
  if (body && pop && btn) {
    const hints = [...body.querySelectorAll<HTMLElement>(':scope > .hint:not(.good):not(.keep)')];
    if (hints.length) {
      pop.innerHTML = hints.map((h) => `<p>${h.innerHTML}</p>`).join('');
      hints.forEach((h) => h.remove());
      btn.hidden = false;
      pop.hidden = !helpOpen;
      btn.setAttribute('aria-expanded', String(helpOpen));
      btn.addEventListener('click', () => { pop.hidden = !pop.hidden; btn.setAttribute('aria-expanded', String(!pop.hidden)); });
    }
  }
  el.querySelectorAll<HTMLSelectElement>('select:not([data-native])').forEach(woodSelect);
}

/** seletor de madeira no lugar do <select> nativo: botão com o valor e lista de opções; ←/→ trocam */
function woodSelect(sel: HTMLSelectElement): void {
  if (sel.dataset.wood) return;
  sel.dataset.wood = '1';
  sel.hidden = true;
  const box = document.createElement('span');
  box.className = 'wsel';
  const label = () => sel.options[sel.selectedIndex]?.text ?? '';
  box.innerHTML = `<button type="button" class="wsel-arrow" aria-label="Anterior">◀</button><button type="button" class="wsel-btn" aria-haspopup="listbox" aria-expanded="false"></button><button type="button" class="wsel-arrow" aria-label="Próximo">▶</button><ul class="wsel-list" role="listbox" hidden></ul>`;
  const [prev, main, next] = box.querySelectorAll<HTMLButtonElement>('button');
  const list = box.querySelector<HTMLUListElement>('ul')!;
  const pick = (i: number) => {
    if (i < 0 || i >= sel.options.length || i === sel.selectedIndex) return;
    sel.selectedIndex = i;
    sel.dispatchEvent(new Event('change', { bubbles: true }));
    sync();
  };
  const sync = () => {
    main.textContent = label();
    list.innerHTML = [...sel.options].map((o, i) => `<li role="option" data-i="${i}" aria-selected="${i === sel.selectedIndex}">${esc(o.text)}</li>`).join('');
  };
  main.addEventListener('click', () => { list.hidden = !list.hidden; main.setAttribute('aria-expanded', String(!list.hidden)); });
  list.addEventListener('click', (e) => {
    const li = (e.target as HTMLElement).closest<HTMLElement>('li[data-i]');
    if (li) { pick(Number(li.dataset.i)); list.hidden = true; main.setAttribute('aria-expanded', 'false'); }
  });
  prev.addEventListener('click', () => pick(sel.selectedIndex - 1));
  next.addEventListener('click', () => pick(sel.selectedIndex + 1));
  sync();
  sel.after(box);
}

function openInfo(title: string, text: string): void { show(title, () => `<p>${esc(text)}</p>`); }

async function act(fn: () => Promise<FarmState>, ok?: string): Promise<void> {
  try { applyState(await fn()); if (ok) toast(ok); } catch (e) { toast(e instanceof Error ? e.message : 'Não deu certo.'); }
}

/** fim da limpeza do lote, se ainda estiver em limpeza */
function cleanupLeft(lot: string): number | null {
  const l = store.state?.lots.find((x) => x.lot_id === lot);
  const left = l ? l.ready_at - store.clock.farmNow() : 0;
  return left > 0 ? left : null;
}

// ---------- canteiro ----------
function cropInfo(c: Crop): string {
  const sell = c.units_per_harvest * c.fair_price_per_unit * stallRatio() * salesMult();
  const base = `Cresce em ${duration(c.grow_minutes * 60)} · semente ${nf1.format(c.seed_cost ?? 0)} · colheita ${c.units_per_harvest} × ${formatGold(c.fair_price_per_unit)} (Barraca ${nf1.format(sell)}) · ${nf1.format(c.xp_per_harvest)} XP`;
  if (c.kind !== 'recurring') return base;
  return `${base}<br>Recorrente: ${c.harvests_per_planting} colheitas com 1 semente, uma a cada ${duration((c.regrow_minutes ?? 0) * 60)} depois da 1ª`;
}

function plotStatus(p: PlotState): string {
  const now = store.clock.farmNow();
  const lot = p.plot_id.split('-')[0];
  const cleanup = cleanupLeft(lot);
  const name = (id: string) => `<strong>${esc(CROPS[id].name_pt)}</strong>`;
  const next = p.crop_id && p.crop_id !== p.planted_crop_id ? `<br>Depois: ${name(p.crop_id)}.` : '';
  if (cleanup) return `Lote em limpeza: fica pronto em ${duration(cleanup)}. ${p.crop_id ? `Depois planta ${name(p.crop_id)}.` : 'Já dá para escolher o cultivo.'}`;
  if (p.state === 'growing') {
    const c = CROPS[p.planted_crop_id!];
    const which = (c.kind === 'recurring' ? ` (colheita ${p.harvests_done + 1} de ${c.harvests_per_planting})` : '')
      + (p.rarity ? ` · semente ${RARITY_BY_ID[p.rarity].name_pt} ×${nf1.format(RARITY_BY_ID[p.rarity].multiplier)}` : '');
    if (p.ready_at! <= now) return `Agora: ${name(c.id)} pronta${which}. Clique no canteiro ou em "Colher agora".${next}`;
    return `Agora: ${name(c.id)} crescendo${which}, pronta em ${duration(p.ready_at! - now)}.${next}`;
  }
  if (p.crop_id && p.stalled_reason === 'sem_ouro') return `Parado: falta ouro para a semente de ${name(p.crop_id)}. Venda algo na Barraca.`;
  if (p.crop_id) return `Vazio, com ${name(p.crop_id)} escolhida. Clique no canteiro para plantar agora ou deixe a equipe plantar.`;
  return 'Vazio. Escolha um cultivo: ele é plantado na hora e replantado sempre que for colhido.';
}

function cropButton(c: Crop, selected: boolean, locked: boolean, attr: string): string {
  return `<button type="button" class="crop ${selected ? 'selected' : ''} ${locked ? 'locked' : ''}" ${locked ? 'disabled' : `${attr}="${c.id}"`} aria-pressed="${selected}">
    ${sprite(iconSprite(store.manifest, c.id), 1)}
    <span><strong>${esc(c.name_pt)}${locked ? ` · nível ${c.unlock_level}` : ''}</strong><small>${cropInfo(c)}</small></span>
  </button>`;
}

function openPlot(id: string): void {
  // 1 cultivo por lote (decisão do dono, 25/10): a escolha vale para os 8 canteiros do lote
  const lot = id.split('-')[0];
  show(`Lavoura ${lot}`, () => {
    const s = store.state;
    const p = s?.plots.find((x) => x.plot_id === id);
    if (!s || !p) return '<p>Carregando…</p>';
    const mine = s.plots.filter((x) => x.plot_id.startsWith(`${lot}-`));
    const count = new Map<string, number>();
    for (const x of mine) if (x.crop_id) count.set(x.crop_id, (count.get(x.crop_id) ?? 0) + 1);
    const lotCrop = [...count.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
    const now = store.clock.farmNow();
    const readyN = mine.filter((x) => x.state === 'growing' && x.ready_at !== null && x.ready_at <= now).length;
    const growingN = mine.filter((x) => x.state === 'growing').length;
    const { open, next } = plotCrops(s.level);
    const crops = [...[...open].reverse().map((c) => cropButton(c, lotCrop === c.id, false, 'data-crop')), ...next.map((c) => cropButton(c, false, true, ''))].join('');
    const seeds = rareSeeds(s.inventory).filter((r) => CROPS[r.crop].kind !== 'orchard' && r.crop === lotCrop); // só do cultivo do lote
    const canRare = !cleanupLeft(lot) && (p.state === 'empty' || (p.ready_at !== null && p.ready_at <= now));
    const rare = seeds.length ? `<h3>Sementes raras</h3><div class="crops">${seeds.map((r) => {
      const t = RARITY_BY_ID[r.rarity];
      return `<button type="button" class="crop" data-rare="${r.crop}:${r.rarity}" ${canRare ? '' : 'disabled'}>${sprite(iconSprite(store.manifest, r.crop), 1)}
        <span><strong style="color:${t.color_hex}">${esc(CROPS[r.crop].name_pt)} ${esc(t.name_pt)} × ${r.qty}</strong><small>Colheita e XP ×${nf1.format(t.multiplier)} no canteiro ${esc(id)}, sem pagar semente${canRare ? '' : ' · colha ou espere o canteiro ficar livre'}</small></span></button>`;
    }).join('')}</div>` : '';
    const status = lotCrop
      ? `<strong>${esc(CROPS[lotCrop].name_pt)}</strong> no lote · ${growingN} de ${mine.length} canteiros plantados${readyN ? ` · <strong>${readyN} prontos</strong>` : ''}`
      : 'Lote parado. Escolha um cultivo para os 8 canteiros.';
    return `<p class="status">${status}</p>
      <div class="row top">
        ${readyN ? `<button type="button" class="primary small" data-harvest>Colher o lote (${readyN})</button>` : ''}
        ${lotCrop ? '<button type="button" class="secondary" data-stop>Parar o lote</button>' : ''}
      </div>
      ${rare}<div class="crops">${crops}</div>
      <p class="hint">Cada lote planta um cultivo só. Com o jogo aberto, plantar e colher com clique é grátis. Quando você sai, a equipe em campo faz sozinha: ${nf1.format(WORK.plant)} de trabalho para plantar e ${nf1.format(WORK.harvest)} para colher (agora ${nf1.format(s.labor_per_hour)} por hora, enquanto tiverem energia). Cultivos longos rendem melhor enquanto você está fora.</p>`;
  }, (el) => {
    el.querySelectorAll<HTMLButtonElement>('[data-crop]').forEach((b) => b.addEventListener('click', () => {
      const chosen = b.dataset.crop!;
      void act(() => setCrop(lot, chosen), `${CROPS[chosen].name_pt} no lote ${lot}`).then(close);
    }));
    el.querySelector('[data-harvest]')?.addEventListener('click', () => void tend(lot));
    el.querySelectorAll<HTMLButtonElement>('[data-rare]').forEach((b) => b.addEventListener('click', () => {
      const [crop, rarity] = b.dataset.rare!.split(':');
      b.disabled = true;
      void act(() => plantRareSeed(id, crop, rarity), `${CROPS[crop].name_pt} ${RARITY_BY_ID[rarity].name_pt} plantada no canteiro ${id}`).then(close);
    }));
    el.querySelector('[data-stop]')?.addEventListener('click', () => void act(() => setCrop(lot, null), `Lote ${lot} parado`));
  });
}

// ---------- lote à venda ----------
const PROBLEM_TEXT: Record<string, (o: NonNullable<ReturnType<typeof lotOffer>>) => string> = {
  vizinho: () => 'Precisa dividir um lado com um lote seu (Galinheiro e Celeiro podem ser comprados de longe).',
  nivel: (o) => `Precisa do nível ${o.needLevel}.`,
  ouro: (o) => `Falta ${formatGold(o.cost - (store.state?.gold ?? 0))} de ouro.`,
  fim: () => 'Você já comprou todos os lotes.',
};

function openLot(id: string): void {
  const def = LOT_BY_ID[id];
  show(`${LOT_TYPE_NAMES[def.type]} ${id}`, () => {
    const s = store.state!;
    const owned = new Set(s.lots.map((l) => l.lot_id));
    const smith = s.characters.some((c) => c.class_id === 'ferreiro');
    const o = lotOffer(id, owned, s.level, s.gold, smith, s.fx.cleanup);
    if (!o) return '<p>Este lote já é seu.</p>';
    if (o.problems.includes('fim')) return `<p>${PROBLEM_TEXT.fim(o)}</p>`;
    const what = def.type === 'lavoura' ? '8 canteiros' : def.type === 'pomar' ? '4 vagas de árvore'
      : def.type === 'pasto_lago' ? `Lago: pesca sozinho (rede de ${FISHING.cycle_minutes * FISHING.max_cycles / 60} h, peixe no Silo) e +${ANIMAL_RULES.lake_bonus.extra_galinheiro_slots} vagas de ave no Galinheiro`
      : `${def.type === 'pasto_galinheiro' ? 'Galinheiro' : 'Celeiro'} com 4 vagas para animais`;
    return `<dl class="facts">
        <dt>Compra</dt><dd>${o.n}ª de 29</dd>
        <dt>O que vem</dt><dd>${what}</dd>
        <dt>Custo</dt><dd>${sprite('ui_coin', 1, 'coin-img')} ${formatGold(o.cost)} ouro <small>(${o.daysOfIncome < 1 ? 'menos de 1 dia' : `≈ ${nf1.format(o.daysOfIncome)} dias`} de renda no seu nível)</small></dd>
        <dt>Nível</dt><dd>${o.needLevel}</dd>
        <dt>Limpeza</dt><dd>${duration(o.cleanupMinutes * 60)} <small>(pedras e tocos; ${smith ? 'com o Ferreiro' : 'sem Ferreiro contratado leva o dobro'})</small></dd>
      </dl>
      ${o.problems.length ? `<ul class="problems">${o.problems.map((p) => `<li>${PROBLEM_TEXT[p](o)}</li>`).join('')}</ul>` : ''}
      <button type="button" class="primary" data-buy ${o.problems.length ? 'disabled' : ''}>Comprar por ${formatGold(o.cost)} ouro</button>`;
  }, (el) => {
    el.querySelector<HTMLButtonElement>('[data-buy]')?.addEventListener('click', (e) => {
      (e.currentTarget as HTMLButtonElement).disabled = true;
      void act(() => buyLot(id), `Lote ${id} comprado! A limpeza começou.`).then(() => { if (store.state?.lots.some((l) => l.lot_id === id)) close(); });
    });
  });
}

// ---------- pomar ----------
function treeStatus(lot: string, slot: number): string {
  const t = store.state?.trees.find((x) => x.lot_id === lot && x.slot === slot);
  if (!t || !t.fruit_id) return 'Vaga vazia.';
  const c = CROPS[t.fruit_id];
  const now = store.clock.farmNow();
  const look = treeLook(t, now);
  const left = t.ready_at! - now;
  const when = left > 0 ? `próxima colheita em ${duration(left)}` : 'pronta para colher';
  const rare = t.rarity && (t.rare_left ?? 0) > 0 ? ` · ${RARITY_BY_ID[t.rarity].name_pt} ×${nf1.format(RARITY_BY_ID[t.rarity].multiplier)} (${t.rare_left} colheitas)` : '';
  return `<strong>${esc(c.name_pt)}</strong> · ${look === 'sapling' ? 'muda' : look === 'fruit' ? 'com fruta' : 'adulta'} · ${when}${rare}`;
}

function fruitInfo(c: Crop): string {
  const sell = c.units_per_harvest * c.fair_price_per_unit * stallRatio() * salesMult();
  return `Muda ${formatGold(c.sapling_cost ?? 0)} · 1ª colheita em ${duration(c.grow_minutes * 60)}, depois a cada ${duration((c.regrow_minutes ?? c.grow_minutes) * 60)} · ${c.units_per_harvest} × ${formatGold(c.fair_price_per_unit)} (Barraca ${nf1.format(sell)}) · ${nf1.format(c.xp_per_harvest)} XP`;
}

function openOrchard(lot: string): void {
  let picking: number | null = null;
  show(`Pomar ${lot}`, () => {
    const s = store.state!;
    const cleanup = cleanupLeft(lot);
    if (cleanup) return `<p class="status">Lote em limpeza: fica pronto em ${duration(cleanup)}. Depois dá para plantar as mudas.</p>`;
    const now = store.clock.farmNow();
    const slots = s.trees.filter((t) => t.lot_id === lot).map((t) => {
      const ready = !!t.fruit_id && t.ready_at !== null && t.ready_at <= now;
      const art = t.fruit_id ? sprite(iconSprite(store.manifest, t.fruit_id), 2) : '<span class="slot-empty">+</span>';
      return `<div class="gcard ${ready ? 'ready' : ''} ${picking === t.slot ? 'picked' : ''} ${t.fruit_id ? '' : 'empty'}"><span class="gcard-n">Vaga ${t.slot}</span>
        <div class="gcard-art">${art}${ready ? '<span class="find-dot">!</span>' : ''}</div>
        <small>${treeStatus(lot, t.slot)}</small>
        <div class="gcard-btns">${ready ? `<button type="button" class="primary small" data-harvest>Colher</button>` : ''}
          <button type="button" class="${picking === t.slot ? 'primary small' : 'secondary small'}" data-pick="${t.slot}">${t.fruit_id ? 'Trocar' : 'Plantar'}</button>
          ${t.fruit_id ? `<button type="button" class="secondary small danger" data-chop="${t.slot}" title="Derrubar (grátis)">Derrubar</button>` : ''}</div></div>`;
    }).join('');
    let picker = '';
    if (picking !== null) {
      const has = s.trees.find((t) => t.lot_id === lot && t.slot === picking)?.fruit_id;
      const { open, next } = orchardFruits(s.level);
      const btn = (c: Crop, locked: boolean) => `<button type="button" class="crop ${locked ? 'locked' : ''}" ${locked ? 'disabled' : `data-fruit="${c.id}"`}>
        ${sprite(iconSprite(store.manifest, c.id), 1)}<span><strong>${esc(c.name_pt)}${locked ? ` · nível ${c.unlock_level}` : ''}</strong><small>${fruitInfo(c)}</small></span></button>`;
      const rare = rareSeeds(s.inventory).filter((r) => CROPS[r.crop].kind === 'orchard').map((r) => {
        const t = RARITY_BY_ID[r.rarity];
        return `<button type="button" class="crop" data-rare-tree="${r.crop}:${r.rarity}">${sprite(iconSprite(store.manifest, r.crop), 1)}
          <span><strong style="color:${t.color_hex}">${esc(CROPS[r.crop].name_pt)} ${esc(t.name_pt)} × ${r.qty}</strong><small>Muda grátis; as próximas 6 colheitas rendem ×${nf1.format(t.multiplier)}</small></span></button>`;
      }).join('');
      picker = `<h3>Muda para a vaga ${picking}</h3>${has ? '<p class="hint">A árvore atual é derrubada de graça e a nova muda cresce do zero.</p>' : ''}
        <div class="crops">${rare}${[...[...open].reverse().map((c) => btn(c, false)), ...next.map((c) => btn(c, true))].join('') || '<p>Nenhuma fruta liberada ainda.</p>'}</div>`;
    }
    const ripe = s.trees.some((t) => t.lot_id === lot && t.fruit_id && t.ready_at !== null && t.ready_at <= store.clock.farmNow());
    return `${ripe ? '<div class="row top"><button type="button" class="primary small" data-harvest>Colher as frutas</button></div>' : ''}<div class="gcard-grid">${slots}</div>${picker}
      <p class="hint">Com o jogo aberto, colher com clique é grátis; fora do jogo a equipe colhe (${nf1.format(WORK.harvest)} de trabalho por árvore; a Rancheira trabalha a 100% no pomar). Árvores não precisam de semente.</p>`;
  }, (el) => {
    el.querySelectorAll('[data-harvest]').forEach((b) => b.addEventListener('click', () => void tend(lot)));
    el.querySelectorAll<HTMLButtonElement>('[data-pick]').forEach((b) => b.addEventListener('click', () => { picking = Number(b.dataset.pick); current?.(); }));
    el.querySelectorAll<HTMLButtonElement>('[data-chop]').forEach((b) => b.addEventListener('click', () => {
      b.disabled = true;
      void act(() => chopTree(lot, Number(b.dataset.chop)), 'Árvore derrubada.');
    }));
    el.querySelectorAll<HTMLButtonElement>('[data-rare-tree]').forEach((b) => b.addEventListener('click', () => {
      const [fruit, rarity] = b.dataset.rareTree!.split(':');
      const slot = picking!;
      picking = null;
      void act(() => plantRareTree(lot, slot, fruit, rarity), `Muda ${RARITY_BY_ID[rarity].name_pt} de ${CROPS[fruit].name_pt} plantada.`);
    }));
    el.querySelectorAll<HTMLButtonElement>('[data-fruit]').forEach((b) => b.addEventListener('click', () => {
      const slot = picking!;
      picking = null;
      void act(() => plantTree(lot, slot, b.dataset.fruit!), `Muda de ${CROPS[b.dataset.fruit!].name_pt} plantada.`);
    }));
  });
}


// ---------- animais (fase 4) ----------
const houseOfLot = (lot: string) => Object.entries(store.state?.houses ?? {}).find(([, h]) => h.lot === lot)?.[0] ?? null;

function onPastureClick(lot: string): void {
  const s = store.state;
  if (!s) return;
  const house = houseOfLot(lot);
  if (!house) { openLake(); return; }
  const now = store.clock.farmNow();
  if (s.animals.some((a) => a.house_id === house && animalLook(a, now) === 'ready')) void tend(lot);
  else openHouse(house);
}

/** Vara de Pescar (ferramenta do Lago): aparece no painel do Lago e na Forja */
function rodCard(s: FarmState): string {
  const f = s.fishing;
  if (!f) return '';
  const low = f.rod < FISHING.rod.low_threshold;
  return `<div class="char-card">${sprite('card_full_pesca_common', 0.36)}<div class="grow"><strong>Vara de Pescar</strong>
        <span class="energy dura ${low ? 'low' : ''}"><span style="width:${Math.round(f.rod)}%"></span></span>
        <small>Ferramenta do Lago · durabilidade ${nf1.format(f.rod)} de 100 · gasta ${nf1.format(FISHING.rod.wear_per_cycle)} por ciclo recolhido${low ? ` · <span class="bad">abaixo de ${FISHING.rod.low_threshold}: a pesca rende a metade</span>` : ''}</small>
        <span class="btns"><button type="button" class="secondary" data-rod ${f.rod >= 100 || s.gold < f.rod_repair ? 'disabled' : ''}>Consertar · ${formatGold(f.rod_repair)}</button></span></div></div>`;
}

function bindRod(el: HTMLElement): void {
  el.querySelector<HTMLButtonElement>('[data-rod]')?.addEventListener('click', (e) => {
    (e.currentTarget as HTMLButtonElement).disabled = true;
    void act(() => repairRod(), 'Vara de Pescar consertada.');
  });
}

/** Lago: rede pronta recolhe na hora; senão mostra a rede e a Vara de Pescar (desgaste e conserto) */
function openLake(): void {
  const s0 = store.state!;
  const f0 = s0.fishing;
  if (f0 && fishCycles(f0.fish_t, store.clock.farmNow()) > 0) { void act(() => collectFish(), 'Rede recolhida: peixe no Silo!').then(() => openLake()); return; }
  show('Lago', () => {
    const s = store.state!, f = s.fishing, lb = ANIMAL_RULES.lake_bonus;
    if (!f) return `<p>Compre o Lago para pescar. Ele também dá +${lb.extra_galinheiro_slots} vagas de ave no Galinheiro.</p>`;
    const sp = fishSpecies(s.level), now = store.clock.farmNow(), cyc = fishCycles(f.fish_t, now);
    const next = f.fish_t + FISHING.cycle_minutes * 60 * (cyc + 1) - now;
    return `<p>Rede: <strong>${cyc}/${FISHING.max_cycles}</strong> ciclos de ${esc(sp.name_pt)}${cyc < FISHING.max_cycles ? ` · próximo em ${duration(Math.max(0, next))}` : ' · cheia'}.</p>
      ${rodCard(s)}
      <p class="hint">A rede enche sozinha: 1 ciclo a cada ${FISHING.cycle_minutes / 60} h, até ${FISHING.max_cycles}. Clique no Lago para recolher; fora do jogo a equipe recolhe a rede cheia. O peixe vai para o Silo. O Lago também dá +${lb.extra_galinheiro_slots} vagas de ave no Galinheiro.</p>`;
  }, bindRod);
}

function animalStatus(a: AnimalState): string {
  const now = store.clock.farmNow();
  const look = animalLook(a, now);
  const d = ANIMAL_BY_ID[a.animal_id];
  if (look === 'hungry') return '<span class="bad">Com fome: falta ouro para a ração. Venda algo e ele volta.</span>';
  if (look === 'ready') return `<strong>${esc(d.product.name_pt)} pronto</strong> · clique para coletar`;
  return `Produzindo ${esc(d.product.name_pt)} · pronto em ${duration(a.ready_at! - now)}`;
}

function openHouse(house: string): void {
  let picking: number | null = null;
  show(HOUSE_NAMES[house] ?? house, () => {
    const s = store.state!;
    const h = s.houses[house];
    if (!h?.owned) return `<p class="status">${cleanupLeft(h?.lot ?? '') ? `Pasto em limpeza: fica pronto em ${duration(cleanupLeft(h.lot)!)}.` : 'Compre o pasto para ter esta casa.'}</p>`;
    const now = store.clock.farmNow();
    const total = h.slots + h.bird_slots;
    const fx = s.fx;
    const rows = Array.from({ length: total }, (_, i) => {
      const slot = i + 1;
      const bird = slot > h.slots;
      const a = s.animals.find((x) => x.house_id === house && x.slot === slot);
      if (!a) return `<div class="gcard empty ${picking === slot ? 'picked' : ''}"><span class="gcard-n">Vaga ${slot}</span><div class="gcard-art"><span class="slot-empty">+</span></div>
        <small>${bird ? 'Vaga do Lago (só aves)' : 'Vazia'}</small>
        <div class="gcard-btns"><button type="button" class="${picking === slot ? 'primary small' : 'secondary small'}" data-pick-slot="${slot}">Comprar</button></div></div>`;
      const d = ANIMAL_BY_ID[a.animal_id];
      const r = RARITY_BY_ID[a.rarity];
      const ready = animalLook(a, now) === 'ready';
      return `<div class="gcard ${ready ? 'ready' : ''}"><span class="gcard-n">Vaga ${slot}</span><div class="gcard-art">${animalFace(a.animal_id)}${ready ? '<span class="find-dot">!</span>' : ''}</div>
        <strong>${esc(d.name_pt)}</strong><span class="shield" style="--c:${r.color_hex}">${esc(r.name_pt)} ×${nf1.format(r.multiplier)}</span>
        <small>${animalStatus(a)}</small>
        <div class="gcard-btns">${ready ? `<button type="button" class="primary small" data-collect>Coletar</button>` : ''}<button type="button" class="secondary small danger" data-remove="${slot}">Tirar</button></div></div>`;
    }).join('');
    let picker = '';
    if (picking !== null) {
      const bird = picking > h.slots;
      const list = ANIMALS.filter((x) => x.house === house && (!bird || x.is_bird));
      picker = `<h3>Animal para a vaga ${picking}</h3><div class="crops">${list.map((x) => {
        const locked = x.unlock_level > s.level;
        const feed = feedPerCycle(x.feed_cost_per_day, x.produce_every_minutes, fx.feed_discount);
        const value = x.product.fair_price_per_unit * collectUnits(1, fx.animal_production, fx.animal_cap, x.is_bird, (fx as { bird_bonus?: number }).bird_bonus ?? 0);
        return `<button type="button" class="crop ${locked ? 'locked' : ''}" ${locked || s.gold < x.buy_cost ? 'disabled' : `data-buy-animal="${x.id}"`}>
          ${animalFace(x.id)}<span><strong>${esc(x.name_pt)}${locked ? ` · nível ${x.unlock_level}` : ` · ${formatGold(x.buy_cost)} ouro`}</strong>
          <small>${esc(x.product.name_pt)} a cada ${duration(x.produce_every_minutes * 60)} (Feira ${formatGold(value)}) · ração ${formatGold(feed)} por ciclo · ${nf1.format(x.xp_per_collect)} XP</small></span></button>`;
      }).join('')}</div><p class="hint">A raridade é sorteada na compra (Comum 75%, Incomum 18%, Raro 5%, Lendário 1,5%, Mítico 0,5%) e fica para sempre. Tirar o animal não devolve o ouro.</p>`;
    }
    const next = HOUSES[house].slots[h.tier + 1];
    const upCost = next ? Math.round(next.cost * (1 + fx.expansion_cost) * 100) / 100 : 0;
    const upWhy = !next ? '' : (next.min_level ?? 0) > s.level ? `nível ${next.min_level}` : s.gold < upCost ? `falta ${formatGold(upCost - s.gold)}` : '';
    const anyReady = s.animals.some((a) => a.house_id === house && animalLook(a, now) === 'ready');
    return `${anyReady ? '<div class="row top"><button type="button" class="primary small" data-collect>Coletar tudo</button></div>' : ''}
      <div class="gcard-grid">${rows}</div>${picker}
      ${next ? `<div class="row"><button type="button" class="secondary" data-upgrade-house ${upWhy ? 'disabled' : ''}>Ampliar para ${next.slots} vagas · ${formatGold(upCost)}${upWhy ? ` (${upWhy})` : ''}</button></div>` : ''}
      <p class="hint">Com o jogo aberto, coletar com clique é grátis e rende 100%. Fora do jogo a equipe coleta (${nf1.format(WORK.harvest)} de trabalho) e rende ${Math.round(ANIMAL_RULES.collector_efficiency.rancheira * 100)}% com a Rancheira em campo, ${Math.round(ANIMAL_RULES.collector_efficiency.other_class * 100)}% sem ela${fx.rancheira ? ' (ela está em campo)' : ''}. A ração é cobrada no começo de cada ciclo.${house === 'galinheiro' && !s.lake ? ' O Lago dá +2 vagas para aves.' : ''}</p>`;
  }, (el) => {
    const s = store.state!;
    el.querySelectorAll('[data-collect]').forEach((b) => b.addEventListener('click', () => void tend(s.houses[house].lot)));
    el.querySelectorAll<HTMLButtonElement>('[data-pick-slot]').forEach((b) => b.addEventListener('click', () => { picking = Number(b.dataset.pickSlot); current?.(); }));
    el.querySelectorAll<HTMLButtonElement>('[data-buy-animal]').forEach((b) => b.addEventListener('click', () => {
      const slot = picking!;
      picking = null;
      b.disabled = true;
      void act(() => buyAnimal(house, slot, b.dataset.buyAnimal!)).then(() => {
        const a = store.state?.animals.find((x) => x.house_id === house && x.slot === slot);
        if (a) toast(`${ANIMAL_BY_ID[a.animal_id].name_pt} ${RARITY_BY_ID[a.rarity].name_pt}!${a.rarity === 'common' ? '' : ` Produz ×${nf1.format(RARITY_BY_ID[a.rarity].multiplier)}.`}`, 5);
      });
    }));
    el.querySelectorAll<HTMLButtonElement>('[data-remove]').forEach((b) => b.addEventListener('click', () => {
      if (b.dataset.confirm !== '1') { b.dataset.confirm = '1'; b.textContent = 'Tirar mesmo? (sem reembolso)'; return; }
      b.disabled = true;
      void act(() => removeAnimal(house, Number(b.dataset.remove)), 'Animal retirado.');
    }));
    el.querySelector<HTMLButtonElement>('[data-upgrade-house]')?.addEventListener('click', (e) => {
      (e.currentTarget as HTMLButtonElement).disabled = true;
      void act(() => upgradeHouse(house), 'Casa ampliada!');
    });
  });
}

// ---------- zonas ----------
function siloItems(withSell: boolean): string {
  const s = store.state!;
  const items = Object.entries(s.silo).filter(([, q]) => q > 0);
  if (!items.length) return '<p class="empty">O Silo está vazio. As colheitas chegam aqui sozinhas.</p>';
  return `<ul class="items">${items.map(([id, q]) => {
    const c = itemInfo(id);
    const unit = c.price * stallRatio() * salesMult();
    const auto = s.auto_sell.includes(id);
    return `<li>${itemIcon(id)}<span><strong>${esc(c.name_pt)}</strong><small>${q} no Silo · Barraca ${nf1.format(unit)} cada</small></span>
      ${withSell ? `<span class="btns"><button type="button" class="secondary" data-sell="${id}" data-qty="1">Vender 1</button><button type="button" class="primary small" data-sell="${id}" data-qty="${q}">Vender tudo (${formatGold(q * unit)})</button>
      <label class="check"><input type="checkbox" data-auto="${id}" ${auto ? 'checked' : ''}> Venda automática</label></span>` : ''}</li>`;
  }).join('')}</ul>`;
}

function bindSell(el: HTMLElement): void {
  el.querySelectorAll<HTMLButtonElement>('[data-sell]').forEach((b) => b.addEventListener('click', () => {
    b.disabled = true;
    const qty = Number(b.dataset.qty);
    void act(() => sellAtStall(b.dataset.sell!, qty), `Vendido: ${qty} ${itemInfo(b.dataset.sell!).name_pt}`);
  }));
  el.querySelectorAll<HTMLInputElement>('[data-auto]').forEach((b) => b.addEventListener('change', () => {
    const id = b.dataset.auto!;
    void act(() => setAutoSell(id, b.checked), b.checked ? `${itemInfo(id).name_pt}: o Comerciante vende sozinho` : `${itemInfo(id).name_pt}: venda automática desligada`);
  }));
  el.querySelectorAll<HTMLButtonElement>('[data-snack-buy]').forEach((b) => b.addEventListener('click', () => {
    b.disabled = true;
    const qty = Number(b.dataset.qty);
    void act(() => buySnack(b.dataset.snackBuy!, qty), `Comprado: ${qty} ${SNACKS.find((x) => x.id === b.dataset.snackBuy)!.name_pt}`);
  }));
}

/** situação do personagem em uma frase */
function charStatus(c: CharacterState): string {
  if (!c.active && c.unpaid_days > 0) return `<span class="bad">Parado: ${c.unpaid_days} dias sem salário</span>`;
  const parts: string[] = [];
  if (c.slot === 'bench') parts.push(c.energy >= c.energy_max ? 'Descansado, no banco' : 'Descansando no banco');
  else if (c.parked) parts.push(`Sem energia: descansa até ${CHARS.energy.parked_until}`);
  else parts.push('Em campo');
  if (c.debt > 0) parts.push(`<span class="bad">Desmotivado (−50%): deve ${formatGold(c.debt)}</span>`);
  return parts.join(' · ');
}

function energyBar(c: CharacterState): string {
  const p = Math.round((c.energy / c.energy_max) * 100);
  return `<span class="energy" role="progressbar" aria-label="Energia" aria-valuenow="${p}" aria-valuemin="0" aria-valuemax="100" title="Energia ${nf1.format(c.energy)} de ${nf1.format(c.energy_max)}"><span style="width:${p}%"></span></span>`;
}

function charCard(c: CharacterState, s: FarmState): string {
  const full = s.characters.filter((x) => x.slot === 'field').length >= CHARS.field_slots;
  const role = toolCard(c.class_id).primary_role_pt;
  const next = hoursToNext(c.level);
  const move = c.slot === 'field'
    ? `<button type="button" class="secondary" data-slot="${c.class_id}" data-to="bench">Para o banco</button>`
    : `<button type="button" class="secondary" data-slot="${c.class_id}" data-to="field" ${full ? 'disabled title="Campo cheio"' : ''}>Para o campo</button>`;
  return `<div class="char-card ${c.slot}">${charPortrait(c.class_id)}<div class="grow">
    <strong>${esc(className(c.class_id))} · Nv ${c.level}</strong>${energyBar(c)}
    <small>${charStatus(c)}</small>
    <small>${esc(role)} · ${nf1.format(c.rate)} de trabalho/h · gasta ${nf1.format(c.energy_use)} de energia/h, recupera ${nf1.format(c.energy_rest)}/h</small>
    <small>${c.class_id === 'agricultor' ? 'Dono da fazenda · sem salário' : `Salário ${formatGold(c.salary)}/dia`}${next ? ` · próximo nível em ${nf1.format(next - c.work_hours)} h de trabalho` : ' · nível máximo'}</small>
    <span class="btns">${move}</span></div></div>`;
}

function operatorsTab(s: FarmState): string {
  const field = s.characters.filter((c) => c.slot === 'field');
  const bench = s.characters.filter((c) => c.slot === 'bench');
  const salaries = s.characters.reduce((a, c) => a + c.salary, 0);
  const debt = s.characters.reduce((a, c) => a + c.debt, 0);
  const empty = (n: number, text: string) => Array.from({ length: Math.max(0, n) }, () => `<div class="slot empty-slot">${text}</div>`).join('');
  const hireable = CLASSES.filter((c) => !s.characters.some((x) => x.class_id === c.id));
  const hires = hireable.map((c) => {
    const cost = hireCost(c.id);
    const why = c.unlock_level > s.level ? `Libera no nível ${c.unlock_level}` : s.gold < cost ? `Falta ${formatGold(cost - s.gold)} de ouro` : '';
    const sal = LEVELS[s.level - 1].reference_income_per_day * CHARS.salary.share_of_R * (1 + CHARS.salary.per_character_level);
    return `<li>${charSprite(c.id, 1)}<span><strong>${esc(c.name_pt)}</strong><small>${esc(toolCard(c.id).primary_role_pt)} · salário ≈ ${formatGold(sal)}/dia</small>${why ? `<small class="bad">${why}</small>` : ''}</span>
      <span class="btns"><button type="button" class="primary small" data-hire="${c.id}" ${why ? 'disabled' : ''}>Contratar · ${formatGold(cost)}</button></span></li>`;
  }).join('');
  return `<p class="status">Trabalho da equipe agora: <strong>${nf1.format(s.labor_per_hour)}/h</strong> (${nf1.format(s.labor_nominal)}/h com todos em campo e com energia).
      ${salaries ? `Salários: <strong>${formatGold(salaries)}/dia</strong>, cobrados à meia-noite (Brasília).` : ''}</p>
    ${debt > 0 ? `<ul class="problems"><li>Salário atrasado: ${formatGold(debt)}. Quem deve trabalha pela metade; com 3 dias sem pagar, para.${s.fx.auto_pay ? ' O Gerente paga sozinho quando entrar ouro.' : ''}</li></ul>
      <button type="button" class="primary" data-pay ${s.gold < debt ? 'disabled' : ''}>Pagar salários (${formatGold(debt)})</button>` : ''}
    <div class="slots"><span class="slot-title">Slots de Campo (${field.length}/${CHARS.field_slots})</span>
      ${field.map((c) => charCard(c, s)).join('')}${empty(CHARS.field_slots - field.length, 'Vago')}
      <span class="slot-title">Slots de Banco (${bench.length}/${CHARS.bench_slots})</span>
      ${bench.map((c) => charCard(c, s)).join('')}${empty(CHARS.bench_slots - bench.length, 'Descanso')}</div>
    <p class="hint">Trabalhando, cada um gasta ${nf1.format(CHARS.energy.use_per_work_hour)} de energia por hora e no banco recupera ${nf1.format(CHARS.energy.recover_per_rest_hour)}. Com 4 ou mais personagens, o rodízio é automático: quem chega a ${CHARS.energy.leave_field_at} sai do campo e entra quem tem ${CHARS.energy.enter_field_at} ou mais. Agricultor e Rancheira trabalham a 100% na lavoura e no pomar; os outros a ${Math.round(CHARS.role_efficiency.other * 100)}%.</p>
    ${hires ? `<h3>Contratar</h3><ul class="items">${hires}</ul>` : ''}`;
}

/** chips para escolher o personagem nas guias Equipamentos e Habilidades */
function charChips(s: FarmState, sel: string): string {
  return `<div class="chips" role="tablist">${s.characters.map((c) => `<button type="button" role="tab" data-pick-char="${c.class_id}" aria-selected="${c.class_id === sel}">${charSprite(c.class_id, 0.5)}${esc(className(c.class_id))}</button>`).join('')}</div>`;
}

function equipmentTab(s: FarmState, sel: string): string {
  const c = s.characters.find((x) => x.class_id === sel) ?? s.characters[0];
  const tc = toolCard(c.class_id);
  const m = matDef(c.material);
  const low = c.durability < 30;
  const repair = Math.round(m.repair_cost_gold * (1 + s.fx.tool_cost) * 100) / 100;
  const snack = c.snack_id ? SNACKS.find((x) => x.id === c.snack_id) : null;
  const owned = SNACKS.filter((x) => (s.inventory[x.id] ?? 0) > 0);
  return `${charChips(s, c.class_id)}
    <div class="char-card">${toolArt(c.class_id)}<div class="grow"><strong>${esc(tc.name_pt)} · nível ${toolLevel(m.id)} (×${nf1.format(m.work_capacity_multiplier)} de trabalho)</strong>
      <span class="energy dura ${low ? 'low' : ''}" title="Durabilidade ${nf1.format(c.durability)}"><span style="width:${Math.round(c.durability)}%"></span></span>
      <small>Durabilidade ${nf1.format(c.durability)} de 100 · perde 2,5 por hora de trabalho${low ? ' · <span class="bad">abaixo de 30: trabalha a 50%</span>' : ''}</small>
      <span class="btns"><button type="button" class="secondary" data-repair="${c.class_id}" ${c.durability >= 100 || s.gold < repair ? 'disabled' : ''}>Consertar · ${formatGold(repair)}</button>
</span>
      <small>${nextToolTier(s.level) ? `Melhora sozinha no nível ${nextToolTier(s.level)!.unlock_level} da fazenda.` : 'Ferramenta no nível máximo.'}</small></div></div>
    <div class="char-card">${snack ? sprite(snack.id, 1) : '<span class="px empty-box"></span>'}<div class="grow"><strong>Lanche</strong>
      <small>${snack ? `${esc(snack.name_pt)} × ${c.snack_qty} · +${snack.energy_restore} de energia, comido sozinho abaixo de ${snack.auto_trigger_below_energy_pct}%` : 'Vazio. Compre lanches na Barraca.'}</small>
      <span class="btns">${owned.map((x) => `<button type="button" class="secondary" data-equip="${x.id}">${esc(x.name_pt)} (${s.inventory[x.id]})</button>`).join('')}
      ${snack ? '<button type="button" class="secondary" data-unequip>Tirar</button>' : ''}</span></div></div>
`;
}

const petName = (id: string) => PETS.list.find((x) => x.id === id)?.name_pt ?? id;

/** o que o pet faz sempre (no nível atual) e o que ele traz no achado */
function petLines(id: string, lv: number): { passive: string; find: string } {
  const d = PETS.list.find((x) => x.id === id)! as unknown as { find_hours: number; find: Record<string, number>; night_event_warning_minutes: number } & Record<string, number>;
  const f = petFactor(lv);
  const R = LEVELS[(store.state?.level ?? 1) - 1].reference_income_per_day;
  const gold = (share: number) => formatGold(Math.round(R * share * f * 100) / 100);
  if (id === 'cachorro') return {
    passive: `+${nf1.format(d.expedition_success_pts * f)} pontos nas expedições · ${pct(d.lost_cargo_recovery_chance * f)} de achar a carga perdida`,
    find: `Baú a cada ${d.find_hours} h: ${gold(d.find.gold_share_of_R ?? 0)} de ouro e ${pct((d.find.card_chance ?? 0) + (d.find.card_chance_per_level ?? 0) * (lv - 1))} de chance de carta`,
  };
  if (id === 'gato') return {
    passive: `+${Math.round(d.energy_recovery_pct * f)}% no descanso da equipe · +${Math.round(d.animal_production_pct * f)}% na produção animal`,
    find: `Soneca a cada ${d.find_hours} h: +${nf1.format((d.find.team_energy ?? 0) * f)} de energia para toda a equipe`,
  };
  return {
    passive: `+${nf1.format(d.sales_gold_pct * f)}% de ouro nas vendas · avisa do evento noturno ${d.night_event_warning_minutes} min antes`,
    find: `Moedas a cada ${d.find_hours} h: ${gold(d.find.gold_share_of_R ?? 0)} de ouro`,
  };
}

/** pega o achado do pet e conta o que veio */
async function takeFind(id: string): Promise<void> {
  try {
    const after = await collectPet(id);
    applyState(after);
    const f = after.pet_find;
    if (!f) return;
    const parts = [f.gold ? `+${formatGold(f.gold)} ouro` : '', f.energy ? `+${nf1.format(f.energy)} de energia na equipe` : '',
      f.card ? `carta ${f.card.card_id} ${RARITY_BY_ID[f.card.rarity]?.name_pt ?? ''}` : ''].filter(Boolean);
    toast(`${petName(id)} trouxe: ${parts.join(' · ') || 'nada desta vez'}`, 5);
  } catch (e) { toast(e instanceof Error ? e.message : 'Não deu certo.'); }
}

/** guia Pets: um card por pet (arte grande, nível, o que faz, achado e carinho) */
function petsTab(s: FarmState): string {
  const now = store.clock.farmNow();
  const cards = PETS.list.map((d) => {
    const mine = s.pets.find((x) => x.pet_id === d.id);
    if (!mine) {
      return `<div class="gcard locked"><div class="gcard-art">${petFace(d.id)}</div><strong>${esc(d.name_pt)}</strong>
        <small>Chega sozinho no nível ${d.unlock_level}</small><span class="lock-badge">🔒 Nv ${d.unlock_level}</span></div>`;
    }
    const lv = petLevel(mine.affinity), next = petNextIn(mine.affinity), cared = mine.last_care === s.game_day;
    const left = petFindLeft(d.id, mine.find_t, now), L = petLines(d.id, lv);
    const pips = Array.from({ length: 5 }, (_, i) => `<i class="${i < lv ? 'on' : ''}"></i>`).join('');
    return `<div class="gcard ${left === 0 ? 'ready' : ''}"><div class="gcard-art">${petFace(d.id)}${left === 0 ? '<span class="find-dot" title="Achado pronto">!</span>' : ''}</div>
      <strong>${esc(d.name_pt)}</strong><span class="pips" title="Nível ${lv} de 5">${pips}</span>
      <small>${esc(L.passive)}</small><small class="find">${esc(L.find)}</small>
      <small class="muted">${next ? `Próximo nível em ${next} carinho${next > 1 ? 's' : ''}` : 'Nível máximo'}</small>
      <div class="gcard-btns">
        <button type="button" class="primary small" data-pet-find="${d.id}" ${left === 0 ? '' : 'disabled'}>${left === 0 ? 'Pegar achado' : duration(left)}</button>
        <button type="button" class="secondary small" data-care="${d.id}" ${cared ? 'disabled' : ''}>${cared ? 'Carinho ✓' : 'Carinho'}</button>
      </div></div>`;
  }).join('');
  return `<div class="gcard-grid">${cards}</div>
    <p class="hint">Os pets chegam sozinhos e andam no pátio da Casa. Todos valem ao mesmo tempo. De tempos em tempos cada um traz um achado (um balão aparece em cima dele): clique no pet ou em "Pegar achado". O achado espera por você, mas o próximo só começa depois que você pegar. 1 carinho por dia em cada pet sobe o nível (efeito de 40% no nível 1 até 100% no 5).</p>`;
}

function bindTeam(el: HTMLElement, pick: (cls: string) => void): void {
  el.querySelectorAll<HTMLButtonElement>('[data-pick-char]').forEach((b) => b.addEventListener('click', () => pick(b.dataset.pickChar!)));
  el.querySelectorAll<HTMLButtonElement>('[data-slot]').forEach((b) => b.addEventListener('click', () => {
    b.disabled = true;
    void act(() => setSlot(b.dataset.slot!, b.dataset.to as 'field' | 'bench'), `${className(b.dataset.slot!)} ${b.dataset.to === 'field' ? 'no campo' : 'no banco'}`);
  }));
  el.querySelectorAll<HTMLButtonElement>('[data-hire]').forEach((b) => b.addEventListener('click', () => {
    b.disabled = true;
    void act(() => hire(b.dataset.hire!), `${className(b.dataset.hire!)} contratado!`);
  }));
  el.querySelector<HTMLButtonElement>('[data-pay]')?.addEventListener('click', (e) => { (e.currentTarget as HTMLButtonElement).disabled = true; void act(() => paySalaries(), 'Salários pagos.'); });
  el.querySelectorAll<HTMLButtonElement>('[data-repair]').forEach((b) => b.addEventListener('click', () => { b.disabled = true; void act(() => repairTool(b.dataset.repair!), 'Ferramenta consertada.'); }));
  el.querySelector('[data-forge]')?.addEventListener('click', () => openZone('oficina_ferreiro'));

  el.querySelectorAll<HTMLButtonElement>('[data-equip]').forEach((b) => b.addEventListener('click', () => {
    const cls = el.querySelector<HTMLButtonElement>('[data-pick-char][aria-selected="true"]')?.dataset.pickChar ?? 'agricultor';
    b.disabled = true;
    void act(() => equipSnack(cls, b.dataset.equip!), 'Lanche no espaço.');
  }));
  el.querySelector('[data-unequip]')?.addEventListener('click', () => {
    const cls = el.querySelector<HTMLButtonElement>('[data-pick-char][aria-selected="true"]')?.dataset.pickChar ?? 'agricultor';
    void act(() => equipSnack(cls, null), 'Lanche de volta ao inventário.');
  });
  el.querySelectorAll<HTMLButtonElement>('[data-care]').forEach((b) => b.addEventListener('click', () => { b.disabled = true; void act(() => carePet(b.dataset.care!), `${petName(b.dataset.care!)}: carinho feito!`); }));
  el.querySelectorAll<HTMLButtonElement>('[data-pet-find]').forEach((b) => b.addEventListener('click', () => { b.disabled = true; void takeFind(b.dataset.petFind!); }));
}

function itemsList(s: FarmState): string {
  const rows: string[] = [];
  for (const x of SNACKS) if (s.inventory[x.id]) rows.push(`<li>${sprite(x.id, 1)}<span><strong>${esc(x.name_pt)}</strong><small>${s.inventory[x.id]} · +${x.energy_restore} de energia · ponha no espaço de lanche em Equipamentos</small></span></li>`);
  for (const r of rareSeeds(s.inventory)) {
    const t = RARITY_BY_ID[r.rarity];
    rows.push(`<li>${sprite(iconSprite(store.manifest, r.crop), 1)}<span><strong style="color:${t.color_hex}">Semente ${esc(t.name_pt)} de ${esc(CROPS[r.crop].name_pt)}</strong><small>${r.qty} · colheita ×${nf1.format(t.multiplier)} por 1 plantio · plante pelo ${CROPS[r.crop].kind === 'orchard' ? 'pomar' : 'canteiro'}</small></span></li>`);
  }
  return rows.length ? `<ul class="items">${rows.join('')}</ul>` : '<p class="empty">Nenhum item ainda.</p>';
}

/** contexto que a Garagem usa para abrir painéis e mostrar avisos */
function garageCtx() {
  return { show, act, toast, sprite, esc, close, itemIcon };
}

function openZone(id: string, tab = 'silo'): void {
  if (id === 'casa_principal') {
    let active = tab;
    let picked = 'agricultor';
    show('Casa', () => {
      const s = store.state!;
      if (!s.characters.some((c) => c.class_id === picked)) picked = s.characters[0]?.class_id ?? 'agricultor';
      const tabs = [['silo', 'Silo'], ['operadores', 'Operadores'], ['equipamentos', 'Equipamentos'], ['pets', 'Pets']]
        .map(([k, n]) => `<button type="button" role="tab" data-tab="${k}" aria-selected="${active === k}">${n}</button>`).join('');
      let body = '';
      if (active === 'silo') body = siloItems(false) + `<h3>Itens</h3>${itemsList(s)}<p class="hint">Para vender, use a Barraca (na hora, sem risco) ou a Garagem (expedição, preço maior com risco).</p>`;
      if (active === 'operadores') body = operatorsTab(s);
      if (active === 'equipamentos') body = equipmentTab(s, picked);
      if (active === 'pets') body = petsTab(s);
      return `<div class="tabs wrap" role="tablist">${tabs}</div>${body}`;
    }, (el) => {
      el.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach((b) => b.addEventListener('click', () => { active = b.dataset.tab!; current?.(); }));
      bindTeam(el, (cls) => { picked = cls; current?.(); });
    });
  }
  if (id === 'barraca_comerciante') {
    show('Barraca', () => {
      const s = store.state!;
      const com = s.fx.auto_sell;
      const snacks = SNACKS.map((x) => {
        const price = s.snack_prices[x.id] ?? 0;
        return `<li>${sprite(x.id, 1)}<span><strong>${esc(x.name_pt)}</strong><small>+${x.energy_restore} de energia · ${formatGold(price)} cada · você tem ${s.inventory[x.id] ?? 0}</small></span>
          <span class="btns"><button type="button" class="secondary" data-snack-buy="${x.id}" data-qty="1" ${s.gold < price ? 'disabled' : ''}>Comprar 1</button>
          <button type="button" class="primary small" data-snack-buy="${x.id}" data-qty="5" ${s.gold < price * 5 ? 'disabled' : ''}>Comprar 5 · ${formatGold(price * 5)}</button></span></li>`;
      }).join('');
      return `<p>Venda na hora, sem risco, a <strong>${pct(stallRatio())}</strong> do preço da Feira${s.fx.sales_gold ? ` e +${pct(s.fx.sales_gold)} de ouro` : ''}.</p>${siloItems(true)}
        <p class="hint">${com ? 'O Comerciante está em campo: os itens com "Venda automática" são vendidos sozinhos.' : 'Venda automática e preço melhor só com o Comerciante num Slot de Campo.'}</p>
        <h3>Lanches</h3><ul class="items">${snacks}</ul>
        <p class="hint">O personagem come sozinho quando a energia cai abaixo de 15%. Ponha até 5 no espaço de lanche (Casa → Equipamentos).</p>`;
    }, bindSell);
  }
  if (id === 'oficina_ferreiro') {
    let picked = 'agricultor';
    show('Forja', () => {
      const s = store.state!;
      const c = s.characters.find((x) => x.class_id === picked) ?? s.characters[0];
      const tc = toolCard(c.class_id);
      const i = TOOL_MATERIALS.findIndex((m) => m.id === c.material);
      const cur = TOOL_MATERIALS[i], next = TOOL_MATERIALS[i + 1] as (typeof TOOL_MATERIALS)[number] | undefined;
      const row = TOOL_MATERIALS.map((m, k) => `<span class="tier ${k <= i ? 'got' : ''} ${m.id === cur.id ? 'current' : ''} ${m.unlock_level > s.level ? 'locked' : ''}" title="Nível ${k + 1}: ×${nf1.format(m.work_capacity_multiplier)} de trabalho · fazenda nível ${m.unlock_level}"><b>${k + 1}</b><small>×${nf1.format(m.work_capacity_multiplier)}</small></span>`).join('');
      const repair = Math.round(cur.repair_cost_gold * (1 + s.fx.tool_cost) * 100) / 100;
      const low = c.durability < 30;
      const n = s.characters.length, idx = s.characters.findIndex((x) => x.class_id === c.class_id);
      return `<div class="forge">
          <button type="button" class="big-arrow" data-forge-step="-1" aria-label="Ferramenta anterior" ${n < 2 ? 'disabled' : ''}>◀</button>
          <div class="forge-card">${toolArt(c.class_id, 0.6)}
            <strong>${esc(tc.name_pt)}</strong><span class="lv-tag">Nv ${i + 1}</span>
            <small>${esc(className(c.class_id))} · ${idx + 1}/${n}</small>
            <span class="energy dura ${low ? 'low' : ''}" title="Durabilidade ${nf1.format(c.durability)}"><span style="width:${Math.round(c.durability)}%"></span></span>
            <small class="${low ? 'bad' : 'muted'}">Durabilidade ${nf1.format(c.durability)}/100</small>
          </div>
          <button type="button" class="big-arrow" data-forge-step="1" aria-label="Próxima ferramenta" ${n < 2 ? 'disabled' : ''}>▶</button>
        </div>
        <button type="button" class="primary big-action" data-repair="${c.class_id}" ${c.durability >= 100 || s.gold < repair ? 'disabled' : ''}>${c.durability >= 100 ? 'Inteira' : `Consertar · ${formatGold(repair)}`}</button>
        <div class="tier-row" aria-label="Níveis da ferramenta">${row}</div>
        <p class="hint">${next ? `A ${esc(tc.name_pt)} sobe sozinha para o nível ${i + 2} (×${nf1.format(next.work_capacity_multiplier)} de trabalho) quando a fazenda chegar ao nível ${next.unlock_level}, de graça.` : `${esc(tc.name_pt)} no nível máximo.`}</p>
        <p class="hint">A ferramenta perde 2,5 de durabilidade por hora de trabalho; abaixo de 30 trabalha a 50% até o conserto. ${esc(className(c.class_id))}: ${nf1.format(c.rate)} de trabalho por hora.</p>
        ${s.fishing ? `<h3>Lago</h3>${rodCard(s)}` : ''}`;
    }, (el) => {
      el.querySelectorAll<HTMLButtonElement>('[data-forge-step]').forEach((b) => b.addEventListener('click', () => {
        const list = store.state!.characters;
        const k = list.findIndex((x) => x.class_id === picked);
        picked = list[(Math.max(0, k) + Number(b.dataset.forgeStep) + list.length) % list.length].class_id;
        current?.();
      }));
      el.querySelectorAll<HTMLButtonElement>('[data-repair]').forEach((b) => b.addEventListener('click', () => { b.disabled = true; void act(() => repairTool(b.dataset.repair!), 'Ferramenta consertada.'); }));
      bindRod(el);
    });
  }
  if (id === 'garagem_expedicao') openGarage(garageCtx());
}

// usado nos testes
export const _internal = { plotStatus, FARM, MAX_LEVEL };
