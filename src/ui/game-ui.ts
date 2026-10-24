// Interface por cima do mapa: barra do topo (nível, XP, ouro, Escrituras, trabalho do Agricultor e o botão
// "Colher e plantar") e os painéis das zonas, dos canteiros, dos lotes à venda e do pomar.
// Clique em canteiro maduro colhe e replanta na hora; em canteiro com cultivo escolhido, planta (grátis, jogo aberto).
import { bus } from '../core/bus';
import { CHARS, CLASSES, CLASS_TOOLS, CROPS, CROP_LIST, FARM, LEVELS, STALL_RATIO, LOT_BY_ID, LOT_TYPE_NAMES, MAX_LEVEL, PETS, RARITY_BY_ID, SKILL_TREE, SNACKS, TOOL_MATERIALS, VEHICLES, WORK, type Crop } from '../data';
import { iconSprite } from '../farm/art';
import {
  classDef, hireCost, hoursToNext, lotOffer, orchardFruits, petFactor, petLevel, petNextIn, petSwapWaitDays, plotCrops, plotLook, rareSeeds,
  skillNodeState, skillPoints, tendCount, treeLook, xpProgress,
} from '../farm/rules';
import { applyState, store } from '../farm/store';
import {
  adoptPet, buyLot, buySnack, carePet, chopTree, equipSnack, hire, linkPet, paySalaries, plantRareSeed, plantRareTree, plantTree, repairTool,
  sellAtStall, setActivePet, setAutoSell, setCrop, setSlot, skillAdd, skillChoose, skillReset, tendFarm, upgradeTool,
  type CharacterState, type FarmState, type PlotState,
} from '../net/farmApi';
import { supabase } from '../net/supabase';
import { duration, formatGold } from './format';

const nf1 = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

function sprite(key: string | null, scale = 2, cls = ''): string {
  const m = key ? store.manifest[key] : null;
  if (!m) return '';
  const [w, h] = m.frame_size ?? m.size;
  return `<span class="px ${cls}" style="width:${w * scale}px;height:${h * scale}px;background-image:url(assets/${m.file});background-size:${m.size[0] * scale}px ${m.size[1] * scale}px"></span>`;
}

// Até as artes chegarem, os outros personagens usam o Agricultor com outra cor (só visual)
const CLASS_HUE: Record<string, number> = { agricultor: 0, rancheira: 150, ferreiro: 200, comerciante: 280, gerente: 40, botanica: 100 };
function charSprite(cls: string, scale = 2): string {
  const key = store.manifest[`char_${cls}_idle`] ? `char_${cls}_idle` : 'char_agricultor_idle';
  const html = sprite(key, scale);
  return key === 'char_agricultor_idle' && CLASS_HUE[cls] ? html.replace('style="', `style="filter:hue-rotate(${CLASS_HUE[cls]}deg);`) : html;
}
const className = (id: string) => classDef(id)?.name_pt ?? id;
const toolCard = (cls: string) => CLASS_TOOLS.find((t) => t.class_id === cls)!;
const matDef = (id: string) => TOOL_MATERIALS.find((m) => m.id === id) ?? TOOL_MATERIALS[0];
/** preço da Barraca agora (Comerciante em campo e habilidades sobem) e o bônus de ouro em vendas */
const stallRatio = () => store.state?.fx?.stall_ratio ?? STALL_RATIO;
const salesMult = () => 1 + (store.state?.fx?.sales_gold ?? 0);
const pct = (x: number) => `${nf1.format(x * 100)}%`;
const PET_TEXT: Record<string, string> = {
  cachorro: 'Expedições: +4 pontos de sucesso e 10% de chance de recuperar a carga perdida (fase 5)',
  gato: '+40% na recuperação de energia da equipe; +10% na produção animal (fase 4)',
  papagaio: '+4% de ouro nas vendas; avisa do evento noturno 30 min antes (fase 6)',
};
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
  ticker = window.setInterval(refreshTendButton, 1000); // maduros mudam com o tempo, sem esperar o servidor
  root.innerHTML = `<div class="hud" id="hud"></div><div class="modal" id="modal" hidden></div><div class="toast" id="toast" role="status" aria-live="polite"></div>`;
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
  bus.on('farm:state', onState);
  bus.on('farm:error', (msg: string) => toast(msg));
  bus.on('art:ready', () => { if (store.state) onState(store.state); });
  bus.on('ui:zone', (id: string) => openZone(id));
  bus.on('ui:plot', (id: string) => onPlotClick(id));
  bus.on('ui:locked', (id: string) => openLot(id));
  bus.on('ui:orchard', (id: string) => onOrchardClick(id));
  bus.on('ui:pet', () => {
    const s = store.state;
    const p = s?.pets.find((x) => x.active);
    if (s && p && p.last_care !== s.game_day) void act(() => carePet(p.pet_id), `${PET_EMOJI[p.pet_id]} Carinho feito! +${PETS.care_energy} de energia para ${className(p.linked_class ?? 'agricultor')}.`);
    else openZone('casa_principal', 'pets');
  });
  bus.on('ui:pasture', (id: string) => openInfo(`${LOT_TYPE_NAMES[LOT_BY_ID[id].type]} ${id}`, 'Este pasto é seu. Os animais chegam na fase 4.'));
}

