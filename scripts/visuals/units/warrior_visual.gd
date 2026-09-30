class_name WarriorVisual
extends CodeDrawnUnitVisual
## Guerreiro desenhado 100% por código (sem PNG, SVG nem sprite sheet).
##
## Rig: cada parte é um conjunto de polígonos no SEU espaço local, posicionado por uma
## cadeia de Transform2D (raiz → quadril → tronco → cabeça/ombros → braço → mão → espada).
## Uma "pose" (ângulos e deslocamentos) é recalculada a cada quadro a partir do estado real
## da CombatUnit; _draw() só aplica a pose. Nada aqui altera a simulação.
##
## Espaço do rig: origem no chão entre os pés, personagem virado para a DIREITA (+x),
## y para baixo. A direção real vem de `_facing` (espelha no eixo x).
##
## Ordem de desenho (de trás para frente):
##   sombra · capa · braço de trás · perna de trás · perna da frente · saiote/cinto · tronco
##   · cabeça (elmo, fenda, pluma) · espada · braço da frente + ombreira + mão
##
## O Guerreiro Sombra (ShadowWarriorVisual) herda este rig: converte a paleta pelo
## ShadowStyle e acrescenta os efeitos necromânticos pelos pontos de extensão.
##
## Desenho LEVE: cada parte (perna, braço, tronco, elmo, espada…) é uma peça pronta, montada UMA vez
## por tipo de unidade a partir das funções _draw_* abaixo, e todas formam a MALHA estática do tipo
## (LiteSkin), com um osso por parte. A cada quadro a pose só move os ossos: nada é redesenhado nem
## reenviado, e o corpo é 1 draw call (ver CodeDrawnUnitVisual: _part, _skin_setup).

# --- Geometria do rig (unidades do rig; RIG_SCALE converte para o mundo) ----------------
const RIG_SCALE := 0.9
## Os pés ficam este tanto abaixo do centro lógico da CombatUnit.
const FOOT_Y := 9.0
const HIP := Vector2(0, -12)            # quadril, no espaço da raiz
const LEG_FRONT_X := 1.6
const LEG_BACK_X := -1.8
const NECK := Vector2(0.6, -12.6)       # no espaço do tronco (origem no quadril)
const SHOULDER_FRONT := Vector2(1.2, -10.6)
const SHOULDER_BACK := Vector2(-2.2, -10.8)
const ARM_LENGTH := 9.0
const HIT_TIME := 0.16

# --- Paleta (a Sombra converte em _apply_shadow_style) -----------------------------------------
var metal := Color("b8bfc9")
var metal_dark := Color("6c7481")
var metal_light := Color("e6ebf1")
var cloth := Color("7d1e20")
var cloth_dark := Color("4a1113")
var plume := Color("c0352c")
var leather := Color("5c3c27")
var blade := Color("dde3ea")
var visor := Color("111116")
var visor_glow := Color(0, 0, 0, 0)     # transparente = sem brilho

# --- Estilo de animação (a Sombra sobrescreve em _init) -----------------------------
var idle_bob := 0.45            # amplitude da respiração (unidades do rig)
var idle_speed := 2.0           # rad/s
var posture_lean := 0.0         # graus; + = tronco para frente
var head_tilt := 0.0            # graus; + = cabeça para frente/baixo
var head_drop := 0.0            # cabeça afundada nos ombros
var back_arm_rest := 12.0
var stride := 15.0              # distância no mundo por ciclo completo de passos
var leg_swing := 30.0           # graus
var leg_phase_gap := PI         # defasagem entre as pernas (PI = alternância perfeita)
var back_leg_amp := 1.0         # < 1 = arrasta a perna de trás
var walk_bob := 1.1
var walk_lurch := 0.0           # balanço do tronco ao andar (graus)
var arm_swing := 14.0
var windup_time := 0.2          # preparação: últimos X s da recarga real
var strike_time := 0.08
var recover_time := 0.22
var rest_arm := -22.0           # braço da espada em repouso
var rest_sword := 38.0          # ângulo absoluto da espada (0 = para cima, + = para frente)
var windup_arm := 128.0
var windup_sword := -32.0
var windup_lean := -7.0
var strike_arm := -82.0
var strike_sword := 102.0
var strike_lean := 9.0
var lunge := 2.2
var death_time := 0.5
var death_forward := false      # false = cai de costas; true = desaba para frente

