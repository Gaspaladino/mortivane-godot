# Mortivane — Notas de migração (HTML V97 → Godot 4)

Referência analisada: `MortivaneV97.html` (18.011 linhas, ~1,8 MB). O arquivo **não foi alterado**.
Título interno do código: "Coleção de Ossos — MVP". Todo o jogo está num único HTML: CSS (~1.400 linhas, com
camadas versionadas `V64`…`V97`), marcação DOM da HUD/overlays e um único `<script id="gameCore">`.

---

## 1. Estrutura do arquivo

O próprio script declara a organização (linha ~1607):

| Bloco | Conteúdo | Linhas aprox. |
|---|---|---|
| 0. Áudio | `SND`: música, SFX e vozes **sintetizados em WebAudio** (nenhum arquivo de som) | 1624–2072 |
| 1. Config + dados | `W/H`, `BATTLEFIELD`, `CFG`, `UNIT_DEFS`, `FACTION_DEFS`, `FACTION_UNITS`, `SCHOOLS`, `RITUAL_DEFS`, `RELIC_DEFS`, progressão | 2073–4520 |
| 2. Estado | objeto global `S` (fase, onda, essência, unidades, cadáveres, relíquias…) | 4521–4602 |
| 3. Utilitários | `rnd`, `clamp`, `dist`, `pick`, `weighted` | 4604+ |
| 4. Fábrica de entidades | criação de unidades, stats recalculados (def + perks + escola + rituais + cadáver especial) | ~5239–5530 |
| 5. Combate | IA por papel, alvo, vanguarda/exposição, projéteis, auras, habilidades | ~5539–6770 |
| 6. Fluxo de fases | ondas, geração de onda, prep/batalha/necromancia, fim de run | ~6770–7645 |
| 7. Necromancia | erguer, sacrificar, portal (entidade que devora cadáveres) | 7646–7910 |
| 8. Render | canvas 2D: arena, unidades desenhadas por código, FX, HUD no canvas | 8319–11485 |
| 9. UI (DOM) | cards, lojas, relíquias, escola, livro de necromancia, tooltips | 11734–15230 |
| 10. Loop / input / boot | `frame()` via `requestAnimationFrame`, input, menu | 15232–16346 |
| Extras | Sandbox/Admin (13584–15030), Laboratório/bot com Web Workers (15426–16012), Jaula Orc V73–75 (16348–17036), Círculo de Estudo (17037+), Livro de Necromancia V93–97 (17212–18008) | |

Observação: há muitas camadas "V64…V97" que sobrescrevem regras anteriores (CSS com `!important`, funções
redefinidas). Isso é histórico de iteração, não arquitetura — **não deve ser replicado** no Godot.

---

## 2. Sistemas identificados

**Núcleo de run**
- Fases (`S.phase`): `menu → prep → battle → necromancy → prep … → victory | dead`.
  - Se a batalha termina sem cadáveres, pula a necromancia e volta direto para `prep`.
  - Run de **25 ondas** (`RUN_CONFIG.total=25`), atos terminando nas ondas 5/12/18/24/25.
- Loop: `frame()` com `dt` limitado a 0,05 s. A batalha roda em **passo fixo de 1/120 s** com acumulador e
  velocidade 1x/2x/3x (`advanceBattleClock`). Pausa quando há modal/escolha pendente.
- Necromante: unidade especial (HP 240, dano 15, alcance 250), posição fixa no lado do jogador; HP **não regenera**
  entre ondas.
- Capacidade do exército: tabela por onda (`CAPACITY_PROGRESSION`, 10 → 45) + bônus de relíquias/escola/rituais.
  Cada unidade tem `cost` (pontos de capacidade).
- Essência: moeda da run (vem de sacrifícios); usada em lojas de relíquias, escola e rituais.

**Conteúdo**
- 4 facções inimigas (`FACTION_ORDER`): Ordem Sagrada, Irmandade das Sombras, Clãs Orcs, Círculo Arcano —
  cada uma com paleta, música, formação e 5–6 unidades (22 no total, com `from` = onda de introdução).
  Ex.: Paladino, Tocador de Sino, Clérigo, Besteiro, Assassino, Orc, Cão de Guerra, Ogro, Mago, Sentinela Arcana…
- Toda unidade de facção gera automaticamente sua versão morta-viva (paleta fria) ao ser erguida.
- Unidades legadas em `UNIT_DEFS` (warrior, archer, mage, brute, boss_titan e versões `u_*`).
- Tags (melee, ranged, projectile, aoe, magic, heal, charge, bone/flesh…) derivadas + explícitas; relíquias e
  rituais interagem por tag.
- Escolas do Necromante: `veil`, `bone`, `soul`, `plague` — **apenas `veil` (Primeiro Véu) está habilitada**,
  com marcos nas ondas 5/12/18.
- Relíquias (~21, `RELIC_DEFS`): acumulam cópias, sem limite de slots; loja/baú com preço por raridade.
- Rituais (~34, `RITUAL_DEFS`): sistema de hooks (`fireHook`, `onBattleEnd`, morte de aliado…). O painel de
  rituais está marcado como *legacy/hidden* — parecem parcialmente substituídos por relíquias/escola.
- Cadáveres especiais (Corrompido, Robusto, Arcano); estado de alma (estável/instável/fraturada).
- Eventos de campo: chuva de fogo, chuva ácida, terremoto. Baú surpresa.

**Posicionamento**
- Grade de formação por lado: 11 colunas × 7 linhas; footprints de 1–4 células (L rotacionável com `R`).
- Máscara do jogador (`PLAYER_GRID_MASK`): `A` livre, `B` bloqueada, `N` reservada ao Necromante.
- Inimigos da próxima onda já ficam no campo durante a preparação, inertes (prévia).

**Interface (DOM sobre o canvas)**
- HUD da run: medidor de capacidade, essência, relíquias, linha do tempo da run, velocidade da batalha,
  cartas do exército (esquerda), bandeja de cadáveres (baixo), ações de fase (direita).
- Overlays: menu inicial, escolha de escola, loja de relíquias, rituais, intro de facção, resumo da onda,
  configurações (áudio + gama via filtro SVG), morte.
- Livro de Necromancia (V93–97): interface principal da fase de necromancia, com animação de abrir/fechar.

**Ferramentas de desenvolvimento**
- Sandbox/Admin: editar unidades por instância, presets (localStorage), debug de IA.
- Laboratório: bot que joga runs inteiras com seed determinística, em Web Workers, gerando telemetria/balanceamento.

**Persistência**: só `localStorage` — config de áudio, gama, presets do admin, histórico das últimas 50 runs.
Não há save de run em andamento.

---

## 3. Cenário, resolução, arena e área jogável

**Mundo lógico fixo: 1000 × 560** (`const W = 1000, H = 560`). Toda a lógica (posições, alcance, velocidades)
está nessa unidade. O canvas só aumenta o *backing store* por `devicePixelRatio` (até 2,4×) para nitidez.

**Área jogável (`BATTLEFIELD`)**
- `MARGIN = 26` → x ∈ [26, 974], y ∈ [**210**, 534].
- `BATTLEFIELD.topY = 560 × 0,375 = 210`: acima disso é "céu" da arte; nada de gameplay vive lá.
- A unidade é limitada para o **sprite inteiro** ficar abaixo de `topY` (usa o envelope visual, não só o centro).
- `DEPLOY_X = 500`: o jogador posiciona na metade esquerda; inimigos na direita.
- Grades: jogador x ≈ 38–488, inimigo x ≈ 512–962; altura de célula ≈ 38,7; largura ≈ 40,9.
- Necromante: centro da célula (linha 3,5; coluna 0,5) da grade do jogador, com `NECROMANCER_POSITION_OFFSET_Y = 34`.
- Portal (entidade que devora cadáveres): x = 500, rompe o chão em y ≈ 259, cabeça em y ≈ 176, raio 46.

**Camadas visuais (de trás para frente)**
1. `#arenaEnvironment` → `#backgroundFar`, `#backgroundMid` (vazios, reservados), `#battlefieldBackground` (arte).
2. `#cv` — canvas transparente com todo o gameplay. **Tremor de tela afeta só esta camada.**
3. `#ambientFxLayer` (vazio hoje).
4. HUD em DOM (`#runHudLayer`, medidores, overlays).

**Ajuste à janela (modo normal, V65/V67/V68)**
- O navegador inteiro é a janela do jogo. O "palco" 1000×560 é escalado uniformemente, centralizado, sem distorção.
- Para ganhar largura em telas mais largas, o palco pode esconder até 70 unidades de altura
  (56 do céu, 14 do rodapé) — proporção efetiva mínima 1000:490.
- A arte de fundo cobre a tela toda (*cover*) e é ancorada no palco na altura y ≈ 380 do mundo,
  para o chão continuar sob as tropas. As sobras são preenchidas pela própria arte, não por barras.
- Existe um cenário procedural de reserva (`buildArenaCache`: placas de pedra, ruínas nas bordas, 4 tochas
  animadas) — hoje só aparece se a imagem falhar.

---

## 4. Assets

**Tudo é embutido; não há nenhuma referência externa** (sem URLs, sem fontes web, sem arquivos de áudio).

| Asset | Onde | Formato | Tamanho |
|---|---|---|---|
| Arte da arena | `ARENA_ART_SRC` (linha 8370) | WebP base64, ~167 KB | 1672 × 941 (≈16:9) |
| Cadáver do Paladino | `PALADIN_CORPSE_IMAGE` (linha 11162) | PNG base64, ~412 KB | 1254 × 1254 (desenhado com recorte 300,312 → 750×655) |

- **Todas as unidades, efeitos, portal, jaula, totens etc. são desenhados por código** (Canvas 2D: `drawUnit`
  → funções por `shape`: paladin, bellringer, cleric, crossbowman, orc, mage…). Não há spritesheets.
- Ícones de UI: SVG inline (paths) e um SVG em data-URI no CSS.
- Fonte: serif do sistema ("Iowan Old Style", "Palatino Linotype", Georgia).
- Áudio: 100% sintetizado (osciladores + ruído) — música por estado/facção, SFX, vozes.

As duas imagens podem ser extraídas do base64 para `res://assets/` sem perdas (já verificado).

**Status da extração**
- Arena: ✔ extraída na Etapa 1 para `assets/art/arena_background.webp`. Os bytes são idênticos ao base64 do
  HTML (SHA-256 `EE74CBFC…216C770B`).
  **Depois foi substituída** por uma arte nova, `assets/art/novocenario.png` (PNG com as mesmas dimensões,
  1672×941), e o `.webp` foi removido. O enquadramento não mudou.
- Cadáver do Paladino: ainda não extraído; fica para a etapa dos cadáveres.

---

## 5. Arquitetura proposta para Godot 4