function onState(s: FarmState): void {
  const deeds = s.inventory.deed ?? 0;
  const pct = Math.round(xpProgress(s.xp, s.xp_to_next) * 100);
  const xpText = s.xp_to_next ? `${formatGold(s.xp)} de ${formatGold(s.xp_to_next)} XP` : 'nível máximo';
  hud.innerHTML = `
    <span class="nick">${esc(s.nickname)}</span>
    <span class="level" title="${xpText}">Nv ${s.level}<span class="xpbar" role="progressbar" aria-label="XP do nível" aria-valuenow="${pct}" aria-valuemin="0" aria-valuemax="100"><span style="width:${pct}%"></span></span></span>
    <span class="gold" title="Ouro">${sprite('ui_coin', 1, 'coin-img')}${formatGold(s.gold)}</span>
    ${deeds ? `<span class="deeds" title="Escrituras">${sprite('item_deed', 0.5)}${deeds}</span>` : ''}
    ${laborMeter(s)}
    <button type="button" class="hud-btn tend" data-tend hidden></button>
    <button type="button" class="hud-btn" data-open="casa_principal">Silo</button>
    <button type="button" class="logout">Sair</button>`;
  hud.querySelector('.logout')!.addEventListener('click', () => supabase!.auth.signOut());
  hud.querySelector('[data-open]')!.addEventListener('click', () => openZone('casa_principal', 'silo'));
  hud.querySelector('[data-tend]')!.addEventListener('click', () => void tend(null));
  hud.querySelector('[data-team]')?.addEventListener('click', () => openZone('casa_principal', 'operadores'));
  refreshTendButton();
  if (lastLevel && s.level > lastLevel) levelUp(lastLevel, s.level);
  lastLevel = s.level;
  current?.();
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
  b.textContent = `Colher e plantar (${n})`;
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
    bus.emit('fx:harvest', fx);
    const got = Object.entries(after.silo).map(([k, q]) => [k, q - (before.silo[k] ?? 0)] as const).filter(([, d]) => d > 0);
    const planted = after.plots.filter((p) => inTarget(p.plot_id) && p.state === 'growing' && p.planted_at !== null && p.planted_at >= after.farm_time - 1).length;
    const parts: string[] = [];
    if (got.length) parts.push(`Colhido: ${got.map(([k, d]) => `${d} ${CROPS[k].name_pt}`).join(', ')}`);
    if (planted) parts.push(`${planted} plantado${planted > 1 ? 's' : ''}`);
    const stalled = after.plots.some((p) => inTarget(p.plot_id) && p.state === 'empty' && p.stalled_reason === 'sem_ouro');
    if (stalled) parts.push('falta ouro para algumas sementes');
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
  const pets = PETS.unlock_level > from && PETS.unlock_level <= to ? ['adotar um pet'] : [];
  const extra = [...news, ...tools, ...hires, ...pets];
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
  const render = () => {
    const scroll = panel.querySelector('.body')?.scrollTop ?? 0;
    panel.innerHTML = `<div class="panel game-panel" role="dialog" aria-label="${esc(title)}">
      <header><h2>${esc(title)}</h2><button type="button" class="close" aria-label="Fechar">×</button></header>
      <div class="body">${body()}</div></div>`;
    panel.querySelector('.close')!.addEventListener('click', close);
    panel.querySelector('.body')!.scrollTop = scroll;
    bind?.(panel);
  };
  current = render;
  panel.hidden = false;
  panel.querySelector('.body')?.scrollTo(0, 0);
  render();
}

