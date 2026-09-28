#!/usr/bin/env python3
"""Fatia a sprite sheet do Paladino Vivo (arte aprovada) em frames alinhados pelo pivô.

A sheet original (assets/sprites/paladin_live/source/paladin_live_sheet_source.png, 1125×844, fundo
transparente) NÃO é uma grade regular: os frames têm larguras diferentes e os arcos de golpe/brilhos
atravessam a coluna do vizinho. Por isso:

  1. cada linha é uma faixa de y; cada frame é um intervalo de x (medidos na própria imagem, ver LAYOUT);
  2. os pedaços conectados (alfa > 8, inclui brilhos e arcos) vão INTEIROS para o frame onde está o seu
     centro — o arco de um frame não é cortado nem aparece no vizinho;
  3. pivô de cada frame = centro entre os pés no chão: y = base do corpo sólido; x = centro dos pixels
     sólidos nas últimas linhas (os pés). Na morte (corpo deitado) x = centro do corpo;
  4. todos os frames vão para células iguais (CELL) com o pivô no mesmo ponto (PIVOT) → sem pulo entre
     animações. Nada é redimensionado: 1 px da arte = 1 px do atlas.

Saída em assets/sprites/paladin_live/: paladin_live_atlas.png, frames/<anim>_<i>.png,
paladin_live_frames.tres (SpriteFrames) e paladin_live_frames.json (contrato + medidas).

    python3 tools/sprites/slice_paladin_live.py
"""
import json
import os

import numpy as np
import scipy.ndimage as nd
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets/sprites/paladin_live")
SRC = os.path.join(OUT, "source/paladin_live_sheet_source.png")
RES = "res://assets/sprites/paladin_live/"

CELL = (320, 208)
PIVOT = (160, 192)            # centro entre os pés, no chão (px da célula)
SOLID = 200                   # alfa do "corpo" (contorno e pintura), sem brilhos
ANY = 8                       # alfa mínimo de qualquer pixel aproveitado (brilhos, arcos)
CORE = 100                    # alfa dos pedaços usados para separar os frames (o halo fraco dos
                              # brilhos encosta nos vizinhos; ele é distribuído depois, por proximidade)

# Linhas (faixa de y) e frames (intervalos de x), medidos na sheet por projeção do alfa sólido.
# fps / loop: ver ARCHITECTURE.md. `feet` = como achar o x do pivô.
LAYOUT = [
    ("idle", (0, 152), [(126, 247), (256, 388), (405, 530), (535, 670), (677, 811), (815, 956)], 6.0, True, "feet"),
    ("walk", (152, 302), [(47, 170), (185, 309), (313, 441), (446, 573), (578, 701), (708, 835), (836, 969), (971, 1092)], 10.0, True, "feet"),
    ("attack", (302, 470), [(52, 189), (198, 355), (355, 566), (566, 756), (759, 933), (933, 1088)], 12.0, False, "feet"),
    ("defend", (470, 611), [(76, 204), (214, 348), (348, 477), (478, 599)], 10.0, False, "feet"),
    ("taunt", (470, 630), [(616, 742), (755, 885), (892, 1025)], 8.0, False, "feet"),
    ("hit", (611, 739), [(96, 236), (251, 367), (385, 504)], 12.0, False, "feet"),
    ("death", (739, 844), [(52, 173), (173, 323), (333, 475), (490, 656), (671, 845), (861, 1089)], 8.0, False, "body"),
]
# Cortes que não são retas verticais: onde dois frames se sobrepõem de verdade na arte (a capa do
# 4º frame do ataque passa por baixo do fim do arco do 3º). Polilinha (x, y) na sheet; o que fica à
# esquerda é do frame da esquerda. Só vale para pedaços que precisam ser divididos.
CUTS = {("attack", 2): [(574, 302), (572, 366), (561, 383), (553, 400), (548, 420), (548, 470)]}

# Frame do ataque em que a espada atinge (sincronizado com o evento real de dano no jogo).
ATTACK_IMPACT_FRAME = 3