### Princípios
1. **Manter o mundo lógico 1000×560** como sistema de coordenadas: todos os números do HTML (alcance,
   velocidade, grades, `topY`) passam a valer diretamente.
2. **Separar simulação de apresentação**: dados/regras em scripts puros; nós visuais só leem o estado.
   Isso preserva a possibilidade do bot/laboratório headless mais tarde.
3. **Dados como Resources** (`.tres`), não dicionários gigantes em código.
4. Um sistema por vez; nada de reproduzir as camadas "V64…V97".

### Configuração do projeto
- Mundo lógico 1000×560. `stretch_mode = canvas_items` e `stretch_aspect = expand`: o mundo escala de forma
  uniforme e o espaço extra mostra mais do fundo, como no HTML. O viewport base implementado é 1000×**490**
  para reproduzir o corte máximo de 70 unidades em telas largas (ver `ARCHITECTURE.md`).
- Fundo como `TextureRect`/`Sprite2D` dimensionado para cobrir a área visível (cover), ancorado em y≈380.
- Filtro de textura: linear (a arte não é pixel-art estrita; revisar depois).
- Batalha em passo fixo 1/120 s com acumulador próprio (para 1x/2x/3x), não dependente de `_physics_process`.

### Estrutura de pastas
```
res://
  project.godot
  assets/
    art/novocenario.png
    art/corpses/paladin_corpse.png
  data/                      # Resources (.tres) — etapas futuras
    units/  factions/  relics/  rituals/  schools/
  scripts/
    autoload/
      Config.gd              # W, H, MARGIN, BATTLEFIELD, CFG, RUN_CONFIG, tabelas de progressão
      GameState.gd           # equivalente ao S: fase, onda, essência, listas
      Events.gd              # barramento de sinais (phase_changed, wave_started…)
    core/
      phase_machine.gd       # MENU/PREP/BATTLE/NECROMANCY/VICTORY/DEAD
      battle_clock.gd        # acumulador de passo fixo + velocidade
    combat/                  # núcleo de combate (implementado: ver seção 6)
      combat_unit.gd  combat_sim.gd  unit_view.gd  battle.gd
    data/                    # unit_def.gd (Resource) + unit_catalog.gd (implementados)
    sandbox/                 # sandbox_controller.gd + sandbox_ui.gd (implementados)
    menu/                    # main_menu.gd (implementado)
    arena/
      battlefield.gd         # limites, clamp, point_inside, grids
      formation_grid.gd      # máscara, células, footprints
    resources/               # classes UnitDef, FactionDef, RelicDef… (futuro)
  scenes/
    main/Main.tscn           # raiz: troca telas, instancia Arena + UI
    arena/Arena.tscn         # Background → World (Node2D, y-sort) → FX → debug overlay
    ui/MainMenu.tscn
    ui/RunHud.tscn           # CanvasLayer
```

### Cena da arena
```
Arena (Node2D)
├─ BackgroundLayer (CanvasLayer, layer -10)   # arte fixa, imune ao tremor
│   └─ ArenaBackground (TextureRect/Sprite2D)
├─ World (Node2D)                               # coordenadas 1000×560; recebe o shake
│   ├─ GroundLayer   (áreas, grades, cadáveres)
│   ├─ Units         (y_sort_enabled)
│   └─ FxLayer
├─ DebugOverlay (Node2D, _draw)                 # limites, topY, DEPLOY_X, grades, portal
└─ Camera2D                                     # shake aplicado aqui ou no World
```

### Unidades (decisão futura)
Como o HTML desenha tudo proceduralmente, há duas rotas:
- **A)** portar os desenhos para `_draw()` do Godot (API muito parecida com Canvas 2D) — fiel, trabalhoso;
- **B)** substituir por sprites/animações — mais "Godot", exige arte nova.
Sugestão: placeholders simples primeiro, decidir A/B quando o combate for migrado.
**Em teste (seção 6):** rota A para Guerreiro e Guerreiro Morto-Vivo. É desenho novo, não uma porta 1:1 de
`drawUnit`, com rig de partes e animação por estado.

### Ordem sugerida de etapas
1. **Esqueleto do projeto + arena**: config, fundo, escala/aspecto, limites do campo, debug overlay, grades. ✔ (ver seção 6)
   - **Núcleo mínimo de combate** (1 × 1: alvo, movimento, ataque, dano, HP, morte). ✔ Feito antes da etapa 2,
     a pedido; adianta parte da etapa 4 (ver seção 6).
   - **Menu inicial + Sandbox** (monta lutas com o combate real) + `UnitDef`/`UnitCatalog`. ✔ Adianta parte das
     etapas 3 e 8 (ver seção 6).
2. Máquina de fases + menu mínimo + HUD vazia.
3. Resources de dados (unidades/facções) + placeholder de unidade e posicionamento na grade.
4. Simulação de batalha: ~~movimento, alvo, ataque e passo fixo~~ (núcleo feito) → falta velocidade 1x/2x/3x,
   IA de formação, à distância/projéteis e integração com a fase de batalha.
5. Cadáveres + Necromancia (erguer/sacrificar, portal).
6. Essência, capacidade, lojas, Relíquias, Escola.
7. Áudio (sintetizado via `AudioStreamGenerator` ou arquivos gerados), configurações.
8. Ferramentas: sandbox/admin, bot/laboratório.

---

## 6. Progresso da migração

### Etapa 1 — Esqueleto + arena ✔
Feito:
- Projeto Godot 4.7 (renderer Compatibility), cena principal `scenes/main/main.tscn`.
- Arena (`scenes/arena/arena.tscn`) com as camadas Background, Stage/World (Ground, Entities),
  Stage/Effects e Debug.
- Resolução, escala e resize que reproduzem o HTML V65/V67/V68:
  - palco uniforme, sem distorção;
  - corte máximo de 56 unidades no topo e 14 no rodapé em telas largas;
  - fundo em cover ancorado em y≈380.
- `WorldConfig` concentra as constantes: 1000×560, MARGIN 26, topY 210, DEPLOY_X 500, portal e enquadramento.
- `BattleGrid` porta a geometria de `buildBattleGrid` e a máscara `PLAYER_GRID_MASK` (só leitura).
- Overlay de debug (F3) mostrando:
  - y=210, x=500 e os limites x de 26 a 974 e y de 210 a 534;
  - o portal (500,176) r=46 e o ponto onde ele rompe o chão (y=259);
  - as grades 11×7 e as faixas que podem ser cortadas;
  - um painel com o tamanho da janela, o mundo visível e a escala.
- Validado com capturas reais em 1600×896, 1800×700 e 1000×800.

Correção pós-revisão (F3/F11):
- Os atalhos passaram para o InputMap (tecla física) e são tratados só em `Main._input`.
- No jogo embutido no editor, o F11 é impossível (a janela embutida não entra em tela cheia) e o teclado depende
  do foco. Agora um aviso na tela explica isso.
- Testado com teclas reais em três situações:
  - jogo em janela própria;
  - editor com o jogo em janela própria;
  - editor com o jogo embutido.

Diferenças conscientes em relação ao HTML:
- O fundo procedural de reserva (`buildArenaCache`) não foi portado, porque a arte sempre está presente no projeto.
- As camadas vazias `backgroundFar`/`backgroundMid` do HTML não foram criadas; podem entrar dentro de `Background` quando houver conteúdo.

Fora do escopo (próximas etapas): unidades, combate, IA, HP, cadáveres, Necromancia, Relíquias, HUD, ondas,
drag-and-drop, footprint.

Correção de documentação: a estrutura de pastas proposta (seção 5) ainda citava `arena_background.webp`;
agora cita `novocenario.png`.

### Núcleo mínimo de combate ✔
Feito antes da máquina de fases, a pedido. Uma luta de teste começa sozinha ao abrir o jogo:
**1 aliado × 1 inimigo**.

Feito:
- `CombatUnit` (dado puro): time, posição, raio, HP/HP máx., dano, alcance, intervalo de ataque, velocidade,
  recarga, alvo e estado `IDLE / MOVING / ATTACKING / DEAD`.
- `CombatSim` (dado puro, sem nós): roda em passo fixo de 1/120 s (`BATTLE_STEP` do HTML), com acumulador em
  `Battle` e dt do quadro limitado a 0,05 s como no `frame()` do HTML.
  - **Alvo:** inimigo vivo mais próximo (distância centro a centro), reavaliado a cada passo.
  - **Movimento:** fora do alcance → `MOVING`, anda em linha reta até o alvo e para um pouco dentro do alcance
    (0,85 × alcance, como o corpo a corpo do HTML). A posição é presa à área jogável.
  - **Ataque:** no alcance → `ATTACKING`, não se move; golpeia quando a recarga zera e recarrega com `cd`.
    A primeira recarga é sorteada entre 0 e 40% de `cd` (HTML: `rnd(0, d.cd*0.4)`), com semente fixa (97).
  - **Dano/HP:** `take_damage` tira no máximo o HP restante; morto não recebe dano.
  - **Morte:** HP 0 → `DEAD`: perde o alvo, para de agir e deixa de ser alvo válido. Sem inimigo vivo → `IDLE`.
- Stats do HTML, sem scaling de onda:
  - aliado = `u_warrior` (Guerreiro Morto-Vivo: HP 74, dano 10, alcance 32, cd 1,0, vel. 56, r 12), em (150, 380);
  - inimigo = `warrior` (Guerreiro: HP 70, dano 9, alcance 32, cd 1,0, vel. 56, r 12), em (850, 380).
- Visual temporário (`UnitView`): círculo na cor do corpo do HTML, marca de direção, barra de HP sempre visível,
  flash branco ao ser atingido e sumiço gradual ao morrer.
- Debug de combate (**F4**, desligado por padrão): círculo de alcance, linha até o alvo, e texto com HP, alcance,
  estado e alvo atual. O morto fica marcado com um ✕ e o estado `DEAD`.
- **F9** reinicia a luta. Ao fim, um aviso no rodapé diz quem venceu.
- Teste headless `tests/combat_test.gd` cobrindo aquisição, movimento, ataque só dentro do alcance, dano exato,
  HP 0, `DEAD`, remoção como alvo e o sobrevivente em `IDLE`.

Resultado da luta de teste (determinística): o Guerreiro Morto-Vivo vence com 20/74 HP em ≈12,0 s.
São 13 golpes: 7 × 10 no inimigo e 6 × 9 no aliado.

Validado:
- teste headless com Godot 4.7: OK;
- capturas reais em 1600×896 (Xvfb) andando, atacando e depois da morte, com e sem F4, e após F9;
- nenhum objeto vazado ao sair.

