// Garagem (fase 5; v3): veículos, nova expedição num mapa de pergaminho (destino clicando no mapa, carga com − / + / MÁX
// e barra de carga), partida direta (sem minigame: o veículo sai sozinho pela estrada), viagens em andamento e o botão Receber com o relatório narrado. O servidor confere e sorteia tudo.
import { EQUIP_CARDS, EQUIP_RARITIES, EXP, RARITIES, RARITY_BY_ID, ROUTES, ROUTE_BY_ID, VEHICLES, VEHICLE_BY_ID, itemInfo } from '../data';
import {
  canReach, capacity, cargoValue, insuranceCost, rarityMult, sellable, splitCargo, tripChance, tripHours, vehicleStatus,
} from '../farm/expeditions';
import { applyState, store } from '../farm/store';
import { buffLines } from '../farm/cards';
import {
  collectExpeditions, launchExpedition, setActiveVehicle,
  type CollectedTrip, type FarmState, type VehicleState,
} from '../net/farmApi';
import { duration, formatGold } from './format';

export type GarageCtx = {
  show: (title: string, body: () => string, bind?: (el: HTMLElement) => void) => void;
  act: (fn: () => Promise<FarmState>, ok?: string) => Promise<void>;
  toast: (msg: string, seconds?: number) => void;
  sprite: (key: string | null, scale?: number, cls?: string, filter?: string) => string;
  esc: (s: string) => string;
  close: () => void;
  itemIcon: (id: string) => string;
};

const nf1 = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });
const pct = (x: number) => `${nf1.format(x * 100)}%`;
const mult = (r: string) => rarityMult(r, RARITIES);
// mapa de pergaminho: posição (%) e ícone de cada destino; a fazenda é o ponto de partida
const MAP_PINS: Record<string, { x: number; y: number; icon: string }> = {
  fazenda: { x: 7, y: 78, icon: '🏡' }, feira: { x: 24, y: 52, icon: '🎪' }, cidade: { x: 42, y: 74, icon: '🏘️' },
  capital: { x: 60, y: 38, icon: '🏛️' }, porto: { x: 77, y: 68, icon: '⚓' }, exportacao: { x: 93, y: 30, icon: '🚢' },
};
const OUTCOME: Record<string, { text: string; icon: string }> = {
  crit: { text: 'Crítico! +25%', icon: 'result_jackpot' }, success: { text: 'Sucesso', icon: 'result_coins' }, fail: { text: 'Falha parcial', icon: 'result_cargo_burned' },
};

/** nome de item com raridade: Kit de Reforma, vestimenta e amuleto */
export function dropName(id: string): string {
  if (id === 'deed') return 'Escritura';
  const [base, rar] = id.split(':');
  const r = RARITY_BY_ID[rar]?.name_pt ?? '';
  if (base === 'kit') return `Kit de Reforma ${r}`;
  const card = EQUIP_CARDS.find((c) => c.id === base);
  return card ? `${card.name_pt} ${r}` : id;
}
export const dropColor = (id: string) => EQUIP_RARITIES[id.split(':')[1]]?.color_hex ?? RARITY_BY_ID[id.split(':')[1]]?.color_hex ?? 'inherit';
const vehName = (id: string) => VEHICLE_BY_ID[id].name_pt;
// v3: a cara do veículo é a animação nova (1º quadro); a raridade aparece no selo
const vehSprite = (ctx: GarageCtx, v: { vehicle_id: string; rarity?: string }, scale = 1, cls = '') => ctx.sprite(`vehicle_anim_${v.vehicle_id}`, scale, cls);

// ---------- estado da tela ----------
type Form = { vehicles: string[]; route: string; cargo: Record<string, number>; insurance: boolean; manager: boolean; repeat: boolean };
let view: 'garage' | 'form' | 'report' = 'garage';
let form: Form = { vehicles: [], route: 'feira', cargo: {}, insurance: false, manager: false, repeat: true };
let lastReport: CollectedTrip[] = [];

export function openGarage(ctx: GarageCtx, start: 'garage' | 'form' = 'garage'): void {
  view = start;
  ctx.show('Garagem', () => body(ctx), (el) => bind(ctx, el));
}

function body(ctx: GarageCtx): string {
  const s = store.state!;
  if (view === 'report') return reportView(ctx);
  if (view === 'form') return formView(ctx, s);
  return garageView(ctx, s);
}

