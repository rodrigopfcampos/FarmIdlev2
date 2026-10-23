import { describe, expect, it } from 'vitest';
import { FarmClock } from '../src/farm/clock';
import { pointInPolygon, seedlingPositions, stageFor, windOffset } from '../src/farm/geometry';
import { stageSprite } from '../src/farm/art';
import { LOTS } from '../src/data';

describe('relógio da fazenda (não usa a hora do aparelho)', () => {
  it('anda com o cronômetro e para no limite offline', () => {
    let ms = 0;
    const c = new FarmClock(() => ms);
    c.sync({ farm_time: 100, server_now: '2026-10-23T10:00:00Z', last_activity_at: '2026-10-23T10:00:00Z', offline_cap_hours: 8 });
    ms = 60_000;
    expect(c.farmNow()).toBe(160);
    ms = 10 * 3600_000; // 10 h com a aba aberta e sem sincronizar: para em 8 h
    expect(c.farmNow()).toBe(100 + 8 * 3600);
  });
  it('se o jogador já estava fora, só anda o que falta das 8 h', () => {
    let ms = 0;
    const c = new FarmClock(() => ms);
    c.sync({ farm_time: 0, server_now: '2026-10-23T17:00:00Z', last_activity_at: '2026-10-23T10:00:00Z', offline_cap_hours: 8 });
    ms = 3 * 3600_000;
    expect(c.farmNow()).toBe(3600);
  });
});

describe('canteiros', () => {
  const a1 = LOTS.find((l) => l.id === 'A1')!;
  it('6 mudas dentro de cada canteiro, em ordem de profundidade', () => {
    for (const p of a1.plots!) {
      const pos = seedlingPositions(p.polygon);
      expect(pos).toHaveLength(6);
      for (const [x, y] of pos) expect(pointInPolygon(x, y - 3, p.polygon)).toBe(true);
      for (let i = 1; i < pos.length; i++) expect(pos[i][1]).toBeGreaterThanOrEqual(pos[i - 1][1]);
    }
  });
  it('estágios: semente, broto, crescendo e pronto', () => {
    const th = [0.25, 0.55, 0.85]; // limiares de exemplo (os do jogo ficam em farm.json)
    expect([0, 0.3, 0.6, 0.9, 1.2].map((p) => stageFor(p, th))).toEqual([0, 1, 2, 3, 3]);
  });
  it('vento move só pixels inteiros, no máximo a força', () => {
    for (let t = 0; t < 10; t += 0.37) { const o = windOffset(t, 700, 1.6, 1); expect(Number.isInteger(o)).toBe(true); expect(Math.abs(o)).toBeLessThanOrEqual(1); }
  });
  it('usa os estágios próprios do cultivo quando existem, senão os genéricos', () => {
    const m: any = { crop_alface_stage1: {}, crop_cenoura_ready: {} };
    expect(stageSprite(m, 'alface', 0)).toBe('crop_alface_stage1');
    expect(stageSprite(m, 'cenoura', 1)).toBe('crop_generic_stage2');
    expect(stageSprite(m, 'cenoura', 3)).toBe('crop_cenoura_ready');
  });
});

describe('câmera centraliza o mapa', () => {
  it('tela larga e baixa: centraliza na largura e deixa arrastar na altura', async () => {
    const { cameraBounds } = await import('../src/farm/geometry');
    // tela do vídeo: 1920 de largura, ~917 de altura; mapa 1672 × 940
    expect(cameraBounds(1672, 940, 1920, 917, 1)).toEqual([-124, 0, 1920, 940]);
  });
  it('mapa cabe nos dois lados: sobra igual dos dois lados', async () => {
    const { cameraBounds } = await import('../src/farm/geometry');
    expect(cameraBounds(1672, 940, 3840, 2160, 2)).toEqual([-124, -70, 1920, 1080]);
  });
});