Diferenças conscientes em relação ao HTML (simplificações desta etapa):
- **Sem `TARGET_AI`:** nada de alinhamento, saturação, "stickiness", provocação ou vanguarda. É só a distância.
- **Parar para atacar:** o HTML golpeia assim que `dist ≤ range`, mesmo ainda se aproximando. Aqui o estado é
  exclusivo, `MOVING` ou `ATTACKING`, e a unidade para antes de golpear.
- **Sem separação/colisão entre corpos:** as unidades podem se sobrepor.
- **Clamp simplificado:** usa o raio da unidade, não o envelope do sprite.
- **Sem alvo reserva:** o Necromante não existe ainda, então não há o fallback "inimigo sem alvo mira o Necromante".
- **Estado `IDLE` a mais:** existe além dos três pedidos, para quem ficou sem inimigo vivo.
- **Stats como constantes:** ficam em `Battle` até a etapa de Resources de dados.

Fora do escopo: máquina de fases, menu, GameState/Events, cadáveres, Necromancia, Relíquias, ondas, HUD final,
formação, drag-and-drop, footprint, IA avançada, projéteis, habilidades, Sandbox, Run Lab, velocidade 1x/2x/3x.

### Menu inicial + Sandbox ✔
Feito antes da máquina de fases, a pedido. Referência do HTML: Sandbox/Admin (linhas 13584–15030). Aqui só a
parte mínima foi portada: montar uma luta e inspecionar ou editar unidades por instância.

Feito:
- **Menu inicial** (`scenes/menu/main_menu.tscn`): título MORTIVANE sobre a arte escurecida e dois botões.
  - **Jogar** só mostra "fluxo principal em construção" e o jogo continua no menu.
  - **Sandbox** abre o modo Sandbox.
- **Main** agora troca de tela (Menu ↔ Sandbox). A Arena deixou de ser filha fixa de `main.tscn`.
- **Sandbox** (`scenes/sandbox/sandbox.tscn`) = a **mesma** `arena.tscn` + `SandboxUI` + `SandboxController`.
  - Não há cópia da Arena nem do combate.
  - As tropas são `CombatUnit` da `CombatSim` da `Battle` da Arena, e o desenho é o mesmo `UnitView`.
- **`Battle` virou executor genérico.** Nasce vazia e parada, com `spawn/start/clear`. A luta de teste automática
  1 × 1 saiu do jogo; a mesma luta segue como referência em `tests/combat_test.gd`.
- **Dados:** `UnitDef` (Resource) + `data/units/u_warrior.tres` e `warrior.tres` (stats e cores do HTML).
  `UnitCatalog` lê a pasta. As listas do Sandbox são geradas daí: nova unidade = novo `.tres`.
- **Painel do Sandbox**, no céu da arte, sem cobrir o campo:
  - listas ALIADOS e INIMIGOS; um clique cria a unidade no lado certo, na próxima posição automática;
  - botões Iniciar combate, Reiniciar combate, Limpar arena e Voltar ao menu;
  - linha de estado (preparação, combate com tempo e vivos, resultado).
- **Regras do Sandbox:**
  - o combate **não** começa sozinho;
  - Iniciar exige pelo menos 1 aliado e 1 inimigo;
  - criar tropas e editar atributos só na preparação;
  - Reiniciar recria a montagem no estado inicial, com a mesma semente, então a luta se repete igual.
- **Unidade selecionada** (clique na arena):
  - anel de destaque;
  - painel com nome, lado, estado, HP atual/máx., dano, alcance, intervalo, velocidade e alvo, ao vivo;
  - **edição por instância** de HP máx., dano, alcance, intervalo e velocidade, só na preparação. A edição
    vale desde o início da luta, sobrevive a Reiniciar e não altera a `UnitDef`.
- **Atalhos:**
  - F3/F4/F11 preservados, e o estado de F3/F4 é lembrado entre entradas no Sandbox;
  - F9 virou atalho secundário de "Reiniciar combate";
  - o painel do F3 foi para o rodapé esquerdo.

Validado:
- `tests/sandbox_test.gd` (novo, ponta a ponta na cena real): os 14 itens pedidos.
  - Inclui um clique real de mouse no viewport para a seleção.
  - Inclui entrar e sair do Sandbox 3 vezes sem acumular nós.
- `tests/combat_test.gd`: agora lê os stats de `data/units`; mesmo resultado de antes (20/74 HP, 12,03 s).
- Cena real em 1600×896 (Xvfb): capturas do menu, da preparação com seleção, do combate 4 × 3 com F4 e do resultado.
  - F11 entra e sai da tela cheia.
  - Voltar ao menu funciona.
  - Nenhum erro nem vazamento ao sair.

Limitações atuais:
- **Sem separação entre corpos.** Com várias unidades, todas convergem para o mesmo ponto e se sobrepõem.
  O núcleo não tem colisão; a IA de formação do HTML (`TARGET_AI`) também faz falta aqui.
- Posições só automáticas: sem arrastar, grade funcional ou footprint. Limite de 40 unidades por lado.
- Só 2 unidades no catálogo, e o painel é só texto e campos numéricos.
- Não dá para remover **uma** unidade (só Limpar tudo), nem trocar a semente pela interface.
- Sem pausa/velocidade 1x/2x/3x e sem os presets em `localStorage` que o Admin do HTML tinha.
- Edições por instância não são salvas entre sessões.

Fora do escopo: campanha/Jogar, máquina de fases, GameState/Events, cadáveres, Necromancia, Relíquias, Rituais,
Escolas, loja, ondas, capacidade, formação, footprints, drag-and-drop, rotação, swap, IA avançada, habilidades,
projéteis, versões Sombra, Run Lab.

### Teste visual: unidades desenhadas 100% por código ✔
Objetivo: medir até onde o visual melhora sem sprites. Só duas unidades, usando o combate real sem nenhuma
mudança de regra. O combate de referência continua dando 20/74 HP em 12,03 s.

Feito:
- `UnitVisual` (base) + `CircleUnitVisual` (o círculo, agora padrão para `UnitDef` sem `visual_script`).
- `WarriorVisual`: Guerreiro montado em partes com uma cadeia de `Transform2D`:
  - elmo fechado com fenda horizontal e pluma;
  - ombreiras arredondadas e peitoral segmentado;
  - braçadeiras, grevas com joelheira e botas;
  - espada, capa vermelha e sombra.
- `UndeadWarriorVisual`: o **mesmo rig**, com outra paleta e desgaste:
  - metal escuro, verde-musgo, pluma desbotada;
  - capa rasgada, lâmina lascada, amassado no elmo e rachadura no peitoral;
  - brilho verde na fenda;
  - postura torta.
- Animações por estado real: IDLE, MOVING (pelo deslocamento real), preparação de ataque (pela recarga real),
  golpe (no evento real de dano), HIT (só visual) e DEAD (queda, e o corpo fica no chão).
  O Morto-Vivo anima de forma perceptivelmente mais irregular e bruta.
- `UnitDef.visual_script` escolhe o visual: `warrior.tres` → `WarriorVisual`, `u_warrior.tres` →
  `UndeadWarriorVisual`.
- `UnitView` ficou enxuto:
  - cuida só de seleção (elipse nos pés), barra de HP (acima do elmo, pelo `top_y()` do visual) e debug F4;
  - o corpo é o filho `Body`.
- `Battle` agora repassa eventos visuais: golpe para o atacante, hit para o alvo. (Desde a etapa da Sentinela:
  `attack_performed` → golpe, `unit_attacked` → hit.)
  O clique usa a área do visual, porque o corpo ficou mais alto que o antigo círculo.

Validado:
- `tests/visual_test.gd` (novo): idle, walk sem "deslizar", preparação/golpe/retorno, hit, queda e permanência
  no chão, que o visual não altera stats, e o círculo padrão.
- `tests/sandbox_test.gd`: +3 verificações: visual certo por `UnitDef`, golpe real chegando ao visual e queda
  dos mortos. `combat_test` inalterado e OK. Nenhum erro nem vazamento.
- Cena real em 1600×896 (Xvfb), com capturas de:
  - preparação/idle 3 × 3, seleção + F4, movimento, ataque e morte do Guerreiro;
  - uma folha de poses ampliada;
  - tiras de quadros de walk, ataque (vivo e morto-vivo) e queda do Morto-Vivo.

Limitações atuais:
- **Sobreposição de corpos:** continua (o núcleo não tem separação). Com o corpo mais alto, fica mais visível
  quando dois atacam o mesmo alvo.
- A direção vira na hora (espelhamento), sem animação de giro. Sem alvo, a unidade mantém a última direção.
- O visual reage 1 quadro depois do passo da simulação (≈ 16 ms), por causa da ordem de processamento.
- O primeiro golpe ao entrar no alcance pode vir sem preparação completa se a recarga já estiver quase zerada.
  O braço salta para a pose de preparação e golpeia.
- O "cadáver" é só a pose final da queda: não é o sistema de cadáveres. Ele some em Reiniciar e Limpar, como
  toda unidade.
- Contornos de ~1,5 px e detalhes finos (rachadura, amassado) só são bem visíveis de perto. Na arena, a leitura
  vem da silhueta, da pluma, da capa e da espada.
- Não há sistema geral de animação: os parâmetros vivem em `WarriorVisual` e o Morto-Vivo os sobrescreve.
  Outras unidades continuam como círculo até ganharem um visual.

### Sentinela Arcana e Sentinela Arcana Sombra (mecânica do HTML + visual por código) ✔
Pedido: rework visual das duas versões, preservando a função da unidade. **A unidade não existia no Godot**, e o
núcleo de combate não tinha ataque à distância, projéteis nem habilidades. Para "preservar a função atual", a
mecânica foi **portada do HTML**, só o necessário e só para quem declara. O corpo a corpo não mudou: o
`combat_test` continua dando 20/74 HP em 12,03 s.

Mecânica portada (referências no HTML):
- `arc_battlemage` (linha ~2469): Sentinela Arcana. HP 43, dano 18, alcance 150, recarga 1,25, velocidade 54,
  r 13, `proj:'orb'`, `arcaneSwords`.
- A Sombra é o `u_arc_battlemage` que `registerFactionUnits` gera: mesmos stats, HP round(43 × 0,94) = 40.
  No HTML ela se chama "Sentinela Arcana Morto-Vivo" e tem estado visual `shadow`; aqui o nome é
  "Sentinela Arcana Sombra".
- **Projétil** (`CombatProjectile`, de `fireProjectile` / `updateProjectiles`):
  - velocidades de `PROJ_STYLE` (orbe 340, lâmina 520);
  - persegue o alvo travado, acerta o alvo (r + 6) ou quem estiver no caminho (r + 5);
  - vida de 2,6 s, some fora do mundo (+40), no máximo 200 projéteis.
  - O dano do ataque básico à distância é aplicado **no impacto**.
