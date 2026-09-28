extends SceneTree
## Gera scenes/arena/arena_backdrop.tscn: o fundo da arena como ÁRVORE DE NÓS EDITÁVEIS.
## Roda UMA vez (ou para recomeçar do zero). Depois, a .tscn é a fonte de verdade: edite no
## editor do Godot. Rodar de novo SOBRESCREVE as edições feitas na cena.
##
##   godot --headless --path . -s "$PWD/tools/arena_backdrop/generate_backdrop_scene.gd"
##
## (Caminho absoluto porque tools/ tem .gdignore.) Precisa de assets/art/arena_layers/*.png e
## scripts/visuals/backdrop/arena_layers_data.gd, gerados por build_layers.py.

const OUT := "res://scenes/arena/arena_backdrop.tscn"
const L := "res://assets/art/arena_layers/"
const S := "res://scripts/visuals/backdrop/"
const MOON := Vector2(1228, 92)
const MOON_R := 66.0
const RIM := Color(0.66, 0.74, 0.93)

var bd: ArenaBackdrop
var _add_mat := CanvasItemMaterial.new()


func _initialize() -> void:
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	bd = ArenaBackdrop.new()
	bd.name = "ArenaBackdrop"
	_build_sky()
	_build_moon()
	_build_clouds("FarClouds", 0.05, 1.6, 7, Vector2(160, 260), Vector2(13, 19), Vector2(36, 150), 4, 11.0,
		[Color(0.29, 0.34, 0.46), Color(0.4, 0.46, 0.6), Color(0.24, 0.28, 0.39), Color(0.64, 0.72, 0.88)])
	_build_clouds("MidClouds", 0.09, 3.2, 6, Vector2(260, 420), Vector2(24, 34), Vector2(64, 196), 6, 23.0,
		[Color(0.26, 0.31, 0.43), Color(0.46, 0.53, 0.67), Color(0.17, 0.21, 0.31), Color(0.86, 0.91, 1.0)])
	_build_clouds("NearClouds", 0.14, 5.0, 4, Vector2(400, 560), Vector2(38, 50), Vector2(34, 112), 8, 41.0,
		[Color(0.21, 0.26, 0.37), Color(0.5, 0.57, 0.72), Color(0.13, 0.16, 0.25), Color(0.9, 0.94, 1.0)])
	_build_mountains("FarMountains", 0.2, 330.0, 3.0, 0.16, 3.5,
		[Vector4(60, 120, 130, 1.3), Vector4(260, 150, 150, 1.4), Vector4(470, 128, 120, 1.3), Vector4(640, 175, 130, 1.5),
		Vector4(820, 205, 140, 1.6), Vector4(990, 160, 120, 1.45), Vector4(1140, 190, 130, 1.55), Vector4(1400, 200, 150, 1.5),
		Vector4(1580, 165, 140, 1.4), Vector4(1720, 140, 120, 1.3)],
		Color(0.25, 0.3, 0.41), Color(0.38, 0.44, 0.57), 0.3)
	_build_fog("FarFog", 0.25, Rect2(-80, 170, 1832, 175), 1.4, 0.3, 0.35, Vector3(170, 290, 340), 5.0, Color(0.45, 0.52, 0.66))
	_build_mountains("MidMountains", 0.32, 342.0, 7.0, 0.2, 5.0,
		[Vector4(150, 170, 120, 1.6), Vector4(700, 200, 60, 2.2), Vector4(760, 160, 90, 1.7), Vector4(880, 215, 100, 1.8),
		Vector4(1020, 175, 90, 1.7), Vector4(1080, 140, 40, 2.3), Vector4(1215, 190, 50, 2.2), Vector4(1262, 285, 70, 2.4),
		Vector4(1330, 170, 110, 1.5), Vector4(1500, 160, 100, 1.5), Vector4(1640, 190, 110, 1.6)],
		Color(0.13, 0.16, 0.24), Color(0.25, 0.3, 0.41), 0.75)
	_build_fog("MidFog", 0.38, Rect2(-80, 160, 1832, 200), -2.2, 0.26, 0.15, Vector3(170, 300, 355), 23.0, Color(0.52, 0.59, 0.73))
	_build_castle()
	_build_ruins()
	_build_mountains("NearMountains", 0.58, 356.0, 13.0, 0.22, 4.0,
		[Vector4(250, 64, 170, 1.2), Vector4(560, 92, 150, 1.3), Vector4(690, 70, 90, 1.5), Vector4(1100, 84, 120, 1.4),
		Vector4(1185, 118, 70, 1.8), Vector4(1460, 110, 160, 1.4)],
		Color(0.075, 0.09, 0.14), Color(0.14, 0.17, 0.25), 0.5)
	_build_fog("NearFog", 0.68, Rect2(-80, 255, 1832, 118), 3.0, 0.3, 0.3, Vector3(262, 338, 372), 41.0, Color(0.58, 0.65, 0.78))
	_build_architecture("left")
	_build_architecture("right")
	_build_banner("left")
	_build_banner("right")
	_build_candles("left")
	_build_candles("right")
	var floor := _sprite("ArenaFloor", L + "arena.png", Vector2.ZERO, 1.0)
	bd.add_child(floor)
	_own(bd, bd)
	var scene := PackedScene.new()
	var err := scene.pack(bd)
	if err == OK:
		err = ResourceSaver.save(scene, OUT)
	if err == OK:
		_strip_null_params()
	print("generate_backdrop_scene: ", "OK " + OUT if err == OK else "ERRO %d" % err)
	bd.free()
	quit(0 if err == OK else 1)


