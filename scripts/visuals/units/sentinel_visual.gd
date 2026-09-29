class_name SentinelVisual
extends CodeDrawnUnitVisual
## Sentinela Arcana (viva) desenhada 100% por código. Referência: arte conceitual
## "Sentinela Arcano Vivo" (chapéu largo e pontudo, manto triangular em camadas com
## capelete e acabamento prateado, joia no peito, símbolo arcano no painel frontal,
## duas lâminas mágicas pairando acima).
##
## Só LÊ o estado real: CombatUnit (estado, alvo, recarga) e unit.swords (SentinelSwords:
## recarga e antecipação de cada lâmina). Nenhuma regra de combate aqui.
##
## Espaços de desenho:
##   - corpo: rig espelhado pela direção (`_facing`), origem nos pés, personagem virado para +x;
##   - lâminas: espaço do UnitView SEM espelhar (a lâmina 0 fica sempre à esquerda, como no
##     HTML) e apontadas pela mira suavizada (`_aim`, HTML: swordAim/aimTurn).
##
## Ordem: sombra · fumaça de trás (sombra) · manto de trás · botas · vestido · painel e símbolo
##        · abas do manto · braço de conjuração · capelete, gola e joia · cabeça · chapéu
##        · carga na mão · lâminas · fumaça da frente (sombra)

const FOOT_Y := 10.0
const SHOULDER := Vector2(4.4, -15.4)       # ombro do braço de conjuração (rig)
const ARM_LENGTH := 8.4
const NECK := Vector2(0.6, -18.6)
const GEM := Vector2(0.0, -15.6)
const SWORD_LENGTH := ProjectileView.SWORD_LENGTH
## Âncora visual das lâminas (local ao UnitView, x por lado): ladeando a copa do chapéu.
const SWORD_ANCHOR := Vector2(12.0, FOOT_Y - 43.5)
const HIT_TIME := 0.2
## Preparação do disparo: a mão recolhe à frente do corpo, na altura da cintura, juntando energia.
const WINDUP_ARM := -38.0
const CAST_TIME := 0.1
const RECOVER_TIME := 0.34
const LAUNCH_FX_TIME := 0.32
const REFORM_TIME := 0.35

# --- Paleta (a Sombra sobrescreve em _init) ---------------------------------------------
var robe := Color("294c82")
var robe_light := Color("426fa9")
var robe_dark := Color("14243d")
var trim := Color("bcc8d6")
var skin := Color("e4c6ab")
var hair := Color("1b2a4d")
var glow := Color("74d4ff")
var gem_color := Color("5fb6ff")
var symbol := Color("c9d3df")
var eye := Color("9be6ff")
var core := Color("eef7ff")
var wisp := Color(0, 0, 0, 0)              # fumaça sombria (transparente = não tem)

# --- Estilo de animação (a Sombra sobrescreve) ------------------------------------------
var breath := 0.012
var hem_idle := 0.6
var stride := 16.0
var glide_bob := 0.55
var move_lean := 4.0
var hem_trail := 3.0
var cast_windup := 0.3                     # preparação: últimos X s da recarga real
var windup_lean := -3.0
var cast_lean := 5.0
var cast_open := 0.7
var sword_float := 2.0
var sword_wobble := 0.045
var sword_jitter := 0.0
var aim_turn := 4.5                        # rad/s (HTML: SENTINEL_CONFIG.aimTurn)
var death_time := 0.9

# --- Estado da animação -----------------------------------------------------------------
var _facing := 1.0
var _last_pos := Vector2.ZERO
var _velocity := Vector2.ZERO
var _walk_phase := 0.0
var _walk_w := 0.0
var _cast_t := -1.0
var _cast_arm := -90.0
var _hit_t := 0.0
var _death_t := -1.0
var _aim: Array[float] = [0.0, 0.0]
var _sword_lag := Vector2.ZERO
var _sword_shake := 0.0
var _sword_kick := 0.0
var _launch_t: Array[float] = [-1.0, -1.0]
var _reform_t: Array[float] = [-1.0, -1.0]
var _was_ready: Array[bool] = [true, true]
var _death_blades: Array = []              # [{pos, aim}] das lâminas que pairavam ao morrer

