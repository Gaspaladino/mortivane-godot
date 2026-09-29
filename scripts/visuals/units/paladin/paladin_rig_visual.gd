class_name PaladinRigVisual
extends UnitVisual
## Paladino Vivo 100% desenhado por código em rig 2.5D (visual padrão do `sac_paladin`).
## Cena: scenes/units/paladin_rig_visual.tscn → Shadow · Rig (PaladinRig) · Effects (PaladinEffects).
##
## Divisão de responsabilidade:
##   CombatSim decide O QUE aconteceu  → esta classe só repassa eventos e o estado real
##   PaladinAnimator decide COMO aparece (estado, direção, transições, molas)
##   PaladinPoseLibrary guarda as poses  ·  PaladinRig desenha  ·  PaladinEffects faz os efeitos
##   PaladinRigLook = parâmetros do Inspector
## Nada aqui altera a CombatUnit: nem dano, nem posição, nem estado.

## Parâmetros visuais (Inspector). Vazio = data/visuals/paladin_rig_look.tres.
@export var look: PaladinRigLook
## Pés abaixo do centro lógico da CombatUnit (como os outros visuais).
@export var foot_y := 9.0

const DEBUG_FONT := 7

var rig: PaladinRig
var effects: PaladinEffects
var shadow_node: Node2D
var animator := PaladinAnimator.new()
var _flash := 0.0
var _debug := false


func setup(p_unit: CombatUnit, p_def: UnitDef) -> void:
	super(p_unit, p_def)


func _ready() -> void:
	if look == null:
		look = PaladinRigLook.get_default()
	shadow_node = _child(&"Shadow", Node2D)
	rig = _child(&"Rig", PaladinRig) as PaladinRig
	effects = _child(&"Effects", PaladinEffects) as PaladinEffects
	for n in [shadow_node, rig, effects]:
		n.position = Vector2(0, foot_y)
	effects.position = Vector2.ZERO
	rig.look = look
	effects.rig = rig
	effects.look = look
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	effects.material = add
	shadow_node.draw.connect(_draw_shadow)
	animator.setup(look, unit)
	_apply(0.0)


## Filho da cena (ou criado aqui, para o visual funcionar também só pelo script).
func _child(child_name: StringName, type) -> Node:
	var n := get_node_or_null(NodePath(child_name))
	if n == null:
		n = type.new()
		n.name = child_name
		add_child(n)
	return n


# --- Interface do UnitVisual ----------------------------------------------------------------

func on_attack_performed() -> void:
	animator.notify_attack()


func on_hit() -> void:
	if unit.is_alive():
		_flash = 0.12
	animator.notify_hit()


func on_ability_event(kind: StringName) -> void:
	if not unit.is_alive():
		return
	match kind:
		&"taunt":
			animator.notify_taunt()
			effects.taunt_t = 0.0
		&"shield":
			animator.notify_shield()
			effects.shield_up_t = 0.0
		&"block":
			animator.notify_block()
			effects.block_t = 0.0


## Empurrão (para mecânicas futuras que desloquem a unidade): só a reação de postura. O
## deslocamento continua vindo da simulação; o animador também detecta sozinho um deslocamento
## que a caminhada não explica.
func on_pushed(screen_dir: Vector2) -> void:
	animator.notify_push(screen_dir)


## Prévia só visual (Sandbox): &"idle", &"walk", &"attack", &"hit", &"push", &"taunt", &"shield",
## &"block", &"death"; `dir` = PaladinPoseLibrary.Dir. Não toca na CombatUnit.
func preview(kind: StringName, dir: int) -> void:
	if rig == null:
		return
	animator.preview(kind, dir)
	rig.overrides.clear()   # espada/escudo soltos por uma prévia de morte voltam às mãos
	match kind:
		&"taunt":
			effects.taunt_t = 0.0
		&"block":
			effects.block_t = 0.0


func update_visual(delta: float) -> void:
	if rig != null:   # antes do _ready não há rig
		_apply(delta)


func _apply(delta: float) -> void:
	var pose := animator.update(delta, unit, rig)
	rig.set_frame(pose, animator.yaw)
	_flash = maxf(0.0, _flash - delta)
	var k := _flash / 0.12
	rig.modulate = Color.WHITE.lerp(Color(1.7, 1.6, 1.4), k * look.hit_flash) if _flash > 0.0 else Color.WHITE
	var shielded := animator.guard_blend > 0.5 and animator.defense_w > 0.5
	rig.emblem_glow = animator.guard_blend * animator.defense_w * look.glow
	effects.step(delta, shielded)
	shadow_node.queue_redraw()
	var view := get_parent() as UnitView
	var dbg := view != null and view.debug_visible
	if dbg or _debug:
		_debug = dbg
		queue_redraw()


func top_y() -> float:
	return foot_y - 104.0 * look.scale - 1.0


func pick_rect() -> Rect2:
	if animator.dead:
		# corpo deitado: caixa dos pontos principais projetados (não depende de o quadro ter sido desenhado)
		var r := Rect2(rig.to_screen(rig.bone(&"pelvis").origin), Vector2.ZERO)
		for bn in [&"head", &"torso", &"r_foot", &"l_foot", &"r_hand", &"l_hand"]:
			r = r.expand(rig.to_screen(rig.bone(bn).origin))
		r.position += rig.position
		return r.grow_individual(3.0, 5.0, 3.0, 3.0)
	var h := 96.0 * look.scale
	var w := 30.0 * look.scale * 2.0 * 0.5
	return Rect2(-w, foot_y - h, w * 2.0, h + 3.0)


func ground_point() -> Vector2:
	return Vector2(0, foot_y)


# --- Desenho auxiliar -----------------------------------------------------------------------

func _draw_shadow() -> void:
	var lying := clampf(animator.death_t / PaladinPoseLibrary.DEATH_TIME, 0.0, 1.0) if animator.dead else 0.0
	var w := 1.0 + lying * 1.6
	shadow_node.draw_set_transform(Vector2.ZERO, 0.0, Vector2(w, 0.32))
	shadow_node.draw_circle(Vector2.ZERO, 26.0 * look.scale * 2.0 * 0.5 * 1.3, Color(0, 0, 0, 0.3))
	shadow_node.draw_set_transform(Vector2.ZERO)


## Debug (F4, junto do debug de combate): direção, estado da apresentação, pose-base, progresso.
func _draw() -> void:
	if not _debug:
		return
	var font := ThemeDB.fallback_font
	var target_dir := "—"
	if unit.target:
		target_dir = PaladinPoseLibrary.DIR_NAMES[PaladinPoseLibrary.dir_from_vector(unit.target.position - unit.position)]
	var lines := [
		"dir %s · yaw %d°" % [PaladinPoseLibrary.DIR_NAMES[animator.dir], roundi(rad_to_deg(animator.yaw))],
		"%s %.2f" % [animator.debug_state, animator.debug_progress],
		"alvo %s · pose %s" % [target_dir, PaladinPoseLibrary.attack_variant(animator.dir)],
	]
	var y := top_y() - 12.0 - lines.size() * (DEBUG_FONT + 1)
	for line in lines:
		draw_string_outline(font, Vector2(-60, y), line, HORIZONTAL_ALIGNMENT_CENTER, 120, DEBUG_FONT, 3, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(-60, y), line, HORIZONTAL_ALIGNMENT_CENTER, 120, DEBUG_FONT, Color(1.0, 0.9, 0.6))
		y += DEBUG_FONT + 1