- **Parada à distância:** 0,92 × alcance (HTML: `dd > range*0.92`).
- **Lâminas** (`SentinelSwords`, de `SENTINEL_CONFIG` / `updateArcaneSwords` / `launchSword` / `swordAnchor`):
  todos os valores e a lógica de ameaça, reação, antecipação, intervalo e recarga iguais ao HTML.

Diferenças conscientes:
- **1ª lâmina lenta (peculiaridade mantida).** No quadro em que o inimigo entra nos 115, o HTML mede aproximação 0
  (`anterior = pd`). Por isso a 1ª lâmina sempre usa a reação lenta (0,55 s) e só a 2ª pode ser rápida. Mantido
  igual e documentado no teste.
- **Antecipação zerada quando a ameaça sai dos 115.** No HTML o `windup` ficava "preso"; aqui ele é zerado.
  Isso só afeta o visual.
- **Âncora sem flutuação/recuo.** A âncora de partida da lâmina na simulação ignora os deslocamentos visuais
  que o `swordAnchor` do HTML somava (flutuação e recuo, < 0,5 r).
- **Partida suavizada.** As lâminas pairam mais alto no desenho do que a âncora da simulação, porque o corpo é
  maior que o do HTML. O `ProjectileView` suaviza a partida em 0,12 s.
- **Sem recuo à distância (kite).** O recuo das unidades à distância quando expostas (`aiKiteVector`, V88) é IA
  avançada e não foi portado; a Sentinela para e atira.
- **Fora do escopo:** relíquias, rituais e escola que interagem com projéteis (perfuração, ricochete, `extra`…)
  e som (`sword_cast`).

Visual (detalhes em `ARCHITECTURE.md`, "Sentinela Arcana"):
- `SentinelVisual` / `SentinelShadowVisual` desenhados por código, a partir da arte conceitual;
- `ArcaneBlade` (a mesma lâmina pairando e em voo), `ProjectileView` (orbe, lâmina, impacto);
- `CodeDrawnUnitVisual`: utilitários comuns extraídos do Guerreiro, sem mudar o visual dele.

Validado:
- `tests/sentinel_test.gd` (novo, 8 grupos): mecânica do HTML e visual das duas versões;
- `sandbox_test` com as Sentinelas no fluxo real (projéteis limpos em Reiniciar, Limpar e ao sair);
- `combat_test` e `visual_test` inalterados e OK; nenhum erro nem vazamento;
- Sandbox real em 1600×896 (Xvfb): folha de poses das duas versões; combate misto (Sentinelas + Guerreiros) com
  preparação, movimento, disparo (tiras de quadros), habilidade das lâminas, morte da viva e morte da Sombra.

Limitações atuais:
- Brilho sem shader: halos são contornos translúcidos, sem mistura aditiva nem partículas.
- Os projéteis ficam na camada `Effects`, sempre acima das unidades (sem y-sort).
- Na escala da arena (≈ 64 px de altura) o rosto e os olhos são pequenos. A leitura vem do chapéu, do manto,
  da joia e das lâminas.
- O chapéu cai sempre para trás. Os restos ficam até Reiniciar ou Limpar (não é o sistema de cadáveres).
- Sem som.

### Fundo animado da arena ✔
Pedido: recriar o cenário da referência como fundo animado em camadas, sem trocar a composição. A referência é
a própria arte da arena (`novocenario.png`; diferença média de 1,6/255, só compressão). Por isso a arte foi
**decomposta em camadas** por uma ferramenta, em vez de redesenhada à mão: essa é a forma de preservar
exatamente a identidade, a perspectiva e as cores.

Feito:
- `tools/arena_backdrop/build_layers.py`: gera as máscaras (céu, vale, castelo, estandartes, velas), a camada de
  cenário com a área atrás dos estandartes reconstruída (inpaint), os recortes e `arena_layers_data.gd`.
- `ArenaBackdrop` (`scenes/arena/arena_backdrop.tscn`) no lugar do antigo `Sprite2D` estático.
  - Camadas: céu (nuvens pintadas fluindo, lua respirando), halo da lua, dois planos de nuvens procedurais em
    parallax (atrás das montanhas), cenário estático, luzes do castelo, dois planos de neblina no vale,
    estandartes balançando, velas e seus halos tremulando.
  - Prioridade de movimento, como pedido: nuvens > neblina > estandartes > velas > castelo > lua.
- **Ajustável:** intensidade global, liga/desliga e força/velocidade por elemento (exportados).
- **Chão e área de combate:** sem nenhuma animação.

Validado:
- `tests/backdrop_test.gd` (novo):
  - ordem das camadas e alinhamento com a arte;
  - camadas que não capturam cliques;
  - posições geradas e importação das máscaras;
  - tempo avançando;
  - intensidade 0 = estático;
  - pausa e ajustes por elemento.
- As outras 4 suítes continuam OK. O Sandbox segue selecionando unidades por clique através do fundo.
- Cena real em 1600×896:
  - quadros em instantes diferentes e comparação do céu estático × animado;
  - recortes de estandarte, velas e castelo;
  - combate sobre o fundo;
  - mapa de movimento: cerca de 3,6% dos pixels mudam entre dois instantes, **0% no chão**.

Limitações:
- As nuvens **pintadas** só oscilam (±7 px); quem atravessa o céu são as nuvens procedurais. Um deslocamento
  contínuo das pintadas exigiria reconstruir o céu por trás delas.
- A lua não se move de verdade; só o halo deriva, menos de 1 px. Mover o disco borraria a lua ao filtrar.
- As árvores secas ficam paradas.
- O menu inicial continua com a arte estática.
- A ferramenta precisa de Python com OpenCV/SciPy, apenas para regenerar as camadas; o jogo não depende disso.

### Fundo da arena reconstruído do zero ✔ (substitui o "fundo animado" anterior)
Pedido: descartar o fundo antigo (céu, lua, nuvens, montanhas, neblina, castelo, torres, ruínas e arcos) e
reconstruí-lo no Godot, mantendo a composição e a identidade da referência. Preservar a arena e os elementos
laterais.

Feito:
- `build_layers.py` passou a extrair **só o primeiro plano**.
  - Critério: pedra, madeira e chão são neutros, e o fundo antigo é azulado. Fica o que é neutro e está ligado
    ao chão ou às bordas.
  - O estandarte é reconstruído por trás (inpaint).
  - As camadas antigas (`scenery.png`, `masks.png`, `sky_flow` e `castle_glow`) foram removidas.
- **Fundo novo, 100% Godot**, em 13 camadas com profundidade de parallax (detalhes em `ARCHITECTURE.md`):
  - céu em gradiente frio com poucas estrelas;
  - lua cheia branco-azulada com halo e pulsação lenta;
  - duas camadas de nuvens estilizadas (bancos longos, topo em escamas, borda prateada perto da lua) deslizando
    da esquerda para a direita;
  - duas cordilheiras góticas;
  - castelo principal e forte menor, com janelas roxas que acendem e apagam uma a uma;
  - pontes em arco e torres partidas;
  - três camadas de neblina, uma no sentido contrário;
  - estandartes com balanço pendular pesado e chamas calmas.
- **Paleta fria** (azul-acinzentado, azul profundo, preto azulado). O roxo aparece só nas janelas, velas,
  estandartes e no desenho do chão.
- **Menu inicial:** usa o mesmo fundo, escurecido. Nenhuma cena usa mais `novocenario.png`.

Validado:
- `tests/backdrop_test.gd` (reescrito):
  - estrutura: ordem das 13 camadas, profundidades crescentes, nenhum uso da arte antiga, geometria das
    silhuetas, lua no alto à direita, camadas sem clique e nada animado entrando no campo;
  - movimento: nuvens para a direita com a do meio mais rápida, neblina em sentidos opostos, velocidades
    baixas, pulsação da lua de 5 a 8 s;
  - janelas: acendem, mas nunca todas juntas;
  - ajustes e parallax.
- As outras 4 suítes seguem OK.
- Cena real em 1600×896:
  - fundo em três instantes;
  - mapa de movimento: cerca de 5% dos pixels mudam em 20 s, **0% no chão**;
  - parallax com ±40 px;
  - menu e combate sobre o fundo.

Limitações:
- A extração do primeiro plano é por cor. Pequenos restos azulados nas bordas do muro podem ter ficado de fora;
  onde isso acontece, o fundo novo aparece e não há buraco.
- Não há câmera móvel ainda: o parallax está pronto, mas só é visto com `view_offset` ou `parallax_preview`.
- As árvores secas laterais são as da arte e ficam paradas.
- Castelo, montanhas e ruínas têm formas fixas no código (listas de picos e peças). Mudar a composição = editar
  essas listas ou os parâmetros das cordilheiras na cena.

### Fundo em nós editáveis + interface do Sandbox na faixa inferior ✔
Pedido: reconstruir o fundo distante e deixar cenário e interface **editáveis no editor do Godot** (nós
separados, Controls reais em `.tscn`), com a UI do Sandbox numa faixa inferior.

Feito:
- **Fundo** (`arena_backdrop.tscn`): antes eram 4 scripts que desenhavam camadas inteiras; agora é uma árvore de
  cerca de 190 nós (ver `ARCHITECTURE.md`, "Fundo da arena").
  - Montanhas (3 profundidades), castelo (penhasco e torres), forte leste e ruínas: um `Polygon2D` por peça, com
    gradiente por vértice e luz de borda em `Line2D`.
  - Nuvens: 3 grupos (Far/Mid/Near) de nuvens individuais `@tool`, mais volumosas, deslizando para a direita
    com velocidades 1,6 · 3,2 · 5 px/s.
  - Névoa: 3 faixas (a do meio em sentido contrário) que respiram.
  - Lua `@tool` com pulsação lenta.
  - Castelo: 24 janelas `CastleWindow` (poucas acesas por vez).
  - Chamas `CandleFlame` como nós.
- Um **gerador** (`tools/arena_backdrop/generate_backdrop_scene.gd`) montou a cena uma vez; a partir de agora a
  `.tscn` é a fonte de verdade.
- **Arquitetura lateral** separada em `LeftArchitecture` e `RightArchitecture` (sai `sides.png`).
- **Interface do Sandbox** em `sandbox_ui.tscn` + `sandbox_theme.tres`:
  - faixa inferior (22%) com Aliados · Controles · Unidade selecionada · Inimigos;
  - o script só liga os nós aos sinais; a API do `SandboxUI` não mudou.
- **`Arena.set_bottom_inset`:** o mundo é enquadrado acima da faixa, com zoom 0,89 em 1600×896, e o campo inteiro
  fica visível.
- F3 (painel) e avisos do `Main` voltaram para o topo.