# --- Pose do quadro ---------------------------------------------------------------------
var p_offset := Vector2.ZERO
var p_scale := Vector2.ONE
var p_lean := 0.0
var p_hem := 0.0          # deslocamento da barra do manto (− = para trás)
var p_tip := 0.0          # balanço da ponta do chapéu
var p_hat := 0.0          # inclinação do chapéu (graus)
var p_head := 0.0         # inclinação da cabeça (graus)
var p_arm := 8.0          # braço de conjuração (0 = para baixo, − = para frente)
var p_open := 0.0         # 0..1 abertura das abas do manto
var p_charge := 0.0       # 0..1 energia na mão
var p_gem := 0.0          # 0..1 brilho extra da joia
var p_step := 0.0         # passo das botas
var p_hat_fall := 0.0     # 0..1 chapéu caindo (morte)
var p_alpha := 1.0        # opacidade do corpo (a Sombra se desfaz)
var p_wisp := 0.0         # intensidade extra da fumaça


func setup(p_unit: CombatUnit, p_def: UnitDef) -> void:
	outline = Color("10121c")   # a Sombra troca pelo contorno roxo do ShadowStyle (no super)
	super(p_unit, p_def)
	_seed = float(unit.id) * 1.618
	_time = fmod(_seed * 3.1, TAU)
	_facing = 1.0 if unit.team == CombatUnit.Team.PLAYER else -1.0
	_aim = [0.0 if _facing > 0.0 else PI, 0.0 if _facing > 0.0 else PI]
	_last_pos = unit.position
	_compute_pose(0.0)


# --- Interface do UnitVisual ------------------------------------------------------------

func on_attack_performed() -> void:
	if not unit.is_alive():
		return
	if unit.target:
		var d := unit.target.position - unit.position
		if absf(d.x) > 0.5:
			_facing = signf(d.x)
		_cast_arm = _arm_angle_to(unit.target.position)
	_cast_t = 0.0
	_sword_kick = 1.0


func on_projectile_fired(p: CombatProjectile) -> void:
	if p.is_sword():
		_launch_t[p.sword_index] = 0.0
		_sword_shake = maxf(_sword_shake, 0.35)   # a outra lâmina estremece


func on_hit() -> void:
	_hit_t = HIT_TIME
	_sword_shake = 1.0


func muzzle_point(p: CombatProjectile) -> Vector2:
	if p.is_sword():
		return _blade_anchor(p.sword_index)
	var hand := SHOULDER + _arm_dir(_cast_arm) * (ARM_LENGTH + 1.2)
	return Vector2(hand.x * _facing, hand.y + FOOT_Y)


func projectile_style(_p: CombatProjectile) -> Dictionary:
	return {core = core, glow = glow, dark = robe_dark, trim = trim, shadow = shadow}


func top_y() -> float:
	return SWORD_ANCHOR.y - 5.0


func pick_rect() -> Rect2:
	if _death_t >= 0.0:
		return Rect2(-17, FOOT_Y - 11, 34, 13)
	return Rect2(-12, FOOT_Y - 40, 24, 42)


func death_elapsed() -> float:
	return _death_t


## Queda em death_time, lâminas somem em 0,85 s, quique amortecido (exp(−8·b)) e escurecimento em
## death_time + 0,3. A Sombra: fiapos assentam em ~1,96 s (death_time 1,1 → 2,2).
func corpse_settle_time() -> float:
	return death_time + 1.1


func ground_point() -> Vector2:
	return Vector2(0, FOOT_Y)


func update_visual(delta: float) -> void:
	_time += delta
	var alive := unit.is_alive()

	if alive and unit.target != null:
		var dx := unit.target.position.x - unit.position.x
		if absf(dx) > 0.5:
			_facing = signf(dx)

	# deslizar: a fase avança pela distância real; a velocidade alimenta o atraso das lâminas
	var moved := unit.position - _last_pos
	_last_pos = unit.position
	if delta > 0.0:
		_velocity = _velocity.lerp(moved / delta, 1.0 - exp(-delta * 10.0))
	var moving := alive and (unit.state == CombatUnit.State.MOVING or moved.length() > 0.01)
	if moving:
		_walk_phase += moved.length() / stride * TAU
	_walk_w = move_toward(_walk_w, 1.0 if moving else 0.0, delta * 6.0)

	_hit_t = maxf(0.0, _hit_t - delta)
	_sword_shake = maxf(0.0, _sword_shake - delta * 3.5)
	_sword_kick = maxf(0.0, _sword_kick - delta * 4.0)
	if _cast_t >= 0.0:
		_cast_t += delta
		if _cast_t > CAST_TIME + RECOVER_TIME:
			_cast_t = -1.0
	_update_blades(delta, alive)

	if not alive and _death_t < 0.0:
		_death_t = 0.0
		_cast_t = -1.0
		_capture_death_blades()
	if _death_t >= 0.0:
		_death_t += delta

	_compute_pose(delta)
	queue_redraw()


# --- Lâminas (estado visual) --------------------------------------------------------------

