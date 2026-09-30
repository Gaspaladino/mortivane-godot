#!/usr/bin/env bash
# Matriz de custo de render das unidades (simulação parada). Só medição.
# Uso: GODOT=/caminho/godot DISPLAY=:99 tools/bench/render_matrix.sh <saida>
#   1) cópia instrumentada (make_probe_copy.py): comandos por parte e draw calls por categoria (pulando cada uma)
#   2) projeto real: tempos (com render e headless) nos modos normal / frozen / squares / hidden
set -u
OUT=${1:?saida}; GODOT=${GODOT:-godot}; ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PROBE=$OUT/probe_project
mkdir -p "$OUT"
python3 "$ROOT/tools/bench/render_probe/make_probe_copy.py" "$ROOT" "$PROBE"
cp "$ROOT/tools/bench/render_breakdown.gd" "$PROBE/tools/bench/"
"$GODOT" --headless --path "$PROBE" --import >/dev/null 2>&1
GL="--rendering-driver opengl3 --resolution 1600x896"
run() {  # projeto rotulo args...
  local proj=$1 label=$2; shift 2
  timeout 300 "$GODOT" --path "$proj" $EXTRA -s res://tools/bench/render_breakdown.gd -- "$@" out="$OUT/$label.json" 2>&1 | grep -E "^RESULT|SCRIPT ERROR" | sed "s/^/$label /"
}
TYPES="warrior u_warrior arc_battlemage u_arc_battlemage sac_paladin u_sac_paladin"
EXTRA=$GL
run "$PROBE" p_hidden enemies=warrior:40 mode=hidden
for t in $TYPES; do
  run "$PROBE" "p_${t}_count" enemies=$t:40 count=1
  for k in contorno preench. linha direto silhueta fx: ; do
    run "$PROBE" "p_${t}_skip_${k%:}" enemies=$t:40 skip="|$k"
  done
done
run "$PROBE" p_hpbar_skip enemies=warrior:40 skip="unit_view|"
for mode in normal frozen squares hidden; do
  EXTRA=$GL;  run "$ROOT" "gl_user80_$mode" allies=u_warrior:40 enemies=warrior:40 mode=$mode seconds=4
  EXTRA=--headless; run "$ROOT" "hl_user80_$mode" allies=u_warrior:40 enemies=warrior:40 mode=$mode seconds=4
done
for spec in "enemies=warrior:40" "allies=u_warrior:2 enemies=warrior:40" "allies=u_warrior:40 enemies=warrior:40"; do
  label=$(echo "$spec" | tr ' =:' '_--')
  EXTRA=$GL; run "$ROOT" "gl_shot_$label" $spec
  EXTRA=--headless; run "$ROOT" "hl_shot_$label" $spec
done
for t in $TYPES; do
  for mode in normal frozen; do
    EXTRA=--headless; run "$ROOT" "hl_${t}_$mode" enemies=$t:40 mode=$mode
    EXTRA=$GL; run "$ROOT" "gl_${t}_$mode" enemies=$t:40 mode=$mode
  done
done
echo FIM