## Sem GPU (headless) o Godot grava os uniforms não definidos como `null`; remove-os para
## valerem os padrões do shader.
func _strip_null_params() -> void:
	var text := FileAccess.get_file_as_string(OUT)
	var lines := text.split("\n")
	var kept := PackedStringArray()
	for line in lines:
		if not (line.begins_with("shader_parameter/") and line.ends_with(" = null")):
			kept.append(line)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(kept))
	f.close()


# --- céu, lua, nuvens, névoa ----------------------------------------------------------------

func _build_sky() -> void:
	var g := _group("Sky", 0.0)
	var rect := BackdropShaderRect.new()
	rect.name = "Gradient"
	rect.position = Vector2(-80, -60)
	rect.size = Vector2(1832, 480)
	var mat := ShaderMaterial.new()
	mat.shader = load(S + "shaders/sky.gdshader")
	mat.set_shader_parameter("moon_center", MOON)
	mat.set_shader_parameter("rect_origin", rect.position)
	mat.set_shader_parameter("rect_size", rect.size)
	rect.material = mat
	g.add_child(rect)


func _build_moon() -> void:
	var m := BackdropMoon.new()
	m.name = "Moon"
	m.position = MOON
	m.set_meta(&"parallax_depth", 0.02)
	bd.add_child(m)
	var disc := ColorRect.new()
	disc.name = "Disc"
	var mat := ShaderMaterial.new()
	mat.shader = load(S + "shaders/moon.gdshader")
	disc.material = mat
	m.add_child(disc)
	m.radius = MOON_R


func _build_clouds(name: String, depth: float, speed: float, count: int, len_range: Vector2, h_range: Vector2,
		y_range: Vector2, lumps: int, seed: float, colors: Array) -> void:
	var g := BackdropDrift.new()
	g.name = name
	g.speed = speed
	g.set_meta(&"parallax_depth", depth)
	bd.add_child(g)
	var span := g.wrap_right - g.wrap_left
	for i in count:
		var c := BackdropCloud.new()
		c.name = "Cloud%d" % (i + 1)
		var h := _hash(i, seed)
		c.position = Vector2(g.wrap_left + span * (i + 0.2 + 0.6 * _hash(i, seed + 1.0)) / count,
			lerpf(y_range.x, y_range.y, _hash(i, seed + 2.0)))
		c.length = lerpf(len_range.x, len_range.y, h)
		c.height = lerpf(h_range.x, h_range.y, _hash(i, seed + 3.0))
		c.lumps = lumps + int(_hash(i, seed + 4.0) * 3.0) - 1
		c.seed = seed + i
		c.body_color = colors[0]
		c.top_color = colors[1]
		c.belly_color = colors[2]
		c.rim_color = colors[3]
		g.add_child(c)


