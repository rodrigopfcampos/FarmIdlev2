// Guia Pets da Casa: os 3 pets em cards, achado e carinho.
import { LEVELS, PETS, RARITY_BY_ID } from '../data';
import { petFactor, petFindLeft, petLevel, petNextIn } from '../farm/rules';
import { applyState, store } from '../farm/store';
import { collectPet, type FarmState } from '../net/farmApi';
import { duration, formatGold } from './format';
import { esc, nf1, pct, petFace, toast } from './panel';

export const petName = (id: string) => PETS.list.find((x) => x.id === id)?.name_pt ?? id;

/** o que o pet faz sempre (no nível atual) e o que ele traz no achado */
export function petLines(id: string, lv: number): { passive: string; find: string } {
  const d = PETS.list.find((x) => x.id === id)! as unknown as { find_hours: number; find: Record<string, number>; night_event_warning_minutes: number } & Record<string, number>;
  const f = petFactor(lv);
  const R = LEVELS[(store.state?.level ?? 1) - 1].reference_income_per_day;
  const gold = (share: number) => formatGold(Math.round(R * share * f * 100) / 100);
  if (id === 'cachorro') return {
    passive: `+${nf1.format(d.expedition_success_pts * f)} pontos nas expedições · ${pct(d.lost_cargo_recovery_chance * f)} de achar a carga perdida`,
    find: `Baú a cada ${d.find_hours} h: ${gold(d.find.gold_share_of_R ?? 0)} de ouro e ${pct((d.find.card_chance ?? 0) + (d.find.card_chance_per_level ?? 0) * (lv - 1))} de chance de carta`,
  };
  if (id === 'gato') return {
    passive: `+${Math.round(d.energy_recovery_pct * f)}% no descanso da equipe · +${Math.round(d.animal_production_pct * f)}% na produção animal`,
    find: `Soneca a cada ${d.find_hours} h: +${nf1.format((d.find.team_energy ?? 0) * f)} de energia para toda a equipe`,
  };
  return {
    passive: `+${nf1.format(d.sales_gold_pct * f)}% de ouro nas vendas · avisa do evento noturno ${d.night_event_warning_minutes} min antes`,
    find: `Moedas a cada ${d.find_hours} h: ${gold(d.find.gold_share_of_R ?? 0)} de ouro`,
  };
}

/** pega o achado do pet e conta o que veio */
export async function takeFind(id: string): Promise<void> {
  try {
    const after = await collectPet(id);
    applyState(after);
    const f = after.pet_find;
    if (!f) return;
    const parts = [f.gold ? `+${formatGold(f.gold)} ouro` : '', f.energy ? `+${nf1.format(f.energy)} de energia na equipe` : '',
      f.card ? `carta ${f.card.card_id} ${RARITY_BY_ID[f.card.rarity]?.name_pt ?? ''}` : ''].filter(Boolean);
    toast(`${petName(id)} trouxe: ${parts.join(' · ') || 'nada desta vez'}`, 5);
  } catch (e) { toast(e instanceof Error ? e.message : 'Não deu certo.'); }
}

/** guia Pets: um card por pet (arte grande, nível, o que faz, achado e carinho) */
export function petsTab(s: FarmState): string {
  const now = store.clock.farmNow();
  const cards = PETS.list.map((d) => {
    const mine = s.pets.find((x) => x.pet_id === d.id);
    if (!mine) {
      return `<div class="gcard locked"><div class="gcard-art">${petFace(d.id)}</div><strong>${esc(d.name_pt)}</strong>
        <small>Chega sozinho no nível ${d.unlock_level}</small><span class="lock-badge">🔒 Nv ${d.unlock_level}</span></div>`;
    }
    const lv = petLevel(mine.affinity), next = petNextIn(mine.affinity), cared = mine.last_care === s.game_day;
    const left = petFindLeft(d.id, mine.find_t, now), L = petLines(d.id, lv);
    const pips = Array.from({ length: 5 }, (_, i) => `<i class="${i < lv ? 'on' : ''}"></i>`).join('');
    return `<div class="gcard ${left === 0 ? 'ready' : ''}"><div class="gcard-art">${petFace(d.id)}${left === 0 ? '<span class="find-dot" title="Achado pronto">!</span>' : ''}</div>
      <strong>${esc(d.name_pt)}</strong><span class="pips" title="Nível ${lv} de 5">${pips}</span>
      <small>${esc(L.passive)}</small><small class="find">${esc(L.find)}</small>
      <small class="muted">${next ? `Próximo nível em ${next} carinho${next > 1 ? 's' : ''}` : 'Nível máximo'}</small>
      <div class="gcard-btns">
        <button type="button" class="primary small" data-pet-find="${d.id}" ${left === 0 ? '' : 'disabled'}>${left === 0 ? 'Pegar achado' : duration(left)}</button>
        <button type="button" class="secondary small" data-care="${d.id}" ${cared ? 'disabled' : ''}>${cared ? 'Carinho ✓' : 'Carinho'}</button>
      </div></div>`;
  }).join('');
  return `<div class="gcard-grid">${cards}</div>
    <p class="hint">Os pets chegam sozinhos e andam no pátio da Casa. Todos valem ao mesmo tempo. De tempos em tempos cada um traz um achado (um balão aparece em cima dele): clique no pet ou em "Pegar achado". O achado espera por você, mas o próximo só começa depois que você pegar. 1 carinho por dia em cada pet sobe o nível (efeito de 40% no nível 1 até 100% no 5).</p>`;
}