function close(): void { panel.hidden = true; current = null; }

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
  const lot = id.split('-')[0];
  show(`Canteiro ${id}`, () => {
    const s = store.state;
    const p = s?.plots.find((x) => x.plot_id === id);
    if (!s || !p) return '<p>Carregando…</p>';
    const { open, next } = plotCrops(s.level);
    const crops = [...[...open].reverse().map((c) => cropButton(c, p.crop_id === c.id, false, 'data-crop')), ...next.map((c) => cropButton(c, false, true, ''))].join('');
    const ready = p.state === 'growing' && p.ready_at !== null && p.ready_at <= store.clock.farmNow();
    const seeds = rareSeeds(s.inventory).filter((r) => CROPS[r.crop].kind !== 'orchard');
    const canRare = !cleanupLeft(lot) && (p.state === 'empty' || (p.ready_at !== null && p.ready_at <= store.clock.farmNow()));
    const rare = seeds.length ? `<h3>Sementes raras</h3><div class="crops">${seeds.map((r) => {
      const t = RARITY_BY_ID[r.rarity];
      return `<button type="button" class="crop" data-rare="${r.crop}:${r.rarity}" ${canRare ? '' : 'disabled'}>${sprite(iconSprite(store.manifest, r.crop), 1)}
        <span><strong style="color:${t.color_hex}">${esc(CROPS[r.crop].name_pt)} ${esc(t.name_pt)} × ${r.qty}</strong><small>Colheita e XP ×${nf1.format(t.multiplier)} neste plantio, sem pagar semente${canRare ? '' : ' · colha ou espere o canteiro ficar livre'}</small></span></button>`;
    }).join('')}</div>` : '';
    return `<p class="status">${plotStatus(p)}</p>
      <div class="row top">
        ${ready ? '<button type="button" class="primary small" data-harvest>Colher agora</button>' : ''}
        <button type="button" class="secondary" data-all ${p.crop_id ? '' : 'disabled'}>${p.crop_id ? `${esc(CROPS[p.crop_id].name_pt)} no lote ${esc(lot)} inteiro` : `Escolha um cultivo para usar no lote ${esc(lot)}`}</button>
        ${p.crop_id ? '<button type="button" class="secondary" data-stop>Parar este canteiro</button>' : ''}
      </div>
      ${rare}<div class="crops">${crops}</div>
      <p class="hint">Com o jogo aberto, plantar e colher com clique é grátis. Quando você sai, a equipe em campo faz sozinha: ${nf1.format(WORK.plant)} de trabalho para plantar e ${nf1.format(WORK.harvest)} para colher (agora ${nf1.format(s.labor_per_hour)} por hora, enquanto tiverem energia). Cultivos longos rendem melhor enquanto você está fora.</p>`;
  }, (el) => {
    el.querySelectorAll<HTMLButtonElement>('[data-crop]').forEach((b) => b.addEventListener('click', () => {
      const chosen = b.dataset.crop!;
      const p = store.state?.plots.find((x) => x.plot_id === id);
      const now = p?.state === 'empty' && !cleanupLeft(lot);
      void act(() => setCrop(id, chosen), now ? `${CROPS[chosen].name_pt} plantada no canteiro ${id}` : `${CROPS[chosen].name_pt} no próximo plantio do canteiro ${id}`).then(close);
    }));
    el.querySelector('[data-harvest]')?.addEventListener('click', () => void tend(id));
    el.querySelectorAll<HTMLButtonElement>('[data-rare]').forEach((b) => b.addEventListener('click', () => {
      const [crop, rarity] = b.dataset.rare!.split(':');
      b.disabled = true;
      void act(() => plantRareSeed(id, crop, rarity), `${CROPS[crop].name_pt} ${RARITY_BY_ID[rarity].name_pt} plantada no canteiro ${id}`).then(close);
    }));
    el.querySelector('[data-all]')?.addEventListener('click', () => {
      const chosen = store.state?.plots.find((x) => x.plot_id === id)?.crop_id;
      if (chosen) void act(() => setCrop(lot, chosen), `${CROPS[chosen].name_pt} em todo o lote ${lot}`);
    });
    el.querySelector('[data-stop]')?.addEventListener('click', () => void act(() => setCrop(id, null), `Canteiro ${id} parado`));
  });
}

// ---------- lote à venda ----------
const PROBLEM_TEXT: Record<string, (o: NonNullable<ReturnType<typeof lotOffer>>) => string> = {
  vizinho: () => 'Precisa dividir um lado com um lote seu (Galinheiro e Celeiro podem ser comprados de longe).',
  nivel: (o) => `Precisa do nível ${o.needLevel}.`,
  escritura: () => 'Precisa de 1 Escritura (missões semanais e expedições longas; por enquanto, só pelo painel do admin).',
  ouro: (o) => `Falta ${formatGold(o.cost - (store.state?.gold ?? 0))} de ouro.`,
  fim: () => 'Você já comprou todos os lotes.',
};

