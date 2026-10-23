// Interface por cima do mapa: barra do topo e os painéis das zonas e dos canteiros.
import { bus } from '../core/bus';
import { CROPS, FARM, STALL_RATIO, UNLOCKED_CROPS } from '../data';
import { iconSprite } from '../farm/art';
import { applyState, store } from '../farm/store';
import { sellAtStall, setCrop, type FarmState, type PlotState } from '../net/farmApi';
import { supabase } from '../net/supabase';
import { formatGold } from './format';

const nf1 = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

export function duration(seconds: number): string {
  const m = Math.max(0, Math.ceil(seconds / 60));
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60), r = m % 60;
  return r ? `${h} h ${String(r).padStart(2, '0')}` : `${h} h`;
}

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

export function mountGameUi(el: HTMLElement): void {
  root = el;
  root.innerHTML = `<div class="hud" id="hud"></div><div class="modal" id="modal" hidden></div><div class="toast" id="toast" role="status" aria-live="polite"></div>`;
  hud = root.querySelector('#hud')!;
  panel = root.querySelector('#modal')!;
  panel.addEventListener('click', (e) => { if (e.target === panel) close(); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
  bus.on('farm:state', onState);
  bus.on('farm:error', (msg: string) => toast(msg));
  bus.on('ui:zone', (id: string) => openZone(id));
  bus.on('ui:plot', (id: string) => openPlot(id));
  bus.on('ui:locked', (id: string) => openInfo(`Lote ${id}`, 'A compra de lotes chega na fase 2 (progressão). Por enquanto, sua fazenda é o lote A1.'));
  if (store.state) onState(store.state);
}

function onState(s: FarmState): void {
  hud.innerHTML = `
    <span class="nick">${esc(s.nickname)}</span>
    <span class="gold" title="Ouro">${sprite('ui_coin', 1, 'coin-img')}${formatGold(s.gold)}</span>
    <button type="button" class="hud-btn" data-open="casa_principal">Silo</button>
    <button type="button" class="logout">Sair</button>`;
  hud.querySelector('.logout')!.addEventListener('click', () => supabase!.auth.signOut());
  hud.querySelector('[data-open]')!.addEventListener('click', () => openZone('casa_principal', 'silo'));
  current?.();
}

function toast(msg: string): void {
  const t = root.querySelector<HTMLElement>('#toast')!;
  t.textContent = msg;
  t.classList.add('show');
  window.setTimeout(() => t.classList.remove('show'), 3500);
}

function show(title: string, body: () => string, bind?: (el: HTMLElement) => void): void {
  const render = () => {
    panel.innerHTML = `<div class="panel game-panel" role="dialog" aria-label="${esc(title)}">
      <header><h2>${esc(title)}</h2><button type="button" class="close" aria-label="Fechar">×</button></header>
      <div class="body">${body()}</div></div>`;
    panel.querySelector('.close')!.addEventListener('click', close);
    bind?.(panel);
  };
  current = render;
  panel.hidden = false;
  render();
}

function close(): void { panel.hidden = true; current = null; }

function openInfo(title: string, text: string): void { show(title, () => `<p>${esc(text)}</p>`); }

async function act(fn: () => Promise<FarmState>, ok?: string): Promise<void> {
  try { applyState(await fn()); if (ok) toast(ok); } catch (e) { toast(e instanceof Error ? e.message : 'Não deu certo.'); }
}

// ---------- canteiro ----------
function plotStatus(p: PlotState): string {
  const now = store.clock.farmNow();
  if (p.state === 'growing') return `<strong>${esc(CROPS[p.planted_crop_id!].name_pt)}</strong> crescendo: pronto em ${duration(p.ready_at! - now)}. Depois o Agricultor colhe e replanta sozinho.`;
  if (p.crop_id && p.stalled_reason === 'sem_ouro') return `Parado: falta ouro para a semente de ${esc(CROPS[p.crop_id].name_pt)}. Venda algo na Barraca.`;
  if (p.crop_id) return `Esperando o Agricultor ter tempo para plantar ${esc(CROPS[p.crop_id].name_pt)}.`;
  return 'Vazio. Escolha o que plantar: o Agricultor replanta sempre o mesmo cultivo.';
}

function openPlot(id: string): void {
  const lot = id.split('-')[0];
  show(`Canteiro ${id}`, () => {
    const p = store.state?.plots.find((x) => x.plot_id === id);
    if (!p) return '<p>Carregando…</p>';
    const crops = UNLOCKED_CROPS.map((c) => {
      const sell = c.units_per_harvest * c.fair_price_per_unit * STALL_RATIO;
      return `<button type="button" class="crop ${p.crop_id === c.id ? 'selected' : ''}" data-crop="${c.id}" aria-pressed="${p.crop_id === c.id}">
        ${sprite(iconSprite(store.manifest, c.id), 1)}
        <span><strong>${esc(c.name_pt)}</strong><small>Cresce em ${duration(c.grow_minutes * 60)} · semente ${nf1.format(c.seed_cost ?? 0)} · colheita ${c.units_per_harvest} × ${c.fair_price_per_unit} (Barraca ${nf1.format(sell)})</small></span>
      </button>`;
    }).join('');
    return `<p class="status">${plotStatus(p)}</p>
      <div class="crops">${crops}</div>
      <div class="row">
        <button type="button" class="secondary" data-all>Usar no lote ${esc(lot)} inteiro</button>
        ${p.crop_id ? '<button type="button" class="secondary" data-stop>Parar este canteiro</button>' : ''}
      </div>
      <p class="hint">Cada plantio usa 1 unidade de trabalho do Agricultor (${nf1.format(store.state!.labor_per_hour)} por hora). Cultivos curtos rendem por hora, mas pedem mais trabalho.</p>`;
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

function openZone(id: string, tab = 'silo'): void {
  if (id === 'casa_principal') {
    let active = tab;
    show('Casa', () => {
      const s = store.state!;
      const tabs = [['silo', 'Silo'], ['operadores', 'Operadores'], ['equipamentos', 'Equipamentos']]
        .map(([k, n]) => `<button type="button" role="tab" data-tab="${k}" aria-selected="${active === k}">${n}</button>`).join('');
      let body = '';
      if (active === 'silo') body = siloItems(false) + '<p class="hint">Para vender, use a Barraca. Expedições chegam na fase 5.</p>';
      if (active === 'operadores') {
        const cap = s.labor_per_hour * s.labor_cap_hours;
        body = `<div class="slots"><span class="slot-title">Slots de Campo</span>
          <div class="char-card">${sprite('char_agricultor_idle', 2)}<div><strong>Agricultor</strong><small>Dono da fazenda · sem salário</small>
          <small>Planta e colhe a lavoura: ${nf1.format(s.labor_per_hour)} plantios por hora</small>
          <small>Trabalho guardado: ${nf1.format(s.labor_bank)} de ${nf1.format(cap)}</small></div></div>
          <div class="slot empty-slot">Vago · contratação na fase 3</div><div class="slot empty-slot">Vago · contratação na fase 3</div>
          <span class="slot-title">Slots de Banco</span><div class="slot empty-slot">Descanso · fase 3</div></div>`;
      }
      if (active === 'equipamentos') body = `<div class="char-card">${sprite('tool_hoe_wood', 2)}<div><strong>Enxada de Madeira</strong><small>Ferramenta do Agricultor (×1,0 de capacidade)</small><small>Desgaste, conserto e melhorias chegam na fase 3.</small></div></div>`;
      return `<div class="tabs" role="tablist">${tabs}</div>${body}`;
    }, (el) => el.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach((b) => b.addEventListener('click', () => { active = b.dataset.tab!; current?.(); })));
  }
  if (id === 'barraca_comerciante') {
    show('Barraca', () => `<p>Venda na hora, sem risco, a ${Math.round(STALL_RATIO * 100)}% do preço da Feira.</p>${siloItems(true)}
      <p class="hint">Lanches para a energia dos personagens chegam na fase 3.</p>`, bindSell);
  }
  if (id === 'oficina_ferreiro') {
    show('Forja', () => `<p>Aqui o Ferreiro vai melhorar e consertar ferramentas e reformar veículos.</p>
      <div class="tool-row">${['wood', 'copper', 'iron', 'gold', 'crystal'].map((m) => sprite(`tool_hoe_${m}`, 2)).join('')}</div>
      <p class="hint">Ferramentas chegam na fase 3 e reforma de veículos na fase 5.</p>`);
  }
  if (id === 'garagem_expedicao') {
    show('Garagem', () => `<div class="char-card">${sprite('vehicle_carroca_common', 1)}<div><strong>Carroça</strong><small>Capacidade 60 · Feira da Vila e Cidade Vizinha</small><small>Raridade: Comum</small></div></div>
      <p class="hint">Expedições chegam na fase 5. Por enquanto, venda na Barraca.</p>`);
  }
}

// usado nos testes
export const _internal = { plotStatus, FARM };
