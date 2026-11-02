// Pomar: vagas em cards, plantar, trocar e derrubar árvores.
import { type Crop, CROPS, RARITY_BY_ID, WORK } from '../data';
import { iconSprite } from '../farm/art';
import { orchardFruits, rareSeeds, treeLook } from '../farm/rules';
import { store } from '../farm/store';
import { chopTree, plantRareTree, plantTree } from '../net/farmApi';
import { duration, formatGold } from './format';
import { act, cleanupLeft, esc, nf1, rerender, salesMult, show, sprite, stallRatio } from './panel';
import { tend } from './plots-ui';

export function onOrchardClick(lot: string): void {
  const s = store.state;
  const now = store.clock.farmNow();
  if (s?.trees.some((t) => t.lot_id === lot && t.fruit_id && t.ready_at !== null && t.ready_at <= now)) void tend(lot);
  else openOrchard(lot);
}

// ---------- pomar ----------
export function treeStatus(lot: string, slot: number): string {
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

export function fruitInfo(c: Crop): string {
  const sell = c.units_per_harvest * c.fair_price_per_unit * stallRatio() * salesMult();
  return `Muda ${formatGold(c.sapling_cost ?? 0)} · 1ª colheita em ${duration(c.grow_minutes * 60)}, depois a cada ${duration((c.regrow_minutes ?? c.grow_minutes) * 60)} · ${c.units_per_harvest} × ${formatGold(c.fair_price_per_unit)} (Barraca ${nf1.format(sell)}) · ${nf1.format(c.xp_per_harvest)} XP`;
}

export function openOrchard(lot: string): void {
  let picking: number | null = null;
  show(`Pomar ${lot}`, () => {
    const s = store.state!;
    const cleanup = cleanupLeft(lot);
    if (cleanup) return `<p class="status">Lote em limpeza: fica pronto em ${duration(cleanup)}. Depois dá para plantar as mudas.</p>`;
    const now = store.clock.farmNow();
    const slots = s.trees.filter((t) => t.lot_id === lot).map((t) => {
      const ready = !!t.fruit_id && t.ready_at !== null && t.ready_at <= now;
      const art = t.fruit_id ? sprite(iconSprite(store.manifest, t.fruit_id), 2) : '<span class="slot-empty">+</span>';
      return `<div class="gcard ${ready ? 'ready' : ''} ${picking === t.slot ? 'picked' : ''} ${t.fruit_id ? '' : 'empty'}"><span class="gcard-n">Vaga ${t.slot}</span>
        <div class="gcard-art">${art}${ready ? '<span class="find-dot">!</span>' : ''}</div>
        <small>${treeStatus(lot, t.slot)}</small>
        <div class="gcard-btns">${ready ? `<button type="button" class="primary small" data-harvest>Colher</button>` : ''}
          <button type="button" class="${picking === t.slot ? 'primary small' : 'secondary small'}" data-pick="${t.slot}">${t.fruit_id ? 'Trocar' : 'Plantar'}</button>
          ${t.fruit_id ? `<button type="button" class="secondary small danger" data-chop="${t.slot}" title="Derrubar (grátis)">Derrubar</button>` : ''}</div></div>`;
    }).join('');
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
    return `${ripe ? '<div class="row top"><button type="button" class="primary small" data-harvest>Colher as frutas</button></div>' : ''}<div class="gcard-grid">${slots}</div>${picker}
      <p class="hint">Com o jogo aberto, colher com clique é grátis; fora do jogo a equipe colhe (${nf1.format(WORK.harvest)} de trabalho por árvore; a Rancheira trabalha a 100% no pomar). Árvores não precisam de semente.</p>`;
  }, (el) => {
    el.querySelectorAll('[data-harvest]').forEach((b) => b.addEventListener('click', () => void tend(lot)));
    el.querySelectorAll<HTMLButtonElement>('[data-pick]').forEach((b) => b.addEventListener('click', () => { picking = Number(b.dataset.pick); rerender(); }));
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
