# Duelo Sombrio — protótipo de combate tático 3×3 (HTML5 Canvas)

Protótipo jogável e independente do projeto Godot. Basta abrir `index.html` no navegador; não precisa de servidor nem de build.

## Planejamento na arena
- **Seleção direta:** clique num aliado e as habilidades dele surgem num leque **à frente** dele, abrindo a partir da mão. As três ofensivas formam um arco, com a do meio mais à frente. Defesa, suporte, proteção e combinação ficam num arco externo menor. Perto da borda, o leque vira para o lado que tem espaço e se desloca na vertical para continuar visível.
- **Correntes:** arraste do personagem até uma habilidade e continue até o alvo, num único gesto. A primeira habilidade tocada é a escolhida; para trocar no meio do gesto, pare cerca de 0,25 s sobre outra. Também funciona só com cliques: personagem → habilidade → alvo. Habilidades de defesa confirmam no próprio círculo.
- **Leitura:**
  - Intenções inimigas aparecem como linhas vermelhas tracejadas e discretas.
  - As ações aliadas são correntes: elos ovais com ponta de lança para ataque, elos redondos com losango para suporte e elos quadrados com escudo para proteção.
  - O medalhão perto do início mostra a habilidade e a ordem; o selo no meio mostra o Clash (Favorável, Equilibrado ou Desfavorável).
  - As correntes sobem acima dos personagens e descem no alvo (Bézier cúbica). A altura depende da distância e de uma faixa: o arco mais curto fica embaixo e quem passa por cima de outro sobe uma faixa. Pontas que compartilham origem ou destino ganham pequenos deslocamentos.
  - Passar o mouse destaca só as conexões daquele personagem; a corrente em edição brilha.
- **Prévia de Clash:** aparece ao mirar um inimigo ou ao passar o mouse no selo. Usa as regras reais, com modificadores e ordem. Clicar no selo liga ou desliga a interceptação.
- **Alterar e cancelar:** clique de novo no personagem para trocar; ✕ no menu ou botão direito cancela; Esc desfaz o passo atual. Soltar a corrente fora de um alvo válido não muda nada.

## Golpes múltiplos e ataques combinados
- **Sequências de golpes** (`hits` em `data.js`): Corte Rápido e Lâmina Veloz dão 2 cortes; Ataque Arriscado dá 3 golpes; Projétil Mágico lança 2 projéteis. Golpe Pesado e Esmagar continuam com um golpe só, com preparação mais longa (`windup`). Cada golpe tem uma fração do dano (`share`), um movimento (`motion`) e uma reação (`react`). O dano é dividido em inteiros que somam exatamente o dano da lógica, e no fim aparece "Total N". A habilidade disputa um único Clash: se perder, nenhum golpe da sequência acontece.
- **Variações cosméticas:** corte horizontal, invertido, diagonal ou de cima; preparação levemente diferente; arco do projétil. Nada disso muda dano, força, alvo ou efeito.
- **Ataques combinados** (`COMBOS` em `data.js`): uma ação que gasta a ação principal dos dois membros e disputa um único Clash.
  - **Investida Conjunta** (Cavaleiro + Espadachim): F10, dano 15 em 4 golpes, derruba, recarga 3. Fica disponível no leque dos dois personagens.
  - **Pressão Brutal** (Brutamontes + Duelista): F10, dano 17, derruba. A IA usa com 30% de chance quando os dois iam atacar e a combinação não está em recarga; é anunciada na preparação inimiga.
  - Se um membro cair antes da vez da combinação, ela é interrompida e ninguém ganha uma ação extra.
  - Cancelar libera os dois membros, e trocar a ação de um membro desfaz a combinação.

## Execução contínua
- **Posições persistentes:** ninguém volta à formação depois de agir. Golpes empurram, interceptadores ficam no caminho e esquivas mudam a profundidade. Entre rodadas, cada lado só recua o necessário para voltar à sua metade, com espaçamento mínimo e dentro da arena.
- **Reações físicas** (`impact`, calculado na lógica e por enquanto só visual):
  - **leve:** inclina o tronco.
  - **médio:** desliza para trás levantando poeira.
  - **forte:** perde o equilíbrio e se apoia com a mão no chão.
  - **extremo:** derrubada, só para habilidades com `impact: 'knockdown'`. O personagem cai, fica no chão, levanta e retoma a postura.
  - **derrota:** fica caído, apagado.
