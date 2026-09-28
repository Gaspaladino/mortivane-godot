extends SceneTree
## Gera a SPRITE SHEET PILOTO do Paladino Vivo (Idle 6 · Walk 8 · Attack 8) em perspectiva 3/4.
## O personagem é pintado por código (rig 3/4 com IK e sombreado de volume) e cada pose é
## renderizada numa SubViewport transparente em supersampling, depois reduzida e montada na sheet.
## Referência: pranchas aprovadas do Paladino (A: conceito e paleta; B: poses 3/4 de jogo;
## C: partes, pivôs e ordem de sobreposição).
##
##   godot --path . --rendering-driver opengl3 -s "$PWD/tools/sprites/render_paladin_pilot.gd"
##   godot --headless --path . --import
##   godot --headless --path . -s "$PWD/tools/sprites/render_paladin_pilot.gd" -- --build
##
## (Precisa de janela/GPU para renderizar: use um X virtual em servidor. O passo --build só monta o
## SpriteFrames a partir dos PNG já importados.) Tudo sai em assets/sprites/paladin_live_pilot/.
##
## Contrato dos frames (igual em todos): FRAME×FRAME px, fundo transparente, PIVÔ = centro entre os
## pés no chão em PIVOT (px do frame). Nada de chão/cenário; a sombra é um PNG separado.

const OUT := "res://assets/sprites/paladin_live_pilot/"
const FRAME := 256
const PIVOT := Vector2(128, 240)
const SS := 3                       # supersampling
const ANIMS := [["idle", 6, 8.0, true], ["walk", 8, 14.0, true], ["attack", 8, 12.0, false]]

var _vp: SubViewport
var _painter: PaladinPainter
var _queue: Array = []              # [anim, index, pose]
var _sheet: Image
var _wait := 0
var _current: Array = []


func _initialize() -> void:
	if "--build" in OS.get_cmdline_user_args():
		_build_sprite_frames()
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	_vp = SubViewport.new()
	_vp.size = Vector2i(FRAME * SS, FRAME * SS)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_painter = PaladinPainter.new()
	_painter.scale = Vector2(SS, SS)
	_painter.position = PIVOT * SS
	_vp.add_child(_painter)
	_sheet = Image.create(FRAME * 8, FRAME * ANIMS.size(), false, Image.FORMAT_RGBA8)
	for a in ANIMS.size():
		var poses := Poses.for_anim(ANIMS[a][0], ANIMS[a][1])
		for i in poses.size():
			_queue.append([a, i, poses[i]])
	_next()


func _next() -> void:
	if _queue.is_empty():
		_finish()
		return
	_current = _queue.pop_front()
	_painter.pose = _current[2]
	_painter.queue_redraw()
	_wait = 3


func _process(_delta: float) -> bool:
	if _current.is_empty():
		return true
	_wait -= 1
	if _wait > 0:
		return false
	var img := _vp.get_texture().get_image()
	img.resize(FRAME, FRAME, Image.INTERPOLATE_LANCZOS)
	var anim: String = ANIMS[_current[0]][0]
	img.save_png(ProjectSettings.globalize_path(OUT + "frames/%s_%02d.png" % [anim, _current[1]]))
	_sheet.blit_rect(img, Rect2i(0, 0, FRAME, FRAME), Vector2i(_current[1] * FRAME, _current[0] * FRAME))
	_next()
	return _current.is_empty()


func _finish() -> void:
	_sheet.save_png(ProjectSettings.globalize_path(OUT + "paladin_live_pilot_sheet.png"))
	_save_shadow()
	var meta := {
		frame_size = [FRAME, FRAME], pivot = [PIVOT.x, PIVOT.y], pivot_note = "centro entre os pés, no chão",
		rows = ANIMS.map(func(a: Array) -> Dictionary: return {name = a[0], frames = a[1], fps = a[2], loop = a[3]}),
		light = "luz principal fria/neutra vinda do alto à esquerda (constante em todos os frames)",
	}
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT + "paladin_live_pilot.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	print("render_paladin_pilot: OK (%d frames)" % ANIMS.reduce(func(s: int, a: Array) -> int: return s + a[1], 0))
	_current = []
	quit(0)


## Sombra da unidade (separada dos frames), no mesmo canvas e pivô.
func _save_shadow() -> void:
	var img := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	for y in range(int(PIVOT.y) - 16, mini(FRAME, int(PIVOT.y) + 16)):
		for x in FRAME:
			var d := Vector2((x - PIVOT.x) / 46.0, (y - PIVOT.y - 1) / 12.0).length()
			if d < 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0.42 * (1.0 - smoothstep(0.55, 1.0, d))))
	img.save_png(ProjectSettings.globalize_path(OUT + "paladin_live_pilot_shadow.png"))


