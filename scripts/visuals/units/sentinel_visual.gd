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
	_build_rig()
	_pose_bones()


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
	_pose_bones()


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


# --- Desenho leve: peças prontas + ossos -----------------------------------------------------
## O corpo, as lâminas pairando e os efeitos são UMA malha estática por tipo (LiteSkin), com um
## osso por peça; a pose do quadro só move os ossos (nada é redesenhado). Formas que antes mudavam
## a cada quadro viraram transformações: a barra do manto balança por CISALHAMENTO, as abas abrem
## GIRANDO no ombro, as botas DESLIZAM, os brilhos (joia, carga, anéis) CRESCEM/ENCOLHEM, e o
## "esmaecer" das lâminas/fumaça virou crescer/encolher. A transparência etérea da Sombra e o
## clarão/escurecimento vão pelo material (LiteFx).

enum {
	B_GROUND, B_AURA, B_CLOAK, B_BOOT_L, B_BOOT_R, B_ROBE, B_ARM_B, B_FLAP_B, B_FLAP_F, B_ARM_F,
	B_CAPELET, B_GEM_GLOW, B_GEM, B_GEM_FLARE, B_HEAD, B_HAT, B_HAT_GLOW,
	B_CHARGE, B_CRACKLE = B_CHARGE + 3, B_BLADES = B_CRACKLE + 3,
}
## Ossos de cada lâmina (a partir de B_BLADES + i × BLADE_BONES).
enum { BL_LINK, BL_HALO, BL_BLADE, BL_GHOST, BL_RING, BL_LAUNCH_RING, BL_LAUNCH_DISC, BLADE_BONES }
const B_DEATH := B_BLADES + 2 * BLADE_BONES
const DEATH_BITS := 10                      # faíscas (viva) ou fragmentos (sombra): 5 por lâmina
const B_DEATH_DISC := B_DEATH + DEATH_BITS
const B_WISP := B_DEATH_DISC + 2
## Sombra: línguas de fumaça atrás (7) e na frente (5), fiapos laterais (4), fiapos do capelete (2).
const WISPS_BACK := 7
const WISPS_SIDE := 4
const WISPS_FRONT := 5
const WISP_PUFFS := 2
const B_COUNT := B_WISP + WISPS_BACK + WISPS_SIDE + WISPS_FRONT + WISP_PUFFS

## Raios de referência das peças de brilho (a pose escala a partir deles).
const RING_R := 8.0
const LAUNCH_R := 10.0

var _saved_bake := []
## Ossos já escondidos (não repetir a chamada a cada quadro enquanto nada muda).
var _charge_hidden := false
var _death_hidden := false


func _bake_begin() -> void:
	_saved_bake = [p_hem, p_open, p_tip, p_step, p_gem, p_alpha, p_charge, p_hat_fall, _time]
	p_hem = 0.0
	p_open = 0.0
	p_tip = 0.0
	p_step = 0.0
	p_gem = 0.0
	p_alpha = 1.0
	p_charge = 0.0
	p_hat_fall = 0.0
	_time = 0.0


func _bake_end() -> void:
	p_hem = _saved_bake[0]
	p_open = _saved_bake[1]
	p_tip = _saved_bake[2]
	p_step = _saved_bake[3]
	p_gem = _saved_bake[4]
	p_alpha = _saved_bake[5]
	p_charge = _saved_bake[6]
	p_hat_fall = _saved_bake[7]
	_time = _saved_bake[8]


