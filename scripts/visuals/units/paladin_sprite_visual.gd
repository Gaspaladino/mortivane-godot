class_name PaladinSpriteVisual
extends UnitVisual
## Paladino Vivo com a sprite sheet aprovada (frame a frame, 3/4). Cena:
## scenes/units/paladin_sprite_visual.tscn → Shadow · Sprite (AnimatedSprite2D) · Effects.
##
## Só LÊ o estado real (CombatUnit + unit.paladin) e os eventos repassados pela Battle; nenhuma
## regra de combate aqui. O estado real decide a animação:
##   morto                           → death (uma vez; para no último frame: o corpo fica no campo)
##   provocação (evento)             → taunt (uma vez)
##   golpe                           → attack: a preparação começa pela recarga real (ou ao chegar
##                                     no alcance) e o frame de IMPACTO aparece no evento real de dano
##   escudo absorveu dano (evento)   → defend, frames do clarão
##   dano recebido                   → hit (curto); durante golpe/provocação só pisca
##   espera do escudo / escudo ativo → defend: ergue (frame 0) e segura a guarda (último frame)
##   andando                         → walk (velocidade do quadro acompanha o deslocamento real)
##   resto                           → idle
## Os efeitos da habilidade (barreira, anéis) são os mesmos do visual por código (PaladinFx).

## Frames do SpriteFrames (paladin_live_frames.tres, gerado por tools/sprites/slice_paladin_live.py).
@export var frames: SpriteFrames
## Escala do sprite no mundo. Com 0,35 o Paladino fica com ~47 unidades até a auréola
## (Guerreiro: ~35), como o Paladino por código.
@export_range(0.1, 1.0, 0.005) var sprite_scale := 0.35:
	set(v):
		sprite_scale = v
		_apply_scale()
## Pés abaixo do centro lógico da CombatUnit (igual ao Paladino por código).
@export var foot_y := 10.0
## Pivô do frame (centro entre os pés) e tamanho da célula, em px da arte (contrato da sheet).
@export var frame_pivot := Vector2(160, 192)
@export var frame_size := Vector2(320, 208)
## Altura da arte parada (pé à auréola) e largura do corpo, em px: barra de HP e área clicável.
@export var art_height := 136.0
@export var art_body_width := 84.0
## A arte olha para a direita; o inimigo usa o espelho.
@export var art_faces_right := true
## Frame do ataque em que a espada atinge (sincronizado com o dano real).
@export var attack_impact_frame := 3
## Velocidade de deslocamento em que o walk roda no FPS do recurso.
@export var walk_reference_speed := 44.0
## Força dos efeitos da habilidade (barreira, anéis).
@export_range(0.0, 2.0, 0.05) var effects_glow := 1.0
@export var show_taunt_ring := true

const HIT_FLASH := 0.12

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var effects: Node2D = $Effects
@onready var shadow_node: Node2D = $Shadow

var _facing := 1.0
var _last_pos := Vector2.ZERO
var _speed := 0.0               # velocidade suavizada (ritmo do walk)
var _moved_now := false         # deslocou-se neste quadro (decide se anda)
## Estado da apresentação: &"idle", &"walk", &"attack", &"defend", &"taunt", &"hit", &"death".
var mode := &"idle"
var _striking := false          # o impacto já aconteceu (tocando o resto do golpe)
var _taunt_playing := false
var _hit_t := 0.0
var _block_t := 0.0
var _flash := 0.0
var _taunt_t := -1.0
var _shield_ring_t := -1.0
var _barrier_age := 0.0
var _was_shielded := false
var _shield_raised := false


func setup(p_unit: CombatUnit, p_def: UnitDef) -> void:
	super(p_unit, p_def)
	_facing = 1.0 if unit.team == CombatUnit.Team.PLAYER else -1.0
	_last_pos = unit.position


func _ready() -> void:
	if frames:
		sprite.sprite_frames = frames
	sprite.centered = true
	sprite.offset = frame_size / 2.0 - frame_pivot     # pivô do contrato no ponto (0, 0) do Sprite
	sprite.position = Vector2(0, foot_y)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.animation_finished.connect(_on_animation_finished)
	shadow_node.position = Vector2(0, foot_y)
	shadow_node.draw.connect(_draw_shadow)
	effects.draw.connect(_draw_effects)
	_apply_scale()
	_play(&"idle")