function openLot(id: string): void {
  const def = LOT_BY_ID[id];
  show(`${LOT_TYPE_NAMES[def.type]} ${id}`, () => {
    const s = store.state!;
    const owned = new Set(s.lots.map((l) => l.lot_id));
    const smith = s.characters.some((c) => c.class_id === 'ferreiro');
    const o = lotOffer(id, owned, s.level, s.inventory.deed ?? 0, s.gold, smith, s.fx.cleanup);
    if (!o) return '<p>Este lote já é seu.</p>';
    if (o.problems.includes('fim')) return `<p>${PROBLEM_TEXT.fim(o)}</p>`;
    const what = def.type === 'lavoura' ? '8 canteiros' : def.type === 'pomar' ? '4 vagas de árvore' : 'pasto para animais (fase 4)';
    return `<dl class="facts">
        <dt>Compra</dt><dd>${o.n}ª de 29</dd>
        <dt>O que vem</dt><dd>${what}</dd>
        <dt>Custo</dt><dd>${sprite('ui_coin', 1, 'coin-img')} ${formatGold(o.cost)} ouro <small>(${o.daysOfIncome < 1 ? 'menos de 1 dia' : `≈ ${nf1.format(o.daysOfIncome)} dias`} de renda no seu nível)</small></dd>
        <dt>Nível</dt><dd>${o.needLevel}</dd>
        ${o.needsDeed ? `<dt>Escritura</dt><dd>${sprite('item_deed', 0.5)} 1 (você tem ${s.inventory.deed ?? 0})</dd>` : ''}
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
    const slots = s.trees.filter((t) => t.lot_id === lot).map((t) => `<li><span class="slot-n">Vaga ${t.slot}</span><span>${treeStatus(lot, t.slot)}</span>
      <span class="btns"><button type="button" class="${picking === t.slot ? 'primary small' : 'secondary'}" data-pick="${t.slot}">${t.fruit_id ? 'Trocar' : 'Plantar'}</button>
      ${t.fruit_id ? `<button type="button" class="secondary" data-chop="${t.slot}">Derrubar (grátis)</button>` : ''}</span></li>`).join('');
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
    return `${ripe ? '<div class="row top"><button type="button" class="primary small" data-harvest>Colher as frutas</button></div>' : ''}<ul class="items trees">${slots}</ul>${picker}
      <p class="hint">Com o jogo aberto, colher com clique é grátis; fora do jogo a equipe colhe (${nf1.format(WORK.harvest)} de trabalho por árvore; a Rancheira trabalha a 100% no pomar). Árvores não precisam de semente.</p>`;
  }, (el) => {
    el.querySelector('[data-harvest]')?.addEventListener('click', () => void tend(lot));
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

// ---------- zonas ----------
function siloItems(withSell: boolean): string {
  const s = store.state!;
  const items = Object.entries(s.silo).filter(([, q]) => q > 0);
  if (!items.length) return '<p class="empty">O Silo está vazio. As colheitas chegam aqui sozinhas.</p>';
  return `<ul class="items">${items.map(([id, q]) => {
    const c = CROPS[id];
    const unit = c.fair_price_per_unit * stallRatio() * salesMult();
    const auto = s.auto_sell.includes(id);
    return `<li>${sprite(iconSprite(store.manifest, id), 1)}<span><strong>${esc(c.name_pt)}</strong><small>${q} no Silo · Barraca ${nf1.format(unit)} cada</small></span>
      ${withSell ? `<span class="btns"><button type="button" class="secondary" data-sell="${id}" data-qty="1">Vender 1</button><button type="button" class="primary small" data-sell="${id}" data-qty="${q}">Vender tudo (${formatGold(q * unit)})</button>
      <label class="check"><input type="checkbox" data-auto="${id}" ${auto ? 'checked' : ''}> Venda automática</label></span>` : ''}</li>`;
  }).join('')}</ul>`;
}

function bindSell(el: HTMLElement): void {
  el.querySelectorAll<HTMLButtonElement>('[data-sell]').forEach((b) => b.addEventListener('click', () => {
    b.disabled = true;
    const qty = Number(b.dataset.qty);
    void act(() => sellAtStall(b.dataset.sell!, qty), `Vendido: ${qty} ${CROPS[b.dataset.sell!].name_pt}`);
  }));
  el.querySelectorAll<HTMLInputElement>('[data-auto]').forEach((b) => b.addEventListener('change', () => {
    const id = b.dataset.auto!;
    void act(() => setAutoSell(id, b.checked), b.checked ? `${CROPS[id].name_pt}: o Comerciante vende sozinho` : `${CROPS[id].name_pt}: venda automática desligada`);
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
  return `<div class="char-card ${c.slot}">${charSprite(c.class_id, 2)}<div class="grow">
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
  const linked = s.pet?.linked === c.class_id ? `<p class="hint">${PET_EMOJI[s.pet.id]} Vinculado ao pet ativo: +${PETS.per_level_work_pct * s.pet.level}% de trabalho e −${PETS.per_level_energy_use_pct * s.pet.level}% de energia.</p>` : '';
  return `${charChips(s, c.class_id)}
    <div class="char-card">${sprite(`${tc.id}_${m.id}`, 2)}<div class="grow"><strong>${esc(tc.name_pt)} de ${esc(m.name_pt)}</strong>
      <span class="energy dura ${low ? 'low' : ''}" title="Durabilidade ${nf1.format(c.durability)}"><span style="width:${Math.round(c.durability)}%"></span></span>
      <small>Durabilidade ${nf1.format(c.durability)} de 100 · perde 2,5 por hora de trabalho${low ? ' · <span class="bad">abaixo de 30: trabalha a 50%</span>' : ''}</small>
      <span class="btns"><button type="button" class="secondary" data-repair="${c.class_id}" ${c.durability >= 100 || s.gold < repair ? 'disabled' : ''}>Consertar · ${formatGold(repair)}</button>
      <button type="button" class="secondary" data-forge>Melhorar na Forja</button></span></div></div>
    <div class="char-card">${snack ? sprite(snack.id, 1) : '<span class="px empty-box"></span>'}<div class="grow"><strong>Lanche</strong>
      <small>${snack ? `${esc(snack.name_pt)} × ${c.snack_qty} · +${snack.energy_restore} de energia, comido sozinho abaixo de ${snack.auto_trigger_below_energy_pct}%` : 'Vazio. Compre lanches na Barraca.'}</small>
      <span class="btns">${owned.map((x) => `<button type="button" class="secondary" data-equip="${x.id}">${esc(x.name_pt)} (${s.inventory[x.id]})</button>`).join('')}
      ${snack ? '<button type="button" class="secondary" data-unequip>Tirar</button>' : ''}</span></div></div>
    <div class="slot empty-slot">Vestimenta · chega nas expedições (fase 5)</div>
    <div class="slot empty-slot">Amuleto · chega nas expedições (fase 5)</div>${linked}`;
}

function skillsTab(s: FarmState, sel: string): string {
  const c = s.characters.find((x) => x.class_id === sel) ?? s.characters[0];
  const pts = skillPoints(c.level, c.skills);
  const week = (() => { const d = new Date(`${s.game_day}T12:00:00Z`); const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 4 - (d.getUTCDay() || 7))); const y = t.getUTCFullYear(); const w = Math.ceil(((t.getTime() - Date.UTC(y, 0, 1)) / 86_400_000 + 1) / 7); return `${y}-${String(w).padStart(2, '0')}`; })();
  const freeReset = c.reset_week !== week;
  const resetCost = LEVELS[s.level - 1].reference_income_per_day * CHARS.skills.extra_reset_cost_R_ratio;
  const branches = SKILL_TREE[c.class_id].map((br) => {
    const row = (part: 'a' | 'b' | 'm') => {
      const st = skillNodeState(c.class_id, br.id, part, c.skills);
      const can = pts.free > 0 && !st.full && !st.locked;
      return `<li class="${st.future ? 'future' : ''}"><span class="node-name">${part === 'm' ? 'Mestria' : part === 'a' ? 'Nó A' : 'Nó B'}</span>
        <span><strong>${esc(st.node.text_pt)}</strong>${part === 'm' ? '' : ' por ponto'}<small>${st.pts}/${st.max}${st.future ? ` · liga na fase ${st.future}` : ''}${st.locked ? ' · complete os nós A e B' : ''}</small></span>
        <span class="btns"><button type="button" class="secondary small-btn" data-skill="${br.id}.${part}" ${can ? '' : 'disabled'} aria-label="Pôr 1 ponto">+</button></span></li>`;
    };
    return `<h3>${esc(br.name_pt)}</h3><ul class="items skills">${row('a')}${row('b')}${row('m')}</ul>`;
  }).join('');
  const early = c.class_id === 'botanica' && skillNodeState('botanica', 'pesquisa', 'm', c.skills).full
    ? `<label>Cultivo liberado 3 níveis antes<select data-early><option value="">escolha…</option>${CROP_LIST.filter((x) => x.unlock_level > s.level && x.unlock_level <= s.level + 3)
      .map((x) => `<option value="${x.id}" ${c.skill_choice === x.id ? 'selected' : ''}>${esc(x.name_pt)} (nível ${x.unlock_level})</option>`).join('')}</select></label>` : '';
  return `${charChips(s, c.class_id)}
    <p class="status"><strong>${esc(className(c.class_id))} · Nv ${c.level}</strong> · pontos livres: <strong>${pts.free}</strong> de ${pts.total} (1 por nível).
      Os efeitos valem com o personagem em campo.</p>
    ${branches}${early}
    <div class="row"><button type="button" class="secondary" data-reset ${pts.spent ? '' : 'disabled'}>${freeReset ? 'Resetar (grátis esta semana)' : `Resetar · ${formatGold(resetCost)}`}</button></div>
    <p class="hint">Cada ramo tem 2 nós de ${CHARS.skills.node_max} pontos e a Mestria de ${CHARS.skills.mastery_points}. Com os ${CHARS.character_level.max - 1} pontos do nível máximo dá para completar 2 ramos: escolha bem.</p>`;
}