func _build_rig() -> void:
	var style := projectile_style(null)
	var body: Array = [
		["cloak", _draw_back_cloak, B_CLOAK], ["boot_l", _draw_boot.bind(-1.0), B_BOOT_L], ["boot_r", _draw_boot.bind(1.0), B_BOOT_R],
		["robe", _draw_robe, B_ROBE], ["arm", _draw_arm, B_ARM_B], ["flap_b", _draw_flap_back, B_FLAP_B],
		["flap_f", _draw_flap_front, B_FLAP_F], ["arm", _draw_arm, B_ARM_F], ["capelet", _draw_capelet, B_CAPELET],
	]
	var layout: Array = _layout_back()
	if shadow_style != null and shadow_style.rim_width > 0.0:
		for e in body + [["head", _draw_head, B_HEAD], ["hat", _draw_hat, B_HAT]]:
			layout.append([_part(e[0], e[1], true), e[2]])
	for e in body:
		layout.append([_part(e[0], e[1]), e[2]])
	layout.append([_part("gem_glow", func(): _disc(Vector2.ZERO, 1.0, Color(glow, 0.22)), false, false), B_GEM_GLOW])
	layout.append([_part("gem", _draw_gem), B_GEM])
	layout.append([_part("gem_flare", func(): _disc(Vector2.ZERO, 1.4, Color(core, 0.75))), B_GEM_FLARE])
	layout.append([_part("head", _draw_head), B_HEAD])
	layout.append([_part("hat", _draw_hat), B_HAT])
	layout.append([_part("hat_glow", func(): _disc(Vector2.ZERO, 2.6, Color(glow, 0.3)), false, false), B_HAT_GLOW])
	layout.append([_part("hat_gem", _draw_hat_gem), B_HAT])
	# carga na mão (três discos) e, na sombra, faíscas escuras girando
	layout.append([_part("charge0", func(): _disc(Vector2.ZERO, 1.0, Color(glow, 0.2)), false, false), B_CHARGE])
	layout.append([_part("charge1", func(): _disc(Vector2.ZERO, 1.0, Color(glow, 0.5)), false, false), B_CHARGE + 1])
	layout.append([_part("charge2", func(): _disc(Vector2.ZERO, 1.0, Color(core, 0.95)), false, false), B_CHARGE + 2])
	if shadow:
		var crackle := _part("crackle", func(): _bake.line(Vector2.ZERO, Vector2(1, 0), Color(glow, 0.6), 0.8), false, false)
		for k in 3:
			layout.append([crackle, B_CRACKLE + k])
	layout.append_array(_layout_front())
	# lâminas pairando: elo de comando, halo da antecipação, lâmina, vulto (recarga), anéis
	var link := _part("blade_link", func(): _bake.line(Vector2.ZERO, Vector2(1, 0), Color(glow, 0.3), 0.9), false, false)
	var halo := _part("blade_halo", func():
		var pts := PackedVector2Array()
		for v in ArcaneBlade.SHAPE:
			pts.append(v * SWORD_LENGTH)
		_bake.outline(pts, Color(glow, 0.3), 5.6), false, false)
	var blade := _part("blade", func(): ArcaneBlade.bake(_bake, SWORD_LENGTH, style, 0.92, 0.1), false, false)
	var ghost := _part("blade_ghost", func(): ArcaneBlade.bake(_bake, SWORD_LENGTH, style, 0.16, 0.0), false, false)
	var ring := _part("blade_ring", func(): _bake.arc(Vector2.ZERO, RING_R, 0.0, TAU, 24, Color(glow, 0.75), 1.2), false, false)
	var lring := _part("blade_launch_ring", func(): _bake.arc(Vector2.ZERO, LAUNCH_R, 0.0, TAU, 24, Color(glow, 0.85), 1.4), false, false)
	var ldisc := _part("blade_launch_disc", func(): _disc(Vector2.ZERO, 1.0, Color(core, 0.5)), false, false)
	for i in 2:
		var b := B_BLADES + i * BLADE_BONES
		for e in [[link, BL_LINK], [halo, BL_HALO], [blade, BL_BLADE], [ghost, BL_GHOST], [ring, BL_RING], [lring, BL_LAUNCH_RING], [ldisc, BL_LAUNCH_DISC]]:
			layout.append([e[0], b + e[1]])
	# morte: faíscas (viva) ou fragmentos (sombra) e um sopro de fumaça por lâmina
	var bit := _part("death_bit", _death_bit_shape, false, false)
	for k in DEATH_BITS:
		layout.append([bit, B_DEATH + k])
	var puff := _part("death_disc", func(): _disc(Vector2.ZERO, 1.0, Color(wisp, wisp.a * 0.6)), false, false)
	for k in 2:
		layout.append([puff, B_DEATH_DISC + k])
	_skin_setup(layout, B_COUNT)


