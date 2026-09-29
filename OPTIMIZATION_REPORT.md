# Otimização 1 — relatório antes/depois (40 aliados × 40 inimigos)

Primeira rodada de otimização, feita em cima do `PROFILING_REPORT.md`. As mudanças foram incrementais, uma por
commit, e cada etapa foi medida com o mesmo conjunto de benchmarks (`tools/bench/opt_step.sh`, a partir de um
`git worktree` do commit da etapa). Tabelas completas: `docs/profiling/otimizacao_1/TABELAS.md`; dados brutos:
`docs/profiling/otimizacao_1/data/`.

**Comportamento preservado.**
- Combate, stats, habilidades, lógica de morte e resultado da batalha não mudaram.
- `tests/bench_parity_test.gd` compara a CombatSim otimizada com uma cópia CONGELADA da CombatSim de antes
  (`tests/support/reference_combat_sim.gd`). São 40 lutas: Guerreiros, Sentinelas, Paladinos, sombras e
  mistas, de 1×1 a 50×50, 40×2 e 2×40. O teste exige idênticos o estado de toda unidade a cada 0,25 s, a
  sequência inteira de eventos (ataques, dano, mortes, provocações, escudo, projéteis), o vencedor e o
  instante do fim. Resultado: idêntico em todas, depois de cada etapa.
- Aparência:
  - comparação pixel a pixel com render real, 0 pixel diferente nas etapas 3 e 5 (exceto 1 pixel com 1/255
    no Paladino, arredondamento do arco da auréola);
  - a etapa 2 congela o cadáver, e as micro-animações que existiam no cadáver param (lista abaixo).

**Como ler os números.**
- `H_` = headless: só a CPU dos scripts. O servidor de render é nulo, então desenhar custa quase nada ali.
- `G_` = render real OpenGL/Compatibility em Xvfb com **GPU por software (llvmpipe)**:
  - draw calls são reais;
  - o "render ms" é rasterização em CPU, muito mais lenta que uma GPU de verdade.
- "quadro − render" aproxima o custo de CPU do jogo numa máquina com GPU.
- Passo fixo (`--fixed-fps 60`): cada quadro = 1/60 s de jogo, então a luta medida é a mesma em todas as etapas.

---

## Resultado por etapa

### ETAPA 1 — Mortos fora do targeting (commit `7189cdb`)

**O que mudou.**
- `CombatSim` mantém listas de unidades ATIVAS por time, na ordem de criação.
- Quem morre sai na hora, em `_apply_damage`.
- Busca de alvo, provocação, projéteis e fim de luta só percorrem inimigos vivos.
- `p in units` da provocação virou consulta O(1).
- Mortes feitas por fora (testes) são detectadas e as listas, refeitas.

| métrica (headless) | ANTES | DEPOIS | GANHO |
|---|---|---|---|
| **40 vivos × 40 cadáveres** — candidatos examinados/s | 384.000 | **0** | −100% |
| 40 vivos × 40 cadáveres — busca de alvo ms/quadro | 2,66 | 0,07 | −97% |
| 40 vivos × 40 cadáveres — sim ms/quadro | 2,97 | 0,37 | −88% |
| 40×40 Guerreiros — sim ms | 5,40 | 2,39 | −56% |
| 40×40 Guerreiros — candidatos/s | 630.000 | 246.088 | −61% |
| 40×40 Guerreiros — FPS | 62,1 | 81,0 | +30% |
| 40×40 misto — FPS | 49,4 | 66,2 | +34% |

Buscas de alvo por segundo não mudam nesta etapa (ainda 1 por unidade viva por passo). Cada busca, porém,
examina só inimigos vivos. Teste novo: 40 vivos × 40 cadáveres ⇒ 0 varreduras em 2 s.

### ETAPA 2 — Cadáveres estáticos (commit `f08944e`)

**O que mudou.**
- Cada visual informa quando o cadáver assentou (`corpse_settle_time`): queda, quique amortecido,
  escurecimento, armas no chão, efeitos.