# --- Estado da animação -----------------------------------------------------------------
var _facing := 1.0
var _last_pos := Vector2.ZERO
var _walk_phase := 0.0
var _walk_w := 0.0              # 0 = parado, 1 = andando (mistura suave)
var _strike_t := -1.0           # tempo desde o golpe real; -1 = sem golpe
var _hit_t := 0.0
var _death_t := -1.0
var _sword_follow := 0.0        # ângulo da espada com inércia

# --- Peças e ossos (índices na ordem de desenho do corpo) ---------------------------------
enum { P_CAPE, P_ARM_B, P_PAULDRON_B, P_LEG_B, P_LEG_F, P_WAIST, P_TORSO, P_HEAD, P_SWORD, P_ARM_F, P_PAULDRON_F, P_HAND, P_COUNT }
## Osso da sombra no chão; ossos extras da variante começam em B_EXTRA.
const B_GROUND := P_COUNT
const B_EXTRA := P_COUNT + 1
var _xf: Array[Transform2D] = []

# --- Pose do quadro ---------------------------------------------------------------------
var p_offset := Vector2.ZERO
var p_rot := 0.0
var p_scale := Vector2.ONE
var p_lean := 0.0
var p_head := 0.0
var p_head_drop := 0.0
var p_leg_f := 0.0
var p_leg_b := 0.0
var p_arm_f := 0.0
var p_arm_b := 0.0
var p_sword := 0.0
var p_cape := 0.0


func setup(p_unit: CombatUnit, p_def: UnitDef) -> void:
	super(p_unit, p_def)
	_seed = float(unit.id) * 1.618
	_time = fmod(_seed * 3.1, TAU)
	_facing = 1.0 if unit.team == CombatUnit.Team.PLAYER else -1.0
	_last_pos = unit.position
	_sword_follow = rest_sword
	_compute_pose(0.0)
	_bake_rig()
	_pose_bones()


## Monta (ou pega do cache do tipo) as peças do corpo e a malha; cria o esqueleto da unidade.
func _bake_rig() -> void:
	var bodies: Array[Callable] = [
		_draw_cape_part, _draw_arm.bind(0.78), _draw_pauldron.bind(0.78), _draw_leg.bind(0.8), _draw_leg.bind(1.0),
		_draw_waist, _draw_torso, _draw_head, _draw_sword, _draw_arm.bind(1.0), _draw_pauldron.bind(1.0), _draw_hand,
	]
	var keys := ["cape", "arm_b", "pauldron_b", "leg_b", "leg_f", "waist", "torso", "head", "sword", "arm_f", "pauldron_f", "hand"]
	_xf.resize(P_COUNT)
	var layout: Array = _layout_back()
	if shadow_style != null and shadow_style.rim_width > 0.0:
		for i in P_COUNT:   # silhueta roxa de todas as peças por baixo do corpo
			layout.append([_part(keys[i], bodies[i], true), i])
	for i in P_COUNT:
		if i == P_HEAD:
			layout.append_array(_layout_head_back())
		layout.append([_part(keys[i], bodies[i]), i])
	layout.append_array(_layout_front())
	_skin_setup(layout, B_EXTRA + _extra_bones())


## Pontos de extensão da malha (a Sombra: névoa/aura atrás, chama atrás do elmo, fumaça na frente).
func _layout_back() -> Array:
	return [[_part("ground", _ground_shape, false, false), B_GROUND]]


func _layout_head_back() -> Array:
	return []


func _layout_front() -> Array:
	return []


func _extra_bones() -> int:
	return 0


