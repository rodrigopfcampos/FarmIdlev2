// Painel "Tempos": quanto falta em cada atividade, num lugar só, com uma aba por atividade
// (Lavoura, Pomar, Animais, Lago, Expedições, Limpeza, Pets). Cada linha tem o ícone, o nome, o tempo que falta e uma barra.
// Os textos e as barras andam sozinhos a cada segundo; clicar na linha abre a tela daquela atividade.
import { ANIMAL_BY_ID, CROPS, HOUSE_NAMES, PETS, ROUTE_BY_ID, VEHICLE_BY_ID } from '../data';
import { orchardLook } from '../farm/life';
import { cleanupMinutes, petFindLeft } from '../farm/rules';
import { store } from '../farm/store';
import type { FarmState } from '../net/farmApi';
import { openHouse } from './animals-ui';
import { duration } from './format';
import { openCasa } from './house-ui';
import { hudIcon } from './hud-icons';
import { openOrchard } from './orchard-ui';
import { animalFace, esc, itemIcon, petFace, rerender, show, sprite } from './panel';
import { openLot } from './plots-ui';

type Row = {
  icon: string; title: string; sub: string;
  start: number; end: number;       // tempo da fazenda (s): começo e fim do que está correndo
  stuck?: string;                   // parado (sem ração, sem equipe…): mostra o motivo no lugar do tempo
  readyText?: string;               // texto quando termina ("Pronto para colher", "Voltou")
  go?: string;                      // o que abre ao clicar
};
type Tab = { id: string; name: string; rows: Row[]; empty: string };

let active = '';
let timer: number | undefined;
let goHandlers: Record<string, () => void> = {};
let garage: (() => void) | null = null;

/** quem monta a tela passa como abrir a Garagem (ela precisa do contexto da tela) */
export function setTimersGarage(open: () => void): void { garage = open; }

const LOOK_PT: Record<string, string> = { sprout: 'Muda', young: 'Jovem', adult: 'Adulta', fruit: 'Com frutas' };