function garageView(ctx: GarageCtx, s: FarmState): string {
  const now = store.clock.farmNow();
  const anyBack = s.expeditions.some((x) => x.status === 'back');
  const cards = VEHICLES.map((d) => {
    const v = s.vehicles.find((x) => x.vehicle_id === d.id);
    if (!v) {
      // v3: a Garagem não vende; o veículo libera sozinho no nível dele
      return `<li class="veh locked">${ctx.sprite(`vehicle_anim_${d.id}`, 0.7, 'silhouette')}<span><strong>${ctx.esc(d.name_pt)}</strong>
        <small>${d.capacity} unid. · duração ×${nf1.format(d.duration_multiplier)} · +${d.safety_pts} pontos · até ${ctx.esc(ROUTE_BY_ID[d.max_route].name_pt)}</small>
        <small>Libera sozinho no nível ${d.unlock_level}</small></span></li>`;
    }
    const st = vehicleStatus(s, v, now);
    const r = RARITY_BY_ID[v.rarity];
    const m = mult(v.rarity);
    const travel = st.trips.find((x) => x.status === 'travel');
    const backN = st.trips.filter((x) => x.status === 'back').length;
    const status = st.status === 'travel' ? `Viajando para ${ROUTE_BY_ID[travel!.route_id].name_pt} · volta em ${duration(st.until! - now)}${travel!.repeat_left ? ` · repete mais ${travel!.repeat_left}×` : ''}${backN ? ` · ${backN} viagem(ns) esperando Receber` : ''}`
      : st.status === 'back' ? `Voltou: ${backN} viagem(ns) para Receber`
      : st.status === 'refurb' ? `Na reforma (vira ${RARITY_BY_ID[v.refurb_rarity!].name_pt}) · pronto em ${duration(st.until! - now)}`
      : 'Livre na Garagem';
    return `<li class="veh ${v.active ? 'active-pet' : ''}">${vehSprite(ctx, v, 0.7)}<span><strong>${ctx.esc(d.name_pt)} <span class="shield" style="--c:${r.color_hex}">${ctx.esc(r.name_pt)}</span></strong>
      <small>${capacity(v, m)} unid. · duração ×${nf1.format(d.duration_multiplier / m)} · +${nf1.format(d.safety_pts * m)} pontos · até ${ctx.esc(ROUTE_BY_ID[d.max_route].name_pt)}</small>
      <span class="energy dura ${v.durability < EXP.low_wear_threshold_pct ? 'low' : ''}" title="Durabilidade ${nf1.format(v.durability)}"><span style="width:${Math.round(v.durability)}%"></span></span>
      <small>${ctx.esc(status)}${v.durability < EXP.low_wear_threshold_pct ? ' · <span class="bad">desgastado: −5 pontos (conserte na Forja)</span>' : ''}</small></span>
      <span class="btns">${backN ? `<button type="button" class="primary small" data-collect="${v.vehicle_id}">Receber</button>` : ''}
      ${!v.active ? `<button type="button" class="secondary" data-active-veh="${v.vehicle_id}">Deixar na vaga</button>` : ''}</span></li>`;
  }).join('');
  const idle = s.vehicles.filter((v) => vehicleStatus(s, v, now).status === 'idle');
  const streak = s.exp_fail_streak >= EXP.bad_luck_protection.after_failures
    ? `<p class="hint good">Garantia contra azar: a próxima expedição sai com +${EXP.bad_luck_protection.bonus_pts} pontos.</p>` : '';
  const vc = s.buffs.find((b) => b.card_id === 'veiculo');
  const vcTxt = vc ? `<p class="status">Carta de Veículo ${ctx.esc(RARITY_BY_ID[vc.rarity]?.name_pt ?? '')} na mão: ${ctx.esc(buffLines('veiculo', vc.rarity).join(', '))} (vale para quem parte agora).</p>`
    : '<p class="hint">Com a carta de Veículo na mão, as expedições levam mais carga e lucro (veja Cartas).</p>';
  return `${vcTxt}${anyBack ? '<button type="button" class="primary" data-collect-all>Receber tudo</button>' : ''}
    <ul class="items">${cards}</ul>${streak}
    <button type="button" class="primary" data-new-exp ${idle.length ? '' : 'disabled'}>${idle.length ? 'Nova expedição' : 'Nenhum veículo livre'}</button>
    ${demandBox(ctx, s)}
    <p class="hint">A Barraca continua sempre aberta: venda na hora, sem risco. Na expedição o preço é maior, mas há chance de perder parte da carga. Quando o veículo volta, ele espera você clicar em Receber; a repetição automática sai sozinha com os mesmos produtos e também fica guardada.</p>`;
}

