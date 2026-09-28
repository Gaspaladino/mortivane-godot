#!/usr/bin/env python3
"""Decompõe a arte da arena (assets/art/novocenario.png) em camadas para o fundo animado.

Rodar a partir da raiz do projeto (ferramenta de desenvolvimento, não roda no jogo):
    pip install pillow numpy scipy opencv-python-headless
    python3 tools/arena_backdrop/build_layers.py

Gera em assets/art/arena_layers/:
    scenery.png         tudo que NÃO é céu (montanhas, castelos, ruínas, árvores, chão), com a área dos
                        estandartes reconstruída por trás (inpaint) para o balanço revelar o fundo certo
    banner_left.png     estandartes recortados (com margem), desenhados por cima com balanço
    banner_right.png
    candles_left.png    chamas/reflexos das velas (brilho que tremula, somado por cima)
    candles_right.png
    masks.png           R = onde as nuvens pintadas podem fluir (céu longe das bordas e da lua)
                        G = vale distante (onde a neblina aparece)
                        B = luzes roxas do castelo (desfocadas)
                        A = céu (suave), recorte das nuvens procedurais
    ../../../scripts/visuals/backdrop/arena_layers_data.gd
                        posições, tamanhos, lua e pontos de luz das velas (gerado; lido pelo ArenaBackdrop)

O céu em si é a própria arte original (novocenario.png), desenhada por baixo de tudo.
"""
import json
import os

import cv2
import numpy as np
from scipy import ndimage as ndi

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "art", "novocenario.png")
OUT = os.path.join(ROOT, "assets", "art", "arena_layers")

MOON_CENTER = (1222, 70)
MOON_RADIUS = 72
BANNER_BOXES = {"left": (40, 100, 128, 300), "right": (1578, 118, 1662, 295)}   # x0, y0, x1, y1
CANDLE_BOXES = {"left": (30, 280, 150, 356), "right": (1568, 296, 1642, 366)}
CASTLE_BOXES = [(300, 0, 640, 330), (1300, 60, 1560, 280)]
PAD = 8   # margem dos recortes (o balanço desloca a amostragem)


def box_mask(shape, b):
    m = np.zeros(shape, bool)
    x0, y0, x1, y1 = b
    m[y0:y1, x0:x1] = True
    return m


def sky_mask(img, luma):
    h, w = img.shape[:2]
    b, g, r = [img[..., i].astype(int) for i in range(3)]
    blur = cv2.GaussianBlur(img, (3, 3), 0)
    flood = np.zeros((h + 2, w + 2), np.uint8)
    skylike = (b > r + 25) & (b > g + 12) & (b > 60)
    for x in range(0, w, 24):
        for y in (4, 30, 60):
            if skylike[y, x] and flood[y + 1, x + 1] == 0:
                cv2.floodFill(blur, flood, (x, y), (0, 0, 0), (4, 4, 4), (4, 4, 4),
                              cv2.FLOODFILL_MASK_ONLY | (255 << 8) | 4)
    m = flood[1:-1, 1:-1] > 0
    yy, xx = np.mgrid[0:h, 0:w]
    moon = ((xx - MOON_CENTER[0]) ** 2 + (yy - MOON_CENTER[1]) ** 2 <= MOON_RADIUS ** 2) & ((r + g + b) > 330)
    m |= moon
    # nuvens: buracos mais claros que o céu em volta (ou pequenos)
    holes = ndi.binary_fill_holes(m) & ~m
    lab, n = ndi.label(holes)
    for i in range(1, n + 1):
        comp = lab == i
        ring = ndi.binary_dilation(comp, iterations=4) & m
        if ring.sum() and (comp.sum() < 1500 or luma[comp].mean() >= luma[ring].mean() - 4):
            m |= comp
    # estruturas escuras invadidas pelo preenchimento (pico, torres): bem mais escuras que o céu da linha
    rowmed = np.array([np.median(luma[y][m[y]]) if m[y].sum() > 20 else 0 for y in range(h)])
    m &= ~((luma < 0.62 * rowmed[:, None]) & ~moon)
    m = ndi.binary_opening(m, iterations=2)
    lab, n = ndi.label(m)
    sizes = ndi.sum(m, lab, range(1, n + 1))
    m = np.isin(lab, 1 + np.where(sizes > 400)[0])
    holes = ndi.binary_fill_holes(m) & ~m
    lab, n = ndi.label(holes)
    sizes = ndi.sum(holes, lab, range(1, n + 1))
    m |= np.isin(lab, 1 + np.where(sizes < 200)[0])
    return m, moon


def largest(m):
    lab, n = ndi.label(m)
    if n == 0:
        return m
    sizes = ndi.sum(m, lab, range(1, n + 1))
    return lab == (1 + int(np.argmax(sizes)))


def feather(m, px):
    return np.clip(cv2.GaussianBlur(m.astype(np.float32), (0, 0), px), 0, 1)


def rgba(bgr, alpha):
    out = np.dstack([bgr[..., 2], bgr[..., 1], bgr[..., 0], np.clip(alpha * 255, 0, 255)]).astype(np.uint8)
    return out


def save(name, arr_rgba):
    cv2.imwrite(os.path.join(OUT, name), cv2.cvtColor(arr_rgba, cv2.COLOR_RGBA2BGRA))