func _apply_scale() -> void:
	if is_node_ready():
		sprite.scale = Vector2(sprite_scale, sprite_scale)


# --- Interface do UnitVisual ----------------------------------------------------------------

func on_attack_performed() -> void:
	if not unit.is_alive():
		return
	# o evento real manda: o frame de impacto aparece agora, venha a preparação de onde vier
	_striking = true
	_taunt_playing = false
	_play(&"attack", attack_impact_frame)


func on_hit() -> void:
	_flash = HIT_FLASH
	var shielded := unit.paladin != null and unit.paladin.is_shielded()
	if not unit.is_alive() or shielded or mode in [&"attack", &"taunt", &"death"]:
		return   # golpe, provocação e guarda do escudo não são interrompidos: só pisca
	_hit_t = _anim_length(&"hit")
	_play(&"hit", 0)


func on_ability_event(kind: StringName) -> void:
	if not unit.is_alive():
		return
	match kind:
		&"taunt":
			_taunt_t = 0.0
			_taunt_playing = true
			_play(&"taunt", 0)
		&"shield":
			_shield_ring_t = 0.0
			_barrier_age = 0.0
			_shield_raised = true
			if mode in [&"idle", &"walk", &"defend", &"hit"]:
				_play(&"defend", 1)       # clarão do escudo subindo, depois segura a guarda
		&"block":
			_block_t = 0.2
			if mode in [&"idle", &"walk", &"defend", &"hit"]:
				_play(&"defend", 1)


func top_y() -> float:
	return foot_y - art_height * sprite_scale - 4.0


func pick_rect() -> Rect2:
	var k := sprite_scale
	if mode == &"death":
		return Rect2(-100.0 * k, foot_y - 64.0 * k, 200.0 * k, 70.0 * k)
	return Rect2(-art_body_width * 0.5 * k, foot_y - art_height * k, art_body_width * k, art_height * k + 3.0)


func ground_point() -> Vector2:
	return Vector2(0, foot_y)


func update_visual(delta: float) -> void:
	var alive := unit.is_alive()
	var pal := unit.paladin
	if alive:
		if pal and pal.is_shielded() and pal.facing.x != 0.0:
			_facing = signf(pal.facing.x)
		elif unit.target != null:
			var dx := unit.target.position.x - unit.position.x
			if absf(dx) > 0.5:
				_facing = signf(dx)
	sprite.flip_h = (_facing < 0.0) == art_faces_right

	var moved := unit.position.distance_to(_last_pos)
	_last_pos = unit.position
	_moved_now = moved > 0.01
	if delta > 0.0:
		_speed = lerpf(_speed, moved / delta, 1.0 - exp(-delta * 10.0))
	_hit_t = maxf(0.0, _hit_t - delta)
	_block_t = maxf(0.0, _block_t - delta)
	_flash = maxf(0.0, _flash - delta)
	if _taunt_t >= 0.0:
		_taunt_t += delta
		if _taunt_t > PaladinFx.TAUNT_RING_TIME:
			_taunt_t = -1.0
	if _shield_ring_t >= 0.0:
		_shield_ring_t += delta
		if _shield_ring_t > PaladinFx.SHIELD_RING_TIME:
			_shield_ring_t = -1.0
	var shielded := alive and pal != null and pal.is_shielded()
	if shielded:
		_barrier_age += delta
	elif _was_shielded:
		_barrier_age = 0.0
		_shield_raised = false
	_was_shielded = shielded

	_choose_animation(delta)
	sprite.modulate = Color(1, 1, 1).lerp(Color(1.6, 1.5, 1.3), _flash / HIT_FLASH * 0.6) if _flash > 0.0 else Color.WHITE
	shadow_node.queue_redraw()
	effects.queue_redraw()


# --- Escolha da animação (lê o estado real) -------------------------------------------------