function petsTab(s: FarmState): string {
  if (s.level < PETS.unlock_level) return `<p class="empty">Os pets chegam no nível ${PETS.unlock_level}. O primeiro é grátis.</p>`;
  const wait = petSwapWaitDays(s.pet_swapped_at, new Date(s.server_now));
  const cost = LEVELS[s.level - 1].reference_income_per_day * PETS.extra_adoption_cost_R;
  const cards = PETS.list.map((p) => {
    const mine = s.pets.find((x) => x.pet_id === p.id);
    if (!mine) {
      const first = s.pets.length === 0;
      return `<li><span class="pet-face" aria-hidden="true">${PET_EMOJI[p.id]}</span><span><strong>${esc(p.name_pt)}</strong><small>${PET_TEXT[p.id]}</small></span>
        <span class="btns"><button type="button" class="primary small" data-adopt="${p.id}" ${!first && s.gold < cost ? 'disabled' : ''}>Adotar${first ? ' (grátis)' : ` · ${formatGold(cost)}`}</button></span></li>`;
    }
    const lv = petLevel(mine.affinity);
    const next = petNextIn(mine.affinity);
    const cared = mine.last_care === s.game_day;
    return `<li class="${mine.active ? 'active-pet' : ''}"><span class="pet-face" aria-hidden="true">${PET_EMOJI[p.id]}</span><span><strong>${esc(p.name_pt)} · Nv ${lv}${mine.active ? ' · ativo' : ''}</strong>
        <small>${PET_TEXT[p.id]} · efeito a ${Math.round(petFactor(lv) * 100)}%</small>
        <small>Afinidade ${mine.affinity}${next ? ` · próximo nível em ${next} carinho${next > 1 ? 's' : ''}` : ' · nível máximo'}</small></span>
      <span class="btns"><button type="button" class="primary small" data-care="${p.id}" ${cared ? 'disabled' : ''}>${cared ? 'Carinho feito hoje' : 'Carinho'}</button>
        ${mine.active ? '' : `<button type="button" class="secondary" data-activate="${p.id}" ${wait ? `disabled title="Espera de ${wait} dias"` : ''}>${wait ? `Ativar em ${wait} d` : 'Tornar ativo'}</button>`}</span></li>`;
  }).join('');
  const active = s.pets.find((x) => x.active);
  const link = active ? `<label>Personagem vinculado ao pet ativo<select data-link>${s.characters.map((c) => `<option value="${c.class_id}" ${active.linked_class === c.class_id ? 'selected' : ''}>${esc(className(c.class_id))}</option>`).join('')}</select></label>
    <p class="hint">O vinculado ganha +${PETS.per_level_work_pct}% de trabalho e −${PETS.per_level_energy_use_pct}% de energia por nível do pet, e +${PETS.care_energy} de energia a cada carinho.</p>` : '';
  return `<ul class="items">${cards}</ul>${link}
    <p class="hint">1 carinho por dia em cada pet (vira à meia-noite de Brasília). Faltar um dia não tira nada. Só o pet ativo dá efeito; trocar o ativo tem espera de ${PETS.swap_wait_days} dias.</p>`;
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
  el.querySelectorAll<HTMLButtonElement>('[data-skill]').forEach((b) => b.addEventListener('click', () => {
    const cls = el.querySelector<HTMLButtonElement>('[data-pick-char][aria-selected="true"]')?.dataset.pickChar ?? 'agricultor';
    b.disabled = true;
    void act(() => skillAdd(cls, b.dataset.skill!));
  }));
  el.querySelector<HTMLButtonElement>('[data-reset]')?.addEventListener('click', (e) => {
    const cls = el.querySelector<HTMLButtonElement>('[data-pick-char][aria-selected="true"]')?.dataset.pickChar ?? 'agricultor';
    (e.currentTarget as HTMLButtonElement).disabled = true;
    void act(() => skillReset(cls), 'Pontos devolvidos.');
  });
  el.querySelector<HTMLSelectElement>('[data-early]')?.addEventListener('change', (e) => {
    const v = (e.currentTarget as HTMLSelectElement).value;
    if (v) void act(() => skillChoose('botanica', v), `${CROPS[v].name_pt} liberado antes.`);
  });
  el.querySelectorAll<HTMLButtonElement>('[data-equip]').forEach((b) => b.addEventListener('click', () => {
    const cls = el.querySelector<HTMLButtonElement>('[data-pick-char][aria-selected="true"]')?.dataset.pickChar ?? 'agricultor';
    b.disabled = true;
    void act(() => equipSnack(cls, b.dataset.equip!), 'Lanche no espaço.');
  }));
  el.querySelector('[data-unequip]')?.addEventListener('click', () => {
    const cls = el.querySelector<HTMLButtonElement>('[data-pick-char][aria-selected="true"]')?.dataset.pickChar ?? 'agricultor';
    void act(() => equipSnack(cls, null), 'Lanche de volta ao inventário.');
  });
  el.querySelectorAll<HTMLButtonElement>('[data-adopt]').forEach((b) => b.addEventListener('click', () => { b.disabled = true; void act(() => adoptPet(b.dataset.adopt!), 'Pet adotado!'); }));
  el.querySelectorAll<HTMLButtonElement>('[data-care]').forEach((b) => b.addEventListener('click', () => { b.disabled = true; void act(() => carePet(b.dataset.care!), `${PET_EMOJI[b.dataset.care!]} Carinho feito!`); }));
  el.querySelectorAll<HTMLButtonElement>('[data-activate]').forEach((b) => b.addEventListener('click', () => { b.disabled = true; void act(() => setActivePet(b.dataset.activate!), 'Pet ativo trocado.'); }));
  el.querySelector<HTMLSelectElement>('[data-link]')?.addEventListener('change', (e) => {
    const v = (e.currentTarget as HTMLSelectElement).value;
    void act(() => linkPet(v), `Pet vinculado a ${className(v)}.`);
  });
}