def main():
    os.makedirs(OUT, exist_ok=True)
    img = cv2.imread(SRC)
    h, w = img.shape[:2]
    b, g, r = [img[..., i].astype(int) for i in range(3)]
    luma = 0.3 * r + 0.59 * g + 0.11 * b
    yy, xx = np.mgrid[0:h, 0:w]
    purple = (r > g + 22) & (b > g + 30)

    sky, moon = sky_mask(img, luma)

    # estandartes
    banners = {}
    for side, bx in BANNER_BOXES.items():
        m = purple & box_mask((h, w), bx)
        m = largest(ndi.binary_fill_holes(ndi.binary_closing(m, iterations=3)))
        banners[side] = m

    # cenário: não-céu, com os estandartes reconstruídos por trás
    scenery = img.copy()
    hole = np.zeros((h, w), np.uint8)
    for m in banners.values():
        hole |= ndi.binary_dilation(m, iterations=3).astype(np.uint8)
    scenery = cv2.inpaint(scenery, hole * 255, 7, cv2.INPAINT_TELEA)
    non_sky = ~ndi.binary_erosion(sky, iterations=1)
    save("scenery.png", rgba(scenery, feather(non_sky, 0.8)))

    # recortes dos estandartes (com margem), e onde fica a haste (topo do tecido)
    info = {"size": [w, h], "moon": {"center": list(MOON_CENTER), "radius": MOON_RADIUS}, "banners": {}, "candles": {}}
    for side, m in banners.items():
        ys, xs = np.where(m)
        x0, y0, x1, y1 = xs.min() - PAD, ys.min() - PAD, xs.max() + 1 + PAD, ys.max() + 1 + PAD
        alpha = feather(ndi.binary_dilation(m, iterations=1), 0.6)
        crop = rgba(img, alpha)[y0:y1, x0:x1]
        save("banner_%s.png" % side, crop)
        info["banners"][side] = {"pos": [int(x0), int(y0)], "size": [int(x1 - x0), int(y1 - y0)], "top": PAD}

    # velas: chamas e reflexos claros; pontos de luz nos agrupamentos
    for side, bx in CANDLE_BOXES.items():
        area = box_mask((h, w), bx)
        flame = area & (luma > 140) & ((r > g + 12) | (luma > 200))
        x0, y0, x1, y1 = bx
        alpha = feather(ndi.binary_dilation(flame, iterations=1), 0.8)
        save("candles_%s.png" % side, rgba(img, alpha)[y0:y1, x0:x1])
        lab, n = ndi.label(ndi.binary_dilation(flame & (luma > 170), iterations=3))
        pts = []
        for s in ndi.find_objects(lab):
            cy, cx = (s[0].start + s[0].stop) / 2, (s[1].start + s[1].stop) / 2
            size = max(s[0].stop - s[0].start, s[1].stop - s[1].start)
            if size >= 6:
                pts.append([round(cx, 1), round(cy, 1), int(size)])
        info["candles"][side] = {"pos": [x0, y0], "size": [x1 - x0, y1 - y0], "lights": pts}

    # máscaras
    moon_zone = ((xx - MOON_CENTER[0]) ** 2 + (yy - MOON_CENTER[1]) ** 2) <= (MOON_RADIUS + 26) ** 2
    flow = feather(ndi.binary_erosion(sky, iterations=12) & ~moon_zone, 8)
    distant = (~sky) & (yy > 110) & (yy < 352) & ((b - r) > 30)
    distant = ndi.binary_opening(distant, iterations=2)
    lab, n = ndi.label(distant)
    sizes = ndi.sum(distant, lab, range(1, n + 1))
    distant = np.isin(lab, 1 + np.where(sizes > 2000)[0])
    fog = feather(distant, 3)
    castle = purple & (luma > 45) & np.logical_or.reduce([box_mask((h, w), bx) for bx in CASTLE_BOXES])
    for m in banners.values():
        castle &= ~ndi.binary_dilation(m, iterations=4)
    castle = ndi.binary_opening(castle, iterations=1)
    glow = np.clip(feather(castle, 5) * 2.2 + feather(castle, 1.2) * 0.8, 0, 1)
    sky_soft = feather(sky, 1.5)
    masks = np.dstack([flow, fog, glow, sky_soft]) * 255
    masks = cv2.resize(masks.astype(np.float32), (w // 2, h // 2), interpolation=cv2.INTER_AREA)
    cv2.imwrite(os.path.join(OUT, "masks.png"),
                cv2.cvtColor(np.clip(masks, 0, 255).astype(np.uint8), cv2.COLOR_RGBA2BGRA))

    data_path = os.path.join(ROOT, "scripts", "visuals", "backdrop", "arena_layers_data.gd")
    with open(data_path, "w") as f:
        f.write("class_name ArenaLayersData\nextends RefCounted\n")
        f.write("## GERADO por tools/arena_backdrop/build_layers.py — não editar à mão.\n")
        f.write("## Posições em pixels da arte (novocenario.png).\n\n")
        f.write("const DATA := " + json.dumps(info, indent="\t").replace('"', '"') + "\n")
    print("ok", json.dumps(info))


if __name__ == "__main__":
    main()