func _update_blades(delta: float, alive: bool) -> void:
	var target_aim := 0.0 if _facing > 0.0 else PI
	for i in 2:
		# mira suave (HTML: updateSwordAim): gira pelo caminho mais curto, sem tremer
		var dif := wrapf(target_aim - _aim[i], -PI, PI)
		_aim[i] += dif * minf(1.0, delta * aim_turn)
		if _launch_t[i] >= 0.0:
			_launch_t[i] += delta
			if _launch_t[i] > LAUNCH_FX_TIME:
				_launch_t[i] = -1.0
		if _reform_t[i] >= 0.0:
			_reform_t[i] += delta
			if _reform_t[i] > REFORM_TIME:
				_reform_t[i] = -1.0
		var ready := _blade_ready(i)
		if alive and ready and not _was_ready[i]:
			_reform_t[i] = 0.0   # a lâmina voltou: reforma com um clarão
		_was_ready[i] = ready
	# atraso das lâminas ao deslizar: ficam um pouco para trás do movimento
	var lag_target := (-_velocity * 0.06).limit_length(4.0)
	_sword_lag = _sword_lag.lerp(lag_target, 1.0 - exp(-delta * 5.0))


func _blade_ready(i: int) -> bool:
	return unit.swords == null or unit.swords.blades[i].is_ready()


func _blade_windup(i: int) -> float:
	if unit.swords == null or not unit.is_alive():
		return 0.0
	var w := unit.swords.blades[i].windup
	return clampf(w / SentinelSwords.WINDUP, 0.0, 1.0) if w > 0.0 else 0.0


## Posição local (UnitView) da lâmina `i` pairando, com flutuação, atraso, tremor e recuo.
func _blade_anchor(i: int) -> Vector2:
	var side := -1.0 if i == 0 else 1.0
	var pos := Vector2(side * SWORD_ANCHOR.x, SWORD_ANCHOR.y + p_offset.y)
	pos.y += sin(_time * 2.2 + i * 1.7) * sword_float           # HTML: flutua = sin(t·2,2 + i·1,7)
	pos += _sword_lag
	pos.y -= 2.0 * _sword_kick                                   # o disparo empurra as lâminas
	var shake := _sword_shake + sword_jitter
	if shake > 0.0:
		pos += Vector2(sin(_time * 53.0 + i * 3.0), cos(_time * 47.0 + i)) * 1.4 * shake
	var wind := _blade_windup(i)
	if wind > 0.0:   # antecipação: recua na direção oposta à mira e vibra (HTML: recuo = r·0,5)
		var k := 1.0 - wind
		pos -= Vector2.from_angle(_aim[i]) * 6.5 * (0.4 + 0.6 * k)
		pos += Vector2(0, sin(_time * 90.0 + i) * 0.7)
	return pos


func _capture_death_blades() -> void:
	_death_blades.clear()
	for i in 2:
		if _blade_ready(i):
			_death_blades.append({pos = _blade_anchor(i), aim = _aim[i], i = i})


# --- Pose --------------------------------------------------------------------------------