- **Clashes:** os dois avançam, as armas se chocam e há resistência (mais longa quando as forças são próximas). As forças aparecem na própria arena. A margem muda só a intensidade visual: por pouco o vencedor força a guarda devagar, numa margem média o perdedor recua, numa margem grande o perdedor perde o equilíbrio.
- **Estados visuais por personagem:** IDLE, PREPARING, APPROACHING, ATTACKING, CLASHING, BLOCKING, DODGING, PARRYING, HIT_LIGHT, HIT_HEAVY, STAGGERING, KNOCKDOWN, GETTING_UP, REPOSITIONING e DEFEATED. A recuperação de um personagem continua enquanto o próximo confronto começa; quem precisa agir espera a própria recuperação terminar.
- **Câmera:** acompanha os personagens focados, inclusive quando são empurrados, e vai direto ao próximo confronto. Só volta ao plano geral no fim da rodada.
- **Peso:** o Cavaleiro e o Brutamontes se movem devagar e são pouco empurrados; o Espadachim e o Duelista são rápidos; os conjuradores se movem de forma suave.

Use `index.html?seed=123` para repetir a mesma batalha. O resultado de cada rodada é idêntico em 1×, em 2× e com Pular.

## Rodada compartilhada
1. **Preparação inimiga:** cada inimigo escolhe a ação e o alvo, e a escolha fica fixa durante a rodada. A arena mostra linhas tracejadas com habilidade, força (F) e dano (D), além das poses de preparação.
2. **Planejamento:** escolha uma ação para cada personagem. Pode ser atacar, usar uma habilidade especial, interceptar, assumir uma postura defensiva, proteger um aliado ou dar suporte.
3. **Prévia:** mostra os Clashes como Favorável, Equilibrado ou Desfavorável, com as chances calculadas a partir de todas as rolagens possíveis. Também mostra os ataques sem oposição e a ordem prevista dos acontecimentos.
4. **Execução:** um acontecimento por vez, sempre na ordem prevista.

### Clash
Cada lado calcula **Força da habilidade + modificadores + rolagem de 0 a 3**. Quem tiver o total maior interrompe o golpe do outro e causa o próprio dano. Em caso de empate, os dois golpes se anulam. Força e dano são valores separados: força alta ajuda a vencer Clashes, e dano alto rende mais contra quem não reage.
- **Direto:** acontece quando você ataca o inimigo que está atacando você.
- **Interceptação:** atacar um inimigo que mira outro aliado permite entrar na frente dele. Só vale se `velocidade da ação (+ alcance) ≥ velocidade do golpe inimigo`. O Cavaleiro tem +4 de alcance.
- Velocidade = velocidade do personagem + prioridade da habilidade (rápido +2, lento −2, suporte +3). As defesas agem antes de tudo.

### Defesas (duram a rodada e gastam a ação)
Postura de Escudo bloqueia o dano. Proteção faz o Cavaleiro receber e bloquear os golpes sem oposição destinados a um aliado, o que é diferente de interceptar. Aparar anula o primeiro golpe físico e contra-ataca; o contra-ataque não pode ser reagido e Aparar não funciona contra magia. Passo Etéreo dá uma chance de esquivar de cada golpe.

### Preparação entre aliados
Enfraquecimento tira 2 de força do alvo e Suporte dá +2 de força para a próxima habilidade de um aliado. Os dois agem cedo, mas só afetam o que vier **depois** deles na ordem; nada muda de forma retroativa.

## Arquitetura
| Arquivo | Papel |
|---|---|
| `js/data.js` | **Balanceamento:** fórmulas (`CONFIG`), personagens, habilidades (com `hits`, `windup` e `impact`), combinações (`COMBOS`), reações e status. Edite aqui. |
| `js/combat.js` | Lógica pura (`Battle`): intenções, `buildPlan` (valida as ações e liga os Clashes e as interceptações), `previewPlan` (prévia), `resolveRound` (fila de eventos com o resultado completo e um snapshot do estado). Usa RNG com semente. |
| `js/ai.js` | IA: Brutamontes prefere golpes fortes, Duelista prefere alvos frágeis ou enfraquecidos e Conjurador usa magias e Maldição. Com pouca vida, às vezes eles se defendem. |
| `js/presenter.js` | Apresentação: estados visuais, rotinas paralelas de recuperação, reações físicas, espaçamento (`settle`), câmera que acompanha, e reprodução dos eventos `stances`, `support`, `clash` e `attack`. |
| `js/planner.js` | Planejamento na arena: seleção, menu radial, correntes, alvos válidos, entrada (clique ou arrasto, Esc, botão direito) e prévia de Clash. |
| `js/ui.js` | Barra compacta: dica, ordem prevista e botão para executar. |
| `js/main.js` | Máquina de estados: `INTENTS → PLAN → RESOLVE → (INTENTS \| END)`. |
| `tools/sim.js` | Simulação sem interface para balanceamento: `node tools/sim.js 1000`. |