## Pontos de extensão da malha (a Sombra: névoa, aura e fumaça).
func _layout_back() -> Array:
	return [[_part("ground", func(): _disc(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.3)), false, false), B_GROUND]]


func _layout_front() -> Array:
	return []


## Faísca azul (viva) — a Sombra troca por um fragmento de lâmina.
func _death_bit_shape() -> void:
	_disc(Vector2.ZERO, 0.9, Color(glow, 0.9))


func _draw() -> void:
	_skin_draw()


## Cisalhamento horizontal com pivô na altura `pivot_y`: pontos abaixo andam `k` por unidade de altura.
static func _shear(k: float, pivot_y: float) -> Transform2D:
	return Transform2D(Vector2(1, 0), Vector2(k, 1), Vector2(-k * pivot_y, 0))


func _pose_bones() -> void:
	if _skin == null:
		return
	var sk := _skin
	var mirror := Transform2D(0.0, Vector2(_facing, 1.0), 0.0, Vector2(0, FOOT_Y))
	var root := mirror * Transform2D(deg_to_rad(p_lean), p_scale, 0.0, p_offset)
	var upright := mirror * Transform2D(deg_to_rad(p_lean), p_offset)
	var neck := Vector2(NECK.x * p_scale.x, NECK.y * p_scale.y)
	var head := upright * Transform2D(deg_to_rad(p_head), neck)
	var hat := head * Transform2D(deg_to_rad(p_hat), Vector2(0.3, -5.9))
	if p_hat_fall > 0.0:
		var hat_ground := mirror * Transform2D(deg_to_rad(-16.0), Vector2(-10.5, -1.2))
		hat = hat.interpolate_with(hat_ground, p_hat_fall)
	hat = hat * Transform2D(deg_to_rad(-p_tip * 1.2), Vector2.ZERO)   # a ponta balança: o chapéu gira de leve
	_pose_ground()
	var h := p_hem
	var o := p_open
	sk.set_bone(B_CLOAK, root * _shear(h * 0.7 / 16.4, -16.4))
	sk.set_bone(B_BOOT_L, root * Transform2D(0.0, Vector2(-p_step, 0)))
	sk.set_bone(B_BOOT_R, root * Transform2D(0.0, Vector2(p_step, 0)))
	sk.set_bone(B_ROBE, root * _shear(h * 0.45 / 17.6, -16.8))
	var arm_xf := root * Transform2D(deg_to_rad(p_arm), SHOULDER)
	var arm_out := p_charge > 0.0 or _cast_t >= 0.0   # conjurando: braço à frente do manto
	sk.set_bone(B_ARM_B, LiteSkin.HIDDEN if arm_out else arm_xf)
	sk.set_bone(B_ARM_F, arm_xf if arm_out else LiteSkin.HIDDEN)
	var pb := Vector2(-5.6, -16.8)
	var pf := Vector2(5.6, -16.8)
	sk.set_bone(B_FLAP_B, root * Transform2D(atan(1.8 * o / 17.0), pb) * _shear(h * 0.4 / 17.0, 0.0) * Transform2D(0.0, -pb))
	sk.set_bone(B_FLAP_F, root * Transform2D(-atan(3.4 * o / 17.0), pf) * _shear(h * 0.35 / 17.0, 0.0) * Transform2D(0.0, -pf))
	sk.set_bone(B_CAPELET, root)
	sk.set_bone(B_GEM, root)
	var gr := 3.0 + 2.4 * p_gem
	sk.set_bone(B_GEM_GLOW, root * Transform2D(0.0, Vector2(gr, gr), 0.0, GEM))
	var flare := clampf(p_gem - 0.3, 0.0, 0.6) / 0.6
	sk.set_bone(B_GEM_FLARE, root * Transform2D(0.0, Vector2(flare, flare), 0.0, GEM) if flare > 0.0 else LiteSkin.HIDDEN)
	sk.set_bone(B_HEAD, head)
	sk.set_bone(B_HAT, hat)
	var hg := (0.6 + 0.4 * p_gem) * (1.0 - p_hat_fall)
	sk.set_bone(B_HAT_GLOW, hat * Transform2D(0.0, Vector2(hg, hg), 0.0, Vector2(1.8, -2.4)) if hg > 0.01 else LiteSkin.HIDDEN)
	_pose_charge(root)
	_pose_blades()
	_pose_extra(root)
	_apply_fx(p_alpha)