func _compute_pose(_delta: float) -> void:
	var w := _walk_w
	var wob := _wobble()
	var br := sin(_time * 2.0 + _seed)

	# IDLE: respiração, barra do manto e ponta do chapéu balançam de leve
	p_offset = Vector2(wob * 0.5, wob * 0.4)
	p_scale = Vector2(1.0, 1.0 + br * breath * (1.0 - w))
	p_lean = wob * 2.0
	p_hem = sin(_time * 1.3 + _seed) * hem_idle
	p_tip = sin(_time * 1.1 + _seed) * 0.8
	p_hat = br * 0.8 + wob * 2.0
	p_head = wob * 3.0
	p_arm = 8.0 + br * 2.0
	p_open = 0.0
	p_charge = 0.0
	p_gem = 0.15 + 0.1 * sin(_time * 2.6 + _seed)
	p_flash = 0.0
	p_dim = 0.0
	p_alpha = 1.0
	p_wisp = 0.0

	# MOVIMENTO: desliza; inclina na direção, manto e ponta do chapéu ficam para trás
	var s := sin(_walk_phase)
	p_offset.y -= absf(s) * glide_bob * w
	p_lean += move_lean * w
	p_hem += (-hem_trail + s * 0.8) * w
	p_tip -= 1.8 * w
	p_step = s * 1.6 * w
	p_arm += 6.0 * w
	p_wisp += 0.5 * w

	# habilidade: lâmina antecipando → a joia acende e a cabeça ergue (ela comanda a lâmina)
	var command := maxf(_blade_windup(0), _blade_windup(1))
	for i in 2:
		if _launch_t[i] >= 0.0:
			command = maxf(command, 1.0 - _launch_t[i] / LAUNCH_FX_TIME)
	p_gem += command * 0.8
	p_head -= 4.0 * command
	p_tip += 0.8 * command

	# ATAQUE: preparação pela recarga real; disparo no evento real
	if unit.is_alive():
		if _cast_t >= 0.0:
			if _cast_t < CAST_TIME:
				var k := _ease_out(_cast_t / CAST_TIME)
				p_arm = lerpf(WINDUP_ARM, _cast_arm, k)
				p_lean += lerpf(windup_lean, cast_lean, k)
				p_open = lerpf(0.35, cast_open, k)
				p_charge = 1.0 - k * 0.6
				p_offset.x -= 1.0 * k
				p_gem += 0.6
			else:
				var r := _ease_in_out((_cast_t - CAST_TIME) / RECOVER_TIME)
				p_arm = lerpf(_cast_arm, p_arm, r)
				p_lean += lerpf(cast_lean, 0.0, r)
				p_open = lerpf(cast_open, 0.0, r)
				p_charge = 0.4 * (1.0 - r)
				p_offset.x -= 1.0 * (1.0 - r)
		elif unit.state == CombatUnit.State.ATTACKING and unit.cooldown < cast_windup:
			var wk := _ease_in_out(clampf(1.0 - unit.cooldown / cast_windup, 0.0, 1.0))
			p_arm = lerpf(p_arm, WINDUP_ARM, wk)   # mão recolhe à frente do corpo, juntando energia
			p_lean += windup_lean * wk
			p_open = 0.35 * wk
			p_charge = wk
			p_gem += 0.5 * wk
			p_tip += 0.6 * wk

	# HIT: recuo, compressão, clarão; as lâminas se desestabilizam (em on_hit)
	var hk := _hit_t / HIT_TIME
	p_offset.x -= 2.2 * hk
	p_scale *= Vector2(1.0 + 0.05 * hk, 1.0 - 0.05 * hk)
	p_tip += sin(_time * 40.0) * 1.5 * hk
	p_flash = hk * 0.55
	_hit_extra(hk)

	if _death_t >= 0.0:
		_death_pose()


## Ponto de extensão: a Sombra se desfaz um pouco no HIT.
func _hit_extra(_k: float) -> void:
	pass


func _death_pose() -> void:
	var t := _death_t
	p_arm = 20.0
	p_open = 0.0
	p_charge = 0.0
	p_flash = 0.0
	p_step = 0.0
	# perde a sustentação, depois o manto colapsa com peso; o chapéu cai para trás
	var buckle := _ease_out(clampf(t / 0.22, 0.0, 1.0))
	var fall := clampf((t - 0.18) / (death_time * 0.6), 0.0, 1.0)
	fall = fall * fall
	p_scale = Vector2(1.0 + 0.3 * fall, 1.0 - 0.1 * buckle - 0.56 * fall)
	p_lean = -4.0 * buckle * (1.0 - fall)
	p_offset = Vector2(0, 0)
	p_hem = -1.5 * fall
	p_head = -70.0 * fall
	p_gem = maxf(0.0, 0.8 - t * 2.5)       # a magia se apaga
	p_hat_fall = _ease_out(clampf((t - 0.25) / 0.45, 0.0, 1.0))
	p_dim = 0.32 * clampf(t / (death_time + 0.3), 0.0, 1.0)
	if t > death_time:   # assenta com um pequeno quique
		var b := t - death_time
		p_scale.y += 0.04 * sin(b * 20.0) * exp(-b * 8.0)
	_death_extra(t)


## Ponto de extensão: a Sombra se desfaz em fumaça.
func _death_extra(_t: float) -> void:
	pass


# --- Desenho -----------------------------------------------------------------------------

func _draw() -> void:
	var mirror := Transform2D(0.0, Vector2(_facing, 1.0), 0.0, Vector2(0, FOOT_Y))
	var root := mirror * Transform2D(deg_to_rad(p_lean), p_scale, 0.0, p_offset)
	var upright := mirror * Transform2D(deg_to_rad(p_lean), p_offset)
	var neck := Vector2(NECK.x * p_scale.x, NECK.y * p_scale.y)
	var head := upright * Transform2D(deg_to_rad(p_head), neck)
	var hat_on := head * Transform2D(deg_to_rad(p_hat), Vector2(0.3, -5.9))
	var hat := hat_on
	if p_hat_fall > 0.0:
		var hat_ground := mirror * Transform2D(deg_to_rad(-16.0), Vector2(-10.5, -1.2))
		hat = hat_on.interpolate_with(hat_ground, p_hat_fall)

	_draw_shadow()
	_with(root)
	_draw_wisps(false)
	_draw_with_rim(_draw_body.bind(root, head, hat))   # na sombra: silhueta roxa por baixo
	if p_charge > 0.0:
		_with(root * Transform2D(deg_to_rad(p_arm), SHOULDER))
		_draw_hand_charge()
	_with(root)
	_draw_wisps(true)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_blades()
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_body(root: Transform2D, head: Transform2D, hat: Transform2D) -> void:
	_with(root)
	_draw_back_cloak()
	_draw_boots()
	_draw_robe()
	var arm_xf := root * Transform2D(deg_to_rad(p_arm), SHOULDER)
	var arm_out := p_charge > 0.0 or _cast_t >= 0.0   # conjurando: braço à frente do manto
	if not arm_out:
		_with(arm_xf)
		_draw_arm()
		_with(root)
	_draw_flaps()
	if arm_out:
		_with(arm_xf)
		_draw_arm()
		_with(root)
	_draw_capelet()
	_with(head)
	_draw_head()
	_with(hat)
	_draw_hat()


