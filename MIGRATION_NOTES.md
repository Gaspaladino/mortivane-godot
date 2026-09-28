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
