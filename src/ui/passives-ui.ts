// Árvore de Passivas (v3): botão Grimório no topo e modal grande com fundo estrelado. Nós em losango ligados por
// linhas a partir da Fazenda (centro). Só ícones na tela; o tooltip mostra nome, nível e o próximo efeito.
// Estados: bloqueado (cinza, linha pontilhada), disponível (pulsa, linha acesa), comprado/máximo (borda dourada, faíscas).
// Ao comprar: a linha se enche de luz, o nó treme e toca um "pling" gerado pelo navegador (sem arquivo; dá para silenciar).
import { hudIcon } from './hud-icons';
import { ACCOUNT_TREE, LEVELS, type AccountBranch, type AccountNode } from '../data';
import { accountPoints, passiveState } from '../farm/rules';
import { store } from '../farm/store';
import { accountSkillAdd, accountSkillReset, type FarmState } from '../net/farmApi';
import { formatGold } from './format';

export type PassivesCtx = {
  show: (title: string, body: () => string, bind?: (el: HTMLElement) => void) => void;
  act: (fn: () => Promise<FarmState>, ok?: string) => Promise<void>;
  esc: (s: string) => string;
};

// texto de cada efeito: sinal + valor + unidade/descrição
const EFFECT_LABEL: Record<string, string> = {
  instant_growth_chance_pct: '% de chance de a semente nascer pronta',
  animal_production_pct: '% de produção dos animais',
  feed_cost_pct: '% no custo da ração',
  legendary_fish_pct: '% de chance de peixe Lendário (vale o dobro)',
  growth_all_pct: '% de crescimento da lavoura e do pomar',
  double_all_pct: '% das colheitas rendem em dobro',
  stall_price_pts: ' ponto(s) no preço da Barraca',
  vehicle_wear_pct: '% de desgaste dos veículos',
  repair_cost_pct: '% no custo dos consertos',
  tool_wear_pct: '% de desgaste das ferramentas',
  expedition_success_pts: ' ponto(s) de sucesso nas expedições',
  cargo_capacity_pct: '% de carga em todos os veículos',
  first_snack_pct: '% de energia no 1º lanche do dia',
  synergy_energy_pct: '% de gasto de energia com o campo cheio',
  low_energy_use_pct: '% de gasto de energia abaixo de 30%',
  salary_pct: '% nos salários',
  daily_revive_pct: '% de energia ao zerar, 1× por dia',
};
const fmt = (v: number) => `${v > 0 ? '+' : v < 0 ? '−' : ''}${Math.abs(Math.round(v * 10) / 10).toLocaleString('pt-BR')}`;
const effectText = (n: AccountNode, lv: number) => n.effects.map((e) => `${fmt(e.per_point * lv)}${EFFECT_LABEL[e.effect] ?? ` ${e.effect}`}`).join(' · ');

let justBought: string | null = null; // nó recém-comprado (animação da linha e do tremor)
let muted = false;
try { muted = localStorage.getItem('vif.passives.mute') === '1'; } catch { /* sem armazenamento: som ligado */ }

/** "pling" mágico curto: duas notas subindo com brilho, feito pelo navegador */
function pling(): void {
  if (muted) return;
  try {
    const A = (window as unknown as { AudioContext?: typeof AudioContext; webkitAudioContext?: typeof AudioContext });
    const Ctx = A.AudioContext ?? A.webkitAudioContext;
    if (!Ctx) return;
    const ac = new Ctx(), t = ac.currentTime;
    [[880, 0], [1320, 0.07], [1760, 0.14]].forEach(([f, d]) => {
      const o = ac.createOscillator(), g = ac.createGain();
      o.type = 'triangle'; o.frequency.setValueAtTime(f, t + d);
      g.gain.setValueAtTime(0, t + d); g.gain.linearRampToValueAtTime(0.12, t + d + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + d + 0.35);
      o.connect(g).connect(ac.destination); o.start(t + d); o.stop(t + d + 0.4);
    });
    window.setTimeout(() => void ac.close(), 800);
  } catch { /* sem áudio: segue sem som */ }
}

/** HUD: botão do Grimório, com pontinho quando há pontos livres */
export function hudPassives(s: FarmState): string {
  const at = s.account_tree;
  if (!at) return '';
  const free = accountPoints(s.level, at.skills).free;
  return `<button type="button" class="icon-btn" data-passives title="Árvore de Passivas${free ? ` · ${free} ponto${free > 1 ? 's' : ''} livre${free > 1 ? 's' : ''}` : ''}" aria-label="Árvore de Passivas">${hudIcon('passives')}${free ? '<span class="dot"></span>' : ''}</button>`;
}