function itemsList(s: FarmState): string {
  const deeds = s.inventory.deed ?? 0;
  const rows: string[] = [];
  if (deeds) rows.push(`<li>${sprite('item_deed', 1)}<span><strong>Escritura</strong><small>${deeds} · cada compra de lote da 20ª em diante gasta 1</small></span></li>`);
  for (const x of SNACKS) if (s.inventory[x.id]) rows.push(`<li>${sprite(x.id, 1)}<span><strong>${esc(x.name_pt)}</strong><small>${s.inventory[x.id]} · +${x.energy_restore} de energia · ponha no espaço de lanche em Equipamentos</small></span></li>`);
  for (const r of rareSeeds(s.inventory)) {
    const t = RARITY_BY_ID[r.rarity];
    rows.push(`<li>${sprite(iconSprite(store.manifest, r.crop), 1)}<span><strong style="color:${t.color_hex}">Semente ${esc(t.name_pt)} de ${esc(CROPS[r.crop].name_pt)}</strong><small>${r.qty} · colheita ×${nf1.format(t.multiplier)} por 1 plantio · plante pelo ${CROPS[r.crop].kind === 'orchard' ? 'pomar' : 'canteiro'}</small></span></li>`);
  }
  return rows.length ? `<ul class="items">${rows.join('')}</ul>` : '<p class="empty">Nenhum item ainda.</p>';
}

