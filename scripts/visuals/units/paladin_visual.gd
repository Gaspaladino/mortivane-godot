class_name PaladinVisual
extends CodeDrawnUnitVisual
## Paladino desenhado 100% por código. Referência: arte conceitual "Paladino Vivo / Sombra"
## (armadura pesada marfim com dourado, elmo fechado de visor estreito, auréola dourada,
## ombreiras grandes, tabardo claro com sol sagrado, capa, escudo grande com o sol, espada
## de uma mão). A intenção de pose/tempo segue o rig do HTML (drawPaladinArt, heavyMelee:
## preparação 0,20 s, golpe desce em 0,12 s, retorno até 0,46 s; bloqueio 0,28 s; hit 0,25 s;
## provocação 0,34 s; queda de 0,72 s e o corpo fica no chão com escudo e espada soltos).
##
## Só LÊ o estado real: CombatUnit (estado, alvo, recarga) e unit.paladin (PaladinTaunt:
## espera até o escudo, escudo ativo, impacto no escudo, direção travada). Eventos:
## on_attack_performed (golpe real), on_hit, on_ability_event(taunt/shield/block).
##
## Rig (espaço do rig: origem no chão entre os pés, virado para +x, y para baixo):
##   raiz (espelho + escala) → quadril → pernas / tronco → cabeça (auréola, elmo)
##   tronco → ombro de trás → braço da espada → mão → espada
##   tronco → ombro da frente → braço do escudo → mão → escudo
## Ordem: névoa/sombra · capa · braço da espada e ombreira de trás · pernas · tabardo e cinto ·
##        peitoral · cabeça · espada e manopla · braço do escudo, ombreira e escudo · efeitos
##        (rastro do golpe, barreira sagrada, anel da provocação).
##
## Parâmetros editáveis: PaladinLook (data/visuals/paladin_look.tres), via UnitDef.visual_look.

const FOOT_Y := 10.0
const HIP := Vector2(0, -13)
const LEG_FRONT_X := 2.4
const LEG_BACK_X := -2.6
const NECK := Vector2(0.8, -15.2)           # no espaço do tronco (origem no quadril)
const SHOULDER_FRONT := Vector2(2.8, -12.8) # braço do escudo
const SHOULDER_BACK := Vector2(-3.4, -13.0) # braço da espada
const ARM_LENGTH := 10.0
const SWORD_LENGTH := 18.0
# tempos (HTML: UNIT_POSE_PROFILES.heavyMelee e paladinCue)
const WINDUP_TIME := 0.20
const STRIKE_DOWN := 0.12
const RECOVER_START := 0.19
const RECOVER_END := 0.46
const BLOCK_TIME := 0.28
const HIT_TIME := 0.25
const TAUNT_TIME := 0.34
const TAUNT_RING_TIME := PaladinFx.TAUNT_RING_TIME
const SHIELD_RING_TIME := PaladinFx.SHIELD_RING_TIME
const DEATH_TIME := 0.72

# --- Paleta (vem do PaladinLook; a Sombra converte em _apply_shadow_style) ---------------
var look: PaladinLook
var ivory := Color("e6ddca")
var ivory_light := Color("fff3dd")
var steel_shade := Color("9b948a")
var under_armor := Color("2a2833")
var gold := Color("d9ad52")
var gold_light := Color("ffe39a")
var cloth := Color("f1ead8")
var cape_color := Color("c7bea9")
var blade := Color("dfe4ea")
var leather := Color("4a3526")
## Luz dos efeitos (rastro do golpe, barreira, anéis): dourado sagrado na viva.
var holy := Color("fff0b3")
var holy_edge := Color("ffdc72")
## Emblema solar do escudo e do tabardo.
var emblem := Color("d9ad52")
var visor := Color("0e0d14")

# --- Estilo de animação (a Sombra ajusta) -------------------------------------------------
var idle_bob := 0.25
var stride := 13.0              # distância no mundo por ciclo de passos (curta e pesada)
var leg_swing := 18.0
var walk_bob := 0.6
var rest_sword_arm := 26.0      # braço da espada em repouso (+ = para trás)
var rest_sword := -12.0         # espada quase em pé, pronta (0 = para cima, + = para frente)
var windup_arm := 150.0
var windup_sword := -58.0
var strike_arm := -72.0
var strike_sword := 118.0
var rest_shield_arm := -48.0    # antebraço do escudo à frente do corpo
var guard_shield_arm := -66.0

# --- Estado da animação -------------------------------------------------------------------
var _facing := 1.0
var _last_pos := Vector2.ZERO
var _walk_phase := 0.0
var _walk_w := 0.0
var _strike_t := -1.0
var _hit_t := 0.0
var _hit_force := 0.5
var _block_t := 0.0
var _taunt_t := -1.0
var _shield_ring_t := -1.0
var _death_t := -1.0
var _sword_follow := 0.0
var _shield_follow := 0.0
var _barrier_age := 0.0
var _was_shielded := false

