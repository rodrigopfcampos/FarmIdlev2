# Vara de Pescar 32×32 desenhada por código (provisória até chegar a arte do dono), uma por material da ferramenta.
# Uso: python3 -I tools/assets/draw_rod.py   (grava assets/raw/v3/tools/rod_<material>.png)
from PIL import Image
import os

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'raw', 'v3', 'tools')
# (escuro, médio, claro) de cada material, nas cores das outras ferramentas
MATS = {
    'wood': ((74, 44, 26), (128, 82, 48), (176, 124, 78)),
    'copper': ((110, 46, 22), (186, 92, 48), (234, 150, 96)),
    'iron': ((54, 56, 62), (118, 122, 132), (186, 190, 198)),
    'gold': ((138, 88, 10), (226, 170, 34), (255, 226, 110)),
    'crystal': ((96, 10, 24), (196, 28, 52), (255, 112, 130)),
}
OUTLINE = (34, 22, 14, 255)
CORK = ((92, 58, 30), (150, 102, 58))
LINE = (232, 226, 210, 255)


def draw(mat):
    dk, md, lt = MATS[mat]
    im = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
    p = im.load()

    def put(x, y, c):
        if 0 <= x < 32 and 0 <= y < 32:
            p[x, y] = c if len(c) == 4 else (*c, 255)

    # haste na diagonal: do cabo (embaixo à esquerda) até a ponta (em cima à direita)
    pts = [(3 + i, 28 - i) for i in range(24)]
    for i, (x, y) in enumerate(pts):
        thick = 2 if i < 17 else 1
        for d in range(-1, thick + 1):
            put(x + d, y, OUTLINE) if d in (-1, thick) else None
        for d in range(thick):
            put(x + d, y, lt if d == 0 and i >= 9 else (md if i >= 9 else CORK[d % 2]))
        put(x, y + 1, OUTLINE)
    # anéis da linha na haste
    for i in (13, 18, 23):
        x, y = pts[i]
        put(x + 1, y - 1, dk); put(x + 2, y, dk)
    # carretel perto do cabo
    cx, cy = 10, 21
    for dx in range(-2, 3):
        for dy in range(-2, 3):
            if abs(dx) + abs(dy) <= 3:
                put(cx + dx, cy + dy, OUTLINE if abs(dx) + abs(dy) == 3 or max(abs(dx), abs(dy)) == 2 else md)
    put(cx, cy, lt); put(cx - 1, cy - 1, lt); put(cx + 3, cy + 1, dk); put(cx + 4, cy + 1, OUTLINE)
    # linha descendo da ponta com a boia
    tx, ty = pts[-1]
    for y in range(ty + 1, ty + 14):
        put(tx + 1, y, LINE)
    by = ty + 14
    for (dx, dy, c) in [(0, 0, (220, 40, 40)), (1, 0, (220, 40, 40)), (2, 0, (220, 40, 40)), (0, 1, (245, 245, 245)), (1, 1, (245, 245, 245)), (2, 1, (245, 245, 245))]:
        put(tx + dx, by + dy, c)
    for (dx, dy) in [(-1, 0), (-1, 1), (3, 0), (3, 1), (0, -1), (2, -1), (0, 2), (1, 2), (2, 2)]:
        put(tx + dx, by + dy, OUTLINE)
    put(tx + 1, by - 1, LINE); put(tx + 1, by + 3, LINE); put(tx + 1, by + 4, (150, 150, 160))
    return im


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for m in MATS:
        draw(m).save(os.path.join(OUT, f'rod_{m}.png'))
    print('ok', ', '.join(MATS))