- O `UnitView` congela o cadáver: nada de `update_visual` nem `queue_redraw` (corpo, anel, barra).
- Mover o cadáver só muda a posição do nó.
- Reviver (Necromancia) ou ligar o debug volta a animar.

| métrica | ANTES | DEPOIS | GANHO |
|---|---|---|---|
| 40 vivos × 40 cadáveres (headless) — redraws/quadro | 254 | 134 | −47% |
| 40 vivos × 40 cadáveres (headless) — `_draw` ms | 9,97 | 4,92 | −51% |
| 40 vivos × 40 cadáveres (headless) — quadro ms | 11,17 | 5,94 | −47% (FPS 89 → 168) |
| 40 vivos × 40 cadáveres (render) — `_draw` ms | 63,7 | 29,9 | −53% |
| 40×40 misto (headless) — FPS | 66,2 | 80,0 | +21% |

**Draw calls iguais.** Os comandos do cadáver ficam guardados no RenderingServer e continuam sendo desenhados
todo quadro. O que some é reconstruí-los.

**O que deixa de se mover no cadáver.** Comparação de pixels com render real, `tools/bench/corpse_pixels.gd`,
cadáver congelado contra o comportamento antigo 3 s depois:

| unidade | pixels diferentes | o que parou |
|---|---|---|
| Guerreiro | 55 (máx. 1/255) | resto do quique amortecido (imperceptível) |
| Paladino Vivo | 0 | nada |
| Sentinela | 340 | a ponta do chapéu caído continuava balançando |
| sombras (Guerreiro, Sentinela, Paladino) | 694–1.979 | névoa roxa "respirando", fiapos de fumaça e ponta da capa |

### ETAPA 3 — Reduzir redraw dos vivos (commit `572ae4d`)

**Auditoria do `queue_redraw` por quadro.** Antes, por unidade e por quadro:
- corpo (animado): necessário;
- anel de seleção (`UnitView._draw`): quase sempre vazio;
- barra de HP: só muda quando o HP muda.

**O que mudou.**
- Anel e barra só são redesenhados quando o que mostram muda (ou com o debug ligado).
- Corpo: as partes estáticas agora são **geometria cacheada**:
  - `DrawCache` porta EXATAMENTE a geometria que o Godot 4.7 gera para polígono, contorno suavizado,
    círculo e arco (`renderer_canvas_cull.cpp`/`canvas_item.cpp`, aritmética em float32);
  - cada forma repetida vira uma malha branca construída uma vez e desenhada com `draw_mesh` + cor via
    `modulate`;
  - as 3 faixas do contorno suavizado (que eram 3 draw calls) viram 1 malha;
  - formas que mudam todo quadro (capa balançando, polígonos projetados do Paladino) seguem o caminho direto.

**Validação.** `tools/bench/draw_cache_pixels.gd`, 6 tipos × 5 poses (parado, andando, golpe, dano com
clarão, morte), render real: **0 pixel diferente**.

| métrica (render real) | ANTES | DEPOIS | GANHO |
|---|---|---|---|
| 40×40 Guerreiros — draw calls | 10.977 | 6.327 | −42% |
| 40×40 Guerreiros — `_draw` ms | 63,8 | 14,6 | −77% |
| 40×40 Guerreiros — quadro ms | 176,3 | 108,5 | −38% (FPS 5,7 → 9,2) |
| 40×40 misto — draw calls | 12.155 | 8.402 | −31% |
| 40×40 misto — `_draw` ms | 64,2 | 36,7 | −43% |
| 40 vivos × 40 cadáveres — draw calls | 10.943 | 6.223 | −43% |
| redraws/quadro (40×40) | 254 | 86–94 | −63% |

No **headless** esta etapa fica ligeiramente pior: Guerreiros de 11,3 → 13,0 ms por quadro. Sem render, os
`draw_*` são quase de graça e o cache acrescenta consultas em GDScript. Com render real o ganho é grande
(acima).

### ETAPA 4 — Targeting menos frequente (commit `459d712`)

**O que mudou.**
- `nearest_foe` mantém o alvo enquanto há **garantia matemática** de que ele continua sendo estritamente o
  inimigo vivo mais próximo; sem garantia, varre.
