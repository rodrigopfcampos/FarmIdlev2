// Vila na interface: botão Vila no topo e painel com a Encomenda da semana (doar produção e ouro, meta coletiva,
// prêmios e títulos) e as Estrelas da Vila (depois do nível 50: pacote e sementes raras).
import { CROP_LIST, RARITY_BY_ID, VILLAGE, itemInfo } from '../data';
import { refresh, store } from '../farm/store';
import { getVillage, starBuy, villageDonate, type VillageState } from '../net/farmApi';
import { formatGold } from './format';

export type VillageCtx = {
  show: (title: string, body: () => string, bind?: (el: HTMLElement) => void) => void;
  toast: (msg: string, seconds?: number) => void;
  esc: (s: string) => string;
  itemIcon: (id: string) => string;
};

const nf = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });
const nf3 = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 3 });
/** pontos por unidade: produtos baratos valem frações pequenas */
const ptUnit = (p: number) => (p > 0 && p < 0.001 ? 'menos de 0,001' : nf3.format(p));
const left = (iso: string) => {
  const m = Math.max(0, Math.round((Date.parse(iso) - Date.now()) / 60_000));
  const d = Math.floor(m / 1440), h = Math.floor((m % 1440) / 60);
  return d ? `${d} d ${h} h` : h ? `${h} h ${m % 60} min` : `${m} min`;
};
const E = VILLAGE.encomenda, S = VILLAGE.stars;

/** botão Vila; quem tem título mostra ao lado do nome (no HUD) */
export function hudVillage(): string {
  return '<button type="button" class="hud-btn ghost" data-village title="Encomenda da Vila e Estrelas">Vila</button>';
}

let tab: 'order' | 'stars' = 'order';
let v: VillageState | null = null;
let seedCrop = '';
let seedRarity = 'rare';

export async function openVillage(ctx: VillageCtx, start: typeof tab = 'order'): Promise<void> {
  tab = start;
  try { v = await getVillage(); } catch (e) { ctx.toast(e instanceof Error ? e.message : 'Não deu certo.'); return; }
  render(ctx);
}

function render(ctx: VillageCtx): void {
  ctx.show('Vila', () => body(ctx), (el) => bind(ctx, el));
}

function body(ctx: VillageCtx): string {
  const tabs = ([['order', 'Encomenda'], ['stars', 'Estrelas']] as const)
    .map(([k, n]) => `<button type="button" role="tab" data-vtab="${k}" aria-selected="${tab === k}">${n}</button>`).join('');
  return `<div class="chips" role="tablist">${tabs}</div>${tab === 'order' ? orderTab(ctx) : starsTab(ctx)}`;
}

