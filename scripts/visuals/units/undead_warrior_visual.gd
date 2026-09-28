class_name UndeadWarriorVisual
extends WarriorVisual
## Guerreiro Morto-Vivo: o MESMO rig do Guerreiro ("era um Guerreiro e foi reanimado").
## Muda só: paleta (metal escuro/gasto, tecido verde-musgo, pluma desbotada), estilo de
## animação (irregular, torto, ataque mais bruto, queda sem controle) e desgaste
## (capa rasgada, lâmina lascada, amassado no elmo, rachadura no peitoral, brilho na fenda).


func _init() -> void:
	# paleta
	metal = Color("8b9288")
	metal_dark = Color("4d544c")
	metal_light = Color("adb4a8")
	outline = Color("191d19")
	cloth = Color("3f5731")
	cloth_dark = Color("26391e")
	plume = Color("66704f")
	leather = Color("3d3125")
	blade = Color("a7ab9f")
	visor = Color("0b0f0b")
	visor_glow = Color(0.62, 1.0, 0.5, 0.85)

	# postura e animação
	idle_bob = 0.35
	idle_speed = 1.6
	jitter = 0.55
	posture_lean = 7.0
	head_tilt = 13.0
	head_drop = 0.8
	back_arm_rest = 24.0
	stride = 14.0
	leg_swing = 25.0
	leg_phase_gap = PI * 0.78
	back_leg_amp = 0.65
	walk_bob = 1.4
	walk_lurch = 6.0
	arm_swing = 9.0
	windup_time = 0.26
	strike_time = 0.09
	recover_time = 0.3
	rest_arm = -12.0
	rest_sword = 58.0
	windup_arm = 158.0
	windup_sword = -6.0
	windup_lean = -4.0
	strike_arm = -58.0
	strike_sword = 128.0
	strike_lean = 14.0
	lunge = 3.4
	death_time = 0.8
	death_forward = true


## Barra da capa rasgada em pontas irregulares.
func _cape_shape(pts: PackedVector2Array) -> PackedVector2Array:
	var a := pts[2]
	var b := pts[3]
	var c := pts[4]
	return PackedVector2Array([
		pts[0], pts[1],
		a, a.lerp(b, 0.35) + Vector2(0.3, -2.4), a.lerp(b, 0.6) + Vector2(0, 0.6),
		b + Vector2(0, -0.8), b.lerp(c, 0.5) + Vector2(0.2, -3.0), c,
	])


## Lâmina com um lascado no fio e a ponta quebrada torta.
func _blade_shape() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-1.25, -1.9), Vector2(1.25, -1.9), Vector2(1.15, -7.6), Vector2(0.1, -8.6),
		Vector2(1.05, -9.8), Vector2(1.0, -13.2), Vector2(-0.3, -15.0), Vector2(-1.1, -13.0),
	])


func _draw_torso_wear() -> void:
	_line(Vector2(-2.6, -12.2), Vector2(-1.2, -9.6), _c(outline), 0.8)
	_line(Vector2(-1.2, -9.6), Vector2(-2.2, -7.4), _c(outline), 0.8)


func _draw_helmet_wear() -> void:
	_line(Vector2(-3.8, -11.2), Vector2(-2.0, -9.8), _c(outline), 0.8)
