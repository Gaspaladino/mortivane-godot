#!/usr/bin/env bash
# Matriz do stress test (ver tools/bench/README.md). Uso:
#   GODOT=/caminho/godot tools/bench/run_matrix.sh <pasta_de_saida> [secoes...]
# Seções: headless gl compare overhead realtime paladins timeline profiler (padrão: todas).
# As execuções são sequenciais de propósito (execuções em paralelo disputam CPU e sujam os tempos).
# Para "gl" é preciso um display (ex.: Xvfb :99) — DISPLAY=:99 por padrão.
set -u
OUT=${1:?pasta de saída}
shift
SECTIONS=${*:-"headless gl compare overhead realtime paladins timeline profiler"}
GODOT=${GODOT:-godot}
export DISPLAY=${DISPLAY:-:99}
cd "$(dirname "$0")/../.."
mkdir -p "$OUT"
SCEN="10x10 20x20 30x30 40x40 40x2 2x40 40x20 20x40 50x50"

hl() {   # headless, passo fixo: custo de CPU da lógica e dos scripts (sem render)
	local out=$1; shift
	timeout 900 "$GODOT" --headless --path . --fixed-fps 60 -s res://tools/bench/stress_bench.gd -- out="$out" "$@" 2>&1 | grep -E "^BENCH|SCRIPT ERROR" | tee -a "$OUT/log.txt"
}
gl() {   # janela real (OpenGL / Compatibility), passo fixo: inclui render e draw calls
	local out=$1; shift
	timeout 1800 "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x896 --fixed-fps 60 --disable-vsync \
		-s res://tools/bench/stress_bench.gd -- out="$out" "$@" 2>&1 | grep -E "^BENCH|SCRIPT ERROR" | tee -a "$OUT/log.txt"
}
dims() { echo "allies=${1%x*} enemies=${1#*x}"; }
phase_args() {   # combate: descarta 3 s (aproximação) e mede 8 s; demais fases: 1 s + 5 s
	if [ "$1" = full ]; then echo "phase=full warmup=3 seconds=8"; else echo "phase=$1 warmup=1 seconds=5"; fi
}

for sec in $SECTIONS; do
	echo "=== $sec ===" | tee -a "$OUT/log.txt"
	case $sec in
	headless)   # 9 cenários × 3 perfis × 4 fases, visual normal
		for prof in warriors sentinels mixed; do
			for s in $SCEN; do
				for ph in spawn move target full; do
					hl "$OUT/headless" $(dims $s) profile=$prof $(phase_args $ph)
				done
			done
		done ;;
	gl)   # render real: parado e combate, 2 perfis
		for prof in warriors mixed; do
			for s in $SCEN; do
				gl "$OUT/gl" $(dims $s) profile=$prof phase=spawn warmup=1 seconds=3
				gl "$OUT/gl" $(dims $s) profile=$prof phase=full warmup=3 seconds=5
			done
		done ;;
	compare)   # 40×40: visual normal × sem desenho × marcador × oculto; e fases (lógica parada/andando/alvo/combate)
		for prof in warriors mixed; do
			for v in normal nodraw minimal hidden; do
				hl "$OUT/compare_headless" allies=40 enemies=40 profile=$prof phase=full warmup=3 seconds=8 visual=$v
				gl "$OUT/compare_gl" allies=40 enemies=40 profile=$prof phase=full warmup=3 seconds=5 visual=$v
			done
			for ph in spawn move target; do
				gl "$OUT/compare_gl" allies=40 enemies=40 profile=$prof $(phase_args $ph) visual=normal
				gl "$OUT/compare_gl" allies=40 enemies=40 profile=$prof $(phase_args $ph) visual=hidden
			done
		done ;;
	overhead)   # custo da própria instrumentação (40×40 Guerreiros, headless)
		hl "$OUT/overhead" allies=40 enemies=40 profile=warriors phase=full warmup=3 seconds=8 sim=real probes=0 label=real_noprobes
		hl "$OUT/overhead" allies=40 enemies=40 profile=warriors phase=full warmup=3 seconds=8 sim=bench timing=0 probes=0 label=bench_counters_only
		hl "$OUT/overhead" allies=40 enemies=40 profile=warriors phase=full warmup=3 seconds=8 sim=bench timing=1 probes=0 label=bench_timing
		hl "$OUT/overhead" allies=40 enemies=40 profile=warriors phase=full warmup=3 seconds=8 sim=bench timing=1 probes=1 label=bench_timing_probes ;;
	realtime)   # sem passo fixo: a Battle compensa quadros lentos com até 6 passos
		timeout 1800 "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x896 --disable-vsync \
			-s res://tools/bench/stress_bench.gd -- out="$OUT/realtime" allies=40 enemies=40 profile=warriors phase=full warmup=1 seconds=4 realtime=1 label=gl_realtime_40x40 2>&1 | grep -E "^BENCH|SCRIPT ERROR" | tee -a "$OUT/log.txt"
		timeout 900 "$GODOT" --headless --path . \
			-s res://tools/bench/stress_bench.gd -- out="$OUT/realtime" allies=40 enemies=40 profile=warriors phase=full warmup=1 seconds=8 realtime=1 label=headless_realtime_40x40 2>&1 | grep -E "^BENCH|SCRIPT ERROR" | tee -a "$OUT/log.txt" ;;
	paladins)   # habilidade do Paladino (provocação/escudo) separada
		for s in 40x40 40x2 2x40 20x20; do
			hl "$OUT/paladins" $(dims $s) profile=paladins phase=full warmup=3 seconds=8
			hl "$OUT/paladins" $(dims $s) profile=paladins phase=target warmup=1 seconds=5
		done
		gl "$OUT/paladins" allies=40 enemies=40 profile=paladins phase=full warmup=3 seconds=5 ;;
	timeline)   # uma luta inteira 40×40 (misto), quadro a quadro: custo × unidades vivas
		hl "$OUT/timeline" allies=40 enemies=40 profile=mixed phase=full warmup=0.1 seconds=75 label=timeline_mixed_40x40
		hl "$OUT/timeline" allies=40 enemies=40 profile=warriors phase=full warmup=0.1 seconds=75 label=timeline_warriors_40x40 ;;
	profiler)   # Profiler do Godot (servers + funções de script) via depuração remota, sem editor
		mkdir -p "$OUT/profiler"
		port=6020
		for prof in warriors sentinels mixed paladins; do
			port=$((port + 1))
			python3 tools/bench/godot_profiler.py --port $port --skip 60 --out "$OUT/profiler/profiler_${prof}_40x40_full_headless.json" -- \
				"$GODOT" --headless --path . --fixed-fps 60 --remote-debug tcp://127.0.0.1:$port \
				-s res://tools/bench/stress_bench.gd -- out="$OUT/profiler" allies=40 enemies=40 profile=$prof phase=full warmup=3 seconds=6 \
				| head -12 | tee -a "$OUT/log.txt"
		done
		port=$((port + 1))
		python3 tools/bench/godot_profiler.py --port $port --skip 30 --out "$OUT/profiler/profiler_warriors_40x40_full_gl.json" -- \
			"$GODOT" --path . --rendering-driver opengl3 --resolution 1600x896 --fixed-fps 60 --disable-vsync --remote-debug tcp://127.0.0.1:$port \
			-s res://tools/bench/stress_bench.gd -- out="$OUT/profiler" allies=40 enemies=40 profile=warriors phase=full warmup=3 seconds=3 \
			| head -12 | tee -a "$OUT/log.txt" ;;
	esac
done
echo "fim" | tee -a "$OUT/log.txt"
