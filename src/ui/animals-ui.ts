// Galinheiro, Celeiro e Lago: animais em cards, compra, ampliação, rede de pesca e Vara de Pescar.
import { ANIMAL_BY_ID, ANIMAL_ODDS, ANIMAL_RULES, ANIMALS, FISHING, HOUSE_NAMES, HOUSES, RARITY_BY_ID, WORK } from '../data';
import { animalLook, collectUnits, feedPerCycle, fishCycles, fishSpecies } from '../farm/rules';
import { store } from '../farm/store';
import { type AnimalState, buyAnimal, collectFish, type FarmState, removeAnimal, repairRod, upgradeHouse } from '../net/farmApi';
import { duration, formatGold } from './format';
import { act, animalFace, cleanupLeft, esc, nf1, pct, rerender, show, sprite, toast } from './panel';
import { tend } from './plots-ui';

// ---------- animais (fase 4) ----------
export const houseOfLot = (lot: string) => Object.entries(store.state?.houses ?? {}).find(([, h]) => h.lot === lot)?.[0] ?? null;

export function onPastureClick(lot: string): void {
  const s = store.state;
  if (!s) return;
  const house = houseOfLot(lot);
  if (!house) { openLake(); return; }
  const now = store.clock.farmNow();
  if (s.animals.some((a) => a.house_id === house && animalLook(a, now) === 'ready')) void tend(lot);
  else openHouse(house);
}

/** Vara de Pescar (ferramenta do Lago): aparece no painel do Lago e na Forja */
export function rodCard(s: FarmState): string {
  const f = s.fishing;
  if (!f) return '';
  const low = f.rod < FISHING.rod.low_threshold;
  return `<div class="char-card">${sprite('card_full_pesca_common', 0.36)}<div class="grow"><strong>Vara de Pescar</strong>
        <span class="energy dura ${low ? 'low' : ''}"><span style="width:${Math.round(f.rod)}%"></span></span>
        <small>Ferramenta do Lago · durabilidade ${nf1.format(f.rod)} de 100 · gasta ${nf1.format(FISHING.rod.wear_per_cycle)} por ciclo recolhido${low ? ` · <span class="bad">abaixo de ${FISHING.rod.low_threshold}: a pesca rende a metade</span>` : ''}</small>
        <span class="btns"><button type="button" class="secondary" data-rod ${f.rod >= 100 || s.gold < f.rod_repair ? 'disabled' : ''}>Consertar · ${formatGold(f.rod_repair)}</button></span></div></div>`;
}

export function bindRod(el: HTMLElement): void {
  el.querySelector<HTMLButtonElement>('[data-rod]')?.addEventListener('click', (e) => {
    (e.currentTarget as HTMLButtonElement).disabled = true;
    void act(() => repairRod(), 'Vara de Pescar consertada.');
  });
}

/** Lago: rede pronta recolhe na hora; senão mostra a rede e a Vara de Pescar (desgaste e conserto) */
export function openLake(): void {
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

export function animalStatus(a: AnimalState): string {
  const now = store.clock.farmNow();
  const look = animalLook(a, now);
  const d = ANIMAL_BY_ID[a.animal_id];
  if (look === 'hungry') return '<span class="bad">Com fome: falta ouro para a ração. Venda algo e ele volta.</span>';
  if (look === 'ready') return `<strong>${esc(d.product.name_pt)} pronto</strong> · clique para coletar`;
  return `Produzindo ${esc(d.product.name_pt)} · pronto em ${duration(a.ready_at! - now)}`;
}

export function openHouse(house: string): void {
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
      }).join('')}</div><p class="hint">A raridade é sorteada na compra (${Object.entries(ANIMAL_ODDS).map(([r, p]) => `${RARITY_BY_ID[r].name_pt} ${pct(p)}`).join(', ')}) e fica para sempre. Tirar o animal não devolve o ouro.</p>`;
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
    el.querySelectorAll<HTMLButtonElement>('[data-pick-slot]').forEach((b) => b.addEventListener('click', () => { picking = Number(b.dataset.pickSlot); rerender(); }));
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