func _build_fog(name: String, depth: float, rect: Rect2, speed: float, opacity: float, haze: float,
		band: Vector3, seed: float, color: Color) -> void:
	var g := _group(name, depth)
	var fog := BackdropFog.new()
	fog.name = "Band"
	fog.position = rect.position
	fog.size = rect.size
	fog.speed = speed
	fog.opacity = opacity
	var mat := ShaderMaterial.new()
	mat.shader = load(S + "shaders/fog.gdshader")
	mat.set_shader_parameter("haze", haze)
	mat.set_shader_parameter("band_top", band.x)
	mat.set_shader_parameter("band_peak", band.y)
	mat.set_shader_parameter("band_bottom", band.z)
	mat.set_shader_parameter("seed", seed)
	mat.set_shader_parameter("fog_color", color)
	mat.set_shader_parameter("rect_origin", rect.position)
	mat.set_shader_parameter("rect_size", rect.size)
	fog.material = mat
	g.add_child(fog)


# --- montanhas ------------------------------------------------------------------------------

## Cada pico vira um Polygon2D próprio ("Peak3"…), posicionado na base do pico: arraste no
## editor ou edite os vértices. Cor por vértice = gradiente vertical (base clareia na névoa).
## A luz de borda (Line2D "Rim") só cobre o trecho do pico que aparece na silhueta.
func _build_mountains(name: String, depth: float, base_y: float, seed: float, rough: float, jag: float,
		peaks: Array, top: Color, bottom: Color, rim_strength: float) -> void:
	var g := _group(name, depth)
	var y_top := base_y
	for p in peaks:
		y_top = minf(y_top, base_y - p.y)
	var envelope := func(x: float) -> float:
		var best := base_y
		for p in peaks:
			best = minf(best, _peak_y(p, x, base_y, seed, rough, jag))
		return best
	for i in peaks.size():
		var p: Vector4 = peaks[i]
		var node := Polygon2D.new()
		node.name = "Peak%d" % (i + 1)
		node.position = Vector2(p.x, base_y)
		node.antialiased = true
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var x := p.x - p.z
		while x <= p.x + p.z + 0.01:
			var y := _peak_y(p, x, base_y, seed, rough, jag)
			pts.append(Vector2(x - p.x, y - base_y))
			cols.append(top.lerp(bottom, clampf((y - y_top) / (base_y + 30.0 - y_top), 0.0, 1.0)))
			x += 4.0
		pts.append(Vector2(p.z, 30))
		cols.append(bottom)
		pts.append(Vector2(-p.z, 30))
		cols.append(bottom)
		node.polygon = pts
		node.vertex_colors = cols
		g.add_child(node)
		# luz de borda: trechos visíveis (na envoltória) e voltados para a lua
		var seg := PackedVector2Array()
		var seg_i := 0
		for k in pts.size() - 2:
			var wp := pts[k] + node.position
			var visible: bool = wp.y <= envelope.call(wp.x) + 0.6
			if visible:
				seg.append(pts[k])
			if (not visible or k == pts.size() - 3) and seg.size() > 3:
				seg_i += 1
				_add_rim(node, "Rim%d" % seg_i if seg_i > 1 else "Rim", seg, node.position, rim_strength)
			if not visible:
				seg = PackedVector2Array()


