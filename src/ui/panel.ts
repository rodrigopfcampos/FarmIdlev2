// Base dos painéis (UI 16-bit): abrir/fechar, aviso, ação no servidor, [?] de ajuda, seletor de madeira e
// ajudas de desenho (sprites, retratos, ícones) que todas as telas usam.
import { ANIM, ANIMAL_BY_ID, ANIMAL_EMOJI, CLASS_TOOLS, itemInfo, PRODUCT_ART, STALL_RATIO, TOOL_MATERIALS, TOOLS_CFG } from '../data';
import { ICON_VARIANTS, iconSprite, petSprite } from '../farm/art';
import { classDef } from '../farm/rules';
import { applyState, store } from '../farm/store';
import { type FarmState } from '../net/farmApi';
import { hudIcon } from './hud-icons';

const PET_EMOJI: Record<string, string> = { cachorro: '🐶', gato: '🐱', papagaio: '🦜' };
let root: HTMLElement;

let panel: HTMLElement;

let current: (() => void) | null = null; // redesenha o painel aberto quando o estado muda

/** a tela do jogo chama uma vez ao montar: onde ficam o painel e o aviso */
export function initPanel(r: HTMLElement, p: HTMLElement): void { root = r; panel = p; }

/** redesenha o painel aberto (o estado mudou) */
export function rerender(): void { current?.(); }

export const nf1 = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });

export const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

export function sprite(key: string | null, scale = 2, cls = '', filter = '', frame = 0): string {
  const m = key ? store.manifest[key] : null;
  if (!m) return '';
  const [w, h] = m.frame_size ?? m.size;
  // tira de quadros: mostra o quadro pedido; --w e --n servem para a animação em CSS (.px-anim)
  const pos = frame ? `;background-position:${-frame * w * scale}px 0` : '';
  const anim = m.frames ? `;--w:${w * scale}px;--n:${m.frames}` : '';
  return `<span class="px ${cls}" style="width:${w * scale}px;height:${h * scale}px;background-image:url(assets/${m.file});background-size:${m.size[0] * scale}px ${m.size[1] * scale}px${pos}${anim}${filter ? `;filter:${filter}` : ''}"></span>`;
}

/** ícone de um item do Silo: arte (com a variação de cor, se houver) ou emoji provisório */
export function itemIcon(id: string): string {
  const key = iconSprite(store.manifest, id);
  if (key) return sprite(key, 1, '', ICON_VARIANTS[id]?.filter ?? '');
  const art = PRODUCT_ART[id];
  if (art && store.manifest[art]) return sprite(art, 1); // peixe do Lago
  const e = itemInfo(id).emoji;
  return e ? `<span class="pet-face small" aria-hidden="true">${e}</span>` : '';
}

/** animal nas listas: arte ou emoji provisório */
export function animalFace(id: string): string {
  const fish = ANIMAL_BY_ID[id]?.is_fish ? ANIMAL_BY_ID[id].product.art : '';
  if (fish && store.manifest[fish]) return `<span class="pet-face" aria-hidden="true">${sprite(fish, 1.25)}</span>`;
  const key = `animal_${id}_f1`;
  return store.manifest[key] ? `<span class="pet-face" aria-hidden="true">${sprite(key, 1.25)}</span>` : `<span class="pet-face" aria-hidden="true">${ANIMAL_EMOJI[id] ?? '🐾'}</span>`;
}

/** pet nas listas: arte nova parada (e andando quando o mouse passa no card), arte antiga ou emoji provisório */
export function petFace(id: string): string {
  const art = (ANIM.pets_map.sprites as Record<string, { walk?: string; idle?: string; idle_frame?: number }>)[id];
  if (art?.walk && store.manifest[art.walk]) {
    const still = art.idle && store.manifest[art.idle] ? sprite(art.idle, 2, 'pet-still') : sprite(art.walk, 2, 'pet-still', '', art.idle_frame ?? 0);
    return `<span class="pet-face pet-new" aria-hidden="true">${still}${sprite(art.walk, 2, 'pet-walk px-anim')}</span>`;
  }
  const key = petSprite(store.manifest, id);
  return key ? `<span class="pet-face" aria-hidden="true">${sprite(key, 1.5)}</span>` : `<span class="pet-face" aria-hidden="true">${PET_EMOJI[id]}</span>`;
}

