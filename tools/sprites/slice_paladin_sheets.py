#!/usr/bin/env python3
"""Fatia as sprite sheets do Paladino Vivo (arte aprovada) em um atlas alinhado pelo pivô.

Fontes (assets/units/paladin/source/, 2000 × 667, fundo JÁ transparente com borda suave):
    paladin_idle.png  paladin_walk.png  paladin_attack.png  paladin_defend.png  paladin_death.png

As sheets não são grades regulares: os frames têm larguras diferentes e os arcos/brilhos do ataque
atravessam a coluna do vizinho. Por isso:

  1. cada frame é uma faixa entre CORTES (reta vertical ou polilinha medida na própria imagem);
  2. pedaços opacos pequenos que o corte deixou do lado errado vão para o frame cuja massa está mais
     perto; o brilho fraco (borda suave, halo dos arcos) acompanha o pixel opaco mais próximo;
  3. o PIVÔ de cada frame fica nos pés, no chão:
       y = base do corpo (última linha com massa de verdade; ponta de espada fina não conta);
       x = registro do frame contra o frame de referência da animação (máxima sobreposição de uma
           faixa do corpo) → sem tremedeira entre frames:
             "feet"  (idle, attack, defend) — faixa das pernas/pés: os pés ficam parados;
             "torso" (walk)                 — faixa do tronco: o corpo desliza, as pernas alternam;
             "chain" (death)                — corpo inteiro contra o frame anterior, mesmo chão da sheet;
  4. cada sheet é levada ao tamanho da sheet de idle (`scale`: as sheets vieram em escalas diferentes);
  5. todos os frames vão para células iguais com o pivô no mesmo ponto → sem pulo entre animações.
     A arte é reduzida ~2× (INTER_AREA com alfa pré-multiplicado, sem franja escura): no jogo o
     Paladino aparece com ~50 px de altura, e o atlas fica leve.

Saída em assets/units/paladin/: paladin_atlas.png, paladin_frames.tres (SpriteFrames) e
paladin_frames.json (contrato: célula, pivô, frames de origem, retângulos e pivôs medidos).

    python3 tools/sprites/slice_paladin_sheets.py
"""
import json
import math
import os

import cv2
import numpy as np
import scipy.ndimage as nd
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets/units/paladin")
SRC = os.path.join(OUT, "source")
RES = "res://assets/units/paladin/"

DOWNSCALE = 2                 # arte da sheet → atlas
SOLID = 200                   # alfa do "corpo" (contorno e pintura)
CORE = 100                    # alfa dos pedaços usados para decidir o dono de cada região
ANY = 6                       # alfa mínimo aproveitado (borda suave, brilhos)
MIN_ROW = 30                  # px sólidos numa linha para contar como chão (ignora pontas de espada)
PAD = 4                       # folga da célula (px do atlas)

# As sheets vieram em tamanhos diferentes (a de defesa ~20% maior, a de caminhada ~13%...). `scale`
# iguala o Paladino ao da sheet de idle; foi medido casando o elmo do idle (frame 0) em várias escalas
# com cada sheet (cv2.matchTemplate, mediana dos frames com boa correspondência).
# Cortes entre frames: x fixo ou polilinha [(x, y), ...] (o que fica à esquerda é do frame da esquerda).
# `rows` = faixas de y de cada linha da sheet (a sheet de defesa tem duas linhas de quatro).
SHEETS = {
    "idle": {"rows": [(0, 667)], "cuts": [[250, 497, 743, 998, 1247, 1500, 1747]], "anchor": "feet", "scale": 1.0},
    "walk": {"rows": [(0, 667)], "cuts": [[262, 506, 764, 1015, 1265, 1506, 1761]], "anchor": "torso", "scale": 1 / 1.13},
    "attack": {"rows": [(0, 667)], "cuts": [[
        [(225, 0), (225, 300), (246, 310), (246, 667)],
        [(455, 0), (455, 310), (472, 320), (472, 667)],
        [(735, 0), (735, 340), (716, 360), (700, 380), (697, 410), (697, 667)],
        [(1030, 0), (1030, 338), (1028, 348), (1033, 360), (1030, 368), (1040, 378), (1044, 396), (1046, 412),
         (1047, 440), (1040, 452), (1030, 462), (1022, 470), (1020, 667)],
        [(1268, 0), (1268, 330), (1242, 370), (1238, 667)],
        [(1515, 0), (1515, 425), (1530, 450), (1535, 667)],
        1748,
    ]], "anchor": "feet", "scale": 1 / 0.945,
        # o fim do arco do 4º frame passa POR TRÁS da capa do 5º na arte: o corte segue o contorno da
        # capa e o arco some suavemente nos últimos px antes dele (em vez de terminar numa reta)
        "feather": {3: 16}},
    "defend": {"rows": [(0, 320), (320, 667)], "cuts": [[500, 1010, 1510], [500, 1010, 1510]], "anchor": "feet",
               "scale": 1 / 1.20},
    "death": {"rows": [(0, 667)], "cuts": [[218, 427, 648, 881, 1170, 1447, 1703]], "anchor": "chain", "scale": 1 / 0.92},
}

