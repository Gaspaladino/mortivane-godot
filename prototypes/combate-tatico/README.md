# Duelo Sombrio — protótipo de combate tático 3×3 (HTML5 Canvas)

Protótipo jogável e independente do projeto Godot. Basta abrir `index.html` no navegador; não precisa de servidor nem de build.

## Interface de batalha
- **HUD limpo:** só um pequeno grupo de botões no canto: rodada (R1), 1×/2×, pular, equipe, ⚙, ajuda e reiniciar. Título, fase e textos ficam em ⚙, junto com áudio, reduzir animações, mostrar o ciclo de elementos, tela cheia e informações de depuração.
- **Seletor em arco (carrossel):** ao clicar num aliado, um trecho de uma roda maior entra girando e deslizando à frente dele, com as habilidades sobre o arco (ícone e nome; o item em foco fica no centro, maior). A roda do mouse ou as setas giram o arco, Enter escolhe o item em foco, e dá para clicar em qualquer item visível. Cada item é uma **placa** com ícone e nome juntos (até 2 linhas, o texto nunca sai da moldura); o hover realça a borda e o ícone, a escolhida fica dourada e a recarga aparece num pequeno número sobre o ícone. Clique, arrasto e correntes funcionam como antes. Há um som de corrente ao abrir e uma trava ao confirmar.
- **Tooltip das correntes inimigas:** passar o mouse sobre a corrente curva mostra o inimigo, a habilidade (marcando se é COMBO), o tipo, a faixa de Força por batidas, Dano, Pressão, o elemento e a vantagem sobre o alvo. A corrente, a origem e o alvo ficam em destaque.
- **AUTO** (ou a tecla A): preenche ações reais com correntes, considerando vida, elemento, chance de Quebra, chance no Clash, defesa do alvo, defesa própria quando está em risco e a combinação quando vale a pena. Nada é executado: você revisa, altera e só então executa.
- **Tela cheia:** navegadores não permitem simular o F11, então o jogo pede tela cheia pela Fullscreen API no primeiro clique, uma única vez. Se o navegador negar, o jogo segue normalmente; também há um botão em ⚙.

## Elementos
Ciclo fechado: **Vermelho > Amarelo > Roxo > Verde > Azul > Vermelho**. Vantagem dá +20% de dano e desvantagem −20% (só no dano, sem mudar o Clash; `CONFIG.element`).

| Elemento | Personagens |
|---|---|
| Vermelho | Espadachim, Brutamontes |
| Amarelo | Lutador, Duelista |
| Roxo | Mago, Conjurador |
| Verde | Lanceiro, Arqueira |
| Azul | Cavaleiro |

O ciclo fica num pentágono com setas no canto superior esquerdo (pode ser escondido em ⚙). O elemento aparece numa gema ao lado da vida, nos cards e na ficha, na prévia de Clash ("▲ Vantagem / ▼ Desvantagem elemental"), no tooltip da habilidade e das correntes inimigas, e no impacto.