# --- Pose do quadro -----------------------------------------------------------------------
var p_offset := Vector2.ZERO
var p_rot := 0.0
var p_scale := Vector2.ONE
var p_lean := 0.0
var p_head := 0.0
var p_crouch := 0.0             # joelhos cedendo / postura de guarda (baixa o quadril)
var p_leg_f := 0.0
var p_leg_b := 0.0
var p_arm_s := 0.0              # braço da espada
var p_sword := 0.0
var p_arm_h := 0.0              # braço do escudo
var p_shield_tilt := 0.0
var p_shield_push := 0.0
var p_cape := 0.0
var p_wind := 0.0               # 0..1 preparação do golpe
var p_guard := 0.0              # 0..1 escudo erguido (espera + escudo ativo)
var p_halo := 0.0               # brilho extra da auréola
var p_shield_flash := 0.0
var p_sword_drop := 0.0         # 0..1 espada caindo (morte)
var p_shield_drop := 0.0        # 0..1 escudo caindo (morte)


func setup(p_unit: CombatUnit, p_def: UnitDef) -> void:
	look = p_def.visual_look as PaladinLook if p_def and p_def.visual_look is PaladinLook else PaladinLook.get_default()
	_apply_look(look)
	outline = Color("11101a")
	super(p_unit, p_def)   # na Sombra: converte a paleta (depois de ler o PaladinLook)
	_seed = float(unit.id) * 1.618
	_time = fmod(_seed * 3.1, TAU)
	_facing = 1.0 if unit.team == CombatUnit.Team.PLAYER else -1.0
	_last_pos = unit.position
	_sword_follow = rest_sword
	_shield_follow = rest_shield_arm
	_compute_pose(0.0)


func _apply_look(l: PaladinLook) -> void:
	ivory = l.ivory
	ivory_light = l.ivory_light
	steel_shade = l.steel_shade
	under_armor = l.under_armor
	gold = l.gold
	gold_light = l.gold_light
	cloth = l.cloth
	cape_color = l.cape
	blade = l.blade
	holy = l.holy_light
	emblem = l.gold
	flash_color = Color("fff8e8")


# --- Interface do UnitVisual ----------------------------------------------------------------

func on_attack_performed() -> void:
	if unit.is_alive():
		_strike_t = 0.0


func on_hit() -> void:
	_hit_t = HIT_TIME
	# golpe pesado (HTML: amount ≥ 14% do HP máximo) empurra mais
	_hit_force = 0.5


func on_ability_event(kind: StringName) -> void:
	if not unit.is_alive():
		return
	match kind:
		&"taunt":
			_taunt_t = 0.0
		&"shield":
			_shield_ring_t = 0.0
			_barrier_age = 0.0
		&"block":
			_block_t = BLOCK_TIME


func top_y() -> float:
	return FOOT_Y - 47.0 * _k()   # acima da estrela da auréola


func pick_rect() -> Rect2:
	var k := _k()
	if _death_t >= 0.0:   # deitado de costas: o corpo fica para trás da direção em que olhava
		var x0 := -38.0 * k if _facing > 0.0 else -12.0 * k
		return Rect2(x0, FOOT_Y - 14.0 * k, 50.0 * k, 18.0 * k)
	return Rect2(-13.0 * k, FOOT_Y - 39.0 * k, 26.0 * k, 43.0 * k)


func ground_point() -> Vector2:
	return Vector2(0, FOOT_Y)


func update_visual(delta: float) -> void:
	_time += delta
	var alive := unit.is_alive()
	var pal := unit.paladin

	if alive:
		if pal and pal.is_shielded() and pal.facing.x != 0.0:
			_facing = signf(pal.facing.x)   # o escudo encara a direção travada na ativação
		elif unit.target != null:
			var dx := unit.target.position.x - unit.position.x
			if absf(dx) > 0.5:
				_facing = signf(dx)

	var moved := unit.position.distance_to(_last_pos)
	_last_pos = unit.position
	var moving := alive and (unit.state == CombatUnit.State.MOVING or moved > 0.01)
	if moving:
		_walk_phase += moved / stride * TAU
	_walk_w = move_toward(_walk_w, 1.0 if moving else 0.0, delta * 6.0)

	_hit_t = maxf(0.0, _hit_t - delta)
	_block_t = maxf(0.0, _block_t - delta)
	if _strike_t >= 0.0:
		_strike_t += delta
		if _strike_t > RECOVER_END:
			_strike_t = -1.0
	if _taunt_t >= 0.0:
		_taunt_t += delta
		if _taunt_t > TAUNT_RING_TIME:
			_taunt_t = -1.0
	if _shield_ring_t >= 0.0:
		_shield_ring_t += delta
		if _shield_ring_t > SHIELD_RING_TIME:
			_shield_ring_t = -1.0
	var shielded := alive and pal != null and pal.is_shielded()
	if shielded:
		_barrier_age += delta
	elif _was_shielded:
		_barrier_age = 0.0
	_was_shielded = shielded
	if not alive and _death_t < 0.0:
		_death_t = 0.0
		_strike_t = -1.0
		_taunt_t = -1.0
	if _death_t >= 0.0:
		_death_t += delta

	_compute_pose(delta)
	queue_redraw()


