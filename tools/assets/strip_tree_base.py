# Uso: python3 -I tools/assets/strip_tree_base.py <entrada.png> <saida.png> <colunasxlinhas>
# tira o quadrado de terra do pé da árvore adulta: corta logo abaixo da "cintura" do tronco (linha mais estreita
# entre a copa e o quadrado), deixa 2 linhas de raiz e põe um contorno escuro embaixo
import sys
from PIL import Image
def is_green(p):
    r,g,b,a=p; return a and g>r and g>b-10
def strip_frame(im, root_rows=2):
    im=im.copy(); px=im.load(); W,H=im.size
    rows=[]
    for y in range(H):
        xs=[x for x in range(W) if px[x,y][3]]
        rows.append((min(xs),max(xs),sum(1 for x in xs if is_green(px[x,y]))) if xs else None)
    # 1ª linha sem copa (menos de 3 verdes) depois de uma linha com copa
    start=None
    for y in range(1,H):
        if rows[y] and rows[y-1] and rows[y-1][2]>=6 and rows[y][2]<3: start=y; break
    if start is None: return im
    cand=[y for y in range(start,min(H,start+14)) if rows[y]]
    waist=min(cand,key=lambda y: rows[y][1]-rows[y][0])
    a,b=rows[waist][0],rows[waist][1]
    cut=waist+1
    for y in range(cut,H):
        k=y-cut
        for x in range(W):
            if not px[x,y][3]: continue
            r,g,bb,_=px[x,y]
            keep = k < root_rows and (a-1-k) <= x <= (b+1+k) and not (r>170 and g>110)
            if not keep: px[x,y]=(0,0,0,0)
    for x in range(W):
        for y in range(H-1,-1,-1):
            if px[x,y][3]:
                if y+1<H and y>=cut-1: px[x,y+1]=(40,24,16,255)
                break
    return im
src, dst, grid = sys.argv[1], sys.argv[2], sys.argv[3]
im=Image.open(src).convert('RGBA')
cols,rws=map(int,grid.split('x')); fw,fh=im.width//cols, im.height//rws
out=Image.new('RGBA',im.size,(0,0,0,0))
for j in range(rws):
    for i in range(cols):
        f=im.crop((i*fw,j*fh,(i+1)*fw,(j+1)*fh))
        out.paste(strip_frame(f),(i*fw,j*fh))
out.save(dst)