func _ground_shape() -> void:
	_disc(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.32))


# --- Interface do UnitVisual ------------------------------------------------------------

func on_attack_performed() -> void:
	if unit.is_alive():
		_strike_t = 0.0


func on_hit() -> void:
	_hit_t = HIT_TIME


func top_y() -> float:
	return FOOT_Y - 39.0 * RIG_SCALE


func pick_rect() -> Rect2:
	var k := RIG_SCALE
	if _death_t >= 0.0:   # deitado: mais largo e baixo
		return Rect2(-22.0 * k, FOOT_Y - 14.0 * k, 44.0 * k, 19.0 * k)
	return Rect2(-11.0 * k, FOOT_Y - 41.0 * k, 22.0 * k, 45.0 * k)


func ground_point() -> Vector2:
	return Vector2(0, FOOT_Y)


func death_elapsed() -> float:
	return _death_t


## Queda em death_time, quique amortecido (exp(−9·b): < 0,01° depois de 1 s) e escurecimento em
## death_time + 0,3.
func corpse_settle_time() -> float:
	return death_time + 1.0


func update_visual(delta: float) -> void:
	_time += delta
	var alive := unit.is_alive()

	# direção: olha para o alvo (espelhamento instantâneo)
	if alive and unit.target != null:
		var dx := unit.target.position.x - unit.position.x
		if absf(dx) > 0.5:
			_facing = signf(dx)

	# andar: a fase avança com a distância REAL percorrida — nada de "deslizar parado"
	var moved := unit.position.distance_to(_last_pos)
	_last_pos = unit.position
	var moving := alive and (unit.state == CombatUnit.State.MOVING or moved > 0.01)
	if moving:
		_walk_phase += moved / stride * TAU
	_walk_w = move_toward(_walk_w, 1.0 if moving else 0.0, delta * 7.0)

	_hit_t = maxf(0.0, _hit_t - delta)
	if _strike_t >= 0.0:
		_strike_t += delta
		if _strike_t > strike_time + recover_time:
			_strike_t = -1.0
	if not alive and _death_t < 0.0:
		_death_t = 0.0
		_strike_t = -1.0
	if _death_t >= 0.0:
		_death_t += delta

	_compute_pose(delta)
	_pose_bones()


# --- Pose --------------------------------------------------------------------------------

