class_name UnitDef
extends Resource
## Definição de uma unidade (dados, não instância). Um arquivo .tres por unidade em res://data/units/.
## Campos portados de UNIT_DEFS do HTML (hp, dmg, range, cd, speed, r, pal).
## A CombatSim não conhece este tipo: recebe o dicionário de to_stats().

## Id estável, igual à chave do HTML (ex.: "warrior", "u_warrior").
@export var id: StringName
@export var display_name: String
## Lado em que a unidade aparece nas listas (u_* = mortos-vivos do jogador).
@export var side: CombatUnit.Team = CombatUnit.Team.ENEMY

@export_group("Combate")
@export var max_hp := 50.0
@export var damage := 5.0
@export var attack_range := 32.0
## Segundos entre ataques.
@export var attack_interval := 1.0
@export var move_speed := 50.0
@export var radius := 12.0
## Ataque à distância: tipo do projétil (HTML: proj, ex.: "orb"). Vazio = corpo a corpo.
@export var projectile_kind: StringName = &""
## Habilidades mecânicas (ex.: "arcane_swords" = lâminas da Sentinela Arcana).
@export var abilities: Array[StringName] = []

@export_group("Visual")
## Script do visual desenhado por código (estende UnitVisual). Vazio = círculo padrão.
@export var visual_script: Script
## Cores do círculo padrão (CircleUnitVisual).
@export var body_color := Color(0.5, 0.5, 0.5)
@export var trim_color := Color(0.9, 0.9, 0.9)
## Versões sombra (u_*): estilo da conversão necromântica. Vazio = data/visuals/shadow_style.tres.
@export var shadow_style: ShadowStyle
## Parâmetros visuais próprios da unidade (ex.: PaladinLook), editáveis no Inspector. Opcional.
@export var visual_look: Resource

## Chaves de atributo que podem ser sobrescritas por instância (Sandbox).
const EDITABLE_STATS := ["hp", "dmg", "range", "cd", "speed"]


## Stats no formato que CombatUnit consome. `overrides` troca valores por instância.
func to_stats(overrides := {}) -> Dictionary:
	var stats := {
		id = id, name = display_name,
		hp = max_hp, dmg = damage, range = attack_range, cd = attack_interval,
		speed = move_speed, r = radius,
		projectile = projectile_kind, abilities = abilities,
	}
	stats.merge(overrides, true)
	return stats
