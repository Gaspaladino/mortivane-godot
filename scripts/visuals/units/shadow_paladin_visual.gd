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


# --- Peças e ossos da sombra (ver PaladinVisual: desenho leve) -----------------------------
const B_MIST := B_EXTRA
const B_AURA := B_EXTRA + 1
const B_PUFF := B_EXTRA + 2
## Fiapos: 3 fontes × 2 (capa/ombros) + 2 × 1 (pés) + 4 × 3 (dissolução na morte).
const PUFFS := 20


func _extra_bones() -> int:
	return 2 + PUFFS


func _layout_back() -> Array:
	return [[_part("mist", _mist_shape, false, false), B_MIST], [_part("aura", _aura_shape, false, false), B_AURA]]


func _layout_front() -> Array:
	var puff := _part("puff", _puff_shape, false, false)
	var out := []
	for j in PUFFS:
		out.append([puff, B_PUFF + j])
	return out


## Névoa no chão (largura 11): poça roxa + núcleo escuro.
func _mist_shape() -> void:
	_bake.fill(LiteBuilder.ring(Vector2.ZERO, Vector2(11.0 * 1.35, 11.0 * 0.42), 24), Color(shadow_style.smoke, shadow_style.smoke.a * 0.35 * shadow_style.smoke_amount))
	_bake.fill(LiteBuilder.ring(Vector2.ZERO, Vector2(11.0, 11.0 * 0.3), 24), Color(0.02, 0.0, 0.05, 0.42))


## Aura atrás do corpo (raios 15 × 24).
func _aura_shape() -> void:
	var a := 0.09 * shadow_style.aura
	for i in 4:
		var s := 1.0 - i * 0.2
		_bake.fill(LiteBuilder.ring(Vector2.ZERO, Vector2(15.0 * s, 24.0 * s), 24), Color(shadow_style.energy, a * (0.55 + i * 0.35)))


func _puff_shape() -> void:
	_bake.fill(PackedVector2Array([
		Vector2(-1.0, 0.4), Vector2(-0.4, -1.2), Vector2(0.2, -2.4), Vector2(0.7, -0.9), Vector2(1.0, 0.5), Vector2(0.0, 1.0),
	]), Color(shadow_style.smoke, shadow_style.smoke.a * shadow_style.smoke_amount * 0.8))


func _pose_ground() -> void:
	var lying := clampf(absf(p_rot) / 90.0, 0.0, 1.0)
	var shift := -14.0 * lying * _k() * _facing
	var w := (11.0 + 9.0 * lying) * _k() / 11.0
	var b := 0.95 + 0.05 * sin((_time + _seed) * 1.3)
	_skin.set_bone(B_MIST, Transform2D(0.0, Vector2(w * b, w), 0.0, Vector2(shift, FOOT_Y)))
	_skin.hide_bone(B_GROUND)
	if _life() > 0.5:
		var pulse := (1.0 + 0.03 * sin((_time + _seed) * 1.7 * shadow_style.pulse_speed)) * _k()
		_skin.set_bone(B_AURA, Transform2D(0.0, Vector2(pulse, pulse), 0.0, Vector2(0, FOOT_Y - 19.0 * _k())))
	else:
		_skin.hide_bone(B_AURA)


## Fumaça subindo dos ombros, da barra da capa e dos pés; na morte, o corpo se desfaz.
func _pose_extra(root: Transform2D, torso: Transform2D) -> void:
	var k := _life()
	var dissolve := 0.0
	if _death_t >= 0.0:
		dissolve = clampf(_death_t / 0.6, 0.0, 1.0) * (1.0 - clampf((_death_t - 1.4) / 1.2, 0.0, 1.0))
	var sw := -p_cape * 0.14
	var n := _smoke(B_PUFF, torso, PackedVector2Array([Vector2(-3.4, -15.0), Vector2(-11.6 + sw, 12.0), Vector2(-6.0 + sw * 0.6, 12.8)]),
		_time, _seed, 10.0, 1.7, 2, minf(maxf(k, dissolve * 1.8), 1.0))
	n = _smoke(n, root, PackedVector2Array([Vector2(-3.0, 0.0), Vector2(4.0, 0.0)]), _time * 0.8, _seed + 3.0, 6.0, 1.4, 1, k)
	_smoke(n, root, PackedVector2Array([Vector2(0, -8), Vector2(0, -18), Vector2(3, -26), Vector2(-3, -32)]), _time * 1.3, _seed + 7.0, 15.0, 2.4, 3, dissolve)


