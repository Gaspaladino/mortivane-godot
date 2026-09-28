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

### Ordem sugerida de etapas
1. **Esqueleto do projeto + arena**: config, fundo, escala/aspecto, limites do campo, debug overlay, grades. ✔ (ver seção 6)
   - **Núcleo mínimo de combate** (1 × 1: alvo, movimento, ataque, dano, HP, morte). ✔ Feito antes da etapa 2,
     a pedido; adianta parte da etapa 4 (ver seção 6).
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