- Na varredura guarda o alvo, os 3 inimigos seguintes (distância e odômetro de cada um) e a distância do
  mais próximo entre os demais.
- Limites usados:
  - vizinho i: ≥ dᵢ − a − bᵢ (a = quanto esta unidade andou; bᵢ = quanto o vizinho andou);
  - resto: ≥ D_resto − a − b, com b = soma, por passo, do maior deslocamento do time inimigo.
- No corpo a corpo, quem ataca fica parado e o alvo se mantém até morrer.
- Resultado **idêntico** ao da varredura completa: paridade exata nas 40 lutas.

| métrica (headless) | ANTES (e3) | DEPOIS | GANHO |
|---|---|---|---|
| 40×40 misto — varreduras/s | 9.300 (1 por consulta) | 193 | −98% |
| 40×40 Guerreiros — varreduras/s | 7.875 | 1.532 | −81% |
| 40×40 misto — candidatos/s | 227.440 | 4.773 | −98% |
| 40×40 misto — busca de alvo ms | 1,81 | 0,79 | −56% |
| 40×40 Guerreiros — candidatos/s | 246.088 | 57.957 | −76% |
| 40×40 (fase só alvo) — sim ms | 3,54 | 1,75 | −51% |
| 40×40 Paladinos — candidatos/s | 294.839 | 38.011 | −87% |

**Frequência efetiva de varredura:** no misto ~2% das consultas varrem; nos Guerreiros ~19% (≈23 por
segundo por unidade viva, contra 120 antes); nos Paladinos ~9%.

**Por que não o refresh fixo de 0,1 s.** Ele muda o instante em que a unidade troca de alvo. Isso altera
posições e o resultado determinístico, que você pediu para manter. A versão com garantia chega à mesma
ordem de frequência sem mudar nenhuma decisão.

### ETAPA 5 — Paladino (commit `c50ac79`)

**O que mudou.**
- O `PaladinLiveVisual` chamava `PaladinAnimator.update()`, que montava a **pose 3D completa** (dicionários,
  molas, `base_for`) e ela era descartada: o visual só lê o estado.
  - Agora `compose_pose = false` nele.
  - O rig 2.5D alternativo continua compondo.
- Pose neutra e trilhas de golpe, provocação, guarda e morte são montadas uma vez (antes, várias vezes por
  quadro).
- Senos e cossenos do elmo e da ombreira ficaram em tabela.
- O anel da auréola usa a malha cacheada.
- O DrawCache ficou desligado no resto do Paladino. No A/B com render ele piora: 288 → 316 ms, porque os
  polígonos projetados quase não se repetem.

**Validação.** `tools/bench/paladin_pixels.gd`, 24 poses do Vivo e do Sombra, antes × depois: 1 pixel com
diferença de 1/255.

| métrica | ANTES (e4) | DEPOIS | GANHO |
|---|---|---|---|
| 40×40 Paladinos (headless) — update visual ms | 18,15 | 9,51 | −48% |
| 40×40 Paladinos (headless) — FPS | 23,3 | 29,6 | +27% |
| 40×40 Paladinos (render) — update visual ms | 22,5 | 12,7 | −44% |
| `paladin_live_test` — custo por Paladino | ~0,21 ms | 0,13 ms | −38% |

Guerreiro × Paladino por unidade, 40×40 com render, depois:

| | Guerreiro | Paladino |
|---|---|---|
| update visual | ~8 µs | ~160 µs |
| `_draw` | ~0,18 ms | ~1,4 ms |
| draw calls | ~72 | ~181 |

### ETAPA 6 — Proteção contra o efeito cascata (commit `2561023`)

**Como foi implementado** (`Battle._process`):
- A `CombatSim` continua em passo FIXO de 1/120 s. O dt do quadro continua limitado a 0,05 s (como no HTML).
- **No máximo `MAX_SIM_STEPS_PER_FRAME = 4` passos por quadro.** Quatro passos = 33 ms, então até 30 FPS
  o tempo de jogo acompanha o relógio.