func _choose_animation(_delta: float) -> void:
	if not unit.is_alive():
		if mode != &"death":
			_striking = false
			_taunt_playing = false
			_play(&"death", 0)
		return
	if _taunt_playing or _striking:
		return   # tocam até o fim (_on_animation_finished)
	# preparação do golpe: começa para que o frame de impacto caia no instante previsto do dano e
	# segura o frame anterior ao impacto até o evento real (a lógica manda no timing)
	var lead := _time_to_impact()
	if lead >= 0.0 and lead <= attack_impact_frame / _fps(&"attack"):
		if mode != &"attack":
			var start := clampi(attack_impact_frame - int(ceil(lead * _fps(&"attack"))), 0, attack_impact_frame - 1)
			_play(&"attack", start)
		if sprite.frame >= attack_impact_frame - 1:
			sprite.frame = attack_impact_frame - 1
			sprite.pause()
		return
	if _hit_t > 0.0 and mode == &"hit":
		return
	var pal := unit.paladin
	if pal and (pal.is_shielded() or pal.is_preparing() or _block_t > 0.0):
		if mode != &"defend":
			_play(&"defend", 0 if pal.is_preparing() else 1)
		if pal.is_preparing() and not pal.is_shielded():
			sprite.frame = 0   # escudo erguido, esperando a bênção subir
			sprite.pause()
		elif not sprite.is_playing() and sprite.frame == 0:
			_play(&"defend", 1)   # a bênção subiu: clarão e guarda
		return
	if unit.state == CombatUnit.State.MOVING or _moved_now:
		if mode != &"walk":
			_play(&"walk", 0)
		sprite.speed_scale = clampf(maxf(_speed, 1.0) / walk_reference_speed, 0.5, 1.8)
		return
	if mode != &"idle":
		_play(&"idle", 0)


## Segundos até o dano previsto; −1 = nenhum golpe a caminho.
## No alcance: a recarga real; chegando: distância que falta ÷ velocidade (recarga já pronta).
func _time_to_impact() -> float:
	var t := unit.target
	if t == null or not t.is_alive():
		return -1.0
	if unit.state == CombatUnit.State.ATTACKING and unit.cooldown > 0.0:
		return unit.cooldown
	if unit.cooldown <= 0.0 and unit.move_speed > 0.0:
		var gap := unit.position.distance_to(t.position) - unit.attack_range
		if gap > 0.0:
			return gap / unit.move_speed
	return -1.0


func _on_animation_finished() -> void:
	match mode:
		&"attack":
			_striking = false
			_play(&"idle", 0)
		&"taunt":
			_taunt_playing = false
			_play(&"idle", 0)
		&"hit":
			_hit_t = 0.0
			_play(&"idle", 0)
		&"defend":
			sprite.frame = sprite.sprite_frames.get_frame_count(&"defend") - 1   # segura a guarda
			sprite.pause()
		# death: fica no último frame (o corpo permanece no campo)


func _play(anim: StringName, from_frame := 0) -> void:
	mode = anim
	sprite.speed_scale = 1.0
	sprite.play(anim)
	sprite.frame = from_frame
	sprite.frame_progress = 0.0


func _fps(anim: StringName) -> float:
	return sprite.sprite_frames.get_animation_speed(anim) if sprite and sprite.sprite_frames else 10.0


func _anim_length(anim: StringName) -> float:
	return sprite.sprite_frames.get_frame_count(anim) / _fps(anim)


# --- Desenho auxiliar -----------------------------------------------------------------------

func _draw_shadow() -> void:
	var lying := 1.0 if mode == &"death" else 0.0
	shadow_node.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 + lying * 1.2, 0.3))
	shadow_node.draw_circle(Vector2.ZERO, 44.0 * sprite_scale, Color(0, 0, 0, 0.3))


func _draw_effects() -> void:
	var pal := unit.paladin
	if pal == null:
		return
	if unit.is_alive() and pal.is_shielded():
		PaladinFx.barrier(effects, pal, unit.radius, _barrier_age, effects_glow, Color(1.0, 0.82, 0.35), Color("ffdc72"), Vector2(_facing, 0))
	if show_taunt_ring:
		PaladinFx.taunt_ring(effects, _taunt_t, effects_glow, Color("f0c674"))
	PaladinFx.shield_ring(effects, _shield_ring_t, unit.radius, effects_glow, Color("f0c674"))
