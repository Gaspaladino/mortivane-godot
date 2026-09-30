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
	_bake_rig()
	_pose_bones()


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


func death_elapsed() -> float:
	return _death_t


## Queda em DEATH_TIME, quique amortecido e escurecimento em DEATH_TIME + 0,3. A Sombra dissolve até 2,6 s.
func corpse_settle_time() -> float:
	return 2.8


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
	_pose_bones()


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


# --- Desenho leve: peças prontas + ossos -----------------------------------------------------
## Corpo, escudo, espada e efeitos da habilidade são UMA malha estática por tipo (LiteSkin), um osso
## por peça; a pose do quadro só move os ossos. Espada e manopla existem em duas camadas (atrás e na
## frente do escudo) e a que não está em uso fica escondida. Efeitos com transparência animada
## (rastro, barreira, anéis) aparecem/somem por escala. Ver CodeDrawnUnitVisual (_part, _skin_setup).

enum {
	P_CAPE, P_ARM_S, P_PAULDRON_B, P_THIGH_B, P_SHIN_B, P_THIGH_F, P_SHIN_F, P_TABARD, P_TORSO,
	P_HALO_SHINE, P_HEAD, P_SWORD_B, P_GAUNTLET_B, P_ARM_H, P_SHIELD, P_SHIELD_FLASH, P_PAULDRON_F,
	P_SWORD_F, P_GAUNTLET_F, B_GROUND, B_TRAIL,
}
const TRAIL_SEGS := 10
const B_BARRIER := B_TRAIL + TRAIL_SEGS
const B_TAUNT_RING := B_BARRIER + 1
const B_SHIELD_RING := B_BARRIER + 2
const B_EXTRA := B_BARRIER + 3
## Raio de montagem do anel do escudo (≈ o raio típico: a escala fica perto de 1 e a linha, fina).
const SHIELD_RING_R := 25.0


func _bake_rig() -> void:
	var rim := shadow_style != null and shadow_style.rim_width > 0.0
	var body: Array = [
		["cape", _draw_cape_part, P_CAPE], ["arm_s", _draw_arm.bind(0.8), P_ARM_S], ["pauldron_b", _draw_pauldron.bind(0.8), P_PAULDRON_B],
		["thigh_b", _draw_thigh.bind(0.8), P_THIGH_B], ["shin_b", _draw_shin.bind(0.8), P_SHIN_B], ["knee_b", _draw_knee.bind(0.8), P_THIGH_B],
		["thigh_f", _draw_thigh.bind(1.0), P_THIGH_F], ["shin_f", _draw_shin.bind(1.0), P_SHIN_F], ["knee_f", _draw_knee.bind(1.0), P_THIGH_F],
		["tabard", _draw_tabard, P_TABARD], ["torso", _draw_torso, P_TORSO],
	]
	var layout: Array = _layout_back()
	if rim:
		for e in body + [["head", _draw_head, P_HEAD], ["sword", _draw_sword, P_SWORD_B], ["gauntlet", _draw_gauntlet.bind(0.9), P_GAUNTLET_B],
				["arm_h", _draw_arm.bind(1.0), P_ARM_H], ["shield", _draw_shield, P_SHIELD], ["pauldron_f", _draw_pauldron.bind(1.0), P_PAULDRON_F],
				["sword", _draw_sword, P_SWORD_F], ["gauntlet", _draw_gauntlet.bind(0.9), P_GAUNTLET_F]]:
			layout.append([_part(e[0], e[1], true), e[2]])
	for e in body:
		layout.append([_part(e[0], e[1]), e[2]])
	layout.append([_part("halo_shine", _draw_halo_shine, false, false), P_HALO_SHINE])
	layout.append([_part("head", _draw_head), P_HEAD])
	layout.append([_part("sword", _draw_sword), P_SWORD_B])
	layout.append([_part("gauntlet", _draw_gauntlet.bind(0.9)), P_GAUNTLET_B])
	layout.append([_part("arm_h", _draw_arm.bind(1.0)), P_ARM_H])
	layout.append([_part("shield", _draw_shield), P_SHIELD])
	layout.append([_part("shield_flash", func(): _fill(_shield_points(), Color(holy, 0.4 * (look.glow if look else 1.0)))), P_SHIELD_FLASH])
	layout.append([_part("pauldron_f", _draw_pauldron.bind(1.0)), P_PAULDRON_F])
	layout.append([_part("sword", _draw_sword), P_SWORD_F])
	layout.append([_part("gauntlet", _draw_gauntlet.bind(0.9)), P_GAUNTLET_F])
	layout.append_array(_layout_front())
	# efeitos da habilidade (espaço do UnitView)
	var glow := look.glow if look else 1.0
	var trail := _part("trail", func():
		_bake.line(Vector2.ZERO, Vector2(1, 0), Color(_trail_color(), 0.22 * glow), 5.0)
		_bake.line(Vector2.ZERO, Vector2(1, 0), Color(_trail_color(), 0.7 * glow), 1.6)
		_bake.line(Vector2.ZERO, Vector2(1, 0), Color(_trail_core(), 0.85 * glow), 0.6), false, false)
	for i in TRAIL_SEGS:
		layout.append([trail, B_TRAIL + i])
	layout.append([_part("barrier", _draw_barrier_shape, false, false), B_BARRIER])
	layout.append([_part("taunt_ring", func():
		_bake.arc(Vector2.ZERO, PaladinTaunt.TAUNT_RADIUS, 0.0, TAU, 64, Color(_ring_color(), 0.4 * glow), 1.6), false, false), B_TAUNT_RING])
	layout.append([_part("shield_ring", func():
		_bake.arc(Vector2.ZERO, SHIELD_RING_R, 0.0, TAU, 40, Color(_ring_color(), 0.7 * glow), 1.4), false, false), B_SHIELD_RING])
	_skin_setup(layout, B_EXTRA + _extra_bones())


