# Stress test / profiling do combate

Ferramentas **só de medição**. Não mudam regra de combate, IA, stats, targeting nem visual. O jogo não usa
nada daqui: a única mudança fora desta pasta é o gancho `Battle.sim_script`, que por padrão é `null`
(e aí a `Battle` cria a `CombatSim` de sempre).

| arquivo | o que é |
|---|---|
| `scripts/debug/bench/bench_combat_sim.gd` | `BenchCombatSim extends CombatSim`: mesma lógica com contadores (chamadas de `nearest_foe`, unidades olhadas, distâncias, alvo mantido/trocado, checagens de alcance, ataques, varreduras da provocação, projétil × unidade…) e cronômetros por seção (alvo, movimento, ataque, lâminas, Paladino, projéteis). Modos `FULL`, `TARGET_ONLY` (alvo sem ataque) e `MOVE_ONLY` (anda sem alvo). |
| `tests/bench_parity_test.gd` | garante que `BenchCombatSim` em `FULL` produz **exatamente** a mesma luta da `CombatSim` (12×12, 40×40, 40×3, mistos, 40 s) e que a `Battle` do jogo usa a `CombatSim`. |
| `tools/bench/stress_bench.gd` | roda **um** cenário no jogo real (Main → Sandbox → Arena → Battle → UnitView) e mede cada quadro. |
| `tools/bench/run_matrix.sh` | roda a matriz inteira (cenários × perfis × fases × modos visuais). |
| `tools/bench/godot_profiler.py` | servidor de depuração remota: liga o **Profiler do Godot** (servers + funções de script) sem o editor e grava o tempo por função. |
| `tools/bench/make_report.py` | agrega os resultados em tabelas Markdown. |
| `tools/bench/opt_step.sh` | conjunto fixo 40×40 (headless, com render, tempo real) medido em cada etapa da otimização, a partir de um `git worktree` do commit. |
| `tools/bench/compare_steps.py` | tabelas ANTES/DEPOIS por etapa (ganho % a cada etapa e total). |
| `tools/bench/draw_cache_pixels.gd` | etapa 3: mesmas poses com e sem o DrawCache, render real, comparação pixel a pixel. |
| `tools/bench/corpse_pixels.gd` | etapa 2: o que o cadáver congelado deixa de mostrar (pixels). |
| `tools/bench/paladin_pixels.gd` | etapa 5: roteiro fixo de 24 poses do Paladino para comparar commits. |
| `tests/support/reference_combat_sim.gd` | cópia congelada da CombatSim de antes da otimização (referência de paridade). |
| `tools/bench/render_breakdown.gd` | custo de RENDER das unidades com a simulação PARADA (Sandbox em preparação): draw calls, objetos, primitivas, quadro, nos modos `normal` / `frozen` (sem redesenho) / `squares` (1 quadrado por unidade) / `merged` (simula 1 triangle array por unidade) / `hidden`. |
| `tools/bench/render_probe/` | `make_probe_copy.py` cria uma CÓPIA instrumentada do projeto em que todo `draw_*` dos visuais passa por `draw_probe.gd` (conta por parte/tipo e pode desligar categorias com `skip=`). O projeto real não muda. |
| `tools/bench/render_matrix.sh` | matriz de render: comandos e draw calls por tipo de unidade e por categoria (cópia instrumentada) + tempos no projeto real. Resultado em `RENDER_REPORT.md`. |

## Como repetir

```bash
# display para os testes com render (opcional)
Xvfb :99 -screen 0 1600x896x24 &

# matriz completa (~1 h; execuções sequenciais de propósito)
GODOT=/caminho/do/godot DISPLAY=:99 tools/bench/run_matrix.sh /tmp/bench
# ou só algumas seções: headless gl compare overhead realtime paladins timeline profiler
GODOT=/caminho/do/godot tools/bench/run_matrix.sh /tmp/bench headless compare

python3 tools/bench/make_report.py /tmp/bench        # → /tmp/bench/REPORT_TABLES.md
```

Um cenário só:

```bash
godot --headless --path . --fixed-fps 60 -s res://tools/bench/stress_bench.gd -- \
    allies=40 enemies=40 profile=warriors phase=full visual=normal warmup=3 seconds=8 out=/tmp/bench/um
```

Etapas da otimização (antes/depois):

```bash
GODOT=/caminho/do/godot DISPLAY=:99 tools/bench/opt_step.sh <commit> <rotulo> /tmp/opt   # ~15 min
python3 tools/bench/compare_steps.py /tmp/opt e0_antes e1_mortos e2_cadaveres ...
```