function openZone(id: string, tab = 'silo'): void {
  if (id === 'casa_principal') {
    let active = tab;
    let picked = 'agricultor';
    show('Casa', () => {
      const s = store.state!;
      if (!s.characters.some((c) => c.class_id === picked)) picked = s.characters[0]?.class_id ?? 'agricultor';
      const tabs = [['silo', 'Silo'], ['operadores', 'Operadores'], ['equipamentos', 'Equipamentos'], ['habilidades', 'Habilidades'], ['pets', 'Pets']]
        .map(([k, n]) => `<button type="button" role="tab" data-tab="${k}" aria-selected="${active === k}">${n}</button>`).join('');
      let body = '';
      if (active === 'silo') body = siloItems(false) + `<h3>Itens</h3>${itemsList(s)}<p class="hint">Para vender, use a Barraca. Expedições chegam na fase 5.</p>`;
      if (active === 'operadores') body = operatorsTab(s);
      if (active === 'equipamentos') body = equipmentTab(s, picked);
      if (active === 'habilidades') body = skillsTab(s, picked);
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
      const row = TOOL_MATERIALS.map((m) => `<span class="tool ${m.id === cur.id ? 'current' : ''} ${m.unlock_level > s.level ? 'locked' : ''}" title="${esc(m.name_pt)} · nível ${m.unlock_level} · ×${nf1.format(m.work_capacity_multiplier)}">${sprite(`${tc.id}_${m.id}`, 2)}<small>${esc(m.name_pt)}</small></span>`).join('');
      let action = `<p>${esc(tc.name_pt)} já está no material mais alto.</p>`;
      if (next) {
        const cost = Math.round(next.upgrade_cost_gold * (1 + s.fx.tool_cost) * 100) / 100;
        const why = next.unlock_level > s.level ? `Precisa do nível ${next.unlock_level}.` : s.gold < cost ? `Falta ${formatGold(cost - s.gold)} de ouro.` : '';
        action = `<p>Próxima: <strong>${esc(tc.name_pt)} de ${esc(next.name_pt)}</strong> · ×${nf1.format(next.work_capacity_multiplier)} de trabalho (${nf1.format(c.rate / cur.work_capacity_multiplier * next.work_capacity_multiplier)} por hora) · nível ${next.unlock_level}</p>
          ${why ? `<ul class="problems"><li>${why}</li></ul>` : ''}
          <button type="button" class="primary" data-upgrade ${why ? 'disabled' : ''}>Melhorar por ${formatGold(cost)} ouro</button>`;
      }
      const repair = Math.round(cur.repair_cost_gold * (1 + s.fx.tool_cost) * 100) / 100;
      return `${charChips(s, c.class_id)}<div class="char-card">${sprite(`${tc.id}_${cur.id}`, 2)}<div class="grow"><strong>${esc(tc.name_pt)} de ${esc(cur.name_pt)}</strong>
          <span class="energy dura ${c.durability < 30 ? 'low' : ''}"><span style="width:${Math.round(c.durability)}%"></span></span>
          <small>${esc(className(c.class_id))} · ${nf1.format(c.rate)} de trabalho por hora · durabilidade ${nf1.format(c.durability)}</small>
          <span class="btns"><button type="button" class="secondary" data-repair="${c.class_id}" ${c.durability >= 100 || s.gold < repair ? 'disabled' : ''}>Consertar · ${formatGold(repair)}</button></span></div></div>
        <div class="tool-row">${row}</div>${action}
        <p class="hint">A ferramenta perde 2,5 de durabilidade por hora de trabalho; abaixo de 30 trabalha a 50% até o conserto. Reforma de veículos na fase 5.</p>`;
    }, (el) => {
      el.querySelectorAll<HTMLButtonElement>('[data-pick-char]').forEach((b) => b.addEventListener('click', () => { picked = b.dataset.pickChar!; current?.(); }));
      el.querySelectorAll<HTMLButtonElement>('[data-repair]').forEach((b) => b.addEventListener('click', () => { b.disabled = true; void act(() => repairTool(b.dataset.repair!), 'Ferramenta consertada.'); }));
      el.querySelector<HTMLButtonElement>('[data-upgrade]')?.addEventListener('click', (e) => {
        (e.currentTarget as HTMLButtonElement).disabled = true;
        void act(() => upgradeTool(picked), 'Ferramenta melhorada!');
      });
    });
  }
  if (id === 'garagem_expedicao') {
    show('Garagem', () => `<div class="char-card">${sprite('vehicle_carroca_common', 1)}<div><strong>Carroça</strong><small>Capacidade ${VEHICLES[0].capacity} · Feira da Vila e Cidade Vizinha</small><small>Raridade: Comum</small></div></div>
      <p class="hint">Expedições chegam na fase 5. Por enquanto, venda na Barraca.</p>`);
  }
}

// usado nos testes
export const _internal = { plotStatus, FARM, MAX_LEVEL };