function orderTab(ctx: VillageCtx): string {
  const x = v!, o = x.order, m = x.mine;
  const pct = Math.min(1, m.total / o.goal);
  const silo = store.state?.silo ?? {};
  const req = o.items.map((id) => `<li class="vreq">${ctx.itemIcon(id)} <strong>${ctx.esc(itemInfo(id).name_pt)}</strong> <small>vale ${nf.format(E.requested_bonus)}×</small> <small>· no Silo: ${silo[id] ?? 0}</small></li>`).join('');
  // tudo o que dá para doar do Silo, pedidos primeiro
  const items = Object.entries(silo).filter(([id, q]) => q > 0 && x.per_unit[id] !== undefined)
    .sort(([a], [b]) => Number(o.items.includes(b)) - Number(o.items.includes(a)) || x.per_unit[b] - x.per_unit[a]);
  const rows = items.map(([id, q]) => `<li class="vdon">${ctx.itemIcon(id)} <span class="grow">${ctx.esc(itemInfo(id).name_pt)}${o.items.includes(id) ? ' <small class="good">pedido</small>' : ''}
      <small>· ${q} no Silo · ${ptUnit(x.per_unit[id])} pt cada (tudo: ${nf.format(q * x.per_unit[id])} pt)</small></span>
      <input type="number" min="1" max="${q}" value="${q}" data-qty="${id}" aria-label="Quantidade de ${ctx.esc(itemInfo(id).name_pt)}">
      <button type="button" class="secondary" data-give="${id}">Doar</button></li>`).join('');
  const gold = store.state?.gold ?? 0;
  const status = m.qualified
    ? (m.top ? `Você está no <strong>top ${E.top_pct}%</strong> (${m.rank}º).` : `Você já passou do mínimo${m.rank ? ` (${m.rank}º)` : ''}.`)
    : `Doe pelo menos <strong>${E.min_points_to_qualify} pontos</strong> para entrar no prêmio.`;
  const last = x.last ? `<h3>Semana passada: ${ctx.esc(x.last.name)}</h3><p>${x.last.result.goal_reached ? 'Meta batida ✔' : 'Meta não batida'} · você doou ${nf.format(x.last.result.points)} pt${x.last.reward ? ` · ganhou ${x.last.reward.cards} carta${x.last.reward.cards === 1 ? '' : 's'}${x.last.reward.title ? ` e o título <strong>${ctx.esc(x.last.reward.title)}</strong>` : ''}` : ''}</p>` : '';
  return `<h3>${ctx.esc(o.name)} <small>· termina em ${left(o.ends_at)}</small></h3>
    <div class="vbar" role="progressbar" aria-valuenow="${Math.round(pct * 100)}" aria-valuemin="0" aria-valuemax="100"><span style="width:${pct * 100}%"></span></div>
    <p class="status">Vila: <strong>${nf.format(m.total)} de ${nf.format(o.goal)} pontos</strong> · ${m.donors} doador${m.donors === 1 ? '' : 'es'}<br>
      Você: <strong>${nf.format(m.points)} pt</strong>. ${status}</p>
    <p class="hint">1 ponto = 1 hora da renda do seu nível (${formatGold(x.gold_per_point)} de ouro). Tudo o que é doado some do jogo.
      Prêmio: meta batida e ${E.min_points_to_qualify}+ pontos = ${E.reward.card_if_goal_and_qualified} carta e o título "${E.titles.participant}"; top ${E.top_pct}% = +${E.reward.card_if_top} carta e o título "${E.titles.top}" por uma semana.</p>
    <h3>Pedidos da semana</h3><ul class="vlist">${req}</ul>
    <h3>Doar do Silo</h3>${rows ? `<ul class="vlist">${rows}</ul>` : '<p class="hint">O Silo está vazio.</p>'}
    <h3>Doar ouro</h3><div class="vdon"><span class="grow">Você tem ${formatGold(gold)}</span>
      <input type="number" min="1" step="1" max="${Math.floor(gold)}" value="${Math.min(Math.floor(gold), Math.ceil(x.gold_per_point))}" data-gold aria-label="Ouro para doar">
      <button type="button" class="secondary" data-give-gold>Doar</button></div>
    ${last}`;
}

