// Guia do jogo (08/11): abinha "Guia" na borda esquerda da tela que abre uma gaveta com cada mecânica explicada por
// partes (arte, título e texto curto), com Anterior/Próximo. Os assuntos lidos ganham ✓ (guardado só neste aparelho);
// na primeira vez que o jogador entra, a gaveta abre sozinha em "Começando".
import { GUIDE } from '../farm/guide';
import { store } from '../farm/store';
import { hudIcon } from './hud-icons';
import { esc } from './panel';

const KEY = 'vif.guide.read';
let topic = GUIDE[0].id;
let page = 0;
let tab: HTMLButtonElement | null = null;
let drawer: HTMLElement | null = null;
let artCount = 0; // artes carregadas no último desenho (redesenha quando chegam)

function readSet(): Set<string> {
  try { return new Set(JSON.parse(localStorage.getItem(KEY) ?? '[]') as string[]); } catch { return new Set(); }
}
function markRead(id: string): void {
  const s = readSet(); s.add(id);
  try { localStorage.setItem(KEY, JSON.stringify([...s])); } catch { /* sem armazenamento: só não lembra */ }
}

/** arte do tamanho da caixa, ampliada em número inteiro quando é pequena (pixel art nítida) */
function art(key: string, box: number): string {
  const m = store.manifest[key];
  if (!m) return '';
  const [w, h] = m.frames && m.frames > 1 ? [m.size[0] / m.frames, m.size[1]] : m.size;
  const k = Math.min(box / w, box / h);
  const s = k >= 1 ? Math.floor(k) : k;
  // tira com vários quadros: mostra só o 1º
  const frames = m.frames && m.frames > 1 ? m.frames : 1;
  return `<span class="g-art" style="width:${Math.round(w * s)}px;height:${Math.round(h * s)}px;background-image:url(assets/${m.file});background-size:${Math.round(w * s * frames)}px ${Math.round(h * s)}px"></span>`;
}

function body(): string {
  const read = readSet();
  const t = GUIDE.find((x) => x.id === topic)!;
  const p = t.pages[page];
  const i = GUIDE.indexOf(t);
  const last = page === t.pages.length - 1, next = GUIDE[i + 1];
  return `<header class="g-head"><h2>Guia do Fazendeiro</h2><button type="button" class="g-x" data-g-close aria-label="Fechar o guia">×</button></header>
    <nav class="g-topics" aria-label="Assuntos">${GUIDE.map((x) => `<button type="button" data-g-topic="${x.id}" aria-current="${x.id === topic}" class="${read.has(x.id) ? 'read' : ''}">
      <span class="g-ico">${art(x.icon, 22)}</span><span>${esc(x.name)}</span>${read.has(x.id) ? '<b aria-label="lido">✓</b>' : ''}</button>`).join('')}</nav>
    <section class="g-page" aria-live="polite">
      <div class="g-pic">${art(p.art, 112)}</div>
      <p class="g-step">${esc(t.name)} · parte ${page + 1} de ${t.pages.length}</p>
      <h3>${esc(p.title)}</h3>
      ${p.text.map((x) => `<p>${esc(x)}</p>`).join('')}
      <div class="g-dots">${t.pages.map((_, k) => `<button type="button" data-g-page="${k}" aria-label="Parte ${k + 1}" aria-current="${k === page}"></button>`).join('')}</div>
      <div class="g-nav">
        <button type="button" class="secondary" data-g-prev ${page === 0 && i === 0 ? 'disabled' : ''}>Anterior</button>
        ${last ? (next ? `<button type="button" class="primary" data-g-next>Próximo: ${esc(next.name)}</button>` : '<button type="button" class="primary" data-g-close>Pronto!</button>')
          : '<button type="button" class="primary" data-g-next>Próximo</button>'}
      </div>
    </section>`;
}

