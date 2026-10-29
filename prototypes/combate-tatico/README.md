# Duelo Sombrio — protótipo de combate tático 3×3 (HTML5 Canvas)

Protótipo jogável e independente do projeto Godot. Basta abrir `index.html` no navegador; não precisa de servidor nem de build.

## Ciclo da batalha
1. **Sua ofensiva:** escolha habilidade e alvo para cada personagem. As setas e a lista mostram a ordem prevista (por velocidade). Confirme para executar.
2. Os confrontos acontecem **um por vez**, com câmera, preparação, avanço, reação, impacto e retorno. Os inimigos reagem sozinhos (bloqueio, esquiva ou aparo).
3. **Ofensiva inimiga:** cada inimigo anuncia o que vai fazer e quem é o alvo. Escolha a reação de cada alvo (o padrão já vem marcado) ou mande o **Cavaleiro proteger** um aliado (uma vez por rodada).
4. A resolução é exibida e as fases se alternam até a vitória ou a derrota. Use **↻** ou o botão do fim de jogo para reiniciar.

Controles: **1×/2×** para a velocidade, **Pular** (ou Espaço) para terminar as animações e **?** para ver as regras. Velocidade e pulo não mudam o resultado, porque tudo é decidido antes de a animação começar.

## Arquitetura
| Arquivo | Papel |
|---|---|
| `js/data.js` | **Balanceamento:** fórmulas (`CONFIG`), personagens, habilidades, reações e status. Edite aqui. |
| `js/combat.js` | Lógica pura (`Battle`): chances, dano, reações, contra-ataque, intervenção e recargas. Usa RNG com semente e devolve *confrontos* com o resultado completo e um snapshot do estado. |
| `js/ai.js` | IA: reação defensiva (menor dano esperado com viés de personalidade) e intenções (alvo foco por vida, vulnerabilidade e ameaça, além da combinação maldição → esmagar). |
| `js/presenter.js` | Apresentação: câmera 2D, tweens, câmera lenta, hit-stop, partículas e desenho procedural dos personagens. Recebe os confrontos e os reproduz numa fila de passos: foco → preparação → intervenção → avanço/projétil → reação → impacto → status → retorno. |
| `js/ui.js` | Interface DOM por fase. |
| `js/main.js` | Máquina de estados: `PLAN → PLAYER_RESOLVE → ENEMY_INTENT → DEFENSE → ENEMY_RESOLVE → (PLAN \| END)`. |
| `tools/sim.js` | Simulação sem interface para balanceamento: `node tools/sim.js 1000`. |

## Regras resumidas
- **Dano** = poder × (atk/7) × (20/(20+def)) × variação de ±10%.
- **Bloquear/Barreira** sempre funciona e reduz o dano pelo `blockPower` da unidade. *Lâmina Fantasma* ignora bloqueios.
- **Esquivar:** 40% de base + perícia + 4% por ponto de velocidade de vantagem. Golpes pesados dão +20% e golpes rápidos −20%. Se a esquiva falhar, o dano é total.
- **Aparar:** 40% de base + perícia. Golpes pesados dão −20% e golpes rápidos +10%. Se der certo, anula o golpe e dispara um contra-ataque que não pode ser reagido. Se falhar, o dano é de 125%. Magia não pode ser aparada.
- **Combinações:** *Quebra-Guarda* deixa o alvo Vulnerável (+50%), e *Estocada Precisa* causa o dobro de dano nesse alvo. *Marca Rúnica* faz o próximo golpe aliado causar +40% e não poder ser esquivado nem aparado. *Desafio* obriga o inimigo a atacar o Cavaleiro.
- **Golpe decisivo** (mata ou tira 30% ou mais da vida máxima): câmera lenta, hit-stop e banner. Aparos e proteções recebem um destaque menor. Os demais golpes são rápidos.