## Fiapos subindo de `sources` (mesma conta do ShadowFX.smoke); o esmaecer vira encolher.
func _smoke(bone: int, space: Transform2D, sources: PackedVector2Array, time: float, seed: float,
		rise: float, size: float, count: int, k: float) -> int:
	for si in sources.size():
		for j in count:
			if k <= 0.0:
				_skin.hide_bone(bone)
			else:
				var h := ShadowFX._hash(si * 7.0 + j, seed)
				var u := fposmod(time * (0.32 + 0.18 * h) + h + float(j) / count, 1.0)
				var p := sources[si] + Vector2(sin(u * 5.0 + h * 9.0) * 1.6 + u * 1.2, -rise * u)
				var r := size * (1.0 - 0.55 * u) * (0.8 + 0.4 * h) * sin(u * PI) * k
				_skin.set_bone(bone, space * Transform2D(0.0, Vector2(r, r), 0.0, p))
			bone += 1
	return bone


## Capa rasgada em pontas.
func _cape_shape(pts: PackedVector2Array) -> PackedVector2Array:
	var a := pts[2]
	var b := pts[3]
	var c := pts[4]
	return PackedVector2Array([
		pts[0], pts[1],
		a + Vector2(-0.4, 0.6), a.lerp(b, 0.3) + Vector2(0.2, -3.0), a.lerp(b, 0.55) + Vector2(0, 0.8),
		b + Vector2(0, -1.0), b.lerp(c, 0.45) + Vector2(0.3, -3.4), c.lerp(b, 0.15) + Vector2(0, 0.6), c,
	])


## Barra da capa com um fio de energia.
func _draw_cape_extra(shape: PackedVector2Array) -> void:
	_pline(shape.slice(2), Color(shadow_style.energy, 0.45), 0.8)


## Tabardo com a barra rasgada.
func _tabard_front() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-0.6, -0.4), Vector2(5.8, -0.4), Vector2(6.2, 10.6), Vector2(4.8, 8.4), Vector2(3.8, 10.4),
		Vector2(2.4, 8.2), Vector2(1.2, 10.8), Vector2(0.2, 8.6), Vector2(-0.8, 10.6),
	])


func _draw_torso_wear() -> void:
	LiteShadowParts.crack(self, PackedVector2Array([Vector2(1.2, -14.6), Vector2(2.4, -11.8), Vector2(1.0, -9.6), Vector2(2.6, -6.8), Vector2(1.6, -4.0)]), shadow_style)
	LiteShadowParts.crack(self, PackedVector2Array([Vector2(2.4, -11.8), Vector2(5.0, -10.8), Vector2(6.2, -9.0)]), shadow_style, 0.8)


## Visor com dois olhos roxos (leitura imediata de "revivido").
func _draw_visor() -> void:
	super()
	LiteShadowParts.eye(self, Vector2(3.0, -6.9), 0.75, shadow_style)
	LiteShadowParts.eye(self, Vector2(5.4, -7.0), 0.7, shadow_style)


## Sol do escudo e do tabardo: estrela roxa com halo.
func _draw_emblem(c: Vector2, size: float) -> void:
	_disc(c, size * 1.3, Color(shadow_style.energy, 0.17))
	super(c, size)
	_star(c, size * 0.4, Color(shadow_style.energy_core, 0.8))


func _draw_shield_wear() -> void:
	LiteShadowParts.crack(self, PackedVector2Array([Vector2(-2.6, -7.6), Vector2(-1.4, -4.8), Vector2(-2.4, -2.4)]), shadow_style, 0.9)
	LiteShadowParts.crack(self, PackedVector2Array([Vector2(1.6, 2.6), Vector2(2.4, 5.2), Vector2(1.2, 7.4)]), shadow_style, 0.9)


## Chama roxa no fio da espada.
func _draw_blade_extra() -> void:
	for i in 6:
		var u := (i + 0.5) / 6.0
		var y := lerpf(-3.4, -16.4, u)
		var lick := 1.2 + 1.3 * 0.5 * 0.85
		var side := -1.0 if i % 2 == 0 else 1.0
		_fill(PackedVector2Array([
			Vector2(side * 1.0, y - 1.0), Vector2(side * 1.1, y + 1.2), Vector2(side * (1.3 + lick), y - 1.6),
		]), Color(shadow_style.energy, 0.55))
	LiteShadowParts.crack(self, PackedVector2Array([Vector2(0, -2.6), Vector2(0.1, -9.0), Vector2(-0.1, -15.6)]), shadow_style, 1.0, 0.6)


# --- Cores dos efeitos: roxo com resto do dourado --------------------------------------------

func _trail_color() -> Color:
	return shadow_style.energy


func _trail_core() -> Color:
	return gold_light


func _ring_color() -> Color:
	return shadow_style.energy


func _barrier_fill() -> Color:
	return Color(0.29, 0.14, 0.4)
