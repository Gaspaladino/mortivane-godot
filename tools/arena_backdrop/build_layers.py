#!/usr/bin/env python3
"""Extrai da arte da arena (assets/art/novocenario.png) APENAS o primeiro plano que é preservado.

Tudo o que fica atrás do campo (céu, lua, nuvens, montanhas, neblina, castelo, torres, ruínas e arcos)
é DESCARTADO: o fundo novo é desenhado do zero no Godot (scenes/arena/arena_backdrop.tscn).

Rodar a partir da raiz do projeto (ferramenta de desenvolvimento, não roda no jogo):
    pip install pillow numpy scipy opencv-python-headless
    python3 tools/arena_backdrop/build_layers.py

Gera em assets/art/arena_layers/:
    arena.png           chão de pedra, desenho roxo central e muro de ruínas (ArenaLayer)
    architecture_left.png / architecture_right.png
                        pilares, arco, árvores secas, lápide e pedras de cada lado (recortes justos),
                        com a área atrás dos estandartes reconstruída (inpaint)
    banner_left.png     estandartes recortados (balançam por cima)
    banner_right.png
    candles_left.png    chamas e reflexos das velas (brilho somado por cima)
    candles_right.png
e scripts/visuals/backdrop/arena_layers_data.gd (posições; lido pelo ArenaBackdrop).

Separação perto × longe: o fundo antigo é azulado (azul bem acima do vermelho); pedra, madeira e o chão
são neutros. Fica o que é neutro E está ligado ao chão ou às bordas laterais.
"""
import json
import os

import cv2
import numpy as np
from scipy import ndimage as ndi

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "art", "novocenario.png")
OUT = os.path.join(ROOT, "assets", "art", "arena_layers")
DATA = os.path.join(ROOT, "scripts", "visuals", "backdrop", "arena_layers_data.gd")

GROUND_Y = 356            # abaixo disto é sempre chão
WALL_BAND_Y = 262         # faixa do muro: pedras iluminadas pela lua são um pouco azuladas
NEAR_BLUE = 26            # b − r abaixo disto = perto
NEAR_BLUE_WALL = 40
BANNER_BOXES = {"left": (40, 100, 128, 300), "right": (1578, 118, 1662, 295)}   # x0, y0, x1, y1
CANDLE_BOXES = {"left": (30, 280, 150, 356), "right": (1568, 296, 1642, 366)}
FORCED_NEAR = [(28, 90, 150, 362), (1566, 108, 1664, 370)]   # velas e estandartes (roxo, mas perto)
SIDE_LEFT_X = 300         # elementos laterais: fora desta faixa central, acima do chão
SIDE_RIGHT_X = 1380
PAD = 8


def box_mask(shape, b):
    m = np.zeros(shape, bool)
    x0, y0, x1, y1 = b
    m[y0:y1, x0:x1] = True
    return m


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
    out[out[..., 3] == 0, :3] = 0   # transparente sem cor: PNG bem menor (a Godot corrige a borda ao importar)
    return out


def save(name, arr):
    cv2.imwrite(os.path.join(OUT, name), cv2.cvtColor(arr, cv2.COLOR_RGBA2BGRA))


def near_mask(img):
    h, w = img.shape[:2]
    b, g, r = [img[..., i].astype(int) for i in range(3)]
    yy, _ = np.mgrid[0:h, 0:w]
    thr = np.where(yy >= WALL_BAND_Y, NEAR_BLUE_WALL, NEAR_BLUE)
    near = ((b - r) < thr) | (yy > GROUND_Y)
    for bx in FORCED_NEAR:
        near |= box_mask((h, w), bx) & ((b - r) < 70)
    near = ndi.binary_opening(near, iterations=1)
    lab, _ = ndi.label(near)
    touch = set(np.unique(lab[GROUND_Y + 4:, :])) | set(np.unique(lab[:, 0])) | set(np.unique(lab[:, w - 1]))
    touch.discard(0)
    near = np.isin(lab, list(touch))
    holes = ndi.binary_fill_holes(near) & ~near
    lab, n = ndi.label(holes)
    sizes = ndi.sum(holes, lab, range(1, n + 1))
    near |= np.isin(lab, 1 + np.where(sizes < 150)[0])
    return near