func _compute_pose(delta: float) -> void:
	var w := _walk_w
	var wob := _wobble()

	# IDLE: respiração e pequenas oscilações (somem ao andar)
	var breath := sin(_time * idle_speed + _seed)
	p_offset = Vector2(0, breath * idle_bob * (1.0 - w) + wob * 0.6)
	p_rot = 0.0
	p_scale = Vector2(1.0, 1.0 + breath * 0.012 * (1.0 - w))
	p_lean = posture_lean + wob * 3.0
	p_head = head_tilt - breath * 1.5 * (1.0 - w) + wob * 5.0
	p_head_drop = head_drop
	p_arm_b = back_arm_rest + breath * 2.0
	p_arm_f = rest_arm + breath * 2.5 * (1.0 - w)
	p_cape = sin(_time * 1.7 + _seed) * 2.0

	# WALK: pernas alternam, corpo sobe quando as pernas cruzam, braços em oposição
	var s := sin(_walk_phase)
	p_leg_f = s * leg_swing * w
	p_leg_b = sin(_walk_phase + leg_phase_gap) * leg_swing * back_leg_amp * w
	p_offset.y -= absf(cos(_walk_phase)) * walk_bob * w
	p_lean += (3.0 + sin(_walk_phase * 0.5) * walk_lurch) * w
	p_head -= 2.0 * w                           # cabeça compensa: fica estável
	p_arm_f -= s * arm_swing * 0.6 * w
	p_arm_b += s * arm_swing * w
	p_cape += 9.0 * w + cos(_walk_phase) * 2.5 * w
	var sword_target := rest_sword - s * arm_swing * 0.6 * w

	# ATTACK: preparação lida da recarga real; golpe disparado pelo evento real de dano
	if unit.is_alive():
		if _strike_t >= 0.0:
			if _strike_t < strike_time:
				var k := _ease_out(_strike_t / strike_time)
				p_arm_f = lerpf(windup_arm, strike_arm, k)
				sword_target = lerpf(windup_sword, strike_sword, k)
				p_lean += lerpf(windup_lean, strike_lean, k)
				p_offset.x += lunge * k
				_sword_follow = sword_target        # golpe: sem atraso
			else:
				var r := _ease_in_out((_strike_t - strike_time) / recover_time)
				p_arm_f = lerpf(strike_arm, p_arm_f, r)
				sword_target = lerpf(strike_sword, sword_target, r)
				p_lean += lerpf(strike_lean, 0.0, r)
				p_offset.x += lunge * (1.0 - r)
		elif unit.state == CombatUnit.State.ATTACKING and windup_time > 0.0:
			var wk := _ease_in_out(clampf(1.0 - unit.cooldown / windup_time, 0.0, 1.0))
			p_arm_f = lerpf(p_arm_f, windup_arm, wk)
			sword_target = lerpf(sword_target, windup_sword, wk)
			p_lean += windup_lean * wk
			p_offset.x -= 1.0 * wk

	# espada com inércia (atraso leve em relação ao braço)
	_sword_follow = lerpf(_sword_follow, sword_target, 1.0 - exp(-delta * 18.0)) if delta > 0.0 else sword_target
	p_sword = _sword_follow

	# HIT: recuo, achatamento sutil e clarão (só visual)
	var hk := _hit_t / HIT_TIME
	p_offset.x -= 2.2 * hk
	p_scale *= Vector2(1.0 + 0.06 * hk, 1.0 - 0.06 * hk)
	p_head -= 9.0 * hk
	p_flash = hk * 0.55
	p_dim = 0.0

	if _death_t >= 0.0:
		_death_pose()


func _death_pose() -> void:
	var t := _death_t
	p_flash = 0.0
	p_arm_b = back_arm_rest
	p_leg_f = 0.0
	p_leg_b = 0.0
	p_head = head_tilt
	if not death_forward:
		# vivo: cai de costas, pesado (acelera até o chão) e quica uma vez
		var k := clampf(t / death_time, 0.0, 1.0)
		var fall := k * k
		p_rot = -88.0 * fall
		if t > death_time:
			var b := t - death_time
			p_rot += 6.0 * sin(b * 18.0) * exp(-b * 9.0)
		p_offset = Vector2(-3.0 * fall, -1.5 * fall)
		p_lean = -6.0 * fall
		p_head = -14.0 * fall
		p_arm_f = lerpf(rest_arm, 150.0, _ease_out(k))
		p_sword = lerpf(rest_sword, 170.0, _ease_out(k))
		p_leg_f = -18.0 * fall
		p_cape = 30.0 * fall
	else:
		# sombra: joelhos cedem, depois desaba para frente sem controle
		var buckle := _ease_out(clampf(t / (death_time * 0.35), 0.0, 1.0))
		var topple := clampf((t - death_time * 0.35) / (death_time * 0.65), 0.0, 1.0)
		var fall := topple * topple
		p_rot = 92.0 * fall
		if t > death_time:
			var b := t - death_time
			p_rot += -7.0 * sin(b * 14.0) * exp(-b * 6.0) + 3.0 * sin(b * 31.0) * exp(-b * 10.0)
		p_offset = Vector2(2.5 * fall, 3.0 * buckle * (1.0 - fall) - 1.0 * fall)
		p_lean = 18.0 * buckle
		p_head = head_tilt + 25.0 * buckle
		p_leg_f = -22.0 * buckle
		p_leg_b = 14.0 * buckle
		p_arm_f = lerpf(rest_arm, 40.0, buckle)
		p_sword = lerpf(rest_sword, 150.0, _ease_out(topple))
		p_cape = -12.0 * fall
	p_scale = Vector2.ONE
	p_dim = 0.28 * clampf(t / (death_time + 0.3), 0.0, 1.0)


