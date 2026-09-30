# Relatório de profiling e stress test do combate — 2026-09-29

Etapa **só de medição**: nada foi otimizado. Combate, IA, stats, targeting e visual ficaram iguais. Ferramentas
e como repetir: `tools/bench/README.md`. Tabelas completas (144 execuções + seções especiais):
`docs/profiling/TABELAS_2026-09-29.md`. Dados brutos: `docs/profiling/data/`.

Legenda usada em todo o documento:
- **[MEDIDO]** — número saído das execuções;
- **[HIPÓTESE]** — interpretação que os números sugerem mas não provam;
- **[RECOMENDAÇÃO]** — o que fazer depois (nada disso foi implementado).

---

## Resumo em uma página

**Por que 40×40 trava e 40×2 não?** [MEDIDO, headless, Guerreiros, combate]

| | 40×2 | 40×40 | razão |
|---|---|---|---|
| quadro | 6,9 ms (145 FPS) | 16,7 ms (60 FPS; mín. 36) | 2,4× |
| simulação | 1,3 ms | 5,8 ms | 4,4× |
| ↳ busca de alvo (`nearest_foe`) | 1,2 ms | 5,4 ms | 4,6× |
| `_draw` dos visuais | 5,0 ms | 9,7 ms | 1,9× |
| draw calls (com render) | 6.037 | 10.973 | 1,8× |

São duas causas somadas:

1. **Visual procedural, linear no número de unidades, e o maior custo absoluto.** Cada unidade é redesenhada do
   zero a todo quadro: ~25 polígonos com contorno suavizado. Isso dá ~130 draw calls por Guerreiro (~142 no misto,
   ~184 por Paladino). 40×40 tem o dobro de corpos de 40×2, e por isso o dobro de desenho.
2. **Busca de alvo quadrática.** Cada unidade varre a lista inteira de unidades, 120 vezes por segundo. De 40×2
   para 40×40 as unidades dobram (42 → 80), e o trabalho de alvo quadruplica (4,6×).

**Qual parte otimizar primeiro para suportar 40×40?** [RECOMENDAÇÃO] **O desenho procedural das unidades.** Ele
responde por ~60% do quadro sem render (9,7 + 0,5 de 16,7 ms) e por ~11 mil draw calls por quadro com render.
Em seguida vem a busca de alvo (~35% do quadro sem render; é o único custo que cresce com N²).

---

## Cenários, perfis e fases

- Cenários: 10×10, 20×20, 30×30, 40×40, 40×2, 2×40, 40×20, 20×40 e 50×50 (acima do limite).
- Perfis: `warriors` (só Guerreiros), `sentinels` (só Sentinelas), `mixed` (Guerreiro + Sentinela alternados) e
  `paladins` (só Paladinos), este último medido à parte por causa da habilidade.
- Fases:
  - A **parado**: unidades criadas, Sandbox em preparação, sem simulação;
  - B **movimento**: só andam, ida e volta, sem alvo;
  - C **alvo/IA**: aquisição de alvo e aproximação reais, sem ataque, dano nem habilidades;
  - D **combate completo**: descarta os 3 s de aproximação e mede 8 s.
- Tudo no fluxo real do jogo: Main → Sandbox → Arena → Battle → UnitView.
- Passo fixo (`--fixed-fps 60`): cada quadro é 1/60 s de jogo, então a luta é idêntica em qualquer máquina e só
  o tempo de relógio muda.
- Dois ambientes:
  - **headless**: só CPU dos scripts. O servidor de render é nulo, então os comandos `draw_*` não viram geometria;
  - **com render**: OpenGL/Compatibility em Xvfb com Mesa **llvmpipe (GPU por software)**. Draw calls e
    primitivas são reais; os ms de render não representam uma GPU.

---

## 1. Maior gargalo: visual procedural (desenho por código a cada quadro)