- Se o quadro precisou de mais:
  - a sobra fica guardada, até 4 passos, e é recuperada nos quadros seguintes (um soluço isolado não perde
    tempo);
  - o que passar disso é descartado (`dropped_time`): o jogo fica em câmera lenta enquanto a máquina não dá
    conta, em vez de fazer 6 passos e deixar o próximo quadro ainda mais lento.
- **Nunca acelera:** no máximo 4 passos por quadro.
- **O resultado da luta não muda:** a sequência de passos é a mesma. `tests/sim_pacing_test.gd` roda a mesma
  luta a 60, 30 e 5 FPS e com soluços, e dá o mesmo vencedor, sobreviventes, HP e posições.

| métrica (relógio real, render por software) | ANTES (e5) | DEPOIS | GANHO |
|---|---|---|---|
| passos da simulação por quadro | 6,00 | 4,00 | −33% |
| sim ms por quadro | 4,24 | 4,62 | (custo por passo igual; varia com a fase da luta) |
| velocidade do jogo | 0,40× | 0,24× | mais lento abaixo de 30 FPS |

**Ressalva honesta.**
- Neste ambiente o jogo roda a ~7 FPS, porque o render por software domina. A proteção limita o custo da
  simulação por quadro, mas não melhora o FPS aqui.
- Abaixo de 30 FPS o jogo passa a andar mais devagar que antes (0,24× contra 0,40×). É o custo de não deixar
  a simulação crescer junto com a lentidão.
- O limite é uma constante: com 6 volta ao comportamento anterior (sem proteção).
- Os runs em tempo real de etapas diferentes medem momentos diferentes da luta (com menos passos, há mais
  unidades vivas na janela medida). Use-os para ver passos por quadro, não para comparar FPS entre etapas.

---

## Resumo final — 40 × 40

| cenário | ANTES | DEPOIS | GANHO |
|---|---|---|---|
| Guerreiros, headless — FPS | 62,1 | 83,1 | +34% |
| misto, headless — FPS | 49,4 | 74,4 | +51% |
| Paladinos, headless — FPS | 19,2 | 31,6 | +65% |
| 40 vivos × 40 cadáveres, headless — FPS | 78,6 | 158,6 | +102% |
| Guerreiros, render (software) — FPS | 5,7 | 9,3 | +62% |
| misto, render (software) — FPS | 4,8 | 7,0 | +46% |
| Guerreiros, render — quadro **menos render** (CPU do jogo) | 77,8 ms | **26,1 ms** | −66% (~13 → ~38 FPS) |
| misto, render — quadro menos render | 95,0 ms | **47,0 ms** | −51% (~11 → ~21 FPS) |
| Paladinos, render — quadro menos render | 157,4 ms | 134,9 ms | −14% |
| 40 vivos × 40 cadáveres, render — quadro menos render | 81,6 ms | 15,0 ms | −82% |
| draw calls 40×40 Guerreiros | 10.977 | 6.327 | −42% |
| candidatos examinados/s 40×40 misto | 744.020 | 4.773 | −99% |
| simulação 40×40 misto (headless) | 7,20 ms | 1,82 ms | −75% |

**Maior ganho.**
- **Etapa 3 (geometria cacheada) com render real:** −77% no `_draw` e −42% nas draw calls dos Guerreiros.
  Foi a maior redução de quadro (176 → 108 ms com render).
- **Etapa 1** vem em seguida: a simulação caiu pela metade, e no cenário 40 vivos × 40 cadáveres a busca de
  alvo foi a ~0.

**FPS final no 40×40.**
- Sem render: Guerreiros **83**, misto **74**, Paladinos **32**.
- Com render por software (sem GPU): Guerreiros 9,3, misto 7,0, Paladinos 3,6. Não representa uma máquina
  com GPU.
- Custo de CPU do jogo excluindo a rasterização:
  - Guerreiros ~26 ms (~38 FPS);
  - misto ~47 ms (~21 FPS);
  - Paladinos ~135 ms (~7 FPS).
- **Meta "jogável e estável":**
  - atingida nos cenários sem Paladino no custo de CPU dos scripts;
  - com render real ainda depende da GPU (não medida aqui);
  - **não** atingida com muitos Paladinos.

