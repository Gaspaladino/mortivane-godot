# Mortivane (Godot 4) — Arquitetura

Estado: **Etapa 1 (esqueleto + arena) + núcleo mínimo de combate + menu inicial + Sandbox
+ Guerreiro, Guerreiro Morto-Vivo, Sentinela Arcana e Sentinela Arcana Sombra desenhados 100% por código.**
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
  data/
    units/u_warrior.tres             # UnitDef — Guerreiro Morto-Vivo (aliado)
    units/warrior.tres               # UnitDef — Guerreiro (inimigo)
    units/arc_battlemage.tres        # UnitDef — Sentinela Arcana (inimiga)
    units/u_arc_battlemage.tres      # UnitDef — Sentinela Arcana Sombra (aliada)
  scenes/
    main/main.tscn                   # raiz do jogo: troca de tela + avisos
    menu/main_menu.tscn              # menu inicial (Jogar / Sandbox)
    sandbox/sandbox.tscn             # Sandbox: Arena + SandboxUI + SandboxController
    arena/arena.tscn                 # arena: camadas + Battle + debug
    arena/arena_backdrop.tscn        # fundo da arena reconstruído (13 camadas)
  scripts/
    core/world_config.gd             # class_name WorldConfig — constantes do mundo
    arena/arena.gd                   # enquadramento (câmera + fundo cover)
    arena/battle_grid.gd             # class_name BattleGrid — geometria das grades (só leitura)
    arena/debug_overlay.gd           # class_name DebugOverlay — desenho de referência
    combat/combat_unit.gd            # class_name CombatUnit — estado de uma unidade (dado puro)
    combat/combat_sim.gd             # class_name CombatSim — alvo, movimento, ataque, projéteis, dano, morte (dado puro)
    combat/combat_projectile.gd      # class_name CombatProjectile — projétil da simulação (dado puro)
    combat/abilities/sentinel_swords.gd  # class_name SentinelSwords — lâminas da Sentinela (dado puro)
    combat/unit_view.gd              # class_name UnitView — seleção + barra de HP + debug; hospeda o visual
    visuals/units/unit_visual.gd     # class_name UnitVisual — base/interface do "corpo" de uma unidade
    visuals/units/circle_unit_visual.gd     # class_name CircleUnitVisual — círculo padrão (sem visual_script)
    visuals/units/code_drawn_unit_visual.gd # class_name CodeDrawnUnitVisual — utilitários de desenho comuns
    visuals/units/sentinel_visual.gd        # class_name SentinelVisual — Sentinela Arcana viva
    visuals/units/sentinel_shadow_visual.gd # class_name SentinelShadowVisual — Sentinela Sombra (herda a viva)
    visuals/effects/arcane_blade.gd         # class_name ArcaneBlade — desenho da lâmina (pairando e em voo)
    visuals/projectiles/projectile_view.gd  # class_name ProjectileView — orbe/lâmina em voo + impacto
    visuals/backdrop/arena_backdrop.gd      # class_name ArenaBackdrop — orquestra camadas, tempo, parallax, ajustes
    visuals/backdrop/arena_layers_data.gd   # class_name ArenaLayersData — GERADO: posições do primeiro plano
    visuals/backdrop/layers/*.gd            # BackdropSilhouette, MountainLayer, CastleLayer, CastleLights, RuinsLayer, CandleFlames
    visuals/backdrop/shaders/*.gdshader     # céu, lua, nuvens, neblina, estandarte, velas (+ noise.gdshaderinc)
    visuals/units/warrior_visual.gd         # class_name WarriorVisual — Guerreiro por código (rig + animação)
    visuals/units/undead_warrior_visual.gd  # class_name UndeadWarriorVisual — herda o Guerreiro
    combat/battle.gd                 # class_name Battle — executor: CombatSim + UnitView + passo fixo
    data/unit_def.gd                 # class_name UnitDef (Resource) — definição de unidade
    data/unit_catalog.gd             # class_name UnitCatalog — carrega data/units/*.tres
    menu/main_menu.gd                # class_name MainMenu — só emite sinais
    sandbox/sandbox_controller.gd    # class_name SandboxController — montagem, ações, seleção
    sandbox/sandbox_ui.gd            # class_name SandboxUI — painéis e botões; só sinais
    main/main.gd                     # troca de tela + atalhos globais (F3/F4/F9/F11) + avisos
  tests/
    combat_test.gd                   # teste headless do combate (SceneTree)
    sandbox_test.gd                  # teste headless de ponta a ponta: menu + Sandbox na cena real
    visual_test.gd                   # teste headless das poses/animações dos visuais por código
    sentinel_test.gd                 # teste headless da Sentinela: mecânica portada do HTML + visual
    backdrop_test.gd                 # teste headless do fundo animado
```

Arquivos `*.import` e `*.uid` são gerados pela Godot e **devem ser versionados**. A pasta `.godot/` é cache
e fica fora do Git.

---

## Cenas

```
Main (Node)                      main.gd — troca de tela, atalhos globais (F3, F4, F9, F11) e avisos
├─ <tela atual>                  uma por vez: MainMenu ou Sandbox (instanciada por Main)
└─ NoticeLayer (CanvasLayer 110) / NoticeLabel   aviso temporário no rodapé

MainMenu (Control)               main_menu.gd — título + Jogar / Sandbox; sinais play_pressed, sandbox_pressed
├─ Backdrop (TextureRect)        a arte da arena, escurecida (cover)
└─ Center / Box                  título, botões, MessageLabel

Sandbox (Node)                   sandbox_controller.gd — montagem, ações, seleção; sinal exit_requested
├─ Arena                         a MESMA arena.tscn (instância), sem nada específico de Sandbox
└─ SandboxUI (CanvasLayer 50)    sandbox_ui.gd — painéis montados em código

Arena (Node2D)                   arena.gd — enquadramento; set_debug_visible()
   ├─ Camera2D                   posicionada pelo enquadramento
   ├─ Background (Node2D)        fundo; nunca treme nem recebe efeitos de gameplay
   │   └─ Backdrop (ArenaBackdrop, arena_backdrop.tscn) — camadas animadas (ver "Fundo animado")
   ├─ Stage (Node2D)             ← futuro tremor de tela aplicado aqui
   │   ├─ World (Node2D)
   │   │   ├─ Ground             áreas no chão, cadáveres (futuro)
   │   │   └─ Entities           unidades (UnitView, criados por Battle), y_sort_enabled
   │   └─ Effects (Node2D)       efeitos visuais do gameplay (futuro)
   ├─ Battle (Node)              battle.gd — executor do combate; entities_path → Stage/World/Entities
   └─ Debug (Node2D)             debug_overlay.gd — DebugOverlay.set_shown()
       └─ InfoLayer (CanvasLayer 100) / InfoLabel   janela, mundo visível, escala (rodapé esquerdo)
```

**Troca de tela.** `Main._switch_to()` tira a tela antiga da árvore na hora (a Arena antiga não disputa a
câmera) e a libera no fim do quadro, depois instancia a nova. Não há `change_scene`: `Main` e o `NoticeLayer`
continuam vivos entre telas.

O painel do F3 (`InfoLabel`) foi para o **rodapé esquerdo**, porque o topo agora é do Sandbox.

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

- Atalhos globais ficam **só em `Main`** e são tratados em `_input`, antes da interface, para que nenhum
  controle de UI consiga "engolir" as teclas. Os botões usam `focus_mode = NONE`, então teclas nunca os apertam.
- `Main` guarda o estado de F3/F4 e o aplica a toda Arena nova, então ele sobrevive a sair e voltar ao Sandbox.
  No menu, F3/F4 só mudam esse estado guardado.
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
  - Cria um `UnitView` por unidade em `Stage/World/Entities`.
  - Emite `finished(winner_team)` uma vez, quando um lado fica sem ninguém vivo (−1 = ninguém sobrou).
    A simulação continua rodando depois disso, e os sobreviventes passam a `IDLE`.
- `UnitView` (`Node2D`) só lê a `CombatUnit` e hospeda o corpo (ver **Visuais de unidade**):
  - anel de seleção (elipse nos pés) e, com F4, alcance e linha até o alvo;
  - filho `Body` = o `UnitVisual` da `UnitDef`;
  - filho `Overlay` = barra de HP e texto do F4, sempre por cima do corpo.
- A `Battle` repassa os sinais como eventos **só visuais**:
  - `attack_performed` → `on_attack_performed()` no atacante;
  - `unit_attacked` → `on_hit()` no alvo;
  - `projectile_fired` → `on_projectile_fired()` no dono, mais um `ProjectileView` em `Stage/Effects`;
  - `projectile_ended` → impacto (ou dissipação) no `ProjectileView`, que depois se libera sozinho.
- `unit_at()` usa a área clicável do visual (`UnitView.contains_point`).

**Regras por passo** (para cada unidade viva, em ordem de criação)
1. Desconta a recarga.
2. Alvo = inimigo **vivo** mais próximo (distância centro a centro). Sem nenhum → `IDLE`.
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
- `UnitDef.visual_script` escolhe o visual. Vazio = `CircleUnitVisual`, o círculo das etapas anteriores.
- **`WarriorVisual`** tem o rig e a animação:
  - O rig é uma cadeia de `Transform2D`: raiz (pés; espelho pela direção; `RIG_SCALE = 0.9`) → quadril →
    pernas / tronco → cabeça, ombros e braços → mão → espada.
  - Cada parte é um conjunto de polígonos no próprio espaço local, com contorno escuro.
  - Ordem de desenho: sombra · capa · braço e ombreira de trás · pernas · saiote/cinto · peitoral
    · elmo (pluma, fenda) · espada · braço, ombreira e mão da frente.
  - Tamanho: ≈ 36 unidades do mundo de altura (≈ 58 px em 1600×896). Os pés ficam 9 abaixo do centro lógico.
- A cada quadro, `update_visual` recalcula uma **pose** (`p_*`: ângulos e deslocamentos) a partir do estado real,
  e `_draw()` só a aplica.

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

**Guerreiro × Morto-Vivo.** `UndeadWarriorVisual extends WarriorVisual` e muda só parâmetros e detalhes:

| | Guerreiro | Morto-Vivo |
|---|---|---|
| Paleta | metal claro, capa e pluma vermelhas | metal escuro/gasto, tecido verde-musgo, pluma desbotada |
| Detalhes | — | capa rasgada, lâmina lascada, amassado no elmo, rachadura no peitoral, brilho verde pulsante na fenda |
| Postura | ereta | tronco +7°, cabeça +13° e afundada |
| Idle | estável | irregular (`jitter`: soma de senos) |
| Walk | pernas em oposição perfeita | defasadas (0,78π), perna de trás arrasta, tronco balança |
| Ataque | recua a espada e estoca na horizontal | ergue a espada acima da cabeça e golpeia para baixo; avanço maior, retorno mais lento |
| Queda | de costas, pesada (acelera), um quique | joelhos cedem, depois desaba para frente com tremores |

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
  - `SentinelShadowVisual extends SentinelVisual`: mesmo rig; troca paleta, estilo e alguns pontos de extensão
    (barra rasgada, capelete, olhos, fumaça, morte).
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

## Fundo da arena (`ArenaBackdrop`) — reconstruído do zero

Tudo o que fica **atrás do campo** foi recriado no Godot, sem nenhum pixel da arte antiga: céu, lua, nuvens,
montanhas, neblina, castelo, torres, ruínas e arcos. Da arte antiga (`novocenario.png`) sobrou apenas o primeiro
plano, que foi pedido para preservar:
- o chão de pedra com o desenho roxo e o muro de ruínas (`arena.png`);
- os elementos laterais: pilares, arco, árvores secas, lápide (`sides.png`), estandartes e velas.

Essas partes são extraídas por `tools/arena_backdrop/build_layers.py`. Nenhuma cena usa mais `novocenario.png`;
ele só serve de fonte para a ferramenta. O menu inicial também usa o fundo novo, escurecido.

**Camadas** (`arena_backdrop.tscn`; espaço local = pixels da arte, 1672×941; a Arena escala em cover)

| Camada | Profundidade | Como é feita | Animação |
|---|---|---|---|
| `SkyLayer` | 0 | shader `sky`: gradiente frio (escuro no alto, mais claro no horizonte), variação larga, poucas estrelas | estrelas cintilam devagar |
| `MoonLayer` | 0,03 | shader `moon`: disco branco-azulado com mares e borda escurecida, halo atmosférico | brilho pulsa ±3,5% num ciclo de 6,5 s |
| `FarCloudLayer` | 0,06 | shader `clouds`: bancos pequenos e ralos, 3 fileiras | 2 px/s → direita |
| `MidCloudLayer` | 0,12 | shader `clouds`: bancos maiores, 2 fileiras; passam na frente da lua | 4,5 px/s → direita |
| `MountainBackLayer` | 0,2 | `MountainLayer` (código): picos claros e enevoados | — |
| `FogLayerFar` | 0,25 | shader `fog`: véu no horizonte | 1,4 px/s → direita |
| `MountainFrontLayer` | 0,35 | `MountainLayer`: picos agudos mais escuros, luz de borda da lua, vincos | — |
| `CastleLayer` | 0,45 | `CastleLayer` (código): castelo principal no penhasco e forte menor | janelas (`CastleLights`) |
| `RuinsLayer` | 0,5 | `RuinsLayer` (código): pontes em arco quebradas e torres partidas | — |
| `FogLayerMid` | 0,55 | shader `fog`: entre montanhas e castelo | 2,4 px/s ← **esquerda** |
| `FogLayerNear` | 0,7 | shader `fog`: faixa baixa atrás do muro | 3,2 px/s → direita |
| `SideElementsLayer` | 0,95 | laterais extraídas + estandartes + velas + `CandleFlames` | estandartes e chamas |
| `ArenaLayer` | 1 | chão e muro extraídos | nenhuma |

**Silhuetas por código** (`scripts/visuals/backdrop/layers/`)
- Base `BackdropSilhouette`:
  - monta a geometria **uma vez**, como triângulos com cor por vértice (gradiente vertical, a base clareia na
    neblina);
  - desenha tudo num único `canvas_item_add_triangle_array`;
  - por cima, linhas antialiasadas: contorno e **luz de borda**, que clareia só as arestas cuja normal aponta
    para a lua;
  - nada é refeito por quadro.
- `MountainLayer`:
  - picos definidos como `Vector4(x, altura, meia-largura, agudeza)`; agudeza > 1 dá encostas côncavas e ponta
    de agulha;
  - ruído em duas escalas (ombros e serrilhado);
  - vincos que descem dos picos altos.
  - As duas cordilheiras são a mesma classe com parâmetros diferentes na cena.
- `CastleLayer`:
  - rochas com borda irregular, torres com beiral e pináculo fino côncavo;
  - a menagem tem telhado baixo e agulha central; torrinhas, muralhas com ameias;
  - janelas góticas;
  - luz de borda nas arestas voltadas para a lua.
- `CastleLights` (aditivo): cada janela tem dois senos lentos, com períodos de dezenas de segundos, e um viés
  próprio. Parte das janelas nunca acende; as outras acendem e apagam suavemente, **nunca todas juntas**, com
  cintilação mínima.
- `RuinsLayer`: pontes com vãos em arco, pilares e pontas quebradas; torres partidas com topo irregular.
- `CandleFlames` (aditivo): língua de fogo por vela, com altura ±10%, largura ±8%, ponta balançando < 0,5 px e
  brilho local pequeno.

**Shaders** (`scripts/visuals/backdrop/shaders/`, com `noise.gdshaderinc`)
- **Nuvens:** bancos numa grade que desliza.
  - Cada banco tem pontas longas e finas, topo em "escamas" e base quase reta.
  - Três tons: corpo, borda de cima clara e barriga escura. Perto da lua, a borda fica prateada.
  - Como a grade é contínua, nada salta; cada banco entra e sai pelas bordas.
- **Neblina:** véu constante mais massas que deslizam, numa faixa vertical com pico de densidade.
- **Estandarte:** balanço **pendular** lento a partir da haste, mais uma onda pequena que desce até a ponta
  (pano pesado).
- **Velas:** o recorte das chamas pintadas respira de leve.

**Parallax.** `view_offset` (px da arte) desloca cada camada por `offset × (1 − profundidade)`: o céu acompanha
tudo e a arena não se move. Está pronto para uma câmera futura. `parallax_preview` faz um vaivém só para
visualizar.

**Ajustes** (propriedades exportadas do `ArenaBackdrop`)
- `animated`, `master_intensity` (0 = nada se mexe nem pulsa).
- Lua: posição, raio, pulsação e halo.
- Estrelas.
- Nuvens e neblina: velocidade e opacidade.
- Janelas do castelo: intensidade e velocidade.
- Estandartes e velas: força e velocidade.
- Forma das silhuetas: picos, cores e força da luz de borda, nos próprios nós da cena.

**Custo.** Céu e lua (simples), duas camadas de nuvem (até 9 bancos avaliados por pixel, só na faixa do céu) e
três de neblina (fbm de 5 oitavas numa faixa de cerca de 220 px). As silhuetas são geometria estática.

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
| `u_warrior` | Guerreiro Morto-Vivo | PLAYER | 74 | 10 | 32 | 1,0 | 56 | 12 |
| `warrior` | Guerreiro | ENEMY | 70 | 9 | 32 | 1,0 | 56 | 12 |
| `arc_battlemage` | Sentinela Arcana | ENEMY | 43 | 18 | 150 | 1,25 | 54 | 13 |
| `u_arc_battlemage` | Sentinela Arcana Sombra | PLAYER | 40 | 18 | 150 | 1,25 | 54 | 13 |

As duas Sentinelas têm `projectile_kind = "orb"` e `abilities = ["arcane_swords"]`. A Sombra é a versão
morta-viva do HTML (`registerFactionUnits`: mesmos stats, HP × 0,94).

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

**Painel da unidade selecionada.**
- Mostra nome, lado, estado, HP atual/máx., dano, alcance, intervalo, velocidade e alvo, atualizado a cada quadro.
- Tem 5 campos editáveis por instância, só em `PREP`: HP máx., dano, alcance, intervalo e velocidade.
  - A edição grava em `Placement.overrides` e recria a montagem, então vale desde o início da luta.
  - A `UnitDef` não muda.

**Layout.** Os painéis ficam no céu da arte, acima de y=210, para não cobrir o campo:
- ALIADOS no topo esquerdo;
- controles, estado e unidade selecionada no topo centro;
- INIMIGOS no topo direito.

---

## Testes headless

```
godot --headless --import                       # uma vez, gera o cache de classes (.godot/)
godot --headless -s res://tests/combat_test.gd  # regras de combate + catálogo
godot --headless -s res://tests/sandbox_test.gd # ponta a ponta na cena real (menu → Sandbox → menu)
godot --headless -s res://tests/visual_test.gd  # poses/animações dos visuais por código
godot --headless -s res://tests/sentinel_test.gd  # Sentinela: mecânica do HTML + visual
godot --headless -s res://tests/backdrop_test.gd  # fundo: camadas, profundidade, movimento, janelas, parallax
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

`sandbox_test` também cobre as Sentinelas no fluxo real:
- visual próprio;
- disparo criando `ProjectileView`;
- Reiniciar e Limpar limpando projéteis;
- sair do Sandbox com projéteis em voo sem vazar nós.

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