# --- Desenho -----------------------------------------------------------------------------

func _draw() -> void:
	_skin_draw()


## A pose do quadro nos ossos (mesma cadeia do rig: raiz → quadril → tronco → …).
func _pose_bones() -> void:
	if _skin == null:
		return
	var root := Transform2D(0.0, Vector2(_facing, 1.0) * RIG_SCALE, 0.0, Vector2(0, FOOT_Y)) \
		* Transform2D(deg_to_rad(p_rot), p_scale, 0.0, p_offset)
	var hip := root * Transform2D(0.0, HIP)
	var torso := hip * Transform2D(deg_to_rad(p_lean), Vector2.ZERO)
	var arm_f_local := _tf(SHOULDER_FRONT, p_arm_f)
	var hand_f := arm_f_local * Vector2(0, ARM_LENGTH)
	# capa: peça pronta inclinada (cisalhamento a partir dos ombros) pelo balanço da barra
	var k := -p_cape * 0.12 / 14.0
	_xf[P_CAPE] = torso * Transform2D(Vector2(1, 0), Vector2(k, 1), Vector2(k * 12.2, 0))
	_xf[P_ARM_B] = torso * _tf(SHOULDER_BACK, p_arm_b)
	_xf[P_PAULDRON_B] = torso * _tf(SHOULDER_BACK, 0.0)
	_xf[P_LEG_B] = hip * _tf(Vector2(LEG_BACK_X, 0), p_leg_b)
	_xf[P_LEG_F] = hip * _tf(Vector2(LEG_FRONT_X, 0), p_leg_f)
	_xf[P_WAIST] = hip
	_xf[P_TORSO] = torso
	_xf[P_HEAD] = torso * _tf(NECK + Vector2(0, p_head_drop), p_head)
	_xf[P_SWORD] = torso * _tf(hand_f, p_sword)
	_xf[P_ARM_F] = torso * arm_f_local
	_xf[P_PAULDRON_F] = torso * _tf(SHOULDER_FRONT, 0.0)
	_xf[P_HAND] = torso * _tf(hand_f, 0.0)
	for i in P_COUNT:
		_skin.set_bone(i, _xf[i])
	_pose_ground()
	_pose_extra(root, torso)
	_apply_fx()


## Sombra no chão: estica e desliza para o lado da queda.
func _pose_ground() -> void:
	var lying := clampf(absf(p_rot) / 90.0, 0.0, 1.0)
	var shift := -12.0 * lying * RIG_SCALE * _facing * (1.0 if p_rot < 0.0 else -1.0)
	_skin.set_bone(B_GROUND, Transform2D(0.0, Vector2(1.0 + lying * 0.9, 0.32), 0.0, Vector2(shift, FOOT_Y)))


## Ponto de extensão: ossos extras da variante (a Sombra: névoa, aura, chama, fumaça).
func _pose_extra(_root: Transform2D, _torso: Transform2D) -> void:
	pass


## Capa (peça pronta, no espaço do tronco): presa aos ombros; o balanço da barra (p_cape) é uma
## inclinação aplicada à peça no quadro (ver _pose_bones).
func _draw_cape_part() -> void:
	var pts := PackedVector2Array([
		Vector2(0.4, -12.4), Vector2(-5.4, -12.0),
		Vector2(-10.6, 1.6), Vector2(-6.4, 3.0), Vector2(-2.0, 0.6),
	])
	_poly(_cape_shape(pts), _c(cloth))
	_line(Vector2(-3.6, -11.2), Vector2(-7.0, 2.0), _c(cloth_dark), 1.0)
	_draw_cape_extra(_cape_shape(pts))


## Ponto de extensão: detalhe na barra da capa (a Sombra: fio de energia).
func _draw_cape_extra(_shape: PackedVector2Array) -> void:
	pass