func _draw_shadow() -> void:
	var spread := 1.0 + 0.5 * p_hat_fall
	draw_set_transform(Vector2(0, FOOT_Y), 0.0, Vector2(spread, 0.32))
	draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.3))


func _draw_back_cloak() -> void:
	var h := p_hem
	_poly(PackedVector2Array([
		Vector2(-6.0, -16.4), Vector2(6.0, -16.4), Vector2(12.2 + h * 0.4, -0.6), Vector2(8.6 + h * 0.4, 0.9),
		Vector2(0.0, 0.6), Vector2(-8.6 + h, 0.9), Vector2(-13.0 + h * 1.2, -0.4),
	]), _c(robe_dark))


func _draw_boots() -> void:
	var boot := _c(robe_dark, 0.6)
	_poly(PackedVector2Array([Vector2(-4.0 - p_step, -1.0), Vector2(-0.8 - p_step, -1.0), Vector2(-0.6 - p_step, 1.6), Vector2(-4.4 - p_step, 1.6)]), boot)
	_poly(PackedVector2Array([Vector2(1.0 + p_step, -1.0), Vector2(4.2 + p_step, -1.0), Vector2(5.4 + p_step, 1.8), Vector2(1.0 + p_step, 1.8)]), boot)


## Barra do vestido (a Sombra rasga em pontas).
func _hem_points(h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(10.4 + h * 0.5, -0.4), Vector2(7.2 + h * 0.4, 1.0), Vector2(3.6 + h * 0.2, 0.1),
		Vector2(0.0, 1.2), Vector2(-3.6 + h * 0.2, 0.1), Vector2(-7.2 + h * 0.5, 1.0), Vector2(-10.6 + h * 0.8, -0.3),
	])


func _draw_robe() -> void:
	var h := p_hem
	var body := PackedVector2Array([Vector2(-5.4, -16.8), Vector2(5.4, -16.8)])
	body.append_array(_hem_points(h))
	_poly(body, _c(robe))
	if _rim_pass:
		return
	var hem := _hem_points(h)
	draw_polyline(hem, _c(trim), 0.9, true)
	# painel frontal com o símbolo arcano
	var panel := robe.lerp(robe_light, 0.4)
	_poly(PackedVector2Array([
		Vector2(-2.2, -13.2), Vector2(2.4, -13.2), Vector2(4.0 + h * 0.2, 0.3), Vector2(0.0, 1.2), Vector2(-3.8 + h * 0.2, 0.3),
	]), _c(panel))
	_line(Vector2(-2.2, -13.2), Vector2(-3.8 + h * 0.2, 0.3), _c(trim), 0.9)
	_line(Vector2(2.4, -13.2), Vector2(4.0 + h * 0.2, 0.3), _c(trim), 0.9)
	var sym := _c(symbol)
	var c := Vector2(0.1, -5.6)
	draw_arc(c, 2.1, 0.0, TAU, 20, sym, 0.85, true)
	_line(Vector2(0.1, -10.4), Vector2(0.1, -0.9), sym, 0.85)
	_line(Vector2(-3.0, -5.6), Vector2(3.2, -5.6), sym, 0.85)
	draw_colored_polygon(PackedVector2Array([Vector2(0.1, -11.4), Vector2(0.8, -10.4), Vector2(0.1, -9.4), Vector2(-0.6, -10.4)]), sym)
	# divisas na barra (angulosas, como na referência)
	var dec := _c(symbol)
	dec.a *= 0.55
	draw_polyline(PackedVector2Array([Vector2(-8.6 + h * 0.6, -1.2), Vector2(-6.4 + h * 0.5, -3.4), Vector2(-5.2 + h * 0.4, -1.0)]), dec, 0.7, true)
	draw_polyline(PackedVector2Array([Vector2(8.4 + h * 0.4, -1.2), Vector2(6.4 + h * 0.3, -3.4), Vector2(5.4 + h * 0.3, -1.0)]), dec, 0.7, true)


