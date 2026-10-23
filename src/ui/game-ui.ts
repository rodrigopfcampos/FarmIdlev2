// Interface por cima do mapa: barra do topo (nível, XP, ouro, Escrituras) e os painéis
// das zonas, dos canteiros, dos lotes à venda e do pomar.
import { bus } from '../core/bus';
import { CROPS, CROP_LIST, FARM, LOT_BY_ID, LOT_TYPE_NAMES, MAX_LEVEL, STALL_RATIO, TOOL_MATERIALS, VEHICLES, WORK, type Crop } from '../data';
import { iconSprite } from '../farm/art';
import { lotOffer, orchardFruits, plotCrops, treeLook, xpProgress } from '../farm/rules';
import { applyState, store } from '../farm/store';
import { buyLot, chopTree, plantTree, sellAtStall, setCrop, upgradeTool, type FarmState, type PlotState } from '../net/farmApi';
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

let root: HTMLElement;
let hud: HTMLElement;
let panel: HTMLElement;
let current: (() => void) | null = null; // redesenha o painel aberto quando o estado muda
let lastLevel = 0;

export function mountGameUi(el: HTMLElement): void {
  root = el;
  lastLevel = 0;
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
  bus.on('ui:plot', (id: string) => openPlot(id));
  bus.on('ui:locked', (id: string) => openLot(id));
  bus.on('ui:orchard', (id: string) => openOrchard(id));
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
    <button type="button" class="hud-btn" data-open="casa_principal">Silo</button>
    <button type="button" class="logout">Sair</button>`;
  hud.querySelector('.logout')!.addEventListener('click', () => supabase!.auth.signOut());
  hud.querySelector('[data-open]')!.addEventListener('click', () => openZone('casa_principal', 'silo'));
  if (lastLevel && s.level > lastLevel) levelUp(lastLevel, s.level);
  lastLevel = s.level;
  current?.();
}

function levelUp(from: number, to: number): void {
  const news = CROP_LIST.filter((c) => c.unlock_level > from && c.unlock_level <= to).map((c) => c.name_pt);
  const tools = TOOL_MATERIALS.filter((m) => m.unlock_level > from && m.unlock_level <= to).map((m) => `Enxada de ${m.name_pt}`);
  const extra = [...news, ...tools];
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
  const sell = c.units_per_harvest * c.fair_price_per_unit * STALL_RATIO;
  const base = `Cresce em ${duration(c.grow_minutes * 60)} · semente ${nf1.format(c.seed_cost ?? 0)} · colheita ${c.units_per_harvest} × ${formatGold(c.fair_price_per_unit)} (Barraca ${nf1.format(sell)}) · ${nf1.format(c.xp_per_harvest)} XP`;
  if (c.kind !== 'recurring') return base;
  return `${base}<br>Recorrente: ${c.harvests_per_planting} colheitas com 1 semente, uma a cada ${duration((c.regrow_minutes ?? 0) * 60)} depois da 1ª`;
}

function plotStatus(p: PlotState): string {
  const now = store.clock.farmNow();
  const lot = p.plot_id.split('-')[0];
  const cleanup = cleanupLeft(lot);
  if (cleanup) return `Lote em limpeza: fica pronto em ${duration(cleanup)}. ${p.crop_id ? `Depois o Agricultor planta ${esc(CROPS[p.crop_id].name_pt)}.` : 'Já dá para escolher o cultivo.'}`;
  if (p.state === 'growing') {
    const c = CROPS[p.planted_crop_id!];
    const which = c.kind === 'recurring' ? ` (colheita ${p.harvests_done + 1} de ${c.harvests_per_planting})` : '';
    return `<strong>${esc(c.name_pt)}</strong> crescendo${which}: pronto em ${duration(p.ready_at! - now)}. Depois o Agricultor colhe e replanta sozinho.`;
  }
  if (p.crop_id && p.stalled_reason === 'sem_ouro') return `Parado: falta ouro para a semente de ${esc(CROPS[p.crop_id].name_pt)}. Venda algo na Barraca.`;
  if (p.crop_id) return `Esperando o Agricultor ter tempo para plantar ${esc(CROPS[p.crop_id].name_pt)}.`;
  return 'Vazio. Escolha o que plantar: o Agricultor replanta sempre o mesmo cultivo.';
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
    return `<p class="status">${plotStatus(p)}</p>
      <div class="crops">${crops}</div>
      <div class="row">
        <button type="button" class="secondary" data-all>Usar no lote ${esc(lot)} inteiro</button>
        ${p.crop_id ? '<button type="button" class="secondary" data-stop>Parar este canteiro</button>' : ''}
      </div>
      <p class="hint">Plantar usa ${nf1.format(WORK.plant_and_harvest)} unidade de trabalho do Agricultor (${nf1.format(s.labor_per_hour)} por hora); cada colheita extra de recorrente ou de árvore usa ${nf1.format(WORK.extra_harvest_recurring_or_tree)}. Cultivos curtos rendem por hora, mas pedem mais trabalho.</p>`;
  }, (el) => {
    let chosen = store.state?.plots.find((x) => x.plot_id === id)?.crop_id ?? null;
    el.querySelectorAll<HTMLButtonElement>('[data-crop]').forEach((b) => b.addEventListener('click', () => {
      chosen = b.dataset.crop!;
      void act(() => setCrop(id, chosen), `${CROPS[chosen].name_pt} no canteiro ${id}`);
    }));
    el.querySelector('[data-all]')?.addEventListener('click', () => {
      if (!chosen) { toast('Escolha um cultivo primeiro.'); return; }
      void act(() => setCrop(lot, chosen), `${CROPS[chosen].name_pt} no lote ${lot} inteiro`);
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
    const o = lotOffer(id, owned, s.level, s.inventory.deed ?? 0, s.gold);
    if (!o) return '<p>Este lote já é seu.</p>';
    if (o.problems.includes('fim')) return `<p>${PROBLEM_TEXT.fim(o)}</p>`;
    const what = def.type === 'lavoura' ? '8 canteiros' : def.type === 'pomar' ? '4 vagas de árvore (o Agricultor cuida do pomar até a fase 3)' : 'pasto para animais (fase 4)';
    return `<dl class="facts">
        <dt>Compra</dt><dd>${o.n}ª de 29</dd>
        <dt>O que vem</dt><dd>${what}</dd>
        <dt>Custo</dt><dd>${sprite('ui_coin', 1, 'coin-img')} ${formatGold(o.cost)} ouro <small>(${o.daysOfIncome < 1 ? 'menos de 1 dia' : `≈ ${nf1.format(o.daysOfIncome)} dias`} de renda no seu nível)</small></dd>
        <dt>Nível</dt><dd>${o.needLevel}</dd>
        ${o.needsDeed ? `<dt>Escritura</dt><dd>${sprite('item_deed', 0.5)} 1 (você tem ${s.inventory.deed ?? 0})</dd>` : ''}
        <dt>Limpeza</dt><dd>${duration(o.cleanupMinutes * 60)} <small>(pedras e tocos; sem Ferreiro leva o dobro, até a fase 3)</small></dd>
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
  const when = left > 0 ? `próxima colheita em ${duration(left)}` : 'colheita esperando o Agricultor';
  return `<strong>${esc(c.name_pt)}</strong> · ${look === 'sapling' ? 'muda' : look === 'fruit' ? 'com fruta' : 'adulta'} · ${when}`;
}

