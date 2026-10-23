// Estado da fazenda no cliente: último estado do servidor + relógio. Sincroniza a cada minuto
// (só com a aba visível) e logo depois da próxima colheita, para o mapa mostrar o replantio.
import { bus } from '../core/bus';
import { FARM } from '../data';
import { getFarm, type FarmState } from '../net/farmApi';
import { FarmClock } from './clock';
import type { Manifest } from './art';

export const store = {
  state: null as FarmState | null,
  clock: new FarmClock(),
  manifest: {} as Manifest,
};

let timer: number | undefined;

export function applyState(s: FarmState): void {
  store.state = s;
  store.clock.sync(s);
  bus.emit('farm:state', s);
  schedule();
}

export async function refresh(): Promise<void> {
  try { applyState(await getFarm()); } catch (e) { bus.emit('farm:error', e instanceof Error ? e.message : String(e)); }
}

function schedule(): void {
  window.clearTimeout(timer);
  if (document.visibilityState !== 'visible' || !store.state) return;
  const now = store.clock.farmNow();
  const next = Math.min(...store.state.plots.filter((p) => p.ready_at !== null).map((p) => p.ready_at! - now), Infinity);
  const wait = Math.max(2, Math.min(FARM.sync_seconds, Number.isFinite(next) ? next + 1 : FARM.sync_seconds));
  timer = window.setTimeout(() => void refresh(), wait * 1000);
}

export function startSync(): void {
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') void refresh(); else window.clearTimeout(timer); });
  void refresh();
}

export function stopSync(): void {
  window.clearTimeout(timer);
  store.state = null;
}
