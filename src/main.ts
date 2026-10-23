// Ponto de entrada: liga o Phaser (mapa) e a interface; sem login mostra a tela de entrar.
import Phaser from 'phaser';
import { BootScene } from './scenes/BootScene';
import { FarmScene } from './scenes/FarmScene';
import { configMissing, supabase } from './net/supabase';
import { enableMockIfAsked } from './net/farmApi';
import { showAuth, showMessage } from './ui/auth';
import { mountGameUi } from './ui/game-ui';
import { startSync, stopSync } from './farm/store';

const game = new Phaser.Game({
  type: Phaser.AUTO,
  parent: 'game',
  backgroundColor: '#1c1c1c',
  pixelArt: true,
  roundPixels: true,
  scale: { mode: Phaser.Scale.RESIZE, width: window.innerWidth, height: window.innerHeight },
  scene: [BootScene, FarmScene],
});

if (import.meta.env.DEV) (window as unknown as { game: Phaser.Game }).game = game; // só para depurar

const ui = document.getElementById('ui')!;
let inGame = false;

function enterGame(): void {
  if (inGame) return;
  inGame = true;
  ui.classList.add('in-game');
  mountGameUi(ui);
  startSync();
}

function leaveGame(): void {
  inGame = false;
  ui.classList.remove('in-game');
  stopSync();
  showAuth(ui);
}

async function boot(): Promise<void> {
  if (await enableMockIfAsked()) { enterGame(); return; }
  if (configMissing) { showMessage(ui, 'Servidor não configurado: faltam as variáveis VITE_SUPABASE_URL e VITE_SUPABASE_PUBLISHABLE_KEY.'); return; }
  supabase!.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_OUT') leaveGame();
    else if (session && (event === 'SIGNED_IN' || event === 'INITIAL_SESSION')) enterGame();
    else if (event === 'INITIAL_SESSION') leaveGame();
  });
}
void boot();
