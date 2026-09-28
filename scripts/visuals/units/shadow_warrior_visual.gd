class_name ShadowWarriorVisual
extends WarriorVisual
## Guerreiro Sombra: o Guerreiro morto e reerguido pelo necromante. MESMO rig e mesma leitura
## de classe (elmo fechado, peitoral, espada, capa); convertido pela regra ShadowStyle:
##   - armadura em grafite violeta, capa quase preta com um resto do vermelho original;
##   - contorno roxo em todas as peças (a silhueta se destaca do chão e do fundo);
##   - olhos roxos na fenda do elmo, fissuras de energia no peitoral e no elmo;
##   - a pluma vira uma chama espectral; o fio da espada brilha;
##   - aura suave, névoa roxa no chão e poucos fiapos de fumaça subindo da capa e dos ombros.
## Animação: pesada e ameaçadora (não cambaleante como um zumbi); desaba para frente e se
## desfaz em fumaça ao morrer.


func _init() -> void:
	shadow = true
	# postura e animação
	idle_bob = 0.4
	idle_speed = 1.5
	jitter = 0.16
	posture_lean = 4.0
	head_tilt = 5.0
	head_drop = 0.3
	back_arm_rest = 16.0
	stride = 15.0
	leg_swing = 27.0
	leg_phase_gap = PI * 0.94
	back_leg_amp = 0.9
	walk_bob = 1.0
	walk_lurch = 2.0
	arm_swing = 11.0
	windup_time = 0.24
	strike_time = 0.08
	recover_time = 0.28
	rest_arm = -16.0
	rest_sword = 48.0
	windup_arm = 150.0
	windup_sword = -16.0
	windup_lean = -5.0
	strike_arm = -70.0
	strike_sword = 118.0
	strike_lean = 12.0
	lunge = 3.0
	death_time = 0.8
	death_forward = true


## A paleta viva do Guerreiro, convertida pela regra da sombra.
func _apply_shadow_style(s: ShadowStyle) -> void:
	metal = s.convert(metal)
	metal_dark = s.convert(metal_dark)
	metal_light = s.convert(metal_light).lightened(0.12)
	cloth = s.convert(cloth, 0.22)
	cloth_dark = s.convert(cloth_dark, 0.15)
	plume = s.energy
	leather = s.convert(leather)
	blade = s.convert(blade, 0.3)
	visor = s.body_dark
	visor_glow = s.energy
	flash_color = s.energy_core


## 1 = de pé; cai a 0 enquanto o corpo escurece na morte.
func _life() -> float:
	return 1.0 - clampf(p_dim / 0.2, 0.0, 1.0)


func _pulse() -> float:
	return ShadowFX.pulse(shadow_style, _time, _seed)


# --- Pontos de extensão do rig -------------------------------------------------------------

## Névoa roxa no chão + aura atrás do corpo (espaço do UnitView, sem espelhar).
func _draw_shadow() -> void:
	var lying := clampf(absf(p_rot) / 90.0, 0.0, 1.0)
	var shift := 12.0 * lying * RIG_SCALE * _facing
	ShadowFX.ground_mist(self, Vector2(shift, FOOT_Y), 9.0 + 7.0 * lying, shadow_style, _time + _seed)
	var k := _life()
	if k > 0.0:
		ShadowFX.aura(self, Vector2(0, FOOT_Y - 17.0 * RIG_SCALE) + p_offset * RIG_SCALE, Vector2(12.0, 21.0), shadow_style, _time + _seed, k)


## Capa rasgada em pontas irregulares.
func _cape_shape(pts: PackedVector2Array) -> PackedVector2Array:
	var a := pts[2]
	var b := pts[3]
	var c := pts[4]
	var f := sin(_time * 3.1 + _seed) * 0.5
	return PackedVector2Array([
		pts[0], pts[1],
		a + Vector2(-0.4, 0.8 + f), a.lerp(b, 0.35) + Vector2(0.3, -2.2), a.lerp(b, 0.6) + Vector2(0, 1.2 - f),
		b + Vector2(0, -0.8), b.lerp(c, 0.5) + Vector2(0.2, -2.6), c,
	])


func _draw_cape(torso: Transform2D) -> void:
	super(torso)
	if _rim_pass:
		return
	# barra da capa com um fio de energia (continua no espaço do tronco)
	var sw := -p_cape * 0.12
	var hem := _cape_shape(PackedVector2Array([
		Vector2(0.4, -12.4), Vector2(-5.4, -12.0), Vector2(-10.6 + sw, 1.6), Vector2(-6.4 + sw * 0.7, 3.0), Vector2(-2.0 + sw * 0.4, 0.6),
	])).slice(2)
	draw_polyline(hem, Color(shadow_style.energy, 0.45 * _life()), 0.8, true)