func _draw_flaps() -> void:
	var h := p_hem
	var o := p_open
	# aba de trás (−x) e aba da frente (+x): abrem no ataque, mostrando o painel
	_poly(PackedVector2Array([
		Vector2(-5.6, -16.8), Vector2(-2.6 - o * 0.6, -14.2), Vector2(-4.6 - o * 1.8 + h * 0.2, 0.4),
		Vector2(-9.4 + h * 0.6, 0.5), Vector2(-11.4 + h * 0.9, -0.5),
	]), _c(robe, 0.9))
	_line(Vector2(-2.6 - o * 0.6, -14.2), Vector2(-4.6 - o * 1.8 + h * 0.2, 0.4), _c(trim), 1.2)
	_poly(PackedVector2Array([
		Vector2(5.6, -16.8), Vector2(2.8 + o * 1.2, -14.2), Vector2(4.8 + o * 3.4 + h * 0.2, 0.4),
		Vector2(9.2 + o * 1.0 + h * 0.4, 0.6), Vector2(10.8 + o * 0.8 + h * 0.5, -0.4),
	]), _c(robe))
	_line(Vector2(2.8 + o * 1.2, -14.2), Vector2(4.8 + o * 3.4 + h * 0.2, 0.4), _c(trim), 1.2)


func _draw_arm() -> void:
	# manga em sino + mão; no repouso, fica quase toda escondida pelo capelete
	_poly(PackedVector2Array([Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(2.7, 6.8), Vector2(-2.5, 7.2)]), _c(robe, 0.95))
	_line(Vector2(-2.5, 7.2), Vector2(2.7, 6.8), _c(trim), 1.0)
	_poly(PackedVector2Array([Vector2(-1.0, 7.0), Vector2(1.2, 6.9), Vector2(1.0, 9.4), Vector2(0.0, 10.2), Vector2(-0.9, 9.3)]), _c(skin))


func _draw_hand_charge() -> void:
	var hand := Vector2(0.0, ARM_LENGTH + 1.0)
	var k := p_charge
	var pulse := 0.5 + 0.5 * sin(_time * 24.0)
	draw_circle(hand, 2.5 + 5.0 * k, Color(glow, 0.2 * k))
	draw_circle(hand, 1.2 + 2.8 * k, Color(glow, 0.5 * k))
	draw_circle(hand, 0.8 + 1.5 * k + pulse * 0.3, Color(core, 0.95 * k))
	if shadow:   # energia sombria crepitando em volta da mão
		for i in 3:
			var ang := _time * 8.0 + i * TAU / 3.0
			draw_line(hand + Vector2.from_angle(ang) * 2.0, hand + Vector2.from_angle(ang + 0.5) * (4.0 + 2.0 * k), Color(glow, 0.6 * k), 0.8, true)


## Pontas do capelete (a Sombra alonga e rasga).
func _capelet_half(side: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -15.4), Vector2(3.2 * side, -19.4), Vector2(7.5 * side, -17.8), Vector2(9.3 * side, -12.8),
		Vector2(7.1 * side, -14.2), Vector2(5.1 * side, -12.4), Vector2(2.7 * side, -14.6),
	])


func _draw_capelet() -> void:
	for side in [-1.0, 1.0]:
		var half := _capelet_half(side)
		_poly(half, _c(robe_light if side > 0.0 else robe, 1.0))
		if _rim_pass:
			continue
		var edge := half.slice(3)
		edge.append(half[0])
		draw_polyline(edge, _c(trim), 0.9, true)
	# gola alta
	_poly(PackedVector2Array([
		Vector2(-3.6, -18.8), Vector2(-4.2, -21.4), Vector2(-1.4, -20.0), Vector2(1.6, -20.0), Vector2(4.4, -21.4), Vector2(3.8, -18.8),
	]), _c(robe_dark))
	if _rim_pass:
		return
	# joia do peito: moldura prateada, pedra azul e brilho
	var g := GEM
	var glow_a := clampf(0.16 + 0.34 * p_gem, 0.0, 0.8) * p_alpha
	draw_circle(g, 3.0 + 2.4 * p_gem, Color(glow, glow_a * 0.5))
	_poly(PackedVector2Array([g + Vector2(0, -2.8), g + Vector2(2.3, 0), g + Vector2(0, 2.8), g + Vector2(-2.3, 0)]), _c(trim))
	_poly(PackedVector2Array([g + Vector2(0, -1.9), g + Vector2(1.5, 0), g + Vector2(0, 1.9), g + Vector2(-1.5, 0)]), _c(gem_color).lerp(core, clampf(p_gem - 0.3, 0.0, 0.6)))
	draw_colored_polygon(PackedVector2Array([g + Vector2(-0.3, -1.2), g + Vector2(0.4, -0.5), g + Vector2(-0.3, 0.1), g + Vector2(-0.8, -0.5)]), Color(core, 0.8 * p_alpha))