// linhas: Fazenda → A de cada ramo; A → B e C; B e C → D; D → Ultimate
function edges(br: AccountBranch): [string, string][] {
  const [a, b, c, d, u] = br.nodes.map((n) => n.id);
  return [[ACCOUNT_TREE.root.id, a], [a, b], [a, c], [b, d], [c, d], [d, u]];
}
// espaçamento vertical condensado (a árvore fica mais junta): y da config × 0,8, com folga em cima para os nomes
const SQUEEZE = 0.8, TOP = 70;
const Y = (y: number) => Math.round(TOP + (y - 80) * SQUEEZE);
const posOf = (id: string): [number, number] => {
  const p = id === ACCOUNT_TREE.root.id ? ACCOUNT_TREE.root.pos : ACCOUNT_TREE.branches.flatMap((b) => b.nodes).find((n) => n.id === id)!.pos;
  return [p[0], Y(p[1])];
};
// linha de cada caminho: Natureza = cipó curvo e brilhante; Comércio = ouro sólido; Resistência = vermelha robusta
function edgePath(br: AccountBranch, x1: number, y1: number, x2: number, y2: number): string {
  if (br.id !== 'natureza') return `M${x1} ${y1} L${x2} ${y2}`;
  const mx = (x1 + x2) / 2, my = (y1 + y2) / 2, dx = x2 - x1, dy = y2 - y1, len = Math.hypot(dx, dy) || 1;
  const off = 14; // curva para o lado (como uma raiz)
  return `M${x1} ${y1} Q${Math.round(mx - (dy / len) * off)} ${Math.round(my + (dx / len) * off)} ${x2} ${y2}`;
}

function treeSvg(s: FarmState): string {
  const skills = s.account_tree?.skills ?? {};
  const free = accountPoints(s.level, skills).free;
  const W = ACCOUNT_TREE.canvas[0], H = Y(ACCOUNT_TREE.root.pos[1]) + 40;
  let lines = '', nodes = '';
  for (const br of ACCOUNT_TREE.branches) {
    for (const [from, to] of edges(br)) {
      const [x1, y1] = posOf(from), [x2, y2] = posOf(to);
      // a linha só acende quando o nó de onde ela sai tem pelo menos 1 ponto (a Fazenda sempre está acesa)
      const on = from === ACCOUNT_TREE.root.id || (skills[from] ?? 0) > 0;
      const anim = justBought === to ? ' fill' : '';
      lines += `<path class="pl ${br.id} ${on ? 'on' : 'off'}${anim}" d="${edgePath(br, x1, y1, x2, y2)}" style="--bc:${br.color_hex}" pathLength="100"/>`;
    }
    for (const n of br.nodes) {
      const st = passiveState(n.id, skills, free).state;
      const r = n.ultimate ? 28 : 21, lv = skills[n.id] ?? 0;
      const [x, y] = posOf(n.id);
      const sparks = st === 'maxed' ? [0, 1, 2].map((k) => `<circle class="spark-dot" r="1.8" cx="${(k - 1) * r * 0.7}" cy="${-r}" style="animation-delay:${k * 0.5}s"/>`).join('') : '';
      // pontos investidos: quadradinhos embaixo do losango, na cor do caminho
      const pw = 7, gap = 3, tot = n.max * pw + (n.max - 1) * gap;
      const pips = Array.from({ length: n.max }, (_, k) => `<rect class="pip ${k < lv ? 'got' : ''}" x="${-tot / 2 + k * (pw + gap)}" y="${r + 7}" width="${pw}" height="${pw}"/>`).join('');
      nodes += `<g class="pn ${st}${n.ultimate ? ' ult' : ''}${justBought === n.id ? ' shake' : ''}" transform="translate(${x} ${y})" style="--bc:${br.color_hex}"
          data-node="${n.id}" tabindex="0" role="button" aria-label="${n.name_pt} ${lv} de ${n.max}">
        <polygon class="halo" points="0,${-r - 6} ${r + 6},0 0,${r + 6} ${-r - 6},0"/>
        <polygon class="dia" points="0,${-r} ${r},0 0,${r} ${-r},0"/>
        <text class="ico" y="1" font-size="${n.ultimate ? 24 : 18}">${n.icon}</text>${sparks}<g class="pips">${pips}</g></g>`;
    }
  }
  const [rx, ry] = posOf(ACCOUNT_TREE.root.id);
  nodes += `<g class="pn root" transform="translate(${rx} ${ry})"><circle class="dia" r="25"/><text class="ico" y="1" font-size="22">${ACCOUNT_TREE.root.icon}</text></g>`;
  const labels = ACCOUNT_TREE.branches.map((br) => { const [x, y] = posOf(br.nodes[4].id); return `<text class="bl" x="${x}" y="${y - 40}" style="fill:${br.color_hex}">${br.name_pt}</text>`; }).join('');
  return `<svg class="ptree" viewBox="0 0 ${W} ${H}" role="img" aria-label="Árvore de Passivas">${lines}${labels}${nodes}</svg>`;
}