## Pontos de extensão da malha (a Sombra: névoa, aura, fumaça).
func _layout_back() -> Array:
	return [[_part("ground", func(): _disc(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.34)), false, false), B_GROUND]]


func _layout_front() -> Array:
	return []


func _extra_bones() -> int:
	return 0


func _draw() -> void:
	_skin_draw()


func _root_xf() -> Transform2D:
	var k := _k()
	return Transform2D(0.0, Vector2(_facing, 1.0) * k, 0.0, Vector2(0, FOOT_Y)) \
		* Transform2D(deg_to_rad(p_rot), p_scale, 0.0, p_offset + Vector2(0, p_crouch))


func _pose_bones() -> void:
	if _skin == null:
		return
	var sk := _skin
	var ground := Transform2D(0.0, Vector2(_facing, 1.0) * _k(), 0.0, Vector2(0, FOOT_Y))
	var root := _root_xf()
	var hip := root * Transform2D(0.0, HIP)
	var torso := hip * Transform2D(deg_to_rad(p_lean), Vector2.ZERO)
	var arm_s_local := _tf(SHOULDER_BACK, p_arm_s)
	var hand_s := arm_s_local * Vector2(0, ARM_LENGTH)
	var arm_h_local := _tf(SHOULDER_FRONT + Vector2(p_shield_push * 0.4, 0), p_arm_h)
	var hand_h := arm_h_local * Vector2(0, ARM_LENGTH)
	# capa: peça pronta inclinada pelo balanço da barra
	var ck := -p_cape * 0.14 / 27.0
	sk.set_bone(P_CAPE, torso * Transform2D(Vector2(1, 0), Vector2(ck, 1), Vector2(ck * 15.0, 0)))
	sk.set_bone(P_ARM_S, torso * arm_s_local)
	sk.set_bone(P_PAULDRON_B, torso * _tf(SHOULDER_BACK, 0.0))
	var bend := p_crouch * 4.0
	var leg_b := hip * _tf(Vector2(LEG_BACK_X, 0), p_leg_b + bend)
	var leg_f := hip * _tf(Vector2(LEG_FRONT_X, 0), p_leg_f - bend * 0.6)
	sk.set_bone(P_THIGH_B, leg_b)
	sk.set_bone(P_SHIN_B, leg_b * Transform2D(deg_to_rad(-bend), Vector2(0, 6.0)))
	sk.set_bone(P_THIGH_F, leg_f)
	sk.set_bone(P_SHIN_F, leg_f * Transform2D(deg_to_rad(bend * 0.6), Vector2(0, 6.0)))
	sk.set_bone(P_TABARD, hip * Transform2D(deg_to_rad(p_lean * 0.4), Vector2.ZERO))
	sk.set_bone(P_TORSO, torso)
	var head := torso * _tf(NECK, p_head)
	sk.set_bone(P_HEAD, head)
	var glow := look.glow if look else 1.0
	var shine := clampf(0.12 + 0.3 * p_halo + 0.08 * sin(_time * 1.3 * (look.secondary_speed if look else 1.0)), 0.0, 1.0) * glow * (1.0 - p_dim * 3.0)
	sk.set_bone(P_HALO_SHINE, head if shine > 0.15 else LiteSkin.HIDDEN)
	# no golpe a espada passa NA FRENTE do escudo (a lâmina fica legível)
	var sword_front := _strike_t >= 0.0 and _strike_t < RECOVER_START + 0.08
	var sword_on := torso * _tf(hand_s + look.sword_offset, p_sword)
	if p_sword_drop > 0.0:
		var sword_ground := ground * Transform2D(deg_to_rad(84.0), Vector2(-9.0, 1.6))
		sword_on = sword_on.interpolate_with(sword_ground, p_sword_drop)
		sword_on.origin.y -= sin(p_sword_drop * PI) * 4.0 * _k()   # sai da mão num pequeno arco
	var gauntlet := torso * _tf(hand_s, 0.0) if p_sword_drop <= 0.0 else LiteSkin.HIDDEN
	sk.set_bone(P_SWORD_B, LiteSkin.HIDDEN if sword_front else sword_on)
	sk.set_bone(P_GAUNTLET_B, LiteSkin.HIDDEN if sword_front else gauntlet)
	sk.set_bone(P_SWORD_F, sword_on if sword_front else LiteSkin.HIDDEN)
	sk.set_bone(P_GAUNTLET_F, gauntlet if sword_front else LiteSkin.HIDDEN)
	sk.set_bone(P_ARM_H, torso * arm_h_local)
	var shield_on := torso * Transform2D(deg_to_rad(p_shield_tilt), hand_h + Vector2(2.2, -1.0) + look.shield_offset)
	if p_shield_drop > 0.0:
		var shield_ground := ground * Transform2D(deg_to_rad(-80.0), Vector2(0.7, 1.0), 0.0, Vector2(-20.0, -9.0))
		shield_on = shield_on.interpolate_with(shield_ground, p_shield_drop)
	sk.set_bone(P_SHIELD, shield_on)
	sk.set_bone(P_SHIELD_FLASH, shield_on if p_shield_flash > 0.15 else LiteSkin.HIDDEN)
	sk.set_bone(P_PAULDRON_F, torso * _tf(SHOULDER_FRONT, 0.0))
	_pose_ground()
	_pose_effects()
	_pose_extra(root, torso)
	_apply_fx()