## Clash em batidas (força acumulativa)
Cada habilidade de ataque tem **Força base**, **Batidas** (1 a 3) e **Impulso** por batida (0–3 em habilidades de 1 batida, 0–2 nas de 2 ou 3).
- O Clash dura o **maior** número de batidas das duas habilidades. Em cada batida, cada lado que ainda tem batida sorteia um impulso (uma única vez) e soma ao acumulado. Quem já usou suas batidas **mantém** o valor e aparece "SEGURA", sustentando a guarda.
- No fim vence a **maior força acumulada**; empate anula os dois golpes (sem dano e sem Pressão). As vitórias parciais só mudam a coreografia: quem lidera empurra e o outro perde terreno, sem dano.
- Depois vêm o golpe vencedor (com os seus impactos), o dano total (com crítico e elemento), a **Pressão uma única vez**, a Postura e a eventual Quebra. Batidas (a disputa) e golpes (o dano) são coisas separadas.
- **Equilíbrio:** a base foi recalculada para que a força média final de cada habilidade continue igual à anterior; o que muda é a dispersão. As de 1 batida são as mais confiáveis, e as de 3 começam mais baixas, mas têm o teto mais alto (ex.: Golpe Pesado 5–8, Corte Rápido 5–9, Sequência de Golpes 4–10). Na simulação, os aliados vencem cerca de 60% dos Clashes (antes 62%).
- **Apresentação:** cada lado tem um **emblema** compacto: um medalhão octogonal metálico com o número grande no centro, losangos que marcam as batidas (vão sendo consumidos) e uma faixa presa ao emblema com o nome da habilidade e do personagem (num combo, "A + B" e ⚔). Os aliados usam azul e ciano, os inimigos vermelho e laranja; os emblemas ficam acima do confronto, fora dos rostos e das barras, e sempre dentro da tela. Em cada batida, o "+N" surge pequeno acima do emblema e desce para dentro dele, o número sobe rápido e o emblema pulsa. Quem lidera brilha e o outro escurece e treme. No fim, o emblema vencedor cresce em dourado e o perdedor recua; no empate os dois ficam neutros.
- **Coreografia:** cada batida tem um padrão diferente (alto, baixo ou mudança de direção, e a última sempre como investida mais agressiva). Quem ficou atrás arma um golpe maior na batida seguinte; quem lidera empurra, com mais força quanto maior a margem, e o perdedor recua e perde a guarda (o escudo do Cavaleiro cede). No empate as armas travam. Quem já esgotou as batidas sustenta a guarda. Em magias e flechas, os projéteis colidem no meio. Isso é só visual: dano e Pressão continuam aplicados uma vez, no fim.
- **Impactos:** clarão direcional (raios na direção do golpe e um núcleo branco curto), estilhaços em cone, onda de choque e poeira nos golpes fortes, e uma variação por material (metal, corpo, perfuração, magia). A pausa no impacto é escalonada: quase nada nas batidas, mais nas finais e golpes fortes, e mais ainda no crítico. Uma Pressão grande (25 ou mais) faz a guarda ceder e a barra de Postura piscar.
- **Som de cada batida:** impacto conforme o material (tin ou clang no metal, escudo, seco nos socos, perfuração, energia nas magias), depois a revelação do impulso (um pouco mais aguda quanto maior o bônus), o tique do número e, na última batida, um "CLASH!" mais forte e o golpe final.
- **Prévia no planejamento:** mostra força base, batidas, intervalo de impulso e a faixa final (ex.: "5 · 2 batidas (+0–2) → 5–9"). As chances de vitória, empate e derrota são **calculadas exatamente** sobre todas as combinações de impulsos. As categorias são Favorável, Equilibrado, Desfavorável, **Vitória certa** e **Derrota certa**. "Equilibrado" vale quando |P(vitória) − P(derrota)| ≤ `CONFIG.clash.evenBand` (padrão 0,12).
- **Cartão de prévia compacto:** ícone, nome e faixa de força da habilidade aliada (azul) **VS** a inimiga (vermelho), e a categoria com ícone. Extras só como ícones: ⚡ (Quebra possível) e ▲/▼ (elemento). Ataques sem oposição mostram "sem confronto"; interceptações inválidas mostram "interceptação indisponível".
- **Clash corpo a corpo × distância:** o lutador corpo a corpo fica parado e intercepta cada projétil por batida com um gesto da classe (Espadachim corte diagonal, Cavaleiro escudo/espada, Lanceiro haste, Lutador antebraço/esquiva). Quem lidera a batida decide: projétil desviado, defensor empurrado ou dissipação no empate. Batidas não causam dano nem Pressão. Se o corpo a corpo vence, avança e golpeia; se perde, o projétil acerta.
- **HUD única de Clash (cabo-de-guerra):** uma barra compartilhada, **esquerda = aliado (azul), direita = inimigo (vermelho)**. As duas forças preenchem a barra até o **ponto de contato**: quem lidera avança e empurra o contato para o lado do adversário (empate = centro), com estrias correndo em direção ao contato, mola no movimento, tremor nos impactos, "chute" do marcador na troca de domínio, pulsação na ponta que lidera e uma pequena explosão no centro ao fim. Cada ponta mostra só o número da Força acumulada, o "+N" do impulso e os marcadores de batida. Largura acompanha a distância na tela (230–620 px), sempre dentro da tela, só durante o Clash.

