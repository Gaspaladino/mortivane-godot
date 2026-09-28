# Mortivane (Godot 4) — Arquitetura

Estado: **Etapa 1 (esqueleto + arena) + núcleo mínimo de combate** (1 aliado × 1 inimigo).
Ainda não há fases, menu, HUD, ondas, formação nem Necromancia.
Referência funcional/visual: `MortivaneV97.html` (não é editado). Análise do HTML: `MIGRATION_NOTES.md`.

Engine: **Godot 4.7** · renderer **Compatibility** (2D puro, roda em qualquer GPU) · GDScript.

---

## Princípios

1. **Mundo lógico 1000 × 560.** Todas as coordenadas de gameplay usam essa unidade, igual ao HTML.
   Os números do HTML (alcance, velocidade, limites, grades) são portados sem conversão.
2. **Fonte única de verdade** para constantes do mundo: `WorldConfig`.
3. **Simulação separada da apresentação:** dados/regras em scripts sem dependência de nós visuais
   (`CombatUnit`, `CombatSim`); cenas só desenham o estado (`UnitView`). A simulação roda igual em teste headless.
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
  assets/art/novocenario.png         # arte da arena (1672×941); substituiu a arte extraída do HTML
  scenes/
    main/main.tscn                   # raiz do jogo
    arena/arena.tscn                 # arena: camadas + debug
  scripts/
    core/world_config.gd             # class_name WorldConfig — constantes do mundo
    arena/arena.gd                   # enquadramento (câmera + fundo cover)
    arena/battle_grid.gd             # class_name BattleGrid — geometria das grades (só leitura)
    arena/debug_overlay.gd           # class_name DebugOverlay — desenho de referência
    combat/combat_unit.gd            # class_name CombatUnit — estado de uma unidade (dado puro)
    combat/combat_sim.gd             # class_name CombatSim — alvo, movimento, ataque, dano, morte (dado puro)
    combat/unit_view.gd              # class_name UnitView — visual temporário + barra de HP + debug
    combat/battle.gd                 # class_name Battle — luta de teste, passo fixo, cria os UnitView
    main/main.gd                     # atalhos globais (F3/F4/F9/F11) + avisos
  tests/
    combat_test.gd                   # teste headless do combate (SceneTree)
```

Arquivos `*.import` e `*.uid` são gerados pela Godot e **devem ser versionados**. A pasta `.godot/` é cache
e fica fora do Git.

---

## Cenas

```
Main (Node)                      main.gd — atalhos globais (F3, F4, F9, F11) e avisos
├─ NoticeLayer (CanvasLayer 110) / NoticeLabel   aviso temporário no rodapé
└─ Arena (Node2D)                arena.gd — enquadramento; set_debug_visible()
   ├─ Camera2D                   posicionada pelo enquadramento
   ├─ Background (Node2D)        arte fixa; nunca treme nem recebe efeitos
   │   └─ ArenaArt (Sprite2D)
   ├─ Stage (Node2D)             ← futuro tremor de tela aplicado aqui
   │   ├─ World (Node2D)
   │   │   ├─ Ground             áreas no chão, cadáveres (futuro)
   │   │   └─ Entities           unidades (UnitView, criados por Battle), y_sort_enabled
   │   └─ Effects (Node2D)       efeitos visuais do gameplay (futuro)
   ├─ Battle (Node)              battle.gd — luta de teste; entities_path → Stage/World/Entities
   └─ Debug (Node2D)             debug_overlay.gd — DebugOverlay.set_shown()
       └─ InfoLayer (CanvasLayer 100) / InfoLabel   janela, mundo visível, escala