function starsTab(ctx: VillageCtx): string {
  const st = v!.stars;
  if (!st.unlocked) return `<p>As <strong>Estrelas da Vila</strong> liberam no nível ${S.unlock_level}: depois dele, cada ${nf.format(S.xp_per_star_ratio_of_level_49 * 100)}% do XP do nível 49 vira 1 Estrela.</p>
    <p class="hint">Com Estrelas + ouro você compra pacote de carta (${S.pack.stars} ⭐, até ${S.pack.per_week} por semana) e sementes raras Incomum, Rara ou Lendária (até ${S.seed.per_week} por semana).</p>`;
  const pct = st.per_star ? Math.min(1, st.xp / st.per_star) : 0;
  const packGold = st.R * S.pack.gold_R_ratio;
  const crops = CROP_LIST.map((c) => `<option value="${c.id}" ${c.id === seedCrop ? 'selected' : ''}>${ctx.esc(c.name_pt)}</option>`).join('');
  const rar = Object.entries(S.seed.rarities).map(([r, p]) => `<option value="${r}" ${r === seedRarity ? 'selected' : ''}>${ctx.esc(RARITY_BY_ID[r]?.name_pt ?? r)} · ${p.stars} ⭐ + ${formatGold(st.R * p.gold_R_ratio)}</option>`).join('');
  return `<p class="status"><strong>${st.stars} ⭐</strong> · próxima Estrela: ${nf.format(st.xp)} de ${nf.format(st.per_star)} XP</p>
    <div class="vbar"><span style="width:${pct * 100}%"></span></div>
    <h3>Pacote de carta</h3>
    <p>${S.pack.stars} ⭐ + ${formatGold(packGold)} de ouro · ${st.packs_week}/${S.pack.per_week} nesta semana. Conta para a garantia.</p>
    <button type="button" class="primary small" data-pack ${st.stars < S.pack.stars || st.packs_week >= S.pack.per_week ? 'disabled' : ''}>Comprar pacote</button>
    <h3>Semente rara</h3>
    <div class="row"><label>Cultivo <select data-seed-crop>${crops}</select></label><label>Raridade <select data-seed-rarity>${rar}</select></label></div>
    <p>${st.seeds_week}/${S.seed.per_week} nesta semana. A semente vale 1 plantio (árvore: 6 colheitas).</p>
    <button type="button" class="primary small" data-seed ${st.seeds_week >= S.seed.per_week ? 'disabled' : ''}>Comprar semente</button>
    <p class="hint">Mítico não se compra: só no sorteio dos pacotes.</p>`;
}

function bind(ctx: VillageCtx, el: HTMLElement): void {
  const run = async (fn: () => Promise<VillageState>, ok: string) => {
    try { v = await fn(); ctx.toast(ok); await refresh(); render(ctx); } catch (e) { ctx.toast(e instanceof Error ? e.message : 'Não deu certo.'); }
  };
  el.querySelectorAll<HTMLButtonElement>('[data-vtab]').forEach((b) => b.addEventListener('click', () => { tab = b.dataset.vtab as typeof tab; render(ctx); }));
  el.querySelectorAll<HTMLButtonElement>('[data-give]').forEach((b) => b.addEventListener('click', () => {
    const id = b.dataset.give!;
    const q = Math.floor(Number(el.querySelector<HTMLInputElement>(`[data-qty="${id}"]`)!.value));
    if (!(q > 0)) return;
    b.disabled = true;
    void run(() => villageDonate(id, q), `Doou ${q} ${itemInfo(id).name_pt} para a Vila.`);
  }));
  el.querySelector('[data-give-gold]')?.addEventListener('click', (e) => {
    const g = Math.floor(Number(el.querySelector<HTMLInputElement>('[data-gold]')!.value));
    if (!(g > 0)) return;
    (e.currentTarget as HTMLButtonElement).disabled = true;
    void run(() => villageDonate(null, g), `Doou ${formatGold(g)} de ouro para a Vila.`);
  });
  if (!seedCrop) seedCrop = CROP_LIST[0].id;
  el.querySelector<HTMLSelectElement>('[data-seed-crop]')?.addEventListener('change', (e) => { seedCrop = (e.target as HTMLSelectElement).value; });
  el.querySelector<HTMLSelectElement>('[data-seed-rarity]')?.addEventListener('change', (e) => { seedRarity = (e.target as HTMLSelectElement).value; });
  el.querySelector('[data-pack]')?.addEventListener('click', (e) => { (e.currentTarget as HTMLButtonElement).disabled = true; void run(() => starBuy('pack'), 'Pacote comprado! A carta abre já.'); });
  el.querySelector('[data-seed]')?.addEventListener('click', (e) => {
    (e.currentTarget as HTMLButtonElement).disabled = true;
    void run(() => starBuy('seed', seedCrop, seedRarity), 'Semente rara no inventário.');
  });
}