func _peak_y(p: Vector4, x: float, base_y: float, seed: float, rough: float, jag: float) -> float:
	var d := absf(x - p.x) / p.z
	if d >= 1.0:
		return base_y
	var h := p.y * pow(1.0 - d, p.w)
	h *= 1.0 + (_fbm(x / 34.0, seed + 5.0) - 0.5) * 2.0 * rough
	h += (_noise(x / 9.0, seed + 11.0) - 0.5) * 2.0 * jag * (0.35 + 0.65 * (1.0 - d))
	return base_y - maxf(h, 0.0)


# --- castelo e ruínas -----------------------------------------------------------------------

const WALL_TOP := Color(0.05, 0.058, 0.095)
const WALL_BASE := Color(0.11, 0.13, 0.2)
const ROCK_TOP := Color(0.085, 0.1, 0.155)
const ROCK_BASE := Color(0.2, 0.24, 0.33)


func _build_castle() -> void:
	var castle := _group("CastleBack", 0.45)
	var main := Node2D.new()
	main.name = "MainCastle"
	castle.add_child(main)
	var east := Node2D.new()
	east.name = "EastKeep"
	castle.add_child(east)
	_rock(main, "Cliff", [Vector2(200, 372), Vector2(236, 268), Vector2(272, 226), Vector2(318, 196), Vector2(356, 178),
		Vector2(430, 172), Vector2(528, 173), Vector2(566, 186), Vector2(594, 214), Vector2(616, 252),
		Vector2(642, 300), Vector2(672, 350), Vector2(690, 372)])
	_rock(east, "Hill", [Vector2(1250, 372), Vector2(1268, 318), Vector2(1292, 272), Vector2(1318, 250), Vector2(1400, 244),
		Vector2(1440, 256), Vector2(1478, 290), Vector2(1500, 372)])
	_wall(main, "Wall", 352, 575, 130, 180)
	_wall(east, "Wall", 1298, 1392, 180, 254)
	var towers := [[main, 350, 16, 134, 178, 24], [main, 378, 28, 98, 178, 42], [main, 406, 11, 112, 178, 30],
		[main, 438, 62, 66, 178, 62], [main, 505, 10, 104, 178, 34], [main, 520, 28, 90, 178, 48], [main, 560, 15, 126, 180, 22],
		[main, 431, 10, 60, 104, 26], [main, 497, 10, 58, 104, 30],
		[east, 1300, 13, 176, 252, 18], [east, 1326, 26, 116, 252, 42], [east, 1366, 19, 146, 252, 26]]
	var n := {main: 0, east: 0}
	for t in towers:
		n[t[0]] += 1
		_tower(t[0], "Tower%d" % n[t[0]], t[1], t[2], t[3], t[4], t[5])
	var lights := CastleLights.new()
	lights.name = "CastleLights"
	lights.set_meta(&"parallax_depth", 0.45)
	bd.add_child(lights)
	var windows := [Vector2(447, 92), Vector2(461, 92), Vector2(476, 92), Vector2(490, 92), Vector2(454, 124), Vector2(483, 124),
		Vector2(468, 150), Vector2(387, 116), Vector2(397, 116), Vector2(392, 148), Vector2(529, 108), Vector2(539, 108),
		Vector2(534, 142), Vector2(412, 150), Vector2(424, 150), Vector2(508, 152), Vector2(548, 152), Vector2(357, 150),
		Vector2(566, 146), Vector2(1334, 138), Vector2(1344, 138), Vector2(1339, 172), Vector2(1375, 166), Vector2(1318, 206)]
	for i in windows.size():
		var w := CastleWindow.new()
		w.name = "Window%d" % (i + 1)
		w.position = windows[i]
		w.material = _add_mat
		lights.add_child(w)


