class_name SentinelShadowVisual
extends SentinelVisual
## Sentinela Arcana Sombra: "a mesma vigília, agora eterna". MESMO rig e mesma leitura de classe
## (chapéu pontudo, manto em camadas, joia, selo arcano, duas lâminas) convertidos pela regra
## ShadowStyle:
##   - paleta viva convertida para grafite violeta; o selo arcano continua azul (identidade);
##   - silhueta com borda roxa, olhos roxos, fissuras de energia na saia, aura e névoa no chão;
##   - manto e capelete com bordas rasgadas e fumaça roxa animada;
##   - idle com tremor arcano, lâminas instáveis e agressivas;
##   - deslizar mais arrastado; disparo roxo com aura; HIT etéreo (o corpo tremula);
##   - morte espectral: sobe, se desfaz em fumaça e as lâminas se partem em fragmentos.


func _init() -> void:
	shadow = true
	jitter = 0.35
	breath = 0.009
	hem_idle = 1.0
	stride = 14.0
	glide_bob = 0.9
	move_lean = 6.0
	hem_trail = 4.2
	cast_windup = 0.34
	windup_lean = -4.5
	cast_lean = 8.0
	cast_open = 0.85
	sword_float = 2.4
	sword_wobble = 0.09
	sword_jitter = 0.12
	death_time = 1.1


## A paleta viva da Sentinela, convertida pela regra da sombra.
func _apply_shadow_style(st: ShadowStyle) -> void:
	robe = st.convert(robe, 0.1)
	robe_light = st.convert(robe_light, 0.12).lightened(0.06)
	robe_dark = st.convert(robe_dark)
	trim = st.convert(trim, 0.15)
	skin = st.convert(skin, 0.1)
	hair = st.body_dark
	glow = st.energy
	gem_color = st.energy
	symbol = Color("5f8ee0")          # o selo arcano continua azul nas duas versões
	eye = st.eye
	core = st.energy_core
	wisp = st.smoke
	flash_color = st.energy_core


func _life() -> float:
	return 1.0 - clampf(p_dim / 0.2, 0.0, 1.0)


# --- Peças e ossos da sombra (ver SentinelVisual: desenho leve) -----------------------------

func _layout_back() -> Array:
	var out := [
		[_part("mist", _mist_shape, false, false), B_GROUND],
		[_part("aura", _aura_shape, false, false), B_AURA],
	]
	var tongue := _part("tongue_back", _tongue_shape.bind(0.8), false, false)
	for k in WISPS_BACK:
		out.append([tongue, B_WISP + k])
	var side := _part("wisp_side", _side_wisp_shape, false, false)
	for k in WISPS_SIDE:
		out.append([side, B_WISP + WISPS_BACK + k])
	return out


func _layout_front() -> Array:
	var out := []
	var tongue := _part("tongue_front", _tongue_shape.bind(0.55), false, false)
	for k in WISPS_FRONT:
		out.append([tongue, B_WISP + WISPS_BACK + WISPS_SIDE + k])
	var puff := _part("puff", _puff_shape, false, false)
	for k in WISP_PUFFS:
		out.append([puff, B_WISP + WISPS_BACK + WISPS_SIDE + WISPS_FRONT + k])
	return out


## Névoa no chão (largura 11): poça roxa + núcleo escuro.
func _mist_shape() -> void:
	_bake.fill(LiteBuilder.ring(Vector2.ZERO, Vector2(11.0 * 1.35, 11.0 * 0.42), 24), Color(shadow_style.smoke, shadow_style.smoke.a * 0.35 * shadow_style.smoke_amount))
	_bake.fill(LiteBuilder.ring(Vector2.ZERO, Vector2(11.0, 11.0 * 0.3), 24), Color(0.02, 0.0, 0.05, 0.42))


## Aura atrás do corpo (raios 14 × 22).
func _aura_shape() -> void:
	var a := 0.09 * shadow_style.aura
	for i in 4:
		var s := 1.0 - i * 0.2
		_bake.fill(LiteBuilder.ring(Vector2.ZERO, Vector2(14.0 * s, 22.0 * s), 24), Color(shadow_style.energy, a * (0.55 + i * 0.35)))


## Língua de fumaça unitária (altura 1, sem inclinação); o osso dá altura e inclinação.
func _tongue_shape(alpha_k: float) -> void:
	_bake.fill(PackedVector2Array([Vector2(-1.3, 0), Vector2(1.3, 0), Vector2(0.6, -0.55), Vector2(0.0, -1.0)]), Color(wisp, wisp.a * alpha_k * 0.75))


## Fiapo lateral unitário: base vertical em x = 0, ponta em (1, 0); o osso estica e vira a ponta.
func _side_wisp_shape() -> void:
	_bake.fill(PackedVector2Array([Vector2(0, -1.4), Vector2(0, 1.4), Vector2(1.0, 0.0)]), Color(wisp, wisp.a * 0.8 * 0.7 * 0.5))


