# Render das unidades — diagnóstico (simulação parada)

**Pergunta.** Por que 40 unidades ≈ 3.256 draw calls, mas 80 ≈ 10.814? E por que 80 unidades visíveis, com a
simulação **parada**, dão 13 FPS no PC do usuário?

**Resposta curta.** Cada comando de desenho de uma unidade vira **um draw call próprio**. O renderizador
(Compatibility/OpenGL) não junta comandos de peças diferentes, e as linhas suavizadas custam **3** cada. O salto de
40 → 80 não é linear porque as unidades somadas foram **Guerreiros Sombra**, que custam **189** draw calls cada contra
**72** do Guerreiro vivo: a sombra desenha o corpo duas vezes (silhueta roxa + corpo) e adiciona os efeitos.

- 3.256 = 376 (cenário) + 40 × 72 (Guerreiro) + 40 × 1 (barra de HP, em lote)
- 10.814 ≈ 3.256 + 40 × 189 (Guerreiro Sombra)

Nada foi alterado no jogo para medir: gameplay, IA, stats, combate e aparência continuam iguais.

## Os prints do PC do usuário (painel F6, simulação parada)

| cena | draw calls | objetos | nós | FPS | quadro |
|---|---|---|---|---|---|
| 0 aliados + 40 Guerreiros | 3.256 | 9.447 | 416 | 57 | 17,5 ms |
| 2 Guerreiros Sombra + 40 Guerreiros | 3.633 (+377) | 10.126 | 422 | 44 | 22,5 ms (+5,0) |
| 40 Guerreiros Sombra + 40 Guerreiros | 10.814 (+7.558) | 22.576 | 539 | 13 | 79,9 ms (+62,4) |

- Os draw calls deste ambiente são **idênticos** aos do PC do usuário: 3.256, 3.634 e 10.817. Medir aqui vale para
  a contagem; o tempo por draw call é o do PC.
- No PC do usuário, cada draw call a mais custa **≈ 7–13 µs** (+377 → +5 ms; +7.558 → +62 ms, que inclui a CPU do
  `_draw` dos Guerreiros Sombra, abaixo).
- O "Visual (update)" do painel (0,23–0,48 ms) mede só o `_process` dos UnitView. O `_draw` roda depois e não
  entra nesse número.

### Draw calls por unidade e por categoria (medido desligando cada categoria)

| unidade | **total/unid.** | contornos (borda de cada peça) | preenchimento das peças | silhueta roxa (2ª passada da sombra) | VFX da sombra (aura, névoa, fumaça, fissuras, olhos) | desenhos diretos (sombra no chão, viseira, capa, auréola, detalhes) | linhas (costuras, fio da lâmina) | barra de HP |
|---|---|---|---|---|---|---|---|---|
| Guerreiro | **72** | 32 | 30 | 0 | 0 | 3 | 7 | 1 |
| Guerreiro Sombra | **189** | 32 | 30 | 57 | 44 | 19 | 7 | 1 |
| Sentinela | **119** | 36 | 24 | 0 | 0 | 29 | 7 | 1 |
| Sentinela Sombra | **218** | 40 | 24 | 52 | 26 | 41 | 6 | 1 |
| Paladino | **180** | 93 | 31 | 0 | 0 | 45 | 12 | 1 |
| Paladino Sombra | **253** | 34 | 32 | 58 | 50 | 67 | 12 | 1 |

### Draw calls por PARTE do corpo (comandos × custo do comando; top 8)

- **Guerreiro**: leg 16, arm 10, sword 9, head 7, waist 7, pauldron 6, torso 6, cape 5
- **Guerreiro Sombra**: fx crack 24, plume 16, leg 16, leg (silhueta) 14, arm 10, arm (silhueta) 9, sword 9, cape 8
- **Sentinela**: robe 25, capelet 18, hat 18, flaps 10, head 6, arm 5, backcloak 4, boots 4
- **Sentinela Sombra**: robe 25, capelet 22, hat 18, wisps 16, fx crack 12, hat (silhueta) 12, capelet (silhueta) 10, flaps 10
- **Paladino**: leg 38, arm 30, pauldron 22, torso 22, shield 18, sword 17, halo 14, head 10
- **Paladino Sombra**: fx crack 30, leg 26, pauldron 18, leg (silhueta) 14, tabard 11, torso 11, arm 10, halo 9

