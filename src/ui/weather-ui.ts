// Clima na interface: selo no topo, faixa do evento noturno com contagem regressiva e o painel com previsão e fuso.
import { EXP, WEATHER } from '../data';
import { bonusLines, condAt, condName, countdown, deviceTz, eventEffect, eventStatus, localMinutes, partAt, partName } from '../farm/weather';
import type { FarmState } from '../net/farmApi';
import { weatherIcon } from './weather-icons';

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
const hhmm = (tz: string, ms: number) => new Intl.DateTimeFormat('pt-BR', { timeZone: tz, hour: '2-digit', minute: '2-digit' }).format(new Date(ms));
const tzName = (tz: string) => tz.replace(/_/g, ' ');

/** selo do topo: ícone e nome do clima (lua à noite), e o ícone do evento quando ele está acontecendo */
export function weatherChip(s: FarmState, ms: number): string {
  const w = s.weather;
  if (!w) return '';
  const cond = condAt(w, ms);
  const part = partAt(localMinutes(w.tz, ms));
  const ev = eventStatus(w, ms);
  const icon = part === 'night' && cond === 'sunny' ? 'night' : cond;
  const label = part === 'night' && cond === 'sunny' ? 'Noite limpa' : condName(cond);
  return `<button type="button" class="wx-chip" data-weather title="Clima: ${esc(label)} · ${hhmm(w.tz, ms)} no seu fuso">${weatherIcon(icon, 2, label)}<span>${esc(label)}</span>${ev?.kind === 'active' ? weatherIcon(ev.ev.id, 1, ev.ev.name_pt) : ''}</button>`;
}

/** faixa do evento: aviso antes (10 min; 30 com o Papagaio) e contagem até o fim */
export function weatherBanner(s: FarmState, ms: number): string {
  const st = s.weather ? eventStatus(s.weather, ms) : null;
  if (!st) return '';
  const txt = st.kind === 'soon'
    ? `<strong>${esc(st.ev.name_pt)}</strong> começa em ${countdown(st.left_ms)}`
    : `<strong>${esc(st.ev.name_pt)}</strong>: ${esc(eventEffect(st.ev.id))} · termina em ${countdown(st.left_ms)}`;
  return `${weatherIcon(st.ev.id, 2, st.ev.name_pt)}<span>${txt}</span>`;
}

/** painel do clima */
export function weatherPanel(s: FarmState, ms: number): string {
  const w = s.weather;
  const min = localMinutes(w.tz, ms);
  const part = partAt(min);
  const cond = condAt(w, ms);
  const bonus = bonusLines(w);
  const ev = eventStatus(w, ms);
  const fc = w.forecast.filter((f) => Date.parse(f.to) > ms).map((f) =>
    `<li>${weatherIcon(f.cond, 1)}<span>${hhmm(w.tz, Date.parse(f.from))}–${hhmm(w.tz, Date.parse(f.to))}</span><strong>${esc(condName(f.cond))}</strong></li>`).join('');
  const a = w.account;
  const dev = deviceTz();
  const canAt = a.can_change_at ? Date.parse(a.can_change_at) : 0;
  const tzBlock = `<h3>Fuso horário</h3>
    <p>Sua fazenda segue <strong>${esc(tzName(a.timezone))}</strong>: dia e noite, clima, evento noturno e a virada do dia (salários).</p>
    ${a.pending ? `<p class="status">Troca marcada para <strong>${esc(tzName(a.pending))}</strong>, vale à meia-noite (${a.pending_at ? hhmm(a.timezone, Date.parse(a.pending_at)) : '00:00'} de hoje para amanhã).</p>` : ''}
    ${dev && dev !== a.timezone && !a.pending ? `<p class="warn-line">Este aparelho está em <strong>${esc(tzName(dev))}</strong>.</p>
      <button type="button" class="secondary" data-tz="${esc(dev)}" ${canAt > ms ? 'disabled' : ''}>Usar o fuso deste aparelho</button>
      <p class="hint">Só dá para trocar 1 vez a cada ${WEATHER.timezone_change_days} dias, e a troca vale a partir da próxima meia-noite.${canAt > ms ? ` Próxima troca liberada em ${new Date(canAt).toLocaleDateString('pt-BR')}.` : ''}</p>` : ''}`;
  return `<p class="status">${weatherIcon(part === 'night' && cond === 'sunny' ? 'night' : cond, 2)} <strong>${esc(condName(cond))}</strong> · ${esc(partName(part))} · ${hhmm(w.tz, ms)}</p>
    ${bonus.length ? `<ul class="wx-bonus">${bonus.map((b) => `<li>${esc(b)}</li>`).join('')}</ul>` : '<p class="hint">Sem bônus do clima agora.</p>'}
    ${ev ? `<div class="wx-event">${weatherIcon(ev.ev.id, 2)}<div><strong>${esc(ev.ev.name_pt)}</strong> ${ev.kind === 'soon' ? `começa em ${countdown(ev.left_ms)}` : `até ${hhmm(w.tz, Date.parse(ev.ev.end))}`}<small>${esc(eventEffect(ev.ev.id))}</small></div></div>` : ''}
    <h3>Previsão (${String(w.forecast_hours).replace('.', ',')} h)</h3>
    <ul class="wx-forecast">${fc}</ul>
    <p class="hint">A Botânica aumenta a previsão em 1 h por ponto no ramo Clima (até ${WEATHER.forecast.max_hours} h).</p>
    <h3>Evento noturno</h3>
    <p class="hint">Todo dia, entre 19:00 e 21:00 no seu fuso, acontece 1 evento de 45 minutos (nunca o mesmo da noite anterior). Ele aparece ${w.warn_minutes} min antes. Vale também para a produção de quem saiu do jogo há menos de 8 h.</p>
    <ul class="wx-events">${WEATHER.night_event.events.map((e) => `<li>${weatherIcon(e.id, 1)}<strong>${esc(e.name_pt)}</strong> <small>${esc(eventEffect(e.id))}</small></li>`).join('')}</ul>
    <h3>Clima do dia</h3>
    <ul class="wx-events">${(['hot_sun', 'rain', 'fog'] as const).map((c) => `<li>${weatherIcon(c, 1)}<strong>${esc(condName(c))}</strong> <small>${esc(condEffect(c))}</small></li>`).join('')}
      <li>${weatherIcon('night', 1)}<strong>Noite</strong> <small>+${WEATHER.effects.night.sales_gold_pct}% ouro nas vendas concluídas à noite, expedições ${EXP.weather_success_pts.night} pontos</small></li></ul>
    ${tzBlock}`;
}

function condEffect(c: 'hot_sun' | 'rain' | 'fog'): string {
  const e = WEATHER.effects[c] as Record<string, number>;
  const out: string[] = [];
  if (e.growth_speed_pct) out.push(`+${e.growth_speed_pct}% velocidade de crescimento`);
  if (e.account_xp_pct) out.push(`+${e.account_xp_pct}% XP da conta`);
  if (e.character_xp_pct) out.push(`+${e.character_xp_pct}% XP dos personagens`);
  const wp = EXP.weather_success_pts;
  if (c === 'rain') out.push(`expedições ${wp.rain} pontos (Carroça ${wp.cart_in_rain})`);
  if (c === 'fog') out.push(`expedições ${wp.fog} pontos`);
  return out.join(', ');
}