## Ponto de extensão: a Sombra rasga a barra.
func _cape_shape(pts: PackedVector2Array) -> PackedVector2Array:
	return pts


func _draw_leg(shade: float) -> void:
	# grevas + joelheira + bota; pivô no quadril, apontando para baixo (12 = chão)
	_poly(PackedVector2Array([Vector2(-2.2, -0.5), Vector2(2.2, -0.5), Vector2(1.9, 10.0), Vector2(-1.9, 10.0)]), _c(metal_dark, shade))
	_poly(PackedVector2Array([Vector2(-1.6, 5.8), Vector2(2.3, 5.2), Vector2(2.1, 9.6), Vector2(-1.6, 9.6)]), _c(metal, shade))
	_circle(Vector2(0.5, 5.2), 1.7, _c(metal_light, shade))
	_poly(PackedVector2Array([Vector2(-2.2, 9.6), Vector2(2.1, 9.6), Vector2(4.4, 10.9), Vector2(4.4, 12.0), Vector2(-2.3, 12.0)]), _c(leather, shade))


func _draw_waist() -> void:
	# saiote de placas + cinto (cobre o topo das pernas)
	_poly(PackedVector2Array([Vector2(-5.2, -1.6), Vector2(5.2, -1.6), Vector2(6.0, 3.8), Vector2(0.4, 4.4), Vector2(-5.9, 3.8)]), _c(metal))
	_line(Vector2(-5.6, 1.4), Vector2(5.7, 1.4), _c(metal_dark), 0.8)
	_poly(PackedVector2Array([Vector2(-5.6, -2.8), Vector2(5.6, -2.8), Vector2(5.6, -0.9), Vector2(-5.6, -0.9)]), _c(leather))
	_poly(PackedVector2Array([Vector2(2.4, -2.9), Vector2(4.2, -2.9), Vector2(4.2, -0.8), Vector2(2.4, -0.8)]), _c(metal_light))


func _draw_torso() -> void:
	# peitoral com lâminas horizontais (segmentado) e um reflexo no peito
	var plate := PackedVector2Array([
		Vector2(-5.3, -1.6), Vector2(4.8, -1.6), Vector2(6.1, -6.4), Vector2(5.6, -10.8),
		Vector2(2.8, -12.8), Vector2(-4.4, -12.8), Vector2(-5.8, -10.6), Vector2(-6.0, -5.0),
	])
	_poly(plate, _c(metal))
	_line(Vector2(-5.8, -4.3), Vector2(5.6, -4.3), _c(metal_dark), 1.0)
	_line(Vector2(-5.9, -7.0), Vector2(6.0, -7.0), _c(metal_dark), 1.0)
	_poly(PackedVector2Array([Vector2(2.6, -10.6), Vector2(4.6, -10.2), Vector2(5.2, -7.6), Vector2(3.2, -7.8)]), _c(metal_light))
	_draw_torso_wear()


## Ponto de extensão: fissuras de energia da Sombra.
func _draw_torso_wear() -> void:
	pass


func _draw_head() -> void:
	# elmo fechado (origem na base do pescoço), aba inferior, fenda horizontal, pluma
	_draw_plume()
	var helm := PackedVector2Array([
		Vector2(-5.0, -0.8), Vector2(5.4, -0.8), Vector2(6.1, -4.8), Vector2(5.7, -8.8),
		Vector2(3.6, -11.6), Vector2(0.0, -12.6), Vector2(-3.6, -11.9), Vector2(-5.5, -9.0), Vector2(-5.7, -4.2),
	])
	_poly(helm, _c(metal))
	_poly(PackedVector2Array([Vector2(-5.0, -0.8), Vector2(5.4, -0.8), Vector2(5.6, -2.5), Vector2(-5.3, -2.5)]), _c(metal_dark))
	_line(Vector2(-5.5, -8.6), Vector2(5.8, -8.9), _c(metal_dark), 0.9)
	_poly(PackedVector2Array([Vector2(-2.6, -11.6), Vector2(-0.6, -12.2), Vector2(-0.4, -9.4), Vector2(-2.2, -9.3)]), _c(metal_light))
	_draw_visor()
	_draw_helmet_wear()