### Tipo de comando → draw calls (desligando cada função)

| unidade | draw_mesh (DrawCache) | draw_colored_polygon | draw_circle | draw_polyline | draw_arc | draw_line |
|---|---|---|---|---|---|---|
| Guerreiro | 58 cmd → 63 DC | 2 cmd → 2 DC | 1 cmd → 1 DC | 1 cmd → 3 DC | — | 8 cmd → 7 DC |
| Guerreiro Sombra | 112 cmd → 114 DC | 10 cmd → 10 DC | 26 cmd → 26 DC | 11 cmd → 33 DC | — | 8 cmd → 7 DC |
| Sentinela | 36 cmd → 36 DC | 10 cmd → 10 DC | 5 cmd → 5 DC | 11 cmd → 33 DC | 1 cmd → 4 DC | 9 cmd → 7 DC |
| Sentinela Sombra | 63 cmd → 63 DC | 29 cmd → 29 DC | 14 cmd → 14 DC | 24 cmd → 72 DC | 1 cmd → 4 DC | 8 cmd → 6 DC |
| Paladino | 2 cmd → 2 DC | 44 cmd → 44 DC | 28 cmd → 29 DC | 26 cmd → 78 DC | 5 cmd → 15 DC | 15 cmd → 12 DC |
| Paladino Sombra | 117 cmd → 120 DC | 32 cmd → 32 DC | 16 cmd → 16 DC | 18 cmd → 54 DC | 7 cmd → 21 DC | 12 cmd → 12 DC |

Leitura:
- **Contorno + preenchimento de cada peça = 2 draw calls por peça.** O DrawCache (otimização 1) evitou a
  triangulação a cada quadro, mas cada peça continua sendo 2 comandos `draw_mesh`.
- **Sombras.** A silhueta roxa redesenha o corpo inteiro (+52–58). Os VFX (+26–50) somam as fissuras (2 linhas
  suavizadas = 6 draw calls cada), 4 círculos de aura, 2 de névoa, 3 por olho e os fiapos de fumaça.
- **Paladino vivo** (`PaladinLiveVisual`): não usa o DrawCache. Os contornos são `draw_polyline` suavizados
  (3 draw calls cada) = 93 só de contorno.
- **Barra de HP**: 2 retângulos, que o Godot junta num lote (1 draw call). O anel de seleção só existe na tropa
  selecionada, e o debug (F4) só com F4.
- **Nós/CanvasItems**: 3 por unidade (UnitView, Body, Overlay). O número de nós não é o problema, e sim os
  comandos dentro do Body.

## Teste decisivo: as mesmas 80 unidades com outro desenho

Cena do usuário (40 Guerreiros Sombra + 40 Guerreiros), simulação parada, mesmas 80 CombatUnits e UnitViews.
A tecla **F7** no Sandbox troca o modo (`RenderCompare`).

| modo | draw calls | objetos | quadro (este ambiente, sem GPU) | CPU headless |
|---|---|---|---|---|
| normal | 10.817 | 22.159 | 130,7 ms | 19,3 ms |
| congelado (sem redesenho, mesmos draw calls) | 10.817 | 22.159 | 106,2 ms | ≤ 6,9 ms* |
| **quadrados** (1 por unidade) | **377** | 759 | **44,8 ms** (= cenário sozinho: 43,5) | ≤ 6,9 ms* |
| **lote simulado** (1 triangle array/unid., mesmos triângulos) | **456** | 759 | 115,3 ms** | ≤ 6,9 ms* |

\* O headless tem um piso fixo de 6,9 ms por quadro; abaixo disso não mede.
\*\* Aqui o render é por software (llvmpipe): 330 mil triângulos rasterizados em CPU pesam. Numa GPU isso é
trivial, e o que pesa é o número de draw calls.

**Confirmação.** Com quadrados, o custo das 80 unidades desaparece: o quadro fica igual ao do cenário vazio.
O gargalo é o visual procedural, em duas partes:
1. **Draw calls**: 72–253 por unidade. É a parte dominante no PC do usuário (≈ 7–13 µs cada).
2. **CPU do `_draw`** (GDScript montando o desenho a cada quadro), por unidade, neste processador:

| Guerreiro | Guerreiro Sombra | Sentinela | Sentinela Sombra | Paladino | Paladino Sombra |
|---|---|---|---|---|---|
| 0,09 ms | 0,40 ms | 0,19 ms | 0,49 ms | 0,32 ms | 0,41 ms |

