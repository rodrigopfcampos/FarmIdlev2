// Relógio da fazenda no cliente. Usa só o horário do servidor e o cronômetro do navegador
// (performance.now), nunca o relógio do aparelho: mudar a hora do celular não muda nada.
export type ClockSync = { farm_time: number; server_now: string; last_activity_at: string; offline_cap_hours: number };

export class FarmClock {
  private base = 0;          // farm_time recebido (s)
  private receivedAt = 0;    // performance.now() na chegada (ms)
  private remaining = 0;     // segundos que a fazenda ainda anda antes do limite offline

  constructor(private now: () => number = () => performance.now()) {}

  sync(s: ClockSync): void {
    this.base = s.farm_time;
    this.receivedAt = this.now();
    const capEnd = Date.parse(s.last_activity_at) + s.offline_cap_hours * 3600_000;
    this.remaining = Math.max(0, (capEnd - Date.parse(s.server_now)) / 1000);
  }

  /** tempo atual da fazenda, em segundos */
  farmNow(): number {
    const elapsed = (this.now() - this.receivedAt) / 1000;
    return this.base + Math.min(Math.max(0, elapsed), this.remaining);
  }
}
