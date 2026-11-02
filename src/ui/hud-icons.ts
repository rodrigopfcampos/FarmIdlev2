// Ícones do HUD em pixel art (16×16), desenhados no código: cada letra da grade é uma cor; '.' é transparente.
// Viram SVG com pixels inteiros (crispEdges), ampliados sem borrão.
const PAL: Record<string, string> = {
  k: '#1a0f08', // contorno
  w: '#8a5a2b', W: '#c58a4a', // madeira
  p: '#f3e3c3', P: '#d9c39a', // pergaminho
  b: '#9a7b55', // linhas
  g: '#f2c230', G: '#b8860b', // ouro
  r: '#c0392b', R: '#7d1f16', // vermelho
  u: '#3f7fbf', U: '#24527f', // azul
  e: '#4caf50', E: '#2e7d32', // verde
  s: '#e9b48a', S: '#b9805a', // pele
  v: '#8e5bd6', V: '#5a3596', // roxo
  y: '#ffe08a', // brilho
  n: '#6d6d6d', N: '#3e3e3e', // ferro
};

const ICONS: Record<string, string[]> = {
  // Missões: pergaminho com bastões de madeira
  missions: [
    '................',
    '.kkkkkkkkkkkkkk.',
    'kWwwwwwwwwwwwwWk',
    '.kkkkkkkkkkkkkk.',
    '..kppppppppppk..',
    '..kpbbbbbbbbpk..',
    '..kppppppppppk..',
    '..kpbbbbbbbppk..',
    '..kppppppppppk..',
    '..kpbbbbbbpppk..',
    '..kppppppppppk..',
    '..kpbbbbbppppk..',
    '..kPPPPPPPPPPk..',
    '.kkkkkkkkkkkkkk.',
    'kWwwwwwwwwwwwwWk',
    '.kkkkkkkkkkkkkk.',
  ],
  // Cartas: duas cartas em leque
  cards: [
    '................',
    '.......kkkkkkk..',
    '......kuuuuuuuk.',
    '..kkkkkkkuyuuuk.',
    '.kpppppppkuuuuk.',
    '.kpgggggpkuyuuk.',
    '.kpgrrrgpkuuuuk.',
    '.kpgrrrgpkuyuuk.',
    '.kpgrrrgpkuuuuk.',
    '.kpgggggpkkkkk..',
    '.kpggGggpk......',
    '.kpgggggpk......',
    '.kpppppppk......',
    '.kPPPPPPPk......',
    '..kkkkkkk.......',
    '................',
  ],
  // Grimório (passivas): livro roxo com joia
  passives: [
    '................',
    '...kkkkkkkkkk...',
    '..kVvvvvvvvvvk..',
    '..kVvvvvvvvvvk..',
    '..kVvvkkkkvvvk..',
    '..kVvkgyygkvvk..',
    '..kVvkgggGkvvk..',
    '..kVvvkGGkvvvk..',
    '..kVvvvkkvvvvk..',
    '..kVvvvvvvvvvk..',
    '..kVvvvvvvvvvk..',
    '..kVkkkkkkkkkk..',
    '..kVppppppppppk.',
    '..kkPPPPPPPPPPk.',
    '...kkkkkkkkkkk..',
    '................',
  ],
  // Amigos: duas pessoas
  friends: [
    '................',
    '....kkk.........',
    '...kssSk..kkk...',
    '...ksssk.kssSk..',
    '...kssSk.ksssk..',
    '....kkk..kssSk..',
    '..kkuuukk.kkk...',
    '.kuuuuuUkkeeekk.',
    '.kuuuuuUkeeeeEk.',
    '.kuuuuuUkeeeeEk.',
    '.kuuuuuUkeeeeEk.',
    '..kkkkkk.keeeEk.',
    '..........kkkk..',
    '................',
    '................',
    '................',
  ],
  // Vila: bandeira no mastro
  village: [
    '................',
    '..kk............',
    '..kgkkkkkkkk....',
    '..kWkrrrrrrrk...',
    '..kWkrrryrrrrk..',
    '..kWkrryyyrrrk..',
    '..kWkrrryrrrk...',
    '..kWkRRRRRRk....',
    '..kWkkkkkkk.....',
    '..kWk...........',
    '..kWk...........',
    '..kWk...........',
    '.kkWkk..........',
    'keeeeek.........',
    'kEEEEEk.........',
    '.kkkkk..........',
  ],
  // Silo: baú de madeira com ferragem dourada
  silo: [
    '................',
    '................',
    '...kkkkkkkkkk...',
    '..kWWWWWWWWWWk..',
    '.kWwwwwwwwwwwWk.',
    '.kwwwwwwwwwwwwk.',
    '.kkkkkkkkkkkkkk.',
    '.kGwwwwkkwwwwGk.',
    '.kGwwwkgykwwwGk.',
    '.kGwwwkGgkwwwGk.',
    '.kGwwwwkkwwwwGk.',
    '.kGwwwwwwwwwwGk.',
    '.kGwwwwwwwwwwGk.',
    '.kkkkkkkkkkkkkk.',
    '................',
    '................',
  ],
  // Sair: porta com seta
  logout: [
    '................',
    '..kkkkkkkk......',
    '..kWwwwwwk......',
    '..kWwwwwwk......',
    '..kWwwwwwk..k...',
    '..kWwwwwwk..kk..',
    '..kWwwwgwkkkkgk.',
    '..kWwwwwwkggggGk',
    '..kWwwwwwkkkkGk.',
    '..kWwwwwwk..kk..',
    '..kWwwwwwk..k...',
    '..kWwwwwwk......',
    '..kWwwwwwk......',
    '.kkkkkkkkkk.....',
    '................',
    '................',
  ],
  // Colher e plantar: cesta com verduras
  tend: [
    '................',
    '.....kkkkkk.....',
    '....kWk..kWk....',
    '...kWk....kWk...',
    '..kkeekkrrkkkk..',
    '.kkeEekrrRkeekk.',
    '.kwkkkkkkkkkkwk.',
    '.kWwWwWwWwWwWwk.',
    '.kwWwWwWwWwWwWk.',
    '..kWwWwWwWwWwk..',
    '..kwWwWwWwWwWk..',
    '...kWwWwWwWwk...',
    '...kkkkkkkkkk...',
    '................',
    '................',
    '................',
  ],
  // Estrela da Vila
  star: [
    '................',
    '.......kk.......',
    '......kgyk......',
    '......kgyk......',
    '.....kggygk.....',
    'kkkkkkggggkkkkkk',
    'kyyggggggggggGGk',
    '.kkgggggggggGkk.',
    '...kgggggggGk...',
    '....kggggggk....',
    '...kggGkkgggk...',
    '...kgGk..kGgk...',
    '..kgGk....kGgk..',
    '..kkk......kkk..',
    '................',
    '................',
  ],
  // Moeda (ouro no HUD)
  coin: [
    '................',
    '.....kkkkkk.....',
    '...kkggggggkk...',
    '..kggyyyyyygGk..',
    '..kgyggGGggyGk..',
    '.kgyggGkkGggyGk.',
    '.kgygGkggkGgyGk.',
    '.kgygGkggkGgyGk.',
    '.kgygGkggkGgyGk.',
    '.kgyggGkkGggyGk.',
    '..kgyggGGggyGk..',
    '..kGgyyyyyygGk..',
    '...kkGGGGGGkk...',
    '.....kkkkkk.....',
    '................',
    '................',
  ],
  // Ajuda (?)
  help: [
    '................',
    '....kkkkkkk.....',
    '...kpppppppk....',
    '..kppkkkkkppk...',
    '..kpk.....kpk...',
    '..kkk....kppk...',
    '........kppk....',
    '.......kppk.....',
    '.......kpk......',
    '.......kpk......',
    '.......kkk......',
    '................',
    '.......kkk......',
    '.......kpk......',
    '.......kkk......',
    '................',
  ],
};

const cache = new Map<string, string>();

/** ícone do HUD como <svg> (pixels inteiros); size = lado em px na tela */
export function hudIcon(name: keyof typeof ICONS | string, size = 24, label = ''): string {
  const key = `${name}|${size}|${label}`;
  let svg = cache.get(key);
  if (!svg) {
    const rows = ICONS[name];
    if (!rows) return '';
    let rects = '';
    rows.forEach((row, y) => {
      // junta pixels vizinhos da mesma cor numa faixa (SVG menor)
      let x = 0;
      while (x < row.length) {
        const c = row[x];
        let w = 1;
        while (x + w < row.length && row[x + w] === c) w++;
        if (c !== '.' && PAL[c]) rects += `<rect x="${x}" y="${y}" width="${w}" height="1" fill="${PAL[c]}"/>`;
        x += w;
      }
    });
    svg = `<svg class="pxi" width="${size}" height="${size}" viewBox="0 0 16 16" shape-rendering="crispEdges" xmlns="http://www.w3.org/2000/svg"${label ? ` role="img" aria-label="${label}"` : ' aria-hidden="true"'}>${rects}</svg>`;
    cache.set(key, svg);
  }
  return svg;
}

export const HUD_ICON_NAMES = Object.keys(ICONS);