(200 unidades headless: (quadro normal − quadro congelado) / 200; inclui o update, que é pequeno.)
40 Guerreiros + 40 Guerreiros Sombra ≈ 20 ms de CPU por quadro neste processador.

## Otimizações estudadas

| ideia | reduz draw calls? | preserva o visual? | avaliação |
|---|---|---|---|
| **Lote por unidade**: o `_draw` junta TODAS as peças (preenchimento, contorno, silhueta, VFX) num único triangle array com cor por vértice e envia **1 comando** | **sim: 72–253 → 1** por unidade (simulado: 10.817 → 456) | **sim**: mesma geometria que o Godot gera hoje (já portada no DrawCache), na mesma ordem, mesma mistura alfa | **maior impacto, risco baixo/médio** |
| Cache de geometria estática / não recriar arrays | não (já feito na otimização 1: DrawCache) | sim | só CPU; o número de draw calls fica |
| Meshes reutilizáveis / materiais compartilhados | não: cada `draw_mesh` continua sendo 1 draw call; não há materiais | sim | sem ganho em draw calls |
| MultiMesh2D | só para formas **idênticas** repetidas | — | não serve: cada unidade tem pose própria a cada quadro |
| Menos CanvasItems / juntar partes estáticas | pouco: são 3 nós por unidade; o custo são os comandos | sim | ganho marginal |
| Atualizar só partes animadas | não (o modo "congelado" mantém os 10.817) | sim | só CPU |
| Pré-renderizar poses em textura / viewport cache | sim | **não exatamente**: reamostragem, poses contínuas viram quadros discretos, memória por pose | risco visual alto; guardar para depois |

## Proposta (maior impacto, menor risco): lote único por unidade

1. **`CodeDrawnUnitVisual` ganha um "lote" do quadro.**
   - Os utilitários (`_fill_poly`, `_outline_closed`, `_fill_circle`, `_circle`, `_line`) e os poucos
     `draw_*` diretos dos visuais e do `ShadowFX` passam a **acrescentar triângulos** a arrays do quadro, em vez de
     emitir um comando.
   - Os triângulos são os mesmos que o Godot gera hoje (DrawCache), já na transformação corrente e com a cor final
     por vértice.
   - No fim do `_draw` sai **um** `canvas_item_add_triangle_array`.
   - A ordem de desenho é a mesma e a mistura alfa é a mesma, então os pixels são os mesmos: validar com as
     ferramentas de comparação de pixels que já existem (`draw_cache_pixels`, `paladin_pixels`).
2. **Ordem de implementação**:
   1. Guerreiro + Guerreiro Sombra (a cena dos prints). Medir no PC com F6/F7.
   2. Sentinela e Sentinela Sombra.
   3. Paladino vivo (`PaladinLiveVisual`, que hoje nem usa o DrawCache) e Paladino Sombra.
3. **Estimativa na cena dos prints**:
   - Draw calls: 10.814 → ~460 (medido na simulação).
   - Quadro no PC do usuário: a parte de draw calls (~55–60 ms) cai para ~3 ms. O que resta é a CPU do
     `_draw` (~10–20 ms), alvo de uma etapa seguinte, se ainda for preciso.
4. **Riscos**:
   - Montar o array em GDScript custa CPU. Para compensar: guardar as malhas do DrawCache já "abertas" em
     triângulos, usar `Transform2D * PackedVector2Array` (nativo) e `append_array`, e medir a cada passo.
   - `draw_set_transform` usado direto nos visuais precisa passar pelo utilitário.
   - Arredondamento de float na transformação feita em CPU: diferença sub-pixel. Medir com os comparadores de pixel.
   - O texto de debug (F4) continua fora do lote.
5. **Fora do escopo**: gameplay, targeting, IA, stats, combate e aparência.

## Como repetir

- Neste ambiente: `tools/bench/render_matrix.sh` e `tools/bench/render_breakdown.gd` (ver `tools/bench/README.md`).
- No PC: Sandbox → monte a cena → **F6** (painel) → **F7** várias vezes (normal → congelado → quadrados → lote
  simulado). Compare FPS, quadro e draw calls de cada modo.
  - **congelado vs normal**: custo da CPU do `_draw`.
  - **lote simulado vs normal**: ganho esperado da proposta.