function demandBox(ctx: GarageCtx, s: FarmState): string {
  const row = (d: Record<string, string[]>) => ROUTES.filter((r) => d[r.id]).map((r) => `<li><span><strong>${ctx.esc(r.name_pt)}</strong><small>${d[r.id].map((p) => ctx.esc(itemInfo(p).name_pt)).join(', ')}</small></span></li>`).join('');
  return `<h3>Demanda do dia (+${Math.round(EXP.daily_demand.bonus * 100)}%)</h3><ul class="items compact">${row(s.demand)}</ul>
    ${s.demand_tomorrow ? `<h3>Demanda de amanhã</h3><ul class="items compact">${row(s.demand_tomorrow)}</ul>` : ''}`;
}

/** tudo o que a tela de nova expedição precisa calcular (usado no desenho e na atualização parcial do − / +) */
function plan(s: FarmState) {
  const now = store.clock.farmNow();
  const owned = s.vehicles.filter((v) => vehicleStatus(s, v, now).status === 'idle');
  form.vehicles = form.vehicles.filter((id) => owned.some((v) => v.vehicle_id === id));
  if (!form.vehicles.length && owned.length) form.vehicles = [(owned.find((v) => v.active) ?? owned[0]).vehicle_id];
  const sel = form.vehicles.map((id) => s.vehicles.find((v) => v.vehicle_id === id)!);
  const lead = form.manager && s.lead?.available ? s.lead : null;
  const routes = ROUTES.filter((r) => r.unlock_level <= s.level && sel.every((v) => canReach(v.vehicle_id, r.id)));
  if (!routes.some((r) => r.id === form.route)) form.route = routes[routes.length - 1]?.id ?? 'feira';
  const caps = sel.map((v, i) => capacity(v, mult(v.rarity), lead && i < lead.vehicles ? lead : null));
  const totalCap = caps.reduce((a, b) => a + b, 0);
  for (const k of Object.keys(form.cargo)) if (!s.silo[k]) delete form.cargo[k];
  const used = Object.values(form.cargo).reduce((a, b) => a + b, 0);
  const demand = s.demand[form.route] ?? [];
  const value = cargoValue(form.cargo, form.route, demand);
  const parts = splitCargo(form.cargo, caps);
  const ins = form.insurance ? parts.reduce((a, p, i) => a + insuranceCost(cargoValue(p, form.route, demand), form.route, lead && i < lead.vehicles ? lead : null), 0) : 0;
  const chances = sel.map((v, i) => tripChance({ v, mult: mult(v.rarity), route: form.route, lead: lead && i < lead.vehicles ? lead : null, minigamePts: 0, expSuccess: s.fx.exp_success ?? 0, failStreak: s.exp_fail_streak }));
  const hours = sel.map((v, i) => tripHours(v, mult(v.rarity), form.route, lead && i < lead.vehicles ? lead : null, s.fx.exp_duration ?? 0));
  const problems: string[] = [];
  if (!sel.length) problems.push('Escolha pelo menos 1 veículo.');
  if (!routes.length) problems.push('Nenhum destino liberado para esses veículos.');
  if (used === 0) problems.push('Coloque algo na carga.');
  if (used > totalCap) problems.push(`A carga (${used}) passa da capacidade (${totalCap}).`);
  if (parts.some((p) => Object.keys(p).length === 0) && used > 0) problems.push('Sobrou veículo sem carga: leve mais ou mande menos veículos.');
  if (ins > s.gold) problems.push('Falta ouro para o seguro.');
  return { owned, sel, lead, routes, caps, totalCap, used, demand, value, ins, chances, hours, problems };
}