func _pose_ground() -> void:
	var lying := clampf(absf(p_rot) / 90.0, 0.0, 1.0)
	var shift := -14.0 * lying * _k() * _facing
	_skin.set_bone(B_GROUND, Transform2D(0.0, Vector2((1.0 + lying * 1.1) * _k(), 0.32 * _k()), 0.0, Vector2(shift, FOOT_Y)))


## Ponto de extensão: ossos extras da variante (a Sombra: névoa, aura, fumaça).
func _pose_extra(_root: Transform2D, _torso: Transform2D) -> void:
	pass


## Efeitos (espaço do UnitView, sem espelhar): rastro do golpe, barreira, anéis.
func _pose_effects() -> void:
	# rastro do golpe: arco da ponta da espada, do alto até a posição atual
	if _strike_t >= 0.0 and _strike_t < 0.26 and unit.is_alive():
		var d := _ease_out(clampf(_strike_t / STRIKE_DOWN, 0.0, 1.0))
		var fade := 1.0 - clampf((_strike_t - STRIKE_DOWN) / 0.14, 0.0, 1.0)
		var prev := _sword_tip(windup_arm, windup_sword)
		for i in TRAIL_SEGS:
			var u := d * float(i + 1) / TRAIL_SEGS
			var p := _sword_tip(lerpf(windup_arm, strike_arm, u), lerpf(windup_sword, strike_sword, u))
			_skin.set_bone(B_TRAIL + i, _seg_bone(prev, p, fade) if fade > 0.05 else LiteSkin.HIDDEN)
			prev = p
	else:
		for i in TRAIL_SEGS:
			_skin.hide_bone(B_TRAIL + i)
	# barreira sagrada à frente, na direção travada
	var pal := unit.paladin
	if pal and unit.is_alive() and pal.is_shielded():
		var f := pal.facing if pal.facing != Vector2.ZERO else Vector2(_facing, 0)
		var r := unit.radius
		var pos := Vector2(f.x * r * PaladinFx.BARRIER_FORWARD, r * PaladinFx.BARRIER_VERTICAL + f.y * r * PaladinFx.BARRIER_FORWARD)
		var ez := 1.0 - pow(1.0 - clampf(_barrier_age / PaladinFx.BARRIER_ENTER, 0.0, 1.0), 3.0)
		var fade := clampf(pal.shield_t / PaladinFx.BARRIER_EXIT, 0.0, 1.0)
		var s := (0.7 + 0.3 * ez) * (0.5 + 0.5 * fade) * r / 14.0
		_skin.set_bone(B_BARRIER, Transform2D(0.0, Vector2(s, s), 0.0, pos) if ez * fade > 0.05 else LiteSkin.HIDDEN)
	else:
		_skin.hide_bone(B_BARRIER)
	# anel no raio real da provocação (abre e some) e anel curto do escudo
	if (look == null or look.show_taunt_ring) and _taunt_t >= 0.0 and _taunt_t <= TAUNT_RING_TIME:
		var k := clampf(_taunt_t / TAUNT_RING_TIME, 0.0, 1.0)
		var tr := lerpf(0.35, 1.0, 1.0 - (1.0 - k) * (1.0 - k)) * (1.0 if k < 0.9 else 0.0)
		_skin.set_bone(B_TAUNT_RING, Transform2D(0.0, Vector2(tr, tr), 0.0, Vector2.ZERO))
	else:
		_skin.hide_bone(B_TAUNT_RING)
	if _shield_ring_t >= 0.0 and _shield_ring_t <= SHIELD_RING_TIME:
		var k := clampf(_shield_ring_t / SHIELD_RING_TIME, 0.0, 1.0)
		var sr := unit.radius * 1.8 * lerpf(0.6, 1.0, k) / SHIELD_RING_R * (1.0 if k < 0.9 else 0.0)
		_skin.set_bone(B_SHIELD_RING, Transform2D(0.0, Vector2(sr, sr), 0.0, Vector2(0, -6)))
	else:
		_skin.hide_bone(B_SHIELD_RING)