Validado:
- `backdrop_test` (reescrito):
  - estrutura: ordem das 21 camadas; nada criado em runtime (todo nó pertence à cena); montanhas como
    `Polygon2D` com gradiente, as distantes mais claras;
  - nuvens: individuais, com velocidades crescentes e volta fora da tela;
  - névoa em sentidos opostos, fora do campo;
  - lua; janelas com poucas acesas;
  - intensidade 0 e parallax.
- `sandbox_test`: +3 verificações da faixa inferior e do campo visível acima dela.
- As outras 3 suítes seguem OK. Nenhum erro nem vazamento.
- Cena real em 1600×896: menu, Sandbox vazio e com seleção, combate, F3+F4, mapa de movimento (cerca de 6% dos
  pixels mudam em 20 s, **0% no chão**) e parallax.

Limitações:
- **Não foi possível abrir o editor do Godot neste ambiente** (sem Vulkan). As cenas foram validadas no jogo e
  nos testes, mas não visualmente dentro do editor.
- Os scripts `@tool` (nuvem, lua, janela, chama, névoa) só desenham e sincronizam; as animações não rodam no
  editor.
- A luz de borda (`Rim`) é calculada para a composição gerada. Depois de mover muito um pico, ela pode aparecer
  por dentro de outro pico; ajuste ou apague a `Line2D`.
- A interface é pensada para o viewport de 1000 unidades de largura; em janelas muito estreitas os painéis
  apertam (os textos longos quebram linha).
- A imagem de referência mencionada não veio anexada; a composição seguiu a das etapas anteriores.

### Investigação: cliques no menu (relato de regressão)
Relato: após a etapa anterior, clicar em Jogar/Sandbox não entrava. Com cliques reais de mouse (X virtual +
xdotool), o commit 7ea0e22 entra no Sandbox rodando sozinho **e** embutido no editor (F5, aba Game); não foi
possível reproduzir. Ficou o teste `menu_click_test` (eventos de mouse pelo viewport, pressionar e soltar em
quadros separados; falha se um Control invisível tomar o clique).

### Sombras necromânticas + coerência do cenário ✔
Pedido (com imagens de referência no clima dos "soldados sombra"): unidades revividas com identidade forte de
"sombra necromântica" — corpo escuro, energia roxa, aura/fumaça/olhos, sem virar mancha e sem perder a classe —
como regra reutilizável; cenário mais coerente (castelo encaixado na montanha, nada flutuando); estandartes mais
fluidos e luzes menos chamativas. Sem mudar combate, números nem fluxo do Sandbox.

Feito:
- **Regra reutilizável** (ver `ARCHITECTURE.md`, "Versões sombra"): `ShadowStyle` (`data/visuals/shadow_style.tres`)
  converte a paleta viva (`convert`), `ShadowFX` desenha aura, névoa no chão, fumaça, fissuras e olhos, e
  `CodeDrawnUnitVisual` ganhou `shadow`/`_apply_shadow_style`/`_draw_with_rim` (borda roxa só na silhueta
  externa). `UnitDef.shadow_style` permite um estilo por unidade.
- **Guerreiro Sombra** (era "Guerreiro Morto-Vivo" verde): `ShadowWarriorVisual` (renomeado de
  `UndeadWarriorVisual`), mesmo rig; armadura grafite violeta, capa quase preta com resto do vermelho, olhos
  roxos na fenda, fissuras de energia no peitoral e no elmo, pluma → chama espectral, fio da espada aceso,
  névoa/aura/fumaça; postura pesada em vez de cambaleante; ao morrer a energia se apaga e o corpo solta fumaça.
  Nome exibido: "Guerreiro Sombra" (stats inalterados).
- **Sentinela Arcana Sombra**: paleta agora convertida pela mesma regra (selo arcano azul mantido), borda roxa,
  olhos pela regra, fissuras na saia, aura, névoa no chão e fumaça no capelete; animações e mecânica iguais.
- **Cenário** (gerador + cena regenerada; só os `unique_id` e as peças abaixo mudam):
  - `MainCastle` 18 px mais baixo; rochedo com platô mais largo; muralha e torres assentam na rocha (antes a
    ponta direita da muralha ficava sobre a encosta, com vão embaixo); idem torre esquerda do `EastKeep`;
  - pontes do castelo passam a ser filhas do castelo (mesmo parallax) e descem até o chão; aqueduto e pilares
    partidos descem até o chão, com entulho no pé e duas colinas baixas na frente.
- **Animações:** estandarte com vento que propaga pelo tecido (atraso por altura), rajadas lentas, ondulação
  na ponta e barra que sobe um pouco; velas com flicker sutil (antes ±10–40%, agora ±4–12%, mais lento);
  tremor das janelas do castelo reduzido (±10% rápido → ±5% lento).

Validado:
- 7 suítes OK: combat, visual, sentinel, sandbox, backdrop, menu_click e a nova `shadow_visual_test`.
- `backdrop_test` ganhou as verificações "nada flutua"; rodadas contra a cena antiga, elas falham exatamente
  nos problemas relatados (muralha/torres fora da rocha, pontes e pilares acabando no ar).
- Capturas no jogo real (1600×896): sombras legíveis no tamanho da arena (corpo escuro, borda roxa, olhos) e em
  close 5×–14×; vivas inalteradas; combate e mortes; fundo antes/depois.
- O editor do Godot abre neste ambiente com `--rendering-driver opengl3` (X virtual): o jogo foi rodado pelo
  editor (F5, embutido); a edição das cenas dentro do editor não foi exercitada.

Limitações:
- Regenerar o fundo pelo gerador sobrescreve edições feitas na `.tscn` (até agora não havia nenhuma: a
  regeneração da versão anterior só mudava os `unique_id`).
- O efeito "sombra" é por código (sem shader de contorno): a borda da silhueta é o corpo desenhado duas vezes,
  o que dobra o custo de desenho das sombras (ainda barato).
- Só existem duas classes hoje (Guerreiro e Sentinela); paladino/healer etc. usarão a mesma regra quando
  forem criados (`convert(cor, keep)` para os acentos da classe).

### Paladino (vivo e Sombra) ✔
Pedido (com a arte conceitual "Paladino Vivo / Paladino Sombra"): portar o Paladino **exatamente como no
HTML** — sem mudar mecânica, números ou função — com visual por código fiel à referência, animações pesadas e
legíveis, versão Sombra pela regra necromântica (dourado preservado) e integração ao Sandbox.

Portado do HTML (`MortivaneV97.html`):
- `FACTION_UNITS.sac_paladin`: HP 120, dano 13, alcance 34, recarga 1,2, velocidade 44, raio 14, corpo a
  corpo, `ability: 'paladin_taunt_shield'`. O `u_sac_paladin` sai de `registerFactionUnits` (mesmos stats e
  habilidade, HP round(120 × 0,94) = **113**). Nome no Godot: "Paladino Sombra" (no HTML, "Paladino Morto-Vivo").
- `PALADIN_CONFIG` + `tickPaladinCombat` + `paladinShieldDamage` + `lockPaladinShieldFacing` + `tauntTarget`/
  `clearTaunt` (em `nearestFoe` e em `killUnit`) → `PaladinTaunt` + ganchos na `CombatSim` (ver
  `ARCHITECTURE.md`, "Combate"). Mesma ordem do HTML: a passada do Paladino roda antes das unidades.
- Fora do escopo (ainda não existem no Godot, então não entram): `cost`/`essence`/`wc`/`from`/`tier`
  (economia e ondas), `stun` e `controlImmune` (nenhuma unidade atual tem), relíquias (`relicShield`), métricas
  (`behaviorMetric`), sons (`paladinCue` toca sons no HTML) e as camadas de dano que o Paladino não usa
  (`incomingMul`, `shield`, `tempHp`, espinhos). O corpo a corpo segue o núcleo mínimo (sem separação
  entre unidades).
- Diferença de apresentação consciente: o HTML desenha o Paladino num rig 3/4 com lado do escudo fixo
  (nunca espelha a arte) e o cadáver é um PNG; aqui ele segue a convenção das outras unidades (espelha pela
  direção) e o cadáver é o próprio rig no chão, com escudo e espada soltos.

Feito:
- `PaladinVisual` / `ShadowPaladinVisual` (desenho 100% por código) e `PaladinLook` (Inspector); tabelas de
  animação e de diferenças Vivo × Sombra em `ARCHITECTURE.md`.
- Eventos de habilidade para o visual: `UnitVisual.on_ability_event(kind)` (via `Battle`/`UnitView`).
- `UnitDef.visual_look` (opcional, genérico).
- Sandbox: "Paladino" (inimigos) e "Paladino Sombra" (aliados) aparecem sozinhos (o catálogo lê a pasta).

Validado:
- 8 suítes OK (combat, visual, sentinel, sandbox, backdrop, menu_click, shadow_visual e a nova paladin_test);
  `shadow_visual_test` agora cobre também o par Paladino/Paladino Sombra. Nenhum vazamento.
- `paladin_test`: mutação de teste (redução 75% → 50%) faz o teste falhar; a luta de referência do Guerreiro
  bate com a medida no commit anterior (`ally 20/74 12.025 13`).
- Capturas em 1600×896 no Sandbox real (provocação, golpes, mortes) e folha de poses ampliada (idle, walk,
  preparação, golpe, provocação, escudo, bloqueio, hit, caindo, no chão), mais comparação de escala.

Limitações:
- O anel da provocação é desenhado no raio real (115); em telas cheias de Paladinos isso pode poluir —
  `PaladinLook.show_taunt_ring` desliga.
- Ainda não há sistema de cadáveres: o corpo no chão é só apresentação do visual.
- Os parâmetros do Inspector ficam num recurso (`paladin_look.tres`); as partes do corpo continuam no código
  (não são nós separados).

### Protótipo: sprite sheet piloto do Paladino Vivo (3/4, frame a frame) — aguardando validação
Pedido: sprite sheet piloto do Paladino Vivo, fiel às pranchas aprovadas (A/B/C), em 3/4 estilizado 2.5D,
só Idle (6), Walk (8) e Attack (8), para validar no Godot escala, fluidez, silhueta e perspectiva.
Decisão (com o usuário): **renderizar pelo próprio Godot** em vez de gerar com IA — consistência e alinhamento
garantidos entre frames; acabamento ilustrado/vetorial (não é pintura à mão como as pranchas).

Feito:
- `tools/sprites/render_paladin_pilot.gd`: pintor 3/4 (proporções da prancha: elmo grande com visor em T e
  crista, auréola com estrelas, ombreiras em lâminas com bordas douradas, peitoral pesado, tabardo com sol,
  saiote, capa com forro, escudo grande com espessura e sol, espada larga), IK nos pés e no braço da espada,
  keyframes: idle (respiração ~1 px), walk (passada curta, 2 px de subida, escudo estável, espada com atraso,
  capa/tabardo atrasados), attack (guarda · preparação · espada recua · tronco gira · início · impacto com arco
  dourado sutil · follow-through · recuperação).
