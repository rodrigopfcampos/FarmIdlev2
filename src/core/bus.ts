// Mensagens entre o mapa (Phaser) e a interface (HTML), sem um depender do outro.
type Handler = (payload?: any) => void;
const handlers = new Map<string, Set<Handler>>();
export const bus = {
  on(event: string, h: Handler) { (handlers.get(event) ?? handlers.set(event, new Set()).get(event)!).add(h); },
  off(event: string, h: Handler) { handlers.get(event)?.delete(h); },
  emit(event: string, payload?: unknown) { handlers.get(event)?.forEach((h) => h(payload)); },
};
