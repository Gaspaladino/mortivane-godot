class_name ShadowPaladinVisual
extends PaladinVisual
## Paladino Sombra: "mesma força, outro senhor". O MESMO rig e a mesma silhueta do Paladino
## (elmo, auréola, ombreiras, escudo, espada, tabardo, capa), convertidos pela regra ShadowStyle:
##   - armadura em grafite violeta; tabardo desbotado e rasgado; capa quase preta, rasgada;
##   - o DOURADO continua (auréola, filetes, guarda da espada, borda do escudo): identidade da
##     classe preservada, só mais escura;
##   - o sol do escudo e do tabardo vira energia roxa; visor com olhos roxos; fissuras roxas
##     no peitoral e no escudo; chama roxa no fio da espada;
##   - borda roxa só na silhueta, aura, névoa no chão e pouca fumaça;
##   - rastro do golpe, barreira e anéis em roxo com resto do dourado;
##   - na morte a energia se apaga e o corpo solta fumaça (o resto fica no chão).
## Animação: a mesma base pesada; só a energia é instável.


func _init() -> void:
	shadow = true
	jitter = 0.1


func _apply_shadow_style(s: ShadowStyle) -> void:
	ivory = s.convert(ivory)
	ivory_light = s.convert(ivory_light).lightened(0.1)
	steel_shade = s.convert(steel_shade)
	under_armor = s.body_dark
	cloth = s.convert(cloth, 0.4)
	cape_color = s.body_dark.lerp(s.energy, 0.14)
	blade = s.convert(blade, 0.2)
	leather = s.convert(leather)
	# o dourado é a identidade do Paladino: fica, só um pouco mais escuro
	gold = gold.darkened(0.12)
	gold_light = gold_light.darkened(0.18)
	emblem = s.energy
	holy = s.energy
	holy_edge = gold_light
	visor = s.body_dark
	flash_color = s.energy_core


func _life() -> float:
	return 1.0 - clampf(p_dim / 0.2, 0.0, 1.0)


func _pulse() -> float:
	return ShadowFX.pulse(shadow_style, _time, _seed)


# --- Pontos de extensão ---------------------------------------------------------------------

func _draw_shadow() -> void:
	var lying := clampf(absf(p_rot) / 90.0, 0.0, 1.0)
	var shift := -14.0 * lying * _k() * _facing
	ShadowFX.ground_mist(self, Vector2(shift, FOOT_Y), (11.0 + 9.0 * lying) * _k(), shadow_style, _time + _seed)
	var k := _life()
	if k > 0.0:
		ShadowFX.aura(self, Vector2(0, FOOT_Y - 19.0 * _k()), Vector2(15.0, 24.0) * _k(), shadow_style, _time + _seed, k)


## Capa rasgada em pontas que tremulam.
func _cape_shape(pts: PackedVector2Array) -> PackedVector2Array:
	var a := pts[2]
	var b := pts[3]
	var c := pts[4]
	var f := sin(_time * 2.6 + _seed) * 0.6
	return PackedVector2Array([
		pts[0], pts[1],
		a + Vector2(-0.4, 0.6 + f), a.lerp(b, 0.3) + Vector2(0.2, -3.0), a.lerp(b, 0.55) + Vector2(0, 0.8 - f),
		b + Vector2(0, -1.0), b.lerp(c, 0.45) + Vector2(0.3, -3.4), c.lerp(b, 0.15) + Vector2(0, 0.6 + f), c,
	])


func _draw_cape(torso: Transform2D) -> void:
	super(torso)
	if _rim_pass:
		return
	var sw := -p_cape * 0.14
	var hem := _cape_shape(PackedVector2Array([
		Vector2(1.0, -15.0), Vector2(-6.4, -14.4), Vector2(-12.6 + sw, 12.0), Vector2(-7.4 + sw * 0.7, 13.4), Vector2(-2.4 + sw * 0.4, 11.2),
	])).slice(2)
	draw_polyline(hem, Color(shadow_style.energy, 0.45 * _life()), 0.8, true)


## Tabardo com a barra rasgada.
func _tabard_front() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-0.6, -0.4), Vector2(5.8, -0.4), Vector2(6.2, 10.6), Vector2(4.8, 8.4), Vector2(3.8, 10.4),
		Vector2(2.4, 8.2), Vector2(1.2, 10.8), Vector2(0.2, 8.6), Vector2(-0.8, 10.6),
	])