- `assets/sprites/paladin_live_pilot/`: sheet 2048 × 768, 22 frames avulsos, sombra separada, JSON do contrato,
  `SpriteFrames`.
- `scenes/prototypes/paladin_sprite_pilot.tscn`: arena real, as 3 animações na escala de jogo ao lado do
  Paladino atual, um Paladino andando a 44/s com o walk sincronizado, versões ampliadas com o pivô marcado
  (Espaço pausa, ←/→ frame a frame, S sombra).

Não feito (por pedido): Hit, Defesa, Provocação, Morte, Paladino Sombra; nada ligado ao combate/Sandbox.

Limitações: acabamento vetorial com sombreado por vértice (sem textura pintada); o escudo é visto sempre pela
face (3/4 fixo); a espada no frame "espada recua" passa por cima da ombreira; 256 px de frame é pouco para
ampliar muito além de 2×.

### Paladino Vivo com a sprite sheet aprovada ✔ (substituída pelas sheets novas, abaixo)
Pedido: integrar a sprite sheet do Paladino Vivo (arte aprovada) no lugar do visual por código, com
AnimatedSprite2D/SpriteFrames, sem mudar mecânica; Paladino Sombra fica como está.

Leitura da sheet (1125 × 844, fundo transparente, sem grade): 36 frames em 6 linhas — idle 6 · walk 8 ·
attack 6 · linha 4 com defend 4 (ergue o escudo, dois clarões, guarda) + taunt 3 (espada erguida com halo,
depois apontando) · hit 3 · death 6. **O ataque tem 6 frames** (não 8); defend e taunt dividem a mesma linha;
o 1º frame do hit já tem o clarão do impacto. Nenhum frame foi inventado.

Feito:
- `tools/sprites/slice_paladin_live.py` fatia a sheet (ver `ARCHITECTURE.md`): atlas 320 × 208 por célula com
  pivô (160, 192) nos pés, frames avulsos, JSON com retângulos e pivôs de origem, `paladin_live_frames.tres`.
- `PaladinSpriteVisual` + cena; `UnitDef.visual_scene` (tem prioridade sobre `visual_script`); `UnitView`
  instancia a cena. `sac_paladin` usa a cena; o `PaladinVisual` fica como alternativa no mesmo `.tres`.
- `PaladinFx`: barreira/anéis extraídos do `PaladinVisual` (os dois visuais usam o mesmo código).
- Mecânica, stats, provocação, Escudo Sagrado, seleção, barra de HP, debug e Sandbox inalterados.

Validado: 9 suítes OK (nova `paladin_sprite_test`: recursos e loops, pivô ±4 px em todos os frames de pé,
escala, cada estado pela lógica real, impacto no instante do dano, morte parada no último frame, Sandbox com
seleção/combate/Reiniciar/Limpar); capturas 1600×896 dos estados e do Sandbox.

Limitações:
- A arte é de ~135 px de altura; no jogo aparece reduzida ~2× (mipmaps). Ampliar muito acima de 1× borra.
- O walk da sheet é um ciclo no lugar sem medida de passada; o ritmo segue a velocidade real
  (`walk_reference_speed` = 44), mas um leve deslizar dos pés pode aparecer — ajustável no Inspector.
- Frame de impacto escolhido na arte (3º frame com o arco = índice 3) — ajustável (`attack_impact_frame`).
- A morte na sheet cai para a direita da arte; espelhada no inimigo. Sem sistema de cadáveres (só visual).
- A sheet piloto renderizada por código (`assets/sprites/paladin_live_pilot/`, cena de protótipo) continua no
  repositório como referência; não é usada pelo jogo.

### Paladino Vivo com as sprite sheets novas (idle, walk, attack, defend, death) ✔ (substituído pelo rig 2.5D, abaixo)
Pedido: substituir o visual do Paladino Vivo pelas cinco sheets novas (estilo cartunesco mais polido e
robusto), organizadas numa pasta própria, com AnimatedSprite2D/SpriteFrames, pivô nos pés, escala coerente,
sem mudar mecânica, stats ou comportamento.

Leitura das sheets (2000 × 667 cada): idle 8 · walk 8 · attack 8 · defend 8 (duas linhas de 4) · death 8.
- **O fundo já vem transparente** (alfa com borda suave), não preto: nenhuma limpeza de cor foi necessária.
- As sheets vieram em **escalas diferentes** (defesa ~20% maior que o idle, caminhada ~13%; ataque e morte
  um pouco menores). O fatiador normaliza tudo pelo elmo do idle.
- No ataque os arcos invadem o frame vizinho; o fim do arco do 4º frame fica atrás da capa do 5º na
  própria arte — o corte segue a capa e o arco some suavemente.
- A sheet de defesa: linha de cima = guarda → giro do escudo (arco) → clarão da bênção → faíscas; linha de
  baixo = guarda firme (respirando).

Feito:
- `assets/units/paladin/`: `source/` com as 5 sheets (PNG sem perdas; `.gdignore`), `paladin_atlas.png`
  (1968 × 930, mipmaps), `paladin_frames.tres` (SpriteFrames), `paladin_frames.json` (contrato e medidas).
- `tools/sprites/slice_paladin_sheets.py` (ver `ARCHITECTURE.md`): cortes, escala por sheet, pivô por
  registro (sem tremedeira), células 246 × 186 com pivô (123, 161).
- Animações: `idle`, `walk`, `attack`, `defend`, `defend_hold`, `defend_block`, `taunt`, `death`.
- `PaladinSpriteVisual`: nova máquina de defesa (espera = defend frame 0; escudo = defend → defend_hold em
  loop; bloqueio = defend_block → defend_hold), impacto do golpe no frame 4, dano = pisca + recuo (sem hit),
  escala 0,37, pivô/célula novos na cena.
- Removidos a sheet anterior (`assets/sprites/paladin_live/`) e `tools/sprites/slice_paladin_live.py`: o
  visual antigo não é mais usado.
- Mecânica, stats, provocação, Escudo Sagrado, seleção, barra de HP e Sandbox inalterados; Paladino Sombra
  inalterado.

Validado: 9 suítes OK (`paladin_sprite_test` reescrita: animações e loops do contrato, célula/pivô/impacto
iguais ao JSON, chão no pivô ±2 px em todos os frames de pé, pés do idle centrados, cada estado pela lógica
real, bloqueio e volta à guarda, dano só pisca, morte parada no frame 7, Sandbox); capturas 1600×896 dos
estados e do combate real.

Limitações:
- Não há sheet de **hit** nem de **provocação**: o dano só pisca/recua e a provocação reaproveita o giro
  do escudo da sheet de defesa (o anel do raio real continua).
- O `defend_hold` é a respiração desenhada na arte: o 2º frame tem a postura um pouco mais aberta (o
  escudo anda ~6 unidades no jogo). É da arte; dá para reduzir tirando esse frame ou baixando o FPS.
- A escala entre sheets foi medida pelo elmo (erro estimado ≤ 3%). Se alguma animação parecer maior ou
  menor, ajustar `scale` da sheet no topo do fatiador.
- O walk é um ciclo no lugar; o ritmo segue a velocidade real (`walk_reference_speed` = 44).
- A morte muda de pose bastante entre frames (queda); o alinhamento é por sobreposição com o frame anterior.

### Paladino Vivo reconstruído 100% por código em rig 2.5D ✔ (substituído pelo PaladinLiveVisual, abaixo)

**Pedido.** Reconstruir do zero o visual do Paladino Vivo a partir de três imagens de referência oficiais.
- 100% desenhado por código no Godot, sem sprite sheet e sem usar as imagens no jogo.
- Rig 2D com fake 2.5D, 8 direções com leitura real e todas as animações pedidas.
- Transições contínuas.
- Espada SEMPRE na mão direita e escudo SEMPRE no braço esquerdo.
- Mecânica idêntica.
- Paladino Sombra e demais tropas inalterados.

**Abordagem.** Esqueleto num espaço 3D do corpo, projetado por uma câmera levemente de cima (detalhes em `ARCHITECTURE.md`).
- Peças low-poly facetadas, que imitam o sombreamento facetado das referências.
- Ordenação por profundidade a cada quadro.
- As direções da esquerda são giros de verdade: a mão da espada nunca troca, nem por espelho.
- Um animador lê a simulação e compõe camadas: locomoção, ação, reações e morte, com molas para o movimento secundário.

**Feito.**
- `scripts/visuals/units/paladin/` com 8 scripts:
  - `PaladinRigVisual` (cola);
  - `PaladinAnimator` (estados, direção, transições, sincronia);
  - `PaladinPoseLibrary` (poses-base por direção + clipes);
  - `PaladinRig` (esqueleto, projeção, desenho);
  - `PaladinModel` e `PaladinMesh` (26 ossos, 42 peças, decalques);
  - `PaladinEffects` (efeitos fora do corpo);
  - `PaladinRigLook` (Inspector).
- `scenes/units/paladin_rig_visual.tscn` e `data/visuals/paladin_rig_look.tres`.
- `sac_paladin.tres` usa o rig: `visual_scene`, e também `visual_script` para funcionar sem a cena. Stats iguais.
- 16 estados (ver tabela em `ARCHITECTURE.md`):
  - IDLE;
  - WALK em 8 direções;
  - ATTACK com 3 variantes (horizontal no RIGHT, de cima no UP_RIGHT, de baixo no DOWN_RIGHT);
  - HIT, PUSH, TAUNT, GUARD_READY, SHIELD_ACTIVE, BLOCK;
  - DEATH → CORPSE, com a espada e o escudo se soltando e caindo ao lado.
- **Push.** A simulação não tem empurrão hoje. O animador reage sozinho a qualquer deslocamento real que a caminhada não explique, e há `on_pushed(dir)` para mecânicas futuras. A animação nunca desloca a unidade.
- **Sandbox.** Fileira "Prévia (só visual)" para a tropa selecionada, com todas as animações.
  - Só na preparação.
  - Iniciar desliga a prévia; Reiniciar e Limpar recriam o visual.
  - `SandboxUI.preview_requested` e `SandboxController.preview_selected`.
- **Debug.** Com F4, o Paladino mostra direção, yaw, estado, progresso, direção do alvo e variante do golpe.
- **Testes.**
  - Nova suíte `paladin_rig_test`.
  - `paladin_test` e `shadow_visual_test` passaram a comparar o Sombra com o `PaladinVisual` por código, a base dele, que continua existindo.
  - `paladin_sprite_test` testa a cena de sprites como alternativa.

