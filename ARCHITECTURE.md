# Mortivane (Godot 4) — Arquitetura

Estado: **Etapa 1 — esqueleto + arena.** Nenhum sistema de jogo ainda (unidades, combate, HUD, ondas…).
Referência funcional/visual: `MortivaneV97.html` (não é editado). Análise do HTML: `MIGRATION_NOTES.md`.

Engine: **Godot 4.7** · renderer **Compatibility** (2D puro, roda em qualquer GPU) · GDScript.

---

## Princípios

1. **Mundo lógico 1000 × 560.** Todas as coordenadas de gameplay usam essa unidade, igual ao HTML.
   Os números do HTML (alcance, velocidade, limites, grades) são portados sem conversão.
2. **Fonte única de verdade** para constantes do mundo: `WorldConfig`.
3. **Simulação separada da apresentação** (a partir das próximas etapas): dados/regras em scripts sem
   dependência de nós visuais; cenas só desenham o estado.
4. **Camadas com responsabilidades fixas**: o fundo nunca recebe efeitos de gameplay; o tremor de tela
   (futuro) afeta só o `Stage`.
5. Um sistema por etapa. Não replicar as camadas de remendo "V64…V97" do HTML.

---

## Resolução, escala e resize

| Configuração (`project.godot`) | Valor | Por quê |
|---|---|---|
| `viewport_width × viewport_height` | **1000 × 490** | largura do mundo × **altura mínima visível** (ver abaixo) |
| janela inicial | 1600 × 896 | 1000:560 × 1,6 |
| `stretch/mode` | `canvas_items` | tudo escala uniformemente a partir das unidades do mundo |
| `stretch/aspect` | `expand` | sobra de tela vira área visível extra, sem barras pretas |

O viewport base é 490 de altura (e não 560) para reproduzir o comportamento V65/V67 do HTML: em telas mais
largas que 1000:490, o palco pode esconder **até 70 unidades** de altura (56 do céu e 14 do rodapé) para
aproveitar melhor a largura. O mundo continua sendo 1000×560, e a área jogável (y de 210 a 534) nunca é cortada.

`Arena._update_framing()` roda no início e a cada `size_changed`:
- **Câmera:** centralizada em x=500. Com altura visível ≥ 560, centraliza em y=280. Com altura menor,
  o corte sai 80% de cima e 20% de baixo.
- **Fundo (cover, como no HTML V68):**
  - uma caixa 1000:560 cobre a tela inteira, ancorada ao mundo em y≈380 e presa para nunca deixar
    uma faixa vazia;
  - a textura (1672×941) cobre essa caixa com escala uniforme, **sem distorção**.

Casos verificados com captura real da janela:

| Janela | Mundo visível | Resultado |
|---|---|---|
| 1600×896 (16:9) | 1000×560 | mundo inteiro |
| 1800×700 (ultrawide) | 1260×490, y de 56 a 546 | corte máximo, arte preenche as laterais |
| 1000×800 (4:3) | 1000×800, y de −120 a 680 | mais céu e mais chão |

---

## Estrutura de pastas

```
res://
  project.godot
  assets/art/arena_background.webp   # extraída do base64 do HTML (ARENA_ART_SRC), sem recompressão
  scenes/
    main/main.tscn                   # raiz do jogo
    arena/arena.tscn                 # arena: camadas + debug
  scripts/
    core/world_config.gd             # class_name WorldConfig — constantes do mundo
    arena/arena.gd                   # enquadramento (câmera + fundo cover)
    arena/battle_grid.gd             # class_name BattleGrid — geometria das grades (só leitura)
    arena/debug_overlay.gd           # desenho de referência (F3)
    main/main.gd                     # atalhos de janela (F11)
```

Arquivos `*.import` e `*.uid` são gerados pela Godot e **devem ser versionados**. A pasta `.godot/` é cache
e fica fora do Git.

---

## Cenas

```
Main (Node)                      main.gd — F11 alterna tela cheia
└─ Arena (Node2D)                arena.gd — enquadramento
   ├─ Camera2D                   posicionada pelo enquadramento
   ├─ Background (Node2D)        arte fixa; nunca treme nem recebe efeitos
   │   └─ ArenaArt (Sprite2D)
   ├─ Stage (Node2D)             ← futuro tremor de tela aplicado aqui
   │   ├─ World (Node2D)
   │   │   ├─ Ground             áreas no chão, cadáveres (futuro)
   │   │   └─ Entities           unidades, y_sort_enabled (futuro)
   │   └─ Effects (Node2D)       efeitos visuais do gameplay (futuro)
   └─ Debug (Node2D)             debug_overlay.gd — F3 liga/desliga
       └─ InfoLayer (CanvasLayer 100) / InfoLabel   janela, mundo visível, escala
```

Os nós `Ground`, `Entities` e `Effects` estão vazios e servem só para fixar a ordem de desenho.

---

## Referência de coordenadas (`WorldConfig`)

| Constante | Valor | Origem no HTML |
|---|---|---|
| `WIDTH × HEIGHT` | 1000 × 560 | `W, H` |
| `MARGIN` | 26 | `MARGIN` |
| `BATTLEFIELD_TOP_Y` | 210 | `BATTLEFIELD.topY = round(560 × 0,375)` |
| `BATTLEFIELD_RECT` | x de 26 a 974, y de 210 a 534 | limites de `clampPointToBattlefield` |
| `DEPLOY_X` | 500 | `DEPLOY_X = W × 0,5` |
| `PORTAL_POSITION`, `PORTAL_RADIUS` | (500, 176), 46 | `PORTAL` |
| `PORTAL_GROUND_BREAK_Y` | 259 | `round(560 × 0,49) − 15` |
| `MIN_VISIBLE_HEIGHT`, `TOP_CROP_SHARE` | 490, 0,8 | CSS V65/V67 (`--stage-w`, `--stage-t`) |
| `ART_ANCHOR_Y` | 380 | CSS V68 (fator 0,678571) |

**Grades (`BattleGrid`, portado de `buildBattleGrid`)**
- 11 colunas × 7 linhas por lado.
- Jogador: x de 38 a 488, y de ≈209,3 a ≈480,3.
- Inimigo: x de 512 a 962, y de 248 a 519.
- Célula ≈ 40,9 × 38,7.
- Máscara do jogador: `A` livre, `B` bloqueada, `N` reservada ao Necromante.

Nesta etapa as grades são **só visuais**: não há ocupação, footprint nem arrasto.

---

## Próximas etapas (planejadas)

1. ~~Esqueleto + arena~~ ✔
2. Máquina de fases (`MENU/PREP/BATTLE/NECROMANCY/VICTORY/DEAD`) + autoloads `GameState` e `Events`, e menu mínimo.
3. Resources de dados (`UnitDef`, `FactionDef`…) + unidade placeholder + posicionamento na grade.
4. Relógio de batalha de passo fixo (1/120 s, 1x/2x/3x) + movimento, alvo e ataque.
5. Cadáveres, Necromancia e portal.
6. Essência, capacidade, lojas, Relíquias, Escola e HUD.
7. Áudio, configurações e ferramentas (sandbox, bot).