Parâmetros: `allies`, `enemies`, `profile` (`warriors` | `sentinels` | `mixed` | `paladins` | `all`), `phase`
(`spawn` parado | `move` só anda | `target` alvo sem ataque | `full` combate), `visual` (`normal` | `nodraw` anima
sem desenhar o corpo | `minimal` marcador fixo | `hidden` sem visual de unidade), `sim` (`bench` | `real`),
`timing` e `probes` (0/1, para medir o custo da própria instrumentação), `dead_enemies=1` (mata os
inimigos pela simulação antes de começar: N vivos × N cadáveres), `draw_cache` (-1 padrão, 0/1 força), `warmup`, `seconds`, `realtime`
(0 = passo fixo com `--fixed-fps 60`; 1 = relógio real), `label`, `out`.

Profiler do Godot num cenário:

```bash
python3 tools/bench/godot_profiler.py --port 6010 --skip 60 --out perfil.json -- \
    godot --headless --path . --fixed-fps 60 --remote-debug tcp://127.0.0.1:6010 \
    -s res://tools/bench/stress_bench.gd -- allies=40 enemies=40 profile=warriors phase=full
```

Custo de render (simulação parada):

```bash
GODOT=/caminho/do/godot DISPLAY=:99 tools/bench/render_matrix.sh /tmp/render   # ~20 min
godot --path . -s res://tools/bench/render_breakdown.gd -- allies=u_warrior:40 enemies=warrior:40 mode=squares
```

No jogo (no PC de verdade): Sandbox, F6 (painel) e **F7** (normal → congelado → quadrados → lote simulado).

## Como cada número é medido

- **Quadro (ms), FPS**: relógio entre dois `_process` do driver (último nó a processar). Sem limite de FPS e sem
  vsync, então é o custo real do quadro inteiro (scripts + redesenhos + render + motor). Com `--fixed-fps 60`
  cada quadro avança exatamente 1/60 s de jogo (2 passos da simulação): a luta é idêntica em qualquer máquina e
  só o tempo de relógio muda. FPS mínimo = 1000 / pior quadro.
- **sim ms**: `BenchCombatSim.step` cronometrado; subdividido em alvo (`nearest_foe`), movimento/alcance, ataque,
  lâminas da Sentinela, passada do Paladino e projéteis.
- **update visual ms**: o driver faz exatamente o que `UnitView._process` faz (posição + `update_visual` +
  `queue_redraw` do corpo e da barra) — com cronômetro por classe de visual. Os `UnitView` ficam com
  `set_process(false)` durante o benchmark.
- **_draw ms**: cada `CanvasItem` da cena tem o sinal `draw` ligado a uma sonda. O Godot faz, para cada nó a
  redesenhar: limpar os comandos antigos → `NOTIFICATION_DRAW` → sinal `draw` → `_draw()`. O intervalo entre dois
  sinais é atribuído ao primeiro nó: ele contém o `_draw` desse nó **mais a limpeza do próximo**. O total por
  unidade (corpo + anel + barra) é correto; a divisão entre vizinhos não (ex.: com render, a categoria
  "Overlay(HP)" carrega a limpeza dos comandos do corpo seguinte).
- **draw calls / objetos / primitivas / nós**: monitores do Godot (`Performance`). Só existem com render.
- **render ms**: `RenderingServer.viewport_get_measured_render_time_cpu` + preparação do quadro.
- **physics**: monitor do Godot e contagem de `physics_frame` (o projeto não tem `_physics_process` nem corpos).
- `process_max_1s_ms` / `physics_max_1s_ms`: os monitores `TIME_PROCESS`/`TIME_PHYSICS_PROCESS` do Godot são o
  **pico do último segundo**, não o quadro atual — estão no CSV só como referência.
- **Contadores por segundo** são por segundo de JOGO (120 passos da simulação).

## Limitações

- Não há GPU no ambiente em que a medição foi feita: o render usa OpenGL por software (Mesa llvmpipe em Xvfb).
  Draw calls, objetos e primitivas são do renderizador real e valem para qualquer GPU; **os tempos de render
  não** (llvmpipe rasteriza em CPU e é muito mais lento que uma GPU). Os números headless (sem render) medem só a
  CPU dos scripts, e subestimam o `_draw`: no servidor nulo os comandos `draw_*` não viram geometria.
- 4 núcleos compartilhados; as execuções são sequenciais e mesmo assim há ruído de ±1 ms por quadro.
- A instrumentação custa algo (seção 4 do relatório): ~1 ms por quadro em 40×40.