**[MEDIDO]**
- **Sem render, 40×40 Guerreiros** (visual `normal` × `nodraw` × `minimal` × `hidden`, mesma simulação):

  | visual | quadro | `_draw` |
  |---|---|---|
  | normal | 15,2 ms | 8,85 ms |
  | anima mas não desenha o corpo | 6,9 ms | 0,4 ms |
  | marcador fixo | 6,5 ms | — |
  | sem visual | 6,2 ms | — |

  Tirar só o desenho dos corpos corta **55%** do quadro. No misto: 20,7 → 8,9 ms (−57%).
- **Com render, 40×40 Guerreiros:** 10.973 draw calls, 206 mil primitivas, `_draw` 63–74 ms e render 98–109 ms,
  total 176–198 ms. Sem os corpos: 580 draw calls, `_draw` 1 ms e render ~44 ms. Esses ~44 ms que sobram são o
  fundo da arena rasterizado pelo llvmpipe.
- **Draw calls por unidade:** ≈ (total − 580 do cenário) ÷ unidades:

  | unidade | draw calls |
  |---|---|
  | Guerreiro | ~130 |
  | misto (Guerreiro + Sentinela) | ~142 |
  | Paladino | ~184 |

  É linear: 3.179 (10×10) → 5.779 (20×20) → 8.380 (30×30) → 10.980 (40×40) → 13.580 (50×50), sempre ~2.600
  a mais por 20 unidades.
- **Profiler do Godot, 40×40 Guerreiros:** a função nº 1 é `CodeDrawnUnitVisual._poly` (polígono +
  contorno com `draw_polyline` suavizado), com **2.000 chamadas por quadro** (25 por Guerreiro).
  - Sem render: 3,6 ms de tempo próprio, 1,8 µs por chamada.
  - Com render: **25,3 ms**, 12,6 µs por chamada.
  - Depois vêm `_circle` (400/quadro; 5,8 ms com render) e `WarriorVisual._draw_shadow` (4,1 ms com render).
- **Os mortos continuam custando visual.** Na linha do tempo da luta mista 40×40, com só 6 vivos o `_draw`
  continua em 10–13 ms, porque os 80 corpos, cadáveres incluídos, são redesenhados a cada quadro.
- **Redesenhos:** 3 `CanvasItem` por unidade (corpo, anel de seleção, barra de HP), todos redesenhados a cada
  quadro: 240 redesenhos por quadro em 40×40. O anel e a barra são baratos (~0,3 e ~0,4 ms sem render), mas
  o anel é um `_draw` vazio chamado 80 vezes por quadro.

**[HIPÓTESE]**
- A diferença entre headless (1,8 µs por `_poly`) e com render (12,6 µs) é o motor transformando cada polígono em
  geometria (triangulação, contorno suavizado virando malha, envio de buffers). Esse custo é de CPU e
  **existe também numa GPU real**.
- No renderer Compatibility, cada `draw_colored_polygon` ou `draw_polyline` vira um comando de polígono que não
  entra no batching, e por isso quase cada chamada é um draw call.
- Numa GPU real o render cai muito, mas 11–12 mil draw calls por quadro continuam caros para o driver (ordem de
  vários ms). Com a CPU dos scripts já em ~16,7 ms sem render, 40×40 não fecha 60 FPS.

## 2. Segundo gargalo: busca de alvo quadrática

**[MEDIDO]**
- `CombatSim.nearest_foe` é chamada **por unidade viva, a cada passo** (120 Hz), e sempre varre a lista
  inteira, **vivos e mortos**. São 80 unidades olhadas por chamada em 40×40 e 42 em 40×2.

  | fase C (alvo sem ataque) | 10×10 | 20×20 | 30×30 | 40×40 | 50×50 |
  |---|---|---|---|---|---|
  | chamadas/s | 2,4k | 4,8k | 7,2k | 9,6k | 12k |
  | distâncias calculadas/s | 24k | 96k | 216k | **384k** | 600k |
  | unidades olhadas/s | 48k | 192k | 432k | **768k** | 1,2M |
  | alvo ms/quadro (Guerreiros) | 0,40 | 1,64 | 3,56 | **6,65** | 9,80 |

  Unidades olhadas por passo ÷ N² fica constante (1,05–1,4 nos Guerreiros): é **O(N²)**. Dobrar os lados
  (20×20 → 40×40) multiplica o custo de alvo por **4,05**; 40×40 → 50×50 por 1,47 (teórico 1,56).