def main() -> None:
    img = np.array(Image.open(SRC).convert("RGBA"))
    alpha = img[:, :, 3]
    lab, n = nd.label(alpha > CORE, structure=np.ones((3, 3)))
    centers = nd.center_of_mass(alpha > CORE, lab, range(1, n + 1))
    sizes = nd.sum(alpha > CORE, lab, range(1, n + 1))

    # dono de cada pedaço: o frame onde está o centro. Pedaço que está de fato em mais de um frame
    # (≥ 15% dos pixels em cada — frames encostados) é dividido pixel a pixel na linha de corte.
    xs_all = np.arange(img.shape[1])
    owner_map = np.full(lab.shape, -1, dtype=np.int32)   # índice global do frame
    frames_idx = [(r, f) for r, l in enumerate(LAYOUT) for f in range(len(l[2]))]
    slices = nd.find_objects(lab)
    for i, sl in enumerate(slices):
        if sl is None or sizes[i] < 3:
            continue
        comp = lab[sl] == i + 1
        cy, cx = centers[i]
        ys, xs = np.nonzero(comp)
        ys = ys + sl[0].start
        xs = xs + sl[1].start
        cand = []
        for g, (r, f) in enumerate(frames_idx):
            name, (y0, y1), cols = LAYOUT[r][0], LAYOUT[r][1], LAYOUT[r][2]
            x0, x1 = cols[f]
            inside = (ys >= y0) & (ys < y1) & (xs >= x0) & (xs < x1)
            share = inside.sum() / len(xs)
            if share > 0:
                cand.append((share, g, x0, x1, y0, y1))
        if not cand:
            continue
        big = [c for c in cand if c[0] >= 0.15]
        if len(big) >= 2:
            for share, g, x0, x1, y0, y1 in cand:
                sel = (ys >= y0) & (ys < y1) & (xs >= x0) & (xs < x1)
                owner_map[ys[sel], xs[sel]] = g
            _apply_cuts(owner_map, ys, xs, frames_idx)
        else:
            best = max(cand)[1] if not big else big[0][1]
            owner_map[ys, xs] = best
    # pixels fracos (brilho, borda suave): mesmo dono do pixel forte mais próximo
    _, (iy, ix) = nd.distance_transform_edt(owner_map < 0, return_indices=True)
    faint = (alpha > ANY) & (owner_map < 0)
    owner_map[faint] = owner_map[iy[faint], ix[faint]]
    os.makedirs(os.path.join(OUT, "frames"), exist_ok=True)
    rows = len(LAYOUT)
    max_frames = max(len(l[2]) for l in LAYOUT)
    atlas = Image.new("RGBA", (CELL[0] * max_frames, CELL[1] * rows), (0, 0, 0, 0))
    meta = {"source": "source/paladin_live_sheet_source.png", "cell": CELL, "pivot": PIVOT,
            "pivot_note": "centro entre os pés, no chão", "attack_impact_frame": ATTACK_IMPACT_FRAME, "animations": []}
    for r, (name, (y0, y1), cols, fps, loop, mode) in enumerate(LAYOUT):
        anim = {"name": name, "fps": fps, "loop": loop, "frames": []}
        for f in range(len(cols)):
            mask = owner_map == frames_idx.index((r, f))
            # tira lascas do vizinho que sobraram do corte: pedaços opacos pequenos e soltos; o brilho
            # fraco só fica perto do que restou
            core = mask & (alpha > CORE)
            fl, fn = nd.label(core, structure=np.ones((3, 3)))
            if fn > 1:
                fs = nd.sum(core, fl, range(1, fn + 1))
                for k, sz in enumerate(fs):
                    if sz < 300 and sz < fs.max() * 0.05:
                        core[fl == k + 1] = False
            near = nd.distance_transform_edt(~core) <= 8
            mask = core | (mask & ~(alpha > CORE) & near)
            frame = np.zeros_like(img)
            frame[mask] = img[mask]
            solid = mask & (alpha > SOLID)
            ys, xs = np.nonzero(solid)
            foot_y = int(ys.max())
            if mode == "feet":
                band = solid[foot_y - 7:foot_y + 1]
                bx = np.nonzero(band)[1]
                foot_x = int(round((bx.min() + bx.max()) / 2))
            else:
                foot_x = int(round((xs.min() + xs.max()) / 2))
            ay, ax = np.nonzero(mask)
            bbox = (int(ax.min()), int(ay.min()), int(ax.max()) + 1, int(ay.max()) + 1)
            # recorta e cola na célula com o pivô no lugar
            crop = Image.fromarray(frame[bbox[1]:bbox[3], bbox[0]:bbox[2]])
            dx = PIVOT[0] - (foot_x - bbox[0])
            dy = PIVOT[1] - (foot_y - bbox[1])
            cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
            cell.alpha_composite(crop, (dx, dy))
            if dx < 0 or dy < 0 or dx + crop.width > CELL[0] or dy + crop.height > CELL[1]:
                raise SystemExit(f"{name}[{f}] não cabe na célula: dx={dx} dy={dy} tam={crop.size}")
            cell.save(os.path.join(OUT, "frames", f"{name}_{f:02d}.png"))
            atlas.alpha_composite(cell, (f * CELL[0], r * CELL[1]))
            sb = solid[bbox[1]:bbox[3], bbox[0]:bbox[2]]
            sy, sx = np.nonzero(sb)
            anim["frames"].append({
                "source_rect": [bbox[0], bbox[1], bbox[2] - bbox[0], bbox[3] - bbox[1]],
                "source_pivot": [foot_x, foot_y],
                # caixa do corpo sólido relativa ao pivô (px da arte): barra de HP, área clicável
                "body": [int(sx.min() + dx - PIVOT[0]), int(sy.min() + dy - PIVOT[1]),
                         int(sx.max() - sx.min() + 1), int(sy.max() - sy.min() + 1)],
            })
        meta["animations"].append(anim)
    atlas.save(os.path.join(OUT, "paladin_live_atlas.png"))
    with open(os.path.join(OUT, "paladin_live_frames.json"), "w") as fh:
        json.dump(meta, fh, indent=1)
    _write_sprite_frames(meta)
    print("slice_paladin_live: OK", {a["name"]: len(a["frames"]) for a in meta["animations"]})