/** barra de carga + resumo + botão (atualizados sem redesenhar a tela inteira) */
/** barra de carga: enche em tempo real; amarela quando lota, vermelha se passar */
function cargoBar(p: ReturnType<typeof plan>): string {
  const full = p.used >= p.totalCap && p.totalCap > 0, over = p.used > p.totalCap;
  const pctFill = p.totalCap ? Math.min(100, (p.used / p.totalCap) * 100) : 0;
  return `<div class="cargo-bar ${over ? 'over' : full ? 'full' : ''}"><span style="width:${pctFill}%"></span><b>Carga: ${p.used}/${p.totalCap}</b></div>`;
}

function summaryHtml(ctx: GarageCtx, s: FarmState, p: ReturnType<typeof plan>): string {
  const ch = p.chances.length ? p.chances.reduce((a, b) => a + b, 0) / p.chances.length : 0;
  const h = p.hours.length ? Math.max(...p.hours) : 0;
  return `<div class="exp-sum"><span>Valor no destino <strong>${formatGold(p.value)}</strong></span><span>Chance <strong>${pct(ch)}</strong></span><span>Volta em <strong>${duration(h * 3600)}</strong></span>
      ${p.ins ? `<span>Seguro <strong>${formatGold(p.ins)}</strong></span>` : ''}</div>
    ${p.problems.length ? `<ul class="problems">${p.problems.map((x) => `<li>${ctx.esc(x)}</li>`).join('')}</ul>` : ''}
    <button type="button" class="primary go-btn" data-go ${p.problems.length ? 'disabled' : ''}>Iniciar Expedição</button>`;
}

function formView(ctx: GarageCtx, s: FarmState): string {
  const p = plan(s);
  const r = ROUTE_BY_ID[form.route];
  // veículos: cartões que ligam/desligam (comboio quando há mais de um)
  const vehs = p.owned.map((v) => `<button type="button" class="veh-chip ${form.vehicles.includes(v.vehicle_id) ? 'on' : ''}" data-veh="${v.vehicle_id}" aria-pressed="${form.vehicles.includes(v.vehicle_id)}">
      ${vehSprite(ctx, v, 0.5)}<span>${ctx.esc(vehName(v.vehicle_id))}<small>${capacity(v, mult(v.rarity))} de carga</small></span></button>`).join('');
  // mapa: estrada pontilhada da fazenda passando por todos os destinos; o escolhido brilha
  const order = ['fazenda', ...ROUTES.map((x) => x.id)];
  const road = order.map((id, i) => `${i ? 'L' : 'M'}${MAP_PINS[id].x} ${MAP_PINS[id].y * 0.6}`).join(' ');
  const pins = ROUTES.map((x) => {
    const pin = MAP_PINS[x.id] ?? { x: 50, y: 50, icon: '📍' };
    const ok = p.routes.some((y) => y.id === x.id);
    const why = x.unlock_level > s.level ? `nível ${x.unlock_level}` : !ok ? 'veículo não alcança' : '';
    return `<button type="button" class="map-pin ${x.id === form.route ? 'on' : ''} ${ok ? '' : 'locked'}" style="left:${pin.x}%;top:${pin.y}%" data-route="${x.id}" ${ok ? '' : 'aria-disabled="true"'} aria-label="${ctx.esc(x.name_pt)}">
      <span class="pin-ico">${ok ? pin.icon : '🔒'}</span><span class="pin-name">${ctx.esc(x.name_pt)}${why ? ` · ${why}` : ''}</span></button>`;
  }).join('');
  const home = MAP_PINS.fazenda;
  // carga: ícone, nome, preço no destino, − quantidade + e MÁX
  const items = sellable(s.silo);
  const cargoRows = items.map(([k, q]) => {
    const info = itemInfo(k), dem = p.demand.includes(k), n = form.cargo[k] ?? 0;
    return `<li class="cargo-row">${ctx.itemIcon(k)}<span><strong>${ctx.esc(info.name_pt)}${dem ? ' <span class="shield" style="--c:#4CAF50">+20%</span>' : ''}</strong>
      <small>${q} no Silo · ${nf1.format(info.price * r.price_multiplier * (dem ? 1 + EXP.daily_demand.bonus : 1))} cada no destino</small></span>
      <span class="qty-btns"><button type="button" class="qbtn" data-dec="${k}" aria-label="Menos ${ctx.esc(info.name_pt)}">−</button>
        <b class="qnum" data-qty="${k}">${n}</b>
        <button type="button" class="qbtn" data-inc="${k}" aria-label="Mais ${ctx.esc(info.name_pt)}">+</button>
        <button type="button" class="qbtn max" data-max="${k}">MÁX</button></span></li>`;
  }).join('');
  const leadOpt = s.lead ? `<label class="toggle"><input type="checkbox" data-opt="manager" ${form.manager ? 'checked' : ''} ${s.lead.available ? '' : 'disabled'}><span>Gerente conduz <small>+${nf1.format(s.lead.success_pts)} pontos, −${Math.round((1 - s.lead.duration_mult) * 100)}% de tempo${s.lead.available ? '' : ' · indisponível'}</small></span></label>` : '';
  return `<button type="button" class="secondary" data-back>← Garagem</button>
    <div class="veh-chips">${vehs}</div>
    <div class="route-map"><svg viewBox="0 0 100 60" preserveAspectRatio="none" aria-hidden="true"><path d="${road}" class="map-road"/></svg>
      <span class="map-home" style="left:${home.x}%;top:${home.y}%">${home.icon}<small>Fazenda</small></span>${pins}<div class="map-tip" hidden></div></div>
    <h3>Carga</h3><div class="cargo-bar-box">${cargoBar(p)}</div>
    ${items.length ? `<button type="button" class="secondary small" data-fill>Encher com o que vale mais</button><button type="button" class="secondary small" data-clear>Esvaziar</button><ul class="items cargo-list">${cargoRows}</ul>` : '<p class="empty">O Silo está vazio.</p>'}
    <div class="exp-opts">
      <label class="toggle"><input type="checkbox" data-opt="insurance" ${form.insurance ? 'checked' : ''} ${r.insurance_pct === null ? 'disabled' : ''}><span>Seguro <small>${r.insurance_pct === null ? 'não existe na Feira' : `${nf1.format(r.insurance_pct)}% da carga; devolve a perda acima de ${Math.round(EXP.insurance_deductible * 100)}%`}</small></span></label>
      ${leadOpt}
      <label class="toggle"><input type="checkbox" data-opt="repeat" ${form.repeat ? 'checked' : ''}><span>Repetir sozinho <small>até ${EXP.auto_repeat_max}× com os mesmos produtos</small></span></label></div>
    <div class="exp-summary">${summaryHtml(ctx, s, p)}</div>`;
}