- **Recalcular sem necessidade:** em 98–100% das chamadas o recálculo devolve **o mesmo alvo de antes**. Nos
  Guerreiros 40×40: 9.560 mantidos contra 40 trocas por segundo.
- **Mortos continuam varridos.** Com um lado inteiro morto (40+0), cada sobrevivente ainda varre as 80
  unidades a cada passo para não achar ninguém: **384 mil unidades olhadas por segundo à toa** (linha do tempo,
  40×40 Guerreiros, 15–75 s).
- Cada unidade olhada chama 3 métodos (`is_enemy_of`, `is_valid_target` → `is_alive`). No profiler, só esses
  somam ~1,9 ms de 40×40 Guerreiros (11–17 mil chamadas por quadro).
- **Quanto custa:**
  - 40×40 Guerreiros: **5,4 ms por quadro** no combate e 6,7 ms na fase C, ~41 µs por chamada.
  - Sem visual nenhum (`hidden`), a simulação sozinha limita o jogo a **~160 FPS** (6,2 ms por quadro).
  - Em 50×50, só a simulação passa de **10 ms**.
- **Sentinelas fazem duas buscas por passo:** as lâminas (`SentinelSwords.update`) chamam `nearest_foe` de novo.
  No misto 40×40, as lâminas custam +2,8–3,3 ms por quadro.
- **Projéteis:** cada projétil em voo testa distância contra as unidades até achar alguém: 77–139 mil
  checagens por segundo (Sentinelas/misto 40×40–50×50), ~0,8–0,9 ms por quadro.
- **Provocação (Paladinos 40×40):**
  - `taunt_target` faz `p in units`, uma varredura linear, para cada provocado a cada passo: 59–95 mil por
    segundo;
  - `try_taunt` testa as N unidades para cada Paladino pronto: 38–61 mil por segundo;
  - passada do Paladino: ~1 ms por quadro pelo cronômetro.
  - Além disso, `_tick_paladins` chama `taunt_target` para **todas** as unidades a cada passo, mesmo sem
    nenhum Paladino na luta: 17–25 mil chamadas por segundo, ~0,1 ms.

## 3. Comportamento quadrático?

**Sim, na simulação:** a busca de alvo é O(N²), como mostrado acima, e as checagens projétil × unidade são
O(projéteis × N). **Não no visual:** desenho, draw calls, redesenhos e nós crescem linearmente. Em 40×40 o
visual ainda pesa mais em valor absoluto; o alvo é o que mais cresce: em 50×50 a fase C já passa de 10 ms.

40×40 gera muito mais trabalho que 40×2 **[MEDIDO, Guerreiros, combate]**:

| | 40×2 | 40×40 | razão |
|---|---|---|---|
| unidades olhadas/s | 202k | 632k | 3,1× |
| distâncias calculadas/s | 262 | 246k | ~940× |
| alvo ms | 1,2 | 5,4 | 4,6× |

- A diferença entre "olhadas" e "distâncias" vem dos filtros: em 40×2 quase todas as unidades olhadas são
  aliadas ou mortas.
- Comparando 40×40 com 40×2, as unidades olhadas sobem só 3,1×, mas o tempo de alvo sobe 4,6×. **[HIPÓTESE]**
  A diferença está no custo por unidade olhada, maior quando ela é inimiga viva (distância calculada e
  comparada).

## 4. Quanto custa cada coisa (40×40, combate)

**Sem render** **[MEDIDO]**:

| sistema | Guerreiros | misto |
|---|---|---|
| quadro total | 15,2–16,7 ms | 20,7–21,9 ms |
| `_draw` dos corpos | 8,0 ms (53%) | 10,5 ms (51%) |
| barra de HP + anel | 0,7 ms | 0,9 ms |
| update visual (animação) | 0,4–0,5 ms (3%) | 0,8 ms (4%) |
| busca de alvo | 4,9–5,4 ms (32%) | 3,4 ms (16%) |
| lâminas da Sentinela | — | 2,8 ms (13%) |
| projéteis | — | 0,8 ms |
| movimento + ataque + dano | 0,1 ms | 0,1 ms |
| fundo, UI, motor (resto) | ~0,7 ms | ~1 ms |

- **Animação:** o update dos visuais é barato: ~6 µs por Guerreiro e ~14 µs por Sentinela. **A exceção é o
  Paladino:** ~260 µs por unidade, 21 ms por quadro para 80 Paladinos. No profiler, `PaladinLiveVisual._update`
  soma 22,3 ms (`_build_parts` 6,0; `PaladinAnimator.update` 8,6; `PaladinPoseLibrary.add`/`mix`/`neutral`
  ~5). 40×40 de Paladinos roda a 19 FPS sem render e a 3,2 FPS com render (15.326 draw calls).
- **Physics:** **0,05 ms por quadro.** Nenhum nó usa `_physics_process` e não há corpos físicos; o tick de
  60 Hz roda vazio.
- **UI/debug:** `_draw` da UI é 0,01 ms. O Sandbox atualiza o texto de status a cada quadro (2 `alive_count`);
  fica dentro do resto (< 1 ms). Os desenhos de debug (F4) estavam desligados.
- **Movimento:** só andar custa 0,3–0,4 ms de simulação em 40×40.

## 5. Draw calls são problema?

**Sim.** **[MEDIDO]**
- 10.973 draw calls por quadro em 40×40 Guerreiros, 12.141 no misto, 15.326 com Paladinos e 15.025 em 50×50 misto.
- O resto da cena (fundo + UI) usa ~580.

**[HIPÓTESE]** Mesmo numa GPU real esse volume custa vários ms de CPU no driver por quadro, e o custo de montar
os comandos (medido acima: `_poly` 25 ms com render) acontece de qualquer forma.

## 6. Excesso de nós?

**Não.** **[MEDIDO]**
- 534 nós em 40×40: ~294 da cena, mais 3 por unidade (UnitView, corpo e barra). É linear e pequeno.
- 107 nós com `_process`: 80 UnitView, 26 do fundo (velas, névoa, nuvens, bandeiras, lua, luzes), Battle e
  Sandbox.
- Nenhum nó com `_physics_process`.

O problema não é a quantidade de nós, e sim **o que cada um faz por quadro** (redesenho completo).

## 7. Frequência de atualização

**[MEDIDO]**

| sistema | frequência | por quadro, 40×40 |
|---|---|---|
| `_process` dos UnitView | 60 Hz × N (vivos e mortos) | 80 |
| `_process` do fundo | 60 Hz | 26 nós |
| `Battle._process` | 60 Hz | 1 (+ `is_finished`: 2 varreduras de N) |
| passo da simulação | **120 Hz** (fixo) | 2 |
| busca de alvo | **120 Hz por unidade viva** (+120 Hz nas lâminas de cada Sentinela) | 160–190 chamadas |
| passada do Paladino (`taunt_target` de todos) | 120 Hz × N, mesmo sem Paladino | 160 |
| update de animação | 60 Hz × N (mortos incluídos) | 80 |
| redesenho procedural | 60 Hz × 3 × N (mortos incluídos) | 240 |
| physics | 60 Hz, sem trabalho | — |

