// Cena da fazenda (fase 0): só o mapa de fundo, em escala inteira e sem suavização.
// Se a tela for menor que o mapa, o jogador arrasta para ver o resto.
import Phaser from 'phaser';

const MAP_W = 1672;
const MAP_H = 940;

export class FarmScene extends Phaser.Scene {
  constructor() {
    super('farm');
  }

  preload(): void {
    this.load.image('farm_base_map', 'assets/map/farm_base_map.png');
  }

  create(): void {
    this.add.image(0, 0, 'farm_base_map').setOrigin(0, 0);
    const cam = this.cameras.main;
    cam.setRoundPixels(true);
    this.fit();
    this.scale.on('resize', () => this.fit());

    // arrastar para mover a câmera quando o mapa não cabe
    this.input.on('pointermove', (p: Phaser.Input.Pointer) => {
      if (!p.isDown) return;
      cam.scrollX -= (p.x - p.prevPosition.x) / cam.zoom;
      cam.scrollY -= (p.y - p.prevPosition.y) / cam.zoom;
    });
  }

  // zoom inteiro (1×, 2×, 3×…) que cabe na tela; nunca menor que 1×
  private fit(): void {
    const { width, height } = this.scale.gameSize;
    const zoom = Math.max(1, Math.floor(Math.min(width / MAP_W, height / MAP_H)));
    const cam = this.cameras.main;
    cam.setZoom(zoom);
    // mapa cabe: fica centralizado; não cabe: limites para o arrasto não sair do mapa
    if (MAP_W * zoom <= width && MAP_H * zoom <= height) cam.removeBounds();
    else cam.setBounds(0, 0, MAP_W, MAP_H);
    cam.centerOn(MAP_W / 2, MAP_H / 2);
  }
}