/** tooltip do destino: duração, preço, risco e achados */
function routeTip(ctx: GarageCtx, s: FarmState, id: string): string {
  const r = ROUTE_BY_ID[id];
  const sel = form.vehicles.map((v) => s.vehicles.find((x) => x.vehicle_id === v)!).filter(Boolean);
  const h = sel.length ? Math.max(...sel.map((v) => tripHours(v, mult(v.rarity), id, null, s.fx.exp_duration ?? 0))) : r.hours;
  const dem = (s.demand[id] ?? []).map((k) => itemInfo(k).name_pt).join(', ');
  return `<strong>${ctx.esc(r.name_pt)}</strong><small>${r.unlock_level > s.level ? `Libera no nível ${r.unlock_level}` : `Volta em ${duration(h * 3600)}`}</small>
    <p>Preço ×${nf1.format(r.price_multiplier)} · chance base ${pct(r.success)}</p>
    <p class="bad">Se falhar: perde ${pct(r.loss[0])} a ${pct(r.loss[1])} da carga</p>
    <p class="next">Achados: item ${pct(r.item_chance)} · Kit ${pct(r.kit_chance)}${r.deed_chance ? ` · Escritura ${pct(r.deed_chance)}` : ''}</p>
    ${dem ? `<p>Demanda do dia (+${Math.round(EXP.daily_demand.bonus * 100)}%): ${ctx.esc(dem)}</p>` : ''}`;
}