func _draw_head() -> void:
	# origem no pescoço; rosto em 3/4 virado para +x, cabelo escuro emoldurando
	var fc := Vector2(1.0, -2.6)
	_poly(PackedVector2Array([Vector2(-3.0, -6.0), Vector2(3.8, -6.1), Vector2(4.3, -3.6), Vector2(2.6, -4.9), Vector2(-1.6, -1.8), Vector2(-3.2, 1.0), Vector2(-3.8, -3.2)]), _c(hair))
	var face := PackedVector2Array()
	for i in 16:
		var a := i * TAU / 16.0
		face.append(fc + Vector2(cos(a) * 3.3, sin(a) * 3.4))
	_poly(face, _c(skin))
	if not _rim_pass:
		_draw_face_shade(fc)
	_poly(PackedVector2Array([Vector2(-2.6, -5.9), Vector2(4.1, -6.0), Vector2(3.6, -5.0), Vector2(2.2, -5.3), Vector2(0.8, -4.6), Vector2(-0.8, -5.2), Vector2(-2.4, -3.6)]), _c(hair))
	if not _rim_pass:
		_draw_eyes()


## Ponto de extensão: a Sombra escurece a parte de baixo do rosto.
func _draw_face_shade(_fc: Vector2) -> void:
	_line(Vector2(2.5, -0.8), Vector2(3.3, -0.9), _c(hair).lerp(_c(skin), 0.4), 0.5)


func _draw_eyes() -> void:
	var lit := 1.0 - clampf(p_dim * 3.0, 0.0, 1.0)
	var e := eye.lerp(robe_dark, 1.0 - lit)
	for c in [Vector2(1.7, -2.9), Vector2(3.6, -2.95)]:
		if lit > 0.0:
			draw_circle(c, 1.4, Color(glow, 0.35 * lit * p_alpha))
		draw_colored_polygon(PackedVector2Array([c + Vector2(-0.75, 0), c + Vector2(0, -0.5), c + Vector2(0.75, 0), c + Vector2(0, 0.42)]), Color(e, p_alpha))


func _draw_hat() -> void:
	# origem no centro da aba; copa para cima com a ponta dobrada para trás
	var tip := p_tip
	_poly(PackedVector2Array([
		Vector2(-13.6, 0.8), Vector2(-8.6, -1.2), Vector2(0.0, -1.8), Vector2(8.6, -1.3),
		Vector2(13.9, 0.5), Vector2(9.0, 1.5), Vector2(0.0, 1.8), Vector2(-9.0, 1.6),
	]), _c(robe))
	_poly(PackedVector2Array([Vector2(-12.4, 1.0), Vector2(12.6, 0.8), Vector2(9.0, 1.5), Vector2(0.0, 1.8), Vector2(-9.0, 1.6)]), _c(robe_dark))
	_poly(PackedVector2Array([
		Vector2(-5.4, -1.2), Vector2(5.6, -1.4), Vector2(4.2, -5.8), Vector2(2.2, -9.8), Vector2(0.2 + tip * 0.3, -12.6),
		Vector2(-2.8 + tip, -15.4), Vector2(-1.8 + tip * 0.6, -12.3), Vector2(-3.0 + tip * 0.2, -8.6), Vector2(-4.6, -4.8),
	]), _c(robe))
	_poly(PackedVector2Array([Vector2(1.4, -2.2), Vector2(4.6, -2.4), Vector2(3.2, -6.2), Vector2(1.2, -9.2)]), _c(robe_light))
	_poly(PackedVector2Array([Vector2(-5.3, -1.3), Vector2(5.5, -1.5), Vector2(5.1, -3.4), Vector2(-5.0, -3.2)]), _c(robe_dark))
	_line(Vector2(-5.2, -3.2), Vector2(5.1, -3.4), _c(trim), 0.7)
	if _rim_pass:
		return
	var g := Vector2(1.8, -2.4)
	var glow_a := (0.2 + 0.3 * p_gem) * p_alpha * (1.0 - p_hat_fall)
	draw_circle(g, 2.6, Color(glow, glow_a * 0.6))
	_poly(PackedVector2Array([g + Vector2(0, -2.1), g + Vector2(1.7, 0), g + Vector2(0, 2.1), g + Vector2(-1.7, 0)]), _c(trim))
	_poly(PackedVector2Array([g + Vector2(0, -1.4), g + Vector2(1.1, 0), g + Vector2(0, 1.4), g + Vector2(-1.1, 0)]), _c(gem_color))


