// Clima no cliente: só mostra o que o servidor mandou (agenda, evento e bônus); nada aqui decide bônus.
import { WEATHER } from '../data';

export type WeatherCond = 'sunny' | 'hot_sun' | 'cloudy' | 'rain' | 'fog';
export type DayPart = 'day' | 'dusk' | 'night';
export type WeatherEvent = { id: string; name_pt: string; start: string; end: string; active: boolean; forced: boolean };
export type WeatherView = {
  tz: string; cond: WeatherCond; part: DayPart;
  forecast: { from: string; to: string; cond: WeatherCond }[];
  forecast_hours: number; warn_minutes: number;
  event: WeatherEvent | null;
  bonus: { growth: number; account_xp: number; char_xp: number; sales: number; moon: number };
  account: { timezone: string; confirmed: boolean; pending: string | null; pending_at: string | null; can_change_at: string | null };
};

const hm = (s: string) => Number(s.slice(0, 2)) * 60 + Number(s.slice(3, 5));

/** minutos desde a meia-noite no fuso dado */
export function localMinutes(tz: string, ms: number): number {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone: tz, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(ms));
  const h = Number(parts.find((p) => p.type === 'hour')?.value ?? 0);
  const m = Number(parts.find((p) => p.type === 'minute')?.value ?? 0);
  return (h % 24) * 60 + m;
}

/** dia, entardecer ou noite pela hora local (06:00–17:59, 18:00–18:59, 19:00–05:59) */
export function partAt(minutes: number): DayPart {
  const p = WEATHER.day_parts;
  if (minutes >= hm(p.day[0]) && minutes <= hm(p.day[1])) return 'day';
  if (minutes >= hm(p.dusk[0]) && minutes <= hm(p.dusk[1])) return 'dusk';
  return 'night';
}

/** clima do bloco que contém o instante (ou o último conhecido) */
export function condAt(w: WeatherView, ms: number): WeatherCond {
  const b = w.forecast.find((f) => Date.parse(f.from) <= ms && ms < Date.parse(f.to));
  return b?.cond ?? w.cond;
}

/** situação do evento noturno agora: em aviso, acontecendo ou nada */
export function eventStatus(w: WeatherView, ms: number): { kind: 'soon' | 'active'; ev: WeatherEvent; left_ms: number } | null {
  const e = w.event;
  if (!e) return null;
  const st = Date.parse(e.start), en = Date.parse(e.end);
  if (ms >= en) return null;
  if (ms >= st) return { kind: 'active', ev: e, left_ms: en - ms };
  if (ms >= st - w.warn_minutes * 60_000) return { kind: 'soon', ev: e, left_ms: st - ms };
  return null;
}

/** "8 min", "1 h 05 min" (arredonda para cima: nunca mostra 0 antes da hora) */
export function countdown(ms: number): string {
  const min = Math.max(1, Math.ceil(ms / 60_000));
  if (min < 60) return `${min} min`;
  return `${Math.floor(min / 60)} h ${String(min % 60).padStart(2, '0')} min`;
}

export const condName = (c: string) => (WEATHER.names_pt as Record<string, string>)[c] ?? c;
export const partName = (p: string) => (WEATHER.part_names_pt as Record<string, string>)[p] ?? p;

/** efeito do evento em texto, lido da config */
export function eventEffect(id: string): string {
  const e = WEATHER.night_event.events.find((x) => x.id === id) as Record<string, unknown> | undefined;
  if (!e) return '';
  const out: string[] = [];
  if (e.account_xp_pct) out.push(`+${e.account_xp_pct}% XP da conta`);
  if (e.character_xp_pct) out.push(`+${e.character_xp_pct}% XP dos personagens`);
  if (e.growth_speed_pct) out.push(`+${e.growth_speed_pct}% velocidade de crescimento`);
  if (e.sales_gold_pct) out.push(`+${e.sales_gold_pct}% ouro nas vendas (até 1/24 da renda do dia)`);
  return out.join(' e ');
}

/** bônus que valem agora, em texto curto */
export function bonusLines(w: WeatherView): string[] {
  const pct = (x: number) => `${Math.round(x * 1000) / 10}%`.replace('.', ',');
  const b = w.bonus, out: string[] = [];
  if (b.growth > 0) out.push(`+${pct(b.growth)} velocidade de crescimento`);
  if (b.account_xp > 0) out.push(`+${pct(b.account_xp)} XP da conta`);
  if (b.char_xp > 0) out.push(`+${pct(b.char_xp)} XP dos personagens`);
  if (b.sales > 0) out.push(`+${pct(b.sales)} ouro nas vendas`);
  if (b.moon > 0) out.push(`Lua Cheia: +${pct(b.moon)} ouro nas vendas`);
  return out;
}

/** fuso do aparelho (padrão IANA) */
export const deviceTz = (): string => Intl.DateTimeFormat().resolvedOptions().timeZone;