function reportView(ctx: GarageCtx): string {
  const rows = lastReport.map((t) => {
    const o = OUTCOME[t.outcome];
    const back = Object.entries(t.cargo_back).filter(([, q]) => q > 0).map(([k, q]) => `${q} ${itemInfo(k).name_pt}`).join(', ');
    return `<li>${ctx.sprite(o.icon, 1)}<span><strong>${ctx.esc(vehName(t.vehicle_id))} · ${ctx.esc(ROUTE_BY_ID[t.route_id].name_pt)}${t.seq ? ` (repetição ${t.seq})` : ''} · ${o.text}</strong>
      <small>${ctx.esc(t.report)}</small>
      <small>${t.gold ? `+${formatGold(t.gold)} ouro` : 'sem venda'}${t.refund ? ` · seguro devolveu ${formatGold(t.refund)}` : ''}${back ? ` · voltou ao Silo: ${ctx.esc(back)}` : ''} · chance ${pct(t.chance)}</small>
      ${t.drops.length ? `<small>Achados: ${t.drops.map((d) => `<span style="color:${dropColor(d)}">${ctx.esc(dropName(d))}</span>`).join(', ')}</small>` : ''}</span></li>`;
  }).join('');
  const total = lastReport.reduce((a, t) => a + t.gold + t.refund, 0);
  return `<p>Total recebido: <strong>${formatGold(total)} ouro</strong></p><ul class="items">${rows}</ul><button type="button" class="primary" data-back>← Garagem</button>`;
}

function bind(ctx: GarageCtx, el: HTMLElement): void {
  el.querySelector('.game-panel')?.classList.toggle('exp-panel', view === 'form');
  const rerender = () => openGarage(ctx, view === 'form' ? 'form' : 'garage');
  el.querySelectorAll<HTMLButtonElement>('[data-active-veh]').forEach((b) => b.addEventListener('click', () => { b.disabled = true; void ctx.act(() => setActiveVehicle(b.dataset.activeVeh!)); }));
  const collect = async (v: string | null) => {
    try {
      const after = await collectExpeditions(v);
      lastReport = after.collected ?? [];
      applyState(after);
      view = 'report';
      ctx.show('Relatório da viagem', () => body(ctx), (e) => bind(ctx, e));
    } catch (e) { ctx.toast(e instanceof Error ? e.message : 'Não deu certo.'); }
  };
  el.querySelectorAll<HTMLButtonElement>('[data-collect]').forEach((b) => b.addEventListener('click', () => { b.disabled = true; void collect(b.dataset.collect!); }));
  el.querySelector<HTMLButtonElement>('[data-collect-all]')?.addEventListener('click', () => void collect(null));
  el.querySelector('[data-new-exp]')?.addEventListener('click', () => { view = 'form'; rerender(); });
  el.querySelector('[data-back]')?.addEventListener('click', () => { view = 'garage'; openGarage(ctx); });
  el.querySelectorAll<HTMLButtonElement>('[data-veh]').forEach((b) => b.addEventListener('click', () => {
    const id = b.dataset.veh!;
    form.vehicles = form.vehicles.includes(id) ? form.vehicles.filter((x) => x !== id) : [...form.vehicles, id];
    rerender();
  }));
  // mapa: clique escolhe o destino; o mouse mostra o tooltip
  const tip = el.querySelector<HTMLElement>('.map-tip');
  el.querySelectorAll<HTMLButtonElement>('[data-route]').forEach((b) => {
    const showTip = () => {
      if (!tip) return;
      tip.innerHTML = routeTip(ctx, store.state!, b.dataset.route!);
      tip.hidden = false;
      const left = Math.min(100 - 2, Math.max(2, parseFloat(b.style.left)));
      tip.style.left = `clamp(4px, calc(${left}% - 120px), calc(100% - 248px))`;
      tip.style.top = parseFloat(b.style.top) > 50 ? `calc(${b.style.top} - ${tip.offsetHeight + 34}px)` : `calc(${b.style.top} + 30px)`;
    };
    b.addEventListener('mouseenter', showTip); b.addEventListener('focus', showTip);
    b.addEventListener('mouseleave', () => { if (tip) tip.hidden = true; });
    b.addEventListener('blur', () => { if (tip) tip.hidden = true; });
    b.addEventListener('click', () => { if (b.getAttribute('aria-disabled')) { showTip(); return; } form.route = b.dataset.route!; rerender(); });
  });
  // carga: − / + (segurar repete, cada vez mais rápido) e MÁX; atualiza só os números, a barra e o resumo
  const refresh = () => {
    const s = store.state!, p = plan(s);
    el.querySelectorAll<HTMLElement>('[data-qty]').forEach((q) => { q.textContent = String(form.cargo[q.dataset.qty!] ?? 0); });
    const bar = el.querySelector<HTMLElement>('.cargo-bar-box');
    if (bar) bar.innerHTML = cargoBar(p);
    const box = el.querySelector<HTMLElement>('.exp-summary');
    if (box) { box.innerHTML = summaryHtml(ctx, s, p); box.querySelector<HTMLButtonElement>('[data-go]')?.addEventListener('click', (e) => { (e.currentTarget as HTMLButtonElement).disabled = true; void go(ctx); }); }
  };
  const change = (k: string, d: number) => {
    const s = store.state!, p = plan(s);
    const have = s.silo[k] ?? 0, cur = form.cargo[k] ?? 0;
    const room = Math.max(0, p.totalCap - p.used);
    const next = Math.max(0, Math.min(have, d > 0 ? cur + Math.min(d, room) : cur + d));
    if (next) form.cargo[k] = next; else delete form.cargo[k];
    refresh();
  };
  const hold = (b: HTMLButtonElement, k: string, d: number) => {
    let timer = 0, n = 0;
    const stop = () => { window.clearTimeout(timer); };
    const tick = () => { change(k, d * (n > 12 ? 10 : n > 5 ? 5 : 1)); n++; timer = window.setTimeout(tick, n === 1 ? 350 : 80); };
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); n = 0; tick(); });
    ['pointerup', 'pointerleave', 'pointercancel'].forEach((ev) => b.addEventListener(ev, stop));
    b.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); change(k, d); } });
  };
  el.querySelectorAll<HTMLButtonElement>('[data-inc]').forEach((b) => hold(b, b.dataset.inc!, 1));
  el.querySelectorAll<HTMLButtonElement>('[data-dec]').forEach((b) => hold(b, b.dataset.dec!, -1));
  el.querySelectorAll<HTMLButtonElement>('[data-max]').forEach((b) => b.addEventListener('click', () => change(b.dataset.max!, 1e9)));
  el.querySelector('[data-clear]')?.addEventListener('click', () => { form.cargo = {}; refresh(); });
  el.querySelectorAll<HTMLInputElement>('[data-opt]').forEach((i) => i.addEventListener('change', () => { (form as unknown as Record<string, boolean>)[i.dataset.opt!] = i.checked; rerender(); }));
  el.querySelector('[data-fill]')?.addEventListener('click', () => { fill(); refresh(); });
  el.querySelector<HTMLButtonElement>('[data-go]')?.addEventListener('click', (e) => { (e.currentTarget as HTMLButtonElement).disabled = true; void go(ctx); });
}