func _rock(parent: Node2D, name: String, outline: Array) -> void:
	var anchor: Vector2 = outline[0]
	var pts := PackedVector2Array()
	for i in outline.size() - 1:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / 7.0))
		for k in steps:
			var p := a.lerp(b, float(k) / steps)
			if k > 0 and i > 0 and i < outline.size() - 2:
				p += Vector2((_noise(p.y / 6.0, 5.0) - 0.5) * 3.0, (_noise(p.x / 6.0, 3.0) - 0.5) * 5.0)
			pts.append(p)
	pts.append(outline[outline.size() - 1])
	var y_top := INF
	for p in pts:
		y_top = minf(y_top, p.y)
	var poly := _poly(parent, name, pts, anchor, ROCK_TOP, ROCK_BASE, y_top, 372.0)
	_add_rim(poly, "Rim", _to_local(pts.slice(1, pts.size() - 1), anchor), anchor, 0.55)


func _wall(parent: Node2D, name: String, x0: float, x1: float, top: float, base: float) -> void:
	var pts := PackedVector2Array([Vector2(x0, base), Vector2(x0, top - 4)])
	var x := x0 + 1.0
	while x + 4.0 <= x1:
		pts.append_array([Vector2(x, top - 4), Vector2(x + 4, top - 4), Vector2(x + 4, top), Vector2(minf(x + 7, x1), top)])
		x += 7.0
	pts.append_array([Vector2(x1, top - 4), Vector2(x1, base)])
	_poly(parent, name, pts, Vector2(x0, base), WALL_TOP, WALL_BASE, top - 10.0, base + 40.0)


func _tower(parent: Node2D, name: String, x: float, w: float, top: float, base: float, spire: float) -> void:
	var cx := x + w / 2.0
	var roof_top := top - 3
	var pts := PackedVector2Array([Vector2(x, base), Vector2(x, top), Vector2(x - 1.5, top), Vector2(x - 1.5, top - 3)])
	var sx := x
	var sw := w
	if w > 36.0:   # menagem: telhado baixo + agulha central (silhueta gótica, não pirâmide)
		roof_top = top - 12
		sw = 22.0
		sx = cx - sw / 2.0
		pts.append(Vector2(x + w * 0.25, roof_top))
	var apex := Vector2(cx, roof_top - spire)
	pts.append_array([Vector2(sx - 1.0, roof_top), Vector2(sx + sw * 0.2, roof_top - spire * 0.42), apex,
		Vector2(sx + sw * 0.8, roof_top - spire * 0.42), Vector2(sx + sw + 1.0, roof_top)])
	if w > 36.0:
		pts.append(Vector2(x + w * 0.75, roof_top))
	pts.append_array([Vector2(x + w + 1.5, top - 3), Vector2(x + w + 1.5, top), Vector2(x + w, top), Vector2(x + w, base)])
	var anchor := Vector2(cx, base)
	var poly := _poly(parent, name, pts, anchor, WALL_TOP, WALL_BASE, apex.y, base + 40.0)
	var finial := Line2D.new()
	finial.name = "Finial"
	finial.points = _to_local(PackedVector2Array([apex, apex - Vector2(0, 5)]), anchor)
	finial.width = 1.0
	finial.default_color = WALL_TOP
	poly.add_child(finial)
	var lit_right := MOON.x > cx
	var ex := x + w if lit_right else x
	var rim := PackedVector2Array([apex, Vector2(sx + sw * (0.8 if lit_right else 0.2), roof_top - spire * 0.42),
		Vector2(sx + (sw + 1.0 if lit_right else -1.0), roof_top), Vector2(ex, top), Vector2(ex, lerpf(top, base, 0.6))])
	var line := _line(poly, "Rim", _to_local(rim, anchor), 1.2)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(RIM, 0.55), Color(RIM, 0.45), Color(RIM, 0.0)])
	line.gradient = grad