- **[MEDIDO]** A busca de alvo a 120 Hz devolve o mesmo alvo em 98–100% das vezes.
- **[MEDIDO]** O redesenho a 60 Hz inclui cadáveres parados.
- **[HIPÓTESE]** São os dois sistemas atualizados com frequência sem necessidade.

**Efeito em cascata no tempo real** **[MEDIDO]**:
- A `Battle` limita o dt a 0,05 s e compensa quadros lentos com mais passos da simulação.
- Com render (llvmpipe), 40×40 roda a ~5 FPS: **6 passos por quadro**, simulação 15 ms por quadro em vez de 6,5 ms.
- O jogo passa a andar a **0,25×** da velocidade real.
- Quanto mais o visual pesa, mais passos a simulação faz por quadro.

## 8. Funções no topo do Profiler do Godot

Coletado com o profiler do próprio Godot, "servers" + funções de script, via `tools/bench/godot_profiler.py`.
Com o profiler ligado o quadro fica mais lento (24 ms contra 16,7 ms); vale para comparar funções entre si.
Tempo próprio (self) em ms por quadro, 40×40, combate.

**Guerreiros, com render** (quadro 194 ms, script 49,6 ms, physics 0,07 ms):

| # | função | self | total | chamadas/quadro |
|---|---|---|---|---|
| 1 | `CodeDrawnUnitVisual._poly` | 25,31 | 26,32 | 2.000 |
| 2 | `CodeDrawnUnitVisual._circle` | 5,80 | 6,01 | 400 |
| 3 | `WarriorVisual._draw_shadow` | 4,10 | 4,10 | 80 |
| 4 | `CombatSim.nearest_foe` | 3,21 | 11,04 | 157 |
| 5 | `CodeDrawnUnitVisual._c` (cor) | 1,26 | 1,26 | 5.520 |
| 6 | `CombatUnit.is_enemy_of` | 1,16 | 1,16 | 12.389 |
| 7 | `WarriorVisual._draw_pauldron` | 0,76 | 3,72 | 160 |
| 8 | `CombatUnit.is_valid_target` | 0,60 | 2,11 | 6.273 |

**Guerreiros, sem render** (quadro 24,3 ms com profiler, script 14,8 ms):

| # | função | self | total | chamadas/quadro |
|---|---|---|---|---|
| 1 | `CodeDrawnUnitVisual._poly` | 3,56 | 4,26 | 2.000 |
| 2 | `CombatSim.nearest_foe` | 2,82 | 9,71 | 146 |
| 3 | `CodeDrawnUnitVisual._circle` | 1,38 | 1,51 | 400 |
| 4 | `CombatUnit.is_enemy_of` | 0,97 | 0,97 | 11.504 |
| 5 | `CodeDrawnUnitVisual._c` | 0,88 | 0,88 | 5.520 |
| 6 | `CombatUnit.is_valid_target` | 0,52 | 1,86 | 5.825 |

**Misto, sem render:**
1. `_poly` 3,99;
2. `nearest_foe` 3,84 (total 13,5 com os métodos auxiliares);
3. `is_enemy_of` 1,40 (15.210 chamadas);
4. `SentinelVisual._c` 0,94;
5. `ArcaneBlade.draw` 0,83;
6. `is_valid_target` 0,81.

**Paladinos, sem render:**
1. `_poly` 4,63;
2. `_tick_paladins` 3,75 (no profiler inclui o laço de contagem do benchmark; o cronômetro dá ~1 ms);
3. `PaladinLiveVisual._build_parts` 3,44;
4. `nearest_foe` 2,81;
5. `PaladinLiveVisual._update` 2,22 (total 22,3);
6. `_draw_pauldron` 1,87;
7. `PaladinLiveVisual._draw` 1,76 (total 25,3);
8. `PaladinAnimator.update` 1,40 (total 8,6).

Nos "servers" do motor (física, áudio) nada passa de 0,02 ms por quadro.

---

## Recomendações futuras (NÃO implementadas)

Em ordem de retorno esperado, pelos números acima.

