# Mortivane (Godot 4) — Arquitetura

Estado: **Etapa 1 (esqueleto + arena) + núcleo mínimo de combate + menu inicial + Sandbox.**
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
  data/
    units/u_warrior.tres             # UnitDef — Guerreiro Morto-Vivo (aliado)
    units/warrior.tres               # UnitDef — Guerreiro (inimigo)
  scenes/
    main/main.tscn                   # raiz do jogo: troca de tela + avisos
    menu/main_menu.tscn              # menu inicial (Jogar / Sandbox)
    sandbox/sandbox.tscn             # Sandbox: Arena + SandboxUI + SandboxController
    arena/arena.tscn                 # arena: camadas + Battle + debug
  scripts/
    core/world_config.gd             # class_name WorldConfig — constantes do mundo
    arena/arena.gd                   # enquadramento (câmera + fundo cover)
    arena/battle_grid.gd             # class_name BattleGrid — geometria das grades (só leitura)
    arena/debug_overlay.gd           # class_name DebugOverlay — desenho de referência
    combat/combat_unit.gd            # class_name CombatUnit — estado de uma unidade (dado puro)
    combat/combat_sim.gd             # class_name CombatSim — alvo, movimento, ataque, dano, morte (dado puro)
    combat/unit_view.gd              # class_name UnitView — visual temporário + barra de HP + debug
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
   ├─ Background (Node2D)        arte fixa; nunca treme nem recebe efeitos
   │   └─ ArenaArt (Sprite2D)
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
- `CombatSim` (`RefCounted`) contém as regras. Não conhece nós. Emite `unit_attacked` e `unit_died`.
- `Battle` (`Node`, dentro da Arena) é o **executor**. Não decide quem luta nem quando.
  - API: `spawn(def, team, pos, overrides)`, `start()`, `clear()`, `is_running()`, `is_finished()`,
    `unit_at(ponto)` e `view_of(unit)`.
  - Nasce vazia e **parada**. Só depois de `start()` acumula o dt do quadro (limitado a 0,05 s) e avança a
    simulação em passos fixos de `CombatSim.STEP` = 1/120 s.
  - Cria um `UnitView` por unidade em `Stage/World/Entities`.
  - Emite `finished(winner_team)` uma vez, quando um lado fica sem ninguém vivo (−1 = ninguém sobrou).
    A simulação continua rodando depois disso, e os sobreviventes passam a `IDLE`.
- `UnitView` (`Node2D`, visual temporário) só lê a `CombatUnit`:
  - círculo com as cores da `UnitDef` e barra de HP;
  - flash ao ser atingido e sumiço gradual ao morrer;
  - anel de seleção;
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
`CombatSim.dispose()` limpa os alvos, e `Battle` o chama em `clear()` e em `_exit_tree`.

**Semente.** `Battle.rng_seed = 97` sorteia a primeira recarga de cada unidade. Assim, a mesma montagem sempre
produz a mesma luta, e o **Reiniciar** do Sandbox repete a luta exatamente igual.

As simplificações em relação ao HTML estão em `MIGRATION_NOTES.md`, seção 6.

---

## Dados de unidade (`UnitDef` + `UnitCatalog`)

- `UnitDef` (`Resource`) define uma unidade: um `.tres` por unidade em `res://data/units/`.
  - Campos: `id` (a chave do HTML), `display_name`, `side` (em que lista aparece);
  - combate: `max_hp`, `damage`, `attack_range`, `attack_interval`, `move_speed`, `radius`;
  - visual temporário: `body_color`, `trim_color`.
- `to_stats(overrides)` gera o dicionário que `CombatUnit` consome. A `CombatSim` **não conhece** `UnitDef`.
- `UnitCatalog` lê a pasta (`all()`, `for_side()`, `get_def(id)`). As listas do Sandbox vêm daqui: para
  adicionar uma unidade basta criar um `.tres`, sem mexer em código.

| `.tres` | Nome | Lado | HP | Dano | Alcance | cd | Vel. | r |
|---|---|---|---|---|---|---|---|---|
| `u_warrior` | Guerreiro Morto-Vivo | PLAYER | 74 | 10 | 32 | 1,0 | 56 | 12 |
| `warrior` | Guerreiro | ENEMY | 70 | 9 | 32 | 1,0 | 56 | 12 |

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
```
Cada teste sai com código 0 se passar e 1 se falhar.

`sandbox_test` aperta os botões reais e faz um clique de verdade no viewport. Ele verifica:
- abertura no menu;
- criação de tropas e combate parado antes de Iniciar;
- combate real, Reiniciar, Limpar e F9;
- F3/F4 e seleção com edição;
- voltar ao menu e entrar/sair 3 vezes sem acumular nós.

---

## Próximas etapas (planejadas)

1. ~~Esqueleto + arena~~ ✔ · ~~núcleo mínimo de combate (1 × 1)~~ ✔ · ~~menu inicial + Sandbox~~ ✔
2. Máquina de fases (`MENU/PREP/BATTLE/NECROMANCY/VICTORY/DEAD`) + autoloads `GameState` e `Events`; ligar o
   botão Jogar.
3. Mais `UnitDef` (facções do HTML), `FactionDef`… + posicionamento na grade. (`UnitDef`/`UnitCatalog` já existem.)
4. Batalha completa sobre o núcleo: velocidade 1x/2x/3x, IA de formação, unidades à distância/projéteis,
   integração com a fase de batalha. (Passo fixo, movimento, alvo e ataque básico já existem.)
5. Cadáveres, Necromancia e portal.
6. Essência, capacidade, lojas, Relíquias, Escola e HUD.
7. Áudio, configurações e ferramentas (evoluir o Sandbox, bot/Run Lab).