/** enche os veículos com o que vale mais na rota (demanda primeiro) */
function fill(): void {
  const s = store.state!;
  const sel = form.vehicles.map((id) => s.vehicles.find((v) => v.vehicle_id === id)!) as VehicleState[];
  const lead = form.manager && s.lead?.available ? s.lead : null;
  let left = sel.reduce((a, v, i) => a + capacity(v, mult(v.rarity), lead && i < lead.vehicles ? lead : null), 0);
  const demand = s.demand[form.route] ?? [];
  const items = sellable(s.silo).sort((a, b) => cargoValue({ [b[0]]: 1 }, form.route, demand) - cargoValue({ [a[0]]: 1 }, form.route, demand));
  form.cargo = {};
  for (const [k, q] of items) { if (left <= 0) break; const take = Math.min(q, left); form.cargo[k] = take; left -= take; }
}

// ---------- partida (v3: sem minigame) ----------
/** a expedição sai direto: a tela some devagar e o veículo começa a andar sozinho pela estrada no mapa */
async function go(ctx: GarageCtx): Promise<void> {
  const s = store.state!;
  const manager = form.manager && !!s.lead?.available;
  try {
    const after = await launchExpedition({ minigame: null, keys: [], vehicles: form.vehicles, route: form.route, cargo: form.cargo, insurance: form.insurance, manager, repeat: form.repeat });
    form.cargo = {};
    view = 'garage';
    const panel = document.querySelector<HTMLElement>('.game-panel');
    panel?.classList.add('fade-out');
    window.setTimeout(() => { ctx.close(); applyState(after); ctx.toast(`Expedição saiu para ${ROUTE_BY_ID[form.route].name_pt}!`, 4); }, 260);
  } catch (e) { ctx.toast(e instanceof Error ? e.message : 'Não deu certo.'); view = 'form'; openGarage(ctx, 'form'); }
}