# --- Pose -----------------------------------------------------------------------------------

func _k() -> float:
	return look.scale if look else 1.0


func _compute_pose(delta: float) -> void:
	var w := _walk_w
	var sec := look.secondary_speed if look else 1.0
	var br := sin(_time * 1.7 * sec + _seed)

	# IDLE: firme — respiração mínima, a armadura quase não balança, a capa reage de leve
	p_offset = Vector2(0, br * idle_bob * (1.0 - w))
	p_rot = 0.0
	p_scale = Vector2.ONE
	p_lean = _wobble() * 2.0
	p_head = -br * 0.8 * (1.0 - w)
	p_crouch = 0.0
	p_arm_s = rest_sword_arm + br * 1.2
	p_arm_h = rest_shield_arm + br * 0.8
	p_shield_tilt = 0.0
	p_shield_push = 0.0
	p_cape = sin(_time * 1.1 * sec + _seed) * 1.6
	p_halo = 0.0
	p_shield_flash = 0.0
	p_sword_drop = 0.0
	p_shield_drop = 0.0
	p_wind = 0.0
	p_guard = 0.0

	# WALK: passada curta e pesada; ombros e tronco avançam juntos; escudo quase parado
	var s := sin(_walk_phase)
	p_leg_f = s * leg_swing * w
	p_leg_b = -s * leg_swing * w
	p_offset.y -= absf(cos(_walk_phase)) * walk_bob * w
	p_offset.y += 0.35 * w                         # joelhos levemente dobrados ao andar
	p_lean += 3.0 * w
	p_head -= 1.5 * w
	p_arm_h += s * 2.0 * w
	p_arm_s += s * 5.0 * w
	p_cape += (7.0 + cos(_walk_phase) * 2.0) * w
	var sword_target := rest_sword - s * 4.0 * w

	# DEFESA: espera até o escudo (estado real) → ergue o escudo; escudo ativo → guarda firme
	var pal := unit.paladin
	if pal and unit.is_alive():
		p_guard = 1.0 if pal.is_shielded() else _ease_in_out(pal.prepare_progress())
	if p_guard > 0.0:
		p_arm_h = lerpf(p_arm_h, guard_shield_arm, p_guard)
		p_shield_push += 2.4 * p_guard
		p_shield_tilt -= 7.0 * p_guard
		p_crouch += 1.2 * p_guard
		p_lean += 3.5 * p_guard
		p_halo += 0.6 * p_guard

	# PROVOCAÇÃO: batida do escudo à frente, peito estufado (HTML: +0,075 r à frente, sobe)
	if _taunt_t >= 0.0 and _taunt_t < TAUNT_TIME:
		var tk := sin(clampf(_taunt_t / TAUNT_TIME, 0.0, 1.0) * PI)
		p_offset.x += 1.2 * tk
		p_offset.y -= 0.6 * tk
		p_shield_push += 2.5 * tk
		p_arm_h -= 10.0 * tk
		p_head -= 5.0 * tk
		p_halo += 1.0 * tk

	# ATAQUE: preparação pela recarga real (e ao chegar no alcance, como no HTML);
	# golpe no evento real de dano; retorno à guarda
	if unit.is_alive():
		p_wind = _windup_amount()
		if _strike_t >= 0.0:
			var down := clampf(_strike_t / STRIKE_DOWN, 0.0, 1.0)
			var rec := clampf((_strike_t - RECOVER_START) / (RECOVER_END - RECOVER_START), 0.0, 1.0)
			var d := _ease_out(down)
			var r := _ease_in_out(rec)
			p_arm_s = lerpf(lerpf(windup_arm, strike_arm, d), p_arm_s, r)
			sword_target = lerpf(lerpf(windup_sword, strike_sword, d), sword_target, r)
			p_lean += lerpf(lerpf(-5.0, 9.0, d), 0.0, r)
			p_offset.x += 2.2 * d * (1.0 - r)
			p_offset.y += 0.9 * d * (1.0 - r)          # impacto pesado: o corpo afunda no golpe
			p_crouch += 1.0 * d * (1.0 - r)
			_sword_follow = sword_target
		elif p_wind > 0.0:
			var wk := _ease_in_out(p_wind)
			p_arm_s = lerpf(p_arm_s, windup_arm, wk)
			sword_target = lerpf(sword_target, windup_sword, wk)
			p_lean -= 5.0 * wk
			p_offset.x -= 0.8 * wk

	# espada com inércia (acompanha o braço com atraso), exceto no golpe
	_sword_follow = lerpf(_sword_follow, sword_target, 1.0 - exp(-delta * 14.0)) if delta > 0.0 else sword_target
	p_sword = _sword_follow
	# escudo com inércia leve (pesado)
	_shield_follow = lerpf(_shield_follow, p_arm_h, 1.0 - exp(-delta * 16.0)) if delta > 0.0 else p_arm_h
	p_arm_h = _shield_follow

	# BLOQUEIO (escudo absorveu dano de verdade): o braço cede, recuo curto, clarão no escudo
	var bk := _block_t / BLOCK_TIME
	if bk > 0.0:
		p_shield_push -= 2.2 * bk
		p_arm_h += 8.0 * bk
		p_offset.x -= 0.9 * bk
		p_shield_flash = bk

	# HIT: recuo pequeno (a armadura absorve), clarão curto, cabeça recua
	var hk := _hit_t / HIT_TIME * _hit_force * 2.0
	p_offset.x -= 1.4 * hk
	p_head -= 6.0 * hk
	p_lean -= 2.0 * hk
	p_flash = clampf(hk * 0.5, 0.0, 0.5)
	p_dim = 0.0

	if _death_t >= 0.0:
		_death_pose()