## Ponto de extensão: ossos da variante (a Sombra: névoa, aura, fumaça). Viva: nada.
func _pose_extra(_root: Transform2D) -> void:
	pass


func _pose_ground() -> void:
	var spread := 1.0 + 0.5 * p_hat_fall
	_skin.set_bone(B_GROUND, Transform2D(0.0, Vector2(spread, 0.32), 0.0, Vector2(0, FOOT_Y)))


## Energia juntando na mão (três discos que crescem com a carga) e, na sombra, faíscas girando.
func _pose_charge(root: Transform2D) -> void:
	var k := p_charge
	if k <= 0.0:
		if not _charge_hidden:
			for i in 3:
				_skin.hide_bone(B_CHARGE + i)
				if shadow:
					_skin.hide_bone(B_CRACKLE + i)
			_charge_hidden = true
		return
	_charge_hidden = false
	var hand_xf := root * Transform2D(deg_to_rad(p_arm), SHOULDER)
	var hand := hand_xf * Vector2(0.0, ARM_LENGTH + 1.0)
	var pulse := 0.5 + 0.5 * sin(_time * 24.0)
	var ramp := sqrt(k)
	var radii := [2.5 + 5.0 * k, 1.2 + 2.8 * k, 0.8 + 1.5 * k + pulse * 0.3]
	for i in 3:
		var r: float = radii[i] * ramp
		_skin.set_bone(B_CHARGE + i, Transform2D(0.0, Vector2(r, r), 0.0, hand))
	if shadow:
		for i in 3:
			var ang := _time * 8.0 + i * TAU / 3.0
			var a := hand + Vector2.from_angle(ang) * 2.0
			var b := hand + Vector2.from_angle(ang + 0.5) * (4.0 + 2.0 * k)
			_skin.set_bone(B_CRACKLE + i, _seg_bone(a, b))


func _pose_blades() -> void:
	if _death_t >= 0.0:
		for i in 2:
			for j in BLADE_BONES:
				_skin.hide_bone(B_BLADES + i * BLADE_BONES + j)
		_death_hidden = false
		_pose_dying_blades()
		return
	if not _death_hidden:
		for k in DEATH_BITS:
			_skin.hide_bone(B_DEATH + k)
		for k in 2:
			_skin.hide_bone(B_DEATH_DISC + k)
		_death_hidden = true
	for i in 2:
		var b := B_BLADES + i * BLADE_BONES
		var pos := _blade_anchor(i)
		var ang := _aim[i] + sin(_time * 1.6 + i) * sword_wobble
		var xf := Transform2D(ang, pos)
		var ready := _blade_ready(i)
		var wind := _blade_windup(i) if ready else 0.0
		if ready:
			var s := 1.0
			if _reform_t[i] >= 0.0:
				s = clampf(_reform_t[i] / (REFORM_TIME * 0.6), 0.05, 1.0)   # volta crescendo
			_skin.set_bone(b + BL_BLADE, Transform2D(ang, Vector2(s, s), 0.0, pos))
			_skin.hide_bone(b + BL_GHOST)
		else:
			_skin.hide_bone(b + BL_BLADE)
			var cd := unit.swords.blades[i].cooldown
			var progress := 1.0 - cd / SentinelSwords.COOLDOWN
			var g := 0.7 + 0.3 * progress
			_skin.set_bone(b + BL_GHOST, Transform2D(ang, Vector2(g, g), 0.0, pos))
		var energy := maxf(wind, 0.25 * _sword_kick) if ready else 0.0
		_skin.set_bone(b + BL_HALO, xf if energy > 0.2 else LiteSkin.HIDDEN)
		_skin.set_bone(b + BL_LINK, _seg_bone(Vector2(0, GEM.y + FOOT_Y), pos) if wind > 0.0 else LiteSkin.HIDDEN)
		if ready and _reform_t[i] >= 0.0:
			var rk := _reform_t[i] / REFORM_TIME
			var rs := (3.0 + 9.0 * rk) / RING_R
			_skin.set_bone(b + BL_RING, Transform2D(0.0, Vector2(rs, rs), 0.0, pos))
		else:
			_skin.hide_bone(b + BL_RING)
		if _launch_t[i] >= 0.0:
			var lk := _launch_t[i] / LAUNCH_FX_TIME
			var anchor := Vector2((-1.0 if i == 0 else 1.0) * SWORD_ANCHOR.x, SWORD_ANCHOR.y)
			var ls := (4.0 + 11.0 * sqrt(lk)) / LAUNCH_R * (1.0 - 0.3 * lk)
			_skin.set_bone(b + BL_LAUNCH_RING, Transform2D(0.0, Vector2(ls, ls), 0.0, anchor))
			var ds := 5.0 * (1.0 - lk)
			_skin.set_bone(b + BL_LAUNCH_DISC, Transform2D(0.0, Vector2(ds, ds), 0.0, anchor))
		else:
			_skin.hide_bone(b + BL_LAUNCH_RING)
			_skin.hide_bone(b + BL_LAUNCH_DISC)