def _apply_cuts(owner_map, ys, xs, frames_idx) -> None:
    """Refaz a divisão dos pixels (ys, xs) nas faixas com corte em polilinha."""
    for (name, f), poly in CUTS.items():
        r = [l[0] for l in LAYOUT].index(name)
        y0, y1 = LAYOUT[r][1]
        left, right = frames_idx.index((r, f)), frames_idx.index((r, f + 1))
        py = np.array([p[1] for p in poly], float)
        px = np.array([p[0] for p in poly], float)
        sel = (ys >= y0) & (ys < y1)
        cur = owner_map[ys[sel], xs[sel]]
        mine = (cur == left) | (cur == right)
        yy, xx = ys[sel][mine], xs[sel][mine]
        cut_x = np.interp(yy, py, px)
        owner_map[yy, xx] = np.where(xx < cut_x, left, right)


def _write_sprite_frames(meta: dict) -> None:
    """SpriteFrames em texto (.tres): um AtlasTexture por frame, na ordem da sheet."""
    subs = []
    anims = []
    sid = 0
    for r, anim in enumerate(meta["animations"]):
        frames = []
        for f in range(len(anim["frames"])):
            sid += 1
            subs.append(f'[sub_resource type="AtlasTexture" id="at_{sid}"]\natlas = ExtResource("1_atlas")\n'
                        f'region = Rect2({f * CELL[0]}, {r * CELL[1]}, {CELL[0]}, {CELL[1]})\n')
            frames.append('{\n"duration": 1.0,\n"texture": SubResource("at_%d")\n}' % sid)
        anims.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %.1f\n}'
                     % (", ".join(frames), "true" if anim["loop"] else "false", anim["name"], anim["fps"]))
    text = (f'[gd_resource type="SpriteFrames" load_steps={sid + 2} format=3]\n\n'
            f'[ext_resource type="Texture2D" path="{RES}paladin_live_atlas.png" id="1_atlas"]\n\n'
            + "\n".join(subs) + "\n[resource]\nanimations = [" + ", ".join(anims) + "]\n")
    with open(os.path.join(OUT, "paladin_live_frames.tres"), "w") as fh:
        fh.write(text)


if __name__ == "__main__":
    main()
