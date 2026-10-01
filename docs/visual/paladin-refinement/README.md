# Refinamento visual do Paladino

Base: `1936c3f` (main). Branch: `codex/paladin-visual-refinement`.

Espada menor e mais vertical, mão afastada do elmo, postura mais ereta, ombreiras compactas, escudo em formato de pipa com símbolo simples. Capa viva reutiliza o osso/peça traseira; nenhum nó, shader, textura ou efeito novo. A versão Sombra herda a revisão de espada, escudo, ombreiras e capa na sua base visual, preservando sua paleta e efeitos existentes.

Somente dois scripts de produção alterados: `paladin_live_visual.gd` e `paladin_visual.gd`. Stats, alcance, cooldown, combate, comportamento, função de frontline e tempos de animação não foram alterados.

## Imagens

[Antes/depois com Guerreiro e Sentinela para comparação](comparison.png).

[Paladino vivo: oito direções em idle, walk, attack e shield](directions.png).

As imagens são capturas do motor. A galeria inclui ataque, habilidade, morte e cadáver.

## Verificação

Passaram: `paladin_live_test`, `paladin_test`, `shadow_visual_test`, `redraw_test`, `corpse_freeze_test`. Incluem equipamento, invariância de combate e stats, redesenho e congelamento de cadáveres. `git diff --check` sem erros.

Ambiente: Godot 4.6 stable, Linux, Compatibility/OpenGL, Mesa llvmpipe (software). O projeto declara Godot 4.7; falta revisão na versão alvo e GPU real.

## Custo medido

Cena isolada de 40 corpos, overlay oculto, sem cenário ou simulação de combate. Valores de vértices são da malha compartilhada, não por frame. Nós incluem UnitView, visual e overlay existente.

| Unidade | Draw calls por corpo antes → depois | Nós por unidade | Ossos | Vértices antes → depois |
|---|---|---|---|---|
| Guerreiro | 1 → 1 | 3 → 3 | 13 → 13 | 4218 → 4218 |
| Sentinela | 1 → 1 | 3 → 3 | 67 → 67 | 9096 → 9096 |
| Paladino vivo | 1 → 1 | 3 → 3 | 45 → 45 | 10494 → 9981 |
| Paladino Sombra | 1 → 1 | 3 → 3 | 55 → 55 | 16500 → 15666 |

Contagem adicional total de objetos no cenário aquecido, incluindo recursos compartilhados e holders do benchmark: vivo 584 → 584; sombra 345 → 345. Não é contagem por unidade. A geometria caiu cerca de 5% em ambas as versões.

**Limite de performance:** duas rodadas intercaladas com renderização por software mediram CPU visual de 4,49–4,75 ms antes e 5,26–5,42 ms depois para 40 Paladinos vivos. Em headless, 5,44–5,49 ms antes e 4,47–4,95 ms depois. Portanto, não está demonstrada equivalência de tempo/FPS em GPU real: o resultado com renderização apresentou aumento, apesar da geometria menor. Manter como draft até revisar em Godot 4.7 no PC, com mesmas condições, câmera, quantidade de tropas e duração. Não alegar ganho de FPS a partir da redução de vértices.

## Reproduzir / continuidade com Claude

Usar `tools/bench/paladin_refinement_review.gd` nesta branch. Para comparar a base, copiar apenas esse helper para um worktree de `1936c3f`.

```sh
godot --path . --resolution 900x500 -s res://tools/bench/paladin_refinement_review.gd -- unit=sac_paladin
godot --path . --resolution 1120x620 -s res://tools/bench/paladin_refinement_review.gd -- poses=/tmp/paladin-poses.png
```

O helper mede 30 frames de aquecimento e 60 amostras; não substitui perfil de batalha. Pendências: aprovação visual do usuário e medição no hardware alvo. Não alterar gameplay ao continuar esta tarefa.