## Pluma (a Sombra troca por uma chama espectral).
func _draw_plume() -> void:
	_poly(PackedVector2Array([
		Vector2(-1.4, -12.6), Vector2(-3.4, -14.8), Vector2(-7.0, -15.0), Vector2(-9.6, -12.4),
		Vector2(-10.2, -8.8), Vector2(-7.4, -10.6), Vector2(-4.0, -11.8),
	]), _c(plume))


func _draw_visor() -> void:
	var slit := PackedVector2Array([Vector2(1.0, -6.9), Vector2(6.2, -7.2), Vector2(6.2, -5.7), Vector2(1.0, -5.6)])
	_fill(slit, _c(visor))
	if visor_glow.a > 0.0:
		var glow := visor_glow
		_disc(Vector2(4.8, -6.3), 3.2, Color(glow, glow.a * 0.22))
		_fill(PackedVector2Array([Vector2(3.0, -6.7), Vector2(6.0, -6.9), Vector2(6.0, -6.0), Vector2(3.0, -5.9)]), glow)


## Ponto de extensão: fissura no elmo da Sombra.
func _draw_helmet_wear() -> void:
	pass


func _draw_pauldron(shade: float) -> void:
	# ombreira arredondada com uma faixa
	var pts := PackedVector2Array()
	for i in 11:
		var a := lerpf(PI * 1.05, PI * 1.95, i / 10.0)
		pts.append(Vector2(cos(a) * 4.4, sin(a) * 3.8 + 1.2))
	pts.append(Vector2(3.6, 2.8))
	pts.append(Vector2(-3.8, 2.8))
	_poly(pts, _c(metal, shade))
	_line(Vector2(-3.6, 1.0), Vector2(3.8, 1.0), _c(metal_dark, shade), 0.9)


func _draw_arm(shade: float) -> void:
	# braço (malha escura) + braçadeira; pivô no ombro, mão em (0, ARM_LENGTH)
	_poly(PackedVector2Array([Vector2(-1.7, 0.0), Vector2(1.7, 0.0), Vector2(1.5, 8.2), Vector2(-1.5, 8.2)]), _c(metal_dark, shade))
	_poly(PackedVector2Array([Vector2(-1.9, 4.4), Vector2(1.9, 4.4), Vector2(1.8, 8.2), Vector2(-1.8, 8.2)]), _c(metal, shade))
	if shade < 1.0:
		_circle(Vector2(0, ARM_LENGTH), 1.8, _c(leather, shade))


func _draw_hand() -> void:
	_circle(Vector2.ZERO, 1.9, _c(leather))


func _draw_sword() -> void:
	# origem na mão; lâmina para -y. Cabo e pomo atrás da mão.
	_poly(PackedVector2Array([Vector2(-0.7, -0.6), Vector2(0.7, -0.6), Vector2(0.7, 3.2), Vector2(-0.7, 3.2)]), _c(leather))
	_circle(Vector2(0, 3.8), 1.2, _c(metal_dark))
	_poly(_blade_shape(), _c(blade))
	_line(Vector2(0, -2.6), Vector2(0, -12.0), _c(metal_dark), 0.6)
	_poly(PackedVector2Array([Vector2(-3.2, -2.0), Vector2(3.2, -2.0), Vector2(3.2, -0.7), Vector2(-3.2, -0.7)]), _c(metal_dark))
	_draw_blade_extra()


## Ponto de extensão: detalhe sobre a lâmina (a Sombra acende o fio).
func _draw_blade_extra() -> void:
	pass


## Ponto de extensão: a Sombra lasca a lâmina.
func _blade_shape() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-1.25, -1.9), Vector2(1.25, -1.9), Vector2(1.1, -13.6), Vector2(0.0, -16.2), Vector2(-1.1, -13.6)])
