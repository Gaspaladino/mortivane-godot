# Mortivane (Godot 4) — Arquitetura

Estado: **Etapa 1 (esqueleto + arena) + núcleo mínimo de combate + menu inicial + Sandbox
+ Guerreiro, Guerreiro Sombra, Sentinela Arcana, Sentinela Arcana Sombra, Paladino e Paladino Sombra
desenhados 100% por código
+ regra visual "sombra necromântica" (ShadowStyle + ShadowFX) para as unidades revividas.**
Ainda não há campanha, fases, HUD de jogo, ondas, formação nem Necromancia.
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
  assets/art/arena_layers/           # primeiro plano extraído da arte (chão, laterais, estandartes, velas)
  tools/arena_backdrop/build_layers.py  # extrai o primeiro plano (Python, só desenvolvimento)
  tools/arena_backdrop/generate_backdrop_scene.gd  # gera arena_backdrop.tscn UMA vez (depois: editar no editor)
  tools/bench/                          # stress test / profiling do combate (só medição; ver tools/bench/README.md)
                                        #   perf_overlay_shots.gd: capturas do painel de desempenho (F6) no Sandbox
  tools/sprites/slice_paladin_sheets.py  # fatia as 5 sprite sheets do Paladino Vivo (atlas + SpriteFrames + JSON)
  assets/units/paladin/               # Paladino Vivo: source/ (sheets originais, .gdignore), atlas, SpriteFrames, JSON
  scenes/units/paladin_live_visual.tscn    # visual PADRÃO do Paladino Vivo (PaladinLiveVisual; parâmetros no Inspector)
  scenes/units/paladin_rig_visual.tscn     # alternativa (fora de uso): rig 2.5D facetado (Shadow · Rig · Effects)
  scenes/units/paladin_sprite_visual.tscn  # alternativa (fora de uso): Paladino Vivo por sprites (Shadow · Sprite · Effects)
  tools/sprites/render_paladin_pilot.gd  # PROTÓTIPO (superado pela sheet aprovada): pinta e exporta a sprite sheet piloto do Paladino Vivo (3/4)
  assets/sprites/paladin_live_pilot/  # sheet (Idle 6 · Walk 8 · Attack 8), frames, sombra, SpriteFrames, JSON do contrato
  scenes/prototypes/paladin_sprite_pilot.tscn  # PROTÓTIPO: prévia da sheet na arena (escala de jogo e ampliada)
  data/
    units/u_warrior.tres             # UnitDef — Guerreiro Sombra (aliado)
    units/warrior.tres               # UnitDef — Guerreiro (inimigo)
    units/arc_battlemage.tres        # UnitDef — Sentinela Arcana (inimiga)
    units/u_arc_battlemage.tres      # UnitDef — Sentinela Arcana Sombra (aliada)
    units/sac_paladin.tres           # UnitDef — Paladino (inimigo)
    units/u_sac_paladin.tres         # UnitDef — Paladino Sombra (aliado)
    visuals/paladin_look.tres        # PaladinLook — escala, offsets, cores, brilho do Paladino por código (base do Sombra)
    visuals/paladin_rig_look.tres    # PaladinRigLook — todos os ajustes do Paladino Vivo 2.5D (Inspector)
    visuals/shadow_style.tres        # ShadowStyle padrão: a conversão "sombra" de TODAS as unidades revividas
  scenes/
    main/main.tscn                   # raiz do jogo: troca de tela + avisos
    menu/main_menu.tscn              # menu inicial (Jogar / Sandbox)
    sandbox/sandbox.tscn             # Sandbox: Arena + SandboxUI + SandboxController
    sandbox/sandbox_ui.tscn          # interface do Sandbox (faixa inferior, Controls editáveis)
    sandbox/sandbox_theme.tres       # tema da interface do Sandbox
    arena/arena.tscn                 # arena: camadas + Battle + debug
    arena/arena_backdrop.tscn        # fundo da arena: ~190 nós editáveis em 21 camadas
  scripts/
    core/world_config.gd             # class_name WorldConfig — constantes do mundo
    arena/arena.gd                   # enquadramento (câmera + fundo cover)
    arena/battle_grid.gd             # class_name BattleGrid — geometria das grades (só leitura)
    arena/debug_overlay.gd           # class_name DebugOverlay — desenho de referência
    combat/combat_unit.gd            # class_name CombatUnit — estado de uma unidade (dado puro)
    combat/combat_sim.gd             # class_name CombatSim — alvo, movimento, ataque, projéteis, dano, morte (dado puro)
    combat/combat_projectile.gd      # class_name CombatProjectile — projétil da simulação (dado puro)
    combat/abilities/sentinel_swords.gd  # class_name SentinelSwords — lâminas da Sentinela (dado puro)
    combat/abilities/paladin_taunt.gd    # class_name PaladinTaunt — provocação + Escudo Sagrado (dado puro)
    combat/unit_view.gd              # class_name UnitView — seleção + barra de HP + debug; hospeda o visual
    debug/bench/bench_combat_sim.gd  # class_name BenchCombatSim — SÓ benchmark: CombatSim com contadores/cronômetros
    visuals/units/unit_visual.gd     # class_name UnitVisual — base/interface do "corpo" de uma unidade
    visuals/units/circle_unit_visual.gd     # class_name CircleUnitVisual — círculo padrão (sem visual_script)
    visuals/units/code_drawn_unit_visual.gd # class_name CodeDrawnUnitVisual — utilitários de desenho comuns
    visuals/units/draw_cache.gd      # class_name DrawCache — formas repetidas viram malhas (mesma geometria do motor)
    visuals/units/sentinel_visual.gd        # class_name SentinelVisual — Sentinela Arcana viva
    visuals/units/sentinel_shadow_visual.gd # class_name SentinelShadowVisual — Sentinela Sombra (herda a viva)
    visuals/effects/arcane_blade.gd         # class_name ArcaneBlade — desenho da lâmina (pairando e em voo)
    visuals/projectiles/projectile_view.gd  # class_name ProjectileView — orbe/lâmina em voo + impacto
    visuals/backdrop/arena_backdrop.gd      # class_name ArenaBackdrop — orquestra camadas, tempo, parallax, ajustes
    visuals/backdrop/arena_layers_data.gd   # class_name ArenaLayersData — GERADO: posições do primeiro plano
    visuals/backdrop/nodes/*.gd             # nós do fundo: BackdropCloud, BackdropDrift, BackdropFog, BackdropMoon,
                                            # CastleWindow, CastleLights, CandleFlame, CandleGlow, BannerSway, BackdropShaderRect
    visuals/backdrop/shaders/*.gdshader     # céu, lua, nuvens, neblina, estandarte, velas (+ noise.gdshaderinc)
    visuals/units/warrior_visual.gd         # class_name WarriorVisual — Guerreiro por código (rig + animação)
    visuals/units/shadow_warrior_visual.gd  # class_name ShadowWarriorVisual — Guerreiro Sombra (herda o Guerreiro)
    visuals/units/paladin_visual.gd         # class_name PaladinVisual — Paladino por código (rig + animação)
    visuals/units/shadow_paladin_visual.gd  # class_name ShadowPaladinVisual — Paladino Sombra (herda o Paladino)
    visuals/units/paladin_look.gd           # class_name PaladinLook (Resource) — parâmetros visuais do Paladino
    visuals/units/paladin_sprite_visual.gd  # class_name PaladinSpriteVisual — Paladino Vivo por sprite sheet (alternativa)
    visuals/units/paladin_live_visual.gd    # class_name PaladinLiveVisual — Paladino Vivo PADRÃO (família do Guerreiro)
    visuals/units/paladin/                  # animador/poses (usados pelo padrão) + rig 2.5D facetado (alternativa):
      paladin_rig_visual.gd   # class_name PaladinRigVisual (UnitVisual) — cola: eventos → animador → rig/efeitos
      paladin_animator.gd     # class_name PaladinAnimator — estados, direção, transições, sincronia, molas
      paladin_pose_library.gd # class_name PaladinPoseLibrary — poses-base por direção + clipes (deltas)
      paladin_rig.gd          # class_name PaladinRig — esqueleto (cinemática), projeção 2.5D, desenho ordenado
      paladin_model.gd        # class_name PaladinModel — ossos (pivôs) e peças low-poly (malhas + decalques)
      paladin_mesh.gd         # class_name PaladinMesh — malhas facetadas (loft, lathe, prisma, painel, decalque)
      paladin_effects.gd      # class_name PaladinEffects — provocação, escudo, bloqueio (separados do corpo)
      paladin_rig_look.gd     # class_name PaladinRigLook (Resource) — parâmetros do Inspector
    visuals/units/paladin_fx.gd             # class_name PaladinFx — barreira, anel da provocação, anel do escudo
    visuals/units/shadow_style.gd           # class_name ShadowStyle (Resource) — regra de conversão viva → sombra
    visuals/units/shadow_fx.gd              # class_name ShadowFX — aura, névoa, fumaça, fissuras, olhos
    combat/battle.gd                 # class_name Battle — executor: CombatSim + UnitView + passo fixo
    data/unit_def.gd                 # class_name UnitDef (Resource) — definição de unidade
    data/unit_catalog.gd             # class_name UnitCatalog — carrega data/units/*.tres
    menu/main_menu.gd                # class_name MainMenu — só emite sinais
    sandbox/sandbox_controller.gd    # class_name SandboxController — montagem, ações, seleção
    sandbox/sandbox_ui.gd            # class_name SandboxUI — liga os Controls da cena a sinais
    main/main.gd                     # troca de tela + atalhos globais (F3/F4/F6/F9/F11) + avisos
    debug/perf_overlay.gd            # class_name PerfOverlay — painel de desempenho do Sandbox (F6, só leitura)
  tests/
    combat_test.gd                   # teste headless do combate (SceneTree)
    sandbox_test.gd                  # teste headless de ponta a ponta: menu + Sandbox na cena real
    visual_test.gd                   # teste headless das poses/animações dos visuais por código
    sentinel_test.gd                 # teste headless da Sentinela: mecânica portada do HTML + visual
    backdrop_test.gd                 # teste headless do fundo animado (inclui "nada flutua")
    menu_click_test.gd               # cliques reais de mouse no menu (Sandbox ida e volta)
    shadow_visual_test.gd            # regra visual das sombras (u_* = sombra; viva continua normal)
    paladin_test.gd                  # Paladino: stats/mecânica do HTML, visual, Sandbox, luta de referência
    paladin_sprite_test.gd           # Paladino Vivo por sprites (alternativa): SpriteFrames, pivô, estados
    paladin_live_test.gd             # Paladino Vivo padrão: gameplay idêntico, família do Guerreiro, mãos, direções, estados, Sandbox
    paladin_rig_test.gd              # rig 2.5D (alternativa): mão da espada, direções, estados
```

Arquivos `*.import` e `*.uid` são gerados pela Godot e **devem ser versionados**. A pasta `.godot/` é cache
e fica fora do Git.

---

## Cenas

```
Main (Node)                      main.gd — troca de tela, atalhos globais (F3, F4, F6, F9, F11) e avisos
├─ <tela atual>                  uma por vez: MainMenu ou Sandbox (instanciada por Main)
└─ NoticeLayer (CanvasLayer 110) / NoticeLabel   aviso temporário no rodapé

MainMenu (Control)               main_menu.gd — título + Jogar / Sandbox; sinais play_pressed, sandbox_pressed
├─ Backdrop (TextureRect)        a arte da arena, escurecida (cover)
└─ Center / Box                  título, botões, MessageLabel

Sandbox (Node)                   sandbox_controller.gd — montagem, ações, seleção; sinal exit_requested
├─ Arena                         a MESMA arena.tscn (instância), sem nada específico de Sandbox
├─ SandboxUI (sandbox_ui.tscn)    faixa inferior com Controls editáveis (ver "Sandbox")
└─ PerfOverlay (CanvasLayer 60)  painel de desempenho, topo esquerdo, desligado por padrão (F6)

Arena (Node2D)                   arena.gd — enquadramento; set_debug_visible()
   ├─ Camera2D                   posicionada pelo enquadramento
   ├─ Background (Node2D)        fundo; nunca treme nem recebe efeitos de gameplay
   │   └─ Backdrop (ArenaBackdrop, arena_backdrop.tscn) — fundo editável (ver "Fundo da arena")
   ├─ Stage (Node2D)             ← futuro tremor de tela aplicado aqui
   │   ├─ World (Node2D)
   │   │   ├─ Ground             áreas no chão, cadáveres (futuro)
   │   │   └─ Entities           unidades (UnitView, criados por Battle), y_sort_enabled
   │   └─ Effects (Node2D)       efeitos visuais do gameplay (futuro)
   ├─ Battle (Node)              battle.gd — executor do combate; entities_path → Stage/World/Entities
   └─ Debug (Node2D)             debug_overlay.gd — DebugOverlay.set_shown()
       └─ InfoLayer (CanvasLayer 100) / InfoLabel   janela, mundo visível, escala (topo esquerdo)
```

**Troca de tela.** `Main._switch_to()` tira a tela antiga da árvore na hora (a Arena antiga não disputa a
câmera) e a libera no fim do quadro, depois instancia a nova. Não há `change_scene`: `Main` e o `NoticeLayer`
continuam vivos entre telas.

O painel do F3 (`InfoLabel`) e o aviso do `Main` ficam no **topo**: a faixa de baixo é da interface do Sandbox.

**Reserva para a interface.** `Arena.set_bottom_inset(px)` enquadra o mundo na área acima de uma faixa de
interface:
- se a área útil ficar mais baixa que 490 unidades, a câmera afasta (`zoom < 1`);
- o fundo continua cobrindo a tela toda, inclusive por trás da faixa.

O Sandbox chama `set_bottom_inset` com a altura da sua faixa sempre que ela muda. Em 1600×896 a faixa ocupa
22%, o zoom fica em 0,89 e o campo inteiro (y de 210 a 534) aparece acima dela.

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
| `combat_restart` | F9 | atalho secundário de **Reiniciar combate** no Sandbox (o principal é o botão) |
| `perf_overlay_toggle` | F6 | liga/desliga o painel de desempenho do Sandbox (começa desligado) |

- Atalhos globais ficam **só em `Main`** e são tratados em `_input`, antes da interface, para que nenhum
  controle de UI consiga "engolir" as teclas. Os botões usam `focus_mode = NONE`, então teclas nunca os apertam.
- `Main` guarda o estado de F3/F4/F6 e o aplica a toda Arena (e todo Sandbox) nova, então ele sobrevive a sair e
  voltar ao Sandbox. No menu, F3/F4/F6 só mudam esse estado guardado.
- Uma tela com Arena expõe `get_arena()`. A Arena expõe `set_debug_visible()` / `is_debug_visible()`, e
  `arena.battle` expõe os mesmos métodos para o debug de combate.
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

O mesmo combate serve a qualquer modo que use a Arena. Hoje o único é o Sandbox. Não há fase de batalha,
ondas nem formação.

**Camadas**
- `CombatUnit` (`RefCounted`) guarda o estado de uma unidade:
  - time, posição, raio;
  - `hp` / `max_hp`, `damage`, `attack_range`, `attack_interval`, `move_speed`;
  - `cooldown`, `target` e `state` (`IDLE / MOVING / ATTACKING / DEAD`).
- `CombatSim` (`RefCounted`) contém as regras. Não conhece nós. Sinais:
  - `attack_performed(atacante, alvo)`: o ataque básico ACONTECEU (golpe desferido ou projétil disparado);
  - `projectile_fired(p)` e `projectile_ended(p, vítima)`;
  - `unit_attacked(atacante, alvo, dano)`: dano aplicado;
  - `unit_died(unidade)`.
- `Battle` (`Node`, dentro da Arena) é o **executor**. Não decide quem luta nem quando.
  - API: `spawn(def, team, pos, overrides)`, `start()`, `clear()`, `is_running()`, `is_finished()`,
    `unit_at(ponto)` e `view_of(unit)`.
  - Nasce vazia e **parada**. Só depois de `start()` acumula o dt do quadro (limitado a 0,05 s) e avança a
    simulação em passos fixos de `CombatSim.STEP` = 1/120 s.
  - **No máximo `MAX_SIM_STEPS_PER_FRAME` = 4 passos por quadro** (cobre 30 FPS sem perder tempo). Um quadro
    lento não faz mais que isso: a sobra (até 4 passos) é recuperada nos quadros seguintes e o excesso é
    descartado (`dropped_time`) — câmera lenta em vez de efeito cascata. O resultado da luta não muda
    (mesma sequência de passos). Diagnóstico: `steps_last_frame`.
  - Cria um `UnitView` por unidade em `Stage/World/Entities`.
  - Emite `finished(winner_team)` uma vez, quando um lado fica sem ninguém vivo (−1 = ninguém sobrou).
    A simulação continua rodando depois disso, e os sobreviventes passam a `IDLE`.
- `UnitView` (`Node2D`) só lê a `CombatUnit` e hospeda o corpo (ver **Visuais de unidade**):
  - anel de seleção (elipse nos pés) e, com F4, alcance e linha até o alvo;
  - filho `Body` = o `UnitVisual` da `UnitDef`;
  - filho `Overlay` = barra de HP e texto do F4, sempre por cima do corpo.
  - Redesenho: o corpo todo quadro (animação); o anel e a barra **só quando o que mostram muda** (HP, vida,
    altura, seleção) ou com o F4 ligado.
  - **Cadáver congelado:** quando o visual diz que o cadáver assentou (`is_settled_corpse()`), o UnitView
    para de chamar `update_visual` e `queue_redraw`; a última pose fica no RenderingServer. Mover o cadáver só
    muda a posição do nó; reviver (Necromancia) ou ligar o F4 volta a animar.
- A `Battle` repassa os sinais como eventos **só visuais**:
  - `attack_performed` → `on_attack_performed()` no atacante;
  - `unit_attacked` → `on_hit()` no alvo;
  - `projectile_fired` → `on_projectile_fired()` no dono, mais um `ProjectileView` em `Stage/Effects`;
  - `projectile_ended` → impacto (ou dissipação) no `ProjectileView`, que depois se libera sozinho.
- `unit_at()` usa a área clicável do visual (`UnitView.contains_point`).

**Regras por passo** (para cada unidade viva, em ordem de criação)
1. Desconta a recarga.
2. Alvo = inimigo **vivo** mais próximo (distância centro a centro; empate = o primeiro criado). Sem nenhum → `IDLE`.
   Implementação (otimização 1, resultado idêntico ao de varrer todo mundo a cada passo):
   - só percorre as listas de unidades **ativas** por time (quem morre sai na hora; cadáveres e aliados nunca
     são examinados);
   - mantém o alvo enquanto há **garantia** de que ele continua estritamente o mais próximo: na varredura guarda
     os 3 inimigos seguintes e a distância do resto; como a simulação sabe quanto cada unidade andou (odômetro,
     `_move_unit`) e quanto o time inimigo andou no máximo, só varre de novo quando a folga acaba ou o alvo morre.
   - Contadores `stat_target_queries/scans/candidates` para o benchmark.
3. `dist > attack_range` → `MOVING`: anda até o alvo, no máximo `move_speed × dt` por passo, parando em
   0,85 × alcance. A posição é presa à área jogável, usando o raio.
4. Senão → `ATTACKING`: não se move. Com a recarga zerada, aplica `damage` e recarrega com `attack_interval`.
5. `take_damage` tira no máximo o HP restante. HP 0 → `die()`: estado `DEAD`, sem alvo. A partir daí a unidade
   não age e `is_valid_target()` é falso.

**Referências entre unidades.** `target` forma um ciclo de `RefCounted` (A → B → A). Por isso
`CombatSim.dispose()` limpa os alvos, e `Battle` o chama em `clear()` e em `_exit_tree`.

**Ataque à distância e habilidades (por unidade; o corpo a corpo não muda).**
- `CombatUnit.projectile` (vindo de `UnitDef.projectile_kind`) torna o ataque básico um disparo. No passo do
  ataque, a `CombatSim` cria um `CombatProjectile`, e o dano só é aplicado quando ele acerta. Regras do HTML
  (`fireProjectile` / `updateProjectiles`):
  - nasce na borda do corpo;
  - persegue o alvo travado enquanto ele for válido;
  - acerta o alvo a raio + 6, ou qualquer inimigo no caminho a raio + 5;
  - some após 2,6 s ou ao sair do mundo.
  - Velocidades: orbe 340, lâmina 520.
- Unidades à distância param a **0,92 × alcance** (HTML); o corpo a corpo continua em 0,85.
- `CombatUnit.swords` (`SentinelSwords`, de `abilities = ["arcane_swords"]`) roda a cada passo, antes do alvo.
  É uma porta fiel de `SENTINEL_CONFIG` / `updateArcaneSwords` / `launchSword`:
  - 2 lâminas; disparam quando o inimigo vivo mais próximo está a ≤ 115;
  - reação de 0,55 s (aproximação lenta) até 0,08 s (aproximação ≥ 55 px/s);
  - 0,10 s de antecipação (`blade.windup`); uma de cada vez, com 0,35 s entre elas;
  - dano = ataque básico × 1; cada lâmina volta após 10 s;
  - partem da âncora (x ± 0,82 r, y − 1,9 r) como projétil perseguidor a 520 px/s.
- A lâmina e o orbe **não** interferem na recarga do ataque básico, como no HTML.
- `CombatUnit.paladin` (`PaladinTaunt`, de `abilities = ["paladin_taunt_shield"]`): porta fiel de
  `PALADIN_CONFIG` / `tickPaladinCombat` / `paladinShieldDamage` / `lockPaladinShieldFacing`:
  - roda numa **passada antes de todas as unidades** (`CombatSim._tick_paladins`, como o HTML chama
    `tickPaladinCombat` antes de `updateUnit`): desconta `taunt_t` de todos e os timers dos Paladinos;
  - pronto (recarga 0 — começa em 0) e com inimigo vivo a ≤ **115**: provoca todos eles por **2,5 s**
    (`taunted_by`/`taunt_t`, alvo = o Paladino), recarga **15 s**, e começa a espera de **1 s**;
  - ao fim da espera sobe o **Escudo Sagrado** por **1,5 s** (descontando o excesso do passo), com a direção
    travada no alvo/provocado/mais próximo;
  - com o escudo, todo dano recebido é reduzido em **75%** (`CombatSim._apply_damage`);
  - provocado: `nearest_foe` devolve o Paladino enquanto a provocação vale (HTML: `tauntTarget` dentro de
    `nearestFoe`); morto o Paladino, quem ele provocou é liberado (HTML: `killUnit` → `clearTaunt`).
  - Sinais só de apresentação: `paladin_taunted`, `paladin_shield_raised`, `paladin_shield_blocked`
    (a `Battle` repassa como `UnitView.on_ability_event(taunt/shield/block)`).
  - Quem não tem a habilidade não muda: a luta de referência (Guerreiro × Guerreiro) é idêntica.

**Semente.** `Battle.rng_seed = 97` sorteia a primeira recarga de cada unidade. Assim, a mesma montagem sempre
produz a mesma luta, e o **Reiniciar** do Sandbox repete a luta exatamente igual.

As simplificações em relação ao HTML estão em `MIGRATION_NOTES.md`, seção 6.

---

## Visuais de unidade (desenho 100% por código)

Nenhum PNG, SVG, sprite sheet ou asset externo. Cadeia: `CombatUnit` → `UnitView` → `UnitVisual`.

- `UnitVisual` (`Node2D`) é a base. Recebe `setup(unit, def)` e, a cada quadro, `update_visual(delta)`
  (chamado pelo `UnitView`).
  - Eventos: `on_attack_performed()`, `on_projectile_fired(p)` e `on_hit()`.
  - Para projéteis: `muzzle_point(p)` (de onde o disparo PARECE sair) e `projectile_style(p)` (cores).
  - Informa `top_y()` (barra de HP), `pick_rect()` (clique) e `ground_point()` (anel de seleção).
  - Só **lê** a `CombatUnit`; não tem regra de combate.
- `UnitDef.visual_scene` (cena cuja raiz estende `UnitVisual`, ex.: sprites) tem prioridade; senão
  `UnitDef.visual_script` (desenho por código); vazio = `CircleUnitVisual`, o círculo das etapas anteriores.
- **`WarriorVisual`** tem o rig e a animação:
  - O rig é uma cadeia de `Transform2D`: raiz (pés; espelho pela direção; `RIG_SCALE = 0.9`) → quadril →
    pernas / tronco → cabeça, ombros e braços → mão → espada.
  - Cada parte é um conjunto de polígonos no próprio espaço local, com contorno escuro.
  - Ordem de desenho: sombra · capa · braço e ombreira de trás · pernas · saiote/cinto · peitoral
    · elmo (pluma, fenda) · espada · braço, ombreira e mão da frente.
  - Tamanho: ≈ 36 unidades do mundo de altura (≈ 58 px em 1600×896). Os pés ficam 9 abaixo do centro lógico.
- A cada quadro, `update_visual` recalcula uma **pose** (`p_*`: ângulos e deslocamentos) a partir do estado real,
  e `_draw()` só a aplica.
- **Cadáver estático:** todo visual informa `death_elapsed()` e `corpse_settle_time()` (quando queda, quique,
  escurecimento e efeitos terminam); daí em diante o UnitView não o atualiza nem redesenha mais.
- **Geometria cacheada (`DrawCache`):** `_poly`, `_circle` e `_rim_poly` do `CodeDrawnUnitVisual` desenham cada
  forma repetida (mesmos pontos no espaço da peça) como uma malha branca feita uma vez, com a cor pelo
  `modulate`. A geometria é a mesma que o Godot 4.7 gera para polígono, contorno suavizado (3 faixas → 1 malha),
  círculo e arco (portada do motor, float32): pixels idênticos, metade dos draw calls por contorno e nenhuma
  triangulação por quadro. Formas que mudam todo quadro seguem pelo caminho direto (`use_draw_cache = false`
  no Paladino Vivo, cujos polígonos são projetados a cada quadro).

| Estado | Como é lido | O que acontece |
|---|---|---|
| IDLE | sempre, atenuado ao andar | respiração (sobe/desce e leve escala), cabeça e braços oscilam, capa balança |
| MOVING | fase dos passos avança pela **distância real percorrida** | pernas alternam, corpo sobe quando elas cruzam, braços em oposição, cabeça compensa, capa vai para trás; parado = pernas não andam |
| ATTACKING (preparação) | últimos `windup_time` s da **recarga real** (`unit.cooldown`) | braço e espada recuam, tronco inclina para trás |
| golpe | evento `on_attack_performed()`, no **mesmo passo** em que a `CombatSim` executa o golpe (e aplica o dano) | golpe rápido (`strike_time`), avanço do corpo (`lunge`), depois retorno suave (`recover_time`) |
| HIT | evento `on_hit()` | 0,16 s de recuo, achatamento sutil, cabeça para trás e clarão |
| DEAD | `unit.state == DEAD` | queda até o chão; o corpo **permanece deitado** e escurece um pouco |

- A espada tem inércia: segue o ângulo-alvo com suavização exponencial, exceto no golpe.
- A direção vem de `unit.target` (espelhamento instantâneo); sem alvo, a unidade mantém a última direção.

**Guerreiro × Guerreiro Sombra.** `ShadowWarriorVisual extends WarriorVisual`: mesmo rig; a paleta viva é
convertida pela regra `ShadowStyle` (ver "Versões sombra") e os detalhes entram por pontos de extensão
(`_draw_plume`, `_draw_visor`, `_draw_torso_wear`, `_draw_helmet_wear`, `_blade_shape`, `_draw_blade_extra`,
`_draw_fx_front`).

| | Guerreiro | Guerreiro Sombra |
|---|---|---|
| Paleta | metal claro, capa e pluma vermelhas | armadura grafite violeta, capa quase preta com um resto do vermelho |
| Silhueta | contorno escuro | borda roxa só na silhueta externa + contorno interno violeta escuro |
| Detalhes | — | olhos roxos na fenda, fissuras de energia no peitoral e no elmo, pluma → chama espectral, fio da espada aceso, capa rasgada com fio de energia, lâmina lascada |
| Ambiente | sombra preta | névoa roxa no chão, aura suave, poucos fiapos de fumaça (capa, ombros, pés) |
| Postura | ereta | tronco +4°, cabeça +5° (pesada, ameaçadora — não cambaleante) |
| Walk | pernas em oposição perfeita | quase em oposição (0,94π), perna de trás um pouco mais curta |
| Ataque | recua a espada e estoca na horizontal | ergue a espada acima da cabeça e golpeia para baixo; o fio brilha no golpe |
| Queda | de costas, pesada (acelera), um quique | joelhos cedem, desaba para frente; a energia se apaga e o corpo solta fumaça |

**Sincronia do ataque.**
- O golpe visual não é previsto: ele começa quando a `CombatSim` emite `attack_performed`, no mesmo passo em que
  aplica o dano.
- A preparação é lida da recarga real, então termina exatamente quando o golpe chega.
- Nada disso altera dano, recarga nem alcance.

**Quadro de atraso.** A `Battle` processa depois das `Entities` no mesmo quadro, então o visual reage no quadro
seguinte ao passo da simulação (≈ 16 ms).

---

### Sentinela Arcana (viva) e Sentinela Arcana Sombra

Referência: a arte conceitual "Sentinela Arcano Vivo / Sombra". O desenho é novo, feito por código; não é uma
porta 1:1 de `drawArcaneSentinel`.

- **Estrutura.** `CodeDrawnUnitVisual` concentra os utilitários de desenho que o Guerreiro já usava.
  - `SentinelVisual` monta a Sentinela.
  - `SentinelShadowVisual extends SentinelVisual`: mesmo rig; paleta convertida pela regra `ShadowStyle`
    (o selo arcano continua azul — identidade da classe), borda roxa na silhueta, olhos, fissuras de energia na
    saia, aura, névoa no chão, fumaça nas bordas e no capelete; estilo e pontos de extensão próprios
    (barra rasgada, capelete, HIT etéreo, morte).
- **Silhueta** (rig espelhado pela direção, origem nos pés):
  - chapéu largo e pontudo, com a ponta dobrada para trás e uma joia na faixa;
  - manto triangular em camadas: manto de trás, vestido, painel frontal com o símbolo arcano, abas com
    acabamento prateado;
  - capelete com pontas, gola alta e joia em losango no peito;
  - rosto em 3/4 com cabelo escuro e olhos brilhantes;
  - pés quase escondidos.
  - Altura ≈ 40 unidades do mundo; os pés ficam 10 abaixo do centro lógico.
- **Lâminas.** Duas `ArcaneBlade` pairam ladeando a copa do chapéu.
  - São desenhadas **sem espelhar** (a lâmina 0 fica sempre à esquerda, como no HTML) e apontam pela mira
    suavizada (HTML: `swordAim`, 4,5 rad/s).
  - O mesmo desenho é usado pelo `ProjectileView` quando a lâmina parte.
  - O visual lê de `unit.swords` a recarga e a antecipação de cada lâmina.
- **Partida dos projéteis.** O `ProjectileView` desenha a partida a partir de `muzzle_point` (a mão, ou a lâmina
  pairando) e converge para a posição real em 0,12 s (HTML: `sentinelHand`). A simulação não muda.

| Animação | Viva | Sombra |
|---|---|---|
| Idle | respiração, barra e ponta do chapéu balançam, lâminas flutuam (sen(t·2,2 + i·1,7), como no HTML) | + tremor arcano, fumaça roxa nas bordas, lâminas instáveis, olhos pulsando |
| Movimento | desliza (fase pela distância real), inclina 4°, manto e ponta do chapéu ficam para trás, botas aparecem, lâminas atrasam | inclina 6°, mais arrastado e irregular, fumaça arrasta |
| Ataque | preparação pela recarga real (últimos 0,30 s): mão recolhe à frente do corpo com energia azul, joia acende; no `attack_performed` o braço aponta ao alvo, o manto abre e as lâminas dão um tranco; retorno de 0,34 s | energia roxa crepitando na mão, orbe escuro com borda violeta e espinhos, inclinação maior |
| Habilidade | lâmina em antecipação (estado real) recua, vibra, brilha, com elo de energia até a joia e a cabeça erguida; na partida, anel de clarão na âncora, a outra lâmina estremece; em recarga fica um vulto que ganha força e reforma com clarão | lâminas com energia sombria saindo do fio, rastro roxo |
| Hit | 0,2 s: recuo, compressão, clarão, ponta do chapéu treme, lâminas desestabilizam | clarão lilás, o corpo tremula (translúcido) e a fumaça explode |
| Morte | perde a sustentação, a magia se apaga, o manto colapsa com peso, o chapéu cai ao lado; as lâminas caem girando e se desfazem em faíscas; o monte fica no chão | sobe e se agita, colapsa se desfazendo (fica translúcida), fumaça sobe e as lâminas se partem em fragmentos |

### Paladino Vivo — `PaladinLiveVisual` (visual padrão do `sac_paladin`)

É a identidade do Paladino traduzida para a MESMA linguagem do Guerreiro e da Sentinela: pequeno na arena,
formas grandes e simples, contorno escuro, poucas peças e luz e sombra chapadas.

`PaladinLiveVisual extends CodeDrawnUnitVisual`, com as mesmas `RIG_SCALE` (0,9), `FOOT_Y`, contorno, clarão
de dano e escurecimento na morte do `WarriorVisual`. Cena: `scenes/units/paladin_live_visual.tscn`.

**Silhueta** (referência: Paladino olhando para a direita/esquerda, imagem da etapa de refinamento).
- Porte próprio sobre a escala comum: `BODY_SCALE` (1,06 × 1,12) no transform do corpo, `body_width` 1,12.
  O topo do elmo fica ~1,12× a altura do Guerreiro (a auréola passa disso), sem porte de chefe.
- Ombreiras grandes com borda dourada e rebites, tronco largo, pernas grossas com pés afastados e joelhos
  levemente dobrados, botas pesadas.
- Espada erguida na diagonal, para fora, na mão direita (cotovelo dobrado, pronta); nunca aponta para baixo
  no idle nem na caminhada.
- Escudo grande (`shield_scale` 1,18) seguro pelo braço esquerdo, cobrindo boa parte do tronco.

**Partes.** Cada parte tem uma âncora no espaço do corpo (L = esquerda, F = frente, Y = altura):
- tronco (placa marfim, sombra embaixo, gola dourada em V, sol dourado);
- cinto dourado com fivela grande;
- fraldão;
- pernas grossas (coxa, canela com faixa dourada, joelheira dourada, bota pesada com faixa dourada);
- túnica escura entre as pernas;
- tabardo (frente com estrela, e verso);
- ombreiras grandes arredondadas com borda dourada, rebite e rebites na borda;
- braços (marfim, cotovelo dourado, punho dourado, manopla marrom);
- espada (mão DIREITA);
- escudo (braço ESQUERDO);
- elmo arredondado com visor em T e friso dourado;
- auréola com três pontas.

**Fake 2.5D leve.**
- A direção vira um yaw: DOWN 8°, DOWN_RIGHT 20°, RIGHT 30° (3/4 frontal, como na referência), UP_RIGHT 128°, UP 164°.
  As da esquerda são o negativo. O yaw é sempre normalizado em −180°..180°.
- **Vista da esquerda = espelho do desenho, como na referência.** A pose e as âncoras são montadas com |yaw|
  (vista da direita) e o transform do corpo espelha o eixo X — sem escala negativa em nenhum nó. Nos dados a
  espada continua na mão direita (`sword_grip3 == r_hand3`). Na vista da esquerda aparece o VERSO do escudo
  (madeira, alças com rebites e o punho segurando), atrás do braço e do tronco.
  - Direita: espada à esquerda da tela, erguida ↖; face do escudo (sol dourado) à direita.
  - Esquerda: espada à direita da tela, erguida ↗; verso do escudo à esquerda.
- No golpe o corpo gira ~45% do caminho até o perfil, para a lâmina correr de lado sem sumir atrás do escudo.
- O yaw só desloca as âncoras e ordena as partes por profundidade. Assim, nas diagonais:
  - um ombro aparece mais que o outro;
  - uma perna fica à frente;
  - a espada troca de plano.
- De costas somem o visor e o sol; aparecem a traseira do elmo, o verso do escudo (madeira com alças) e o tabardo de trás.
- A face do escudo fica quase sempre voltada para a câmera, para ser lida, e gira só um pouco com o corpo.
- As formas continuam 2D.

**Estado e tempo.** Vêm do `PaladinAnimator`, o mesmo usado pelo rig: ele lê a simulação.
- Caminhada: peso suavizado, ciclo de 1,05 s, mais pesado que o Guerreiro.
- Golpe:
  - começa pela recarga real e segura antes do impacto;
  - o impacto cai no evento real de dano;
  - ele para de andar para atacar;
  - variantes: horizontal no RIGHT, de cima no UP_RIGHT, de baixo no DOWN_RIGHT;
  - cascata quadril → tronco → ombro → braço → espada.
- Habilidade: provocação → guarda pronta → Escudo Sagrado.
- Reações: bloqueio, hit (curto, com clarão) e push (só postura).
- Morte: joelhos cedem, a espada cai, o escudo tomba, ele cai de costas e fica o cadáver, com a espada e o escudo no chão ao lado.

As poses 2D ficam em `neutral()` e nos clipes `_taunt`, `_guard`, `_attack`, `_push` e `_death` (deltas com easing).

**Efeitos, simples e fora do corpo:**
- provocação: anel no raio real (115) e uma onda curta no chão;
- auréola que clareia na provocação e com o escudo ativo;
- contorno dourado sutil no escudo ativo;
- clarão quando o escudo sobe;
- faíscas no bloqueio.

**Inspector:**
- proporções: `body_width`, `shield_scale`, `sword_scale`, `head_scale`;
- movimento: `step_length`, `step_lift`, `breathing`, `turn_speed`;
- cores: marfim, ouro, escuro, aço, couro, madeira, visor, luz sagrada.

**Debug e Sandbox.** F4 mostra direção, yaw, estado, progresso e variante do golpe. A fileira de prévia do Sandbox funciona igual.

**API para testes/ferramentas.** `helmet_top_y()` (topo do elmo, sem auréola) e `screen_anchor(key)` (âncora
em coordenadas locais, já com o espelho e o porte do corpo).

**Custo.** ~0,2 ms de CPU por Paladino por quadro.

### Paladino Vivo 2.5D por código (alternativa, fora de uso)

Rig 2.5D facetado (etapa anterior), mantido para comparação: cena `scenes/units/paladin_rig_visual.tscn`, testada em `paladin_rig_test`. A descrição abaixo continua válida para ele.

100% desenhado por código a partir das três referências oficiais (frente 3/4, frente, 3/4 lateral):
- armadura marfim facetada com frisos dourados grossos;
- elmo fechado com visor em T e auréola com três estrelas;
- ombreiras grandes com rebite dourado;
- tabardo com estrela e túnica escura entre as pernas;
- luvas escuras;
- espada larga na mão DIREITA e escudo de cavaleiro com aro dourado e estrela sagrada no braço ESQUERDO.

Nenhuma imagem é usada.

**Arquitetura** (`scripts/visuals/units/paladin/`):

| Parte | Responsabilidade |
|---|---|
| `PaladinRigVisual` (`UnitVisual`, cena `paladin_rig_visual.tscn`: `Shadow` · `Rig` · `Effects`) | recebe os eventos da `Battle` e o estado real; chama o animador; entrega a pose ao rig; flash de dano; barra de HP, clique, debug |
| `PaladinAnimator` | decide COMO aparece: estado, direção (8), transições com pesos suavizados, sincronia do golpe, reações, morte, molas |
| `PaladinPoseLibrary` | poses-base das direções + clipes (idle, walk, attack ×3, taunt, guarda, block, hit, push, death, cadáver) |
| `PaladinRig` | esqueleto (26 ossos com pivô próprio) → projeção 2.5D → peças ordenadas por profundidade → desenho |
| `PaladinModel` / `PaladinMesh` | peças low-poly (42) presas aos ossos, com materiais e decalques (visor, estrelas, fivela, rebites) |
| `PaladinEffects` | provocação, escudo subindo/ativo, bloqueio — fora do corpo |
| `PaladinRigLook` (`data/visuals/paladin_rig_look.tres`) | todos os ajustes do Inspector |

**Fake 2.5D.**
- O esqueleto vive num espaço 3D do corpo: x = esquerda do personagem, y = cima, z = frente.
- O corpo gira (`yaw`) e uma câmera levemente de cima (`view_tilt`) projeta tudo em 2D.
- Cada peça é uma malha low-poly de faces planas:
  - as faces de costas são descartadas;
  - cada face recebe um degrau de luz, com a luz fixa em relação à câmera; as facetas mudam quando ele gira, e isso dá o volume;
  - cada peça ganha contorno escuro (o casco convexo dela).
- As peças são **reordenadas por profundidade a cada quadro**, com um viés ao longo da frente do osso.
  - Por isso não é uma árvore de `Polygon2D` com `z_index` fixo: de costas o escudo passa para trás, de lado o braço da espada passa para a frente, e assim por diante.
- A auréola é um anel meio voltado para a câmera.

**Regra do equipamento.**
- O rig é destro por construção: a espada pende da mão direita e o escudo do braço esquerdo (`PaladinModel.SWORD_CHAIN` / `SHIELD_CHAIN`).
- As direções da esquerda são **giros de verdade**, não espelho: nenhuma direção pode trocar a mão.
- Na morte a espada e o escudo se soltam (os ossos `sword`/`shield` passam a ter transformação própria) e caem ao lado do corpo.

**Direções.** São 8, quantizadas com histerese a partir do vetor real:
- andando: o deslocamento;
- atacando: o alvo;
- com o escudo: a direção travada pela simulação.

Cada uma é uma pose-base (`PaladinPoseLibrary.DIRS`):

| Direção | yaw | Leitura | Ataque |
|---|---|---|---|
| DOWN | 16° (pende para o último lado) | frente 3/4, peito e visor | `rising` (de baixo) |
| DOWN_RIGHT | 40° | frente-lado | `rising` |
| RIGHT | 62° | 3/4 lateral, cabeça e tronco para a direita | `flat` (horizontal) |
| UP_RIGHT | 122° | costas 3/4, olhando para a diagonal de cima | `overhead` (de cima) |
| UP | 160° | costas: traseira do elmo, das ombreiras e do tabardo, escudo por trás | `overhead` |
| LEFT / UP_LEFT / DOWN_LEFT | −yaw | o mesmo giro para o outro lado (espada continua na direita) | idem |

A pose-base ajusta só a apresentação:
- a face do escudo vira para a câmera quando ele está do lado de longe, e para a frente quando está do lado de perto (deixa o peito aparecer);
- a lâmina de repouso aponta para fora.

O corpo gira até a nova direção com `turn_speed` (sem teleporte) e a pose-base se mistura suavemente.

**Estados.** Todos são lidos da simulação; o visual não comanda nada.

| Estado | Gatilho real | Apresentação | Tempo |
|---|---|---|---|
| IDLE | parado | muralha viva: respiração lenta, peso passando de um pé para o outro, joelhos levemente dobrados | ciclo 2,2 s |
| WALK | deslocamento real | passos curtos e pesados, joelhos dobram na passada, quadril gira pouco, espada com inércia, tabardo com as pernas; o ritmo segue a velocidade real | ciclo 0,95 s a 44 |
| ATTACK | recarga real + `attack_performed` | antecipação (peso recua, espada para trás) → aceleração em cascata (quadril → tronco → ombro → braço → espada) → **impacto no quadro do dano** → acompanhamento → recuperação; três variantes por direção | 0,78 s |
| HIT | `on_hit` | recuo curto de corpo pesado, ombros comprimem, joelhos absorvem; aditivo (volta ao estado anterior) | 0,22 s |
| PUSH | deslocamento real que a caminhada não explica (ou `on_pushed`) | centro de gravidade quebra na direção do empurrão, pé de trás busca apoio, escudo e espada atrasam; sem deslocamento extra | 0,45 s |
| TAUNT | `paladin_taunted` | firma os pés, baixa o centro, recua o escudo e o avança, peito aberto, encara; termina na guarda pronta | 0,8 s |
| GUARD_READY | `paladin.is_preparing()` | escudo dominante à frente durante a espera de 1 s | — |
| SHIELD_ACTIVE | `paladin.is_shielded()` | postura fechada, centro baixo, corpo atrás do escudo, espada pronta, virado para a direção travada | 1,5 s |
| BLOCK | `paladin_shield_blocked` | escudo recua alguns graus, braço comprime, tronco absorve, pés firmes (o golpe no escudo não vira HIT) | 0,24 s |
| DEATH → CORPSE | `unit.state == DEAD` | golpe fatal → postura quebra → joelhos cedem (apoiados no chão) → espada escapa da mão direita → escudo sai do braço esquerdo → queda de costas → acomodação → cadáver deitado de costas, espada e escudo ao lado | 1,35 s |

**Transições.** Nada troca de uma vez:
- a locomoção tem peso `move_w`, que acelera e desacelera;
- ataque e defesa têm pesos próprios, que entram e saem em ~0,1–0,3 s;
- as reações (hit, block, push) são deltas somados que voltam a zero.

Ao decidir atacar, a caminhada sai: ele para de andar, e a simulação já para a unidade no alcance.

Os keyframes usam easing: `out` na antecipação, `in` na aceleração e `back` no acompanhamento. O golpe é escalonado por partes.

Molas criticamente amortecidas dão atraso à espada, ao escudo, ao tabardo e à auréola. O corpo é pesado, então há pouco balanço.

**Sincronia do golpe.** Segue a mesma regra dos outros visuais:
- a antecipação começa quando faltam ≤ 0,34 s para o dano previsto (a recarga real no alcance, ou distância ÷ velocidade chegando);
- a pose segura antes do impacto até o `attack_performed`;
- o impacto aparece no mesmo passo do dano. O timing é da simulação.

**Efeitos** (`PaladinEffects`, com mistura aditiva, fora do rig):
- provocação: anel no raio real (115), onda curta no chão e brilho na auréola;
- clarão quando o escudo sobe;
- escudo ativo: brilho dourado sutil no escudo; a estrela do escudo e os frisos dourados clareiam (só cor);
- faíscas no bloqueio;
- flash de dano (modulação).

**Inspector** (`PaladinRigLook`):
- Corpo: `scale` (0,5 → ~48 unidades até o elmo), `body_width`, `body_height`, `head_scale`, `shoulder_width`,
  `view_tilt`, `outline_width`, `facet_steps`.
- Escudo: `shield_scale`, `shield_offset`, `shield_angle`. Espada: `sword_scale`, `sword_offset`, `sword_rest_angle`.
- Movimento: `walk_cycle`, `walk_reference_speed`, `stride`, `vertical_bounce`, `walk_amplitude`,
  `secondary_motion`, `turn_speed`. Idle: `breathing`, `idle_cycle`.
- Ataque: `windup`, `body_rotation`, `sword_arc`, `follow_through`. Tecido: `cloth_inertia`, `cloth_amplitude`.
- Efeitos: `glow`, `block_flash`, `taunt_intensity`, `show_taunt_ring`, `hit_flash`.
- Cores: contorno + 3 tons (claro, médio, sombra) por material (marfim, ouro, tecido escuro, couro, aço,
  punho, madeira, tabardo, luvas) e a luz sagrada.
- Na cena: `foot_y` (pés abaixo do centro lógico).

**Debug.** Com F4 (debug de combate), o Paladino mostra:
- direção e yaw;
- estado da apresentação e progresso;
- direção do alvo e variante do golpe.

**Sandbox.** Com um Paladino Vivo selecionado aparece a fileira "Prévia (só visual)": Idle, Andar nas 8 direções, Atacar → ↗ ↘, Hit, Push, Provocar, Escudo, Bloqueio, Morte.
- Só funciona na preparação (a unidade não se move nem luta).
- Iniciar desliga a prévia; Reiniciar e Limpar recriam o visual.

**Custo.** ~1–2 ms de CPU por Paladino por quadro (animação + montagem do desenho, medido no teste). No ambiente de captura (Xvfb, GL por software), 16 Paladinos custam o mesmo que 16 Paladinos Sombra por código.

### Paladino Vivo por sprite sheets (alternativa, fora de uso)

Mantido no projeto para comparação: cena `scenes/units/paladin_sprite_visual.tscn`, assets em `assets/units/paladin/`.
- Para usar, basta apontar `UnitDef.visual_scene` para a cena.
- O teste `paladin_sprite_test` continua cobrindo.

Arte aprovada: cinco sheets em `assets/units/paladin/source/` (`paladin_idle.png`, `paladin_walk.png`,
`paladin_attack.png`, `paladin_defend.png`, `paladin_death.png`; 2000 × 667, fundo **já transparente** com
borda suave — nada de fundo preto para remover). A pasta tem `.gdignore`: o Godot não importa as originais.
`tools/sprites/slice_paladin_sheets.py` gera `paladin_atlas.png`, `paladin_frames.tres` e `paladin_frames.json`:
- **cortes** entre frames medidos na imagem: reta vertical ou polilinha (no ataque os arcos atravessam a
  coluna do vizinho; o corte entre o 4º e o 5º frame segue o contorno da capa e o fim do arco some em 16 px
  em vez de terminar numa reta — `feather`); pedaços opacos pequenos do lado errado vão para o frame cuja
  massa está mais perto; o brilho fraco segue o pixel opaco mais próximo;
- **escala por sheet**: as sheets vieram em tamanhos diferentes (defesa ~20% maior, caminhada ~13% maior,
  ataque ~5% e morte ~8% menores que o idle). `scale` iguala tudo ao idle — medido casando o elmo do idle em
  várias escalas com cada sheet (`cv2.matchTemplate`);
- **pivô** = pés no chão. y = última linha com ≥ 30 px sólidos (ponta de espada não conta); x = registro do
  frame contra o frame 0 da sheet, pela sobreposição de uma faixa do corpo — `feet` (idle, ataque, defesa:
  faixa das pernas, os pés não se mexem), `torso` (walk: o tronco não balança, as pernas alternam), `chain`
  (morte: corpo inteiro contra o frame anterior, mesmo chão da sheet);
- redução ~2× (`INTER_AREA` com alfa pré-multiplicado: sem franja escura) para **células de 246 × 186 com o
  pivô em (123, 161)**, pivô no meio da largura (espelhar não desloca); atlas 8 × 5 com mipmaps. Cada frame
  de origem vira uma célula; as animações só apontam para as células (defend, defend_block e taunt
  reaproveitam frames da sheet de defesa).

| Animação | Frames (sheet) | FPS | Loop | Uso (estado real) |
|---|---|---|---|---|
| `idle` | idle 0–7 | 7 | sim | parado (a auréola pulsa nos frames ímpares) |
| `walk` | walk 0–7 | 10 × (velocidade real ÷ 44) | sim | andando |
| `attack` | attack 0–7 | 14 | não | golpe; **frame 4 = impacto** (clarão), mostrado no evento real de dano |
| `defend` | defend 0–3 (linha de cima) | 12 | não | espera do escudo = frame 0 parado; escudo sobe = 1–3 (giro, clarão da bênção) |
| `defend_hold` | defend 4–7 (linha de baixo) | 6 | sim | guarda firme enquanto o escudo está ativo |
| `defend_block` | defend 2–3 | 12 | não | o escudo absorve um golpe (evento `block`); volta ao `defend_hold` |
| `taunt` | defend 1, 0 | 6 | não | evento da provocação: giro do escudo e volta à guarda (o anel mostra o raio real 115) |
| `death` | death 0–7 | 8 | não (para no último) | morto; o último frame é o corpo no campo |

Não há sheet de **hit**: o dano pisca a arte e dá um recuo curto (2,5 px × escala), sem trocar a animação.

`PaladinSpriteVisual` (cena `scenes/units/paladin_sprite_visual.tscn`: `Shadow` · `Sprite` · `Effects`):
- só lê o estado: morto → death; provocação → taunt; golpe → attack; espera do escudo → defend (frame 0);
  escudo ativo → defend → defend_hold; bloqueio → defend_block; andando → walk; resto → idle. A animação só
  troca quando o estado muda (não reinicia a cada quadro);
- **sincronia do golpe:** a preparação começa quando faltam ≤ 4 frames (0,29 s) para o dano previsto — a
  recarga real no alcance, ou a distância que falta ÷ velocidade ao chegar — e segura o frame anterior ao
  impacto; o frame de impacto entra no `attack_performed` (o mesmo passo do dano). O timing é da lógica;
- a arte olha para a direita; o inimigo usa `flip_h`;
- efeitos da habilidade compartilhados com o visual por código (`PaladinFx`): barreira sagrada, anel da
  provocação (raio real 115) e anel do escudo;
- Inspector: `sprite_scale` (0,37 → ~47 unidades até a auréola; Guerreiro ~35), `foot_y`, `frame_pivot`,
  `frame_size`, `art_height`/`art_body_width` (barra de HP e clique), `attack_impact_frame`,
  `walk_reference_speed`, `effects_glow`, `show_taunt_ring`. O teste confere pivô, célula e frame de impacto
  contra o `paladin_frames.json`;
- filtragem: atlas com mipmaps e sprite em `LINEAR_WITH_MIPMAPS` — a arte (~128 px no atlas) aparece a
  ~47 unidades (~2,7× menor): sem serrilhado.
- O Paladino Sombra segue no visual por código (`ShadowPaladinVisual`).
- Para trocar a arte: substituir as sheets em `source/`, conferir os cortes/escala no topo do script e rodar
  `python3 tools/sprites/slice_paladin_sheets.py` (se a célula mudar, atualizar `frame_pivot`/`frame_size` na
  cena — o teste avisa).

### Paladino Sombra (visual por código; o `PaladinVisual` vivo por código virou só a base dele)

Referência: a arte conceitual "Paladino Vivo / Paladino Sombra" (o desenho é novo, por código); tempos e
intenção de pose do rig do HTML (`drawPaladinArt`, perfil `heavyMelee`, `paladinCue`, `drawPaladinBarrier`,
cadáver com escudo e espada soltos).

- **Estrutura.** `PaladinVisual extends CodeDrawnUnitVisual`; `ShadowPaladinVisual extends PaladinVisual`
  (mesmo rig; regra `ShadowStyle`). Parâmetros no Inspector: `PaladinLook` (`data/visuals/paladin_look.tres`,
  via `UnitDef.visual_look`): `scale`, `shield_offset`, `sword_offset`, cores, `glow`, `show_taunt_ring`,
  `secondary_speed`. A intensidade da sombra fica no `ShadowStyle`.
- **Rig** (origem nos pés, espelhado pela direção): raiz → quadril → pernas (joelho dobra com `p_crouch`) /
  tronco → cabeça (auréola atrás do elmo) · ombro de trás → braço → espada · ombro da frente → braço → escudo.
  Ordem: sombra · capa · braço da espada e ombreira de trás · pernas · tabardo partido e cinto · peitoral ·
  elmo · espada · braço do escudo, escudo e ombreira da frente · efeitos. No golpe a espada passa **na frente**
  do escudo.
- **Silhueta:** ~47 unidades até a estrela da auréola (Guerreiro ~35), área clicável 26 × 43 (Guerreiro
  20 × 40): maior e mais largo pelos ombros, escudo e armadura — sem virar chefe.

| Estado | Como é lido | Paladino |
|---|---|---|
| Idle | sempre | firme: respiração mínima (0,25), capa reage de leve, escudo sustentado, espada em pé, pronta |
| Walk | fase pela distância real | passada curta e pesada (13 por ciclo, 18°), corpo sobe pouco, tronco e ombros juntos, escudo quase parado, espada com inércia |
| Preparação | últimos 0,20 s da recarga real; e ao chegar a < 2r do alcance com a recarga pronta (HTML) | espada recua acima da cabeça, tronco inclina para trás |
| Golpe | `attack_performed` (mesmo passo do dano) | desce em 0,12 s com o corpo afundando (peso), avanço, rastro no arco da espada; retorno à guarda até 0,46 s |
| Provocação | `paladin_taunted` | batida do escudo à frente, peito ergue, anel no raio real de 115 |
| Espera do escudo | `paladin.delay` (estado real) | ergue a guarda aos poucos |
| Escudo ativo | `paladin.shield_t` | guarda firme (joelhos dobram, inclina, escudo à frente), barreira sagrada à frente na direção travada (HTML: entra 0,2 s, some 0,16 s) |
| Bloqueio | `paladin_shield_blocked` (dano realmente reduzido) | 0,28 s: o braço cede, recuo curto, clarão no escudo e na barreira |
| Hit | `on_hit` | 0,25 s: recuo pequeno, cabeça recua, clarão curto |
| Morte | `unit.state == DEAD` | joelhos cedem, a espada escapa da mão e cai solta ao lado, o escudo pesa e cai ao lado do corpo, tomba de costas (0,72 s, acelera), quica e fica no chão |

| | Paladino | Paladino Sombra |
|---|---|---|
| Armadura | marfim, sombra na metade de trás | grafite violeta (`convert`) |
| Dourado | auréola, crista, filetes, guarda e pomo, borda do escudo | **preservado** (só um pouco mais escuro) |
| Sol (escudo/tabardo) | dourado | energia roxa pulsando |
| Tecidos | tabardo e capa claros | tabardo desbotado e rasgado; capa quase preta, rasgada, com fio roxo |
| Detalhes | — | olhos roxos no visor, fissuras roxas no peitoral e no escudo, chama roxa no fio da espada |
| Ambiente | sombra | borda roxa na silhueta, aura, névoa no chão, pouca fumaça; na morte a energia se apaga e o corpo solta fumaça |
| Efeitos | rastro, barreira e anéis dourados | roxos com resto do dourado |

### Protótipo: sprite sheet 3/4 do Paladino Vivo (frame a frame)

Validação do estilo 2.5D/3/4 em animação por frames. **Não está ligado ao jogo** (o Paladino em combate continua
o `PaladinVisual`); só a cena `scenes/prototypes/paladin_sprite_pilot.tscn` usa a sheet.
- Gerada por `tools/sprites/render_paladin_pilot.gd`: o personagem é pintado por código num rig 3/4 (ombro da
  espada perto da câmera, escudo à frente com espessura, auréola atrás do elmo, sombreado de volume com luz fixa
  do alto à esquerda), com pés por IK plantados no chão e keyframes feitos à mão; cada pose é renderizada numa
  `SubViewport` transparente em supersampling 3× e reduzida.
- Contrato (`paladin_live_pilot.json`): frames 256 × 256, fundo transparente, **pivô = (128, 240)** (centro entre
  os pés, no chão) em todos os frames; linhas idle (6, 8 fps, loop) · walk (8, 14 fps, loop) · attack (8, 12 fps).
  Sombra num PNG separado com o mesmo pivô. `paladin_live_pilot_frames.tres` = `SpriteFrames` (AtlasTexture).
- Escala de jogo: o personagem tem ~152 px no frame → `47 / 152 ≈ 0,31` (mesma altura do Paladino atual).
  Walk no lugar: o pé de apoio recua 24 px em 4 frames; a 14 fps isso dá 84 px/s no sprite, então
  `speed_scale = velocidade / (84 × escala)` faz os pés não deslizarem.
- Inimigo = a mesma sheet com `flip_h` (o pivô fica no centro do frame em x).

### Versões sombra (unidades revividas pelo necromante)

Regra do projeto: **versão viva = aparência normal da classe; versão sombra (`u_*`) = a mesma classe convertida
em "sombra necromântica"**. A classe continua legível pela silhueta e pelos elementos-chave; a sombra se
reconhece de longe pelo corpo escuro com borda roxa e pelos olhos acesos.

- **`ShadowStyle`** (`Resource`, `data/visuals/shadow_style.tres`, editável no Inspector):
  - `convert(cor, keep)`: leva uma cor da versão viva para a sombra — corpo entre `body_dark` e `body_light`
    (grafite violeta), com `keep_hue` do tom original; `keep` > 0 preserva acentos da classe (ouro de paladino,
    runas, símbolos sagrados) mais escuros, mas com o matiz;
  - `edge` (contorno interno), `rim`/`rim_width` (borda roxa só na silhueta externa);
  - `energy`, `energy_core`, `eye`, `smoke` e as intensidades `aura`, `smoke_amount`, `cracks`, `pulse_speed`.
  - `UnitDef.shadow_style` pode apontar outro estilo (ex.: sombra de elite); vazio = o padrão.
- **`ShadowFX`**: `aura`, `ground_mist`, `smoke`, `crack`, `eye`, `pulse` — desenho determinístico pelo tempo
  (sem partículas nem nós), barato com dezenas de unidades.
- **`CodeDrawnUnitVisual`**: a subclasse marca `shadow = true` em `_init`; o `setup()` resolve o estilo e chama
  `_apply_shadow_style(style)`, onde a unidade converte a **sua** paleta viva. `_draw_with_rim(corpo)` desenha
  o corpo duas vezes: primeiro engordado em roxo (`_rim_pass`), depois normal — só a silhueta externa fica roxa
  (contornar cada peça em roxo deixava a unidade inteira roxa no tamanho real).
- **Nova unidade sombra:** herde o visual vivo, `shadow = true` em `_init`, converta a paleta em
  `_apply_shadow_style`, envolva o corpo com `_draw_with_rim` e use `ShadowFX` nos pontos da classe (olhos,
  fissuras, fumaça). Na morte, `_life()` → 0 apaga a energia.

## Fundo da arena (`ArenaBackdrop`) — cena de nós editáveis

`scenes/arena/arena_backdrop.tscn` é uma **árvore de nós** (cerca de 190), em que cada parte visual é um nó que se
seleciona, move e ajusta no editor.
- O fundo distante é 100% Godot, sem nada da arte antiga: céu, lua, nuvens, montanhas, névoa, castelo e ruínas.
- Do `novocenario.png` vêm só o chão e a arquitetura lateral, extraídos por `build_layers.py`:
  `arena.png`, `architecture_left/right.png`, estandartes e velas.

```
ArenaBackdrop (arena_backdrop.gd)            profundidade de parallax (metadado parallax_depth)
├─ Sky (Node2D)          └─ Gradient (ColorRect + sky.gdshader)                        0
├─ Moon (BackdropMoon)   └─ Disc (ColorRect + moon.gdshader) — disco + halo            0,02
├─ FarClouds (BackdropDrift) └─ Cloud1…7 (BackdropCloud)                               0,05
├─ MidClouds (BackdropDrift) └─ Cloud1…6                                               0,09
├─ NearClouds (BackdropDrift) └─ Cloud1…4                                              0,14
├─ FarMountains  └─ Peak1…10 (Polygon2D, cor por vértice) └─ Rim (Line2D, luz da lua)  0,2
├─ FarFog        └─ Band (BackdropFog: ColorRect + fog.gdshader)                        0,25
├─ MidMountains  └─ Peak1…11                                                            0,32
├─ MidFog        └─ Band                                                                0,38
├─ CastleBack    ├─ MainCastle └─ Cliff, Wall, Tower1…9, Bridge (Polygon2D) └─ Rim, Finial 0,45
│                └─ EastKeep   └─ Hill, Wall, Tower1…3, Bridge
├─ CastleLights (CastleLights) └─ Window1…24 (CastleWindow)                             0,45
├─ Ruins         └─ Aqueduct, BrokenTower1…3 (Polygon2D) └─ Rubble                     0,5
├─ NearMountains └─ Peak1…8                                                             0,58
├─ NearFog       └─ Band                                                                0,68
├─ LeftArchitecture / RightArchitecture (Sprite2D)                                      0,95
├─ LeftBanner / RightBanner (BannerSway: Sprite2D + banner_sway.gdshader)               0,95
├─ LeftCandles / RightCandles └─ Glow (CandleGlow) + Flame1…n (CandleFlame)             0,95
└─ ArenaFloor (Sprite2D) — chão, desenho roxo e muro                                    1
```

**O que cada nó faz** (`scripts/visuals/backdrop/nodes/`)

| Nó | Editável no Inspector | No jogo |
|---|---|---|
| `BackdropMoon` (@tool) | posição, `radius`, pulsação, halo | brilho pulsa ±3,5% em 6,5 s; oscila < 1 px |
| `BackdropCloud` (@tool, desenhada por código e visível no editor) | `length`, `height`, `lumps`, `seed`, 4 cores | corpo, faixa iluminada no topo e barriga escura; borda prateada perto da lua |
| `BackdropDrift` (grupo de nuvens) | `speed`, faixa de volta `wrap_left/right`, `bob` | desliza os filhos → direita; reaparecem do outro lado fora da tela; oscilação vertical de 1,5 px |
| `BackdropFog` (@tool) | posição/tamanho, `speed` (negativo = ←), `opacity`, `breath`; forma e cor no material | desliza e "respira" (opacidade ±18%, ~11 s) |
| `Polygon2D` de montanha, torre, penhasco e ponte | vértices (ferramenta de polígono), cores por vértice, posição | estático (a névoa passa na frente) |
| `Line2D` `Rim` | pontos, largura, gradiente | luz de borda da lua |
| `CastleLights` + `CastleWindow` (@tool) | posição de cada janela, tamanho, cores, `can_light`; `lit_share`, `speed`, `intensity` no grupo | cada janela acende e apaga devagar no seu ritmo; em média de 4 a 7 acesas de 24 |
| `BannerSway` | `amplitude`, `speed`, `phase`, `top_px` | vento suave que desce pelo tecido (cada altura repete o movimento de cima com atraso), rajadas lentas, ondulação pequena até a ponta, a barra sobe um pouco quando o pano se afasta |
| `CandleFlame` (@tool) + `CandleGlow` | posição, `flame_height`, cores, força | flicker sutil: altura ±7%, largura ±4%, brilho ±8% (chama e reflexos ±12%), lento — não pisca |
| `BackdropShaderRect` (@tool) | posição/tamanho | mantém `rect_origin/rect_size` do shader iguais ao nó |

No editor nada se move (as animações só rodam no jogo). As nuvens, a lua, as janelas e as chamas aparecem
desenhadas.

**Coerência da composição** (garantida por `backdrop_test`):
- o castelo principal (`MainCastle`: rochedo, muralha, torres e ponte) fica 18 px mais baixo (`position` do nó);
  o rochedo tem um platô mais largo que as muralhas, e muralhas e torres descem alguns px para dentro da rocha —
  a base de toda torre externa fica **dentro** do polígono do rochedo (idem `EastKeep`/`Hill`);
- as pontes presas ao castelo são filhas do próprio castelo (mesmo parallax) e os pilares descem até o chão
  (y 372, atrás do chão da arena); o aqueduto e os pilares partidos também, com entulho (`Rubble`) no pé e duas
  colinas baixas (`NearMountains/Peak7…8`) na frente — nada flutua.

**`ArenaBackdrop`** (script da raiz) só coordena:
- `animated` e `master_intensity` (repassados a todos os nós do grupo `backdrop_animated`);
- a posição da lua para as nuvens;
- o parallax: cada filho com `parallax_depth` desloca `view_offset × (1 − profundidade)` a partir da posição do
  editor. `parallax_preview` faz um vaivém só para visualizar.

**Como editar**
- **Mover ou redimensionar:** selecione o nó na árvore e arraste.
  - Montanhas, torres e pontes são `Polygon2D`: a ferramenta de polígono edita os vértices.
  - O **nó fica na base da peça**, então arrastar move o pico ou a torre inteira.
- **Nova nuvem:** duplique uma `Cloud` (Ctrl+D) dentro do grupo e mude `seed`, `length` e `height`.
- **Nova janela ou chama:** duplique `WindowN` ou `FlameN` e posicione.
- **Nova montanha:** duplique um `PeakN`. A luz de borda (`Rim`) é gerada para a silhueta original e pode ser
  editada ou apagada à mão.
- **Velocidades e intensidades:** ficam no nó animado (ou no grupo, para nuvens e janelas).
- **Recomeçar do zero:** `tools/arena_backdrop/generate_backdrop_scene.gd` gera a cena de novo, **sobrescrevendo
  as edições**.

## Dados de unidade (`UnitDef` + `UnitCatalog`)

- `UnitDef` (`Resource`) define uma unidade: um `.tres` por unidade em `res://data/units/`.
  - Campos: `id` (a chave do HTML), `display_name`, `side` (em que lista aparece);
  - combate: `max_hp`, `damage`, `attack_range`, `attack_interval`, `move_speed`, `radius`,
    `projectile_kind` (vazio = corpo a corpo) e `abilities`;
  - visual: `visual_script` (um `UnitVisual`; vazio = círculo), `body_color` e `trim_color` (cores do círculo).
- `to_stats(overrides)` gera o dicionário que `CombatUnit` consome. A `CombatSim` **não conhece** `UnitDef`.
- `UnitCatalog` lê a pasta (`all()`, `for_side()`, `get_def(id)`). As listas do Sandbox vêm daqui: para
  adicionar uma unidade basta criar um `.tres`, sem mexer em código.

| `.tres` | Nome | Lado | HP | Dano | Alcance | cd | Vel. | r |
|---|---|---|---|---|---|---|---|---|
| `u_warrior` | Guerreiro Sombra | PLAYER | 74 | 10 | 32 | 1,0 | 56 | 12 |
| `warrior` | Guerreiro | ENEMY | 70 | 9 | 32 | 1,0 | 56 | 12 |
| `arc_battlemage` | Sentinela Arcana | ENEMY | 43 | 18 | 150 | 1,25 | 54 | 13 |
| `u_arc_battlemage` | Sentinela Arcana Sombra | PLAYER | 40 | 18 | 150 | 1,25 | 54 | 13 |
| `sac_paladin` | Paladino | ENEMY | 120 | 13 | 34 | 1,2 | 44 | 14 |
| `u_sac_paladin` | Paladino Sombra | PLAYER | 113 | 13 | 34 | 1,2 | 44 | 14 |

As duas Sentinelas têm `projectile_kind = "orb"` e `abilities = ["arcane_swords"]`. A Sombra é a versão
morta-viva do HTML (`registerFactionUnits`: mesmos stats, HP × 0,94).
Os dois Paladinos têm `abilities = ["paladin_taunt_shield"]` (HTML: `FACTION_UNITS.sac_paladin`; a Sombra é o
`u_sac_paladin` de `registerFactionUnits`, HP round(120 × 0,94) = 113) e `visual_look = paladin_look.tres`.

---

## Sandbox

Fluxo: **Menu → Sandbox → Arena + SandboxUI + combate real.** O menu Jogar só mostra "em construção".

**Responsabilidades**

| Parte | Faz | Não faz |
|---|---|---|
| `MainMenu` | mostra botões, emite sinais | trocar de tela |
| `Main` | troca de tela, atalhos globais | nada de combate |
| `SandboxController` | guarda a **montagem**, chama `Battle`, seleção, liga a UI | regras de combate |
| `SandboxUI` | painéis, listas, botões, painel da unidade; só emite sinais | conhecer `Battle`/`CombatSim` |
| `Battle` / `CombatSim` / `CombatUnit` / `UnitView` | o combate real (os mesmos do jogo) | nada de Sandbox |

**Montagem.** Uma lista de `Placement` (`def`, `team`, `position`, `overrides`, e a `unit` viva atual).
- **Reiniciar** faz `battle.clear()` e recria cada `Placement` com `battle.spawn(...)`: HP cheio, posição
  original, mesmas edições e mesma semente.
- **Limpar** esvazia a montagem.

**Modos do controller:** `PREP` → (Iniciar) → `RUNNING` → (fim) → `FINISHED` → (Reiniciar) → `PREP`.
- Criar tropas e editar atributos: só em `PREP`.
- Iniciar: só em `PREP`, e com pelo menos 1 aliado e 1 inimigo.
- Reiniciar e Limpar: em qualquer modo, desde que haja tropas.

**Posições automáticas.** Colunas a partir da divisa, a 100 de x=500 e com passo de 45; linhas na ordem
y = 380, 330, 430, 280, 480.
- Aliados crescem para a esquerda e inimigos para a direita.
- Limite de 8 colunas × 5 linhas = 40 por lado.

**Seleção.** Um clique que nenhum painel consumiu chega a `SandboxController._unhandled_input`.
- A posição do evento vira coordenada do mundo (`arena.make_input_local`), e `battle.unit_at()` escolhe a
  unidade (vivas têm prioridade).
- Um clique no vazio desfaz a seleção. A seleção segue o `Placement` e sobrevive a Reiniciar e a edições.

**Prévia só visual.** Hoje só o Paladino Vivo 2.5D tem `preview(kind, dir)` no visual.
- Quando a tropa selecionada tem esse método, a `SandboxUI` mostra a fileira `PreviewRow` e emite `preview_requested`.
- O controller só repassa em `PREP` e desliga as prévias ao Iniciar.
- Nada da `CombatUnit` muda.

**Painel da unidade selecionada.**
- Mostra nome, lado, estado, HP atual/máx., dano, alcance, intervalo, velocidade e alvo, atualizado a cada quadro.
- Tem 5 campos editáveis por instância, só em `PREP`: HP máx., dano, alcance, intervalo e velocidade.
  - A edição grava em `Placement.overrides` e recria a montagem, então vale desde o início da luta.
  - A `UnitDef` não muda.

**Layout** (`scenes/sandbox/sandbox_ui.tscn`, tudo em Controls editáveis). Há uma faixa inferior ancorada ao
rodapé (`anchor_top = 0,78`, 22% da altura), e o resto da tela fica livre para a arena e o fundo:

```
SandboxUI (CanvasLayer 50)
└─ Root (Control, tela toda, ignora o mouse; tema sandbox_theme.tres)
   └─ %BottomBar (PanelContainer, variação de tema "BottomBar")
      └─ Columns (HBoxContainer)
         ├─ AlliesPanel   └─ VBox: %AlliesHeader, Hint, Scroll/%AlliesList  (botões gerados do catálogo)
         ├─ ControlsPanel └─ VBox: Buttons (Grid 2×2: %StartButton %ResetButton %ClearButton %MenuButton), %StatusLabel
         ├─ SelectedPanel └─ VBox: %SelectedTitle, %SelectedInfo, %EditRow (HpSpin, DmgSpin, RangeSpin, CdSpin, SpeedSpin)
         └─ EnemiesPanel  └─ VBox: %EnemiesHeader, Hint, Scroll/%EnemiesList
```

- Os nós com `%` são nomes únicos: o script os encontra pelo nome, então dá para **mover para outro pai** sem
  mudar código.
- Largura das colunas: `size_flags_stretch_ratio` (1 · 1,3 · 2 · 1).
- Altura da faixa: `anchor_top` da `BottomBar`. A Arena se reenquadra sozinha pelo sinal `layout_changed`.
- Campos de edição: cada `SpinBox` de `EditRow` tem o metadado `stat_key` (hp, dmg, range, cd, speed); mínimo,
  máximo, passo e prefixo ficam no Inspector.
- Cores, bordas e fonte: `sandbox_theme.tres`.
- Gerados por código: só os botões das listas (um por `UnitDef`).

**Painel de desempenho (F6, ferramenta de debug).** `PerfOverlay` (`scripts/debug/perf_overlay.gd`), filho do
Sandbox, `CanvasLayer` 60 (acima da UI do Sandbox, abaixo dos avisos). Painel pequeno no **topo esquerdo**, fundo
semitransparente, `mouse_filter = IGNORE` (não bloqueia cliques). Começa **desligado**; F6 liga/desliga e o `Main`
lembra o estado. Atualiza o texto 5×/s (janela de 0,2 s). Desligado, não processa nem mede nada.

| linha | de onde vem |
|---|---|
| FPS · Quadro (pior) | média e pior quadro da janela de 0,2 s (FPS = quadros / tempo da janela) |
| Aliados · Inimigos | `sim.alive_count(time)` |
| Vivos · Cadáveres · Total | vivos, `sim.units.size() − vivos`, `sim.units.size()` |
| Projéteis | `sim.projectiles.size()` |
| Draw calls · Objetos · Nós | monitores oficiais `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `RENDER_TOTAL_OBJECTS_IN_FRAME`, `OBJECT_NODE_COUNT`; **N/A** sem render (headless) |
| Sim | `Battle.sim_usec_last_frame` (tempo dos passos da simulação no quadro) e passos por quadro; "parada" fora do combate |
| Alvo/s | taxa dos contadores já existentes da CombatSim: buscas (`stat_target_queries`), varreduras, candidatos |
| Visual (update) | soma do `UnitView._process` de todas as unidades, medida só com o painel ligado (`UnitView.profiling`) |

- Só **lê**: não muda regra, IA, stats, alvo nem desenho. O teste confirma a mesma luta com o painel ligado e
  desligado.
- Não mede o `_draw` nem o render (isso é do `tools/bench`); o tempo de alvo aparece como taxa, não em ms (medir
  cada busca custaria mais que a própria busca).

---

## Testes headless

```
godot --headless --import                       # uma vez, gera o cache de classes (.godot/)
godot --headless -s res://tests/combat_test.gd  # regras de combate + catálogo
godot --headless -s res://tests/sandbox_test.gd # ponta a ponta na cena real (menu → Sandbox → menu)
godot --headless -s res://tests/visual_test.gd  # poses/animações dos visuais por código
godot --headless -s res://tests/sentinel_test.gd  # Sentinela: mecânica do HTML + visual
godot --headless -s res://tests/backdrop_test.gd  # fundo: camadas, profundidade, movimento, janelas, parallax, nada flutua
godot --headless -s res://tests/menu_click_test.gd  # cliques reais de mouse no menu: Sandbox → menu → Sandbox, Jogar
godot --headless -s res://tests/shadow_visual_test.gd  # regra "sombra": u_* = sombra convertida da viva
godot --headless -s res://tests/paladin_test.gd  # Paladino: mecânica do HTML, visual, Sandbox, luta de referência
godot --headless -s res://tests/paladin_sprite_test.gd  # Paladino Vivo por sprites (alternativa): frames, pivô, estados
godot --headless -s res://tests/paladin_live_test.gd  # Paladino Vivo padrão: gameplay idêntico, família visual, espada/escudo, estados
godot --headless -s res://tests/paladin_rig_test.gd  # rig 2.5D (alternativa): espada/escudo, direções, estados
godot --headless -s res://tests/bench_parity_test.gd  # CombatSim otimizada == referência congelada (40 lutas) + BenchCombatSim
godot --headless -s res://tests/corpse_freeze_test.gd  # cadáver assentado não é mais atualizado nem redesenhado
godot --headless -s res://tests/redraw_test.gd  # anel/barra só por mudança; DrawCache (1ª vez direto, 2ª malha)
godot --headless -s res://tests/sim_pacing_test.gd  # limite de passos por quadro; mesmo resultado em 60/30/5 FPS
godot --headless -s res://tests/perf_overlay_test.gd  # painel F6: liga/desliga, métricas, não bloqueia, não muda a luta
```
Cada teste sai com código 0 se passar e 1 se falhar.

`sandbox_test` aperta os botões reais e faz um clique de verdade no viewport. Ele verifica:
- abertura no menu;
- criação de tropas e combate parado antes de Iniciar;
- combate real, Reiniciar, Limpar e F9;
- F3/F4 e seleção com edição;
- voltar ao menu e entrar/sair 3 vezes sem acumular nós;
- que cada tropa usa o visual da sua `UnitDef`, que o golpe real chega ao visual e que os mortos executam a queda.

`visual_test` dirige os dois visuais quadro a quadro com `CombatUnit` reais. Ele verifica:
- idle;
- walk só com deslocamento;
- preparação, golpe e retorno;
- hit curto;
- queda e permanência no chão;
- que o visual não altera stats;
- o círculo padrão para `UnitDef` sem `visual_script`.

`sentinel_test` verifica a Sentinela:
- stats do HTML nas duas versões;
- ataque à distância: para a 0,92 × alcance, o dano vem no impacto e não no disparo, orbe a 340;
- orbe acerta quem estiver no caminho quando o alvo morre, e expira;
- lâminas: reação 0,55 s, antecipação, uma de cada vez, âncora, 520 px/s, dano, volta em 10 s, reação rápida
  da 2ª lâmina e nada fora de 115;
- visual das duas versões: idle, movimento, preparação/disparo/retorno, antecipação/partida/recarga/reforma
  da lâmina, hit, morte e permanência no chão; e que o visual não altera stats.

`sandbox_test` também verifica que a UI está na faixa inferior (15–30% da altura) e que o campo inteiro aparece
acima dela.

`shadow_visual_test` verifica a regra das sombras:
- o estilo padrão vem de `data/visuals/shadow_style.tres`; `convert` escurece o corpo e `keep` preserva o matiz
  de acentos; a energia é roxa;
- toda `u_*` do catálogo usa visual de sombra e toda unidade viva, visual normal;
- em cada par vivo/sombra: estilo só na sombra, contorno da regra, **mesma silhueta** (área clicável e altura da
  barra de HP), corpo bem mais escuro, brilho roxo, o visual não altera a unidade e a energia se apaga na morte.

`backdrop_test` também garante a coerência do fundo: a base de toda torre externa e das muralhas fica dentro do
rochedo, as pontes do castelo são filhas do castelo e todo pilar/ponte desce até o chão.

`paladin_test` verifica o Paladino:
- stats do HTML nas duas versões e `PALADIN_CONFIG` (115 · 2,5 s · 1 s · 1,5 s · 75% · 15 s);
- provocação no 1º passo, alvo forçado mesmo com outro inimigo mais perto, fora do raio (116) não provoca,
  expira em 2,5 s, não repete antes de 15 s e repete depois; escudo 1 s depois, travado na direção do inimigo,
  20 → 5 de dano, dura 1,5 s, só vale para o próprio Paladino; morte libera os provocados;
- 3 × 3 Paladinos + Guerreiros até o fim; a **luta de referência** Guerreiro Sombra × Guerreiro (semente 97)
  dá exatamente o mesmo resultado medido antes desta etapa (`ally 20/74 12.025 13`);
- visual das duas versões: idle firme, walk curto pela distância, preparação/golpe/retorno, provocação,
  espera/escudo/bloqueio, hit curto, morte de costas com espada e escudo soltos, permanência no chão, e que o
  visual não altera stats; regra da sombra com o dourado preservado; maior que o Guerreiro sem virar chefe;
- Sandbox real: botões dos dois Paladinos, vários Paladinos + Guerreiros + Sentinela, combate até o fim com
  provocações, Reiniciar e Limpar.

`sandbox_test` também cobre as Sentinelas no fluxo real:
- visual próprio;
- disparo criando `ProjectileView`;
- Reiniciar e Limpar limpando projéteis;
- sair do Sandbox com projéteis em voo sem vazar nós.

---

## Benchmark e profiling (`tools/bench`) — só medição

Ferramentas para medir o custo do combate com muitas unidades, **sem mudar o jogo** (detalhes e como repetir em
`tools/bench/README.md`; resultados e conclusões em `PROFILING_REPORT.md`).

- `BenchCombatSim extends CombatSim` (`scripts/debug/bench/`): envolve a CombatSim (chama `super` e só cronometra
  e conta), com os modos `FULL` / `TARGET_ONLY` / `MOVE_ONLY`. Os contadores de alvo vêm da própria CombatSim.
- `tests/support/reference_combat_sim.gd`: cópia CONGELADA da CombatSim de antes da otimização 1;
  `tests/bench_parity_test.gd` exige resultado idêntico a ela.
- Otimização por etapas: `tools/bench/opt_step.sh` + `compare_steps.py`; resultado em `OPTIMIZATION_REPORT.md`.
- `Battle.sim_script`: único gancho no código do jogo. `null` (padrão) = `CombatSim`; o stress test põe
  `BenchCombatSim` antes de `Battle.clear()`.
- `tools/bench/stress_bench.gd`: um cenário no fluxo real (Main → Sandbox → Arena → Battle → UnitView). Um nó
  "driver", último a processar, faz o que o `UnitView._process` faz (com cronômetro por classe de visual), liga uma
  sonda ao sinal `draw` de cada `CanvasItem` (tempo de `_draw` por categoria) e lê os monitores do Godot (draw
  calls, primitivas, nós, render). Modos visuais `normal` / `nodraw` / `minimal` / `hidden` para separar visual e
  lógica.
- `tools/bench/godot_profiler.py`: servidor de depuração remota que liga o Profiler do Godot (servers + funções de
  script) sem o editor — o jogo roda com `--remote-debug tcp://127.0.0.1:PORTA`.
- `tools/bench/run_matrix.sh` (matriz completa) e `tools/bench/make_report.py` (tabelas Markdown).

---

## Próximas etapas (planejadas)

1. ~~Esqueleto + arena~~ ✔ · ~~núcleo mínimo de combate (1 × 1)~~ ✔ · ~~menu inicial + Sandbox~~ ✔
2. Máquina de fases (`MENU/PREP/BATTLE/NECROMANCY/VICTORY/DEAD`) + autoloads `GameState` e `Events`; ligar o
   botão Jogar.
3. Mais `UnitDef` (facções do HTML), `FactionDef`… + posicionamento na grade. (`UnitDef`/`UnitCatalog` já existem.)
4. Batalha completa sobre o núcleo: velocidade 1x/2x/3x, IA de formação (inclui recuo das unidades à distância),
   integração com a fase de batalha. (Passo fixo, movimento, alvo, ataque básico, projéteis e as lâminas da
   Sentinela já existem.)
5. Cadáveres, Necromancia e portal.
6. Essência, capacidade, lojas, Relíquias, Escola e HUD.
7. Áudio, configurações e ferramentas (evoluir o Sandbox, bot/Run Lab).