func _build_ruins() -> void:
	var g := _group("Ruins", 0.5)
	_bridge(g, "BridgeWest", 574, 712, 150, 13, 272, 3, 11, false, true)
	_bridge(g, "BridgeEast", 1156, 1242, 206, 11, 300, 2, 10, false, true)
	_bridge(g, "BridgeEastEnd", 1270, 1318, 214, 11, 300, 1, 10, true, false)
	var towers := [[900, 18, 246, 318], [1098, 15, 262, 318], [766, 13, 272, 318]]
	for i in towers.size():
		var t: Array = towers[i]
		var x: float = t[0]
		var tw: float = t[1]
		var pts := PackedVector2Array([Vector2(x, t[3]), Vector2(x, t[2] + 3.0)])
		for k in range(1, 4):
			pts.append(Vector2(x + tw * k / 4.0, t[2] + _hash(int(x) + k, 9.0) * 7.0))
		pts.append_array([Vector2(x + tw, t[2] + 5.0), Vector2(x + tw, t[3])])
		_poly(g, "BrokenTower%d" % (i + 1), pts, Vector2(x + tw / 2.0, t[3]),
			Color(0.075, 0.09, 0.14), Color(0.2, 0.24, 0.33), t[2], t[3] + 20.0)


func _bridge(parent: Node2D, name: String, x0: float, x1: float, top: float, deck: float, base: float,
		spans: int, pier: float, broken_start: bool, broken_end: bool) -> void:
	var span_w := (x1 - x0 - pier) / spans
	var r := (span_w - pier) / 2.0
	var spring := top + deck + r
	var top_edge := PackedVector2Array()
	var x := x0
	while x <= x1 + 0.01:
		var y := top
		if broken_end and x > x1 - pier - 14.0:
			y = top + (x - (x1 - pier - 14.0)) * 0.35 + (_hash(int(x), 2.0) - 0.5) * 5.0
		if broken_start and x < x0 + pier + 14.0:
			y = top + ((x0 + pier + 14.0) - x) * 0.35 + (_hash(int(x), 4.0) - 0.5) * 5.0
		top_edge.append(Vector2(x, minf(y, top + deck * 0.9)))
		x += 3.0
	var pts := PackedVector2Array([Vector2(x0, base)])
	pts.append_array(top_edge)
	pts.append(Vector2(x1, base))
	var right := x1
	for s in spans:
		var pier_left := right - pier
		pts.append_array([Vector2(pier_left, base), Vector2(pier_left, spring)])
		var mid := pier_left - r
		for k in range(1, 12):
			var a := PI * k / 12.0
			pts.append(Vector2(mid + r * cos(a), spring - r * sin(a)))
		pts.append_array([Vector2(mid - r, spring), Vector2(mid - r, base)])
		right = mid - r
	var anchor := Vector2((x0 + x1) / 2.0, base)
	var poly := _poly(parent, name, pts, anchor, Color(0.075, 0.09, 0.14), Color(0.2, 0.24, 0.33), top - 5.0, base + 20.0)
	_add_rim(poly, "Rim", _to_local(top_edge, anchor), anchor, 0.5)


# --- primeiro plano (extraído da arte) ------------------------------------------------------

func _build_architecture(side: String) -> void:
	var a: Dictionary = ArenaLayersData.DATA.architecture[side]
	bd.add_child(_sprite(side.capitalize() + "Architecture", L + "architecture_%s.png" % side, Vector2(a.pos[0], a.pos[1]), 0.95))


func _build_banner(side: String) -> void:
	var cap := side.capitalize()
	var b: Dictionary = ArenaLayersData.DATA.banners[side]
	var banner := BannerSway.new()
	banner.name = cap + "Banner"
	banner.texture = load(L + "banner_%s.png" % side)
	banner.centered = false
	banner.position = Vector2(b.pos[0], b.pos[1])
	banner.top_px = b.top
	banner.phase = 0.0 if side == "left" else 2.4
	banner.set_meta(&"parallax_depth", 0.95)
	var mat := ShaderMaterial.new()
	mat.shader = load(S + "shaders/banner_sway.gdshader")
	banner.material = mat
	bd.add_child(banner)


