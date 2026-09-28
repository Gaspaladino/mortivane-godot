class_name SentinelShadowVisual
extends SentinelVisual
## Sentinela Arcana Sombra: "a mesma vigília, agora eterna". MESMO rig da viva; muda:
##   - paleta preta/violeta/azul frio, olhos roxos brilhando, símbolo ainda azul;
##   - manto e capelete com bordas rasgadas e fumaça roxa animada;
##   - idle com tremor arcano, lâminas instáveis e agressivas;
##   - deslizar mais arrastado; disparo roxo com aura; HIT etéreo (o corpo tremula);
##   - morte espectral: sobe, se desfaz em fumaça e as lâminas se partem em fragmentos.


func _init() -> void:
	robe = Color("242035")
	robe_light = Color("3f2d58")
	robe_dark = Color("100f1a")
	trim = Color("8e86a6")
	skin = Color("a79cbd")
	hair = Color("120f1c")
	glow = Color("c486ff")
	gem_color = Color("a76cff")
	symbol = Color("5f8ee0")          # o selo continua azul nas duas versões
	eye = Color("e3c4ff")
	core = Color("f3e6ff")
	wisp = Color(0.55, 0.28, 0.9, 0.55)
	flash_color = Color("d9b8ff")

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


func _hem_points(h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 11
	for i in n:
		var x := lerpf(10.6, -11.2, float(i) / (n - 1))
		var drag := h * lerpf(0.4, 1.0, float(i) / (n - 1))
		var flick := sin(_time * 5.0 + i * 1.7 + _seed) * 0.5
		var y := (1.8 + flick) if i % 2 == 0 else (-1.4 + flick)
		pts.append(Vector2(x + drag, y))
	return pts


func _capelet_half(side: float) -> PackedVector2Array:
	var f := sin(_time * 4.0 + side * 2.0 + _seed) * 0.5
	return PackedVector2Array([
		Vector2(0.0, -15.4), Vector2(3.2 * side, -19.4), Vector2(7.6 * side, -17.6), Vector2(9.8 * side, -11.6 + f),
		Vector2(8.2 * side, -13.6), Vector2(6.8 * side, -11.0 - f), Vector2(5.0 * side, -13.2), Vector2(2.7 * side, -14.6),
	])


func _draw_face_shade(fc: Vector2) -> void:
	# metade de baixo do rosto na sombra
	var shade := PackedVector2Array()
	for i in 8:
		var a := lerpf(0.1, PI - 0.1, i / 7.0)
		shade.append(fc + Vector2(cos(a) * 3.3, sin(a) * 3.4))
	draw_colored_polygon(shade, Color(robe_dark, 0.45 * p_alpha))


func _draw_eyes() -> void:
	var lit := 1.0 - clampf(p_dim * 3.0, 0.0, 1.0)
	var pulse := 0.8 + 0.2 * sin(_time * 3.1 + _seed)
	for c in [Vector2(1.7, -2.9), Vector2(3.6, -2.95)]:
		if lit > 0.0:
			draw_circle(c, 2.3, Color(glow, 0.28 * lit * pulse * p_alpha))
			draw_circle(c, 1.3, Color(glow, 0.5 * lit * p_alpha))
		var e := eye.lerp(robe_dark, 1.0 - lit)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-0.8, 0), c + Vector2(0, -0.55), c + Vector2(0.8, 0), c + Vector2(0, 0.45)]), Color(e, p_alpha))


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


func _draw_wisps(front: bool) -> void:
	var boost := 1.0 + p_wisp
	var base := Color(wisp, wisp.a * (0.55 if front else 0.8))
	var n := 5 if front else 7
	for k in n:
		var u := (k + (0.5 if front else 0.0)) / float(n)
		var x := lerpf(10.0, -11.5, u) + p_hem * lerpf(0.4, 1.0, u)
		var f := 0.5 + 0.5 * sin(_time * (3.0 + k * 0.7) + k * 2.3 + _seed)
		var h := (2.6 + 2.6 * f) * boost
		var lean := -1.5 + p_hem * 0.4 + sin(_time * 2.0 + k) * 0.8
		var foot := Vector2(x, 0.8 if k % 2 == 0 else -0.6)
		draw_colored_polygon(PackedVector2Array([
			foot + Vector2(-1.3, 0), foot + Vector2(1.3, 0),
			foot + Vector2(lean * 0.5 + 0.6, -h * 0.55), foot + Vector2(lean, -h),
		]), Color(base, base.a * (0.5 + 0.5 * f)))
	if not front:
		# fiapos subindo pelas laterais do manto
		for side in [-1.0, 1.0]:
			for k in 2:
				var f := 0.5 + 0.5 * sin(_time * 4.2 + k * 2.0 + side + _seed)
				var anchor := Vector2(side * (9.5 - k * 2.5), -4.0 - k * 5.0)
				draw_colored_polygon(PackedVector2Array([
					anchor + Vector2(0, -1.4), anchor + Vector2(0, 1.4),
					anchor + Vector2(side * (2.4 + 2.0 * f) * boost, -1.0 - 1.5 * f),
				]), Color(base, base.a * 0.7 * f))


## Morte (sombra): as lâminas se partem em fragmentos que voam e se desfazem em fumaça.
func _draw_dying_blades(style: Dictionary) -> void:
	var t := _death_t
	for b in _death_blades:
		var pos: Vector2 = b.pos
		var aim: float = b.aim
		if t < 0.16:   # estremecem antes de partir
			var shake := Vector2(sin(_time * 80.0), cos(_time * 70.0)) * 1.5
			ArcaneBlade.draw(self, Transform2D(aim, pos + shake), SWORD_LENGTH, style, 1.0, _time, 1.0)
			draw_set_transform_matrix(Transform2D.IDENTITY)
			continue
		var k := clampf((t - 0.16) / 0.7, 0.0, 1.0)
		var a := 1.0 - k
		var dir := Vector2.from_angle(aim)
		for f in 5:
			var along := lerpf(-0.4, 0.8, f / 4.0) * SWORD_LENGTH
			var out := Vector2.from_angle(aim + (f - 2) * 0.9 + _seed) * (10.0 + f * 3.0) * _ease_out(k)
			var c := pos + dir * along + out + Vector2(0, 12.0 * k * k)
			var rot := aim + k * (4.0 + f)
			var s := 2.2 * (1.0 - 0.5 * k)
			var tri := PackedVector2Array([
				c + Vector2.from_angle(rot) * s, c + Vector2.from_angle(rot + 2.3) * s * 0.7, c + Vector2.from_angle(rot + 4.1) * s * 0.8,
			])
			draw_colored_polygon(tri, Color(style.dark, a))
			var edge := tri.duplicate()
			edge.append(tri[0])
			draw_polyline(edge, Color(glow, a), 0.7, true)
		draw_circle(pos, 6.0 * (1.0 - k) + 2.0, Color(wisp, wisp.a * 0.6 * a))
