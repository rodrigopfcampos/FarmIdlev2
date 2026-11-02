// Lavoura: colher/plantar com clique, painel do lote (cultivo e sementes raras) e compra de lote.
import { bus } from '../core/bus';
import { ANIMAL_BY_ID, ANIMAL_RULES, type Crop, CROPS, FISHING, HOUSES, itemInfo, LOT_BY_ID, LOT_TYPE_NAMES, PURCHASES, RARITY_BY_ID, WORK } from '../data';
import { iconSprite } from '../farm/art';
import { animalLook, lotOffer, plotCrops, plotLook, rareSeeds } from '../farm/rules';
import { applyState, store } from '../farm/store';
import { type AnimalState, buyLot, plantRareSeed, type PlotState, setCrop, tendFarm } from '../net/farmApi';
import { duration, formatGold } from './format';
import { act, cleanupLeft, close, esc, nf1, salesMult, show, sprite, stallRatio, toast } from './panel';

// ---------- clique do jogador ----------
let busy = false;

/** colhe e planta (canteiro, lote ou fazenda inteira) e mostra o que entrou no Silo */
export async function tend(target: string | null): Promise<void> {
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

export function onPlotClick(id: string): void {
  const s = store.state;
  const p = s?.plots.find((x) => x.plot_id === id);
  if (!s || !p) return;
  const look = plotLook(p, store.clock.farmNow(), s.lots.find((l) => l.lot_id === id.split('-')[0])?.ready_at ?? 0);
  if (look === 'ready' || look === 'planned') void tend(id);
  else openPlot(id);
}

// ---------- canteiro ----------
export function cropInfo(c: Crop): string {
  const sell = c.units_per_harvest * c.fair_price_per_unit * stallRatio() * salesMult();
  const base = `Cresce em ${duration(c.grow_minutes * 60)} · semente ${nf1.format(c.seed_cost ?? 0)} · colheita ${c.units_per_harvest} × ${formatGold(c.fair_price_per_unit)} (Barraca ${nf1.format(sell)}) · ${nf1.format(c.xp_per_harvest)} XP`;
  if (c.kind !== 'recurring') return base;
  return `${base}<br>Recorrente: ${c.harvests_per_planting} colheitas com 1 semente, uma a cada ${duration((c.regrow_minutes ?? 0) * 60)} depois da 1ª`;
}

export function plotStatus(p: PlotState): string {
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

export function cropButton(c: Crop, selected: boolean, locked: boolean, attr: string): string {
  return `<button type="button" class="crop ${selected ? 'selected' : ''} ${locked ? 'locked' : ''}" ${locked ? 'disabled' : `${attr}="${c.id}"`} aria-pressed="${selected}">
    ${sprite(iconSprite(store.manifest, c.id), 1)}
    <span><strong>${esc(c.name_pt)}${locked ? ` · nível ${c.unlock_level}` : ''}</strong><small>${cropInfo(c)}</small></span>
  </button>`;
}

export function openPlot(id: string): void {
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
      : `Lote parado. Escolha um cultivo para os ${mine.length} canteiros.`;
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
export const PROBLEM_TEXT: Record<string, (o: NonNullable<ReturnType<typeof lotOffer>>) => string> = {
  vizinho: () => 'Precisa dividir um lado com um lote seu (Galinheiro e Celeiro podem ser comprados de longe).',
  nivel: (o) => `Precisa do nível ${o.needLevel}.`,
  ouro: (o) => `Falta ${formatGold(o.cost - (store.state?.gold ?? 0))} de ouro.`,
  fim: () => 'Você já comprou todos os lotes.',
};

export function openLot(id: string): void {
  const def = LOT_BY_ID[id];
  show(`${LOT_TYPE_NAMES[def.type]} ${id}`, () => {
    const s = store.state!;
    const owned = new Set(s.lots.map((l) => l.lot_id));
    const smith = s.characters.some((c) => c.class_id === 'ferreiro');
    const o = lotOffer(id, owned, s.level, s.gold, smith, s.fx.cleanup);
    if (!o) return '<p>Este lote já é seu.</p>';
    if (o.problems.includes('fim')) return `<p>${PROBLEM_TEXT.fim(o)}</p>`;
    const what = def.type === 'lavoura' ? `${def.plots?.length ?? 0} canteiros` : def.type === 'pomar' ? `${(def as { tree_slots?: unknown[] }).tree_slots?.length ?? 0} vagas de árvore`
      : def.type === 'pasto_lago' ? `Lago: pesca sozinho (rede de ${FISHING.cycle_minutes * FISHING.max_cycles / 60} h, peixe no Silo) e +${ANIMAL_RULES.lake_bonus.extra_galinheiro_slots} vagas de ave no Galinheiro`
      : `${def.type === 'pasto_galinheiro' ? 'Galinheiro' : 'Celeiro'} com ${HOUSES[def.type === 'pasto_galinheiro' ? 'galinheiro' : 'celeiro'].slots[0].slots} vagas para animais`;
    return `<dl class="facts">
        <dt>Compra</dt><dd>${o.n}ª de ${PURCHASES.length}</dd>
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