## HTML: wind = 1 − cd/0,20 no alcance; e, chegando perto com a recarga pronta, 1 − gap/(2r).
func _windup_amount() -> float:
	var t := unit.target
	if t == null or not t.is_alive():
		return 0.0
	var dist := unit.position.distance_to(t.position)
	if unit.state == CombatUnit.State.ATTACKING and unit.cooldown > 0.0 and unit.cooldown < WINDUP_TIME:
		return 1.0 - unit.cooldown / WINDUP_TIME
	if unit.cooldown <= 0.0:
		var gap := dist - unit.attack_range
		if gap > 0.0 and gap < unit.radius * 2.0:
			return 1.0 - gap / (unit.radius * 2.0)
	return 0.0


## Morte pesada: os joelhos cedem, a espada escapa da mão, o escudo pesa e cai ao lado,
## e o corpo tomba de costas (acelerando), quica uma vez e fica no chão.
func _death_pose() -> void:
	var t := _death_t
	p_flash = 0.0
	p_guard = 0.0
	p_wind = 0.0
	p_shield_push = 0.0
	var buckle := _ease_out(clampf(t / 0.22, 0.0, 1.0))
	var fall := clampf((t - 0.22) / (DEATH_TIME - 0.22), 0.0, 1.0)
	fall = fall * fall
	p_crouch = 2.2 * buckle * (1.0 - fall)
	p_lean = 8.0 * buckle * (1.0 - fall) - 6.0 * fall
	p_head = 14.0 * buckle * (1.0 - fall) - 18.0 * fall
	p_leg_f = -14.0 * buckle
	p_leg_b = 10.0 * buckle
	p_arm_s = lerpf(rest_sword_arm, 120.0, fall)
	p_arm_h = lerpf(rest_shield_arm, -10.0, buckle)
	p_rot = -88.0 * fall
	if t > DEATH_TIME:
		var b := t - DEATH_TIME
		p_rot += 5.0 * sin(b * 16.0) * exp(-b * 9.0)
	p_offset = Vector2(-2.5 * fall, 0.0)
	p_cape = 26.0 * fall
	p_sword_drop = _ease_in_out(clampf((t - 0.1) / 0.45, 0.0, 1.0))
	p_shield_drop = _ease_in_out(clampf((t - 0.28) / 0.5, 0.0, 1.0))
	p_dim = 0.25 * clampf(t / (DEATH_TIME + 0.3), 0.0, 1.0)


# --- Desenho --------------------------------------------------------------------------------

func _draw() -> void:
	_draw_shadow()
	_draw_with_rim(_draw_rig)   # na Sombra: silhueta roxa por baixo do corpo
	_draw_effects()


func _root_xf() -> Transform2D:
	var k := _k()
	return Transform2D(0.0, Vector2(_facing, 1.0) * k, 0.0, Vector2(0, FOOT_Y)) \
		* Transform2D(deg_to_rad(p_rot), p_scale, 0.0, p_offset + Vector2(0, p_crouch))


