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

## Resultado no PC do usuário (F7, mesma cena: 40 Guerreiros Sombra + 40 Guerreiros, simulação parada)

| modo | draw calls | quadro | FPS |
|---|---|---|---|
| normal | 10.825 | 78,7 ms | 13 |
| congelado (mesmos draw calls, sem `_draw`) | 10.836 | 28,7 ms | 35 |
| quadrados | 398 | 16,7 ms | 60 (teto do vsync) |
| lote simulado | 456 | 16,7 ms | 60 (teto do vsync) |

**Correção da leitura anterior.** No PC do usuário, a maior parte do custo é a **CPU do `_draw`**: normal −
congelado = **~50 ms**. Os 10.800 draw calls custam **no máximo ~12 ms** (congelado 28,7 ms vs ≤ 16,7 ms). O lote
simulado bate 60 FPS também porque não roda o `_draw` real. Por isso a solução precisa cortar primeiro a CPU do
`_draw`, e só depois os draw calls.

O `_draw` pesa mais lá (~50 ms) que aqui (~12–18 ms). Uma causa provável: rodar pelo editor (build de debug com o
depurador ligado). Vale medir uma vez com o jogo exportado.

### Para onde vai a CPU do `_draw` (Profiler do Godot, 80 unidades, este ambiente)

`tools/bench/godot_profiler.py` + `render_breakdown.gd`: 17,9 ms de script por quadro (com o custo do próprio
profiler).

| onde | ms/quadro (self) | observação |
|---|---|---|
| caminho genérico por peça: `_poly` → `_fill_poly` + `_outline_closed` (+ `draw_mesh`) | ~13 (total) | 3.000 peças/quadro, 2 comandos cada |
| └ `DrawCache.fill_mesh` + `outline_mesh` | 5,5 (total) | a CHAVE da busca é o array de pontos inteiro, com hash a cada chamada; o contorno ainda duplica o array para fechar |
| └ `_c()` (cor com clarão/escurecimento) | 1,3 | 8.240 chamadas; quase sempre sem clarão nem escurecimento |
| capa do Guerreiro Sombra (`_draw_cape`) | 2,1 | forma muda todo quadro: triangulação + contorno suavizado no motor |
| efeitos da sombra (`ShadowFX`) | 1,7 | fumaça, fissuras, olhos, aura |
| silhueta roxa (`_rim_poly`) | 4,7 (total) | redesenha o corpo inteiro |

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

## Proposta revista (depois dos números do PC): lote por unidade com geometria pré-montada

O mesmo refactor resolve as duas partes, **se** montar o lote for mais barato que o caminho atual por peça:

1. **Geometria pronta por peça, sem busca por hash.**
   - Cada forma fixa (em espaço local) vira triângulos prontos, guardados uma vez por tipo de unidade.
   - A cada quadro só se aplica a transformação (`Transform2D * PackedVector2Array`, nativo), a cor e o
     `append_array` no lote da unidade.
   - Isso elimina o hash do array de pontos, a duplicação do contorno e os ~140 `draw_mesh` por unidade.
   - `_c()` ganha um caminho direto quando não há clarão nem escurecimento.
2. **Um comando por unidade** (`canvas_item_add_triangle_array`) no fim do `_draw`: 10.800 → ~460 draw calls.
3. **Mesmos pixels**:
   - mesma geometria que o Godot gera hoje (DrawCache), mesma ordem, mesma mistura alfa;
   - validar com os comparadores de pixel existentes;
   - formas que mudam todo quadro (capa, fumaça) seguem com triangulação por quadro, só que dentro do lote.
4. **Por etapas, medindo cada uma no PC** (F6/F7, com meta de 80 unidades paradas ≤ 16,7 ms):
   1. Guerreiro + Guerreiro Sombra.
   2. Sentinela.
   3. Paladino.
5. **Risco**:
   - Se a CPU de montar o lote não cair o suficiente, o próximo passo é reaproveitar o lote entre quadros quando a
     pose não muda (ex.: unidades paradas). Isso não mexe no visual.
   - O que mexeria no visual (pré-render em textura, animar a menos quadros por segundo) fica de fora.
6. **Fora do escopo**: gameplay, targeting, IA, stats, combate e aparência.

## Reformulação leve (implementada): malha estática com ossos

Em vez do lote por unidade refeito a cada quadro (que cortava os draw calls mas não a CPU), cada tropa virou uma
**malha estática por tipo com ossos** (skinning 2D na GPU):
- as peças (mesmas formas de antes) são montadas uma vez;
- cada unidade tem só um esqueleto;
- a pose do quadro só move os ossos (detalhes em `ARCHITECTURE.md`, "Desenho leve").

| tropa | draw calls/unid. (antes → agora) | CPU/unid. (antes → agora) | vértices da malha (compartilhada) | ossos |
|---|---|---|---|---|
| Guerreiro | 72 → **1** | 0,09 → **0,011 ms** | 4.218 | 13 |
| Guerreiro Sombra | 189 → **1** | 0,40 → **0,040 ms** | 8.754 | 42 |
| Sentinela | 119 → **1** | 0,19 → **0,032 ms** | 9.096 | 67 |
| Sentinela Sombra | 218 → **1** | 0,49 → **0,058 ms** | 13.260 | 67 |
| Paladino | 180 → **1** | 0,32 → **0,115 ms** | 10.494 | 45 |
| Paladino Sombra | 253 → **1** | 0,41 → **0,043 ms** | 16.500 | 55 |

Notas:
- Os draw calls são medidos com render (40 unidades paradas; mais a barra de HP, 1 por unidade).
- A CPU é medida headless com 1.000 unidades: (quadro normal − quadro congelado) / 1.000.
- Cena dos prints (40 Guerreiros Sombra + 40 Guerreiros): **10.817 → 536 draw calls**. A CPU dessas 80 unidades
  cai de ~20 ms para ~2 ms neste processador. No PC do usuário (onde eram ~50 ms de `_draw` + ~12 ms de draw
  calls), o esperado é o custo das tropas quase sumir; confirmar com F6/F7.

O que mudou no visual (o resto é a mesma geometria):
- Formas que mudavam a cada quadro viraram transformações: capa e barra do manto por cisalhamento, abas do manto
  girando, botas deslizando, joelho dobrando.
- Fumaça, brasas, lâminas voltando, anéis e brilhos crescem/encolhem em vez de esmaecer.
- As pontas da capa da Sombra não tremulam mais, e a pulsação das fissuras ficou fixa.

## Como repetir

- Neste ambiente: `tools/bench/render_matrix.sh` e `tools/bench/render_breakdown.gd` (ver `tools/bench/README.md`).
- No PC: Sandbox → monte a cena → **F6** (painel) → **F7** várias vezes (normal → congelado → quadrados → lote
  simulado). Compare FPS, quadro e draw calls de cada modo.
  - **congelado vs normal**: custo da CPU do `_draw`.
  - **lote simulado vs normal**: ganho esperado da proposta.
