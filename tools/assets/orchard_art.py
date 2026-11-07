# Arte do pomar (06/11): monta as 3 fases (muda, jovem, adulta) em quadros de 64×64 a partir das imagens grandes do dono.
#  - muda: usa os 9 quadros da animação do dono (tira o brilho solto do canto), base fixa;
#  - jovem e adulta: as folhas da animação do dono quase não mexem (só o 1º quadro muda), então o balanço é feito aqui:
#    16 quadros de uma onda de vento que sobe pela copa (até 2 px no alto, 0 no tronco); o tronco e o chão não se mexem.
# Uso: python3 -I tools/assets/orchard_art.py <pasta do dono> <pasta de saída (assets/raw/v3)>
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

FRAME = 64          # quadro do jogo
FOOT = 61           # linha do pé (o resto do quadro fica para a copa)
FRAMES = 16         # quadros do balanço (jovem e adulta)
LAG = 2.2           # atraso da onda do pé ao alto da copa (radianos)
GUST = 0.3          # rajada: mistura uma 2ª onda mais rápida
SWAY_PX = 2         # quanto o alto da copa vai para cada lado (px)


def cells(path, cols=3, rows=3):
    im = Image.open(path).convert('RGBA')
    cw, ch = im.width // cols, im.height // rows
    return [im.crop((i * cw, j * ch, (i + 1) * cw, (j + 1) * ch)) for j in range(rows) for i in range(cols)]


def clean(im):
    """só a figura principal: tira pedaços soltos (brilho, folha caindo)"""
    a = np.array(im)
    m = a[:, :, 3] > 128
    lab, n = ndimage.label(m, structure=np.ones((3, 3)))
    if n > 1:
        sizes = ndimage.sum(m, lab, range(1, n + 1))
        keep = np.isin(lab, [k + 1 for k, s in enumerate(sizes) if s >= sizes.max() * 0.02])
        a[~keep] = 0
    return Image.fromarray(a)


def shrink(frames, height):
    """reduz todos os quadros com o mesmo corte e escala (não treme) e põe o pé na linha FOOT, no meio"""
    box = None
    for f in frames:
        b = f.getbbox()
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    s = height / (box[3] - box[1])
    w = round((box[2] - box[0]) * s)
    out = []
    for f in frames:
        c = f.crop(box).resize((w, height), Image.BOX)
        a = np.array(c)
        a[:, :, 3] = np.where(a[:, :, 3] >= 110, 255, 0)  # pixel art: sem meio-transparente
        fr = Image.new('RGBA', (FRAME, FRAME), (0, 0, 0, 0))
        fr.alpha_composite(Image.fromarray(a), ((FRAME - w) // 2, FOOT - height))
        out.append(fr)
    return out


def crown_bottom(im):
    """última linha da copa: depois do miolo da copa, a 1ª linha com pouco verde (começo do tronco)"""
    a = np.array(im).astype(int)
    green = (a[:, :, 3] > 0) & (a[:, :, 1] > a[:, :, 0] + 8) & (a[:, :, 1] > a[:, :, 2])
    g = green.sum(1)
    peak = int(np.argmax(g))
    for y in range(peak, FRAME):
        if g[y] < max(3, g[peak] * 0.18):
            return y
    return FOOT


def sway(base):
    """balanço da copa como vento de verdade: uma onda que sobe do tronco para o alto (cada linha atrasa um pouco
    em relação à de baixo), mais forte no alto e nada no tronco; com a onda, poucas linhas mudam de um quadro para o
    outro, então o movimento corre suave em vez de a copa inteira pular junto"""
    a = np.array(base)
    rows = np.nonzero(a[:, :, 3].any(1))[0]
    top, cb = int(rows.min()), crown_bottom(base)
    out = []
    for k in range(FRAMES):
        b = np.zeros_like(a)
        for y in range(FRAME):
            h = min(1.0, max(0.0, (cb - y) / max(1, cb - top)))      # 0 no pé da copa, 1 no alto
            w = h ** 1.2
            ph = 2 * math.pi * k / FRAMES - LAG * h                   # o alto vem depois (a onda sobe)
            t = math.sin(ph) + GUST * math.sin(2 * ph + 0.8)          # rajada: ida mais lenta que a volta
            # arredonda com um limiar diferente por linha (proporção áurea): as linhas viram de lugar em momentos
            # diferentes, então a copa "escorre" de 1 em 1 px em vez de pular em bloco
            dx = int(math.floor(SWAY_PX * w * t / (1 + GUST) + ((y * 0.618034) % 1)))
            b[y] = np.roll(a[y], dx, axis=0)
        out.append(Image.fromarray(b))
    return out


def sheet(frames):
    """tira em grade quadrada (3×3 para 9 quadros, 4×4 para 16)"""
    n = math.ceil(math.sqrt(len(frames)))
    sh = Image.new('RGBA', (FRAME * n, FRAME * n), (0, 0, 0, 0))
    for k, f in enumerate(frames):
        sh.alpha_composite(f, ((k % n) * FRAME, (k // n) * FRAME))
    return sh


if __name__ == '__main__':
    src, dst = sys.argv[1], sys.argv[2]
    # alturas em px no jogo: muda pequena, jovem média, adulta quase o quadro todo
    muda = shrink([clean(c) for c in cells(os.path.join(src, 'Movimentação da muda.png'))], 24)
    young = shrink([clean(Image.open(os.path.join(src, '7713b0a5-c5d8-4f19-9bac-76082c101e43.png')).convert('RGBA'))], 46)[0]
    adult = shrink([clean(Image.open(os.path.join(src, '6b3891e6-d7ab-4276-b9c7-c0ef077e3fea.png')).convert('RGBA'))], 59)[0]
    for name, frames in (('sprout', muda), ('young', sway(young)), ('adult', sway(adult))):
        frames[0].save(os.path.join(dst, f'orchard_{name}.png'))
        sheet(frames).save(os.path.join(dst, f'orchard_{name}_sway.png'))
    print('ok')