**Validado: 10 suítes OK.** A nova suíte cobre:
- stats, provocação e escudo inalterados;
- a mesma luta rodada só na simulação e no Sandbox com os visuais (inclusive com empurrões, hits e bloqueios visuais extras disparados durante a luta) tem HP, posição, estado, recarga, provocações e bloqueios idênticos passo a passo;
- o visual não altera a `CombatUnit`;
- espada no punho direito e escudo no esquerdo nas 8 direções × 11 estados, sem espelho;
- andar nas 8 direções vira o corpo;
- cada estado vem do estado real, e o impacto do golpe cai no evento de dano;
- no Sandbox: prévia, Reiniciar, Limpar e saída sem nós sobrando;
- custo de CPU por Paladino.

Capturas grandes dos 16 estados, folha comparativa e capturas em escala real no Sandbox.

**Limitações.**
- É uma interpretação procedural: as referências são pinturas com microdetalhes (placas sobrepostas, cinto
  diagonal, frisos em arco no peitoral) que ficaram simplificados em malhas low-poly. Na escala da arena
  isso não aparece; em close o estilo é "facetado" e não pintado.
- A ordenação é por peça (não por pixel): em poses extremas uma peça pode passar na frente de outra por uma
  fração de segundo (ex.: braço cruzando o tronco no fim do golpe).
- O Paladino Sombra continua no visual por código anterior (fora do escopo); ele não herda o rig novo, então
  vivo e sombra hoje têm silhuetas diferentes. Uma etapa futura pode aplicar a regra `ShadowStyle` ao rig.
- **Push.** Não existe mecânica de empurrão na simulação. A reação está pronta e testada, mas em combate
  normal só aparece se algum dia a simulação deslocar a unidade.
- **Morte.** O corpo gira até ~70° de lado antes de cair, para o cadáver ficar atravessado e legível.
- **Desempenho.** O desenho é montado em GDScript a cada quadro, ~1–2 ms de CPU por Paladino. Com dezenas
  de Paladinos na tela pode valer cachear quadros ou reduzir facetas (`PaladinModel`).
- **Arquivos fora de uso.**
  - As sprite sheets e a cena de sprites continuam no projeto como alternativa.
  - `PaladinVisual` continua existindo porque é a base do Sombra.

### Tropas leves: malha estática com ossos (desenho leve) ✔ (aguardando validação)

**Pedido.** Deixar as tropas leves para o jogo (FPS e RAM), podendo reformular cada uma mantendo o design e o
sentido; o que mais pesava eram as partes das tropas (no PC do usuário, ~50 ms de CPU do `_draw` + ~12 ms de
draw calls com 80 unidades).

**Feito.**
- Base nova em `scripts/visuals/units/lite/`:
  - `LiteBuilder`: formas → triângulos com cor e borda suavizada como a do motor.
  - `LitePart`: peça pronta.
  - `LiteSkin`: malha estática do tipo + esqueleto 2D por unidade.
  - `LiteFx`: clarão, escurecimento e alfa por shader, com materiais compartilhados.
  - `LiteShadowParts`: olhos e fissuras da sombra.
- `CodeDrawnUnitVisual` ganhou o "modo de montagem": as funções `_draw_*` de cada tropa montam as peças UMA vez
  por tipo. Cada unidade tem 1 comando (a malha), e a pose só move os ossos.
- As 6 tropas foram convertidas (Guerreiro, Sentinela, Paladino e as sombras). O Paladino Vivo mantém a pose
  2.5D, com a projeção afim das peças planas e uma malha por ordem de profundidade.
- O que mudava de forma a cada quadro virou transformação: capa/manto por cisalhamento, abas girando, botas
  deslizando, joelho dobrando. Fumaça, brasas, lâminas voltando, anéis e brilhos crescem e encolhem em vez de
  esmaecer. Todo o resto é a mesma geometria de antes.
- Testes: `redraw_test` e `corpse_freeze_test` seguem o novo contrato (a pose anda pelos ossos, sem redesenho).
  Os testes de pose, gameplay e 8 direções não mudaram.
- Ferramenta nova: `tools/bench/unit_gallery.gd` (6 tropas × 9 poses, de perto).

**Resultado** (este ambiente; detalhes em `RENDER_REPORT.md`):
- Draw calls por unidade: 72–253 → **1** (+ a barra de HP). A cena de 80 unidades dos prints: 10.817 → **536**.
- CPU por unidade (atualização + desenho, headless):

  | tropa | antes | agora |
  |---|---|---|
  | Guerreiro | 0,09 ms | 0,011 ms |
  | Guerreiro Sombra | 0,40 ms | 0,040 ms |
  | Sentinela | 0,19 ms | 0,032 ms |
  | Sentinela Sombra | 0,49 ms | 0,058 ms |
  | Paladino | 0,32 ms | 0,115 ms |
  | Paladino Sombra | 0,41 ms | 0,043 ms |

- RAM: cada tipo é uma malha de 4 a 16 mil vértices, compartilhada (≈ 3 MB para os 6 tipos). Cada unidade guarda
  só o esqueleto (13–67 ossos), em vez de 70–250 comandos de desenho refeitos a cada quadro.

**Validado.** 17 suítes OK. As galerias antes/depois mostram o mesmo visual.

**Limitações.**
- A fumaça e os brilhos agora crescem/encolhem em vez de esmaecer. A capa da Sombra não tremula mais nas pontas.
  A pulsação das fissuras ficou fixa.
- O Paladino Vivo ainda é a tropa mais cara de CPU (pose 2.5D).
- O FPS real precisa ser medido no PC (F6/F7): aqui o render é por software.

### Diagnóstico do render das unidades (simulação parada) ✔ (aguardando validação)

**Pedido.** Pelos prints do painel F6 no PC do usuário, 80 unidades visíveis com a simulação parada dão 13 FPS e
10.814 draw calls. Descobrir de onde vêm os draw calls (por tipo de unidade e por parte), comparar com um quadrado
por unidade e propor a solução de maior impacto e menor risco, **sem mudar** gameplay, IA, stats, combate nem
aparência.

**Feito** (só medição; detalhes em `RENDER_REPORT.md`):
- `tools/bench/render_probe/`: cópia instrumentada do projeto em que todo `draw_*` dos visuais é contado por parte
  e tipo e pode ser desligado por categoria. O projeto real não muda.
- `tools/bench/render_breakdown.gd` + `render_matrix.sh`: draw calls, objetos e primitivas por tipo de unidade e por
  categoria; modos normal / congelado / quadrados / lote simulado / oculto.
- **F7 no Sandbox** (`RenderCompare`, debug): os mesmos modos no jogo, para medir no PC do usuário com o F6.

**Resultado.**
- Cada comando de desenho vira 1 draw call; linhas suavizadas viram 3.
- Draw calls por unidade: Guerreiro 72, Guerreiro Sombra 189, Sentinela 119, Sentinela Sombra 218,
  Paladino 180, Paladino Sombra 253.
- Nas sombras: silhueta roxa +52–58 e VFX +26–50.
- Quadrados: 10.817 → 377 draw calls, e o quadro volta ao do cenário vazio.
- Lote simulado: 10.817 → 456.
- **Proposta**: um triangle array por unidade no `_draw` (mesma geometria e mesma ordem de hoje), começando por
  Guerreiro e Guerreiro Sombra.
- **No PC do usuário (F7)**: normal 78,7 ms; congelado 28,7 ms; quadrados e lote simulado 16,7 ms (vsync).
  - O maior custo lá é a CPU do `_draw` (~50 ms); os draw calls custam ~12 ms.
  - O profiler mostra ~75% do `_draw` no caminho genérico por peça (busca no DrawCache com hash do array de pontos,
    `draw_mesh` por peça, `_c()`).
  - Proposta revista: lote por unidade com geometria pré-montada, sem busca por hash (ver `RENDER_REPORT.md`).

**Validado.** 17 suítes OK (nova: `render_compare_test`).

**Limitações.**
- Sem GPU aqui: os tempos com render são de software. O ganho real se mede no PC com F7.
- O headless tem piso de 6,9 ms por quadro.

### Painel de desempenho do Sandbox (F6) ✔ (aguardando validação)

**Pedido.** Ferramenta de debug para medir o desempenho no PC do usuário: painel discreto no Sandbox com FPS,
quadro, aliados/inimigos, cadáveres, total, draw calls, objetos/nós e, se houver instrumentação, sim / alvo /
update visual. Sem mudar gameplay, IA, stats, visual das unidades nem combate.

**Feito.**
- `PerfOverlay` (`scripts/debug/perf_overlay.gd`): `CanvasLayer` 60, painel no topo esquerdo, fundo
  semitransparente, fonte 11, não bloqueia cliques, atualiza 5×/s, desligado por padrão.
- Tecla **F6** (`perf_overlay_toggle`): o F4 sugerido já é o debug de combate. `Main` trata e lembra o estado.
- Instrumentação mínima: `Battle.sim_usec_last_frame` (2 leituras de relógio por quadro) e
  `UnitView.profiling`/`stat_usec` (cronômetro no `_process` só com o painel ligado). Alvo usa os contadores
  que a CombatSim já tinha (taxa por segundo).
- `tests/perf_overlay_test.gd`; `tools/bench/perf_overlay_shots.gd` (capturas com render).

**Validado.** 16 suítes OK. Capturas com o painel ligado: 10×10, 20×20, 40×40 Guerreiros, Sentinelas e Paladinos.

**Limitações.**
- Draw calls/objetos são N/A sem render (headless).
- `_draw` e render não entram no painel (ver `tools/bench`).
- As capturas daqui usam render por software, então os FPS delas não representam uma GPU.

### Otimização 1 — 40 × 40 (6 etapas incrementais) ✔ (aguardando validação)

**Pedido.** Primeira rodada de otimização a partir do profiling: melhorar muito o 40×40 sem mudar
comportamento, stats, habilidades, aparência, morte nem resultado da batalha. Etapas na ordem pedida, cada
uma medida (FPS, quadro, sim, alvo, update visual, `_draw`, draw calls).

**Feito** (um commit por etapa; detalhes e tabelas em `OPTIMIZATION_REPORT.md`):
0. Base: referência congelada da CombatSim (`tests/support/`), paridade de 40 lutas, contadores baratos na
   CombatSim, bench que envolve a simulação real.
1. Mortos fora do targeting: listas de ativos por time. 40 vivos × 40 cadáveres: 384 mil → 0 candidatos/s.
2. Cadáveres estáticos: o UnitView congela o cadáver assentado (sem update nem redraw).
3. Redraw dos vivos: anel/barra só por mudança; `DrawCache` (geometria do motor portada, pixels idênticos):
   draw calls 40×40 Guerreiros 10.977 → 6.327; `_draw` com render 63,8 → 14,6 ms.