# Animações do jogo → frames das sheets (sheet, índice). fps / loop: ver ARCHITECTURE.md.
#   defend       = ergue o escudo (guarda → giro do escudo → clarão da bênção)   [linha de cima da sheet]
#   defend_hold  = guarda firme, respirando, enquanto o escudo está ativo         [linha de baixo]
#   defend_block = o escudo absorve um golpe (clarão)                             [clarões da linha de cima]
#   taunt        = desafio: giro do escudo e volta à guarda (a provocação real é o anel no raio 115)
ANIMS = [
    ("idle", [("idle", i) for i in range(8)], 7.0, True),
    ("walk", [("walk", i) for i in range(8)], 10.0, True),
    ("attack", [("attack", i) for i in range(8)], 14.0, False),
    ("defend", [("defend", i) for i in range(4)], 12.0, False),
    ("defend_hold", [("defend", i) for i in range(4, 8)], 6.0, True),
    ("defend_block", [("defend", 2), ("defend", 3)], 12.0, False),
    ("taunt", [("defend", 1), ("defend", 0)], 6.0, False),
    ("death", [("death", i) for i in range(8)], 8.0, False),
]
# Frame do ataque em que a espada atinge (clarão do impacto): sincronizado com o evento real de dano.
ATTACK_IMPACT_FRAME = 4


def cut_x(cut, ys):
    if isinstance(cut, (int, float)):
        return np.full(len(ys), float(cut))
    return np.interp(ys, [p[1] for p in cut], [p[0] for p in cut])


def slice_sheet(name: str, spec: dict) -> list:
    """Devolve a lista de frames da sheet: dict(img, mask, strong) em coordenadas da sheet."""
    img = np.array(Image.open(os.path.join(SRC, f"paladin_{name}.png")).convert("RGBA"))
    alpha = img[:, :, 3]
    h, w = alpha.shape
    owner = np.full((h, w), -1, np.int32)
    xs = np.arange(w)
    base = 0
    for (y0, y1), cuts in zip(spec["rows"], spec["cuts"]):
        for y in range(y0, y1):
            k = np.zeros(w, np.int32)
            for c in cuts:
                k += xs >= cut_x(c, np.array([y]))[0]
            owner[y] = base + k
        base += len(cuts) + 1
    n = base
    strong = alpha > CORE
    # massa principal de cada frame (maiores pedaços) e redistribuição dos pedaços pequenos
    main = np.zeros((n, h, w), bool)
    pieces = []
    for f in range(n):
        lab, cnt = nd.label(strong & (owner == f), structure=np.ones((3, 3)))
        if cnt == 0:
            raise SystemExit(f"{name}[{f}] vazio")
        sizes = nd.sum(np.ones_like(lab), lab, range(1, cnt + 1))
        big = sizes.max()
        for k, sz in enumerate(sizes):
            m = lab == k + 1
            if sz >= 0.03 * big or sz >= 1500:
                main[f] |= m
            else:
                pieces.append(m)
    dist = [nd.distance_transform_edt(~main[f]) for f in range(n)]
    strong_owner = np.full((h, w), -1, np.int32)
    for f in range(n):
        strong_owner[main[f]] = f
    for m in pieces:
        d = [dist[f][m].min() for f in range(n)]
        strong_owner[m] = int(np.argmin(d))
    # brilho fraco: mesmo dono do pixel opaco mais próximo
    _, (iy, ix) = nd.distance_transform_edt(strong_owner < 0, return_indices=True)
    final = strong_owner.copy()
    faint = (alpha > ANY) & (strong_owner < 0)
    final[faint] = strong_owner[iy[faint], ix[faint]]
    frames = []
    for f in range(n):
        mask = final == f
        frames.append({"img": img, "mask": mask, "solid": mask & (alpha > SOLID), "fade": None})
    # esmaecimento do frame da esquerda junto de um corte (arcos que passam por trás do vizinho)
    for c, width in spec.get("feather", {}).items():
        y0, y1 = spec["rows"][0]
        ys = np.arange(y0, y1)
        cx = cut_x(spec["cuts"][0][c], ys)
        fade = np.ones((h, w), np.float32)
        fade[y0:y1] = np.clip((cx[:, None] - xs[None, :]) / width, 0.0, 1.0)
        frames[c]["fade"] = fade
    return frames