## Escudo Sagrado (HTML: holyShieldPath) no raio de referência 14, na opacidade máxima.
func _draw_barrier_shape() -> void:
	var glow := look.glow if look else 1.0
	var w := 14.0 * PaladinFx.BARRIER_WIDTH
	var h := 14.0 * PaladinFx.BARRIER_HEIGHT
	var path := PackedVector2Array()
	for i in 9:
		var u := i / 8.0
		path.append(Vector2(lerpf(0.0, w * 0.5, u), lerpf(-h * 0.5, -h * 0.38, u * u)))
	for i in 7:
		var u := i / 6.0
		path.append(Vector2(lerpf(w * 0.47, 0.0, u * u), lerpf(h * 0.0, h * 0.5, u)))
	var n := path.size()
	for i in range(n - 2, 0, -1):
		path.append(Vector2(-path[i].x, path[i].y))
	var a := 0.88 * glow
	_bake.fill(path, Color(_barrier_fill(), 0.13 * a))
	_bake.outline(path, Color(holy_edge, 0.9 * a), 1.8)
	var pts := PackedVector2Array()
	for i in 8:
		var ang := i * TAU / 8.0 - PI / 2.0
		var rr := h * 0.16 if i % 2 == 0 else h * 0.16 * 0.3
		pts.append(Vector2(0, -h * 0.05) + Vector2(cos(ang), sin(ang)) * rr)
	_bake.fill(pts, Color(holy_edge, 0.55 * a))