## Monta o SpriteFrames (AtlasTexture de cada frame da sheet importada).
func _build_sprite_frames() -> void:
	var tex: Texture2D = load(OUT + "paladin_live_pilot_sheet.png")
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	for a in ANIMS.size():
		var name: StringName = ANIMS[a][0]
		sf.add_animation(name)
		sf.set_animation_speed(name, ANIMS[a][2])
		sf.set_animation_loop(name, ANIMS[a][3])
		for i in ANIMS[a][1]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * FRAME, a * FRAME, FRAME, FRAME)
			sf.add_frame(name, at)
	var err := ResourceSaver.save(sf, OUT + "paladin_live_pilot_frames.tres")
	print("render_paladin_pilot --build: ", "OK" if err == OK else "ERRO %d" % err)


# ==============================================================================================
# Poses (keyframes feitos à mão; pés por IK, sempre plantados no chão)
# ==============================================================================================

class Poses:
	## Pose neutra de guarda (prancha B, "1. Idle"): base larga, espada erguida à frente-esquerda,
	## escudo grande à frente do tronco.
	static func base() -> Dictionary:
		return {
			hip = Vector2(0, -50), lean = 3.0, twist = 0.0, head = 0.0, chest = 0.0,
			foot_n = Vector2(-15, 3), foot_f = Vector2(17, -3),
			hand_s = Vector2(-37, -64), sword = -18.0,
			shield = Vector2(40, -58), shield_rot = 0.0,
			cape = 0.0, tabard = 0.0,
			arc = 0.0, arc_hand = Vector2.ZERO, arc_sword = 0.0,
		}

	static func for_anim(anim: String, n: int) -> Array:
		var out := []
		for i in n:
			var p := base()
			match anim:
				"idle": _idle(p, i, n)
				"walk": _walk(p, i, n)
				"attack": _attack(p, i)
			out.append(p)
		return out

	## Respiração sutil: peito sobe ~1 px, espada oscila 1,5°, escudo quase parado,
	## capa e tabardo reagem com atraso.
	static func _idle(p: Dictionary, i: int, n: int) -> void:
		var a := TAU * i / n
		var b := (1.0 - cos(a)) * 0.5
		p.chest = -1.2 * b
		p.hip += Vector2(0, -0.4 * b)
		p.head = -0.8 * b
		p.hand_s += Vector2(0, -0.8 * b)
		p.sword += 1.5 * b
		p.shield += Vector2(0, -0.5 * b)
		p.cape = 1.5 * sin(a - 1.1)
		p.tabard = 0.9 * sin(a - 0.7)

	## Passada curta e pesada, no lugar (quem se desloca é a unidade): o pé de apoio recua rente
	## ao chão, o outro sobe pouco e avança; o corpo desce no apoio duplo.
	static func _walk(p: Dictionary, i: int, n: int) -> void:
		var ph := float(i) / n
		p.foot_n = _foot(ph, Vector2(-2, 3))
		p.foot_f = _foot(fposmod(ph + 0.5, 1.0), Vector2(3, -3))
		var a := TAU * ph
		p.hip = Vector2(1.5, -49.0 - 1.8 * absf(sin(a)))
		p.lean = 6.0
		p.twist = 0.12 * sin(a)
		p.chest = -0.5 * absf(sin(a))
		p.head = -1.0
		p.hand_s += Vector2(2.0 + 2.5 * cos(a - 0.8), 0.8 * absf(sin(a)))
		p.sword += 3.0 * sin(a - 0.9)
		p.shield += Vector2(1.5, -0.8 * absf(sin(a - 0.4)))
		p.shield_rot = 1.0 * sin(a - 0.5)
		p.cape = -3.0 - 2.0 * sin(a - 1.3)
		p.tabard = -1.2 - 1.2 * sin(2.0 * a - 1.0)

	## Pé no ciclo: apoio (0..0,5) recua de +12 a −12 no chão; balanço (0,5..1) sobe até 6 px e avança.
	static func _foot(ph: float, off: Vector2) -> Vector2:
		const HALF := 12.0
		if ph < 0.5:
			return off + Vector2(lerpf(HALF, -HALF, ph / 0.5), 0)
		var u := (ph - 0.5) / 0.5
		var s := u * u * (3.0 - 2.0 * u)
		return off + Vector2(lerpf(-HALF, HALF, s), -6.0 * sin(u * PI))

	## Golpe pesado em 8 tempos: guarda · preparação · espada recua · tronco gira · início do golpe ·
	## impacto (arco dourado sutil) · follow-through · recuperação. O escudo segue presente.
	static func _attack(p: Dictionary, i: int) -> void:
		var keys: Array = [
			{},
			{hand_s = Vector2(-43, -80), sword = -52.0, lean = 1.0, twist = -0.2, hip = Vector2(-1, -50), shield = Vector2(40, -59)},
			{hand_s = Vector2(-37, -102), sword = -110.0, lean = -4.0, twist = -0.45, hip = Vector2(-3, -49), head = -3.0, shield = Vector2(42, -60), cape = 1.5},
			{hand_s = Vector2(-31, -108), sword = -136.0, lean = -6.0, twist = -0.6, hip = Vector2(-4, -47.5), head = -4.0, shield = Vector2(42, -59), cape = 2.5, chest = -1.0},
			{hand_s = Vector2(-9, -106), sword = -26.0, lean = 4.0, twist = -0.1, hip = Vector2(0, -48), head = -1.0, shield = Vector2(41, -58), cape = 1.0},
			{hand_s = Vector2(33, -64), sword = 104.0, lean = 13.0, twist = 0.45, hip = Vector2(6, -45), head = 4.0, shield = Vector2(44, -54), shield_rot = 4.0,
				foot_f = Vector2(21, -3), cape = -3.5, tabard = -1.5, arc = 1.0, arc_hand = Vector2(-9, -106), arc_sword = -26.0},
			{hand_s = Vector2(29, -50), sword = 134.0, lean = 11.0, twist = 0.35, hip = Vector2(5, -46), head = 3.0, shield = Vector2(43, -55), shield_rot = 3.0,
				foot_f = Vector2(21, -3), cape = -4.0, tabard = -2.0, arc = 0.35, arc_hand = Vector2(33, -64), arc_sword = 104.0},
			{hand_s = Vector2(-20, -64), sword = 6.0, lean = 6.0, twist = 0.1, hip = Vector2(2, -49), head = 1.0, shield = Vector2(41, -57), cape = -1.5, tabard = -0.8},
		]
		var k: Dictionary = keys[i]
		for key in k:
			p[key] = k[key]


