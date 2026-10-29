# Duelo Sombrio — protótipo de combate tático 3×3 (HTML5 Canvas)

Protótipo jogável e independente do projeto Godot. Basta abrir `index.html` no navegador; não precisa de servidor nem de build.

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
| `js/data.js` | **Balanceamento:** fórmulas (`CONFIG`), personagens, habilidades, reações e status. Edite aqui. |
| `js/combat.js` | Lógica pura (`Battle`): intenções, `buildPlan` (valida as ações e liga os Clashes e as interceptações), `previewPlan` (prévia), `resolveRound` (fila de eventos com o resultado completo e um snapshot do estado). Usa RNG com semente. |
| `js/ai.js` | IA: Brutamontes prefere golpes fortes, Duelista prefere alvos frágeis ou enfraquecidos e Conjurador usa magias e Maldição. Com pouca vida, às vezes eles se defendem. |
| `js/presenter.js` | Apresentação: câmera, tweens, câmera lenta, hit-stop, partículas e personagens. Reproduz os eventos `stances`, `support`, `clash` (aproximação, choque, forças, vencedor e golpe) e `attack`. |
| `js/ui.js` | Interface DOM por fase. |
| `js/main.js` | Máquina de estados: `INTENTS → PLAN → RESOLVE → (INTENTS \| END)`. |
| `tools/sim.js` | Simulação sem interface para balanceamento: `node tools/sim.js 1000`. |
