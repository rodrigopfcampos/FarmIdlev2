// Forja (UI 16-bit): a ferramenta de cada personagem no centro, setas para trocar, conserto grande embaixo,
// os 5 níveis da ferramenta (sobem sozinhos com a fazenda) e a Vara de Pescar do Lago.
import { TOOL_MATERIALS } from '../data';
import { store } from '../farm/store';
import { repairTool } from '../net/farmApi';
import { bindRod, rodCard } from './animals-ui';
import { formatGold } from './format';
import { act, className, DUR, esc, nf1, pct, rerender, show, toolArt, toolCard } from './panel';

/** Forja: ferramentas e Vara de Pescar */
export function openForge(): void {
  let picked = 'agricultor';
  show('Forja', () => {
    const s = store.state!;
    const c = s.characters.find((x) => x.class_id === picked) ?? s.characters[0];
    const tc = toolCard(c.class_id);
    const i = TOOL_MATERIALS.findIndex((m) => m.id === c.material);
    const cur = TOOL_MATERIALS[i], next = TOOL_MATERIALS[i + 1] as (typeof TOOL_MATERIALS)[number] | undefined;
    const row = TOOL_MATERIALS.map((m, k) => `<span class="tier ${k <= i ? 'got' : ''} ${m.id === cur.id ? 'current' : ''} ${m.unlock_level > s.level ? 'locked' : ''}" title="Nível ${k + 1}: ×${nf1.format(m.work_capacity_multiplier)} de trabalho · fazenda nível ${m.unlock_level}"><b>${k + 1}</b><small>×${nf1.format(m.work_capacity_multiplier)}</small></span>`).join('');
    const repair = Math.round(cur.repair_cost_gold * (1 + s.fx.tool_cost) * 100) / 100;
    const low = c.durability < DUR.low_durability_threshold;
    const n = s.characters.length, idx = s.characters.findIndex((x) => x.class_id === c.class_id);
    return `<div class="forge">
        <button type="button" class="big-arrow" data-forge-step="-1" aria-label="Ferramenta anterior" ${n < 2 ? 'disabled' : ''}>◀</button>
        <div class="forge-card">${toolArt(c.class_id, 0.6)}
          <strong>${esc(tc.name_pt)}</strong><span class="lv-tag">Nv ${i + 1}</span>
          <small>${esc(className(c.class_id))} · ${idx + 1}/${n}</small>
          <span class="energy dura ${low ? 'low' : ''}" title="Durabilidade ${nf1.format(c.durability)}"><span style="width:${Math.round(c.durability)}%"></span></span>
          <small class="${low ? 'bad' : 'muted'}">Durabilidade ${nf1.format(c.durability)}/${DUR.max_durability}</small>
        </div>
        <button type="button" class="big-arrow" data-forge-step="1" aria-label="Próxima ferramenta" ${n < 2 ? 'disabled' : ''}>▶</button>
      </div>
      <button type="button" class="primary big-action" data-repair="${c.class_id}" ${c.durability >= 100 || s.gold < repair ? 'disabled' : ''}>${c.durability >= 100 ? 'Inteira' : `Consertar · ${formatGold(repair)}`}</button>
      <div class="tier-row" aria-label="Níveis da ferramenta">${row}</div>
      <p class="hint">${next ? `A ${esc(tc.name_pt)} sobe sozinha para o nível ${i + 2} (×${nf1.format(next.work_capacity_multiplier)} de trabalho) quando a fazenda chegar ao nível ${next.unlock_level}, de graça.` : `${esc(tc.name_pt)} no nível máximo.`}</p>
      <p class="hint">A ferramenta perde ${nf1.format(DUR.loss_per_work_hour)} de durabilidade por hora de trabalho; abaixo de ${DUR.low_durability_threshold} trabalha a ${pct(DUR.low_durability_capacity_penalty_multiplier)} até o conserto. ${esc(className(c.class_id))}: ${nf1.format(c.rate)} de trabalho por hora.</p>
      ${s.fishing ? `<h3>Lago</h3>${rodCard(s)}` : ''}`;
  }, (el) => {
    el.querySelectorAll<HTMLButtonElement>('[data-forge-step]').forEach((b) => b.addEventListener('click', () => {
      const list = store.state!.characters;
      const k = list.findIndex((x) => x.class_id === picked);
      picked = list[(Math.max(0, k) + Number(b.dataset.forgeStep) + list.length) % list.length].class_id;
      rerender();
    }));
    el.querySelectorAll<HTMLButtonElement>('[data-repair]').forEach((b) => b.addEventListener('click', () => { b.disabled = true; void act(() => repairTool(b.dataset.repair!), 'Ferramenta consertada.'); }));
    bindRod(el);
  });
}