func _draw_rig() -> void:
	var ground := Transform2D(0.0, Vector2(_facing, 1.0) * _k(), 0.0, Vector2(0, FOOT_Y))
	var root := _root_xf()
	var hip := root * Transform2D(0.0, HIP)
	var torso := hip * Transform2D(deg_to_rad(p_lean), Vector2.ZERO)
	var arm_s_local := _tf(SHOULDER_BACK, p_arm_s)
	var hand_s := arm_s_local * Vector2(0, ARM_LENGTH)
	var arm_h_local := _tf(SHOULDER_FRONT + Vector2(p_shield_push * 0.4, 0), p_arm_h)
	var hand_h := arm_h_local * Vector2(0, ARM_LENGTH)

	_draw_cape(torso)
	# braço da espada (lado de trás) + ombreira de trás
	_with(torso * arm_s_local)
	_draw_arm(0.8)
	_with(torso * _tf(SHOULDER_BACK, 0.0))
	_draw_pauldron(0.8)
	# pernas (joelhos dobram com p_crouch)
	var bend := p_crouch * 4.0
	_with(hip * _tf(Vector2(LEG_BACK_X, 0), p_leg_b + bend))
	_draw_leg(0.8, -bend)
	_with(hip * _tf(Vector2(LEG_FRONT_X, 0), p_leg_f - bend * 0.6))
	_draw_leg(1.0, bend * 0.6)
	# tabardo, cinto e peitoral
	_with(hip * Transform2D(deg_to_rad(p_lean * 0.4), Vector2.ZERO))
	_draw_tabard()
	_with(torso)
	_draw_torso()
	_with(torso * _tf(NECK, p_head))
	_draw_head()
	# no golpe a espada passa NA FRENTE do escudo (a lâmina fica legível)
	var sword_front := _strike_t >= 0.0 and _strike_t < RECOVER_START + 0.08
	if not sword_front:
		_draw_sword_part(torso, ground, hand_s)
	# braço do escudo, ombreira da frente e escudo (o mais à frente)
	_with(torso * arm_h_local)
	_draw_arm(1.0)
	var shield_on := torso * Transform2D(deg_to_rad(p_shield_tilt), hand_h + Vector2(2.2, -1.0) + look.shield_offset)
	if p_shield_drop > 0.0:
		# cai ao lado do corpo (atrás, em profundidade), sem cobri-lo
		var shield_ground := ground * Transform2D(deg_to_rad(-80.0), Vector2(0.7, 1.0), 0.0, Vector2(-20.0, -9.0))
		_with(shield_on.interpolate_with(shield_ground, p_shield_drop))
	else:
		_with(shield_on)
	_draw_shield()
	_with(torso * _tf(SHOULDER_FRONT, 0.0))
	_draw_pauldron(1.0)
	if sword_front:
		_draw_sword_part(torso, ground, hand_s)
	_draw_fx_front(root, torso)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Espada presa à mão (com a manopla), ou escapando dela e caindo solta ao lado do corpo.
func _draw_sword_part(torso: Transform2D, ground: Transform2D, hand_s: Vector2) -> void:
	var sword_on := torso * _tf(hand_s + look.sword_offset, p_sword)
	if p_sword_drop > 0.0:
		var sword_ground := ground * Transform2D(deg_to_rad(84.0), Vector2(-9.0, 1.6))
		var drop := sword_on.interpolate_with(sword_ground, p_sword_drop)
		drop.origin.y -= sin(p_sword_drop * PI) * 4.0 * _k()   # sai da mão num pequeno arco
		_with(drop)
	else:
		_with(sword_on)
	_draw_sword()
	if p_sword_drop <= 0.0:
		_with(torso * _tf(hand_s, 0.0))
		_draw_gauntlet(0.9)


func _draw_shadow() -> void:
	var lying := clampf(absf(p_rot) / 90.0, 0.0, 1.0)
	var shift := -14.0 * lying * _k() * _facing
	draw_set_transform(Vector2(shift, FOOT_Y), 0.0, Vector2(1.0 + lying * 1.1, 0.32))
	draw_circle(Vector2.ZERO, 12.0 * _k(), Color(0, 0, 0, 0.34))
	draw_set_transform(Vector2.ZERO)


## Capa pesada presa aos ombros; a barra reage com atraso (p_cape).
func _draw_cape(torso: Transform2D) -> void:
	_with(torso)
	var sw := -p_cape * 0.14
	var pts := PackedVector2Array([
		Vector2(1.0, -15.0), Vector2(-6.4, -14.4),
		Vector2(-12.6 + sw, 12.0), Vector2(-7.4 + sw * 0.7, 13.4), Vector2(-2.4 + sw * 0.4, 11.2),
	])
	_poly(_cape_shape(pts), _c(cape_color))
	_line(Vector2(-4.2, -13.2), Vector2(-8.4 + sw * 0.7, 12.4), _c(cape_color.darkened(0.25)), 1.0)


## Ponto de extensão: a Sombra rasga a barra.
func _cape_shape(pts: PackedVector2Array) -> PackedVector2Array:
	return pts


func _draw_leg(shade: float, knee_bend: float) -> void:
	# coxote escuro + grevas marfim, joelheira com filete dourado, sapatão
	_poly(PackedVector2Array([Vector2(-2.8, -0.5), Vector2(2.8, -0.5), Vector2(2.5, 11.2), Vector2(-2.5, 11.2)]), _c(under_armor, shade))
	_with_local(Transform2D(deg_to_rad(knee_bend), Vector2(0, 6.0)))
	_poly(PackedVector2Array([Vector2(-2.3, -1.0), Vector2(2.9, -1.6), Vector2(2.7, 5.0), Vector2(-2.2, 5.0)]), _c(ivory, shade))
	_line(Vector2(1.6, -1.2), Vector2(1.7, 4.6), _c(steel_shade, shade), 0.7)
	_poly(PackedVector2Array([Vector2(-2.9, 4.6), Vector2(2.9, 4.6), Vector2(5.8, 6.1), Vector2(5.8, 7.0), Vector2(-3.0, 7.0)]), _c(ivory, shade))
	_line(Vector2(-2.8, 4.9), Vector2(5.6, 5.9), _c(gold, shade), 0.6)
	_pop_local()
	_circle(Vector2(0.7, 5.6), 2.3, _c(ivory_light, shade))
	if not _rim_pass:
		draw_arc(Vector2(0.7, 5.6), 1.4, 0.0, TAU, 12, _c(gold, shade), 0.6, true)