def baseline(solid: np.ndarray) -> int:
    rows = np.nonzero(solid.sum(1) >= MIN_ROW)[0]
    return int(rows.max())


def _band_overlap(a, ax, ay, b, bx, by, y_lo, y_hi, dx_range):
    """Melhor x de âncora para `a` (pixels sólidos) casando com `b` ancorado em (bx, by).
    Compara as linhas y_lo..y_hi (relativas ao chão, negativas = acima)."""
    best, best_x = -1, ax
    ya = np.arange(ay + y_lo, ay + y_hi)
    yb = np.arange(by + y_lo, by + y_hi)
    A = a[ya]
    B = b[yb]
    for dx in dx_range:
        x = ax + dx
        shift = bx - x                        # desloca A para o referencial de B
        if shift >= 0:
            s = (A[:, : A.shape[1] - shift] & B[:, shift:]).sum() if shift < A.shape[1] else 0
        else:
            s = (A[:, -shift:] & B[:, : B.shape[1] + shift]).sum()
        if s > best:
            best, best_x = s, x
    return best_x


def anchors(frames: list, mode: str) -> list:
    """Pivô (x, y) de cada frame, em px da sheet."""
    out = []
    ref = frames[0]["solid"]
    ref_y = baseline(ref)
    top = int(np.nonzero(ref.any(1))[0].min())
    H = ref_y - top
    band = ref[ref_y - 11:ref_y + 1]
    bx = np.nonzero(band)[1]
    ref_x = int(round((bx.min() + bx.max()) / 2))       # centro entre os pés do frame de referência
    for i, fr in enumerate(frames):
        s = fr["solid"]
        if mode == "chain":
            y = ref_y                                     # mesmo chão da sheet
            if i == 0:
                x = ref_x
            else:
                px, py = out[-1]
                prev = frames[i - 1]["solid"]
                cx = int(np.nonzero(s.any(0))[0].mean())
                ccx = int(np.nonzero(prev.any(0))[0].mean())
                x = _band_overlap(s, cx - ccx + px, y, prev, px, py, -int(H * 0.8), 1, range(-60, 61))
        else:
            y = baseline(s)
            cx = int(round(np.nonzero(s[y - 11:y + 1])[1].mean()))
            if i == 0:
                x = ref_x
            else:
                lo, hi = (-int(H * 0.3), 1) if mode == "feet" else (-int(H * 0.72), -int(H * 0.38))
                x = _band_overlap(s, cx, y, ref, ref_x, ref_y, lo, hi, range(-70, 71))
        out.append((int(x), int(y)))
    return out


