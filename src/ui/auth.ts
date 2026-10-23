// Tela de entrada: entrar, criar conta e sair. Fica por cima do mapa (HTML, não Phaser),
// para funcionar com teclado do celular, gerenciador de senhas e leitor de tela.
import { supabase } from '../net/supabase';
import { ageOn } from './format';

type Mode = 'login' | 'signup';

// erro com texto pronto para o jogador (em pt-BR)
class PlayerMessage extends Error {}

const ERRORS: Record<string, string> = {
  'Invalid login credentials': 'E-mail ou senha incorretos.',
  'Email not confirmed': 'Confirme seu e-mail antes de entrar (veja sua caixa de entrada).',
  'User already registered': 'Esse e-mail já tem conta. Use "Entrar".',
};
const translate = (msg: string) => ERRORS[msg] ?? (msg.includes('Password') ? 'A senha precisa ter pelo menos 8 caracteres.' : 'Não deu certo. Tente de novo em instantes.');

export function showAuth(root: HTMLElement): void {
  let mode: Mode = 'login';
  root.innerHTML = '';
  const panel = document.createElement('form');
  panel.className = 'panel auth';
  panel.noValidate = true;
  root.appendChild(panel);

  const render = () => {
    panel.innerHTML = `
      <h1>Village Idle Farm</h1>
      <div class="tabs" role="tablist">
        <button type="button" role="tab" data-mode="login" aria-selected="${mode === 'login'}">Entrar</button>
        <button type="button" role="tab" data-mode="signup" aria-selected="${mode === 'signup'}">Criar conta</button>
      </div>
      <label>E-mail<input name="email" type="email" autocomplete="email" required /></label>
      <label>Senha<input name="password" type="password" minlength="8" autocomplete="${mode === 'login' ? 'current-password' : 'new-password'}" required /></label>
      ${mode === 'signup' ? `
        <label>Apelido<input name="nickname" maxlength="20" minlength="3" autocomplete="nickname" required /></label>
        <label>Data de nascimento<input name="birth_date" type="date" required /></label>` : ''}
      <p class="msg" role="status" aria-live="polite"></p>
      <button type="submit" class="primary">${mode === 'login' ? 'Entrar' : 'Criar conta'}</button>`;
    panel.querySelectorAll<HTMLButtonElement>('[data-mode]').forEach((b) =>
      b.addEventListener('click', () => { mode = b.dataset.mode as Mode; render(); }));
  };
  render();

  panel.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const msg = panel.querySelector<HTMLElement>('.msg')!;
    const button = panel.querySelector<HTMLButtonElement>('button[type=submit]')!;
    const f = new FormData(panel);
    const email = String(f.get('email') ?? '').trim();
    const password = String(f.get('password') ?? '');
    msg.className = 'msg';
    if (!email.includes('@')) { msg.textContent = 'Digite um e-mail válido.'; return; }
    if (password.length < 8) { msg.textContent = 'A senha precisa ter pelo menos 8 caracteres.'; return; }
    button.disabled = true;
    msg.textContent = mode === 'login' ? 'Entrando…' : 'Criando sua fazenda…';
    try {
      if (mode === 'login') {
        const { error } = await supabase!.auth.signInWithPassword({ email, password });
        if (error) throw error;
      } else {
        const nickname = String(f.get('nickname') ?? '').trim();
        const birth = String(f.get('birth_date') ?? '');
        const age = ageOn(birth);
        if (nickname.length < 3) throw new PlayerMessage('O apelido precisa ter de 3 a 20 letras.');
        if (age === null) throw new PlayerMessage('Digite sua data de nascimento.');
        if (age < 18) throw new PlayerMessage('O jogo é para maiores de 18 anos.');
        const { data, error } = await supabase!.auth.signUp({
          email, password,
          options: { data: { nickname, birth_date: birth }, emailRedirectTo: window.location.origin },
        });
        if (error) throw error;
        if (!data.session) {
          msg.className = 'msg ok';
          msg.textContent = 'Conta criada! Abra o e-mail de confirmação e depois volte para entrar.';
          mode = 'login';
          button.disabled = false;
          return;
        }
      }
    } catch (e) {
      msg.textContent = e instanceof PlayerMessage ? e.message : translate(e instanceof Error ? e.message : String(e));
      button.disabled = false;
    }
  });
}

export function showHud(root: HTMLElement, nickname: string, gold: string): void {
  root.innerHTML = `
    <div class="hud">
      <span class="nick">${escapeHtml(nickname)}</span>
      <span class="gold" title="Ouro"><span class="coin" aria-hidden="true"></span>${gold}</span>
      <button type="button" class="logout">Sair</button>
    </div>`;
  root.querySelector('.logout')!.addEventListener('click', () => supabase!.auth.signOut());
}

export function showMessage(root: HTMLElement, text: string): void {
  root.innerHTML = `<div class="panel"><h1>Village Idle Farm</h1><p>${escapeHtml(text)}</p></div>`;
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}