## Postura e Quebra de Guarda
Cada personagem tem **Vida** (sempre **verde** nos aliados e **vermelha** nos inimigos; a cor identifica a equipe e nunca muda com a quantidade) e **Postura** (barra âmbar, mais fina, logo abaixo).
- **Desgaste:** só quem **perde um Clash** perde Postura, igual à **Pressão** da habilidade vencedora. A Pressão é aplicada **uma vez por habilidade**, mesmo com vários golpes; a barra cai em etapas junto com os impactos. Empates e ataques sem Clash não desgastam. Na interceptação, quem perde Postura é quem interceptou.
- **Sem regeneração:** a Postura persiste entre rodadas.
- **Quebra:** em 0 o personagem perde a guarda (animação própria por classe, ruptura e som) e **perde a próxima ação**. Se ainda não agiu na rodada, a ação planejada é cancelada; se já agiu, perde a ação da rodada seguinte (não dá para planejar nada para ele, e a IA não o usa).
- **Recuperação:** cumprida a penalidade, a Postura volta ao máximo e ele ganha **Estabilidade Recuperada** (losango verde). Enquanto ela durar, a Postura pode cair até 1, mas não quebra de novo; a proteção acaba quando ele executa uma ação válida.
- **Recuperar por habilidade:** **Firmar Guarda** (Cavaleiro, +25, além do bloqueio) e **Reforço Arcano** (Mago, +15 num aliado, além do +2 de força). Não passam do máximo e não removem uma Quebra já aplicada.
- **Interface:** a Pressão aparece no leque, na ficha e na prévia de Clash ("Se vencer: −P na Postura de X… → possível QUEBRA" / "Se perder: risco de QUEBRA"). Ao mirar, **⚡ QUEBRA?** aparece junto da barra dos alvos que podem quebrar se você vencer. Passar o mouse num inimigo mostra a Postura dele.
- **Postura baixa (só visual):** abaixo de 50% a guarda oscila; abaixo de 25% o tronco recua e a barra pulsa. É diferente do cansaço da Vida baixa (corpo curvado e respiração mais pesada).
- **IA:** pesa um pouco a chance de Quebra conforme a classe (o Brutamontes mais, o Duelista menos), sem caçar sempre o alvo mais frágil.

| Postura | Cavaleiro 100 · Espadachim 70 · Mago 40 · Lanceiro 75 · Lutador 65 · Arqueira 45 · Brutamontes 110 · Duelista 70 · Conjurador 45 |
|---|---|
| Pressão | Ataque Básico 15 · Golpe de Escudo 10 · Golpe Pesado 35 · Corte Rápido 12 · Golpe Preciso 8 · Ataque Arriscado 20 · Projétil 10 · Explosão 20 · Enfraquecimento 12 · Estocada 12 · Varredura 30 · Investida Perfurante 25 · Soco 10 · Sequência 25 · Ascendente 35 · Flecha Precisa 10 · Disparo Duplo 15 · Flecha Perfurante 20 · Esmagar 40 · Pancada 20 · Lâmina Veloz 15 · Investida Feroz 25 · Raio 15 · Maldição 10 · Investida Conjunta 40 · Pressão Brutal 45 |

## Críticos
10% de chance por habilidade que acerta e 1,5× de dano (`CONFIG.crit`). São rolados **uma vez por habilidade**, mesmo com vários golpes, e não afetam o Clash. A apresentação tem uma pausa no impacto configurável, flash dourado, tremor maior, "CRÍTICO!", número em destaque, som próprio e um efeito que varia por tipo de golpe (corte cruzado, estocada, soco ou anel mágico).

## Ficha de personagem e prévia
Na formação, cada personagem tem uma ficha com moldura na cor da classe: retrato, função e estilo, atributos (Vida, Postura, Velocidade, Ataque e Defesa), habilidades com ícone, força, dano, Pressão, número de golpes e efeitos, e a especialidade. Passar o mouse, focar com o teclado ou clicar numa habilidade mostra uma **prévia animada** feita com o próprio motor de combate, num canvas separado, contra um boneco de treino. As defesas aparecem contra um Duelista e o suporte num aliado. A prévia não altera a batalha. A opção **Reduzir animações** (no menu 🔊) faz as prévias tocarem uma vez só e reduz tremores e câmera lenta.

