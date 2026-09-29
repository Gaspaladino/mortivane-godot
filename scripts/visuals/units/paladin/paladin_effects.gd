class_name PaladinEffects
extends Node2D
## Efeitos do Paladino Vivo, separados do corpo (o rig não desenha nada disto):
##   provocação      anel no raio real (115) + onda curta no chão + brilho na auréola
##   escudo sobe     clarão curto no escudo
##   escudo ativo    brilho dourado sutil em volta do escudo e na estrela
##   bloqueio        faíscas douradas no escudo
## Posições vêm das âncoras do rig (PaladinRig.anchor), no mesmo espaço deste nó.

var rig: PaladinRig
var look: PaladinRigLook

var taunt_t := -1.0
var shield_up_t := -1.0
var block_t := -1.0
var shield_active := 0.0     # 0..1 (suavizado)
var _t := 0.0

static var _glow_tex: Texture2D


static func glow_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.35))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_glow_tex = t
	return _glow_tex


func step(delta: float, shielded: bool) -> void:
	_t += delta
	taunt_t = _adv(taunt_t, delta, 0.9)
	shield_up_t = _adv(shield_up_t, delta, 0.35)
	block_t = _adv(block_t, delta, 0.26)
	shield_active = move_toward(shield_active, 1.0 if shielded else 0.0, delta * 4.0)
	queue_redraw()


static func _adv(t: float, delta: float, length: float) -> float:
	if t < 0.0:
		return t
	t += delta
	return t if t < length else -1.0


func _draw() -> void:
	if rig == null or look == null:
		return
	var gold := Color("ffd76a")
	var holy := look.holy_light
	var g := look.glow
	var k := look.scale
	var offs := rig.position
	# provocação: anel do raio real + onda no chão + auréola acesa
	if taunt_t >= 0.0:
		var p := taunt_t / 0.9
		if look.show_taunt_ring:
			PaladinFx.taunt_ring(self, taunt_t, g * look.taunt_intensity, Color("f0c674"))
		var wave := ease(clampf(p / 0.6, 0.0, 1.0), 0.4)
		draw_set_transform(offs, 0.0, Vector2(1.0, 0.36))
		draw_arc(Vector2.ZERO, lerpf(12.0, 44.0, wave), 0.0, TAU, 48, Color(gold, 0.55 * (1.0 - p) * g * look.taunt_intensity), 2.2, true)
		draw_set_transform(Vector2.ZERO)
		_glow(offs + rig.anchor(&"halo"), 16.0 * k * 2.0, Color(holy, 0.3 * sin(clampf(p, 0.0, 1.0) * PI) * g * look.taunt_intensity))
	# escudo ativo: brilho sutil em volta do escudo + estrela reforçada
	var sc := offs + rig.anchor(&"shield_center")
	if shield_active > 0.0:
		var pulse := 0.85 + 0.15 * sin(_t * 5.0)
		_glow(sc, 24.0 * k * 2.0, Color(holy, 0.13 * shield_active * pulse * g))
		_glow(sc, 7.0 * k * 2.0, Color(1, 1, 0.9, 0.22 * shield_active * pulse * g))
	if shield_up_t >= 0.0:
		var p := shield_up_t / 0.35
		draw_arc(sc, lerpf(8.0, 26.0, ease(p, 0.4)) * k * 2.0, 0.0, TAU, 36, Color(gold, 0.8 * (1.0 - p) * g), 1.6, true)
		_glow(sc, 22.0 * k * 2.0, Color(holy, 0.3 * (1.0 - p) * g))
	# bloqueio: faíscas saindo do escudo
	if block_t >= 0.0:
		var p := block_t / 0.26
		var a := (1.0 - p) * look.block_flash * g
		_glow(sc, 16.0 * k * 2.0, Color(1, 0.97, 0.8, 0.35 * a))
		for i in 7:
			var ang := -PI / 2.0 + (i - 3) * 0.42 + (0.0 if rig.shield_facing >= 0.0 else PI)
			var dir := Vector2(cos(ang + PI / 2.0 * signf(sc.x - offs.x + 0.01)), sin(ang))
			var r0 := lerpf(3.0, 12.0, p) * k * 2.0
			var r1 := r0 + lerpf(8.0, 3.0, p) * k * 2.0
			draw_line(sc + dir * r0, sc + dir * r1, Color(gold, a), 1.4, true)


func _glow(center: Vector2, radius: float, color: Color) -> void:
	if color.a <= 0.003:
		return
	draw_texture_rect(glow_texture(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)