## Morte (viva): as lâminas perdem o controle, caem girando e se desfazem em faíscas azuis.
## (Usa os ossos de lâmina e de faísca; a Sombra troca a coreografia.)
func _pose_dying_blades() -> void:
	var t := _death_t
	var bit := 0
	for n in _death_blades.size():
		var bd: Dictionary = _death_blades[n]
		var fall_t := maxf(0.0, t - 0.08)
		var pos: Vector2 = bd.pos + Vector2(0, 0.5 * 170.0 * fall_t * fall_t)
		pos.y = minf(pos.y, FOOT_Y - 1.0)
		var aim: float = bd.aim
		var ang := lerp_angle(aim, PI / 2.0, clampf(fall_t * 2.5, 0.0, 1.0)) + fall_t * 3.0 * (1.0 if bd.i == 0 else -1.0)
		var alpha := 1.0 - clampf((t - 0.4) / 0.45, 0.0, 1.0)
		var b := B_BLADES + int(bd.i) * BLADE_BONES
		_skin.set_bone(b + BL_BLADE, Transform2D(ang, Vector2(alpha, alpha), 0.0, pos) if alpha > 0.0 else LiteSkin.HIDDEN)
		for k in 5:
			if t > 0.35 and alpha > 0.0:
				var rise := (t - 0.35) * (14.0 + k * 3.0)
				var sp := pos + Vector2(sin(_seed + k * 2.1) * 6.0, -rise)
				_skin.set_bone(B_DEATH + bit, Transform2D(0.0, Vector2(alpha, alpha), 0.0, sp))
			else:
				_skin.hide_bone(B_DEATH + bit)
			bit += 1
	for k in range(bit, DEATH_BITS):
		_skin.hide_bone(B_DEATH + k)
	for k in 2:
		_skin.hide_bone(B_DEATH_DISC + k)


func _draw_back_cloak() -> void:
	var h := p_hem
	_poly(PackedVector2Array([
		Vector2(-6.0, -16.4), Vector2(6.0, -16.4), Vector2(12.2 + h * 0.4, -0.6), Vector2(8.6 + h * 0.4, 0.9),
		Vector2(0.0, 0.6), Vector2(-8.6 + h, 0.9), Vector2(-13.0 + h * 1.2, -0.4),
	]), _c(robe_dark))