var _local_stack: Array[Transform2D] = []
var _current_xf := Transform2D.IDENTITY


func _with(xf: Transform2D) -> void:
	_current_xf = xf
	draw_set_transform_matrix(xf)


func _with_local(xf: Transform2D) -> void:
	_local_stack.append(_current_xf)
	_with(_current_xf * xf)


func _pop_local() -> void:
	_with(_local_stack.pop_back())


func _draw_tabard() -> void:
	# painel de trás, cinto, painel da frente (tabardo partido, marfim com sol dourado)
	_poly(PackedVector2Array([Vector2(-5.4, -1.0), Vector2(-1.2, -1.0), Vector2(-2.0, 10.8), Vector2(-4.2, 9.6), Vector2(-6.6, 10.4)]), _c(cloth, 0.82))
	_poly(PackedVector2Array([Vector2(-6.6, -3.4), Vector2(6.6, -3.4), Vector2(6.6, -0.6), Vector2(-6.6, -0.6)]), _c(leather))
	_poly(PackedVector2Array([Vector2(1.6, -3.6), Vector2(4.2, -3.6), Vector2(4.2, -0.4), Vector2(1.6, -0.4)]), _c(gold))
	var front := _tabard_front()
	_poly(front, _c(cloth))
	if _rim_pass:
		return
	var trim := front.duplicate()
	trim.append(front[0])
	draw_polyline(trim, _c(gold), 0.7, true)
	_draw_emblem(Vector2(2.6, 5.2), 2.2)


## Painel da frente do tabardo (a Sombra rasga a barra).
func _tabard_front() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-0.6, -0.4), Vector2(5.8, -0.4), Vector2(6.2, 11.0), Vector2(2.6, 9.8), Vector2(-0.8, 11.2)])


func _draw_torso() -> void:
	# peitoral pesado: placa marfim com a metade de trás sombreada, filete dourado e crista central
	var plate := PackedVector2Array([
		Vector2(-6.6, -2.4), Vector2(6.0, -2.4), Vector2(7.6, -7.8), Vector2(7.0, -13.2),
		Vector2(3.8, -15.6), Vector2(-4.8, -15.6), Vector2(-7.2, -13.0), Vector2(-7.4, -7.0),
	])
	_poly(plate, _c(ivory))
	if _rim_pass:
		return
	draw_colored_polygon(PackedVector2Array([Vector2(-6.6, -2.4), Vector2(-1.0, -2.4), Vector2(-1.6, -15.6), Vector2(-4.8, -15.6), Vector2(-7.2, -13.0), Vector2(-7.4, -7.0)]), _c(steel_shade, 0.95))
	draw_polyline(PackedVector2Array([Vector2(-6.6, -2.4), Vector2(6.0, -2.4), Vector2(7.6, -7.8)]), _c(gold), 0.9, true)
	_line(Vector2(3.2, -15.0), Vector2(4.4, -3.0), _c(steel_shade), 0.8)
	draw_colored_polygon(PackedVector2Array([Vector2(4.6, -13.2), Vector2(6.4, -12.4), Vector2(6.6, -9.0), Vector2(5.0, -9.6)]), _c(ivory_light))
	# gola / gorjal
	_poly(PackedVector2Array([Vector2(-3.4, -15.2), Vector2(4.2, -15.2), Vector2(4.8, -17.0), Vector2(-3.6, -17.0)]), _c(under_armor))
	_line(Vector2(-3.6, -15.3), Vector2(4.6, -15.3), _c(gold), 0.8)
	_draw_torso_wear()


## Ponto de extensão: fissuras de energia da Sombra.
func _draw_torso_wear() -> void:
	pass


func _draw_head() -> void:
	# origem no pescoço; a auréola fica atrás do elmo
	if not _rim_pass:
		_draw_halo()
	var helm := PackedVector2Array([
		Vector2(-5.4, -0.6), Vector2(6.0, -0.6), Vector2(6.6, -5.2), Vector2(6.2, -9.2), Vector2(4.2, -12.2),
		Vector2(0.0, -13.2), Vector2(-4.0, -12.4), Vector2(-6.0, -9.2), Vector2(-6.2, -4.2),
	])
	# crista dourada no topo
	_poly(PackedVector2Array([Vector2(-0.8, -12.6), Vector2(0.6, -17.2), Vector2(1.8, -12.8)]), _c(gold))
	_poly(helm, _c(ivory))
	if _rim_pass:
		return
	draw_colored_polygon(PackedVector2Array([Vector2(-5.4, -0.6), Vector2(-1.2, -0.6), Vector2(-1.6, -12.9), Vector2(-4.0, -12.4), Vector2(-6.0, -9.2), Vector2(-6.2, -4.2)]), _c(steel_shade, 0.95))
	_poly(PackedVector2Array([Vector2(-5.4, -0.6), Vector2(6.0, -0.6), Vector2(6.2, -2.4), Vector2(-5.6, -2.4)]), _c(gold))
	# filete dourado no meio da face (a "cruz" do elmo)
	draw_colored_polygon(PackedVector2Array([Vector2(3.0, -12.6), Vector2(4.2, -12.2), Vector2(4.6, -7.8), Vector2(3.4, -7.8)]), _c(gold))
	draw_colored_polygon(PackedVector2Array([Vector2(1.4, -12.0), Vector2(2.4, -12.6), Vector2(2.2, -9.0), Vector2(1.4, -9.4)]), _c(ivory_light))
	_draw_visor()


