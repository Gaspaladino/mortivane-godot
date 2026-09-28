class_name MountainLayer
extends BackdropSilhouette
## Cordilheira gótica desenhada por código: picos altos e finos, silhueta irregular,
## gradiente vertical (a base clareia na neblina), luz de borda da lua e poucos vincos.
##
## Cada pico: Vector4(x, altura, meia-largura, agudeza). Agudeza > 1 = encostas côncavas,
## ponta de agulha (gótico); ~1,3 = montanha larga.

@export var peaks: Array[Vector4] = []
@export var base_y := 340.0
@export var x_range := Vector2(-80, 1752)
@export var step := 4.0
@export var seed := 1.0
## Ondulação mínima entre os picos (a cordilheira nunca chega a zero).
@export var min_height := 18.0
@export var jag := 4.0                       # serrilhado fino da crista (px)
## Irregularidade média (fração da altura): ombros, degraus e cristas secundárias.
@export var roughness := 0.14
@export var top_color := Color(0.1, 0.12, 0.19)
@export var base_color := Color(0.2, 0.24, 0.35)
@export var rim_color := Color(0.62, 0.7, 0.9)
@export_range(0.0, 1.0) var rim_strength := 0.6
@export var rim_width := 1.6
## Vincos: quantos por pico alto (0 = sem) e a altura mínima do pico para recebê-los.
@export var creases := 2
@export var crease_min_height := 150.0


func ridge_y(x: float) -> float:
	var h := min_height + fbm1(x / 160.0, seed) * min_height
	var hmax := 1.0
	for p in peaks:
		hmax = maxf(hmax, p.y)
		var d := absf(x - p.x) / p.z
		if d < 1.0:
			h = maxf(h, p.y * pow(1.0 - d, p.w))
	var frac := clampf(h / hmax, 0.0, 1.0)
	h *= 1.0 + (fbm1(x / 34.0, seed + 5.0) - 0.5) * 2.0 * roughness
	h += (noise1(x / 9.0, seed + 11.0) - 0.5) * 2.0 * jag * (0.35 + 0.65 * frac)
	return base_y - h


func _build() -> void:
	var ridge := PackedVector2Array()
	var x := x_range.x
	while x <= x_range.y:
		ridge.append(Vector2(x, ridge_y(x)))
		x += step
	var y_top := base_y
	for p in peaks:
		y_top = minf(y_top, base_y - p.y)
	add_ridge_fill(ridge, base_y + 30.0, top_color, base_color, y_top)
	_add_creases(y_top)
	add_line(ridge, _ridge_colors(ridge, y_top), 1.1)            # contorno suave (antialias)
	add_rim(ridge, rim_color, rim_width, rim_strength)


func _ridge_colors(ridge: PackedVector2Array, y_top: float) -> PackedColorArray:
	var cols := PackedColorArray()
	for p in ridge:
		cols.append(top_color.lerp(base_color, clampf((p.y - y_top) / (base_y + 30.0 - y_top), 0.0, 1.0)))
	return cols


## Vincos que descem dos picos altos: um escuro do lado da sombra, um claro do lado da lua.
func _add_creases(y_top: float) -> void:
	if creases <= 0:
		return
	var k := 0
	for p in peaks:
		if p.y < crease_min_height:
			continue
		var apex := Vector2(p.x, ridge_y(p.x))
		var lit_side := 1.0 if moon_center.x > p.x else -1.0
		for c in creases:
			var side := -lit_side if c % 2 == 0 else lit_side
			var pts := PackedVector2Array()
			var spread := (0.18 + 0.12 * c) * p.z
			for i in 7:
				var f := i / 6.0
				var wob := (noise1(f * 3.0 + k, seed + 21.0) - 0.5) * 4.0
				pts.append(apex + Vector2(side * spread * f + wob, p.y * 0.55 * f + 2.0))
			var col := top_color.darkened(0.35) if side != lit_side else rim_color
			var alpha := 0.45 if side != lit_side else 0.14
			add_solid_line(pts, Color(col, alpha), 1.2)
			k += 1