1. **Visual procedural** (maior gargalo):
   - não redesenhar o que não mudou: cadáveres parados, barra de HP só quando o HP muda, anel só quando a
     seleção muda;
   - reduzir comandos por unidade: contorno sem `draw_polyline` suavizado, por exemplo um polígono maior atrás;
     juntar partes;
   - "assar" o visual procedural em texturas ou sprites por pose ou quadro (o código continua sendo a fonte, mas
     o jogo desenha 1 sprite por unidade);
   - partes como nós persistentes (`Polygon2D`/`MeshInstance2D`) movidos por transformação em vez de
     redesenhados;
   - LOD (menos detalhe com muitas unidades) e batching;
   - Paladino: guardar a geometria entre quadros (`_build_parts` e animador custam ~260 µs por unidade).
2. **Busca de alvo** (segundo gargalo, único quadrático):
   - listas de vivos por time, para não varrer mortos nem aliados;
   - manter o alvo até ele morrer, sair do alcance ou haver provocação, e reavaliar com menos frequência
     (98–100% das reavaliações hoje dão o mesmo resultado);
   - spatial hash ou grade de proximidade (ou quadtree) quando N crescer;
   - reaproveitar no mesmo passo o `nearest_foe` das lâminas da Sentinela;
   - trocar `p in units` da provocação por uma checagem O(1);
   - não chamar `taunt_target` para todas as unidades quando não há Paladino.
3. **Cascata do tempo real:** rever o limite de passos por quadro / dt máximo quando o quadro fica lento.
4. **Pooling:** não apareceu como problema. Nós e objetos são estáveis, e projéteis são poucos (< 25 em voo).
5. **Physics tick:** nada a fazer. O custo medido é ~0.

## Limitações dos testes

- **Sem GPU:** o render é Mesa llvmpipe (software) em Xvfb. Draw calls, primitivas e objetos são do renderer
  real; **os tempos de render e o FPS "com render" não representam uma máquina com GPU**.
- **Headless subestima o `_draw`:** o servidor de render nulo não monta geometria (1,8 contra 12,6 µs por `_poly`).
  O custo real numa máquina com GPU fica entre os dois ambientes.
- **Máquina:** 4 núcleos compartilhados, execuções sequenciais. Há ruído de ±1–2 ms nos quadros; picos isolados
  (FPS mín.) podem ser do ambiente. Repetições do mesmo cenário deram 176,2 e 177,9 ms (com render) e 15,2–16,7 ms
  (headless).
- **Custo da instrumentação:** em 40×40 Guerreiros headless, o jogo sem nenhuma instrumentação fez 13,8 ms por
  quadro contra 15,3 ms com tudo ligado (contadores + cronômetros + sondas), ~10%. O profiler do Godot pesa mais
  (24 ms).
- **Atribuição do `_draw`:** o Godot limpa os comandos antigos de um nó antes de emitir o sinal `draw` dele, então
  o intervalo medido de cada nó inclui a limpeza do próximo. O total por unidade é correto; a divisão entre
  vizinhos não. Com render, "Overlay(HP)" carrega a limpeza do corpo seguinte.
- **Update visual:** durante o benchmark os `UnitView` têm o `_process` desligado e um driver faz exatamente o
  mesmo trabalho, com cronômetro. A ordem entre simulação e visual no quadro muda (1 quadro de defasagem), o custo
  não.
- **Combate (fase D):** a janela medida (3–11 s de jogo) pega a luta em andamento, com mortes; as médias de "vivos"
  estão nas tabelas. A linha do tempo cobre a luta inteira (75 s).
- **50×50:** o Sandbox limita 40 por lado; as unidades extras usam a mesma grade (colunas 9 e 10) e ficam presas
  à borda do campo.
- **Paridade garantida:** `tests/bench_parity_test.gd` confirma que a simulação instrumentada reproduz a
  `CombatSim` do jogo exatamente, em lutas mistas com habilidades e projéteis.