function tabs(s: FarmState, now: number): Tab[] {
  goHandlers = {};
  const go = (key: string, fn: () => void) => { goHandlers[key] = fn; return key; };

  // Lavoura: um lote por linha (8 canteiros juntos), do 1º plantio até o último ficar pronto
  const lotReady = new Map(s.lots.map((l) => [l.lot_id, l.ready_at]));
  const byLot = new Map<string, typeof s.plots>();
  for (const p of s.plots) {
    const lot = p.plot_id.split('-')[0];
    if (!byLot.has(lot)) byLot.set(lot, []);
    byLot.get(lot)!.push(p);
  }
  const crops: Row[] = [];
  for (const [lot, ps] of byLot) {
    if ((lotReady.get(lot) ?? 0) > now) continue; // em limpeza: aparece na aba Limpeza
    const grow = ps.filter((p) => p.state === 'growing' && p.ready_at !== null && p.planted_at !== null);
    const stalled = ps.filter((p) => p.state === 'empty' && p.crop_id && p.stalled_reason);
    if (!grow.length && !stalled.length) continue;
    const names = [...new Set((grow.length ? grow : stalled).map((p) => CROPS[p.crop_id ?? p.planted_crop_id ?? '']?.name_pt).filter(Boolean))];
    const ready = grow.filter((p) => p.ready_at! <= now).length;
    const first = grow.length ? (grow.find((p) => p.crop_id) ?? grow[0]).crop_id ?? grow[0].planted_crop_id : stalled[0].crop_id;
    crops.push({
      icon: first ? itemIcon(first) : '', title: `Lote ${lot} · ${names.join(', ')}`,
      sub: grow.length ? `${ready ? `${ready} de ${grow.length} prontos` : `${grow.length} canteiro${grow.length > 1 ? 's' : ''} crescendo`}${stalled.length ? ` · ${stalled.length} parado${stalled.length > 1 ? 's' : ''}` : ''}` : `${stalled.length} canteiro${stalled.length > 1 ? 's' : ''} esperando`,
      start: grow.length ? Math.min(...grow.map((p) => p.planted_at!)) : 0, end: grow.length ? Math.max(...grow.map((p) => p.ready_at!)) : 0,
      stuck: grow.length ? undefined : stalled[0].stalled_reason ?? 'Parado', readyText: 'Pronto para colher', go: go(`lot:${lot}`, () => openLot(lot)),
    });
  }

  // Pomar: uma árvore por linha, com a fase (muda, jovem, adulta, com frutas)
  const trees: Row[] = [];
  for (const t of s.trees) {
    if (!t.fruit_id || t.ready_at === null || t.planted_at === null) continue;
    const c = CROPS[t.fruit_id];
    const first = t.ready_at - t.planted_at <= c.grow_minutes * 60 + 1;
    const cycle = first ? t.ready_at - t.planted_at : (c.regrow_minutes ?? c.grow_minutes) * 60;
    const look = orchardLook(t, now, true);
    trees.push({ icon: itemIcon(t.fruit_id), title: `${c.name_pt} · Pomar ${t.lot_id}, vaga ${t.slot}`, sub: `${LOOK_PT[look] ?? ''}${first ? ' · 1ª colheita' : ''}`,
      start: t.ready_at - cycle, end: t.ready_at, readyText: 'Frutas prontas', go: go(`tree:${t.lot_id}`, () => openOrchard(t.lot_id)) });
  }

  // Animais e Lago: um por vaga
  const animalRow = (a: FarmState['animals'][number]): Row => {
    const d = ANIMAL_BY_ID[a.animal_id];
    return { icon: animalFace(a.animal_id), title: `${d?.name_pt ?? a.animal_id} · ${HOUSE_NAMES[a.house_id] ?? a.house_id}, vaga ${a.slot}`,
      sub: d ? `${d.product.name_pt} a cada ${duration(d.produce_every_minutes * 60)}` : '',
      start: a.cycle_start ?? 0, end: a.ready_at ?? 0, stuck: a.state === 'hungry' ? 'Sem ração' : undefined,
      readyText: 'Pronto para coletar', go: go(`house:${a.house_id}`, () => openHouse(a.house_id)) };
  };
  const animals = s.animals.filter((a) => a.house_id !== 'lago').map(animalRow);
  const fish = s.animals.filter((a) => a.house_id === 'lago').map(animalRow);

  // Expedições: cada viagem até voltar
  const veh = new Map(s.vehicles.map((v) => [v.vehicle_id, v]));
  const trips: Row[] = s.expeditions.map((e) => ({
    icon: sprite(`vehicle_${e.vehicle_id}_${veh.get(e.vehicle_id)?.rarity ?? 'common'}`, 0.4) || sprite(`vehicle_${e.vehicle_id}_common`, 0.4),
    title: `${VEHICLE_BY_ID[e.vehicle_id]?.name_pt ?? e.vehicle_id} · ${ROUTE_BY_ID[e.route_id]?.name_pt ?? e.route_id}`,
    sub: `${Object.values(e.cargo).reduce((a, b) => a + b, 0)} unid. de carga${e.repeat_left ? ` · repete mais ${e.repeat_left}×` : ''}`,
    start: e.started_at, end: e.status === 'back' ? Math.min(now, e.returns_at) : e.returns_at, readyText: 'Voltou: receber na Garagem',
    go: go('garage', () => garage?.()),
  }));

  // Limpeza: lote comprado ainda com mato
  const smith = s.characters.some((c) => c.class_id === 'ferreiro' && c.slot === 'field');
  const clean: Row[] = s.lots.filter((l) => l.ready_at > now).map((l) => {
    const total = cleanupMinutes(l.purchase_n ?? 1, smith, s.fx.cleanup) * 60;
    return { icon: hudIcon('tend', 20), title: `Lote ${l.lot_id}`, sub: 'Limpando o mato', start: l.ready_at - Math.max(total, l.ready_at - now), end: l.ready_at, readyText: 'Limpo' };
  });

  // Pets: achado de cada pet
  const pets: Row[] = s.pets.filter((p) => p.find_t !== null).map((p) => {
    const d = PETS.list.find((x) => x.id === p.pet_id)!;
    const left = petFindLeft(p.pet_id, p.find_t, now);
    return { icon: petFace(p.pet_id), title: d?.name_pt ?? p.pet_id, sub: 'Achado', start: p.find_t!, end: now + left, readyText: 'Achado pronto', go: go('pets', () => openCasa('pets')) };
  });

  return [
    { id: 'lavoura', name: 'Lavoura', rows: crops, empty: 'Nenhum canteiro crescendo.' },
    { id: 'pomar', name: 'Pomar', rows: trees, empty: 'Nenhuma árvore plantada.' },
    { id: 'animais', name: 'Animais', rows: animals, empty: 'Nenhum animal no Galinheiro ou no Celeiro.' },
    { id: 'lago', name: 'Lago', rows: fish, empty: s.lake ? 'Nenhum peixe no Lago.' : 'O Lago ainda não foi comprado.' },
    { id: 'expedicoes', name: 'Expedições', rows: trips, empty: 'Nenhuma expedição na estrada.' },
    { id: 'limpeza', name: 'Limpeza', rows: clean, empty: 'Nenhum lote em limpeza.' },
    { id: 'pets', name: 'Pets', rows: pets, empty: 'Nenhum pet chegou ainda.' },
  ];
}

const isReady = (r: Row, now: number) => !r.stuck && r.end <= now;
const pct = (r: Row, now: number) => (r.stuck ? 0 : r.end <= r.start ? 100 : Math.max(0, Math.min(100, ((now - r.start) / (r.end - r.start)) * 100)));
const leftText = (r: Row, now: number) => (r.stuck ? r.stuck : isReady(r, now) ? r.readyText ?? 'Pronto' : `Falta ${duration(r.end - now)}`);