function fruitInfo(c: Crop): string {
  const sell = c.units_per_harvest * c.fair_price_per_unit * STALL_RATIO;
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
      picker = `<h3>Muda para a vaga ${picking}</h3>${has ? '<p class="hint">A árvore atual é derrubada de graça e a nova muda cresce do zero.</p>' : ''}
        <div class="crops">${[...[...open].reverse().map((c) => btn(c, false)), ...next.map((c) => btn(c, true))].join('') || '<p>Nenhuma fruta liberada ainda.</p>'}</div>`;
    }
    return `<ul class="items trees">${slots}</ul>${picker}
      <p class="hint">O Agricultor colhe as árvores sozinho; cada colheita usa ${nf1.format(WORK.extra_harvest_recurring_or_tree)} de trabalho. Árvores não precisam de semente.</p>`;
  }, (el) => {
    el.querySelectorAll<HTMLButtonElement>('[data-pick]').forEach((b) => b.addEventListener('click', () => { picking = Number(b.dataset.pick); current?.(); }));
    el.querySelectorAll<HTMLButtonElement>('[data-chop]').forEach((b) => b.addEventListener('click', () => {
      b.disabled = true;
      void act(() => chopTree(lot, Number(b.dataset.chop)), 'Árvore derrubada.');
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
  const items = Object.entries(store.state?.silo ?? {}).filter(([, q]) => q > 0);
  if (!items.length) return '<p class="empty">O Silo está vazio. As colheitas chegam aqui sozinhas.</p>';
  return `<ul class="items">${items.map(([id, q]) => {
    const c = CROPS[id];
    const unit = c.fair_price_per_unit * STALL_RATIO;
    return `<li>${sprite(iconSprite(store.manifest, id), 1)}<span><strong>${esc(c.name_pt)}</strong><small>${q} no Silo · Barraca ${nf1.format(unit)} cada</small></span>
      ${withSell ? `<span class="btns"><button type="button" class="secondary" data-sell="${id}" data-qty="1">Vender 1</button><button type="button" class="primary small" data-sell="${id}" data-qty="${q}">Vender tudo (${formatGold(q * unit)})</button></span>` : ''}</li>`;
  }).join('')}</ul>`;
}

function bindSell(el: HTMLElement): void {
  el.querySelectorAll<HTMLButtonElement>('[data-sell]').forEach((b) => b.addEventListener('click', () => {
    b.disabled = true;
    const qty = Number(b.dataset.qty);
    void act(() => sellAtStall(b.dataset.sell!, qty), `Vendido: ${qty} ${CROPS[b.dataset.sell!].name_pt}`);
  }));
}

function toolMaterial(s: FarmState) {
  const id = s.tools.agricultor ?? TOOL_MATERIALS[0].id;
  const i = TOOL_MATERIALS.findIndex((m) => m.id === id);
  return { cur: TOOL_MATERIALS[i], next: TOOL_MATERIALS[i + 1] as (typeof TOOL_MATERIALS)[number] | undefined };
}

function openZone(id: string, tab = 'silo'): void {
  if (id === 'casa_principal') {
    let active = tab;
    show('Casa', () => {
      const s = store.state!;
      const tabs = [['silo', 'Silo'], ['operadores', 'Operadores'], ['equipamentos', 'Equipamentos']]
        .map(([k, n]) => `<button type="button" role="tab" data-tab="${k}" aria-selected="${active === k}">${n}</button>`).join('');
      let body = '';
      if (active === 'silo') {
        const deeds = s.inventory.deed ?? 0;
        body = siloItems(false) + `<h3>Itens</h3>${deeds
          ? `<ul class="items"><li>${sprite('item_deed', 1)}<span><strong>Escritura</strong><small>${deeds} · cada compra de lote da 20ª em diante gasta 1</small></span></li></ul>`
          : '<p class="empty">Nenhum item ainda.</p>'}<p class="hint">Para vender, use a Barraca. Expedições chegam na fase 5.</p>`;
      }
      if (active === 'operadores') {
        const cap = s.labor_per_hour * s.labor_cap_hours;
        body = `<div class="slots"><span class="slot-title">Slots de Campo</span>
          <div class="char-card">${sprite('char_agricultor_idle', 2)}<div><strong>Agricultor</strong><small>Dono da fazenda · sem salário</small>
          <small>Planta e colhe a lavoura e o pomar: ${nf1.format(s.labor_per_hour)} unidades de trabalho por hora</small>
          <small>Trabalho guardado: ${nf1.format(s.labor_bank)} de ${nf1.format(cap)}</small></div></div>
          <div class="slot empty-slot">Vago · contratação na fase 3</div><div class="slot empty-slot">Vago · contratação na fase 3</div>
          <span class="slot-title">Slots de Banco</span><div class="slot empty-slot">Descanso · fase 3</div></div>`;
      }
      if (active === 'equipamentos') {
        const { cur } = toolMaterial(s);
        body = `<div class="char-card">${sprite(`tool_hoe_${cur.id}`, 2)}<div><strong>Enxada de ${esc(cur.name_pt)}</strong><small>Ferramenta do Agricultor (×${nf1.format(cur.work_capacity_multiplier)} de trabalho)</small><small>Melhore na Forja. Desgaste e conserto chegam na fase 3.</small></div></div>`;
      }
      return `<div class="tabs" role="tablist">${tabs}</div>${body}`;
    }, (el) => el.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach((b) => b.addEventListener('click', () => { active = b.dataset.tab!; current?.(); })));
  }
  if (id === 'barraca_comerciante') {
    show('Barraca', () => `<p>Venda na hora, sem risco, a ${Math.round(STALL_RATIO * 100)}% do preço da Feira.</p>${siloItems(true)}
      <p class="hint">Lanches para a energia dos personagens chegam na fase 3.</p>`, bindSell);
  }
  if (id === 'oficina_ferreiro') {
    show('Forja', () => {
      const s = store.state!;
      const { cur, next } = toolMaterial(s);
      const row = TOOL_MATERIALS.map((m) => `<span class="tool ${m.id === cur.id ? 'current' : ''} ${m.unlock_level > s.level ? 'locked' : ''}" title="${esc(m.name_pt)} · nível ${m.unlock_level} · ×${nf1.format(m.work_capacity_multiplier)}">${sprite(`tool_hoe_${m.id}`, 2)}<small>${esc(m.name_pt)}</small></span>`).join('');
      let action = '<p>A Enxada já está no material mais alto.</p>';
      if (next) {
        const why = next.unlock_level > s.level ? `Precisa do nível ${next.unlock_level}.` : s.gold < next.upgrade_cost_gold ? `Falta ${formatGold(next.upgrade_cost_gold - s.gold)} de ouro.` : '';
        action = `<p>Próxima: <strong>Enxada de ${esc(next.name_pt)}</strong> · ×${nf1.format(next.work_capacity_multiplier)} de trabalho (${nf1.format(s.labor_per_hour / cur.work_capacity_multiplier * next.work_capacity_multiplier)} por hora) · nível ${next.unlock_level}</p>
          ${why ? `<ul class="problems"><li>${why}</li></ul>` : ''}
          <button type="button" class="primary" data-upgrade ${why ? 'disabled' : ''}>Melhorar por ${formatGold(next.upgrade_cost_gold)} ouro</button>`;
      }
      return `<div class="char-card">${sprite(`tool_hoe_${cur.id}`, 2)}<div><strong>Enxada de ${esc(cur.name_pt)}</strong><small>Agricultor · ${nf1.format(s.labor_per_hour)} unidades de trabalho por hora</small></div></div>
        <div class="tool-row">${row}</div>${action}
        <p class="hint">Na fase 3 o Ferreiro chega: desgaste, conserto e ferramentas dos outros personagens. Reforma de veículos na fase 5.</p>`;
    }, (el) => el.querySelector<HTMLButtonElement>('[data-upgrade]')?.addEventListener('click', (e) => {
      (e.currentTarget as HTMLButtonElement).disabled = true;
      void act(() => upgradeTool('agricultor'), 'Enxada melhorada!');
    }));
  }
  if (id === 'garagem_expedicao') {
    show('Garagem', () => `<div class="char-card">${sprite('vehicle_carroca_common', 1)}<div><strong>Carroça</strong><small>Capacidade ${VEHICLES[0].capacity} · Feira da Vila e Cidade Vizinha</small><small>Raridade: Comum</small></div></div>
      <p class="hint">Expedições chegam na fase 5. Por enquanto, venda na Barraca.</p>`);
  }
}

// usado nos testes
export const _internal = { plotStatus, FARM, MAX_LEVEL };
