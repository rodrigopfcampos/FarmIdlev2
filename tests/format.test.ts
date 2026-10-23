import { describe, expect, it } from 'vitest';
import { ageOn, formatGold } from '../src/ui/format';

describe('formatGold', () => {
  it('usa ponto de milhar e "mi" para milhões', () => {
    expect(formatGold(2000)).toBe('2.000');
    expect(formatGold(1_500_000)).toBe('1,5 mi');
    expect(formatGold(999.99)).toBe('999');
  });
});

describe('ageOn (cadastro só para 18+)', () => {
  const today = new Date(Date.UTC(2026, 9, 23));
  it('conta a idade certa na véspera e no dia do aniversário', () => {
    expect(ageOn('2008-10-24', today)).toBe(17);
    expect(ageOn('2008-10-23', today)).toBe(18);
  });
  it('recusa data inválida', () => {
    expect(ageOn('2001-02-30', today)).toBeNull();
    expect(ageOn('', today)).toBeNull();
  });
});