```

`Ground` e `Effects` estão vazios e servem só para fixar a ordem de desenho. `Entities` recebe os `UnitView`.

---

## Input e atalhos

As ações ficam no **InputMap** (`project.godot`, seção `[input]`) e usam a **tecla física**
(`physical_keycode`), que não depende do layout do teclado:

| Ação | Tecla | Efeito |
|---|---|---|
| `debug_toggle` | F3 | liga/desliga a camada de debug e o painel de informações |
| `fullscreen_toggle` | F11 | alterna entre janela e tela cheia (`Window.mode`: `MODE_WINDOWED` ↔ `MODE_FULLSCREEN`) |
| `combat_debug_toggle` | F4 | liga/desliga o debug de combate (alcance, alvo, HP, estado) |
| `combat_restart` | F9 | reinicia a luta de teste |

- Atalhos globais ficam **só em `Main`** e são tratados em `_input`, antes da interface, para que nenhum
  controle de UI futuro consiga "engolir" as teclas. A Arena expõe `set_debug_visible()` e `is_debug_visible()`;
  `Battle` (via `arena.battle`) expõe `set_debug_visible()`, `is_debug_visible()` e `restart()`.
- **Jogo embutido no editor.** A Godot 4.4+ roda o jogo dentro da aba *Game* por padrão:
  - o jogo só recebe teclado quando a área dele está focada;
  - uma janela embutida **não pode** entrar em tela cheia.

  `Engine.is_embedded_in_editor()` detecta esse caso. Nele, `Main` mostra um aviso ao iniciar e ao apertar
  F11, em vez de falhar em silêncio.
- **Recomendação para desenvolvimento:** rodar o jogo em janela própria. Na aba *Game*, menu ⋮ → desmarque
  **Embed Game on Next Play**, ou use *Editor Settings → Run → Window Placement → Game Embed Mode = Disabled*.

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

## Combate (núcleo mínimo)

Luta de teste fixa: **1 aliado × 1 inimigo**, que começa sozinha. Não há fase de batalha, ondas nem formação.

**Camadas**
- `CombatUnit` (`RefCounted`) guarda o estado de uma unidade:
  - time, posição, raio;
  - `hp` / `max_hp`, `damage`, `attack_range`, `attack_interval`, `move_speed`;
  - `cooldown`, `target` e `state` (`IDLE / MOVING / ATTACKING / DEAD`).
- `CombatSim` (`RefCounted`) contém as regras. Não conhece nós. Emite `unit_attacked` e `unit_died`.
- `Battle` (`Node`, dentro da Arena) é o dono da simulação:
  - acumula o dt do quadro (limitado a 0,05 s) e avança a simulação em passos fixos de `CombatSim.STEP` = 1/120 s;
  - cria um `UnitView` por unidade em `Stage/World/Entities`;
  - emite `finished(winner)` uma vez, quando um lado fica sem ninguém vivo.
- `UnitView` (`Node2D`, visual temporário) só lê a `CombatUnit`:
  - círculo com as cores do HTML e barra de HP;
  - flash ao ser atingido e sumiço gradual ao morrer;
  - debug com F4.

**Regras por passo** (para cada unidade viva, em ordem de criação)
1. Desconta a recarga.
2. Alvo = inimigo **vivo** mais próximo (distância centro a centro). Sem nenhum → `IDLE`.
3. `dist > attack_range` → `MOVING`: anda até o alvo, no máximo `move_speed × dt` por passo, parando em
   0,85 × alcance. A posição é presa à área jogável, usando o raio.
4. Senão → `ATTACKING`: não se move. Com a recarga zerada, aplica `damage` e recarrega com `attack_interval`.
5. `take_damage` tira no máximo o HP restante. HP 0 → `die()`: estado `DEAD`, sem alvo. A partir daí a unidade
   não age e `is_valid_target()` é falso.

**Referências entre unidades.** `target` forma um ciclo de `RefCounted` (A → B → A). Por isso
`CombatSim.dispose()` limpa os alvos, e `Battle` o chama ao reiniciar e em `_exit_tree`.

**Stats** (`Battle.ALLY_STATS`, `Battle.ENEMY_STATS`, portados de `UNIT_DEFS`)

| Unidade | Início | HP | Dano | Alcance | cd | Vel. | r |
|---|---|---|---|---|---|---|---|
| Aliado `u_warrior` | (150, 380) | 74 | 10 | 32 | 1,0 | 56 | 12 |
| Inimigo `warrior` | (850, 380) | 70 | 9 | 32 | 1,0 | 56 | 12 |

A semente fixa (97) torna a luta determinística: o aliado vence com 20/74 HP em ≈12,0 s.

**Teste headless**
```
godot --headless --import                      # uma vez, gera o cache de classes (.godot/)
godot --headless -s res://tests/combat_test.gd # sai com 0 se passar, 1 se falhar
```

As simplificações em relação ao HTML estão em `MIGRATION_NOTES.md`, seção 6.

---

## Próximas etapas (planejadas)

1. ~~Esqueleto + arena~~ ✔ · ~~núcleo mínimo de combate (1 × 1)~~ ✔
2. Máquina de fases (`MENU/PREP/BATTLE/NECROMANCY/VICTORY/DEAD`) + autoloads `GameState` e `Events`, e menu mínimo.
3. Resources de dados (`UnitDef`, `FactionDef`…) + unidade placeholder + posicionamento na grade.
4. Batalha completa sobre o núcleo: velocidade 1x/2x/3x, IA de formação, unidades à distância/projéteis,
   integração com a fase de batalha. (Passo fixo, movimento, alvo e ataque básico já existem.)
5. Cadáveres, Necromancia e portal.
6. Essência, capacidade, lojas, Relíquias, Escola e HUD.
7. Áudio, configurações e ferramentas (sandbox, bot).