func _build_candles(side: String) -> void:
	var data := ArenaLayersData.DATA
	var c: Dictionary = data.candles[side]
	var g := _group(side.capitalize() + "Candles", 0.95)
	var glow := CandleGlow.new()
	glow.name = "Glow"
	glow.texture = load(L + "candles_%s.png" % side)
	glow.centered = false
	glow.position = Vector2(c.pos[0], c.pos[1])
	glow.seed = 3.0 if side == "left" else 17.0
	var mat := ShaderMaterial.new()
	mat.shader = load(S + "shaders/candle_flicker.gdshader")
	glow.material = mat
	g.add_child(glow)
	for i in c.flames.size():
		var f: Array = c.flames[i]
		var flame := CandleFlame.new()
		flame.name = "Flame%d" % (i + 1)
		flame.flame_height = f[2]
		flame.position = Vector2(f[0], f[1] + f[2] * 0.3)
		flame.material = _add_mat
		g.add_child(flame)


# --- utilitários ----------------------------------------------------------------------------

func _group(name: String, depth: float) -> Node2D:
	var g := Node2D.new()
	g.name = name
	g.set_meta(&"parallax_depth", depth)
	bd.add_child(g)
	return g


func _sprite(name: String, path: String, pos: Vector2, depth: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = name
	s.texture = load(path)
	s.centered = false
	s.position = pos
	s.set_meta(&"parallax_depth", depth)
	return s


## Polygon2D com o nó na âncora (o que se arrasta no editor) e gradiente vertical por vértice.
func _poly(parent: Node, name: String, world_pts: PackedVector2Array, anchor: Vector2, top: Color, bottom: Color,
		y_top: float, y_bottom: float) -> Polygon2D:
	var node := Polygon2D.new()
	node.name = name
	node.position = anchor
	node.antialiased = true
	var cols := PackedColorArray()
	for p in world_pts:
		cols.append(top.lerp(bottom, clampf((p.y - y_top) / maxf(1.0, y_bottom - y_top), 0.0, 1.0)))
	node.polygon = _to_local(world_pts, anchor)
	node.vertex_colors = cols
	parent.add_child(node)
	return node


## Luz de borda: clareia só os trechos cuja normal aponta para a lua (gradiente ao longo da linha).
func _add_rim(parent: Node2D, name: String, local_pts: PackedVector2Array, origin: Vector2, strength: float) -> void:
	if local_pts.size() < 2:
		return
	var line := _line(parent, name, local_pts, 1.6)
	var grad := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	var total := 0.0
	var lens := [0.0]
	for i in range(1, local_pts.size()):
		total += local_pts[i].distance_to(local_pts[i - 1])
		lens.append(total)
	var step := maxi(1, local_pts.size() / 60)
	for i in range(0, local_pts.size(), step):
		var a := local_pts[maxi(i - 1, 0)]
		var b := local_pts[mini(i + 1, local_pts.size() - 1)]
		var d := (b - a).normalized()
		var n := Vector2(d.y, -d.x)
		var to_moon := (MOON - (local_pts[i] + origin)).normalized()
		offs.append(lens[i] / maxf(total, 0.001))
		cols.append(Color(RIM, strength * smoothstep(0.55, 0.98, n.dot(to_moon))))
	grad.offsets = offs
	grad.colors = cols
	line.gradient = grad


func _line(parent: Node, name: String, pts: PackedVector2Array, width: float) -> Line2D:
	var line := Line2D.new()
	line.name = name
	line.points = pts
	line.width = width
	line.antialiased = true
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	parent.add_child(line)
	return line


func _to_local(pts: PackedVector2Array, anchor: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p - anchor)
	return out


func _own(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		_own(c, owner)


static func _hash(i: float, s: float) -> float:
	var v := sin(i * 127.1 + s * 311.7) * 43758.5453
	return v - floorf(v)


static func _noise(x: float, s: float) -> float:
	var i := floorf(x)
	var f := x - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(_hash(i, s), _hash(i + 1.0, s), f)


static func _fbm(x: float, s: float) -> float:
	return _noise(x, s) * 0.55 + _noise(x * 2.1, s + 3.0) * 0.3 + _noise(x * 4.3, s + 7.0) * 0.15