## Bota de um lado (−1 = de trás, +1 = da frente); o passo é um deslizamento no osso.
func _draw_boot(side: float) -> void:
	var boot := _c(robe_dark, 0.6)
	if side < 0.0:
		_poly(PackedVector2Array([Vector2(-4.0, -1.0), Vector2(-0.8, -1.0), Vector2(-0.6, 1.6), Vector2(-4.4, 1.6)]), boot)
	else:
		_poly(PackedVector2Array([Vector2(1.0, -1.0), Vector2(4.2, -1.0), Vector2(5.4, 1.8), Vector2(1.0, 1.8)]), boot)


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
	_pline(hem, _c(trim), 0.9)
	# painel frontal com o símbolo arcano
	var panel := robe.lerp(robe_light, 0.4)
	_poly(PackedVector2Array([
		Vector2(-2.2, -13.2), Vector2(2.4, -13.2), Vector2(4.0 + h * 0.2, 0.3), Vector2(0.0, 1.2), Vector2(-3.8 + h * 0.2, 0.3),
	]), _c(panel))
	_line(Vector2(-2.2, -13.2), Vector2(-3.8 + h * 0.2, 0.3), _c(trim), 0.9)
	_line(Vector2(2.4, -13.2), Vector2(4.0 + h * 0.2, 0.3), _c(trim), 0.9)
	var sym := _c(symbol)
	var c := Vector2(0.1, -5.6)
	_arc_line(c, 2.1, 0.0, TAU, 20, sym, 0.85)
	_line(Vector2(0.1, -10.4), Vector2(0.1, -0.9), sym, 0.85)
	_line(Vector2(-3.0, -5.6), Vector2(3.2, -5.6), sym, 0.85)
	_fill(PackedVector2Array([Vector2(0.1, -11.4), Vector2(0.8, -10.4), Vector2(0.1, -9.4), Vector2(-0.6, -10.4)]), sym)
	# divisas na barra (angulosas, como na referência)
	var dec := _c(symbol)
	dec.a *= 0.55
	_pline(PackedVector2Array([Vector2(-8.6 + h * 0.6, -1.2), Vector2(-6.4 + h * 0.5, -3.4), Vector2(-5.2 + h * 0.4, -1.0)]), dec, 0.7)
	_pline(PackedVector2Array([Vector2(8.4 + h * 0.4, -1.2), Vector2(6.4 + h * 0.3, -3.4), Vector2(5.4 + h * 0.3, -1.0)]), dec, 0.7)
	_draw_robe_extra()


## Ponto de extensão: detalhe no vestido (a Sombra: fissuras de energia).
func _draw_robe_extra() -> void:
	pass


## Aba de trás do manto (−x); abre girando no ombro (osso).
func _draw_flap_back() -> void:
	_poly(PackedVector2Array([
		Vector2(-5.6, -16.8), Vector2(-2.6, -14.2), Vector2(-4.6, 0.4), Vector2(-9.4, 0.5), Vector2(-11.4, -0.5),
	]), _c(robe, 0.9))
	_line(Vector2(-2.6, -14.2), Vector2(-4.6, 0.4), _c(trim), 1.2)


## Aba da frente (+x): abre no ataque, mostrando o painel.
func _draw_flap_front() -> void:
	_poly(PackedVector2Array([
		Vector2(5.6, -16.8), Vector2(2.8, -14.2), Vector2(4.8, 0.4), Vector2(9.2, 0.6), Vector2(10.8, -0.4),
	]), _c(robe))
	_line(Vector2(2.8, -14.2), Vector2(4.8, 0.4), _c(trim), 1.2)


func _draw_arm() -> void:
	# manga em sino + mão; no repouso, fica quase toda escondida pelo capelete
	_poly(PackedVector2Array([Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(2.7, 6.8), Vector2(-2.5, 7.2)]), _c(robe, 0.95))
	_line(Vector2(-2.5, 7.2), Vector2(2.7, 6.8), _c(trim), 1.0)
	_poly(PackedVector2Array([Vector2(-1.0, 7.0), Vector2(1.2, 6.9), Vector2(1.0, 9.4), Vector2(0.0, 10.2), Vector2(-0.9, 9.3)]), _c(skin))


## Pontas do capelete (a Sombra alonga e rasga).
func _capelet_half(side: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -15.4), Vector2(3.2 * side, -19.4), Vector2(7.5 * side, -17.8), Vector2(9.3 * side, -12.8),
		Vector2(7.1 * side, -14.2), Vector2(5.1 * side, -12.4), Vector2(2.7 * side, -14.6),
	])