## Capa pesada presa aos ombros (peça pronta no espaço do tronco; a barra balança por inclinação).
func _draw_cape_part() -> void:
	var pts := PackedVector2Array([
		Vector2(1.0, -15.0), Vector2(-6.4, -14.4),
		Vector2(-12.6, 12.0), Vector2(-7.4, 13.4), Vector2(-2.4, 11.2),
	])
	_poly(_cape_shape(pts), _c(cape_color))
	_line(Vector2(-4.2, -13.2), Vector2(-8.4, 12.4), _c(cape_color.darkened(0.25)), 1.0)
	_draw_cape_extra(_cape_shape(pts))


## Ponto de extensão: detalhe na barra da capa (a Sombra: fio de energia).
func _draw_cape_extra(_shape: PackedVector2Array) -> void:
	pass


## Ponto de extensão: a Sombra rasga a barra.
func _cape_shape(pts: PackedVector2Array) -> PackedVector2Array:
	return pts


## Coxa (coxote escuro), no espaço da perna; a canela é outra peça (o joelho dobra).
func _draw_thigh(shade: float) -> void:
	_poly(PackedVector2Array([Vector2(-2.8, -0.5), Vector2(2.8, -0.5), Vector2(2.5, 11.2), Vector2(-2.5, 11.2)]), _c(under_armor, shade))


## Canela e sapatão (grevas marfim, filete dourado), no espaço do joelho.
func _draw_shin(shade: float) -> void:
	_poly(PackedVector2Array([Vector2(-2.3, -1.0), Vector2(2.9, -1.6), Vector2(2.7, 5.0), Vector2(-2.2, 5.0)]), _c(ivory, shade))
	_line(Vector2(1.6, -1.2), Vector2(1.7, 4.6), _c(steel_shade, shade), 0.7)
	_poly(PackedVector2Array([Vector2(-2.9, 4.6), Vector2(2.9, 4.6), Vector2(5.8, 6.1), Vector2(5.8, 7.0), Vector2(-3.0, 7.0)]), _c(ivory, shade))
	_line(Vector2(-2.8, 4.9), Vector2(5.6, 5.9), _c(gold, shade), 0.6)


## Joelheira (no espaço da perna, por cima da canela).
func _draw_knee(shade: float) -> void:
	_circle(Vector2(0.7, 5.6), 2.3, _c(ivory_light, shade))
	_arc_line(Vector2(0.7, 5.6), 1.4, 0.0, TAU, 12, _c(gold, shade), 0.6)


var _current_xf := Transform2D.IDENTITY