func _draw_torso_wear() -> void:
	var k := _life()
	var p := _pulse()
	ShadowFX.crack(self, PackedVector2Array([Vector2(1.2, -14.6), Vector2(2.4, -11.8), Vector2(1.0, -9.6), Vector2(2.6, -6.8), Vector2(1.6, -4.0)]), shadow_style, p, k)
	ShadowFX.crack(self, PackedVector2Array([Vector2(2.4, -11.8), Vector2(5.0, -10.8), Vector2(6.2, -9.0)]), shadow_style, p, k * 0.8)


## Visor com dois olhos roxos (leitura imediata de "revivido").
func _draw_visor() -> void:
	super()
	var k := _life() * (1.0 - p_flash)
	var pulse := 0.75 + 0.25 * _pulse()
	ShadowFX.eye(self, Vector2(3.0, -6.9), 0.75, shadow_style, pulse, k)
	ShadowFX.eye(self, Vector2(5.4, -7.0), 0.7, shadow_style, pulse, k)


## Sol do escudo e do tabardo: estrela roxa que pulsa, com halo.
func _draw_emblem(c: Vector2, size: float) -> void:
	var k := _life()
	if k > 0.0:
		draw_circle(c, size * 1.3, Color(shadow_style.energy, 0.2 * k * (0.7 + 0.3 * _pulse())))
	super(c, size)
	if k > 0.0:
		_star(c, size * 0.4, Color(shadow_style.energy_core, 0.8 * k))


func _draw_shield_wear() -> void:
	var k := _life()
	var p := _pulse()
	ShadowFX.crack(self, PackedVector2Array([Vector2(-2.6, -7.6), Vector2(-1.4, -4.8), Vector2(-2.4, -2.4)]), shadow_style, p, k * 0.9)
	ShadowFX.crack(self, PackedVector2Array([Vector2(1.6, 2.6), Vector2(2.4, 5.2), Vector2(1.2, 7.4)]), shadow_style, 1.0 - p, k * 0.9)


## Chama roxa correndo pelo fio da espada (mais forte no golpe).
func _draw_blade_extra() -> void:
	var k := _life()
	if k <= 0.0:
		return
	var strike := 0.0
	if _strike_t >= 0.0:
		strike = 1.0 - clampf(_strike_t / RECOVER_END, 0.0, 1.0)
	var boost := 0.7 + 0.6 * maxf(strike, p_wind)
	for i in 6:
		var u := (i + 0.5) / 6.0
		var y := lerpf(-3.4, -16.4, u)
		var lick := 1.2 + 1.3 * (0.5 + 0.5 * sin(_time * 9.0 + i * 1.9 + _seed)) * boost
		var side := -1.0 if i % 2 == 0 else 1.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(side * 1.0, y - 1.0), Vector2(side * 1.1, y + 1.2), Vector2(side * (1.3 + lick), y - 1.6),
		]), Color(shadow_style.energy, 0.55 * k))
	ShadowFX.crack(self, PackedVector2Array([Vector2(0, -2.6), Vector2(0.1, -9.0), Vector2(-0.1, -15.6)]), shadow_style, maxf(_pulse() * 0.6, strike), k)


func _draw_fx_front(root: Transform2D, torso: Transform2D) -> void:
	if _rim_pass:
		return
	var k := _life()
	var dissolve := 0.0
	if _death_t >= 0.0:
		dissolve = clampf(_death_t / 0.6, 0.0, 1.0) * (1.0 - clampf((_death_t - 1.4) / 1.2, 0.0, 1.0))
	if k <= 0.0 and dissolve <= 0.0:
		return
	var sw := -p_cape * 0.14
	_with(torso)
	ShadowFX.smoke(self, PackedVector2Array([Vector2(-3.4, -15.0), Vector2(-11.6 + sw, 12.0), Vector2(-6.0 + sw * 0.6, 12.8)]),
		shadow_style, _time, _seed, 10.0, 1.7, 2, maxf(k, dissolve * 1.8))
	_with(root)
	ShadowFX.smoke(self, PackedVector2Array([Vector2(-3.0, 0.0), Vector2(4.0, 0.0)]), shadow_style, _time * 0.8, _seed + 3.0, 6.0, 1.4, 1, k)
	if dissolve > 0.0:
		ShadowFX.smoke(self, PackedVector2Array([Vector2(0, -8), Vector2(0, -18), Vector2(3, -26), Vector2(-3, -32)]),
			shadow_style, _time * 1.3, _seed + 7.0, 15.0, 2.4, 3, dissolve)


# --- Cores dos efeitos: roxo com resto do dourado --------------------------------------------

func _trail_color() -> Color:
	return shadow_style.energy


func _trail_core() -> Color:
	return gold_light


func _ring_color() -> Color:
	return shadow_style.energy


func _barrier_fill() -> Color:
	return Color(0.29, 0.14, 0.4)
