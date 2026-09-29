#!/usr/bin/env python3
"""Agrega a saída de tools/bench/run_matrix.sh em tabelas Markdown.

Uso: python3 tools/bench/make_report.py <pasta_da_matriz> [saida.md]
Lê <pasta>/*/summary.jsonl e <pasta>/timeline/frames_*.csv. Só stdlib.
"""
import csv
import glob
import json
import os
import sys

ORDER = ["10x10", "20x20", "30x30", "40x40", "40x2", "2x40", "40x20", "20x40", "50x50"]
PHASES = ["spawn", "move", "target", "full"]
PHASE_PT = {"spawn": "A parado", "move": "B movimento", "target": "C alvo/IA", "full": "D combate"}


def load(root, sub):
    out = []
    for f in glob.glob(os.path.join(root, sub, "summary.jsonl")):
        for line in open(f):
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def sc(d):
    return "%dx%d" % (d["allies"], d["enemies"])


def f1(x):
    return "%.1f" % x


def f2(x):
    return "%.2f" % x


def k(x):
    if x >= 1e6:
        return "%.2fM" % (x / 1e6)
    if x >= 1e3:
        return "%.1fk" % (x / 1e3)
    return "%.0f" % x


def table(headers, rows):
    s = "| " + " | ".join(headers) + " |\n|" + "|".join("---" for _ in headers) + "|\n"
    for r in rows:
        s += "| " + " | ".join(str(c) for c in r) + " |\n"
    return s + "\n"


def pick(runs, **kw):
    res = [r for r in runs if all(r.get(a) == b for a, b in kw.items())]
    return res[-1] if res else None