func _puff_shape() -> void:
	_bake.fill(PackedVector2Array([
		Vector2(-1.0, 0.4), Vector2(-0.4, -1.2), Vector2(0.2, -2.4), Vector2(0.7, -0.9), Vector2(1.0, 0.5), Vector2(0.0, 1.0),
	]), Color(shadow_style.smoke, shadow_style.smoke.a * shadow_style.smoke_amount * 0.8))


## Fragmento de lâmina (morte da sombra): triângulo escuro com borda de energia.
func _death_bit_shape() -> void:
	var tri := PackedVector2Array([Vector2.from_angle(0.0), Vector2.from_angle(2.3) * 0.7, Vector2.from_angle(4.1) * 0.8])
	_bake.fill(tri, Color(robe_dark, 1.0))
	_bake.outline(tri, Color(glow, 1.0), 0.7)


func _pose_ground() -> void:
	var w := (1.0 + 0.5 * p_hat_fall)
	var b := 0.95 + 0.05 * sin((_time + _seed) * 1.3)
	_skin.set_bone(B_GROUND, Transform2D(0.0, Vector2(w * b, w), 0.0, Vector2(0, FOOT_Y)))
	var k := _life() * p_alpha
	if k > 0.5:
		var pulse := 1.0 + 0.03 * sin((_time + _seed) * 1.7 * shadow_style.pulse_speed)
		_skin.set_bone(B_AURA, Transform2D(0.0, Vector2(pulse, pulse), 0.0, Vector2(0, FOOT_Y - 17.0) + Vector2(p_offset.x * _facing, p_offset.y)))
	else:
		_skin.hide_bone(B_AURA)


## Fumaça sombria nas bordas do manto: línguas atrás e na frente, fiapos laterais, fiapos do capelete.
func _pose_extra(root: Transform2D) -> void:
	var boost := 1.0 + p_wisp
	var bone := B_WISP
	for layer in 2:
		var front := layer == 1
		if front:
			bone = B_WISP + WISPS_BACK + WISPS_SIDE
		var n := WISPS_FRONT if front else WISPS_BACK
		for k in n:
			var u := (k + (0.5 if front else 0.0)) / float(n)
			var x := lerpf(10.0, -11.5, u) + p_hem * lerpf(0.4, 1.0, u)
			var f := 0.5 + 0.5 * sin(_time * (3.0 + k * 0.7) + k * 2.3 + _seed)
			var h := (2.6 + 2.6 * f) * boost
			var lean := -1.5 + p_hem * 0.4 + sin(_time * 2.0 + k) * 0.8
			var foot := Vector2(x, 0.8 if k % 2 == 0 else -0.6)
			_skin.set_bone(bone, root * Transform2D(Vector2(1, 0), Vector2(-lean, h), foot))
			bone += 1
		if not front:
			for side in [-1.0, 1.0]:
				for k in 2:
					var f := 0.5 + 0.5 * sin(_time * 4.2 + k * 2.0 + side + _seed)
					var anchor := Vector2(side * (9.5 - k * 2.5), -4.0 - k * 5.0)
					_skin.set_bone(bone, root * Transform2D(Vector2(side * (2.4 + 2.0 * f) * boost, -1.0 - 1.5 * f), Vector2(0, 1), anchor))
					bone += 1
	# fiapos subindo das pontas do capelete
	var srcs := [Vector2(-9.0, -12.6), Vector2(9.4, -12.0)]
	var amount := minf(_life() * p_alpha * boost, 1.5)
	for si in 2:
		var b := B_WISP + WISPS_BACK + WISPS_SIDE + WISPS_FRONT + si
		if amount <= 0.0:
			_skin.hide_bone(b)
			continue
		var hh := ShadowFX._hash(si * 7.0, _seed)
		var uu := fposmod(_time * (0.32 + 0.18 * hh) + hh, 1.0)
		var p: Vector2 = srcs[si] + Vector2(sin(uu * 5.0 + hh * 9.0) * 1.6 + uu * 1.2, -8.0 * uu)
		var r := 1.3 * (1.0 - 0.55 * uu) * (0.8 + 0.4 * hh) * sin(uu * PI) * minf(amount, 1.0)
		_skin.set_bone(b, root * Transform2D(0.0, Vector2(r, r), 0.0, p))


## Fissuras de energia subindo da barra do vestido.
func _draw_robe_extra() -> void:
	LiteShadowParts.crack(self, PackedVector2Array([Vector2(-7.0, 0.2), Vector2(-5.8, -2.8), Vector2(-6.6, -5.0), Vector2(-5.4, -7.4)]), shadow_style)
	LiteShadowParts.crack(self, PackedVector2Array([Vector2(7.2, 0.4), Vector2(6.2, -2.4), Vector2(7.0, -4.6)]), shadow_style, 0.8)