## Movimento e gestos
Durante o planejamento, os personagens dão pequenos passos em **X e Y** (Y é profundidade: quem está mais abaixo aparece maior e desenhado na frente). Seguem a preferência de formação (a frente fica mais à frente, a retaguarda mais ao fundo) e recuam se um inimigo chega perto. Também fazem **gestos de classe** de vez em quando: o Cavaleiro ajusta o escudo, o Espadachim gira a espada, o Mago move as mãos, o Lanceiro reposiciona a lança, o Lutador alterna a guarda e a Arqueira ajusta o arco ou mira. Os inimigos gesticulam sobre a pose de preparação. Nada disso acontece com quem está selecionado, atacando, caído ou quebrado. As **posturas defensivas** escolhidas (bloqueio, aparo, esquiva, proteção) aparecem já no planejamento, com pose própria por classe, e voltam suavemente ao neutro ao cancelar. As intenções inimigas ganharam **setas** na ponta e um chevron que percorre o arco.

## Formação da equipe
A tela cabe inteira, sem rolagem: a grade dos 6 personagens fica à esquerda, a ficha em blocos no centro (identidade e elemento, atributos, habilidades e papel tático: faz bem, melhor contra, limitações), e à direita ficam o painel da habilidade clicada (descrição, números e **prévia, só ao clicar**) e os 3 espaços da equipe. Escolha 3 dos 6 combatentes: Cavaleiro, Espadachim, Mago, **Lanceiro**, **Lutador** e **Arqueira**. Cada card tem retrato e barras de vida, velocidade e resistência; clique para ver os detalhes (habilidades com força, dano e número de golpes, a defesa e o estilo). Não dá para repetir personagem e o botão Iniciar só libera com 3 escolhidos. A posição em campo segue a especialidade: Cavaleiro e Lutador na frente, Mago e Arqueira atrás. No fim da batalha dá para lutar de novo com a mesma equipe ou trocar; o botão 👥 também volta à formação, e a última equipe fica salva.

| Novo | Papel | Habilidades | Defesa |
|---|---|---|---|
| Lanceiro | alcance e controle (alcance de golpe 128, +2 para interceptar) | Estocada (F8 D7, rápida) · Varredura (F6 D9, empurra) · Investida Perfurante (F5 D14, desequilibra) | Guarda da Lança (aparo) |
| Lutador | pressão e múltiplos impactos (o mais rápido) | Soco Direto (F7 D6) · Sequência de Golpes (F6 D12 em 3 socos) · Golpe Ascendente (F5 D12, derruba) | Esquiva Lateral |
| Arqueira | precisão à distância (flechas físicas, que podem ser aparadas) | Flecha Precisa (F8 D7) · Disparo Duplo (F6 D10 em 2 flechas) · Flecha Perfurante (F5 D14, preparação longa) | Recuo Ágil (esquiva) |

## Apresentação e game feel
- **Câmera em ataques à distância:** o enquadramento usa o tamanho real visível da tela. Se atacante e alvo cabem juntos, aparecem juntos (o zoom se ajusta). Se não cabem, a câmera mostra o disparo, acompanha o projétil e chega ao alvo antes do impacto. O dano só aparece no contato. Um teste automático em telas de 900×700 e 1400×860 confirmou que todos os impactos aconteceram na tela.
- **Arena:** 4 camadas maiores que a área de combate (céu, montanhas e ruínas, colunas e braseiros, chão rachado) com parallax discreto. As faixas pretas de cinema foram removidas e a câmera tem limites que nunca revelam a borda.
- **Movimento ambiente:** durante o planejamento, cada personagem dá pequenos passos de vez em quando, com propósito: recua se um inimigo está perto demais, ajusta a profundidade ou só a postura. A preferência de formação é fraca e nunca puxa de volta à posição inicial (melee pode ficar avançado). Não acontece com o personagem selecionado, durante um arrasto, numa queda ou numa ação.
- **Condição física:** muda suavemente com a vida. Acima de 50% é normal; entre 25% e 50% a respiração fica mais forte e o tronco curva; abaixo de 25% o corpo curva mais, balança e a arma pesa. O Cavaleiro passa a se apoiar no escudo. É só visual.
- **Preparação inimiga:** posturas lentas e diferentes por classe (o Brutamontes ergue a clava devagar, o Duelista se posiciona, o Conjurador concentra energia), sem tremores.
- **Efeitos:**
  - rastros de lâmina e rastro linear de estocada com brilho na ponta;
  - linhas de velocidade nos socos e flechas com trajetória e rastro;
  - luz breve no impacto e tremor de câmera direcional;
  - hit-stop quase nulo nos golpes intermediários e mais forte no golpe final pesado;
  - recuperação visível após golpes fortes e poeira em quedas e recuos.
