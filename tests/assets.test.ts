// Toda arte do manifest existe e tem exatamente o tamanho registrado (pixel art sem escala quebrada).
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import sharp from 'sharp';

const manifest = JSON.parse(readFileSync('public/assets/sprites/manifest.json', 'utf8')).sprites as Record<string, { file: string; size: [number, number]; frames?: number }>;

describe('artes recortadas', () => {
  it('tem uma arte para cada nome de tools/assets/sheets.json', () => {
    const sheets = JSON.parse(readFileSync('tools/assets/sheets.json', 'utf8')).sheets as any[];
    let expected = 0;
    for (const sh of sheets) for (const r of sh.regions) expected += r.strip ? r.strip.length : r.names.flat().filter(Boolean).length;
    expect(Object.keys(manifest).length).toBe(expected);
  });
  it('cada PNG tem o tamanho do manifest e fundo transparente', async () => {
    for (const [key, s] of Object.entries(manifest)) {
      const img = sharp(`public/assets/${s.file}`);
      const meta = await img.metadata();
      const w = s.size[0]; // tiras de animação: largura total (quadros × largura)
      expect([key, meta.width, meta.height]).toEqual([key, w, s.size[1]]);
      const { data } = await img.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
      // canto superior esquerdo transparente (as ilustrações de carta ocupam o retângulo todo)
      if (!key.startsWith('card_art_')) expect([key, data[3]]).toEqual([key, 0]);
    }
  });
});
