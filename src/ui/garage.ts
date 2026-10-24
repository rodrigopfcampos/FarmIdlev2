// Garagem (fase 5): veículos, nova expedição (carga, rota, seguro, Gerente, comboio), minigame de setas,
// viagens em andamento e o botão Receber com o relatório narrado. O servidor confere e sorteia tudo.
import { EQUIP_CARDS, EQUIP_RARITIES, EXP, RARITIES, RARITY_BY_ID, ROUTES, ROUTE_BY_ID, VEHICLES, VEHICLE_BY_ID, itemInfo } from '../data';
import {
  canReach, capacity, cargoValue, evalMinigame, insuranceCost, rarityMult, sellable, splitCargo, tripChance, tripHours, vehicleStatus,
} from '../farm/expeditions';
import { applyState, store } from '../farm/store';
import {
  buyVehicle, collectExpeditions, launchExpedition, setActiveVehicle, startMinigame,
  type CollectedTrip, type FarmState, type MinigameStart, type VehicleState,
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
const ARROW: Record<string, string> = { up: '↑', down: '↓', left: '←', right: '→' };
const KEYMAP: Record<string, string> = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', w: 'up', s: 'down', a: 'left', d: 'right', W: 'up', S: 'down', A: 'left', D: 'right' };
const RESULT_TEXT: Record<string, string> = { perfect: 'Perfeita! +3 pontos', done: 'Concluída', incomplete: 'Incompleta: −5 pontos', failed: 'Falhou: −10 pontos' };
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
const vehSprite = (ctx: GarageCtx, v: { vehicle_id: string; rarity: string }, scale = 1, cls = '') => ctx.sprite(`vehicle_${v.vehicle_id}_${v.rarity}`, scale, cls);

// ---------- estado da tela ----------
type Form = { vehicles: string[]; route: string; cargo: Record<string, number>; insurance: boolean; manager: boolean; repeat: boolean; calm: boolean };
let view: 'garage' | 'form' | 'report' = 'garage';
let form: Form = { vehicles: [], route: 'feira', cargo: {}, insurance: false, manager: false, repeat: true, calm: false };
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
      const why = d.unlock_level > s.level ? `nível ${d.unlock_level}` : s.gold < d.cost ? `falta ${formatGold(d.cost - s.gold)} de ouro` : '';
      return `<li class="veh locked">${ctx.sprite(`vehicle_${d.id}_common`, 1, 'silhouette')}<span><strong>${ctx.esc(d.name_pt)}</strong>
        <small>${d.capacity} unid. · duração ×${nf1.format(d.duration_multiplier)} · +${d.safety_pts} pontos · até ${ctx.esc(ROUTE_BY_ID[d.max_route].name_pt)}</small>
        <small>Nível ${d.unlock_level} · ${formatGold(d.cost)} ouro</small></span>
        <span class="btns"><button type="button" class="secondary" data-buy-veh="${d.id}" ${why ? 'disabled' : ''}>${why ? ctx.esc(why) : `Comprar · ${formatGold(d.cost)}`}</button></span></li>`;
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
    return `<li class="veh ${v.active ? 'active-pet' : ''}">${vehSprite(ctx, v)}<span><strong>${ctx.esc(d.name_pt)} <span class="shield" style="--c:${r.color_hex}">${ctx.esc(r.name_pt)}</span></strong>
      <small>${capacity(v, m)} unid. · duração ×${nf1.format(d.duration_multiplier / m)} · +${nf1.format(d.safety_pts * m)} pontos · até ${ctx.esc(ROUTE_BY_ID[d.max_route].name_pt)}</small>
      <span class="energy dura ${v.durability < EXP.low_wear_threshold_pct ? 'low' : ''}" title="Durabilidade ${nf1.format(v.durability)}"><span style="width:${Math.round(v.durability)}%"></span></span>
      <small>${ctx.esc(status)}${v.durability < EXP.low_wear_threshold_pct ? ' · <span class="bad">desgastado: −5 pontos (conserte na Forja)</span>' : ''}</small></span>
      <span class="btns">${backN ? `<button type="button" class="primary small" data-collect="${v.vehicle_id}">Receber</button>` : ''}
      ${!v.active ? `<button type="button" class="secondary" data-active-veh="${v.vehicle_id}">Deixar na vaga</button>` : ''}</span></li>`;
  }).join('');
  const idle = s.vehicles.filter((v) => vehicleStatus(s, v, now).status === 'idle');
  const streak = s.exp_fail_streak >= EXP.bad_luck_protection.after_failures
    ? `<p class="hint good">Garantia contra azar: a próxima expedição sai com +${EXP.bad_luck_protection.bonus_pts} pontos.</p>` : '';
  return `${anyBack ? '<button type="button" class="primary" data-collect-all>Receber tudo</button>' : ''}
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

function formView(ctx: GarageCtx, s: FarmState): string {
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
  const items = sellable(s.silo);
  for (const k of Object.keys(form.cargo)) if (!s.silo[k]) delete form.cargo[k];
  const used = Object.values(form.cargo).reduce((a, b) => a + b, 0);
  const demand = s.demand[form.route] ?? [];
  const value = cargoValue(form.cargo, form.route, demand);
  const parts = splitCargo(form.cargo, caps);
  const ins = form.insurance ? parts.reduce((a, p, i) => a + insuranceCost(cargoValue(p, form.route, demand), form.route, lead && i < lead.vehicles ? lead : null), 0) : 0;
  const preview = sel.map((v, i) => {
    const l = lead && i < lead.vehicles ? lead : null;
    const ch = tripChance({ v, mult: mult(v.rarity), route: form.route, lead: l, minigamePts: 0, expSuccess: s.fx.exp_success ?? 0, failStreak: s.exp_fail_streak });
    return `<li>${vehSprite(ctx, v, 0.75)}<span><strong>${ctx.esc(vehName(v.vehicle_id))}${l ? ' · Gerente conduz' : ''}</strong>
      <small>${caps[i]} unid. · ${duration(tripHours(v, mult(v.rarity), form.route, l, s.fx.exp_duration ?? 0) * 3600)} · chance ${pct(ch)} (minigame Concluída)</small></span></li>`;
  }).join('');
  const r = ROUTE_BY_ID[form.route];
  const vehChecks = owned.map((v) => `<label class="check"><input type="checkbox" data-veh="${v.vehicle_id}" ${form.vehicles.includes(v.vehicle_id) ? 'checked' : ''}> ${ctx.esc(vehName(v.vehicle_id))} (${capacity(v, mult(v.rarity))})</label>`).join('');
  const cargoRows = items.map(([k, q]) => {
    const info = itemInfo(k);
    const dem = demand.includes(k);
    return `<li>${ctx.itemIcon(k)}<span><strong>${ctx.esc(info.name_pt)}${dem ? ' <span class="shield" style="--c:#4CAF50">demanda +20%</span>' : ''}</strong>
      <small>${q} no Silo · ${nf1.format(info.price * r.price_multiplier * (dem ? 1 + EXP.daily_demand.bonus : 1))} cada na rota (Barraca ${nf1.format(info.price * (s.fx.stall_ratio ?? 0.7))})</small></span>
      <span class="btns"><input type="number" class="qty" min="0" max="${q}" step="1" value="${form.cargo[k] ?? 0}" data-cargo="${k}" aria-label="Quantidade de ${ctx.esc(info.name_pt)}"></span></li>`;
  }).join('');
  const problems: string[] = [];
  if (!sel.length) problems.push('Escolha pelo menos 1 veículo.');
  if (!routes.length) problems.push('Nenhuma rota liberada para esses veículos.');
  if (used === 0) problems.push('Escolha o que levar.');
  if (used > totalCap) problems.push(`A carga (${used}) passa da capacidade (${totalCap}).`);
  if (parts.some((p) => Object.keys(p).length === 0) && used > 0) problems.push('Sobrou veículo sem carga: leve mais ou mande menos veículos.');
  if (ins > s.gold) problems.push('Falta ouro para o seguro.');
  const leadOpt = s.lead ? `<label class="check"><input type="checkbox" data-opt="manager" ${form.manager ? 'checked' : ''} ${s.lead.available ? '' : 'disabled'}> Gerente conduz (+${nf1.format(s.lead.success_pts)} pontos, −${Math.round((1 - s.lead.duration_mult) * 100)}% de duração, +1 s no minigame${s.lead.available ? '' : ' · indisponível agora'}; ele sai do campo até voltar)</label>` : '';
  return `<button type="button" class="secondary" data-back>← Garagem</button>
    <h3>Veículos</h3><div class="checks">${vehChecks}</div>${sel.length > 1 ? `<p class="hint">Comboio: 1 minigame só, com +${EXP.minigame.convoy_extra_arrows} setas e +${nf1.format(EXP.minigame.convoy_extra_seconds)} s por veículo extra.</p>` : ''}
    <h3>Rota</h3><div class="chips" role="tablist">${routes.map((x) => `<button type="button" role="tab" data-route="${x.id}" aria-selected="${x.id === form.route}">${ctx.esc(x.name_pt)}</button>`).join('')}</div>
    <p class="hint">${ctx.esc(r.name_pt)}: preço ×${nf1.format(r.price_multiplier)} · chance base ${pct(r.success)} · se falhar perde ${pct(r.loss[0])} a ${pct(r.loss[1])} (o resto volta) · item ${pct(r.item_chance)}${r.deed_chance ? ` · Escritura ${pct(r.deed_chance)}` : ''} · Kit ${pct(r.kit_chance)}</p>
    <h3>Carga (${used} de ${totalCap})</h3>
    ${items.length ? `<button type="button" class="secondary" data-fill>Encher com o que vale mais</button><ul class="items">${cargoRows}</ul>` : '<p class="empty">O Silo está vazio.</p>'}
    <h3>Opções</h3><div class="checks">
      <label class="check"><input type="checkbox" data-opt="insurance" ${form.insurance ? 'checked' : ''} ${r.insurance_pct === null ? 'disabled' : ''}> Seguro${r.insurance_pct === null ? ' (não existe na Feira da Vila)' : ` · ${nf1.format(r.insurance_pct)}% da carga = ${formatGold(ins)}: se falhar, devolve a perda acima de ${Math.round(EXP.insurance_deductible * 100)}%`}</label>
      ${leadOpt}
      <label class="check"><input type="checkbox" data-opt="repeat" ${form.repeat ? 'checked' : ''}> Repetir até ${EXP.auto_repeat_max}× sozinho com os mesmos produtos (fica guardado até Receber)</label>
      <label class="check"><input type="checkbox" data-opt="calm" ${form.calm ? 'checked' : ''}> Modo calmo: +50% de tempo no minigame, sem o bônus de Perfeita</label></div>
    <ul class="items compact">${preview}</ul>
    <p>Valor da carga na rota: <strong>${formatGold(value)}</strong> (na Barraca: ${formatGold(Object.entries(form.cargo).reduce((a, [k, q]) => a + q * itemInfo(k).price * (s.fx.stall_ratio ?? 0.7), 0))})</p>
    ${problems.length ? `<ul class="problems">${problems.map((p) => `<li>${ctx.esc(p)}</li>`).join('')}</ul>` : ''}
    <button type="button" class="primary" data-go ${problems.length ? 'disabled' : ''}>Partir (minigame de setas)</button>`;
}

function reportView(ctx: GarageCtx): string {
  const rows = lastReport.map((t) => {
    const o = OUTCOME[t.outcome];
    const back = Object.entries(t.cargo_back).filter(([, q]) => q > 0).map(([k, q]) => `${q} ${itemInfo(k).name_pt}`).join(', ');
    return `<li>${ctx.sprite(o.icon, 1)}<span><strong>${ctx.esc(vehName(t.vehicle_id))} · ${ctx.esc(ROUTE_BY_ID[t.route_id].name_pt)}${t.seq ? ` (repetição ${t.seq})` : ''} · ${o.text}</strong>
      <small>${ctx.esc(t.report)}</small>
      <small>${t.gold ? `+${formatGold(t.gold)} ouro` : 'sem venda'}${t.refund ? ` · seguro devolveu ${formatGold(t.refund)}` : ''}${back ? ` · voltou ao Silo: ${ctx.esc(back)}` : ''} · minigame ${ctx.esc(RESULT_TEXT[t.minigame] ?? t.minigame)} · chance ${pct(t.chance)}</small>
      ${t.drops.length ? `<small>Achados: ${t.drops.map((d) => `<span style="color:${dropColor(d)}">${ctx.esc(dropName(d))}</span>`).join(', ')}</small>` : ''}</span></li>`;
  }).join('');
  const total = lastReport.reduce((a, t) => a + t.gold + t.refund, 0);
  return `<p>Total recebido: <strong>${formatGold(total)} ouro</strong></p><ul class="items">${rows}</ul><button type="button" class="primary" data-back>← Garagem</button>`;
}

function bind(ctx: GarageCtx, el: HTMLElement): void {
  const rerender = () => openGarage(ctx, view === 'form' ? 'form' : 'garage');
  el.querySelectorAll<HTMLButtonElement>('[data-buy-veh]').forEach((b) => b.addEventListener('click', () => { b.disabled = true; void ctx.act(() => buyVehicle(b.dataset.buyVeh!), `${vehName(b.dataset.buyVeh!)} comprado!`); }));
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
  el.querySelectorAll<HTMLInputElement>('[data-veh]').forEach((i) => i.addEventListener('change', () => {
    const id = i.dataset.veh!;
    form.vehicles = i.checked ? [...form.vehicles.filter((x) => x !== id), id] : form.vehicles.filter((x) => x !== id);
    rerender();
  }));
  el.querySelectorAll<HTMLButtonElement>('[data-route]').forEach((b) => b.addEventListener('click', () => { form.route = b.dataset.route!; rerender(); }));
  el.querySelectorAll<HTMLInputElement>('[data-cargo]').forEach((i) => i.addEventListener('change', () => {
    const q = Math.max(0, Math.min(Number(i.max), Math.floor(Number(i.value) || 0)));
    if (q) form.cargo[i.dataset.cargo!] = q; else delete form.cargo[i.dataset.cargo!];
    rerender();
  }));
  el.querySelectorAll<HTMLInputElement>('[data-opt]').forEach((i) => i.addEventListener('change', () => { (form as unknown as Record<string, boolean>)[i.dataset.opt!] = i.checked; rerender(); }));
  el.querySelector('[data-fill]')?.addEventListener('click', () => { fill(); rerender(); });
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

// ---------- minigame ----------
async function go(ctx: GarageCtx): Promise<void> {
  const s = store.state!;
  const manager = form.manager && !!s.lead?.available;
  let mg: MinigameStart;
  try { mg = await startMinigame(form.route, form.vehicles.length, manager, form.calm); } catch (e) { ctx.toast(e instanceof Error ? e.message : 'Não deu certo.'); openGarage(ctx, 'form'); return; }
  const keys: { k: string; t: number }[] = [];
  const t0 = performance.now();
  let pos = 0, penalty = 0, done = false, timer = 0;
  const finish = async () => {
    if (done) return;
    done = true;
    window.clearInterval(timer);
    document.removeEventListener('keydown', onKey);
    const local = evalMinigame(mg.arrows, keys, mg.limit_ms, form.calm);
    try {
      const after = await launchExpedition({ minigame: mg.id, keys, vehicles: form.vehicles, route: form.route, cargo: form.cargo, insurance: form.insurance, manager, repeat: form.repeat });
      applyState(after);
      const res = after.minigame?.result ?? local.result;
      ctx.toast(`Expedição saiu! Minigame: ${RESULT_TEXT[res]}.`, 5);
      form.cargo = {};
      view = 'garage';
      openGarage(ctx);
    } catch (e) { ctx.toast(e instanceof Error ? e.message : 'Não deu certo.'); view = 'form'; openGarage(ctx, 'form'); }
  };
  const press = (k: string) => {
    if (done) return;
    const t = Math.round(performance.now() - t0);
    keys.push({ k, t });
    const box = document.querySelector<HTMLElement>('.minigame');
    if (k === mg.arrows[pos]) { pos++; } else { penalty += EXP.minigame.wrong_key_penalty_s * 1000; box?.classList.remove('shake'); void box?.offsetWidth; box?.classList.add('shake'); }
    paint();
    if (pos >= mg.arrows.length) void finish();
  };
  const onKey = (e: KeyboardEvent) => { const k = KEYMAP[e.key]; if (k) { e.preventDefault(); press(k); } };
  const paint = () => {
    const el = document.querySelector<HTMLElement>('.minigame');
    if (!el) { void finish(); return; } // painel fechado no meio: sai com o que foi feito
    const left = Math.max(0, mg.limit_ms - (performance.now() - t0) - penalty);
    el.querySelector<HTMLElement>('.mg-time span')!.style.width = `${(left / mg.limit_ms) * 100}%`;
    el.querySelectorAll<HTMLElement>('.mg-arrow').forEach((a, i) => { a.classList.toggle('ok', i < pos); a.classList.toggle('now', i === pos); });
    if (left <= 0) void finish();
  };
  ctx.show('Partida', () => `<div class="minigame">
      <p>Repita as setas antes do tempo acabar (teclado: setas ou WASD).</p>
      <div class="mg-arrows">${mg.arrows.map((a) => `<span class="mg-arrow">${ARROW[a]}</span>`).join('')}</div>
      <div class="mg-time"><span></span></div>
      <div class="mg-pad">${['up', 'left', 'down', 'right'].map((k) => `<button type="button" class="secondary" data-k="${k}" aria-label="${k}">${ARROW[k]}</button>`).join('')}</div>
    </div>`, (el) => {
    el.querySelectorAll<HTMLButtonElement>('[data-k]').forEach((b) => b.addEventListener('pointerdown', (e) => { e.preventDefault(); press(b.dataset.k!); }));
    // fechar no meio: a expedição sai com o que foi feito
    el.querySelector('.close')?.addEventListener('click', () => void finish());
  });
  document.addEventListener('keydown', onKey);
  timer = window.setInterval(paint, 50);
  paint();
}
