extends Node2D
## PROTÓTIPO (validação visual): sprite sheet piloto do Paladino Vivo em 3/4, frame a frame.
## Não faz parte do jogo nem do Sandbox — só mostra, na arena real e na escala de jogo:
##   - Idle, Walk e Attack lado a lado (+ o Paladino atual desenhado por código, para comparar);
##   - um Paladino andando pela arena na velocidade real (44/s), com o walk sincronizado aos pés;
##   - os mesmos três ampliados 1:1 (px do sprite) no topo, com o pivô marcado.
## Rodar: abrir scenes/prototypes/paladin_sprite_pilot.tscn e F6 (ou `godot --path . res://scenes/...`).
## Teclas: Espaço = pausa · ←/→ = frame a frame (pausado) · S = mostra/oculta a sombra.

const FRAMES := preload("res://assets/sprites/paladin_live_pilot/paladin_live_pilot_frames.tres")
const SHADOW := preload("res://assets/sprites/paladin_live_pilot/paladin_live_pilot_shadow.png")
## Contrato da sheet (assets/sprites/paladin_live_pilot/paladin_live_pilot.json).
const FRAME := 256.0
const PIVOT := Vector2(128, 240)
## Altura do personagem no frame (px, do pé à estrela da auréola) e altura desejada no mundo
## (a mesma do Paladino por código: ~47 unidades) → escala de jogo.
const CHAR_PX := 152.0
const WORLD_HEIGHT := 47.0
const GAME_SCALE := WORLD_HEIGHT / CHAR_PX
## Walk: o pé de apoio recua 24 px em meio ciclo (4 frames). A 14 fps → 84 px/s no sprite.
const WALK_FOOT_SPEED_PX := 24.0 * 14.0 / 4.0
const MOVE_SPEED := 44.0          # HTML: speed do sac_paladin

@onready var arena: Arena = $Arena

var _sprites: Array[AnimatedSprite2D] = []
var _shadows: Array[Sprite2D] = []
var _walker: AnimatedSprite2D
var _walker_dir := 1.0
var _paused := false


func _ready() -> void:
	arena.set_debug_visible(false)
	var ents := arena.get_node("Stage/World/Entities")
	# escala de jogo, no chão da arena
	var y := 390.0
	for i in 3:
		var anim: StringName = [&"idle", &"walk", &"attack"][i]
		_add(ents, anim, Vector2(420 + i * 70, y), GAME_SCALE, "%s (jogo)" % anim)
	_add_code_paladin(ents, Vector2(640, y))
	_walker = _add(ents, &"walk", Vector2(300, 470), GAME_SCALE, "")
	_walker.speed_scale = MOVE_SPEED / (WALK_FOOT_SPEED_PX * GAME_SCALE)
	# ampliado 1:1 (px do sprite), por cima de tudo, com o pivô marcado
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	for i in 3:
		var anim: StringName = [&"idle", &"walk", &"attack"][i]
		var s := _add(layer, anim, Vector2(170 + i * 230, 250), 1.0, "%s · %d frames · %d fps" % [anim, FRAMES.get_frame_count(anim), FRAMES.get_animation_speed(anim)])
		var mark := Polygon2D.new()
		mark.polygon = PackedVector2Array([Vector2(-5, 0), Vector2(0, -5), Vector2(5, 0), Vector2(0, 5)])
		mark.color = Color(1, 0.3, 0.3, 0.9)
		s.add_child(mark)
	var help := Label.new()
	help.text = "PROTÓTIPO — sprite sheet piloto do Paladino Vivo (3/4, frame a frame)   ·   Espaço: pausa   ←/→: frame   S: sombra"
	help.position = Vector2(12, 8)
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 4)
	layer.add_child(help)


## Um AnimatedSprite2D com o pivô (centro entre os pés) na posição dada, e a sombra embaixo.
func _add(parent: Node, anim: StringName, pos: Vector2, scale_k: float, label: String) -> AnimatedSprite2D:
	var shadow := Sprite2D.new()
	shadow.texture = SHADOW
	shadow.offset = Vector2(FRAME / 2.0, FRAME / 2.0) - PIVOT
	shadow.position = pos
	shadow.scale = Vector2.ONE * scale_k
	parent.add_child(shadow)
	_shadows.append(shadow)
	var s := AnimatedSprite2D.new()
	s.sprite_frames = FRAMES
	s.animation = anim
	s.offset = Vector2(FRAME / 2.0, FRAME / 2.0) - PIVOT   # pivô do contrato no ponto (0, 0)
	s.position = pos
	s.scale = Vector2.ONE * scale_k
	s.play()
	if not FRAMES.get_animation_loop(anim):
		s.animation_finished.connect(func() -> void: s.play())   # attack: repete para avaliar
	parent.add_child(s)
	_sprites.append(s)
	if label != "":
		var l := Label.new()
		l.text = label
		l.position = Vector2(-60, 14 if scale_k < 1.0 else 16) / (scale_k if scale_k < 1.0 else 1.0)
		l.add_theme_font_size_override("font_size", 12 if scale_k >= 1.0 else 28)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 5)
		s.add_child(l)
	return s


## O Paladino atual (desenhado por código), parado, para comparar escala e leitura.
func _add_code_paladin(parent: Node, pos: Vector2) -> void:
	var def := UnitCatalog.get_def(&"sac_paladin")
	var unit := CombatUnit.new(900, CombatUnit.Team.PLAYER, def.to_stats(), pos - Vector2(0, PaladinVisual.FOOT_Y))
	var view := UnitView.new(unit, def)
	parent.add_child(view)


func _process(delta: float) -> void:
	if _paused:
		return
	_walker.position.x += MOVE_SPEED * _walker_dir * delta
	if _walker.position.x > 720.0 or _walker.position.x < 280.0:
		_walker_dir = -_walker_dir
		_walker.flip_h = _walker_dir < 0.0   # o inimigo usa o espelho da mesma sheet
		_walker.offset.x = -_walker.offset.x
	_shadows[_sprites.find(_walker)].position = _walker.position


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			_paused = not _paused
			for s in _sprites:
				if _paused:
					s.pause()
				else:
					s.play()
		KEY_RIGHT, KEY_LEFT:
			if _paused:
				for s in _sprites:
					var n := s.sprite_frames.get_frame_count(s.animation)
					s.frame = posmod(s.frame + (1 if key.keycode == KEY_RIGHT else -1), n)
		KEY_S:
			for sh in _shadows:
				sh.visible = not sh.visible