- **Áudio** (`js/audio.js`): todos os efeitos são sintetizados com a Web Audio API (sem arquivos externos, sem licença a verificar), com pequena variação de tom e volume. Há sons de lâmina, escudo, soco, estocada, Clash (e de vitória ou derrota no Clash), bloqueio, esquiva, aparo, magia (preparação, lançamento e impacto), arco (tensionar, disparar, flecha voando e acerto), queda e interface. O botão 🔊 abre volume geral, volume dos efeitos e silenciar. O som só começa depois da primeira interação.

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
- **Posições persistentes:** ninguém volta à formação depois de agir. Golpes empurram, interceptadores ficam no caminho e esquivas mudam a profundidade. Entre rodadas, **cada um fica onde terminou**: só um pequeno ajuste (até ~60 px) — passo ou saltinho para longe de um inimigo colado (ranged busca um pouco mais de espaço), virar para a ameaça e assumir a guarda. A posição inicial nunca é destino.
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
| `js/audio.js` | Efeitos sonoros sintetizados (AudioManager) e volumes. |
| `js/data.js` | **Balanceamento:** fórmulas (`CONFIG`), personagens, habilidades (com `hits`, `windup` e `impact`), combinações (`COMBOS`), reações e status. Edite aqui. |
| `js/combat.js` | Lógica pura (`Battle`): intenções, `buildPlan` (valida as ações e liga os Clashes e as interceptações), `previewPlan` (prévia), `resolveRound` (fila de eventos com o resultado completo e um snapshot do estado). Usa RNG com semente. |
| `js/ai.js` | IA: Brutamontes prefere golpes fortes, Duelista prefere alvos frágeis ou enfraquecidos e Conjurador usa magias e Maldição. Com pouca vida, às vezes eles se defendem. |
| `js/presenter.js` | Apresentação: estados visuais, rotinas paralelas de recuperação, reações físicas, espaçamento (`settle`), câmera que acompanha, e reprodução dos eventos `stances`, `support`, `clash` e `attack`. |
| `js/preview.js` | Prévia animada das habilidades nas fichas (reaproveita o Presenter com eventos sintéticos). |
| `js/planner.js` | Planejamento na arena: seleção, menu radial, correntes, alvos válidos, entrada (clique ou arrasto, Esc, botão direito) e prévia de Clash. |
| `js/ui.js` | Barra compacta: dica, ordem prevista e botão para executar. |
| `js/main.js` | Máquina de estados: `INTENTS → PLAN → RESOLVE → (INTENTS \| END)`. |
| `tools/sim.js` | Simulação sem interface para balanceamento: `node tools/sim.js 1000`. |

## Estados sem poluição visual

Durante a execução, os estados aparecem como **ícones pequenos** ao lado da barra (um por personagem por vez, somem em ~1 s) e pela animação do corpo: bloqueio (escudo), esquiva (rastro), aparo (lâminas cruzadas + flash metálico), Quebra de Postura (escudo rachado + barra zerada + som), ação perdida (×), derrubada (seta para baixo), derrota (caveira, sem texto permanente). Banners grandes de "DERROTADO", "APARADO", "PROTEÇÃO", "INTERCEPTAÇÃO" e textos como "ESQUIVA"/"BLOQUEIO" foram removidos; detalhes completos ficam nos tooltips e fichas.

## Interceptação e ações do protegido

A interceptação só consome a ação do **interceptor**. O ataque inimigo é redirecionado (no planejamento a corrente inimiga passa a apontar para o interceptor e o alvo original ganha um escudo), e a ação planejada do protegido continua na fila. Ele só deixa de agir se cair, sofrer Quebra de Postura ou se a própria ação dele virar outro Clash (ex.: ele mira um inimigo que também o ataca — Clash direto, que ele pode perder).

## Tela limpa

- **Sem barra inferior:** só os botões **AUTO** e **Executar** ficam soltos no canto inferior direito durante o planejamento (fundo discreto, contorno, sombra, hover e clique). A ordem prevista e as dicas continuam disponíveis nos tooltips das correntes.
- **Sem textos no Clash:** a legenda do topo ("CLASH · …", "INTERCEPTAÇÃO · …"), os banners de ataque combinado e os textos de vantagem elemental, efeitos aplicados e ações falhas foram removidos da execução; a luta é lida pela animação, pela barra, pelos números, pelos ícones e pelos efeitos.