function render(): void {
  if (!drawer) return;
  const t = GUIDE.find((x) => x.id === topic)!;
  if (page === t.pages.length - 1) markRead(topic);
  artCount = Object.keys(store.manifest).length;
  drawer.innerHTML = body();
  drawer.querySelectorAll<HTMLButtonElement>('[data-g-close]').forEach((b) => b.addEventListener('click', () => toggle(false)));
  drawer.querySelectorAll<HTMLButtonElement>('[data-g-topic]').forEach((b) => b.addEventListener('click', () => { topic = b.dataset.gTopic!; page = 0; render(); }));
  drawer.querySelectorAll<HTMLButtonElement>('[data-g-page]').forEach((b) => b.addEventListener('click', () => { page = Number(b.dataset.gPage); render(); }));
  drawer.querySelector('[data-g-prev]')?.addEventListener('click', () => go(-1));
  drawer.querySelector('[data-g-next]')?.addEventListener('click', () => go(1));
  drawer.querySelector('.g-page')?.classList.add('enter');
  refreshTab();
}

/** próxima ou anterior: passa de parte em parte e de assunto em assunto */
function go(d: number): void {
  const i = GUIDE.findIndex((x) => x.id === topic), t = GUIDE[i];
  if (d > 0) {
    if (page < t.pages.length - 1) page++;
    else if (GUIDE[i + 1]) { topic = GUIDE[i + 1].id; page = 0; }
  } else if (page > 0) page--;
  else if (GUIDE[i - 1]) { topic = GUIDE[i - 1].id; page = GUIDE[i - 1].pages.length - 1; }
  render();
}

function toggle(open: boolean): void {
  if (!drawer || !tab) return;
  drawer.classList.toggle('open', open);
  drawer.setAttribute('aria-hidden', String(!open));
  tab.setAttribute('aria-expanded', String(open));
  if (open) { render(); drawer.querySelector<HTMLElement>('[data-g-next], [data-g-close]')?.focus(); }
}

function refreshTab(): void {
  if (!tab) return;
  const unread = GUIDE.filter((t) => !readSet().has(t.id)).length;
  tab.querySelector('.g-badge')?.remove();
  if (unread) tab.insertAdjacentHTML('beforeend', `<span class="g-badge" title="${unread} assunto${unread > 1 ? 's' : ''} para ler">${unread}</span>`);
}

/** monta a abinha e a gaveta uma vez; na 1ª entrada (nada lido) abre sozinha em "Começando" */
export function mountGuide(root: HTMLElement): void {
  if (!tab) {
    tab = document.createElement('button');
    tab.type = 'button';
    tab.className = 'guide-tab';
    tab.title = 'Guia: como funciona cada parte do jogo';
    tab.setAttribute('aria-controls', 'guide');
    tab.innerHTML = `<span class="g-book" aria-hidden="true">${hudIcon('help', 22)}</span><span class="g-label">Guia</span>`;
    tab.addEventListener('click', () => toggle(!drawer!.classList.contains('open')));
    drawer = document.createElement('aside');
    drawer.id = 'guide';
    drawer.className = 'guide';
    drawer.setAttribute('aria-label', 'Guia do jogo');
    drawer.setAttribute('aria-hidden', 'true');
    document.addEventListener('keydown', (e) => {
      if (!drawer?.classList.contains('open')) return;
      if (e.key === 'Escape') toggle(false);
      else if (e.key === 'ArrowRight' && !(e.target instanceof HTMLInputElement)) go(1);
      else if (e.key === 'ArrowLeft' && !(e.target instanceof HTMLInputElement)) go(-1);
    });
  }
  if (!root.contains(tab)) { root.appendChild(tab); root.appendChild(drawer!); }
  tab.hidden = !!store.visit;
  if (store.visit) toggle(false);
  refreshTab();
  if (drawer!.classList.contains('open') && Object.keys(store.manifest).length !== artCount) render();
  if (!readSet().size && !store.visit && !sessionStorageFlag()) toggle(true);
}

/** abre sozinha só uma vez por sessão (não reabre a cada atualização do estado) */
function sessionStorageFlag(): boolean {
  if ((window as unknown as { __vifGuideAuto?: boolean }).__vifGuideAuto) return true;
  (window as unknown as { __vifGuideAuto?: boolean }).__vifGuideAuto = true;
  return false;
}

/** abre o guia num assunto (para botões de ajuda de outras telas) */
export function openGuide(id?: string): void {
  if (id && GUIDE.some((t) => t.id === id)) { topic = id; page = 0; }
  toggle(true);
}