## Gargalos restantes

1. **Paladino (desenho).** ~1,4 ms e ~181 draw calls por Paladino com render. Os polígonos são projetados a
   cada quadro, com pontos já transformados, e o cache não se aplica. Próximo passo: desenhar as peças
   rígidas (escudo, espada, elmo, ombreiras, estrelas) no espaço local de cada uma, com a transformação
   aplicada pelo `draw_set_transform`. Assim elas viram formas constantes cacheáveis, sem mudar a aparência.
2. **Draw calls ainda altos:** 6,3k (Guerreiros) a 15k (Paladinos). Cada peça cacheada ainda custa 2 draw
   calls (preenchimento + contorno). Juntar mais exige mudar a técnica de render (malha única por unidade
   com cores por vértice, ou visual "assado" em textura), já na fronteira de "não mudar o visual".
3. **Sentinela.** Manto, chapéu e lâminas mudam todo quadro (poucas formas repetidas); `ArcaneBlade.draw` e
   projéteis desenhados por código.
4. **Headless:** o DrawCache acrescenta ~1 ms de GDScript em 40×40 quando não há render. Irrelevante no jogo
   real, mas aparece nos testes sem render.
5. **Render da cena de fundo** (~580 draw calls e ~44 ms no llvmpipe) não foi tocado.

## Arquivos alterados

**Jogo:**
- `scripts/combat/combat_sim.gd`: listas de ativos, cache de alvo com garantia, `_move_unit`, contadores;
- `scripts/combat/abilities/paladin_taunt.gd`: `foes_alive()`;
- `scripts/combat/battle.gd`: `sim_script` (bench), `MAX_SIM_STEPS_PER_FRAME`, diagnóstico;
- `scripts/combat/unit_view.gd`: cadáver congelado, anel/barra por mudança;
- `scripts/visuals/units/unit_visual.gd`: contrato do cadáver;
- `scripts/visuals/units/code_drawn_unit_visual.gd`: `_poly`/`_circle`/`_rim_poly` pelo DrawCache;
- `scripts/visuals/units/draw_cache.gd` (novo);
- visuais com assentamento do cadáver: `warrior_visual.gd`, `shadow_warrior_visual.gd`,
  `sentinel_visual.gd`, `paladin_visual.gd`, `paladin_live_visual.gd` (também a etapa 5),
  `circle_unit_visual.gd`;
- `scripts/visuals/units/paladin/paladin_animator.gd`: `compose_pose`.

**Testes:**
- `tests/bench_parity_test.gd` (reescrito: 40 lutas contra a referência);
- `tests/support/reference_combat_sim.gd` (novo);
- `tests/corpse_freeze_test.gd`, `tests/redraw_test.gd`, `tests/sim_pacing_test.gd` (novos).

**Ferramentas:**
- `scripts/debug/bench/bench_combat_sim.gd` (envolve a CombatSim em vez de copiar);
- `tools/bench/stress_bench.gd` (chama o `UnitView._process` real, `dead_enemies`, `draw_cache`);
- `tools/bench/opt_step.sh`, `compare_steps.py`, `draw_cache_pixels.gd`, `corpse_pixels.gd`,
  `paladin_pixels.gd` (novos);
- `tools/bench/README.md`.

**Documentação:** este arquivo, `docs/profiling/otimizacao_1/`, `ARCHITECTURE.md`, `MIGRATION_NOTES.md`,
`docs/.gdignore`.

## Limitações

- Sem GPU no ambiente: com render, os tempos são de rasterização por software. Draw calls, redraws e o custo
  de CPU dos scripts são confiáveis; o FPS numa máquina real precisa ser medido lá.
- Ruído de ±1–2 ms entre execuções (4 núcleos compartilhados). O primeiro run headless da etapa 3 foi refeito
  porque rodou junto com outras tarefas.
- A etapa 2 muda o cadáver: micro-animações paradas (tabela da etapa 2).
- A etapa 6 deixa o jogo mais lento que antes abaixo de 30 FPS (por projeto).