## Fumaça sombria nas bordas do manto (só a Sombra). `front` = camada da frente.
func _draw_wisps(_front: bool) -> void:
	pass


func _draw_blades() -> void:
	var style := projectile_style(null)
	if _death_t >= 0.0:
		_draw_dying_blades(style)
		return
	for i in 2:
		var pos := _blade_anchor(i)
		var ang := _aim[i] + sin(_time * 1.6 + i) * sword_wobble
		if _blade_ready(i):
			var wind := _blade_windup(i)
			var alpha := 0.9 + 0.1 * wind
			if _reform_t[i] >= 0.0:
				alpha *= clampf(_reform_t[i] / (REFORM_TIME * 0.6), 0.0, 1.0)
			if wind > 0.0:   # elo de energia: a Sentinela comanda a lâmina
				draw_line(Vector2(0, GEM.y + FOOT_Y), pos, Color(glow, 0.35 * wind * (0.6 + 0.4 * sin(_time * 50.0))), 0.9, true)
			ArcaneBlade.draw(self, Transform2D(ang, pos), SWORD_LENGTH, style, alpha, _time + i, maxf(wind, 0.25 * _sword_kick))
			draw_set_transform_matrix(Transform2D.IDENTITY)
			if _reform_t[i] >= 0.0:
				var k := _reform_t[i] / REFORM_TIME
				draw_arc(pos, 3.0 + 9.0 * k, 0.0, TAU, 20, Color(glow, 0.8 * (1.0 - k)), 1.2, true)
		else:
			# recarregando: vulto da lâmina que se recompõe aos poucos
			var cd := unit.swords.blades[i].cooldown
			var progress := 1.0 - cd / SentinelSwords.COOLDOWN
			ArcaneBlade.draw(self, Transform2D(ang, pos), SWORD_LENGTH, style, 0.06 + 0.2 * progress, _time + i, 0.0)
			draw_set_transform_matrix(Transform2D.IDENTITY)
		if _launch_t[i] >= 0.0:   # clarão de partida (HTML: ring na âncora)
			var k := _launch_t[i] / LAUNCH_FX_TIME
			var anchor := Vector2((-1.0 if i == 0 else 1.0) * SWORD_ANCHOR.x, SWORD_ANCHOR.y)
			draw_arc(anchor, 4.0 + 11.0 * sqrt(k), 0.0, TAU, 24, Color(glow, 0.9 * (1.0 - k)), 1.4, true)
			draw_circle(anchor, 5.0 * (1.0 - k), Color(core, 0.5 * (1.0 - k)))


## Morte (viva): as lâminas perdem o controle, caem girando e se desfazem em faíscas azuis.
func _draw_dying_blades(style: Dictionary) -> void:
	var t := _death_t
	for b in _death_blades:
		var fall_t := maxf(0.0, t - 0.08)
		var pos: Vector2 = b.pos + Vector2(0, 0.5 * 170.0 * fall_t * fall_t)
		pos.y = minf(pos.y, FOOT_Y - 1.0)
		var aim: float = b.aim
		var ang := lerp_angle(aim, PI / 2.0, clampf(fall_t * 2.5, 0.0, 1.0)) + fall_t * 3.0 * (1.0 if b.i == 0 else -1.0)
		var alpha := 1.0 - clampf((t - 0.4) / 0.45, 0.0, 1.0)
		ArcaneBlade.draw(self, Transform2D(ang, pos), SWORD_LENGTH, style, alpha, _time, 0.0)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		if t > 0.35 and alpha > 0.0:
			for k in 5:
				var rise := (t - 0.35) * (14.0 + k * 3.0)
				var sp := pos + Vector2(sin(_seed + k * 2.1) * 6.0, -rise)
				draw_circle(sp, 0.9, Color(glow, alpha * 0.9))


func _arm_dir(angle_deg: float) -> Vector2:
	var a := deg_to_rad(angle_deg)
	return Vector2(-sin(a), cos(a))


## Ângulo do braço (rig espelhado) para apontar ao ponto do mundo.
func _arm_angle_to(world_point: Vector2) -> float:
	var shoulder_world := unit.position + Vector2(SHOULDER.x * _facing, SHOULDER.y + FOOT_Y)
	var d := world_point - shoulder_world
	d.x = absf(d.x)
	return rad_to_deg(atan2(-d.x, d.y))


func _c(col: Color, shade := 1.0) -> Color:
	var out := super(col, shade)
	out.a *= p_alpha
	return out