function rowHtml(r: Row, now: number): string {
  const ready = isReady(r, now), p = Math.round(pct(r, now));
  return `<li class="trow ${ready ? 'ready' : ''} ${r.stuck ? 'stuck' : ''}" data-s="${r.start}" data-e="${r.end}" ${r.stuck ? 'data-stuck="1"' : ''} ${r.go ? `data-go="${r.go}" tabindex="0" role="button"` : ''}>
    <span class="ticon">${r.icon}</span>
    <span class="tmain"><span class="ttop"><strong>${esc(r.title)}</strong><b class="tleft">${esc(leftText(r, now))}</b></span>
      <span class="tbar" role="progressbar" aria-valuenow="${p}" aria-valuemin="0" aria-valuemax="100"><span style="width:${p}%"></span></span>
      ${r.sub ? `<small>${esc(r.sub)}</small>` : ''}</span></li>`;
}

/** quantas coisas estão prontas agora (para o número no botão do HUD) */
export function readyCount(s: FarmState): number {
  const now = store.clock.farmNow();
  return tabs(s, now).reduce((n, t) => n + t.rows.filter((r) => isReady(r, now)).length, 0);
}

export function hudTimers(): string {
  const s = store.state;
  const n = s ? readyCount(s) : 0;
  return `<button type="button" class="icon-btn" data-timers title="Tempos: quanto falta em cada atividade" aria-label="Tempos">${hudIcon('clock')}${n ? `<span class="badge ok">${n}</span>` : ''}</button>`;
}

export function openTimers(tab?: string): void {
  if (tab) active = tab;
  show('Tempos', () => {
    const s = store.state!, now = store.clock.farmNow();
    const all = tabs(s, now);
    // aba que abre: a última vista; na 1ª vez, a 1ª com algo pronto ou correndo
    if (!all.some((t) => t.id === active)) active = (all.find((t) => t.rows.some((r) => isReady(r, now))) ?? all.find((t) => t.rows.length) ?? all[0]).id;
    const t = all.find((x) => x.id === active)!;
    const head = all.map((x) => {
      const ready = x.rows.filter((r) => isReady(r, now)).length;
      return `<button type="button" role="tab" data-tab="${x.id}" aria-selected="${x.id === active}" title="${ready ? `${ready} pronto${ready > 1 ? "s" : ""}` : `${x.rows.length} correndo`}">${x.name}${x.rows.length ? ` <span class="tcount ${ready ? "on" : ""}">${ready || x.rows.length}</span>` : ''}</button>`;
    }).join('');
    const rows = [...t.rows].sort((a, b) => Number(isReady(b, now)) - Number(isReady(a, now)) || Number(!!a.stuck) - Number(!!b.stuck) || a.end - b.end);
    return `<div class="tabs wrap timers-tabs" role="tablist">${head}</div>
      ${rows.length ? `<ul class="timers">${rows.map((r) => rowHtml(r, now)).join('')}</ul>` : `<p class="empty">${esc(t.empty)}</p>`}
      <p class="hint">Mostra o que está correndo em cada atividade e quanto falta. A barra enche até ficar pronto; clique numa linha para abrir a tela dela. O tempo anda online e offline.</p>`;
  }, (el) => {
    el.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach((b) => b.addEventListener('click', () => { active = b.dataset.tab!; rerender(); }));
    el.querySelectorAll<HTMLElement>('[data-go]').forEach((li) => {
      const open = () => goHandlers[li.dataset.go!]?.();
      li.addEventListener('click', open);
      li.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open(); } });
    });
  });
  // a cada segundo: anda o texto e a barra; se algo ficou pronto, redesenha (reordena e atualiza as abas)
  window.clearInterval(timer);
  timer = window.setInterval(() => {
    const list = document.querySelector('.timers');
    const tabsEl = document.querySelector('.timers-tabs');
    if (!tabsEl || tabsEl.closest('[hidden]')) { window.clearInterval(timer); return; } // painel fechado ou trocado
    if (!list) return;
    const now = store.clock.farmNow();
    let changed = false;
    list.querySelectorAll<HTMLElement>('.trow').forEach((li) => {
      if (li.dataset.stuck) return;
      const s = Number(li.dataset.s), e = Number(li.dataset.e);
      const ready = e <= now;
      if (ready !== li.classList.contains('ready')) { changed = true; return; }
      if (ready) return;
      const p = e <= s ? 100 : Math.max(0, Math.min(100, ((now - s) / (e - s)) * 100));
      li.querySelector<HTMLElement>('.tbar > span')!.style.width = `${p}%`;
      li.querySelector('.tbar')!.setAttribute('aria-valuenow', String(Math.round(p)));
      li.querySelector('.tleft')!.textContent = `Falta ${duration(e - now)}`;
    });
    if (changed) rerender();
  }, 1000);
}
