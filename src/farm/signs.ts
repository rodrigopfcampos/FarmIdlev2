// Plaquinhas do mapa desenhadas pixel a pixel (sem arte externa): tábua com dois postes e um ícone.
// "lock" = lote à venda (lavoura ou pomar); "tree" = pomar já comprado (marca onde fica o pomar).
export type SignIcon = 'lock' | 'tree';

// tábua 18 × 20: o contorno, luz, madeira, veio, postes e capim
const BOARD = [
  '.oooooooooooooooo.',
  'ollllllllllllllllo',
  'olnwwwwwwwwwwwwnwo',
  'olwwwwdwwwwwwwwwdo',
  'olwwwwwwwwwwwwwwdo',
  'oddddddddddddddddo',
  'ollllllllllllllllo',
  'olwwwwwwwwwwdwwwdo',
  'olnwwwwwwwwwwwwndo',
  'oddddddddddddddddo',
  '.oooooooooooooooo.',
  '...oPpo....oPpo...',
  '...oPpo....oPpo...',
  '...oPpo....oPpo...',
  '...oPpo....oPpo...',
  '...oPpo....oPpo...',
  '...oPpo....oPpo...',
  '..hoPpoh..hoPpoh..',
  '.hhhhhhhhhhhhhhhh.',
  '...hhhhhhhhhhhh...',
];

// ícone 6 × 7 por cima da tábua (colunas 6–11, linhas 2–8)
const ICONS: Record<SignIcon, string[]> = {
  lock: [
    '..ss..',
    '.s..s.',
    '.s..s.',
    'yyyyyy',
    'yyKKyy',
    'yyKKyy',
    'yyyyyy',
  ],
  tree: [
    '..ff..',
    '.fFFf.',
    'fFFFFf',
    'fFrFrf',
    '.ffff.',
    '..tt..',
    '..tt..',
  ],
};

export const SIGN_PALETTE: Record<string, number> = {
  o: 0x3b2412, l: 0xe0ad6c, w: 0xb87f47, d: 0x8a5a2e, n: 0x4a3018, p: 0x5a3a1e, P: 0x8a5a2e, h: 0x000000,
  s: 0xd8d8d8, y: 0xf2c230, K: 0x3b2412, f: 0x3f8a2e, F: 0x6cc24a, r: 0xd8402e, t: 0x7a4b25,
};

/** pixels de sombra no chão: pintados com transparência */
export const SIGN_SHADOW = 0x000000;
export const SIGN_SHADOW_ALPHA = 0.28;

/** grade de pixels da placa (null = transparente) */
export function signPixels(icon: SignIcon): (number | null)[][] {
  const rows = BOARD.map((r) => [...r].map((c) => (c === '.' ? null : SIGN_PALETTE[c])));
  ICONS[icon].forEach((r, y) => [...r].forEach((c, x) => { if (c !== '.') rows[2 + y][6 + x] = SIGN_PALETTE[c]; }));
  return rows;
}
