import { describe, expect, it } from 'vitest';
import { condAt, countdown, eventStatus, localMinutes, partAt, type WeatherView } from '../src/farm/weather';

const view = (over: Partial<WeatherView> = {}): WeatherView => ({
  tz: 'America/Sao_Paulo', cond: 'sunny', part: 'day', forecast_hours: 1, warn_minutes: 10, event: null,
  forecast: [{ from: '2030-06-01T12:00:00-03:00', to: '2030-06-01T15:00:00-03:00', cond: 'hot_sun' }, { from: '2030-06-01T15:00:00-03:00', to: '2030-06-01T18:00:00-03:00', cond: 'rain' }],
  bonus: { growth: 0, account_xp: 0, char_xp: 0, sales: 0, moon: 0 },
  account: { timezone: 'America/Sao_Paulo', confirmed: true, pending: null, pending_at: null, can_change_at: null }, ...over,
});

describe('clima no cliente', () => {
  it('hora local segue o fuso da conta', () => {
    const t = Date.parse('2030-06-01T22:30:00Z');
    expect(localMinutes('America/Sao_Paulo', t)).toBe(19 * 60 + 30);
    expect(localMinutes('Asia/Tokyo', t)).toBe(7 * 60 + 30);
  });
  it('dia 06–17:59, entardecer 18–18:59, noite 19–05:59', () => {
    expect(partAt(6 * 60)).toBe('day');
    expect(partAt(17 * 60 + 59)).toBe('day');
    expect(partAt(18 * 60 + 30)).toBe('dusk');
    expect(partAt(19 * 60)).toBe('night');
    expect(partAt(5 * 60 + 59)).toBe('night');
  });
  it('clima pelo bloco da previsão', () => {
    expect(condAt(view(), Date.parse('2030-06-01T16:00:00-03:00'))).toBe('rain');
    expect(condAt(view(), Date.parse('2030-06-01T20:00:00-03:00'))).toBe('sunny');
  });
  it('evento: aviso 10 min antes, acontecendo por 45 min, depois some', () => {
    const ev = { id: 'lua_cheia', name_pt: 'Lua Cheia', start: '2030-06-01T19:30:00-03:00', end: '2030-06-01T20:15:00-03:00', active: false, forced: false };
    const w = view({ event: ev });
    expect(eventStatus(w, Date.parse('2030-06-01T19:15:00-03:00'))).toBeNull();
    expect(eventStatus(w, Date.parse('2030-06-01T19:22:00-03:00'))?.kind).toBe('soon');
    expect(eventStatus(w, Date.parse('2030-06-01T19:40:00-03:00'))?.kind).toBe('active');
    expect(eventStatus(w, Date.parse('2030-06-01T20:15:00-03:00'))).toBeNull();
  });
  it('contagem regressiva', () => {
    expect(countdown(30_000)).toBe('1 min');
    expect(countdown(8 * 60_000)).toBe('8 min');
    expect(countdown(65 * 60_000)).toBe('1 h 05 min');
  });
});
