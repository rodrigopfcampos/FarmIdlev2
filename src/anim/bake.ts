// Quadros pré-assados a partir da arte parada, só deslocando linhas em pixels inteiros (sem escala, sem giro).
import Phaser from 'phaser';

/** balanço por faixas: cada linha anda round(ponta × (1 − y/h)^curva) px; a raiz fica parada e a ponta inclina */
export function bakeSway(scene: Phaser.Scene, src: string, out: string, table: number[], curve: number): boolean {
  if (scene.textures.exists(out)) return true;
  if (!scene.textures.exists(src)) return false;
  const img = scene.textures.get(src).getSourceImage() as HTMLImageElement | HTMLCanvasElement;
  const w = img.width, h = img.height;
  const tex = scene.textures.createCanvas(out, w * table.length, h);
  if (!tex) return false;
  const ctx = tex.getContext();
  ctx.imageSmoothingEnabled = false;
  table.forEach((tip, k) => {
    for (let y = 0; y < h; y++) {
      const dx = Math.round(tip * Math.pow(1 - (y + 0.5) / h, curve));
      ctx.drawImage(img, 0, y, w, 1, k * w + dx, y, w, 1);
    }
    tex.add(k, 0, k * w, 0, w, h);
  });
  tex.refresh(); // no Phaser 4 o canvas só sobe para a GPU depois disto
  return true;
}
