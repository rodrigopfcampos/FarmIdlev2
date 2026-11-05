# Uso: python3 -I tools/assets/strip_tree_base.py <entrada.png> <saida.png> <colunasxlinhas>
# Tira o quadrado de terra do pé da árvore adulta sem cortar o tronco: da "cintura" do tronco para baixo fica só o que
# tem a cor do tronco e das raízes e está ligado ao tronco (a terra tem outras cores na paleta); depois põe contorno escuro.
import sys
from collections import deque
from PIL import Image

# paleta da arte do dono (pixel art: cores exatas)
TRUNK = {0x5d2d3c, 0x79453c, 0xa06245, 0x915841, 0x633441, 0x441534}
OUTLINE = (2, 3, 24, 255)


def rgb(p):
    return (p[0] << 16) | (p[1] << 8) | p[2]


def is_green(p):
    r, g, b, a = p
    return a and g > r and g > b - 10


def strip_frame(im):
    im = im.copy(); px = im.load(); W, H = im.size
    rows = []
    for y in range(H):
        xs = [x for x in range(W) if px[x, y][3]]
        rows.append((min(xs), max(xs), sum(1 for x in xs if is_green(px[x, y]))) if xs else None)
    # 1ª linha sem copa (menos de 3 verdes) logo depois de uma linha com copa = começo do tronco
    start = next((y for y in range(1, H) if rows[y] and rows[y - 1] and rows[y - 1][2] >= 6 and rows[y][2] < 3), None)
    if start is None: return im
    cand = [y for y in range(start, min(H, start + 14)) if rows[y]]
    waist = min(cand, key=lambda y: rows[y][1] - rows[y][0])
    # tronco e raízes: cor de tronco ligada à cintura (4 vizinhos), da cintura para baixo
    keep = set()
    q = deque((x, waist) for x in range(W) if px[x, waist][3] and rgb(px[x, waist]) in TRUNK)
    while q:
        x, y = q.popleft()
        if (x, y) in keep or not (0 <= x < W and waist <= y < H): continue
        if not px[x, y][3] or rgb(px[x, y]) not in TRUNK: continue
        keep.add((x, y))
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    for y in range(waist + 1, H):
        for x in range(W):
            if (x, y) not in keep: px[x, y] = (0, 0, 0, 0)
    # contorno escuro de 1 px em volta do que ficou embaixo da cintura
    edge = [(x + dx, y + dy) for (x, y) in keep for dx, dy in ((1, 0), (-1, 0), (0, 1)) if y + dy > waist]
    for x, y in edge:
        if 0 <= x < W and 0 <= y < H and not px[x, y][3]: px[x, y] = OUTLINE
    return im


if __name__ == '__main__':
    src, dst, grid = sys.argv[1], sys.argv[2], sys.argv[3]
    im = Image.open(src).convert('RGBA')
    cols, rws = map(int, grid.split('x')); fw, fh = im.width // cols, im.height // rws
    out = Image.new('RGBA', im.size, (0, 0, 0, 0))
    for j in range(rws):
        for i in range(cols):
            out.paste(strip_frame(im.crop((i * fw, j * fh, (i + 1) * fw, (j + 1) * fh))), (i * fw, j * fh))
    out.save(dst)