def main():
    os.makedirs(OUT, exist_ok=True)
    for old in ("scenery.png", "masks.png", "scenery.png.import", "masks.png.import", "sides.png", "sides.png.import"):
        p = os.path.join(OUT, old)
        if os.path.exists(p):
            os.remove(p)
    img = cv2.imread(SRC)
    h, w = img.shape[:2]
    b, g, r = [img[..., i].astype(int) for i in range(3)]
    luma = 0.3 * r + 0.59 * g + 0.11 * b
    yy, xx = np.mgrid[0:h, 0:w]
    purple = (r > g + 22) & (b > g + 30)

    banners = {}
    for side, bx in BANNER_BOXES.items():
        m = purple & box_mask((h, w), bx)
        banners[side] = largest(ndi.binary_fill_holes(ndi.binary_closing(m, iterations=3)))

    near = near_mask(img)
    # o que fica atrás dos estandartes é reconstruído (o balanço revela o pilar, não outro estandarte)
    hole = np.zeros((h, w), np.uint8)
    for m in banners.values():
        hole |= ndi.binary_dilation(m, iterations=3).astype(np.uint8)
    base = cv2.inpaint(img, hole * 255, 7, cv2.INPAINT_TELEA)

    sides = near & ((xx < SIDE_LEFT_X) | (xx > SIDE_RIGHT_X)) & (yy < GROUND_Y + 16)
    arena = near & ~sides
    save("arena.png", rgba(img, feather(arena, 0.6) * near))
    info = {"size": [w, h], "horizon_y": GROUND_Y, "architecture": {}, "banners": {}, "candles": {}}
    side_rgba = rgba(base, feather(sides, 0.6) * near)
    for side, part in (("left", xx < w / 2), ("right", xx >= w / 2)):
        ys, xs = np.where(sides & part)
        x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
        save("architecture_%s.png" % side, side_rgba[y0:y1, x0:x1])
        info["architecture"][side] = {"pos": [int(x0), int(y0)], "size": [int(x1 - x0), int(y1 - y0)]}

    for side, m in banners.items():
        ys, xs = np.where(m)
        x0, y0, x1, y1 = xs.min() - PAD, ys.min() - PAD, xs.max() + 1 + PAD, ys.max() + 1 + PAD
        crop = rgba(img, feather(ndi.binary_dilation(m, iterations=1), 0.6))[y0:y1, x0:x1]
        save("banner_%s.png" % side, crop)
        info["banners"][side] = {"pos": [int(x0), int(y0)], "size": [int(x1 - x0), int(y1 - y0)], "top": PAD}

    for side, bx in CANDLE_BOXES.items():
        area = box_mask((h, w), bx)
        flame = area & (luma > 140) & ((r > g + 12) | (luma > 200))
        x0, y0, x1, y1 = bx
        save("candles_%s.png" % side, rgba(img, feather(ndi.binary_dilation(flame, iterations=1), 0.8))[y0:y1, x0:x1])
        # chamas = pontos claros pequenos e altos (pontas de vela); reflexos largos no chão ficam de fora
        lab, _ = ndi.label(ndi.binary_dilation(flame & (luma > 170), iterations=2))
        pts = []
        for s in ndi.find_objects(lab):
            hgt, wid = s[0].stop - s[0].start, s[1].stop - s[1].start
            if 5 <= hgt <= 26 and wid <= 12 and hgt >= wid:
                pts.append([round((s[1].start + s[1].stop) / 2, 1), round((s[0].start + s[0].stop) / 2, 1), int(hgt)])
        info["candles"][side] = {"pos": [x0, y0], "size": [x1 - x0, y1 - y0], "flames": pts}

    with open(DATA, "w") as f:
        f.write("class_name ArenaLayersData\nextends RefCounted\n")
        f.write("## GERADO por tools/arena_backdrop/build_layers.py — não editar à mão.\n")
        f.write("## Posições em pixels da arte (1672×941).\n\n")
        f.write("const DATA := " + json.dumps(info, indent="\t") + "\n")
    print("ok", json.dumps(info))


if __name__ == "__main__":
    main()