## Visor estreito em T (a Sombra acende os olhos).
func _draw_visor() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(1.4, -7.4), Vector2(6.6, -7.7), Vector2(6.6, -6.4), Vector2(1.4, -6.2)]), _c(visor))
	draw_colored_polygon(PackedVector2Array([Vector2(3.6, -6.4), Vector2(4.6, -6.4), Vector2(4.8, -3.0), Vector2(3.8, -3.0)]), _c(visor))


## Auréola dourada atrás do elmo, com estrelas (leitura sagrada de longe).
func _draw_halo() -> void:
	var glow := (look.glow if look else 1.0)
	var c := Vector2(-0.4, -7.6)
	var col := _c(gold)
	var lift := 0.08 * sin(_time * 1.3 * (look.secondary_speed if look else 1.0))
	var shine := clampf(0.12 + 0.3 * p_halo + lift, 0.0, 1.0) * glow * (1.0 - p_dim * 3.0)
	if shine > 0.0:
		draw_arc(c, 8.4, PI * 0.84, PI * 2.16, 24, Color(holy, 0.35 * shine), 3.2, true)
	draw_arc(c, 8.0, PI * 0.84, PI * 2.16, 24, _c(outline), 2.1, true)
	draw_arc(c, 8.0, PI * 0.84, PI * 2.16, 24, col, 1.25, true)
	_star(c + Vector2(0, -8.0), 2.6, _c(gold_light))
	_star(c + Vector2(-8.0 * 0.95, -1.6), 1.5, col)
	_star(c + Vector2(8.0 * 0.95, -1.6), 1.5, col)


func _draw_pauldron(shade: float) -> void:
	# ombreira pesada em duas lâminas sobrepostas, borda dourada e rebite (fica NA borda do ombro)
	var top := PackedVector2Array()
	for i in 11:
		var a := lerpf(PI * 1.05, PI * 1.95, i / 10.0)
		top.append(Vector2(cos(a) * 4.8, sin(a) * 3.6 + 0.8))
	top.append(Vector2(4.4, 2.2))
	top.append(Vector2(-4.6, 2.2))
	var lame := PackedVector2Array([Vector2(-4.4, 1.4), Vector2(4.2, 1.4), Vector2(3.8, 4.4), Vector2(-4.0, 4.4)])
	_poly(lame, _c(ivory, shade * 0.92))
	_poly(top, _c(ivory, shade))
	if _rim_pass:
		return
	_line(Vector2(-4.2, 4.0), Vector2(3.8, 4.0), _c(gold, shade), 0.8)
	var rim := PackedVector2Array()
	for i in 11:
		var a := lerpf(PI * 1.08, PI * 1.92, i / 10.0)
		rim.append(Vector2(cos(a) * 4.1, sin(a) * 2.9 + 1.4))
	draw_polyline(rim, _c(gold, shade), 0.9, true)
	draw_circle(Vector2(0.4, -1.2), 0.8, _c(gold_light, shade))


func _draw_arm(shade: float) -> void:
	# braço blindado; pivô no ombro, mão em (0, ARM_LENGTH)
	_poly(PackedVector2Array([Vector2(-2.1, 0.0), Vector2(2.1, 0.0), Vector2(1.9, 9.2), Vector2(-1.9, 9.2)]), _c(under_armor, shade))
	_poly(PackedVector2Array([Vector2(-2.3, 4.6), Vector2(2.3, 4.6), Vector2(2.1, 9.2), Vector2(-2.1, 9.2)]), _c(ivory, shade))
	_line(Vector2(-2.2, 4.8), Vector2(2.2, 4.8), _c(gold, shade), 0.6)


func _draw_gauntlet(shade: float) -> void:
	_circle(Vector2.ZERO, 2.3, _c(under_armor.lightened(0.1), shade))


func _draw_sword() -> void:
	# origem na mão; lâmina para −y. Punho, pomo e guarda dourados.
	_poly(PackedVector2Array([Vector2(-0.75, -0.8), Vector2(0.75, -0.8), Vector2(0.75, 3.6), Vector2(-0.75, 3.6)]), _c(leather))
	_circle(Vector2(0, 4.4), 1.3, _c(gold))
	_poly(_blade_shape(), _c(blade))
	_poly(PackedVector2Array([Vector2(-4.0, -2.6), Vector2(-1.0, -2.2), Vector2(1.0, -2.2), Vector2(4.0, -2.6), Vector2(3.6, -0.8), Vector2(-3.6, -0.8)]), _c(gold))
	if _rim_pass:
		return
	_line(Vector2(0, -3.0), Vector2(0, -15.0), _c(blade.darkened(0.3)), 0.6)
	_draw_blade_extra()