## Pluma → chama espectral roxa que ondula para trás (mais para trás ao andar).
func _draw_plume() -> void:
	var k := _life()
	var drag := 1.0 + 0.35 * _walk_w
	var base := Vector2(-1.2, -12.2)
	_poly(PackedVector2Array([base + Vector2(1.2, 0.2), base + Vector2(-2.4, -1.8), base + Vector2(-4.6, 0.6), base + Vector2(-1.6, 1.2)]), _c(metal_dark))
	if k <= 0.0 or _rim_pass:
		return
	# trilha ondulante de "brasas" que afinam para trás: o penacho vira fogo espectral
	var n := 7
	for j in n:
		var u := float(j) / (n - 1)
		var wave := sin(_time * 6.0 - u * 4.0 + _seed) * (0.3 + 1.0 * u)
		var c := base + Vector2(-9.5 * u * drag, -1.0 + 2.8 * u + wave)
		var r := lerpf(2.1, 0.5, u) * (0.9 + 0.1 * sin(_time * 9.0 + j))
		draw_circle(c, r * 1.7, Color(shadow_style.energy, 0.22 * k * (1.0 - u * 0.5)))
		draw_circle(c, r, Color(shadow_style.energy.lerp(shadow_style.energy_core, 0.45 * (1.0 - u)), 0.85 * k * (1.0 - u * 0.6)))


## Olhos: dois pontos roxos na fenda do elmo (lidos mesmo de longe).
func _draw_visor() -> void:
	if _rim_pass:
		return
	var slit := PackedVector2Array([Vector2(1.0, -6.9), Vector2(6.2, -7.2), Vector2(6.2, -5.7), Vector2(1.0, -5.6)])
	draw_colored_polygon(slit, _c(visor))
	var k := _life() * (1.0 - p_flash)
	var pulse := 0.75 + 0.25 * _pulse()
	ShadowFX.eye(self, Vector2(3.4, -6.3), 0.75, shadow_style, pulse, k)
	ShadowFX.eye(self, Vector2(5.4, -6.4), 0.7, shadow_style, pulse, k)


## Fissuras de energia no peitoral.
func _draw_torso_wear() -> void:
	if _rim_pass:
		return
	var k := _life()
	var p := _pulse()
	ShadowFX.crack(self, PackedVector2Array([Vector2(-1.4, -12.4), Vector2(-0.4, -10.2), Vector2(-1.8, -8.2), Vector2(-0.6, -5.8), Vector2(-1.4, -3.2)]), shadow_style, p, k)
	ShadowFX.crack(self, PackedVector2Array([Vector2(-0.4, -10.2), Vector2(1.6, -9.4), Vector2(2.4, -8.0)]), shadow_style, p, k * 0.8)


func _draw_helmet_wear() -> void:
	if _rim_pass:
		return
	ShadowFX.crack(self, PackedVector2Array([Vector2(-3.8, -11.4), Vector2(-2.3, -9.9), Vector2(-3.1, -8.4)]), shadow_style, _pulse(), _life() * 0.8)


## Lâmina lascada (a arma do Guerreiro, gasta pela morte).
func _blade_shape() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-1.25, -1.9), Vector2(1.25, -1.9), Vector2(1.15, -7.6), Vector2(0.4, -8.4),
		Vector2(1.05, -9.6), Vector2(1.0, -13.4), Vector2(0.0, -15.8), Vector2(-1.1, -13.4),
	])


## Fio da espada aceso em roxo (mais forte no golpe).
func _draw_blade_extra() -> void:
	if _rim_pass:
		return
	var strike := 0.0
	if _strike_t >= 0.0:
		strike = 1.0 - clampf(_strike_t / (strike_time + recover_time), 0.0, 1.0)
	ShadowFX.crack(self, PackedVector2Array([Vector2(0, -2.4), Vector2(0.1, -8.0), Vector2(-0.1, -13.6)]), shadow_style, maxf(_pulse() * 0.6, strike), _life())


## Fumaça subindo dos ombros, da barra da capa e dos pés; na morte, o corpo se desfaz.
func _draw_fx_front(root: Transform2D, torso: Transform2D) -> void:
	if _rim_pass:
		return
	var k := _life()
	var dissolve := 0.0
	if _death_t >= 0.0:
		dissolve = clampf(_death_t / 0.6, 0.0, 1.0) * (1.0 - clampf((_death_t - 1.2) / 1.2, 0.0, 1.0))
	if k <= 0.0 and dissolve <= 0.0:
		return
	var sw := -p_cape * 0.12
	_with(torso)
	ShadowFX.smoke(self, PackedVector2Array([Vector2(-2.6, -12.0), Vector2(-9.8 + sw, 1.8), Vector2(-5.0 + sw * 0.6, 2.6)]),
		shadow_style, _time, _seed, 9.0, 1.5, 2, maxf(k, dissolve * 1.8))
	_with(root)
	ShadowFX.smoke(self, PackedVector2Array([Vector2(-2.0, 0.0), Vector2(3.0, 0.0)]), shadow_style, _time * 0.8, _seed + 3.0, 5.0, 1.3, 1, k)
	if dissolve > 0.0:
		ShadowFX.smoke(self, PackedVector2Array([Vector2(0, -6), Vector2(0, -14), Vector2(3, -22), Vector2(-3, -26)]),
			shadow_style, _time * 1.3, _seed + 7.0, 14.0, 2.2, 3, dissolve)
