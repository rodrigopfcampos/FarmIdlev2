// Casa, Barraca e Forja: Silo e itens, equipe (campo/banco/contratar), equipamentos e lanches, venda e ferramentas.
import { CHARS, CLASSES, CROPS, itemInfo, LEVELS, RARITY_BY_ID, SNACKS } from '../data';
import { iconSprite } from '../farm/art';
import { hireCost, hoursToNext, rareSeeds } from '../farm/rules';
import { store } from '../farm/store';
import { buySnack, carePet, type CharacterState, equipSnack, type FarmState, hire, paySalaries, repairTool, sellAtStall, setAutoSell, setSlot } from '../net/farmApi';
import { openForge } from './forge-ui';
import { formatGold } from './format';
import { act, charPortrait, charSprite, className, DUR, esc, itemIcon, matDef, nextToolTier, nf1, pct, rerender, salesMult, show, sprite, stallRatio, toolArt, toolCard, toolLevel } from './panel';
import { petName, petsTab, takeFind } from './pets-ui';

// ---------- zonas ----------
export function siloItems(withSell: boolean): string {
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

export function bindSell(el: HTMLElement): void {
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
export function charStatus(c: CharacterState): string {
  if (!c.active && c.unpaid_days > 0) return `<span class="bad">Parado: ${c.unpaid_days} dias sem salário</span>`;
  const parts: string[] = [];
  if (c.slot === 'bench') parts.push(c.energy >= c.energy_max ? 'Descansado, no banco' : 'Descansando no banco');
  else if (c.parked) parts.push(`Sem energia: descansa até ${CHARS.energy.parked_until}`);
  else parts.push('Em campo');
  if (c.debt > 0) parts.push(`<span class="bad">Desmotivado (−${pct(1 - CHARS.salary.unpaid_efficiency)}): deve ${formatGold(c.debt)}</span>`);
  return parts.join(' · ');
}

export function energyBar(c: CharacterState): string {
  const p = Math.round((c.energy / c.energy_max) * 100);
  return `<span class="energy" role="progressbar" aria-label="Energia" aria-valuenow="${p}" aria-valuemin="0" aria-valuemax="100" title="Energia ${nf1.format(c.energy)} de ${nf1.format(c.energy_max)}"><span style="width:${p}%"></span></span>`;
}

export function charCard(c: CharacterState, s: FarmState): string {
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

export function operatorsTab(s: FarmState): string {
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
export function charChips(s: FarmState, sel: string): string {
  return `<div class="chips" role="tablist">${s.characters.map((c) => `<button type="button" role="tab" data-pick-char="${c.class_id}" aria-selected="${c.class_id === sel}">${charSprite(c.class_id, 0.5)}${esc(className(c.class_id))}</button>`).join('')}</div>`;
}

export function equipmentTab(s: FarmState, sel: string): string {
  const c = s.characters.find((x) => x.class_id === sel) ?? s.characters[0];
  const tc = toolCard(c.class_id);
  const m = matDef(c.material);
  const low = c.durability < DUR.low_durability_threshold;
  const repair = Math.round(m.repair_cost_gold * (1 + s.fx.tool_cost) * 100) / 100;
  const snack = c.snack_id ? SNACKS.find((x) => x.id === c.snack_id) : null;
  const owned = SNACKS.filter((x) => (s.inventory[x.id] ?? 0) > 0);
  return `${charChips(s, c.class_id)}
    <div class="char-card">${toolArt(c.class_id)}<div class="grow"><strong>${esc(tc.name_pt)} · nível ${toolLevel(m.id)} (×${nf1.format(m.work_capacity_multiplier)} de trabalho)</strong>
      <span class="energy dura ${low ? 'low' : ''}" title="Durabilidade ${nf1.format(c.durability)}"><span style="width:${Math.round(c.durability)}%"></span></span>
      <small>Durabilidade ${nf1.format(c.durability)} de ${DUR.max_durability} · perde ${nf1.format(DUR.loss_per_work_hour)} por hora de trabalho${low ? ` · <span class="bad">abaixo de ${DUR.low_durability_threshold}: trabalha a ${pct(DUR.low_durability_capacity_penalty_multiplier)}</span>` : ''}</small>
      <span class="btns"><button type="button" class="secondary" data-repair="${c.class_id}" ${c.durability >= 100 || s.gold < repair ? 'disabled' : ''}>Consertar · ${formatGold(repair)}</button>
</span>
      <small>${nextToolTier(s.level) ? `Melhora sozinha no nível ${nextToolTier(s.level)!.unlock_level} da fazenda.` : 'Ferramenta no nível máximo.'}</small></div></div>
    <div class="char-card">${snack ? sprite(snack.id, 1) : '<span class="px empty-box"></span>'}<div class="grow"><strong>Lanche</strong>
      <small>${snack ? `${esc(snack.name_pt)} × ${c.snack_qty} · +${snack.energy_restore} de energia, comido sozinho abaixo de ${snack.auto_trigger_below_energy_pct}%` : 'Vazio. Compre lanches na Barraca.'}</small>
      <span class="btns">${owned.map((x) => `<button type="button" class="secondary" data-equip="${x.id}">${esc(x.name_pt)} (${s.inventory[x.id]})</button>`).join('')}
      ${snack ? '<button type="button" class="secondary" data-unequip>Tirar</button>' : ''}</span></div></div>
`;
}

export function bindTeam(el: HTMLElement, pick: (cls: string) => void): void {
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
  el.querySelector('[data-forge]')?.addEventListener('click', () => openForge());

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

export function itemsList(s: FarmState): string {
  const rows: string[] = [];
  for (const x of SNACKS) if (s.inventory[x.id]) rows.push(`<li>${sprite(x.id, 1)}<span><strong>${esc(x.name_pt)}</strong><small>${s.inventory[x.id]} · +${x.energy_restore} de energia · ponha no espaço de lanche em Equipamentos</small></span></li>`);
  for (const r of rareSeeds(s.inventory)) {
    const t = RARITY_BY_ID[r.rarity];
    rows.push(`<li>${sprite(iconSprite(store.manifest, r.crop), 1)}<span><strong style="color:${t.color_hex}">Semente ${esc(t.name_pt)} de ${esc(CROPS[r.crop].name_pt)}</strong><small>${r.qty} · colheita ×${nf1.format(t.multiplier)} por 1 plantio · plante pelo ${CROPS[r.crop].kind === 'orchard' ? 'pomar' : 'canteiro'}</small></span></li>`);
  }
  return rows.length ? `<ul class="items">${rows.join('')}</ul>` : '<p class="empty">Nenhum item ainda.</p>';
}

/** Casa: guias Silo, Operadores, Equipamentos e Pets */
export function openCasa(tab = 'silo'): void {
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
    el.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach((b) => b.addEventListener('click', () => { active = b.dataset.tab!; rerender(); }));
    bindTeam(el, (cls) => { picked = cls; rerender(); });
  });
}

/** Barraca: venda na hora e lanches */
export function openStall(): void {
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
      <p class="hint">O personagem come sozinho quando a energia cai abaixo de ${SNACKS[0].auto_trigger_below_energy_pct}%. Ponha até ${SNACKS[0].max_stack_in_slot} no espaço de lanche (Casa → Equipamentos).</p>`;
  }, bindSell);
}
