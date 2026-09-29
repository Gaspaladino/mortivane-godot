#!/usr/bin/env python3
"""Cria uma CÓPIA instrumentada do projeto para medir draw calls por parte (só medição).

Uso: make_probe_copy.py <projeto> <destino>
Na cópia, toda chamada `draw_*(...)` (menos draw_set_transform*) dos visuais de unidade e do UnitView
vira `preload(".../draw_probe.gd").draw_*(self|alvo, ...)`, que conta e pode pular a chamada.
O projeto original não é alterado.
"""
import os, re, shutil, subprocess, sys

src, dst = sys.argv[1], sys.argv[2]
if os.path.exists(dst):
    shutil.rmtree(dst)
files = subprocess.check_output(["git", "-C", src, "ls-files"], text=True).split("\n")
for f in files:
    if not f:
        continue
    os.makedirs(os.path.join(dst, os.path.dirname(f)), exist_ok=True)
    shutil.copy2(os.path.join(src, f), os.path.join(dst, f))
if os.path.isdir(os.path.join(src, ".godot")):
    shutil.copytree(os.path.join(src, ".godot"), os.path.join(dst, ".godot"))

PROBE = "res://scripts/debug/draw_probe.gd"
shutil.copy2(os.path.join(src, "tools/bench/render_probe/draw_probe.gd"), os.path.join(dst, "scripts/debug/draw_probe.gd"))

targets = ["scripts/combat/unit_view.gd"]
for root, _, names in os.walk(os.path.join(dst, "scripts/visuals/units")):
    for n in names:
        if n.endswith(".gd"):
            targets.append(os.path.relpath(os.path.join(root, n), dst))

fns = set()
bare = re.compile(r"(?<![\w.])draw_(?!set_)([a-z_]+)\(")
member = re.compile(r"\b([A-Za-z_]\w*)\.draw_(?!set_)([a-z_]+)\(")
total = 0
for t in targets:
    p = os.path.join(dst, t)
    s = open(p, encoding="utf-8").read()
    lines = s.split("\n")
    out = []
    for line in lines:
        if line.lstrip().startswith("func ") or line.lstrip().startswith("static func ") or line.lstrip().startswith("#"):
            out.append(line)
            continue
        def rm(m):
            fns.add(m.group(2))
            return 'preload("%s").draw_%s(%s, ' % (PROBE, m.group(2), m.group(1))
        def rb(m):
            fns.add(m.group(1))
            return 'preload("%s").draw_%s(self, ' % (PROBE, m.group(1))
        n1 = member.sub(rm, line)
        n2 = bare.sub(rb, n1)
        if n2 != line:
            total += 1
        out.append(n2)
    open(p, "w", encoding="utf-8").write("\n".join(out))

with open(os.path.join(dst, "scripts/debug/draw_probe.gd"), "a", encoding="utf-8") as fp:
    fp.write("\n\n# --- gerado ---\n")
    for fn in sorted(fns):
        fp.write("\nstatic func draw_%s(ci: CanvasItem, ...args: Array) -> void:\n\t_do(ci, &\"draw_%s\", args)\n" % (fn, fn))
print("instrumentado: %d linhas em %d arquivos; funções: %s" % (total, len(targets), ", ".join(sorted(fns))))
