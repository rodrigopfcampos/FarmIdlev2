// Interface por cima do mapa: monta a tela, barra do topo (nível, XP, ouro, equipe, ícones) e encaminha
// os cliques do mapa para cada tela (lavoura, pomar, animais, Casa, Barraca, Forja, Garagem).
import { bus } from '../core/bus';
import { mapView } from '../core/mapView';
import { ANIMALS, CLASSES, CROP_LIST, FARM, MAX_LEVEL, PETS, TOOL_MATERIALS } from '../data';
import { petFindLeft, tendCount, xpProgress } from '../farm/rules';
import { applyState, store } from '../farm/store';
import { deviceTz } from '../farm/weather';
import { carePet, clientPing, type FarmState, setTimezone, warningSeen } from '../net/farmApi';
import { supabase } from '../net/supabase';
import { onPastureClick } from './animals-ui';
import { type CardsCtx, hudCards, maybeOpenPack, openCards, openMissions, renderHand } from './cards-ui';
import { openForge } from './forge-ui';
import { formatGold } from './format';
import { openGarage } from './garage';
import { openCasa, openStall } from './house-ui';
import { hudIcon } from './hud-icons';
import { onOrchardClick } from './orchard-ui';
import { act, charSprite, close, esc, initPanel, itemIcon, nf1, pct, rerender, show, sprite, toast } from './panel';
import { hudPassives, openPassives } from './passives-ui';
import { petName, takeFind } from './pets-ui';
import { onPlotClick, openLot, tend } from './plots-ui';
import { bindVisitHud, hudSocial, openHelp, openSocial, type SocialCtx, visitHud } from './social-ui';
import { hudVillage, openVillage } from './village-ui';
import { weatherBanner, weatherChip, weatherPanel } from './weather-ui';

let root: HTMLElement;
let hud: HTMLElement;
let panel: HTMLElement;

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
  initPanel(root, panel);
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
  rerender();
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

function levelUp(from: number, to: number): void {
  const news = CROP_LIST.filter((c) => c.unlock_level > from && c.unlock_level <= to).map((c) => c.name_pt);
  const tools = TOOL_MATERIALS.filter((m) => m.unlock_level > from && m.unlock_level <= to).map((m) => `ferramentas de ${m.name_pt}`);
  const hires = CLASSES.filter((c) => c.unlock_level > from && c.unlock_level <= to).map((c) => `contratar ${c.name_pt}`);
  const pets = PETS.list.filter((p) => p.unlock_level > from && p.unlock_level <= to).map((p) => `${p.name_pt} chegou à fazenda`);
  const animals = ANIMALS.filter((a) => a.unlock_level > from && a.unlock_level <= to).map((a) => a.name_pt);
  const extra = [...news, ...animals, ...tools, ...hires, ...pets];
  toast(`Nível ${to}!${extra.length ? ` Liberado: ${extra.join(', ')}.` : ''}`, FARM.ui.level_up_toast_seconds);
}

/** contexto que a Garagem usa para abrir painéis e mostrar avisos */
function garageCtx() {
  return { show, act, toast, sprite, esc, close, itemIcon };
}

/** clique numa zona do mapa (prédio) abre a tela dela */
export function openZone(id: string, tab = 'silo'): void {
  if (id === 'casa_principal') openCasa(tab);
  if (id === 'barraca_comerciante') openStall();
  if (id === 'oficina_ferreiro') openForge();
  if (id === 'garagem_expedicao') openGarage(garageCtx());
}