# ==============================================================================================
# Pintor 3/4 (origem nos pés; x → direita da tela, para onde ele olha; y para baixo)
# Proporções da prancha: elmo grande, ombreiras enormes em lâminas, tronco largo, pernas curtas
# e grossas, escudo grande, espada larga; malha escura aparecendo nas juntas.
# ==============================================================================================

class PaladinPainter:
	extends Node2D

	# paleta (prancha A — Paladino Vivo)
	const INK := Color("17141d")
	const IVORY := Color("e4dcc8")
	const IVORY_LIGHT := Color("fff8ea")
	const IVORY_SHADE := Color("9d9586")
	const GOLD := Color("d39f3a")
	const GOLD_LIGHT := Color("ffe39a")
	const GOLD_DARK := Color("8e5c19")
	const UNDER := Color("24222b")
	const UNDER_LIGHT := Color("45414e")
	const LEATHER := Color("4b3526")
	const CLOTH := Color("f1e9d5")
	const CLOTH_SHADE := Color("bdb39a")
	const CAPE := Color("ddd3bc")
	const CAPE_LINING := Color("7b7466")
	const STEEL := Color("e3e7ec")
	const STEEL_SHADE := Color("8b93a0")
	## Luz principal constante: do alto à esquerda.
	const LIGHT := Vector2(-0.62, -0.78)
	const OUTLINE_W := 1.8

	const THIGH := 24.0
	const SHIN := 22.0
	const UPPER_ARM := 18.0
	const FOREARM := 17.0
	const BLADE := 62.0

	var pose: Dictionary = {}

	func _draw() -> void:
		if pose.is_empty():
			return
		var hip: Vector2 = pose.hip
		var lean := deg_to_rad(pose.lean)
		var tw: float = pose.twist
		var torso := Transform2D(lean, hip)
		var chest: float = pose.chest
		var sh_n := torso * Vector2(-26 + tw * 8.0, -38 + chest)
		var sh_f := torso * Vector2(22 + tw * 3.0, -40 + chest)
		var neck := torso * Vector2(3 + tw * 2.0, -47 + chest)
		var hip_n := hip + Vector2(-11, 1)
		var hip_f := hip + Vector2(11, -1)
		var ankle_n: Vector2 = pose.foot_n + Vector2(0, -8)
		var ankle_f: Vector2 = pose.foot_f + Vector2(0, -8)
		var knee_n := _ik(hip_n, ankle_n, THIGH, SHIN, 1.0)
		var knee_f := _ik(hip_f, ankle_f, THIGH, SHIN, 1.0)
		var hand_s: Vector2 = pose.hand_s
		var elbow_s := _ik(sh_n, hand_s, UPPER_ARM, FOREARM, -1.0)
		var shield_c: Vector2 = pose.shield

		# ordem de sobreposição (prancha C): capa · perna de trás · braço do escudo · ombreira de trás ·
		# perna da frente · tabardo/saiote · tronco · cabeça · escudo · braço, ombreira e espada da frente
		_cape(sh_n, sh_f)
		_leg(hip_f, knee_f, ankle_f, pose.foot_f, 0.8)
		_vol(_quad(sh_f, shield_c + Vector2(-8, 4), 14.0, 12.0), UNDER.darkened(0.2), 0.2)
		_pauldron(sh_f + Vector2(3, -1), 0.8, lean)
		_leg(hip_n, knee_n, ankle_n, pose.foot_n, 1.0)
		_tabard(hip, lean)
		_torso(torso, tw, chest)
		_head(neck, deg_to_rad(pose.head) + lean * 0.4)
		_shield(shield_c, deg_to_rad(pose.shield_rot))
		_arm(sh_n, elbow_s, hand_s)
		_pauldron(sh_n + Vector2(-3, -1), 1.0, lean)
		if pose.arc > 0.0:
			_arc(pose.arc_hand, deg_to_rad(pose.arc_sword), hand_s, deg_to_rad(pose.sword), pose.arc)
		_sword(hand_s, deg_to_rad(pose.sword))
		_gauntlet(hand_s, deg_to_rad(pose.sword))

	# --- ossos ------------------------------------------------------------------------------

	## IK de 2 ossos: joelho/cotovelo. side = +1 dobra para a frente (+x), −1 para trás.
	static func _ik(a: Vector2, b: Vector2, l1: float, l2: float, side: float) -> Vector2:
		var d := clampf(a.distance_to(b), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
		var ang := (b - a).angle()
		var c := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
		var off := acos(c)
		var k1 := a + Vector2.from_angle(ang + off) * l1
		var k2 := a + Vector2.from_angle(ang - off) * l1
		var mid := (a + b) * 0.5
		return k1 if (k1.x - mid.x) * side >= (k2.x - mid.x) * side else k2

	# --- utilitários de desenho --------------------------------------------------------------

	## Polígono com volume: cada vértice clareia/escurece conforme a luz (do alto à esquerda).
	func _vol(pts: PackedVector2Array, base: Color, amount := 0.3, outline := true) -> void:
		var c := Vector2.ZERO
		for p in pts:
			c += p
		c /= pts.size()
		var r := 0.001
		for p in pts:
			r = maxf(r, p.distance_to(c))
		var cols := PackedColorArray()
		for p in pts:
			var t := clampf(((p - c) / r).dot(LIGHT), -1.0, 1.0)
			cols.append(base.lightened(amount * t) if t > 0.0 else base.darkened(-amount * t * 1.2))
		draw_polygon(pts, cols)
		if outline:
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, INK, OUTLINE_W, true)

	func _line(pts: PackedVector2Array, col: Color, w: float) -> void:
		draw_polyline(pts, col, w, true)

	static func _quad(a: Vector2, b: Vector2, wa: float, wb: float) -> PackedVector2Array:
		var n := (b - a).orthogonal().normalized()
		return PackedVector2Array([a + n * wa * 0.5, b + n * wb * 0.5, b - n * wb * 0.5, a - n * wa * 0.5])

	static func _ellipse(c: Vector2, r: Vector2, rot := 0.0, n := 24, from := 0.0, to := TAU) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in n:
			var a := lerpf(from, to, float(i) / (n if to - from >= TAU - 0.001 else n - 1))
			pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(rot))
		return pts

	func _star(c: Vector2, s: float, col: Color, rot := 0.0, points := 8, inner := 0.28) -> void:
		var pts := PackedVector2Array()
		for i in points * 2:
			var a := rot + i * PI / points - PI / 2.0
			var r := s if i % 2 == 0 else s * inner
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, col)

	## Sol sagrado (prancha A): 4 raios longos + 4 curtos, anel e disco.
	func _sun(c: Vector2, s: float, squash := Vector2.ONE) -> void:
		draw_set_transform(c, 0.0, squash)
		_star(Vector2.ZERO, s * 1.08, GOLD_DARK, 0.0, 4, 0.2)
		_star(Vector2.ZERO, s, GOLD, 0.0, 4, 0.2)
		_star(Vector2.ZERO, s * 0.62, GOLD, PI / 4.0, 4, 0.25)
		draw_circle(Vector2.ZERO, s * 0.36, GOLD_DARK)
		draw_circle(Vector2.ZERO, s * 0.29, GOLD)
		draw_circle(Vector2.ZERO, s * 0.18, GOLD_LIGHT)
		draw_set_transform(Vector2.ZERO)

	# --- partes --------------------------------------------------------------------------------

	## Capa creme (forro mais escuro), caindo atrás até perto do chão; a barra reage com atraso.
	func _cape(sh_n: Vector2, sh_f: Vector2) -> void:
		var sw: float = pose.cape
		var outer := PackedVector2Array([
			sh_n + Vector2(6, -6), sh_f + Vector2(-4, -6), sh_f + Vector2(10, 8), Vector2(31 + sw * 0.5, -14),
			Vector2(26 + sw, -3), Vector2(14 + sw, -6), Vector2(2 + sw, -2), Vector2(-12 + sw, -6),
			Vector2(-27 + sw * 0.9, -2), Vector2(-37 + sw * 0.6, -18), sh_n + Vector2(-12, 14),
		])
		_vol(outer, CAPE, 0.24)
		# forro visível na borda de perto e dobras
		_vol(PackedVector2Array([Vector2(-37 + sw * 0.6, -18), sh_n + Vector2(-12, 14), sh_n + Vector2(-6, 22),
			Vector2(-30 + sw * 0.8, -4)]), CAPE_LINING, 0.2)
		_line(PackedVector2Array([sh_n + Vector2(0, 16), Vector2(-16 + sw * 0.8, -6)]), CAPE_LINING, 1.6)
		_line(PackedVector2Array([sh_f + Vector2(2, 10), Vector2(20 + sw * 0.9, -5)]), CAPE_LINING, 1.4)

	## Perna blindada: malha escura + coxote, joelheira dourada, greva, sapatão (virado para +x).
	func _leg(hip_p: Vector2, knee: Vector2, ankle: Vector2, foot: Vector2, shade: float) -> void:
		var dk := func(c: Color) -> Color: return c.darkened(1.0 - shade)
		_vol(_quad(hip_p, knee, 20.0, 17.0), dk.call(UNDER), 0.2)
		_vol(_quad(hip_p.lerp(knee, 0.2), knee.lerp(hip_p, 0.1), 17.0, 14.0), dk.call(IVORY), 0.32)
		_vol(_quad(knee, ankle, 17.0, 14.0), dk.call(IVORY), 0.32)
		var n := (ankle - knee).orthogonal().normalized()
		var mid := knee.lerp(ankle, 0.55)
		_line(PackedVector2Array([mid - n * 7.5, mid + n * 7.5]), dk.call(GOLD), 1.8)
		_line(PackedVector2Array([knee.lerp(ankle, 0.15) + n * 4.0, ankle + n * 3.5]), dk.call(IVORY_LIGHT), 1.6)
		# joelheira: cúpula com aba e filete dourado
		_vol(_ellipse(knee + Vector2(1, 0), Vector2(10.0, 8.5)), dk.call(IVORY_LIGHT), 0.32)
		draw_arc(knee + Vector2(1, 0), 6.2, PI * 0.85, PI * 2.15, 16, dk.call(GOLD), 1.8, true)
		draw_circle(knee + Vector2(2, -1), 1.8, dk.call(GOLD_LIGHT))
		# sapatão largo com biqueira
		var toe := foot + Vector2(15, 0)
		_vol(PackedVector2Array([ankle + Vector2(-9, -2), ankle + Vector2(7, -3), toe + Vector2(-2, -6), toe + Vector2(3, -1),
			toe + Vector2(1, 1), foot + Vector2(-11, 1)]), dk.call(IVORY), 0.3)
		_line(PackedVector2Array([ankle + Vector2(-8, 3), toe + Vector2(-3, -2)]), dk.call(GOLD), 1.6)

	func _tabard(hip: Vector2, lean: float) -> void:
		var sw: float = pose.tabard
		var belt_l := hip + Vector2(-25, -3).rotated(lean)
		var belt_r := hip + Vector2(24, -5).rotated(lean)
		# painel entre as pernas (sombra)
		_vol(PackedVector2Array([hip + Vector2(-9, 0), hip + Vector2(12, -1), Vector2(12 + sw, -12), Vector2(-7 + sw, -10)]), CLOTH_SHADE.darkened(0.15), 0.2)
		# saiote de placas (faldas) nos lados, sobre as coxas
		_vol(PackedVector2Array([belt_l, hip + Vector2(-7, 1), hip + Vector2(-10, 17), belt_l + Vector2(-5, 17)]), IVORY, 0.32)
		_line(PackedVector2Array([belt_l + Vector2(-2, 9), hip + Vector2(-8, 9)]), GOLD, 1.4)
		_vol(PackedVector2Array([hip + Vector2(11, -1), belt_r, belt_r + Vector2(5, 15), hip + Vector2(13, 16)]), IVORY.darkened(0.14), 0.3)
		# painel da frente (tabardo claro, borda dourada, sol)
		var front := PackedVector2Array([hip + Vector2(-9, -2), hip + Vector2(13, -3), Vector2(15 + sw, -7), Vector2(4 + sw, -4),
			Vector2(-8 + sw, -6)])
		_vol(front, CLOTH, 0.22)
		_line(PackedVector2Array([front[0] + Vector2(2.5, 2), front[4] + Vector2(2.5, -2)]), GOLD, 2.0)
		_line(PackedVector2Array([front[1] + Vector2(-2.5, 2), front[2] + Vector2(-2.5, -2)]), GOLD, 2.0)
		_sun(hip.lerp(Vector2(4 + sw, -5), 0.5) + Vector2(2, 0), 9.0)
		# cinto largo com fivela dourada
		_vol(_quad(belt_l, belt_r, 8.0, 8.0), LEATHER, 0.25)
		var buckle := belt_l.lerp(belt_r, 0.56)
		_vol(PackedVector2Array([buckle + Vector2(-6, -5.5), buckle + Vector2(6, -5.5), buckle + Vector2(6, 5.5), buckle + Vector2(-6, 5.5)]), GOLD, 0.35)
		draw_rect(Rect2(buckle - Vector2(2.6, 2.6), Vector2(5.2, 5.2)), LEATHER)

	func _torso(torso: Transform2D, tw: float, chest: float) -> void:
		var c := Vector2(0, chest)
		var ridge_x := 4.0 + tw * 5.0
		var plate := [Vector2(-24, -3), Vector2(22, -5), Vector2(27, -20), Vector2(26, -35), Vector2(15, -46), Vector2(-12, -47),
			Vector2(-27, -39), Vector2(-29, -20)]
		var pts := PackedVector2Array()
		for i in plate.size():
			pts.append(torso * (plate[i] + (c if i >= 2 else Vector2.ZERO)))
		_vol(pts, IVORY, 0.36)
		var far := [Vector2(ridge_x + 3, -5), Vector2(22, -5), Vector2(27, -20), Vector2(26, -35), Vector2(15, -46), Vector2(ridge_x + 5, -46)]
		var fp := PackedVector2Array()
		for i in far.size():
			fp.append(torso * (far[i] + (c if i >= 2 else Vector2.ZERO)))
		draw_colored_polygon(fp, Color(IVORY_SHADE, 0.55))
		# crista central, reflexo, filetes dourados (peito e abdome)
		_line(PackedVector2Array([torso * (Vector2(ridge_x + 1, -44) + c), torso * Vector2(ridge_x, -8)]), IVORY_SHADE.darkened(0.25), 1.4)
		_line(PackedVector2Array([torso * (Vector2(-18, -35) + c), torso * (Vector2(-11, -20) + c)]), IVORY_LIGHT, 3.0)
		_line(PackedVector2Array([torso * (Vector2(-27, -22) + c), torso * (Vector2(-3, -17) + c), torso * (Vector2(26, -21) + c)]), GOLD, 2.0)
		_line(PackedVector2Array([torso * Vector2(-24, -8), torso * Vector2(22, -10)]), GOLD, 2.2)
		# gorjal escuro com borda dourada
		var gorget := PackedVector2Array([torso * (Vector2(-12, -45) + c), torso * (Vector2(16, -46) + c),
			torso * (Vector2(13, -53) + c), torso * (Vector2(-9, -53) + c)])
		_vol(gorget, UNDER_LIGHT, 0.25)
		_line(PackedVector2Array([gorget[0], gorget[1]]), GOLD, 2.0)

	## Grande elmo fechado em 3/4 (calota arredondada, placa da face virada para a direita, visor
	## estreito em T), crista dourada e auréola dourada atrás com estrelas.
	func _head(neck: Vector2, rot: float) -> void:
		var hc := neck + Vector2(2, -17).rotated(rot)
		var halo_c := hc + Vector2(-3, -5)
		draw_arc(halo_c, 25.0, 0, TAU, 56, GOLD_DARK, 5.2, true)
		draw_arc(halo_c, 25.0, 0, TAU, 56, GOLD, 3.2, true)
		draw_arc(halo_c, 25.0, PI * 1.05, PI * 1.55, 18, GOLD_LIGHT, 1.6, true)
		_star(halo_c + Vector2(0, -26), 8.0, GOLD_DARK, 0.0, 4, 0.25)
		_star(halo_c + Vector2(0, -26), 6.6, GOLD_LIGHT, 0.0, 4, 0.25)
		_star(halo_c + Vector2(-25.5, -3), 4.6, GOLD, 0.0, 4, 0.3)
		_star(halo_c + Vector2(25.5, -3), 4.6, GOLD, 0.0, 4, 0.3)
		var x := Transform2D(rot, hc)
		_vol(PackedVector2Array([x * Vector2(-3, -17), x * Vector2(2, -29), x * Vector2(7, -17)]), GOLD, 0.35)
		var dome := PackedVector2Array([x * Vector2(-17, 14), x * Vector2(-18, -2), x * Vector2(-15, -13), x * Vector2(-4, -19),
			x * Vector2(8, -18), x * Vector2(16, -11), x * Vector2(19, 1), x * Vector2(17, 15)])
		_vol(dome, IVORY, 0.38)
		var face := PackedVector2Array([x * Vector2(0, -17), x * Vector2(9, -17), x * Vector2(17, -9), x * Vector2(19, 3),
			x * Vector2(16, 15), x * Vector2(1, 16)])
		_vol(face, IVORY_LIGHT, 0.24)
		# faixa dourada frontal e aro dourado da base
		_vol(PackedVector2Array([x * Vector2(4, -18), x * Vector2(9, -18), x * Vector2(9, -4), x * Vector2(4, -4)]), GOLD, 0.3)
		_vol(PackedVector2Array([x * Vector2(-17, 10), x * Vector2(17, 11), x * Vector2(16, 16), x * Vector2(-17, 15)]), GOLD, 0.32)
		# visor estreito em T
		draw_colored_polygon(PackedVector2Array([x * Vector2(0, -4), x * Vector2(18, -4.5), x * Vector2(18, 0.5), x * Vector2(0, 0.5)]), INK)
		draw_colored_polygon(PackedVector2Array([x * Vector2(5, 0.5), x * Vector2(8.5, 0.5), x * Vector2(8.5, 10), x * Vector2(5, 10)]), INK)
		# respiros e reflexo da calota
		for k in 3:
			draw_line(x * Vector2(11 + k * 2.4, 4), x * Vector2(11 + k * 2.4, 8), INK, 1.1, true)
		_line(PackedVector2Array([x * Vector2(-12, -9), x * Vector2(-6, -15)]), Color(1, 1, 1, 0.75), 2.4)

	## Ombreira robusta em três lâminas (a de cima em cúpula), bordas douradas e rebite.
	func _pauldron(c: Vector2, size: float, lean: float) -> void:
		var dk := IVORY.darkened((1.0 - size) * 0.5)
		var r := Vector2(19.0, 14.0) * size
		var rot := lean * 0.5
		for k in [2, 1]:
			var lc := c + Vector2(-1.5 * k, 5.0 + k * 5.5).rotated(rot) * size
			var lr := r * Vector2(0.92 - k * 0.08, 0.55)
			var lame := _ellipse(lc, lr, rot, 14, PI * 0.02, PI * 0.98)
			var top_edge := _ellipse(lc + Vector2(0, -lr.y * 0.55).rotated(rot), lr * Vector2(1.0, 0.4), rot, 10, PI * 0.98, PI * 0.02)
			lame.append_array(top_edge)
			_vol(lame, dk.darkened(0.05 * k), 0.3)
			draw_arc(lc, lr.x * 0.9, PI * 0.12, PI * 0.88, 12, GOLD, 1.8 * size, true)
		var dome := _ellipse(c, r, rot, 26, PI, TAU)
		dome.append(c + Vector2(r.x, 4 * size).rotated(rot))
		dome.append(c + Vector2(-r.x, 4 * size).rotated(rot))
		_vol(dome, dk, 0.4)
		draw_arc(c + Vector2(0, 1).rotated(rot), r.x * 0.84, PI * 1.02, PI * 1.98, 20, GOLD, 2.4 * size, true)
		draw_circle(c + Vector2(-3, -6) * size, 2.2 * size, GOLD_LIGHT)
		_line(PackedVector2Array([c + Vector2(-12, -5) * size, c + Vector2(-5, -11) * size]), Color(1, 1, 1, 0.6 * size), 2.2 * size)

	## Braço da espada (perto da câmera): malha, braçal, cotoveleira e manopla.
	func _arm(sh: Vector2, elbow: Vector2, hand: Vector2) -> void:
		_vol(_quad(sh, elbow, 16.0, 13.0), UNDER, 0.2)
		_vol(_quad(sh.lerp(elbow, 0.3), elbow, 15.0, 13.0), IVORY, 0.32)
		_vol(_quad(elbow, hand, 14.5, 13.0), IVORY, 0.34)
		var n := (hand - elbow).orthogonal().normalized()
		var band := elbow.lerp(hand, 0.7)
		_line(PackedVector2Array([band - n * 7.0, band + n * 7.0]), GOLD, 2.2)
		_vol(_ellipse(elbow, Vector2(8.0, 7.0)), IVORY_LIGHT, 0.32)
		draw_circle(elbow + Vector2(-1, -1), 1.6, GOLD)

	func _gauntlet(hand: Vector2, ang: float) -> void:
		_vol(_ellipse(hand, Vector2(8.0, 7.2), ang), UNDER_LIGHT, 0.32)
		_line(PackedVector2Array([hand + Vector2(-4, -5).rotated(ang), hand + Vector2(4, -5).rotated(ang)]), GOLD, 1.6)

	## Espada larga de uma mão: guarda e pomo dourados, lâmina com fio claro e sulco.
	func _sword(hand: Vector2, ang: float) -> void:
		var x := Transform2D(ang, hand)
		_vol(PackedVector2Array([x * Vector2(-2.6, -3), x * Vector2(2.6, -3), x * Vector2(2.6, 11), x * Vector2(-2.6, 11)]), LEATHER, 0.2)
		_vol(_ellipse(x * Vector2(0, 14), Vector2(4.4, 4.4)), GOLD, 0.35)
		var blade := PackedVector2Array([x * Vector2(-4.8, -8), x * Vector2(4.8, -8), x * Vector2(4.2, -BLADE + 11),
			x * Vector2(0, -BLADE), x * Vector2(-4.2, -BLADE + 11)])
		_vol(blade, STEEL, 0.3)
		draw_colored_polygon(PackedVector2Array([x * Vector2(0.4, -9), x * Vector2(4.6, -9), x * Vector2(4.0, -BLADE + 11), x * Vector2(0.4, -BLADE + 3)]), Color(STEEL_SHADE, 0.5))
		_line(PackedVector2Array([x * Vector2(0, -10), x * Vector2(0, -BLADE + 9)]), STEEL_SHADE.darkened(0.2), 1.2)
		_vol(PackedVector2Array([x * Vector2(-15, -10), x * Vector2(-5, -7), x * Vector2(5, -7), x * Vector2(15, -10),
			x * Vector2(14, -4), x * Vector2(-14, -4)]), GOLD, 0.35)
		draw_circle(x * Vector2(0, -6), 2.0, GOLD_LIGHT)

	## Escudo heráldico grande em 3/4: face girada (lado de longe mais estreito), espessura visível
	## na borda de perto, borda dourada larga e sol sagrado.
	func _shield(c: Vector2, rot: float) -> void:
		var w := 28.0
		var h := 37.0
		var face := PackedVector2Array()
		for p in [Vector2(-1.0, -1.0), Vector2(0.0, -1.1), Vector2(1.0, -1.0), Vector2(0.97, 0.12), Vector2(0.64, 0.74),
				Vector2(0.0, 1.16), Vector2(-0.64, 0.74), Vector2(-0.97, 0.12)]:
			var q := Vector2(p.x * w, p.y * h)
			q.x *= 0.84 if q.x > 0.0 else 1.0
			q.y -= q.x * 0.07
			face.append(c + q.rotated(rot))
		var edge := PackedVector2Array()
		for i in [0, 7, 6, 5]:
			edge.append(face[i])
		for i in [5, 6, 7, 0]:
			edge.append(face[i] + Vector2(-6, 2.5).rotated(rot))
		_vol(edge, GOLD_DARK, 0.2)
		_vol(face, IVORY, 0.34)
		draw_colored_polygon(PackedVector2Array([face[1], face[2], face[3], face[4], face[5]]), Color(IVORY_SHADE, 0.45))
		var rim := face.duplicate()
		rim.append(face[0])
		draw_polyline(rim, INK, 7.4, true)
		draw_polyline(rim, GOLD_DARK, 6.0, true)
		draw_polyline(rim, GOLD, 3.8, true)
		_line(PackedVector2Array([face[7].lerp(face[0], 0.25) + Vector2(4, 3).rotated(rot), face[6] + Vector2(4, -4).rotated(rot)]), IVORY_LIGHT, 2.4)
		_sun(c + Vector2(-1, -4).rotated(rot), 19.0, Vector2(0.88, 1.0))

	## Rastro do golpe: faixa dourada sutil entre a ponta da espada no frame anterior e a atual.
	func _arc(hand_a: Vector2, ang_a: float, hand_b: Vector2, ang_b: float, strength: float) -> void:
		var pts := PackedVector2Array()
		for i in 13:
			var u := i / 12.0
			var h := hand_a.lerp(hand_b, u)
			var a := lerpf(ang_a, ang_b, u)
			pts.append(h + Vector2(0, -BLADE * 0.95).rotated(a))
		draw_polyline(pts, Color(GOLD_LIGHT, 0.18 * strength), 10.0, true)
		draw_polyline(pts, Color(GOLD_LIGHT, 0.5 * strength), 4.0, true)
		draw_polyline(pts.slice(6), Color(1, 0.98, 0.9, 0.75 * strength), 1.6, true)