def main():
    root = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "REPORT_TABLES.md")
    md = "# Tabelas do stress test (geradas por tools/bench/make_report.py)\n\n"
    md += "Unidades: ms por quadro; contadores por segundo de JOGO (120 passos da simulação). " \
          "FPS = quadros / tempo de relógio, sem limite de FPS e sem vsync.\n\n"

    hl = load(root, "headless")
    if hl:
        md += "## 1. Matriz headless (CPU da lógica e dos scripts, sem render)\n\n"
        md += "`--headless`: o servidor de render é nulo — os `_draw` rodam (GDScript + chamadas `draw_*`), " \
              "mas nenhum comando vira geometria/GPU. Mede só o custo de CPU dos scripts.\n\n"
        for prof in ["warriors", "sentinels", "mixed"]:
            md += "### Perfil `%s`\n\n" % prof
            rows = []
            for s in ORDER:
                for ph in PHASES:
                    r = next((x for x in hl if x["profile"] == prof and sc(x) == s and x["phase"] == ph), None)
                    if not r:
                        continue
                    rows.append([s, PHASE_PT[ph], f1(r["fps_avg"]), f1(r["fps_min"]), f2(r["frame_ms_avg"]),
                                 f2(r["frame_ms_p95"]), f2(r["frame_ms_max"]),
                                 k(r.get("nearest_calls_per_s", 0)), k(r.get("dist_checks_per_s", 0)),
                                 f2(r["sim_ms"]), f2(r.get("ms_target", 0)), f2(r["view_update_ms"]),
                                 f2(r["draw_ms_total"]), f1(r["redraws"]), "%d" % r["nodes"],
                                 "%.0f+%.0f" % (r["alive_p"], r["alive_e"])])
            md += table(["cenário", "fase", "FPS", "FPS mín", "quadro ms", "p95", "máx", "target calls/s",
                         "dist checks/s", "sim ms", "↳ alvo ms", "update visual ms", "_draw ms", "redraws/quadro",
                         "nós", "vivos"], rows)

        md += "### Escala do targeting (fase D, contadores medidos)\n\n"
        rows = []
        for prof in ["warriors", "sentinels", "mixed"]:
            for s in ORDER:
                r = next((x for x in hl if x["profile"] == prof and sc(x) == s and x["phase"] == "full"), None)
                if not r:
                    continue
                n = r["alive_p"] + r["alive_e"]
                calls = r.get("nearest_calls_per_s", 0)
                rows.append([prof, s, "%.0f" % n, k(calls), "%.1f" % (r.get("examined_per_s", 0) / max(calls, 1)),
                             k(r.get("dist_checks_per_s", 0)), "%.2f" % (r.get("examined_per_s", 0) / 120.0 / max(n * n, 1)),
                             "%.1f%%" % (100.0 * r.get("target_kept_per_s", 0) / max(r.get("target_kept_per_s", 0) + r.get("target_changed_per_s", 0), 1)),
                             k(r.get("target_changed_per_s", 0)), k(r.get("taunt_target_calls_per_s", 0)),
                             k(r.get("projectile_hit_checks_per_s", 0)), f2(r.get("ms_target", 0)),
                             "%.1f" % (1000.0 * r.get("ms_target", 0) * 60.0 / max(calls, 1)) if calls else "-"])
        md += table(["perfil", "cenário", "vivos (média)", "nearest_foe/s", "unidades olhadas/chamada",
                     "dist checks/s", "olhadas por passo ÷ N²", "recálculo deu o mesmo alvo", "trocas de alvo/s",
                     "taunt_target/s", "checagens projétil×unidade/s", "alvo ms/quadro", "µs por chamada"], rows)

    g = load(root, "gl")
    if g:
        md += "## 2. Matriz com render (OpenGL/Compatibility em Xvfb + llvmpipe — GPU por SOFTWARE)\n\n"
        md += "Draw calls, objetos e primitivas são do renderizador real (independem da GPU). Os TEMPOS de " \
              "render aqui são de rasterização em CPU (llvmpipe) e superestimam muito uma GPU real.\n\n"
        rows = []
        for prof in ["warriors", "mixed"]:
            for s in ORDER:
                for ph in ["spawn", "full"]:
                    r = next((x for x in g if x["profile"] == prof and sc(x) == s and x["phase"] == ph), None)
                    if not r:
                        continue
                    n = max(r["views"], 1)
                    rows.append([prof, s, PHASE_PT[ph], f1(r["fps_avg"]), f2(r["frame_ms_avg"]), f2(r["frame_ms_max"]),
                                 "%.0f" % r["draw_calls"], "%.0f" % (r["draw_calls"] / n), k(r["primitives"]),
                                 f2(r["render_cpu_ms"]), f2(r["draw_ms_total"]), f2(r["sim_ms"]), f2(r["view_update_ms"]),
                                 k(r.get("nearest_calls_per_s", 0)), k(r.get("dist_checks_per_s", 0))])
        md += table(["perfil", "cenário", "fase", "FPS", "quadro ms", "máx", "draw calls", "draw calls/unidade",
                     "primitivas", "render ms", "_draw ms", "sim ms", "update visual ms", "target calls/s",
                     "dist checks/s"], rows)

    for sub, title in [("compare_headless", "headless"), ("compare_gl", "com render (llvmpipe)")]:
        c = load(root, sub)
        if not c:
            continue
        md += "## 3. 40×40 — visual × lógica (%s)\n\n" % title
        rows = []
        for r in c:
            rows.append([r["profile"], PHASE_PT[r["phase"]], r["visual"], f1(r["fps_avg"]), f2(r["frame_ms_avg"]),
                         f2(r["frame_ms_max"]), f2(r["sim_ms"]), f2(r["view_update_ms"]), f2(r["draw_ms_total"]),
                         f2(r["render_cpu_ms"]), "%.0f" % r["draw_calls"], "%.0f" % r["nodes"]])
        rows.sort(key=lambda x: (x[0], x[1], x[2]))
        md += table(["perfil", "fase", "visual", "FPS", "quadro ms", "máx", "sim ms", "update visual ms", "_draw ms",
                     "render ms", "draw calls", "nós"], rows)

    o = load(root, "overhead")
    if o:
        md += "## 4. Custo da própria instrumentação (40×40 Guerreiros, headless)\n\n"
        rows = [[r["label"], f1(r["fps_avg"]), f2(r["frame_ms_avg"]), f2(r["frame_ms_p95"]), f2(r["sim_ms"]),
                 f2(r["draw_ms_total"])] for r in o]
        md += table(["execução", "FPS", "quadro ms", "p95", "sim ms (0 = sem cronômetro)", "_draw ms (0 = sem sonda)"], rows)

    rt = load(root, "realtime")
    if rt:
        md += "## 5. Tempo real (sem passo fixo)\n\n"
        rows = [[r["label"], f1(r["fps_avg"]), f2(r["frame_ms_avg"]), f2(r["sim_steps_per_frame"]), f2(r["sim_ms"]),
                 "%.2f" % (r["game_s"] / r["wall_s"])] for r in rt]
        md += table(["execução", "FPS", "quadro ms", "passos da sim por quadro", "sim ms/quadro",
                     "velocidade do jogo (s de jogo por s real)"], rows)

    p = load(root, "paladins")
    if p:
        md += "## 6. Paladinos (provocação + Escudo Sagrado)\n\n"
        rows = []
        for r in p:
            rows.append([sc(r), PHASE_PT[r["phase"]], "gl" if not r["headless"] else "headless", f1(r["fps_avg"]),
                         f2(r["frame_ms_avg"]), f2(r["sim_ms"]), f2(r.get("ms_paladins", 0)), f2(r.get("ms_target", 0)),
                         f2(r["view_update_ms"]), f2(r["draw_ms_total"]), k(r.get("taunt_scans_per_s", 0)),
                         k(r.get("paladin_taunt_checks_per_s", 0)), k(r.get("nearest_forced_per_s", 0)), "%.0f" % r["draw_calls"]])
        md += table(["cenário", "fase", "modo", "FPS", "quadro ms", "sim ms", "↳ habilidade ms", "↳ alvo ms",
                     "update visual ms", "_draw ms", "varreduras `p in units`/s", "checagens de provocação/s",
                     "alvos forçados/s", "draw calls"], rows)

    # detalhamento por categoria (40×40 combate)
    for sub in ["compare_gl", "compare_headless"]:
        for prof in ["warriors", "mixed"]:
            r = pick(load(root, sub), profile=prof, phase="full", visual="normal")
            if not r:
                continue
            md += "## 7. Onde vai o tempo — 40×40 %s, combate, %s\n\n" % (prof, sub.replace("compare_", ""))
            rows = []
            items = [("CombatSim ▸ alvo (nearest_foe)", r.get("ms_target", 0)),
                     ("CombatSim ▸ movimento/alcance", r.get("ms_move", 0)),
                     ("CombatSim ▸ ataque/dano", r.get("ms_attack", 0)),
                     ("CombatSim ▸ lâminas da Sentinela", r.get("ms_swords", 0)),
                     ("CombatSim ▸ passada do Paladino", r.get("ms_paladins", 0)),
                     ("CombatSim ▸ projéteis", r.get("ms_projectiles", 0))]
            for cls, v in r.get("update_by_class", {}).items():
                items.append(("update_visual ▸ " + cls, v["ms_per_frame"]))
            for cat, v in r.get("draw_by_category", {}).items():
                items.append(("_draw ▸ %s (%.0f/quadro)" % (cat, v["draws_per_frame"]), v["ms_per_frame"]))
            items.append(("render (servidor, CPU)", r.get("render_cpu_ms", 0)))
            items.sort(key=lambda x: -x[1])
            total = r["frame_ms_avg"]
            for name, v in items:
                rows.append([name, f2(v), "%.0f%%" % (100.0 * v / total)])
            md += "Quadro médio: %.2f ms (%.1f FPS).\n\n" % (total, r["fps_avg"])
            md += table(["função / sistema", "ms por quadro", "% do quadro"], rows)

    # linha do tempo
    for f in sorted(glob.glob(os.path.join(root, "timeline", "frames_*.csv"))):
        rows_csv = list(csv.DictReader(open(f)))
        if not rows_csv:
            continue
        md += "## 8. Linha do tempo — %s\n\n" % os.path.basename(f)[7:-4]
        buckets = {}
        for i, r in enumerate(rows_csv):
            sec = i // 300   # blocos de 5 s de jogo
            b = buckets.setdefault(sec, [])
            b.append(r)
        rows = []
        for sec in sorted(buckets):
            b = buckets[sec]
            m = lambda key: sum(float(x.get(key) or 0) for x in b) / len(b)
            rows.append(["%d–%d s" % (sec * 5, sec * 5 + 5), "%.0f+%.0f" % (m("alive_p"), m("alive_e")),
                         f2(m("frame_ms")), f2(max(float(x["frame_ms"]) for x in b)), f2(m("us_step") / 1000.0),
                         f2(m("us_target") / 1000.0), f2(m("view_update_ms")), f2(m("draw_ms_total")),
                         "%.0f" % (m("examined") * 60), "%.1f" % (m("projectiles"))])
        md += table(["janela", "vivos", "quadro ms", "máx", "sim ms", "↳ alvo ms", "update visual ms", "_draw ms",
                     "unidades olhadas/s", "projéteis"], rows)

    open(out_path, "w").write(md)
    print("escrito:", out_path)


if __name__ == "__main__":
    main()