// Até as artes chegarem, os outros personagens usam o Agricultor com outra cor (só visual)
const CLASS_HUE: Record<string, number> = { agricultor: 0, rancheira: 150, ferreiro: 200, comerciante: 280, gerente: 40, botanica: 100 };

export function charSprite(cls: string, scale = 2): string {
  // sem a arte de corpo inteiro (Pescador): o retrato reduzido na altura do boneco (48 px)
  if (!store.manifest[`char_${cls}_idle`] && store.manifest[`char_${cls}_portrait`]) return sprite(`char_${cls}_portrait`, scale * 48 / 180);
  const key = store.manifest[`char_${cls}_idle`] ? `char_${cls}_idle` : 'char_agricultor_idle';
  const html = sprite(key, scale);
  return key === 'char_agricultor_idle' && CLASS_HUE[cls] ? html.replace('style="', `style="filter:hue-rotate(${CLASS_HUE[cls]}deg);`) : html;
}

/** retrato do personagem no tamanho nativo da arte (1:1, sem esticar nem borrar) */
export function charPortrait(cls: string): string {
  const key = `char_${cls}_portrait`;
  return store.manifest[key] ? sprite(key, 1, 'portrait') : charSprite(cls, 2);
}

export const className = (id: string) => classDef(id)?.name_pt ?? id;

export const DUR = TOOLS_CFG.tool_durability_rules;

export const toolCard = (cls: string) => CLASS_TOOLS.find((t) => t.class_id === cls)!;

export const matDef = (id: string) => TOOL_MATERIALS.find((m) => m.id === id) ?? TOOL_MATERIALS[0];

/** v3: a ferramenta é a carta dela (Comum) e o "nível da ferramenta" sobe sozinho com a fazenda */
export const toolArt = (cls: string, scale = 0.36) => sprite(`card_full_${(toolCard(cls) as { card_id?: string }).card_id ?? 'enxada'}_common`, scale);

export const toolLevel = (id: string) => TOOL_MATERIALS.findIndex((m) => m.id === id) + 1;

export const nextToolTier = (level: number) => TOOL_MATERIALS.find((m) => m.unlock_level > level);

/** preço da Barraca agora (Comerciante em campo e habilidades sobem) e o bônus de ouro em vendas */
export const stallRatio = () => store.state?.fx?.stall_ratio ?? STALL_RATIO;

export const salesMult = () => 1 + (store.state?.fx?.sales_gold ?? 0);

export const pct = (x: number) => `${nf1.format(x * 100)}%`;

export function toast(msg: string, seconds = 3.5): void {
  const t = root.querySelector<HTMLElement>('#toast')!;
  t.textContent = msg;
  t.classList.add('show');
  window.clearTimeout(Number(t.dataset.timer));
  t.dataset.timer = String(window.setTimeout(() => t.classList.remove('show'), seconds * 1000));
}

export function show(title: string, body: () => string, bind?: (el: HTMLElement) => void): void {
  let again = false; // o [?] aberto continua aberto só quando o mesmo painel redesenha
  const render = () => {
    const scroll = panel.querySelector('.body')?.scrollTop ?? 0;
    const helpOpen = again && !!panel.querySelector('.help-pop:not([hidden])');
    again = true;
    panel.innerHTML = `<div class="panel game-panel" role="dialog" aria-label="${esc(title)}">
      <header><h2>${esc(title)}</h2><button type="button" class="help-btn" aria-label="Ajuda" title="Como funciona" hidden>${hudIcon('help', 18)}</button><button type="button" class="close" aria-label="Fechar">×</button></header>
      <div class="help-pop" role="note" hidden></div>
      <div class="body">${body()}</div></div>`;
    panel.querySelector('.close')!.addEventListener('click', close);
    tidyPanel(panel, helpOpen);
    panel.querySelector('.body')!.scrollTop = scroll;
    bind?.(panel);
  };
  current = render;
  panel.hidden = false;
  panel.querySelector('.body')?.scrollTo(0, 0);
  render();
}