def main() -> None:
    sheets = {}
    for name, spec in SHEETS.items():
        frames = slice_sheet(name, spec)
        for fr, (x, y) in zip(frames, anchors(frames, spec["anchor"])):
            fr["pivot"] = (x, y)
            ys, xs = np.nonzero(fr["mask"])
            fr["bbox"] = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
        sheets[name] = frames
    # célula única: maior extensão em volta do pivô, já na escala do atlas
    ext = [0, 0, 0, 0]   # esquerda, direita, cima, baixo
    for name, frames in sheets.items():
        f = SHEETS[name]["scale"] / DOWNSCALE
        for fr in frames:
            (x, y), (x0, y0, x1, y1) = fr["pivot"], fr["bbox"]
            ext = [max(ext[0], (x - x0) * f), max(ext[1], (x1 - x) * f), max(ext[2], (y - y0) * f), max(ext[3], (y1 - y) * f)]
    half = [math.ceil(e) + PAD for e in ext]
    left = right = max(half[0], half[1])              # pivô no meio da largura (espelhar não desloca)
    cell = (left + right, half[2] + half[3])
    pivot = (left, half[2])
    # uma célula por frame de origem usado; as animações só apontam para as células
    used = []
    for _, refs, _, _ in ANIMS:
        for r in refs:
            if r not in used:
                used.append(r)
    cols = 8
    rows = math.ceil(len(used) / cols)
    atlas = Image.new("RGBA", (cell[0] * cols, cell[1] * rows), (0, 0, 0, 0))
    cell_of = {}
    info = {}
    for k, (sheet, i) in enumerate(used):
        fr = sheets[sheet][i]
        f = SHEETS[sheet]["scale"] / DOWNSCALE
        x0, y0, x1, y1 = fr["bbox"]
        px, py = fr["pivot"]
        crop = fr["img"][y0:y1, x0:x1].astype(np.float32)
        crop[~fr["mask"][y0:y1, x0:x1]] = 0
        if fr["fade"] is not None:
            crop[:, :, 3] *= fr["fade"][y0:y1, x0:x1]
        # redução com alfa pré-multiplicado (sem franja escura na borda suave)
        a = crop[:, :, 3:4] / 255.0
        pre = np.concatenate([crop[:, :, :3] * a, a], axis=2)
        size = (max(1, round(crop.shape[1] * f)), max(1, round(crop.shape[0] * f)))
        small = cv2.resize(pre, size, interpolation=cv2.INTER_AREA)
        sa = small[:, :, 3:4]
        rgb = np.where(sa > 0, small[:, :, :3] / np.maximum(sa, 1e-6), 0)
        out = np.concatenate([rgb, sa * 255.0], axis=2).round().clip(0, 255).astype(np.uint8)
        ox = pivot[0] - round((px - x0) * size[0] / crop.shape[1])
        oy = pivot[1] - round((py - y0) * size[1] / crop.shape[0])
        if ox < 0 or oy < 0 or ox + size[0] > cell[0] or oy + size[1] > cell[1]:
            raise SystemExit(f"{sheet}[{i}] não cabe na célula")
        c, r = k % cols, k // cols
        atlas.alpha_composite(Image.fromarray(out, "RGBA"), (c * cell[0] + ox, r * cell[1] + oy))
        cell_of[(sheet, i)] = (c * cell[0], r * cell[1])
        info[(sheet, i)] = {"sheet": f"source/paladin_{sheet}.png", "index": i,
                            "source_rect": [x0, y0, x1 - x0, y1 - y0], "source_pivot": [px, py],
                            "scale": round(f, 4), "cell": [c, r]}
    atlas.save(os.path.join(OUT, "paladin_atlas.png"), optimize=True)
    # medidas da arte parada (idle 0) no atlas: barra de HP e área clicável
    fr = sheets["idle"][0]
    s = fr["solid"]
    ys, xs = np.nonzero(s)
    art_height = (fr["pivot"][1] - ys.min()) / DOWNSCALE
    torso = s[fr["pivot"][1] - int(art_height * DOWNSCALE * 0.6):fr["pivot"][1] - int(art_height * DOWNSCALE * 0.3)]
    tx = np.nonzero(torso)[1]
    meta = {"sources": {n: {"file": f"source/paladin_{n}.png", "scale": round(SHEETS[n]["scale"] / DOWNSCALE, 4)}
                        for n in SHEETS},
            "cell": list(cell), "pivot": list(pivot), "pivot_note": "centro entre os pés, no chão",
            "attack_impact_frame": ATTACK_IMPACT_FRAME, "art_height": round(float(art_height), 1),
            "art_body_width": round(float((tx.max() - tx.min()) / DOWNSCALE), 1), "animations": []}
    for name, refs, fps, loop in ANIMS:
        meta["animations"].append({"name": name, "fps": fps, "loop": loop,
                                   "frames": [info[r] for r in refs]})
    with open(os.path.join(OUT, "paladin_frames.json"), "w") as fh:
        json.dump(meta, fh, indent=1)
    _write_sprite_frames(cell, cell_of)
    print("slice_paladin_sheets: OK", "célula", cell, "pivô", pivot, "atlas", atlas.size,
          {a[0]: len(a[1]) for a in ANIMS}, "altura", meta["art_height"], "largura", meta["art_body_width"])


def _write_sprite_frames(cell, cell_of) -> None:
    """SpriteFrames em texto (.tres): um AtlasTexture por célula; animações apontam para elas."""
    subs = []
    ids = {}
    for key, (x, y) in cell_of.items():
        ids[key] = len(ids) + 1
        subs.append(f'[sub_resource type="AtlasTexture" id="at_{ids[key]}"]\natlas = ExtResource("1_atlas")\n'
                    f'region = Rect2({x}, {y}, {cell[0]}, {cell[1]})\n')
    anims = []
    for name, refs, fps, loop in ANIMS:
        frames = ['{\n"duration": 1.0,\n"texture": SubResource("at_%d")\n}' % ids[r] for r in refs]
        anims.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %.1f\n}'
                     % (", ".join(frames), "true" if loop else "false", name, fps))
    text = (f'[gd_resource type="SpriteFrames" load_steps={len(ids) + 2} format=3]\n\n'
            f'[ext_resource type="Texture2D" path="{RES}paladin_atlas.png" id="1_atlas"]\n\n'
            + "\n".join(subs) + "\n[resource]\nanimations = [" + ", ".join(anims) + "]\n")
    with open(os.path.join(OUT, "paladin_frames.tres"), "w") as fh:
        fh.write(text)


if __name__ == "__main__":
    main()