func _with(xf: Transform2D) -> void:
	_current_xf = xf
	super(xf)


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
	_pline(trim, _c(gold), 0.7)
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
	_fill(PackedVector2Array([Vector2(-6.6, -2.4), Vector2(-1.0, -2.4), Vector2(-1.6, -15.6), Vector2(-4.8, -15.6), Vector2(-7.2, -13.0), Vector2(-7.4, -7.0)]), _c(steel_shade, 0.95))
	_pline(PackedVector2Array([Vector2(-6.6, -2.4), Vector2(6.0, -2.4), Vector2(7.6, -7.8)]), _c(gold), 0.9)
	_line(Vector2(3.2, -15.0), Vector2(4.4, -3.0), _c(steel_shade), 0.8)
	_fill(PackedVector2Array([Vector2(4.6, -13.2), Vector2(6.4, -12.4), Vector2(6.6, -9.0), Vector2(5.0, -9.6)]), _c(ivory_light))
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
	_fill(PackedVector2Array([Vector2(-5.4, -0.6), Vector2(-1.2, -0.6), Vector2(-1.6, -12.9), Vector2(-4.0, -12.4), Vector2(-6.0, -9.2), Vector2(-6.2, -4.2)]), _c(steel_shade, 0.95))
	_poly(PackedVector2Array([Vector2(-5.4, -0.6), Vector2(6.0, -0.6), Vector2(6.2, -2.4), Vector2(-5.6, -2.4)]), _c(gold))
	# filete dourado no meio da face (a "cruz" do elmo)
	_fill(PackedVector2Array([Vector2(3.0, -12.6), Vector2(4.2, -12.2), Vector2(4.6, -7.8), Vector2(3.4, -7.8)]), _c(gold))
	_fill(PackedVector2Array([Vector2(1.4, -12.0), Vector2(2.4, -12.6), Vector2(2.2, -9.0), Vector2(1.4, -9.4)]), _c(ivory_light))
	_draw_visor()


## Visor estreito em T (a Sombra acende os olhos).
func _draw_visor() -> void:
	_fill(PackedVector2Array([Vector2(1.4, -7.4), Vector2(6.6, -7.7), Vector2(6.6, -6.4), Vector2(1.4, -6.2)]), _c(visor))
	_fill(PackedVector2Array([Vector2(3.6, -6.4), Vector2(4.6, -6.4), Vector2(4.8, -3.0), Vector2(3.8, -3.0)]), _c(visor))


## Brilho da auréola (peça à parte: aparece quando a auréola brilha).
func _draw_halo_shine() -> void:
	_arc_line(Vector2(-0.4, -7.6), 8.4, PI * 0.84, PI * 2.16, 24, Color(holy, 0.35 * 0.35 * (look.glow if look else 1.0)), 3.2)


## Auréola dourada atrás do elmo, com estrelas (leitura sagrada de longe).
func _draw_halo() -> void:
	var c := Vector2(-0.4, -7.6)
	var col := _c(gold)
	_arc_line(c, 8.0, PI * 0.84, PI * 2.16, 24, _c(outline), 2.1)
	_arc_line(c, 8.0, PI * 0.84, PI * 2.16, 24, col, 1.25)
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
	_pline(rim, _c(gold, shade), 0.9)
	_disc(Vector2(0.4, -1.2), 0.8, _c(gold_light, shade))


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
	_fill(PackedVector2Array([Vector2(0, -10.4), Vector2(-5.2, -9.1), Vector2(-5.1, 1.4), Vector2(-3.5, 7.2), Vector2(0, 11.6)]), _c(steel_shade, 1.02))
	var rim := pts.duplicate()
	rim.append(pts[0])
	_pline(rim, _c(gold), 1.3)
	_draw_emblem(Vector2(0.2, -0.8), 4.4)
	_draw_shield_wear()


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
	_arc_line(c, size * 0.42, 0.0, TAU, 14, col, 0.7)


func _star(c: Vector2, s: float, col: Color, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := rot + i * TAU / 8.0 - PI / 2.0
		var r := s if i % 2 == 0 else s * 0.3
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	_fill(pts, col)


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