func _hem_points(h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 11
	for i in n:
		var x := lerpf(10.6, -11.2, float(i) / (n - 1))
		var drag := h * lerpf(0.4, 1.0, float(i) / (n - 1))
		var y := 1.8 if i % 2 == 0 else -1.4
		pts.append(Vector2(x + drag, y))
	return pts


func _capelet_half(side: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -15.4), Vector2(3.2 * side, -19.4), Vector2(7.6 * side, -17.6), Vector2(9.8 * side, -11.6),
		Vector2(8.2 * side, -13.6), Vector2(6.8 * side, -11.0), Vector2(5.0 * side, -13.2), Vector2(2.7 * side, -14.6),
	])


func _draw_face_shade(fc: Vector2) -> void:
	# metade de baixo do rosto na sombra
	var shade := PackedVector2Array()
	for i in 8:
		var a := lerpf(0.1, PI - 0.1, i / 7.0)
		shade.append(fc + Vector2(cos(a) * 3.3, sin(a) * 3.4))
	_fill(shade, Color(robe_dark, 0.45))


func _draw_eyes() -> void:
	for c in [Vector2(1.7, -2.9), Vector2(3.6, -2.95)]:
		LiteShadowParts.eye(self, c, 0.7, shadow_style)


func _hit_extra(k: float) -> void:
	# etéreo: o corpo tremula e a fumaça explode por um instante
	p_alpha = 1.0 - 0.35 * k * (0.5 + 0.5 * sin(_time * 60.0))
	p_wisp += 1.5 * k


func _death_extra(t: float) -> void:
	# primeiro sobe e se agita; depois colapsa se desfazendo (o manto fica translúcido)
	var rise := clampf(t / 0.35, 0.0, 1.0)
	var settle := clampf((t - 0.35) / 0.5, 0.0, 1.0)
	p_offset.y -= 2.5 * rise * (1.0 - settle)
	p_offset.x += sin(_time * 38.0) * 0.8 * (1.0 - settle)
	p_wisp = 2.0 * (1.0 - clampf((t - 0.6) / 1.6, 0.0, 0.85))
	p_alpha = lerpf(1.0, 0.62, settle)
	p_flash = 0.35 * rise * (1.0 - settle) * (0.5 + 0.5 * sin(_time * 30.0))


## Morte (sombra): as lâminas estremecem e se partem em fragmentos que voam e se desfazem em fumaça.
func _pose_dying_blades() -> void:
	var t := _death_t
	var bit := 0
	var disc := 0
	for bd in _death_blades:
		var pos: Vector2 = bd.pos
		var aim: float = bd.aim
		var b := B_BLADES + int(bd.i) * BLADE_BONES
		if t < 0.16:   # estremecem antes de partir
			var shake := Vector2(sin(_time * 80.0), cos(_time * 70.0)) * 1.5
			_skin.set_bone(b + BL_BLADE, Transform2D(aim, pos + shake))
			_skin.set_bone(b + BL_HALO, Transform2D(aim, pos + shake))
			for f in 5:
				_skin.hide_bone(B_DEATH + bit)
				bit += 1
			_skin.hide_bone(B_DEATH_DISC + disc)
			disc += 1
			continue
		_skin.hide_bone(b + BL_BLADE)
		_skin.hide_bone(b + BL_HALO)
		var k := clampf((t - 0.16) / 0.7, 0.0, 1.0)
		var a := 1.0 - k
		var dir := Vector2.from_angle(aim)
		for f in 5:
			var along := lerpf(-0.4, 0.8, f / 4.0) * SWORD_LENGTH
			var out := Vector2.from_angle(aim + (f - 2) * 0.9 + _seed) * (10.0 + f * 3.0) * _ease_out(k)
			var c := pos + dir * along + out + Vector2(0, 12.0 * k * k)
			var s := 2.2 * (1.0 - 0.5 * k) * sqrt(a)
			_skin.set_bone(B_DEATH + bit, Transform2D(aim + k * (4.0 + f), Vector2(s, s), 0.0, c) if a > 0.0 else LiteSkin.HIDDEN)
			bit += 1
		var r := (6.0 * (1.0 - k) + 2.0) * sqrt(a)
		_skin.set_bone(B_DEATH_DISC + disc, Transform2D(0.0, Vector2(r, r), 0.0, pos) if a > 0.0 else LiteSkin.HIDDEN)
		disc += 1
	for k in range(bit, DEATH_BITS):
		_skin.hide_bone(B_DEATH + k)
	for k in range(disc, 2):
		_skin.hide_bone(B_DEATH_DISC + k)