func _blade_shape() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-1.4, -2.2), Vector2(1.4, -2.2), Vector2(1.25, -15.4), Vector2(0.0, -SWORD_LENGTH), Vector2(-1.25, -15.4)])


## Ponto de extensão: a Sombra acende o fio.
func _draw_blade_extra() -> void:
	pass


func _draw_shield() -> void:
	# escudo heráldico grande, visto em 3/4 (um pouco estreitado), com o sol no centro
	var pts := _shield_points()
	_poly(pts, _c(ivory))
	if _rim_pass:
		return
	# metade sombreada, borda dourada, sol
	draw_colored_polygon(PackedVector2Array([Vector2(0, -10.4), Vector2(-5.2, -9.1), Vector2(-5.1, 1.4), Vector2(-3.5, 7.2), Vector2(0, 11.6)]), _c(steel_shade, 1.02))
	var rim := pts.duplicate()
	rim.append(pts[0])
	draw_polyline(rim, _c(gold), 1.3, true)
	_draw_emblem(Vector2(0.2, -0.8), 4.4)
	_draw_shield_wear()
	if p_shield_flash > 0.0:
		draw_colored_polygon(pts, Color(holy, 0.55 * p_shield_flash * (look.glow if look else 1.0)))


func _shield_points() -> PackedVector2Array:
	var w := 5.4
	return PackedVector2Array([
		Vector2(0, -10.6), Vector2(w, -9.2), Vector2(w * 0.97, 1.4), Vector2(w * 0.66, 7.2),
		Vector2(0, 11.8), Vector2(-w * 0.66, 7.2), Vector2(-w * 0.97, 1.4), Vector2(-w, -9.2),
	])


## Ponto de extensão: fissuras roxas no escudo da Sombra.
func _draw_shield_wear() -> void:
	pass


## Sol sagrado: disco + estrela de oito pontas (tabardo e escudo).
func _draw_emblem(c: Vector2, size: float) -> void:
	var col := _c(emblem)
	_star(c, size, col)
	_star(c, size * 0.62, col, PI / 4.0)
	draw_arc(c, size * 0.42, 0.0, TAU, 14, col, 0.7, true)


func _star(c: Vector2, s: float, col: Color, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := rot + i * TAU / 8.0 - PI / 2.0
		var r := s if i % 2 == 0 else s * 0.3
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)


## Ponto de extensão: efeitos por cima do corpo (Sombra: fumaça).
func _draw_fx_front(_root: Transform2D, _torso: Transform2D) -> void:
	pass


# --- Efeitos (espaço do UnitView, sem espelhar) ---------------------------------------------

func _draw_effects() -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var glow := look.glow if look else 1.0
	# rastro do golpe: arco da ponta da espada, do alto até a posição atual
	if _strike_t >= 0.0 and _strike_t < 0.26 and unit.is_alive():
		var d := _ease_out(clampf(_strike_t / STRIKE_DOWN, 0.0, 1.0))
		var fade := 1.0 - clampf((_strike_t - STRIKE_DOWN) / 0.14, 0.0, 1.0)
		var pts := PackedVector2Array()
		var n := 10
		for i in n + 1:
			var u := d * float(i) / n
			pts.append(_sword_tip(lerpf(windup_arm, strike_arm, u), lerpf(windup_sword, strike_sword, u)))
		var trail := _trail_color()
		draw_polyline(pts, Color(trail, 0.22 * fade * glow), 5.0, true)
		draw_polyline(pts, Color(trail, 0.7 * fade * glow), 1.6, true)
		draw_polyline(pts, Color(_trail_core(), 0.85 * fade * glow), 0.6, true)
	var pal := unit.paladin
	# barreira sagrada, anel da provocação (raio real de 115) e anel do escudo: PaladinFx
	if pal and unit.is_alive() and pal.is_shielded():
		PaladinFx.barrier(self, pal, unit.radius, _barrier_age, glow, _barrier_fill(), holy_edge, Vector2(_facing, 0))
	if look == null or look.show_taunt_ring:
		PaladinFx.taunt_ring(self, _taunt_t, glow, _ring_color())
	PaladinFx.shield_ring(self, _shield_ring_t, unit.radius, glow, _ring_color())


## Ponta da espada (espaço do UnitView) para um ângulo de braço e de espada.
func _sword_tip(arm_deg: float, sword_deg: float) -> Vector2:
	var root := _root_xf()
	var torso := root * Transform2D(0.0, HIP) * Transform2D(deg_to_rad(p_lean), Vector2.ZERO)
	var hand := _tf(SHOULDER_BACK, arm_deg) * Vector2(0, ARM_LENGTH)
	return torso * (_tf(hand, sword_deg) * Vector2(0, -SWORD_LENGTH))


func _trail_color() -> Color:
	return gold_light


func _trail_core() -> Color:
	return Color("fffbe8")


func _ring_color() -> Color:
	return Color("f0c674")


func _barrier_fill() -> Color:
	return Color(1.0, 0.82, 0.35)
