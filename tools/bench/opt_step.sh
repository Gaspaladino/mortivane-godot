#!/usr/bin/env bash
# Conjunto fixo de benchmarks 40×40 usado em cada etapa da otimização (antes/depois).
# Uso: GODOT=/caminho/godot tools/bench/opt_step.sh <commit-ish> <rotulo> <pasta_saida> [secoes]
# Roda a partir de um git worktree do commit (o código em edição não contamina a medição).
# Seções: headless gl realtime (padrão: todas). Precisa de DISPLAY (Xvfb) para gl/realtime.
set -u
REV=${1:?commit}; TAG=${2:?rotulo}; OUT=${3:?pasta}; shift 3
SECTIONS=${*:-"headless gl realtime"}
GODOT=${GODOT:-godot}
export DISPLAY=${DISPLAY:-:99}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
WT=$(mktemp -d /tmp/mortivane_wt_XXXX)
git -C "$REPO" worktree add --detach "$WT" "$REV" >/dev/null 2>&1 || { echo "worktree falhou"; exit 1; }
cd "$WT"
timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1
mkdir -p "$OUT/$TAG"
B="res://tools/bench/stress_bench.gd"
hl() { timeout 900 "$GODOT" --headless --path . --fixed-fps 60 -s $B -- out="$OUT/$TAG" "$@" 2>&1 | grep -E "^BENCH|SCRIPT ERROR"; }
gl() { timeout 1800 "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x896 --fixed-fps 60 --disable-vsync -s $B -- out="$OUT/$TAG" "$@" 2>&1 | grep -E "^BENCH|SCRIPT ERROR"; }
for sec in $SECTIONS; do
	case $sec in
	headless)
		hl allies=40 enemies=40 profile=warriors phase=full warmup=3 seconds=8 label=H_warriors_full
		hl allies=40 enemies=40 profile=mixed phase=full warmup=3 seconds=8 label=H_mixed_full
		hl allies=40 enemies=40 profile=paladins phase=full warmup=3 seconds=8 label=H_paladins_full
		hl allies=40 enemies=40 profile=mixed phase=target warmup=1 seconds=5 label=H_mixed_target
		hl allies=40 enemies=40 profile=warriors phase=full dead_enemies=1 warmup=3 seconds=5 label=H_warriors_40x0_corpses ;;
	gl)
		gl allies=40 enemies=40 profile=warriors phase=full warmup=3 seconds=4 label=G_warriors_full
		gl allies=40 enemies=40 profile=mixed phase=full warmup=3 seconds=4 label=G_mixed_full
		gl allies=40 enemies=40 profile=paladins phase=full warmup=3 seconds=4 label=G_paladins_full
		gl allies=40 enemies=40 profile=warriors phase=full dead_enemies=1 warmup=3 seconds=3 label=G_warriors_40x0_corpses ;;
	realtime)   # relógio real (sem passo fixo): efeito cascata
		timeout 1800 "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x896 --disable-vsync -s $B -- \
			out="$OUT/$TAG" allies=40 enemies=40 profile=mixed phase=full warmup=1 seconds=4 realtime=1 label=R_gl_mixed_realtime 2>&1 | grep -E "^BENCH|SCRIPT ERROR"
		timeout 900 "$GODOT" --headless --path . -s $B -- \
			out="$OUT/$TAG" allies=40 enemies=40 profile=mixed phase=full warmup=1 seconds=8 realtime=1 label=R_headless_mixed_realtime 2>&1 | grep -E "^BENCH|SCRIPT ERROR" ;;
	esac
done
cd "$REPO"
git worktree remove --force "$WT" >/dev/null 2>&1
echo "fim $TAG"
