// Ponto de entrada: liga o Phaser (mapa) e a tela de login por cima.
import Phaser from 'phaser';
import { FarmScene } from './scenes/FarmScene';
import { configMissing, loadPlayer, supabase } from './net/supabase';
import { showAuth, showHud, showMessage } from './ui/auth';
import { formatGold } from './ui/format';

new Phaser.Game({
  type: Phaser.AUTO,
  parent: 'game',
  backgroundColor: '#1c1c1c',
  pixelArt: true,
  roundPixels: true,
  scale: { mode: Phaser.Scale.RESIZE, width: window.innerWidth, height: window.innerHeight },
  scene: [FarmScene],
});

const ui = document.getElementById('ui')!;

async function refresh(): Promise<void> {
  const { data } = await supabase!.auth.getSession();
  if (!data.session) { showAuth(ui); return; }
  try {
    const p = await loadPlayer();
    showHud(ui, p.nickname, formatGold(p.gold));
  } catch (e) {
    showMessage(ui, e instanceof Error ? e.message : 'Erro ao carregar.');
  }
}

if (configMissing) {
  showMessage(ui, 'Servidor não configurado: faltam as variáveis VITE_SUPABASE_URL e VITE_SUPABASE_PUBLISHABLE_KEY.');
} else {
  supabase!.auth.onAuthStateChange((event) => {
    if (event === 'SIGNED_IN' || event === 'SIGNED_OUT') void refresh();
  });
  void refresh();
}