4. Targeting com cache de garantia (resultado idêntico): varreduras −81% a −98%.
5. Paladino: pose 3D descartada deixa de ser montada; trilhas constantes calculadas uma vez. Update visual
   −48%.
6. `Battle.MAX_SIM_STEPS_PER_FRAME = 4`: nada de 6 passos num quadro lento (câmera lenta em vez de cascata).

**Validado.** 15 suítes OK (novas: `corpse_freeze_test`, `redraw_test`, `sim_pacing_test`;
`bench_parity_test` reescrito). Pixels: etapa 3 = 0 diferenças; etapa 5 = 1 pixel (1/255).

**Resultado 40×40** (headless): Guerreiros 62 → 83 FPS, misto 49 → 74, Paladinos 19 → 32. Com render
(sem a rasterização por software): Guerreiros 77,8 → 26,1 ms, misto 95 → 47 ms, Paladinos 157 → 135 ms.

**Limitações / pendências.**
- Cadáver congelado: param micro-animações (chapéu da Sentinela; névoa e fumaça das sombras).
- Abaixo de 30 FPS o jogo anda mais devagar que antes (por projeto da etapa 6).
- O desenho do Paladino segue caro (~1,4 ms e ~181 draw calls por unidade): próximo passo é desenhar as
  peças rígidas no espaço local para o cache funcionar.
- Sem GPU no ambiente: FPS com render é de software.

### Profiling e stress test do combate (só medição) ✔ (aguardando validação)

**Pedido.** Descobrir, com números, por que o FPS cai com muitas unidades dos dois lados — sem otimizar e sem
mudar combate, IA, stats, targeting ou visual. Cenários 10×10 a 50×50 (incluindo 40×2, 2×40, 40×20, 20×40),
perfis Guerreiros / Sentinelas / misto (+ Paladinos à parte), fases parado / movimento / alvo / combate,
comparações visual × lógica, e relatório com evidência, hipótese e recomendação separadas.

**Feito.**
- `BenchCombatSim` (só benchmark) com contadores e cronômetros por seção; `tests/bench_parity_test.gd` garante
  luta idêntica à `CombatSim`. Único gancho no jogo: `Battle.sim_script` (null = `CombatSim`).
- `tools/bench/`: `stress_bench.gd` (cenário no fluxo real + driver de quadro + sondas de `_draw` + monitores do
  Godot), `run_matrix.sh`, `make_report.py` e `godot_profiler.py` (Profiler do Godot via depuração remota, sem
  editor).
- Matriz executada: 108 execuções headless, 36 com render (llvmpipe), comparações visual × lógica, overhead,
  tempo real, Paladinos, linha do tempo e profiler. Resultado em `PROFILING_REPORT.md`; tabelas e dados em
  `docs/profiling/`.

**Conclusões principais** (detalhes e números no relatório):
1. maior gargalo: visual procedural redesenhado a cada quadro (~130 draw calls por Guerreiro, ~11 mil por quadro
   em 40×40; ~60% do quadro sem render), inclusive cadáveres;
2. segundo: busca de alvo O(N²) a 120 Hz por unidade, varrendo mortos e aliados, com o mesmo resultado em
   98–100% das vezes (5,4 ms em 40×40; > 10 ms em 50×50);
3. physics ≈ 0; nós não são excesso; draw calls são problema;
4. Paladino é o visual mais caro (~260 µs de update por unidade);
5. em tempo real, quadro lento → até 6 passos da simulação por quadro (cascata).

**Limitações.** Sem GPU no ambiente (render por software): draw calls valem, ms de render não. Nada otimizado.

### Paladino Vivo refeito pela referência direita/esquerda (`PaladinLiveVisual`) ✔ (aguardando validação)

**Pedido.** Usar a imagem anexada (Paladino olhando para a direita e para a esquerda) como referência principal
de silhueta e proporção, sem copiar barra de vida, texto ou fundo.
- ~10–15% mais alto e ~15–20% mais largo que o Guerreiro; ombros, escudo, pernas e botas maiores. Não é chefe.
- Mesmo estilo: 2D, cartunesco, contorno escuro, cores chapadas.
- Elmo com visor, auréola dourada, ombreiras grandes, armadura marfim com ouro, tabardo, pernas blindadas, botas
  pesadas, espada de uma mão, escudo grande.
- Espada SEMPRE na mão direita, escudo SEMPRE no braço esquerdo; espada nunca para baixo no idle/caminhada.
- Postura: pés afastados, joelhos levemente dobrados, tronco firme. Fake 2.5D leve. As 16 animações.

**Feito** (só o visual; mecânica, stats, IA e Paladino Sombra intocados).
- Porte: `BODY_SCALE` (1,06 × 1,12) no transform do corpo, `body_width` 1,12, `shield_scale` 1,18,
  `sword_scale` 1,4. Topo do elmo ~1,12× o Guerreiro. `top_y` e `pick_rect` acompanham.
- Pose neutra nova: espada erguida na diagonal, para fora (s_elev 52°, s_yaw 78°), cotovelo dobrado; escudo
  preso ao braço esquerdo cobrindo o tronco; pés afastados e joelhos dobrados (para a frente e para fora).
- Peças: ombreiras maiores com rebites, pernas mais grossas com faixa dourada na canela, botas pesadas,
  joelheiras douradas, cinto dourado com fivela grande, manoplas marrons com punho dourado, tabardo mais longo,
  auréola maior com três pontas, verso do escudo com alças e rebites.
- Direções: RIGHT passou a 3/4 frontal (30°), como na referência. A vista da esquerda é o espelho do desenho da
  direita (a referência mostra assim, com o verso do escudo), feito no transform do corpo — sem escala negativa;
  nos dados a espada continua na mão direita.
- No golpe o corpo gira em direção ao perfil (a lâmina não some atrás do escudo). Tempos iguais.
- Correção: o yaw acumulava voltas (ex.: 390°) depois de várias viradas; agora é normalizado em −180°..180°.
- Testes (`paladin_live_test`): altura até o elmo 1,08–1,2× o Guerreiro e com a auréola < 1,35×; ombros
  > 10; leitura lateral (direita: espada ↖ e face do escudo; esquerda: espada ↗ e verso do escudo, no idle e
  em 3 fases da caminhada); yaw normalizado.

**Interpretação a validar.** O texto pede "espada para cima na diagonal direita" olhando para a direita; a
imagem (referência principal) mostra a espada erguida para FORA do corpo (↖ na vista da direita, ↗ na da
esquerda). Segui a imagem. Se a intenção for a lâmina inclinada para a frente (para o lado em que olha), é só
trocar `s_yaw` na `neutral()`.

**Validado.** 11 suítes OK. Capturas: referência × jogo, família de perto e na escala do jogo, os 16 estados,
animações quadro a quadro (idle, caminhada direita/esquerda, golpe, provocação → escudo, morte) e o Sandbox em
1600×896.

### Paladino Vivo na linguagem do Guerreiro e da Sentinela (`PaladinLiveVisual`) ✔

**Pedido.** Reconstruir o Paladino Vivo para ser da MESMA família visual do Guerreiro e da Sentinela.
- Pequeno, simples, contorno escuro, poucas formas, cartunesco, 100% código.
- Não é uma reprodução das concept arts.
- Mais pesado que o Guerreiro, sem virar chefe.
- Escudo dominante no braço esquerdo, espada na mão direita.
- Direções com leitura, e animações lentas e pesadas.
- Mecânica intacta.

**Feito.**
- `scripts/visuals/units/paladin_live_visual.gd` (`PaladinLiveVisual extends CodeDrawnUnitVisual`) e a cena
  `scenes/units/paladin_live_visual.tscn`. Os mesmos utilitários, a mesma escala, o mesmo chão e o mesmo
  contorno do `WarriorVisual`.
- **Partes simples** com âncoras no espaço do corpo:
  - um yaw por direção desloca as âncoras e ordena as partes (fake 2.5D leve);
  - as direções da esquerda são o mesmo giro, sem espelho;
  - de costas: traseira do elmo e verso do escudo.
- **Estado e tempo** vêm do `PaladinAnimator` já testado: golpe sincronizado, provocação → guarda → escudo,
  bloqueio, hit, push, morte. Ele passou a aceitar rodar sem o rig 3D.
- **Poses 2D próprias.**
  - Idle quase imóvel.
  - Passos curtos, ciclo de 1,05 s.
  - Três golpes:
    - RIGHT: espada atrás da cabeça, depois horizontal no impacto;
    - UP_RIGHT: de cima para baixo;
    - DOWN_RIGHT: de baixo para cima.
  - Taunt: firma os pés, recua e avança o escudo, abre o peito; a auréola clareia.
  - Guarda fechada com o escudo à frente.
  - Block: o escudo recua, o corpo absorve.
  - Hit: curto, com clarão.
  - Push: inclina, e o pé de trás busca apoio.
  - Morte: joelhos cedem, a espada cai à frente, o escudo tomba ao lado dos pés, a queda é de costas e fica o cadáver.
- **Efeitos simples fora do corpo:**
  - anel real da provocação e onda curta no chão;
  - contorno dourado sutil no escudo ativo;
  - clarão quando o escudo sobe;
  - faíscas no bloqueio.
- **Debug e Sandbox:** F4 mostra direção, estado e progresso; a prévia do Sandbox funciona igual.
- **`sac_paladin.tres`** aponta para o novo visual (`visual_scene` e `visual_script`). Stats iguais.
- **Testes:**
  - nova suíte `paladin_live_test`, com a mesma bateria do rig: gameplay idêntico com e sem visual, espada/escudo nas mãos certas em 8 direções × 11 estados, direções, estados da simulação, Sandbox sem vazamento e custo; mais as proporções da família (altura ~1,1× o Guerreiro, mesma escala e contorno);
  - `paladin_rig_test` passou a testar o rig 2.5D como alternativa;
  - `paladin_test` e `paladin_sprite_test` foram atualizados.

**Validado.** 11 suítes OK. Capturas feitas:
- família lado a lado (Guerreiro, Sentinela, Paladino, Paladino Sombra);
- os 16 estados;
- golpe e morte quadro a quadro;
- combate real no Sandbox em 1600×896.

**Limitações.**
- O Paladino Sombra continua o visual antigo, mais volumoso. Vivo e Sombra ainda não têm a mesma silhueta:
  uma etapa futura pode derivar o Sombra do `PaladinLiveVisual` (regra `ShadowStyle`), como o Guerreiro Sombra.
- O rig 2.5D facetado e a versão por sprites continuam no projeto como alternativas fora de uso; dá para
  apagar os dois se não forem mais úteis.
- Não existe empurrão na simulação: o PUSH só aparece com deslocamento real inesperado ou na prévia.