function tipHtml(ctx: PassivesCtx, s: FarmState, id: string): string {
  const skills = s.account_tree?.skills ?? {};
  const free = accountPoints(s.level, skills).free;
  const br = ACCOUNT_TREE.branches.find((b) => b.nodes.some((n) => n.id === id))!;
  const n = br.nodes.find((x) => x.id === id)!;
  const lv = skills[id] ?? 0, st = passiveState(id, skills, free);
  const now = lv ? `<p>Agora: ${ctx.esc(effectText(n, lv))}</p>` : '';
  const next = lv < n.max ? `<p class="next">${lv ? 'Próximo' : 'Ao comprar'}: ${ctx.esc(effectText(n, lv + 1))}</p>` : '<p class="next">No máximo.</p>';
  const cost = n.cost > 1 ? ` · custa ${n.cost} pontos` : '';
  const lock = st.why.length ? `<p class="bad">Precisa: ${ctx.esc(st.why.join(', '))}</p>` : lv < n.max && free < n.cost ? `<p class="bad">Faltam pontos (${free} livre${free === 1 ? '' : 's'}).</p>` : '';
  return `<strong style="color:${br.color_hex}">${n.ultimate ? '★ ' : ''}${ctx.esc(n.name_pt)}</strong><small>${ctx.esc(br.name_pt)} · ${lv}/${n.max}${cost}</small>
    <p>${ctx.esc(n.text_pt)}</p>${now}${next}${lock}`;
}

export function openPassives(ctx: PassivesCtx): void {
  ctx.show(ACCOUNT_TREE.name_pt, () => {
    const s = store.state;
    if (!s?.account_tree) return '<p>Carregando…</p>';
    const at = s.account_tree, pts = accountPoints(s.level, at.skills);
    const resetCost = LEVELS[s.level - 1].reference_income_per_day * ACCOUNT_TREE.extra_reset_cost_R_ratio;
    return `<div class="ptree-wrap">
      <div class="ptree-bar"><span>Pontos livres <strong>${pts.free}</strong> de ${pts.total}</span>
        <span class="btns"><button type="button" class="secondary small" data-mute title="${muted ? 'Ligar som' : 'Silenciar'}">${muted ? '🔇' : '🔊'}</button>
        <button type="button" class="secondary small" data-preset ${pts.spent ? '' : 'disabled'}>${at.free_reset ? 'Resetar (grátis esta semana)' : `Resetar · ${formatGold(resetCost)}`}</button></span></div>
      ${treeSvg(s)}<div class="ptip" hidden></div>
      <p class="hint">1 ponto por nível da fazenda. Cada caminho tem 4 passivas de até 5 pontos e uma Ultimate (5 pontos, pede 15 no caminho). Passe o mouse num nó para ver; clique para comprar.</p></div>`;
  }, (el) => {
    el.querySelector('.game-panel')?.classList.add('tree-panel');
    const s = store.state!, tip = el.querySelector<HTMLElement>('.ptip')!, wrap = el.querySelector<HTMLElement>('.ptree-wrap')!;
    const place = (g: Element) => {
      const r = g.getBoundingClientRect(), w = wrap.getBoundingClientRect();
      tip.innerHTML = tipHtml(ctx, store.state ?? s, (g as HTMLElement).dataset.node!);
      tip.hidden = false;
      const left = Math.min(w.width - 250, Math.max(4, r.left - w.left + r.width / 2 - 120));
      const top = r.top - w.top > 170 ? r.top - w.top - tip.offsetHeight - 6 : r.bottom - w.top + 6;
      tip.style.left = `${left}px`; tip.style.top = `${top}px`;
    };
    el.querySelectorAll<SVGGElement>('.pn[data-node]').forEach((g) => {
      g.addEventListener('mouseenter', () => place(g));
      g.addEventListener('focus', () => place(g));
      g.addEventListener('mouseleave', () => { tip.hidden = true; });
      g.addEventListener('blur', () => { tip.hidden = true; });
      const buy = () => {
        const id = g.dataset.node!, st = passiveState(id, store.state!.account_tree!.skills, accountPoints(store.state!.level, store.state!.account_tree!.skills).free).state;
        g.classList.remove('tap'); void g.getBoundingClientRect(); g.classList.add('tap'); // tremor de clique (100 ms)
        if (st !== 'available' && st !== 'bought') { place(g); return; }
        justBought = id;
        pling();
        void ctx.act(() => accountSkillAdd(id)).finally(() => window.setTimeout(() => { justBought = null; }, 900));
      };
      g.addEventListener('click', buy);
      g.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); buy(); } });
    });
    el.querySelector('[data-mute]')?.addEventListener('click', (e) => {
      muted = !muted;
      try { localStorage.setItem('vif.passives.mute', muted ? '1' : '0'); } catch { /* sem armazenamento */ }
      (e.currentTarget as HTMLButtonElement).textContent = muted ? '🔇' : '🔊';
    });
    el.querySelector('[data-preset]')?.addEventListener('click', (e) => {
      (e.currentTarget as HTMLButtonElement).disabled = true;
      void ctx.act(() => accountSkillReset(), 'Pontos devolvidos.');
    });
  });
}
