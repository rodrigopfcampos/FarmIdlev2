// Guia do jogo: todo assunto tem partes com título e texto, sem números soltos de config que faltem (undefined/NaN)
import { describe, expect, it } from 'vitest';
import { GUIDE } from '../src/farm/guide';
import { CHARS } from '../src/data';

describe('guia', () => {
  it('cada assunto tem id único, ícone e pelo menos uma parte com título e texto', () => {
    expect(new Set(GUIDE.map((t) => t.id)).size).toBe(GUIDE.length);
    for (const t of GUIDE) {
      expect(t.icon).toBeTruthy();
      expect(t.pages.length).toBeGreaterThan(0);
      for (const p of t.pages) { expect(p.title).toBeTruthy(); expect(p.art).toBeTruthy(); expect(p.text.length).toBeGreaterThan(0); }
    }
  });
  it('nenhum texto ficou com valor faltando da config', () => {
    const all = GUIDE.flatMap((t) => t.pages.flatMap((p) => [p.title, ...p.text])).join('\n');
    expect(all).not.toMatch(/undefined|NaN|\[object/);
  });
  it('os números vêm da config (ex.: vagas de campo)', () => {
    const team = GUIDE.find((t) => t.id === 'equipe')!.pages.flatMap((p) => p.text).join(' ');
    expect(team).toContain(`Só ${CHARS.field_slots} trabalham`);
  });
});