## Capelete (as duas metades) e gola alta. A joia é outra peça (brilho no meio).
func _draw_capelet() -> void:
	for side in [-1.0, 1.0]:
		var half := _capelet_half(side)
		_poly(half, _c(robe_light if side > 0.0 else robe, 1.0))
		if _rim_pass:
			continue
		var edge := half.slice(3)
		edge.append(half[0])
		_pline(edge, _c(trim), 0.9)
	_poly(PackedVector2Array([
		Vector2(-3.6, -18.8), Vector2(-4.2, -21.4), Vector2(-1.4, -20.0), Vector2(1.6, -20.0), Vector2(4.4, -21.4), Vector2(3.8, -18.8),
	]), _c(robe_dark))


## Joia do peito: moldura prateada, pedra e reflexo.
func _draw_gem() -> void:
	var g := GEM
	_poly(PackedVector2Array([g + Vector2(0, -2.8), g + Vector2(2.3, 0), g + Vector2(0, 2.8), g + Vector2(-2.3, 0)]), _c(trim))
	_poly(PackedVector2Array([g + Vector2(0, -1.9), g + Vector2(1.5, 0), g + Vector2(0, 1.9), g + Vector2(-1.5, 0)]), _c(gem_color))
	_fill(PackedVector2Array([g + Vector2(-0.3, -1.2), g + Vector2(0.4, -0.5), g + Vector2(-0.3, 0.1), g + Vector2(-0.8, -0.5)]), Color(core, 0.8))


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
	for c in [Vector2(1.7, -2.9), Vector2(3.6, -2.95)]:
		_disc(c, 1.4, Color(glow, 0.35))
		_fill(PackedVector2Array([c + Vector2(-0.75, 0), c + Vector2(0, -0.5), c + Vector2(0.75, 0), c + Vector2(0, 0.42)]), eye)


func _draw_hat() -> void:
	# origem no centro da aba; copa para cima com a ponta dobrada para trás
	_poly(PackedVector2Array([
		Vector2(-13.6, 0.8), Vector2(-8.6, -1.2), Vector2(0.0, -1.8), Vector2(8.6, -1.3),
		Vector2(13.9, 0.5), Vector2(9.0, 1.5), Vector2(0.0, 1.8), Vector2(-9.0, 1.6),
	]), _c(robe))
	_poly(PackedVector2Array([Vector2(-12.4, 1.0), Vector2(12.6, 0.8), Vector2(9.0, 1.5), Vector2(0.0, 1.8), Vector2(-9.0, 1.6)]), _c(robe_dark))
	_poly(PackedVector2Array([
		Vector2(-5.4, -1.2), Vector2(5.6, -1.4), Vector2(4.2, -5.8), Vector2(2.2, -9.8), Vector2(0.2, -12.6),
		Vector2(-2.8, -15.4), Vector2(-1.8, -12.3), Vector2(-3.0, -8.6), Vector2(-4.6, -4.8),
	]), _c(robe))
	_poly(PackedVector2Array([Vector2(1.4, -2.2), Vector2(4.6, -2.4), Vector2(3.2, -6.2), Vector2(1.2, -9.2)]), _c(robe_light))
	_poly(PackedVector2Array([Vector2(-5.3, -1.3), Vector2(5.5, -1.5), Vector2(5.1, -3.4), Vector2(-5.0, -3.2)]), _c(robe_dark))
	_line(Vector2(-5.2, -3.2), Vector2(5.1, -3.4), _c(trim), 0.7)


## Joia do chapéu (o brilho é outra peça, por baixo).
func _draw_hat_gem() -> void:
	var g := Vector2(1.8, -2.4)
	_poly(PackedVector2Array([g + Vector2(0, -2.1), g + Vector2(1.7, 0), g + Vector2(0, 2.1), g + Vector2(-1.7, 0)]), _c(trim))
	_poly(PackedVector2Array([g + Vector2(0, -1.4), g + Vector2(1.1, 0), g + Vector2(0, 1.4), g + Vector2(-1.1, 0)]), _c(gem_color))


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