export function close(): void { panel.hidden = true; current = null; }

/** UI 16-bit: as explicações longas (.hint) saem da tela e vão para o [?] do cabeçalho;
 *  todo <select> vira um seletor de madeira (lista própria), mantendo o select escondido para o código de sempre */
export function tidyPanel(el: HTMLElement, helpOpen = false): void {
  const body = el.querySelector<HTMLElement>('.body');
  const pop = el.querySelector<HTMLElement>('.help-pop');
  const btn = el.querySelector<HTMLButtonElement>('.help-btn');
  if (body && pop && btn) {
    const hints = [...body.querySelectorAll<HTMLElement>(':scope > .hint:not(.good):not(.keep)')];
    if (hints.length) {
      pop.innerHTML = hints.map((h) => `<p>${h.innerHTML}</p>`).join('');
      hints.forEach((h) => h.remove());
      btn.hidden = false;
      pop.hidden = !helpOpen;
      btn.setAttribute('aria-expanded', String(helpOpen));
      btn.addEventListener('click', () => { pop.hidden = !pop.hidden; btn.setAttribute('aria-expanded', String(!pop.hidden)); });
    }
  }
  el.querySelectorAll<HTMLSelectElement>('select:not([data-native])').forEach(woodSelect);
}

/** seletor de madeira no lugar do <select> nativo: botão com o valor e lista de opções; ←/→ trocam */
export function woodSelect(sel: HTMLSelectElement): void {
  if (sel.dataset.wood) return;
  sel.dataset.wood = '1';
  sel.hidden = true;
  const box = document.createElement('span');
  box.className = 'wsel';
  const label = () => sel.options[sel.selectedIndex]?.text ?? '';
  box.innerHTML = `<button type="button" class="wsel-arrow" aria-label="Anterior">◀</button><button type="button" class="wsel-btn" aria-haspopup="listbox" aria-expanded="false"></button><button type="button" class="wsel-arrow" aria-label="Próximo">▶</button><ul class="wsel-list" role="listbox" hidden></ul>`;
  const [prev, main, next] = box.querySelectorAll<HTMLButtonElement>('button');
  const list = box.querySelector<HTMLUListElement>('ul')!;
  const pick = (i: number) => {
    if (i < 0 || i >= sel.options.length || i === sel.selectedIndex) return;
    sel.selectedIndex = i;
    sel.dispatchEvent(new Event('change', { bubbles: true }));
    sync();
  };
  const sync = () => {
    main.textContent = label();
    list.innerHTML = [...sel.options].map((o, i) => `<li role="option" data-i="${i}" aria-selected="${i === sel.selectedIndex}">${esc(o.text)}</li>`).join('');
  };
  main.addEventListener('click', () => { list.hidden = !list.hidden; main.setAttribute('aria-expanded', String(!list.hidden)); });
  list.addEventListener('click', (e) => {
    const li = (e.target as HTMLElement).closest<HTMLElement>('li[data-i]');
    if (li) { pick(Number(li.dataset.i)); list.hidden = true; main.setAttribute('aria-expanded', 'false'); }
  });
  prev.addEventListener('click', () => pick(sel.selectedIndex - 1));
  next.addEventListener('click', () => pick(sel.selectedIndex + 1));
  sync();
  sel.after(box);
}

export function openInfo(title: string, text: string): void { show(title, () => `<p>${esc(text)}</p>`); }

export async function act(fn: () => Promise<FarmState>, ok?: string): Promise<void> {
  try { applyState(await fn()); if (ok) toast(ok); } catch (e) { toast(e instanceof Error ? e.message : 'Não deu certo.'); }
}

/** fim da limpeza do lote, se ainda estiver em limpeza */
export function cleanupLeft(lot: string): number | null {
  const l = store.state?.lots.find((x) => x.lot_id === lot);
  const left = l ? l.ready_at - store.clock.farmNow() : 0;
  return left > 0 ? left : null;
}
