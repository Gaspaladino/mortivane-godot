#!/usr/bin/env python3
"""Tabelas ANTES/DEPOIS por etapa da otimização (saída de tools/bench/opt_step.sh).

Uso: python3 tools/bench/compare_steps.py <pasta> <rotulo0> <rotulo1> ... [--out arquivo.md]
Cada <pasta>/<rotulo>/summary.jsonl tem o mesmo conjunto de cenários (label). Só stdlib.
"""
import json
import os
import sys

METRICS = [
    ("FPS", "fps_avg", "%.1f", +1),
    ("FPS mín", "fps_min", "%.1f", +1),
    ("quadro ms", "frame_ms_avg", "%.2f", -1),
    ("p95 ms", "frame_ms_p95", "%.2f", -1),
    ("sim ms", "sim_ms", "%.2f", -1),
    ("alvo ms", "ms_target", "%.2f", -1),
    ("update visual ms", "view_update_ms", "%.2f", -1),
    ("_draw ms", "draw_ms_total", "%.2f", -1),
    ("render ms", "render_cpu_ms", "%.2f", -1),
    ("draw calls", "draw_calls", "%.0f", -1),
    ("redraws/quadro", "redraws", "%.1f", -1),
    ("buscas de alvo/s", "nearest_calls_per_s", "%.0f", -1),
    ("varreduras/s", "target_scans_per_s", "%.0f", -1),
    ("candidatos/s", "examined_per_s", "%.0f", -1),
    ("passos sim/quadro", "sim_steps_per_frame", "%.2f", 0),
    ("jogo ÷ real", "speed", "%.2f", 0),
]


def load(path):
    out = {}
    f = os.path.join(path, "summary.jsonl")
    if os.path.exists(f):
        for line in open(f):
            if line.strip():
                d = json.loads(line)
                d["speed"] = d["game_s"] / d["wall_s"] if d.get("wall_s") else 0
                out[d["label"]] = d
    return out


def gain(a, b, sense):
    if a is None or b is None or sense == 0:
        return ""
    if a == 0:
        return "—" if b == 0 else ""
    g = (b - a) / abs(a) * 100.0 * sense
    return "%+.0f%%" % g


def main():
    args = sys.argv[1:]
    out_path = None
    if "--out" in args:
        i = args.index("--out")
        out_path = args[i + 1]
        del args[i:i + 2]
    root, tags = args[0], args[1:]
    runs = [load(os.path.join(root, t)) for t in tags]
    labels = []
    for r in runs:
        for k in r:
            if k not in labels:
                labels.append(k)
    md = ""
    for lab in labels:
        md += "### %s\n\n" % lab
        head = ["métrica"] + tags + ["ganho total"]
        md += "| " + " | ".join(head) + " |\n|" + "---|" * len(head) + "\n"
        for name, key, fmt, sense in METRICS:
            vals = [r.get(lab, {}).get(key) for r in runs]
            if all(v is None for v in vals):
                continue
            cells = []
            prev = None
            for v in vals:
                if v is None:
                    cells.append("—")
                else:
                    g = gain(prev, v, sense) if prev is not None else ""
                    cells.append((fmt % v) + (" (%s)" % g if g else ""))
                    prev = v
            first = next((v for v in vals if v is not None), None)
            last = next((v for v in reversed(vals) if v is not None), None)
            md += "| %s | %s | %s |\n" % (name, " | ".join(cells), gain(first, last, sense))
        md += "\n"
    if out_path:
        open(out_path, "w").write(md)
    print(md)


if __name__ == "__main__":
    main()
