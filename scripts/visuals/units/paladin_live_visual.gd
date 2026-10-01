class_name PaladinLiveVisual
extends CodeDrawnUnitVisual
## Paladino Vivo desenhado 100% por código na MESMA linguagem do Guerreiro e da Sentinela:
## formas grandes e simples, contorno escuro, poucas peças, luz e sombra chapadas.
##
## Rig de partes simples (corpo, cabeça, auréola, ombreiras, braços, escudo, espada, pernas,
## tabardo). Cada parte tem uma âncora no "espaço do corpo" (lateral, frente, altura); a direção
## (yaw) só desloca essas âncoras e muda a ordem das partes — fake 2.5D leve: nas diagonais um
## ombro aparece mais que o outro, uma perna fica à frente, o escudo muda de ângulo, a espada troca
## de plano; de costas aparecem a traseira do elmo e o verso do escudo. As formas continuam 2D.
##
## Estado e tempo (o que mostrar e quando) vêm do PaladinAnimator — o mesmo que lê a simulação:
## caminhada, golpe sincronizado com o dano real, provocação → guarda → Escudo Sagrado, bloqueio,
## hit, push e morte. Esta classe só traduz isso em poses 2D e desenha. Nada altera a CombatUnit.
##
## Regra do equipamento: espada SEMPRE na mão direita, escudo SEMPRE no braço esquerdo. As direções
## da esquerda seguem a referência (vista espelhada, com o VERSO do escudo à mostra): a pose é a da
## direção da direita e só o desenho é espelhado no eixo X (sem escala negativa no nó). Nos dados
## (âncoras, clipes) a espada continua sendo a mão direita — nunca troca nem duplica.
##
## Espaço do corpo: L = esquerda do personagem, F = frente, Y = altura (pés em 0). Unidades do rig;
## RIG_SCALE converte para o mundo (igual ao Guerreiro).

const RIG_SCALE := 0.9
## Porte do Paladino sobre a escala comum (Guerreiro): ~12% mais alto e mais largo. Aplicado no
## transform do corpo (as âncoras continuam no espaço do rig).
const BODY_SCALE := Vector2(1.06, 1.12)
## Pés abaixo do centro lógico da CombatUnit (igual ao Guerreiro).
const FOOT_Y := 9.0
## Quanto a profundidade desce na tela (chão visto um pouco de cima).
const DEPTH_Y := 0.14
const HIT_TIME := 0.22
const RIGHT := -1.0   # L do lado direito
const LEFT := 1.0

## yaw (graus) de cada direção da direita; as da esquerda são o negativo. DOWN/UP pendem para o
## último lado lateral (nunca ficam chapados de frente/costas).
const DIR_YAW := [8.0, 20.0, 30.0, 128.0, 164.0]

@export_group("Proporções")
## Largura do tronco e distância entre os ombros; silhueta compacta de frontline.
@export_range(0.8, 1.4, 0.01) var body_width := 1.04
@export_range(0.8, 1.5, 0.01) var shield_scale := 1.18
@export_range(0.8, 1.5, 0.01) var sword_scale := 1.18
@export_range(0.8, 1.3, 0.01) var head_scale := 1.0

@export_group("Movimento")
## Passos curtos: deslocamento do pé (unidades do rig) e quanto ele sobe.
@export_range(1.0, 6.0, 0.1) var step_length := 3.0
@export_range(0.0, 3.0, 0.05) var step_lift := 1.4
@export_range(0.0, 2.0, 0.05) var breathing := 1.0
## Velocidade de giro entre direções (graus/s).
@export_range(120.0, 1400.0, 10.0) var turn_speed := 520.0

@export_group("Cores")
@export var ivory := Color("e8e1d1")
@export var ivory_shade := Color("bdb3a0")
@export var ivory_light := Color("f8f4ea")
@export var gold := Color("d9a93c")
@export var gold_light := Color("f4d27a")
@export var gold_dark := Color("98691c")
@export var dark := Color("2b2730")
@export var blade := Color("dde3ea")
@export var blade_dark := Color("8e96a3")
@export var leather := Color("5c3c27")
@export var wood := Color("5b4330")
@export var visor := Color("111116")
@export var holy := Color("fff0b3")

var animator := PaladinAnimator.new()
var look := PaladinRigLook.new()   # só os tempos/parâmetros do animador (ritmo, inércia)

var _yaw := 52.0                 # graus, suavizado
var _flash_t := 0.0
var _sword_drop := {}            # {pos, ang, t} no espaço da raiz (morte)
var _shield_drop := {}
var _pose := {}
var _ring_t := -1.0              # efeitos simples
var _shield_up_t := -1.0
var _block_fx_t := -1.0

# Âncoras calculadas no quadro (espaço da raiz, antes da queda) — para efeitos e testes
var anchors := {}
## Partes do quadro ([profundidade, desenho]), montadas no update (o _draw só envia).
var _parts: Array = []


func setup(p_unit: CombatUnit, p_def: UnitDef) -> void:
	use_draw_cache = false   # polígonos projetados a cada quadro: não se repetem
	super(p_unit, p_def)
	_seed = float(unit.id) * 1.618
	_time = fmod(_seed * 3.1, TAU)
	look.walk_cycle = 1.05          # mais pesado que o Guerreiro
	look.secondary_motion = 0.8
	animator.compose_pose = false   # este visual só lê o estado do animador (ver PaladinAnimator)
	animator.setup(look, unit)
	_yaw = _dir_yaw(animator.dir, animator.lateral)
	_init_parts()
	_update(0.0)


# --- Interface do UnitVisual ------------------------------------------------------------

func on_attack_performed() -> void:
	animator.notify_attack()


func on_hit() -> void:
	if unit.is_alive():
		_flash_t = HIT_TIME
	animator.notify_hit()


func on_ability_event(kind: StringName) -> void:
	if not unit.is_alive():
		return
	match kind:
		&"taunt":
			animator.notify_taunt()
			_ring_t = 0.0
		&"shield":
			_shield_up_t = 0.0
		&"block":
			animator.notify_block()
			_block_fx_t = 0.0


## Empurrão vindo de uma mecânica futura: só a postura (a posição é da simulação).
func on_pushed(screen_dir: Vector2) -> void:
	animator.notify_push(screen_dir)


## Prévia só visual (Sandbox). `dir` = PaladinPoseLibrary.Dir. Não toca na CombatUnit.
func preview(kind: StringName, dir: int) -> void:
	animator.preview(kind, dir)
	_sword_drop.clear()
	_shield_drop.clear()
	if kind == &"taunt":
		_ring_t = 0.0
	elif kind == &"block":
		_block_fx_t = 0.0


func top_y() -> float:
	return FOOT_Y - 44.0 * RIG_SCALE * BODY_SCALE.y


## Topo do elmo (sem a auréola), para comparar a altura do corpo com a do Guerreiro.
func helmet_top_y() -> float:
	return FOOT_Y + float(anchors.get(&"helmet_top", Vector2(0, -44.0)).y) * RIG_SCALE * BODY_SCALE.y


## Âncora em coordenadas locais do visual (com o espelho da vista da esquerda e o porte do corpo).
func screen_anchor(key: StringName) -> Vector2:
	var q: Vector2 = anchors[key]
	return Vector2(q.x * (1.0 if _yaw >= 0.0 else -1.0) * BODY_SCALE.x * RIG_SCALE, FOOT_Y + q.y * BODY_SCALE.y * RIG_SCALE)


func pick_rect() -> Rect2:
	var k := RIG_SCALE * BODY_SCALE.y
	if animator.dead:
		return Rect2(-28.0 * k, FOOT_Y - 14.0 * k, 56.0 * k, 19.0 * k)
	return Rect2(-14.0 * k, FOOT_Y - 44.0 * k, 28.0 * k, 48.0 * k)


func ground_point() -> Vector2:
	return Vector2(0, FOOT_Y)


## Só a morte real (a prévia de morte do Sandbox continua animada).
func death_elapsed() -> float:
	return animator.death_t if animator.dead and animator.preview_kind == &"" else -1.0


## Queda em 1,35 s, espada/escudo no chão em ~1,1 s, escurecimento em 1,65 s, efeitos (0,9 s).
func corpse_settle_time() -> float:
	return 2.0


func update_visual(delta: float) -> void:
	_update(delta)
	var view := get_parent() as UnitView
	if view and view.debug_visible:
		queue_redraw()   # só o texto do F4 precisa redesenhar; o corpo vai pelos ossos


# --- Pose -------------------------------------------------------------------------------


## Pose neutra (valores absolutos). Ângulos em graus. swing: 0 = braço para baixo, 90 = à frente.
## s_elev: elevação da lâmina (0 = horizontal para a frente, −90 = para baixo, 90 = para cima).
## Guarda alta: lâmina afastada do elmo, cotovelo dobrado e escudo à frente.
## s_yaw: lâmina para fora (lado direito); sh_yaw: face do escudo girada para fora (lado esquerdo).
static func neutral() -> Dictionary:
	return {
		twist = 0.0, lean = 1.0, crouch = 0.6, rootx = 0.0, rooty = 0.0, stance = 0.0,
		r_swing = 28.0, r_abd = 38.0, r_elbow = 68.0, s_elev = 70.0, s_yaw = 62.0,
		l_swing = 42.0, l_abd = -10.0, l_elbow = 58.0, sh_yaw = 18.0, sh_fwd = 0.0,
		tab = 0.0, head_tilt = 0.0, head_turn = 0.0,
		rf = 0.9, rl = 0.0, lf = -0.7, ll = 0.0, tilt = 0.0, glow = 0.0,
	}


## Pose neutra calculada uma vez (neutral() é chamada várias vezes por quadro).
static var _NEUTRAL := neutral()
## Trilhas constantes (golpes, provocação, morte), montadas uma vez na 1ª vez que são usadas.
static var _tracks := {}
## Senos/cossenos fixos das curvas do elmo e da ombreira (os mesmos ângulos todo quadro).
## (mesmas expressões do desenho original, para dar exatamente os mesmos valores)
static var _HELM_COS := _helm_table(true)
static var _HELM_SIN := _helm_table(false)
static var _PAULDRON_COS := _pauldron_table(true)
static var _PAULDRON_SIN := _pauldron_table(false)


static func _helm_table(want_cos: bool) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in 13:
		var ang := PI + i * PI / 12.0
		out.append(cos(ang) if want_cos else sin(ang))
	return out


static func _pauldron_table(want_cos: bool) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in 13:
		var ang := PI * 1.02 + i * PI * 0.96 / 12.0
		out.append(cos(ang) if want_cos else sin(ang))
	return out


## Converte um dicionário de alvos ABSOLUTOS em deltas sobre a pose neutra.
static func _abs(d: Dictionary) -> Dictionary:
	var n := _NEUTRAL
	var out := {}
	for k in d:
		out[k] = float(d[k]) - float(n.get(k, 0.0))
	return out


func _update(delta: float) -> void:
	_time += delta
	var an := animator
	an.update(delta, unit, null)
	var p := _NEUTRAL.duplicate()
	var t := _time

	# direção (giro suave, sem teleporte); na morte vira de lado para cair atravessado
	var target := _dir_yaw(an.dir, an.lateral)
	if an.dead:
		target = 70.0 * (1.0 if an.lateral >= 0.0 else -1.0)
	var diff := wrapf(target - _yaw, -180.0, 180.0)
	_yaw += clampf(diff, -turn_speed * delta, turn_speed * delta) if delta > 0.0 else diff
	_yaw = wrapf(_yaw, -180.0, 180.0)   # o sinal decide o espelho: nunca acumular voltas

	# IDLE: quase imóvel, respiração muito sutil
	var br := sin(t * TAU / 2.4 + _seed) * breathing
	var sway := sin(t * TAU / 4.8 + _seed * 0.7) * breathing
	var idle_w := 1.0 - an.move_w
	p = PaladinPoseLibrary.add(p, {rooty = -0.25 * br, lean = 0.6 * br, r_swing = 1.5 * br, l_swing = 1.0 * br, s_elev = 1.2 * br,
		rootx = 0.25 * sway, tab = 1.5 * sway, head_tilt = -0.6 * br}, idle_w)

	# WALK: passos curtos e pesados, pouco quique, escudo firme, espada com leve inércia
	var act := maxf(an.attack_w, an.defense_w)
	if an.move_w > 0.0:
		var th := an.walk_phase * TAU
		var s := sin(th)
		var w := an.move_w * (1.0 - act)
		p = PaladinPoseLibrary.add(p, {
			rf = step_length * s, lf = -step_length * s,
			rl = step_lift * maxf(0.0, cos(th)), ll = step_lift * maxf(0.0, -cos(th)),
			rooty = -0.7 * absf(cos(th)) + 0.3, crouch = 0.4, lean = 3.0,
			twist = 4.0 * s, r_swing = -7.0 * s, l_swing = 2.5 * s, s_elev = -3.0 * s,
			tab = 8.0 + 5.0 * s, head_turn = -2.0 * s,
		}, w)

	# DEFESA: provocação → guarda pronta (espera) → guarda com o Escudo Sagrado
	if an.defense_w > 0.0:
		var d: Dictionary
		if an.taunt_t >= 0.0:
			d = _taunt(clampf(an.taunt_t / PaladinPoseLibrary.TAUNT_TIME, 0.0, 1.0))
		else:
			if not _tracks.has(&"guard_ready"):
				_tracks[&"guard_ready"] = _abs(_GUARD_READY)
			d = PaladinPoseLibrary.mix_delta(_tracks[&"guard_ready"], _guard(t), an.guard_blend)
		p = PaladinPoseLibrary.add(p, d, an.defense_w * (1.0 - an.attack_w * 0.6))

	# ATAQUE: espada recua → quadril → tronco → ombro → braço → espada (cascata) → impacto no
	# evento real de dano → acompanhamento → recuperação
	if an.attack_w > 0.0:
		p = PaladinPoseLibrary.add(p, _attack(an.attack_p, an.attack_variant), an.attack_w)

	# reações curtas (somam e voltam sozinhas)
	if an.hit_t >= 0.0:
		var k := _pulse(an.hit_t / PaladinPoseLibrary.HIT_TIME, 0.25)
		p = PaladinPoseLibrary.add(p, {lean = -7.0, rootx = -1.3, crouch = 0.6, head_tilt = -8.0, r_swing = -8.0, l_swing = -6.0, tab = -6.0}, k)
	if an.block_t >= 0.0:
		var k := _pulse(an.block_t / PaladinPoseLibrary.BLOCK_TIME, 0.22)
		p = PaladinPoseLibrary.add(p, {sh_yaw = 16.0, sh_fwd = -1.6, l_elbow = 22.0, lean = -4.0, rootx = -0.9, crouch = 0.4, head_tilt = -5.0}, k)
	if an.push_t >= 0.0:
		p = PaladinPoseLibrary.add(p, _push(an.push_t / PaladinPoseLibrary.PUSH_TIME, an.push_dir))

	# MORTE: joelhos cedem, espada cai, escudo inclina, corpo cai pesado de costas
	if an.dead:
		p = PaladinPoseLibrary.mix(p, _death(clampf(an.death_t / PaladinPoseLibrary.DEATH_TIME, 0.0, 1.0)), clampf(an.death_t / 0.08, 0.0, 1.0))

	# brilho sagrado sutil na provocação e com o escudo ativo
	p.glow = maxf(float(p.glow), an.guard_blend * an.defense_w * 0.6)
	_pose = p

	_flash_t = maxf(0.0, _flash_t - delta)
	p_flash = (_flash_t / HIT_TIME) * 0.55
	p_dim = 0.26 * clampf(an.death_t / (PaladinPoseLibrary.DEATH_TIME + 0.3), 0.0, 1.0) if an.dead and an.preview_kind == &"" else 0.0
	for key in [&"_ring_t", &"_shield_up_t", &"_block_fx_t"]:
		var v: float = get(key)
		if v >= 0.0:
			v += delta
			set(key, v if v < 0.9 else -1.0)
	_parts = _build_parts(p)
	_update_drops(delta)
	_apply_frame()


func _dir_yaw(dir: int, lateral: float) -> float:
	var i: int = [0, 1, 2, 3, 4, 3, 2, 1][dir]
	var right := dir in [1, 2, 3] or (dir in [0, 4] and lateral >= 0.0)
	var y: float = DIR_YAW[i]
	return y if right else -y


# --- Clipes (deltas sobre a pose neutra) -------------------------------------------------

const _GUARD_READY := {crouch = 1.4, stance = 0.5, l_swing = 78.0, l_elbow = 18.0, sh_yaw = 0.0, sh_fwd = 2.2,
	twist = 8.0, r_swing = 32.0, r_elbow = 72.0, s_elev = 40.0, s_yaw = 50.0, lean = 2.0}


func _guard(t: float) -> Dictionary:
	var b := sin(t * TAU / 1.6) * breathing
	return _abs({crouch = 2.0 + 0.1 * b, stance = 0.7, l_swing = 82.0, l_elbow = 22.0, sh_yaw = -6.0, sh_fwd = 2.8,
		twist = 12.0, lean = 6.0 + 0.4 * b, r_swing = 44.0, r_elbow = 96.0, s_elev = 56.0, s_yaw = 45.0, head_tilt = 4.0,
		rf = 0.4, lf = 1.4})


func _taunt(p: float) -> Dictionary:
	if not _tracks.has(&"taunt"):
		_tracks[&"taunt"] = _taunt_keys()
	return PaladinPoseLibrary.track(_tracks[&"taunt"], p)


func _taunt_keys() -> Array:
	return [
		[0.0, {}, &"linear"],
		[0.2, _abs({crouch = 1.6, stance = 0.7}), &"out"],
		[0.42, _abs({crouch = 1.8, stance = 0.7, l_swing = 5.0, l_elbow = 95.0, sh_yaw = 42.0, twist = -8.0, lean = 1.0}), &"inout"],
		[0.58, _abs({crouch = 1.9, stance = 0.8, l_swing = 86.0, l_elbow = 8.0, sh_yaw = -4.0, sh_fwd = 3.2, twist = 12.0,
			lean = -3.0, r_swing = -8.0, r_abd = 38.0, r_elbow = 30.0, head_tilt = -6.0, glow = 1.0}), &"back"],
		[1.0, _abs(_GUARD_READY), &"inout"],
	]


func _attack(p: float, variant: StringName) -> Dictionary:
	var key := StringName("attack_" + String(variant))
	if not _tracks.has(key):
		_tracks[key] = _attack_keys(variant)
	var keys: Array = _tracks[key]
	var I := PaladinPoseLibrary.ATTACK_IMPACT
	var out := PaladinPoseLibrary.track(keys[0], p).duplicate()
	var a := PaladinPoseLibrary.track(keys[1], p - 0.025)
	var s := PaladinPoseLibrary.track(keys[2], p - 0.045)
	for k in a:
		out[k] = a[k]
	for k in s:
		out[k] = s[k]
	var hit := clampf(1.0 - absf(p - I) / 0.2, 0.0, 1.0)
	out[&"tab"] = -10.0 * hit
	return out


## Trilhas do golpe (corpo, braço, espada) por variante: constantes.
func _attack_keys(variant: StringName) -> Array:
	var I := PaladinPoseLibrary.ATTACK_IMPACT
	var body: Array
	var arm: Array
	var sword: Array
	match variant:
		&"overhead":   # alvo na diagonal de cima: golpe de cima para baixo
			body = [[0.0, {}, &"linear"], [0.34, _abs({twist = -8.0, lean = -6.0, rootx = -1.0, crouch = 0.9}), &"out"],
				[I, _abs({twist = 6.0, lean = 12.0, rootx = 1.8, crouch = 1.6}), &"in"], [0.62, _abs({twist = 8.0, lean = 14.0, rootx = 1.6, crouch = 1.7}), &"out"], [1.0, {}, &"inout"]]
			arm = [[0.0, {}, &"linear"], [0.34, _abs({r_swing = 172.0, r_elbow = 55.0, r_abd = 10.0}), &"out"],
				[I - 0.025, _abs({r_swing = 96.0, r_elbow = 6.0, r_abd = 8.0}), &"in"], [0.62, _abs({r_swing = 48.0, r_elbow = 20.0}), &"out"], [1.0, {}, &"inout"]]
			sword = [[0.0, {}, &"linear"], [0.34, _abs({s_elev = 125.0, s_yaw = 5.0}), &"out"],
				[I - 0.045, _abs({s_elev = 5.0, s_yaw = 0.0}), &"in"], [0.62, _abs({s_elev = -62.0, s_yaw = 5.0}), &"back"], [1.0, {}, &"inout"]]
		&"rising":   # alvo na diagonal de baixo: corte de baixo para cima
			body = [[0.0, {}, &"linear"], [0.34, _abs({twist = -14.0, lean = 9.0, rootx = -1.0, crouch = 1.8}), &"out"],
				[I, _abs({twist = 10.0, lean = 4.0, rootx = 1.6, crouch = 1.0}), &"in"], [0.62, _abs({twist = 14.0, lean = 0.0, rootx = 1.4, crouch = 0.8}), &"out"], [1.0, {}, &"inout"]]
			arm = [[0.0, {}, &"linear"], [0.34, _abs({r_swing = -25.0, r_elbow = 25.0, r_abd = 26.0}), &"out"],
				[I - 0.025, _abs({r_swing = 72.0, r_elbow = 8.0}), &"in"], [0.62, _abs({r_swing = 132.0, r_elbow = 22.0}), &"out"], [1.0, {}, &"inout"]]
			sword = [[0.0, {}, &"linear"], [0.34, _abs({s_elev = -70.0, s_yaw = 60.0}), &"out"],
				[I - 0.045, _abs({s_elev = 22.0, s_yaw = 0.0}), &"in"], [0.62, _abs({s_elev = 78.0, s_yaw = -10.0}), &"back"], [1.0, {}, &"inout"]]
		_:   # &"flat": alvo ao lado
			body = [[0.0, {}, &"linear"], [0.34, _abs({twist = -16.0, lean = -4.0, rootx = -1.2, crouch = 1.0}), &"out"],
				[I, _abs({twist = 12.0, lean = 9.0, rootx = 2.0, crouch = 1.5}), &"in"], [0.62, _abs({twist = 16.0, lean = 10.0, rootx = 1.8, crouch = 1.5}), &"out"], [1.0, {}, &"inout"]]
			arm = [[0.0, {}, &"linear"], [0.34, _abs({r_swing = 148.0, r_elbow = 62.0, r_abd = 22.0}), &"out"],
				[I - 0.025, _abs({r_swing = 88.0, r_elbow = 4.0, r_abd = 12.0}), &"in"], [0.62, _abs({r_swing = 58.0, r_elbow = 18.0, r_abd = -5.0}), &"out"], [1.0, {}, &"inout"]]
			sword = [[0.0, {}, &"linear"], [0.34, _abs({s_elev = 118.0, s_yaw = 40.0}), &"out"],
				[I - 0.045, _abs({s_elev = -4.0, s_yaw = 0.0}), &"in"], [0.62, _abs({s_elev = -52.0, s_yaw = -35.0}), &"back"], [1.0, {}, &"inout"]]
	return [body, arm, sword]


## Empurrão: o centro de gravidade quebra na direção do empurrão e o pé de trás busca apoio.
## `dir` no espaço do corpo (x = esquerda, z = frente). Nenhum deslocamento: só postura.
func _push(p: float, dir: Vector3) -> Dictionary:
	var k := _pulse(p, 0.28)
	var step := sin(clampf((p - 0.15) / 0.5, 0.0, 1.0) * PI)
	var d := {lean = dir.z * 14.0 * k, rootx = dir.z * 3.2 * k, crouch = 1.0 * k, head_tilt = -dir.z * 8.0 * k,
		twist = -dir.x * 10.0 * k, l_swing = -dir.z * 14.0 * k, r_swing = -dir.z * 10.0 * k, tab = -dir.z * 12.0 * k}
	if dir.z < 0.0:
		d[&"rf"] = -4.0 * step
		d[&"rl"] = 1.6 * step
	else:
		d[&"lf"] = 4.0 * step
		d[&"ll"] = 1.6 * step
	return d


## Morte pesada (pose absoluta). `tilt` gira o corpo inteiro em volta dos pés (cair de costas).
func _death(p: float) -> Dictionary:
	if not _tracks.has(&"death"):
		_tracks[&"death"] = _death_keys()
	var keys: Array = _tracks[&"death"]
	for i in range(1, keys.size()):
		if p <= keys[i][0]:
			var u: float = (p - keys[i - 1][0]) / (keys[i][0] - keys[i - 1][0])
			return PaladinPoseLibrary.mix(keys[i - 1][1], keys[i][1], PaladinPoseLibrary.ease_by(keys[i][2], u))
	return keys[keys.size() - 1][1]


## Poses-chave da morte (constantes).
func _death_keys() -> Array:
	var n := _NEUTRAL
	var fatal := PaladinPoseLibrary.add(n, _abs({lean = -9.0, head_tilt = -12.0, rootx = -1.0, crouch = 1.0, r_swing = 10.0, l_swing = 25.0}))
	var kneel := PaladinPoseLibrary.add(n, _abs({crouch = 6.5, stance = 0.6, lean = 16.0, head_tilt = 14.0, r_swing = 8.0, r_elbow = 10.0,
		s_elev = -80.0, l_swing = 12.0, l_elbow = 20.0, sh_yaw = 45.0, rf = 2.5, lf = -2.5}))
	var tip := PaladinPoseLibrary.add(kneel, {tilt = 40.0, lean = -10.0, head_tilt = -14.0})
	var ground := PaladinPoseLibrary.add(n, _abs({tilt = 88.0, crouch = 2.0, lean = -6.0, head_tilt = -10.0, r_swing = 150.0, r_elbow = 10.0,
		l_swing = 140.0, l_elbow = 20.0, rf = 3.0, lf = 1.0, rl = 1.5, tab = 25.0}))
	var bounce := PaladinPoseLibrary.add(ground, {tilt = -5.0})
	return [[0.0, n, &"linear"], [0.11, fatal, &"out"], [0.42, kneel, &"inout"], [0.62, tip, &"in"],
		[0.8, ground, &"in"], [0.87, bounce, &"out"], [1.0, ground, &"inout"]]


static func _pulse(p: float, peak: float) -> float:
	if p <= 0.0 or p >= 1.0:
		return 0.0
	if p < peak:
		return PaladinPoseLibrary.ease_by(&"out", p / peak)
	return 1.0 - PaladinPoseLibrary.ease_by(&"inout", (p - peak) / (1.0 - peak))


## Espada e escudo se soltam na queda e param no chão ao lado do corpo (sem girar com ele).
func _update_drops(delta: float) -> void:
	var an := animator
	if not an.dead:
		return
	var dp := an.death_t / PaladinPoseLibrary.DEATH_TIME
	var fs := 1.0 if _yaw >= 0.0 else -1.0
	if _sword_drop.is_empty() and dp >= 0.4 and anchors.has(&"sword_grip"):
		var g: Vector2 = anchors.sword_grip
		var ang: float = anchors.sword_ang
		_sword_drop = {from = Vector2(g.x * fs, g.y), from_ang = ang if fs > 0.0 else PI - ang, t = 0.0,
			to = Vector2(-fs * 20.0, 3.0), to_ang = 0.0 if fs > 0.0 else PI}
	if _shield_drop.is_empty() and dp >= 0.5 and anchors.has(&"shield_c"):
		var c: Vector2 = anchors.shield_c
		_shield_drop = {from = Vector2(c.x * fs, c.y), t = 0.0, to = Vector2(fs * 17.0, 0.6)}
	for d in [_sword_drop, _shield_drop]:
		if not d.is_empty():
			d.t += delta


# --- Projeção (fake 2.5D leve) -----------------------------------------------------------

## Ponto do corpo (L esquerda, F frente, Y altura) → tela do rig (x, y) + profundidade (z, + = perto).
static func _proj(l: float, f: float, y: float, yaw_deg: float) -> Vector3:
	var a := deg_to_rad(yaw_deg)
	var x := l * cos(a) + f * sin(a)
	var d := -l * sin(a) + f * cos(a)
	return Vector3(x, -y + d * DEPTH_Y, d)


static func _v2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.y)


# --- Desenho leve: peças prontas + ossos -----------------------------------------------------
## Cada parte do Paladino é uma PEÇA PRONTA num espaço canônico, montada uma vez por tipo, e a pose
## do quadro vira transformações de ossos (LiteSkin):
##   - peças planas do corpo (túnica, tabardo) seguem a projeção fake 2.5D EXATA (é afim para um
##     plano: o osso sai de três pontos projetados);
##   - membros, espada e ombreiras são peças esticadas entre as articulações (montadas no comprimento
##     real, então a borda não engrossa);
##   - peito, elmo, auréola e escudo: largura pelo giro (escala horizontal), como antes;
##   - variantes que dependem do giro (frente/costas do peito, visor/crista, face/verso do escudo,
##     tabardo da frente/de trás) entram na malha só quando visíveis.
## A ordem por profundidade continua por quadro: a malha é escolhida pela ORDEM das partes (uma por
## ordem, em cache por tipo); a ordem só muda quando o Paladino gira ou numa pose grande.

enum {
	B_GROUND, B_TAUNT_RING, B_GROUND_ARC,
	B_LEG_R_THIGH, B_LEG_R_SHIN, B_LEG_R_BOOT, B_LEG_R_KNEE,
	B_LEG_L_THIGH, B_LEG_L_SHIN, B_LEG_L_BOOT, B_LEG_L_KNEE,
	B_ROBE, B_TAB_FRONT, B_TAB_BACK,
	B_TORSO, B_TORSO_FRONT, B_TORSO_BACK, B_BUCKLE,
	B_HEAD, B_VISOR, B_CREST, B_HALO, B_HALO_GLOW,
	B_ARM_R_UPPER, B_ARM_R_FORE, B_ARM_R_ELBOW, B_ARM_R_HAND, B_PAULDRON_R,
	B_ARM_L_UPPER, B_ARM_L_FORE, B_ARM_L_ELBOW, B_ARM_L_HAND, B_PAULDRON_L,
	B_SWORD, B_SHIELD_EDGE, B_SHIELD, B_SWORD_DROP, B_SHIELD_DROP,
	B_HOLY_ARC, B_SHIELD_UP, B_SPARK, B_COUNT = B_SPARK + 5,
}
## Tamanhos canônicos das peças (unidades do rig).
const THIGH_L := 6.9
const SHIN_L := 6.0
const UPPER_L := 5.4
const FORE_L := 5.2
const TORSO_W := 9.0
const TAB_H := 11.4
const GROUND_ARC_R := 20.0
const SHIELD_UP_R := 11.0

## Grupos (partes do desenho original) do quadro, em ordem de profundidade: ids inteiros (ver G_*).
## Cada id tem a lista de [peça, osso] já resolvida (_group_parts); a ordem decide a malha.
enum { G_LEG_R, G_LEG_L, G_ROBE, G_TAB_F, G_TAB_B, G_HALO, G_ARM_R, G_ARM_L, G_PAUL_R, G_PAUL_L, G_SWORD,
	G_SHIELD_F, G_SHIELD_B, G_TORSO = 100, G_HEAD = 200 }
var _groups := PackedInt32Array()
var _order := PackedInt32Array()
var _depths := PackedFloat64Array()
var _sort_keys := PackedInt64Array()
var _layout_ids := PackedInt32Array([-1])
var _group_parts := {}
var _bones: Array[Transform2D] = []
var _part_bodies := {}


func _bake_salt() -> String:
	return "%.2f|%.2f|%.2f|%.2f" % [body_width, shield_scale, sword_scale, head_scale]


## Peça pronta pelo nome (as funções de montagem ficam em _part_bodies).
func _piece(key: String) -> LitePart:
	return _part(key, _part_bodies[key], false, not key.begins_with("fx_"))


func _init_parts() -> void:
	var hs := head_scale
	var bw := body_width
	_part_bodies = {
		"ground": func(): _disc(Vector2.ZERO, 12.5, Color(0, 0, 0, 0.32)),
		"fx_taunt_ring": func(): _bake.arc(Vector2.ZERO, PaladinTaunt.TAUNT_RADIUS, 0.0, TAU, 64, Color(Color("f0c674"), 0.4), 1.6),
		"fx_ground_arc": func(): _bake.arc(Vector2.ZERO, GROUND_ARC_R, 0.0, TAU, 40, Color(gold_light, 0.35), 1.6),
		"thigh_r": _bake_limb.bind(THIGH_L, 3.3, 2.9, ivory, 1.0), "thigh_l": _bake_limb.bind(THIGH_L, 3.3, 2.9, ivory, 0.85),
		"shin_r": _bake_shin.bind(1.0), "shin_l": _bake_shin.bind(0.85),
		"boot_r": _bake_boot.bind(1.0), "boot_l": _bake_boot.bind(0.85),
		"knee_r": _bake_knee.bind(1.0), "knee_l": _bake_knee.bind(0.85),
		"robe": func():
			var pts := PackedVector2Array()
			for c in [[-3.0, 15.0], [3.0, 15.0], [3.6, 6.0], [-3.6, 6.0]]:
				pts.append(Vector2(c[0] * bw, -c[1]))
			_poly(pts, _c(dark)),
		"tab_front": _bake_tabard.bind(true), "tab_back": _bake_tabard.bind(false),
		"torso": _bake_torso, "torso_side": _bake_torso_side, "torso_hi": _bake_torso_hi,
		"torso_front": _bake_torso_front, "torso_back": _bake_torso_back, "torso_belt": _bake_torso_belt,
		"buckle": func():
			_poly(PackedVector2Array([Vector2(-1.8, -1.6), Vector2(1.8, -1.6), Vector2(1.8, 1.6), Vector2(-1.8, 1.6)]), _c(gold_light))
			_disc(Vector2.ZERO, 0.7, _c(gold_dark)),
		"torso_frald": func():
			var w := TORSO_W
			_fill(PackedVector2Array([Vector2(-w * 0.8, 6.0), Vector2(w * 0.8, 6.0), Vector2(w * 0.86, 8.4), Vector2(-w * 0.86, 8.4)]), _c(ivory_shade)),
		"helm": _bake_helm, "helm_shade_l": _bake_helm_shade.bind(-1.0), "helm_shade_r": _bake_helm_shade.bind(1.0),
		"helm_top": _bake_helm_top, "visor": _bake_visor, "crest": func():
			_line(Vector2(0, -11.4 * hs * 0.97), Vector2(0, -11.4 * hs * 0.1), _c(gold), 1.2),
		"halo": _bake_halo, "fx_halo_glow": func(): _disc(Vector2.ZERO, 1.0, Color(holy, 0.18)),
		"upper_r": _bake_limb.bind(UPPER_L, 2.4, 2.2, ivory_shade, 1.0), "upper_l": _bake_limb.bind(UPPER_L, 2.4, 2.2, ivory_shade, 0.82),
		"fore_r": _bake_fore.bind(1.0), "fore_l": _bake_fore.bind(0.82),
		"elbow_r": _bake_elbow.bind(1.0), "elbow_l": _bake_elbow.bind(0.82),
		"hand_r": func(): _circle(Vector2.ZERO, 2.1, _c(leather, 1.0)),
		"hand_l": func(): _circle(Vector2.ZERO, 2.1, _c(leather, 0.82)),
		"pauldron_r": _bake_pauldron.bind(1.0), "pauldron_l": _bake_pauldron.bind(0.82),
		"sword": _bake_sword, "shield_edge": func(): _poly(_shield_outer(), _c(gold_dark)),
		"shield_front": _bake_shield.bind(true), "shield_back": _bake_shield.bind(false), "shield_drop": _bake_shield_drop,
		"fx_holy_arc": func(): _bake.arc(Vector2.ZERO, 11.0 * RIG_SCALE * shield_scale, 0.0, TAU, 32, Color(holy, 0.3), 1.4),
		"fx_shield_up": func(): _bake.arc(Vector2.ZERO, SHIELD_UP_R, 0.0, TAU, 32, Color(gold_light, 0.7), 1.4),
		"fx_spark": func(): _bake.line(Vector2.ZERO, Vector2(1, 0), Color(gold_light, 0.9), 1.2),
	}
	_bones.resize(B_COUNT)
	for i in B_COUNT:
		_bones[i] = LiteSkin.HIDDEN
	_skin = LiteSkin.new(B_COUNT)
	_skin.attach(self)
	set_notify_transform(true)


## Os ossos do quadro vão para o esqueleto; se a ordem/visibilidade das partes mudou, troca a malha.
func _apply_frame() -> void:
	if _skin == null:
		return
	if _groups != _layout_ids:
		_layout_ids = _groups.duplicate()
		var layout := [[_piece("fx_taunt_ring"), B_TAUNT_RING], [_piece("fx_ground_arc"), B_GROUND_ARC], [_piece("ground"), B_GROUND]]
		for g in _groups:
			layout.append_array(_parts_of(g))
		layout.append([_piece("shield_drop"), B_SHIELD_DROP])
		layout.append([_piece("sword"), B_SWORD_DROP])
		layout.append([_piece("fx_holy_arc"), B_HOLY_ARC])
		layout.append([_piece("fx_shield_up"), B_SHIELD_UP])
		var spark := _piece("fx_spark")
		for i in 5:
			layout.append([spark, B_SPARK + i])
		var key := PackedStringArray()
		for g in _groups:
			key.append(str(g))
		_mesh = LiteSkin.mesh(_bake_prefix + "mesh|" + ",".join(key), layout)
		queue_redraw()
	for i in B_COUNT:
		_skin.set_bone(i, _bones[i])
	_apply_fx()


## [peça, osso] do grupo `g` (resolvido uma vez).
func _parts_of(g: int) -> Array:
	var out: Array = _group_parts.get(g, [])
	if not out.is_empty():
		return out
	match g:
		G_LEG_R, G_LEG_L:
			var k := "r" if g == G_LEG_R else "l"
			var b0 := B_LEG_R_THIGH if g == G_LEG_R else B_LEG_L_THIGH
			out = [[_piece("thigh_" + k), b0], [_piece("shin_" + k), b0 + 1], [_piece("boot_" + k), b0 + 2], [_piece("knee_" + k), b0 + 3]]
		G_ROBE:
			out = [[_piece("robe"), B_ROBE]]
		G_TAB_F:
			out = [[_piece("tab_front"), B_TAB_FRONT]]
		G_TAB_B:
			out = [[_piece("tab_back"), B_TAB_BACK]]
		G_HALO:
			out = [[_piece("fx_halo_glow"), B_HALO_GLOW], [_piece("halo"), B_HALO]]
		G_ARM_R, G_ARM_L:
			var k := "r" if g == G_ARM_R else "l"
			var b0 := B_ARM_R_UPPER if g == G_ARM_R else B_ARM_L_UPPER
			out = [[_piece("upper_" + k), b0], [_piece("fore_" + k), b0 + 1], [_piece("elbow_" + k), b0 + 2], [_piece("hand_" + k), b0 + 3]]
		G_PAUL_R:
			out = [[_piece("pauldron_r"), B_PAULDRON_R]]
		G_PAUL_L:
			out = [[_piece("pauldron_l"), B_PAULDRON_L]]
		G_SWORD:
			out = [[_piece("sword"), B_SWORD]]
		G_SHIELD_F, G_SHIELD_B:
			out = [[_piece("shield_edge"), B_SHIELD_EDGE], [_piece("shield_front" if g == G_SHIELD_F else "shield_back"), B_SHIELD]]
		_:
			if g >= G_HEAD:   # bits: 1 = sombra do lado direito, 2 = visor (senão crista)
				var f := g - G_HEAD
				out = [[_piece("helm"), B_HEAD], [_piece("helm_shade_r" if f & 1 else "helm_shade_l"), B_HEAD], [_piece("helm_top"), B_HEAD]]
				out.append([_piece("visor"), B_VISOR] if f & 2 else [_piece("crest"), B_CREST])
			else:             # tronco — bits: 1 = lado, 2 = frente (senão costas), 4 = fivela
				var f := g - G_TORSO
				out = [[_piece("torso"), B_TORSO]]
				if f & 1:
					out.append([_piece("torso_side"), B_TORSO])
				out.append([_piece("torso_hi"), B_TORSO])
				out.append([_piece("torso_front"), B_TORSO_FRONT] if f & 2 else [_piece("torso_back"), B_TORSO_BACK])
				out.append([_piece("torso_belt"), B_TORSO])
				if f & 4:
					out.append([_piece("buckle"), B_BUCKLE])
				out.append([_piece("torso_frald"), B_TORSO])
	_group_parts[g] = out
	return out


func _draw() -> void:
	_skin_draw()
	_draw_debug()


## Osso de uma peça montada ao longo de +x com `length` unidades, esticada de `a` até `b`.
static func _limb(a: Vector2, b: Vector2, length: float) -> Transform2D:
	var d := b - a
	var n := d.orthogonal().normalized() if d.length() > 0.001 else Vector2(0, -1)
	return Transform2D(d / length, n, a)


## Osso de uma peça PLANA do corpo. A peça é montada em (u, v) e o ponto 3D (L, F, Y) do corpo é
## afim em (u, v): L = u; F = f0 + fv·v; Y = y0 + yv·v. A projeção (_proj) também é afim, então o osso
## sai exato de três pontos: origem, u = 1 e v = 1.
static func _plane_bone(f0: float, fv: float, y0: float, yv: float, yaw: float) -> Transform2D:
	var o := _proj(0.0, f0, y0, yaw)
	var pu := _proj(1.0, f0, y0, yaw)
	var pv := _proj(0.0, f0 + fv, y0 + yv, yaw)
	return Transform2D(Vector2(pu.x - o.x, pu.y - o.y), Vector2(pv.x - o.x, pv.y - o.y), Vector2(o.x, o.y))


func _build_parts(p: Dictionary) -> Array:
	var a := absf(_yaw)          # a pose é sempre montada na vista da direita; o desenho espelha
	var mirrored := _yaw < 0.0
	# no golpe o corpo gira para o perfil (a lâmina corre de lado, sem sumir atrás do escudo)
	if not animator.dead:
		a += (90.0 - a) * 0.45 * animator.attack_w
	var au := a + float(p.twist)
	var ah := au + float(p.head_turn)
	var ca := cos(deg_to_rad(a))
	var bw := body_width
	var crouch: float = p.crouch
	var lean_x := float(p.lean) * 0.09          # inclinação: o tronco avança na direção da frente
	var up_f := lean_x                           # frente do tronco (unidades F) por causa da inclinação
	var fs := 1.0 if _yaw >= 0.0 else -1.0
	var root := Transform2D(0.0, BODY_SCALE * RIG_SCALE, 0.0, Vector2(0, FOOT_Y))
	var body := root * Transform2D(0.0, Vector2(fs, 1.0), 0.0, Vector2.ZERO) * Transform2D(deg_to_rad(-float(p.tilt)), Vector2(float(p.rootx), float(p.rooty)))
	_body_xf = body
	_groups.resize(0)
	_depths.resize(0)
	var A := {}
	var bn := _bones

	# --- pernas (yaw do quadril) ---
	for side in [RIGHT, LEFT]:
		var key := "r" if side < 0 else "l"
		var hip := Vector3(side * 4.0 * bw, 13.4 - crouch, 0.0)
		var foot := Vector3(side * (7.0 + float(p.stance)) * bw, float(p[key + "l"]), float(p[key + "f"]))
		var dist := Vector2(hip.x - foot.x, hip.y - foot.y).length()
		var knee_push := sqrt(maxf(0.0, 6.9 * 6.9 - dist * dist / 4.0))
		var knee := (hip + foot) / 2.0 + Vector3(side * knee_push * 0.25, 0, knee_push * 0.85)
		var ph := _proj(hip.x, hip.z, hip.y, a)
		var pk := _proj(knee.x, knee.z, knee.y, a)
		var pf := _proj(foot.x, foot.z, foot.y, a)
		var b0 := B_LEG_R_THIGH if side < 0 else B_LEG_L_THIGH
		bn[b0] = body * _limb(_v2(ph), _v2(pk), THIGH_L)
		bn[b0 + 1] = body * _limb(_v2(pk), _v2(pf) + Vector2(0, -1.4), SHIN_L)
		bn[b0 + 2] = body * Transform2D(0.0, _v2(pf))
		bn[b0 + 3] = body * Transform2D(0.0, _v2(pk))
		_group(G_LEG_R if side < 0 else G_LEG_L, ph.z - 0.5)
	# túnica escura entre as pernas (atrás do tabardo): plano F = −0,6
	bn[B_ROBE] = body * _plane_bone(-0.6, 0.0, -crouch, -1.0, a)
	_group(G_ROBE, -1.5)
	# tabardo: frente (com a estrela) e verso; a barra balança para a frente/trás (plano inclinado)
	var tab: float = p.tab
	var top := 15.0 - crouch
	var bot := 3.6 - crouch * 0.5
	var ky := (top - bot) / TAB_H
	for front in [true, false]:
		if (front and ca > -0.35) or (not front and ca < 0.35):
			var f := 5.0 if front else -4.2
			var sw := (tab if front else -tab) * 0.06
			var bone := B_TAB_FRONT if front else B_TAB_BACK
			# A capa reutiliza a peça/osso traseiro: nenhum nó ou passe adicional.
			var cape_top := 27.0 - crouch
			bn[bone] = body * _plane_bone(f, sw / TAB_H, top if front else cape_top, -ky if front else -(cape_top - bot) / TAB_H, a)
			_group(G_TAB_F if front else G_TAB_B, (4.8 * ca + 0.8) if front else (-4.2 * ca - 0.8))

	# --- tronco (yaw do tronco) ---
	var c := cos(deg_to_rad(au))
	var s := sin(deg_to_rad(au))
	var tw := 8.6 * bw * (0.84 + 0.16 * absf(c))
	var cx := _proj(up_f, 1.0, 21.0 - crouch, au)
	var o := Vector2(cx.x, cx.y)
	var tsx := Vector2(tw / TORSO_W, 0.0)
	bn[B_TORSO] = body * Transform2D(tsx, Vector2(0, 1), o)
	var tf := 0
	if absf(s) > 0.3:
		tf |= 1
	if c > 0.12:
		bn[B_TORSO_FRONT] = body * Transform2D(tsx, Vector2(0, 1), o + Vector2(s * tw * 0.35, 0))
		tf |= 2
	else:
		bn[B_TORSO_BACK] = body * Transform2D(tsx, Vector2(0, 1), o + Vector2(s * tw * 0.3, 0))
	if c > 0.1:
		bn[B_BUCKLE] = body * Transform2D(0.0, o + Vector2(s * tw * 0.4, 4.9))
		tf |= 4
	_group(G_TORSO + tf, 0.0)
	# --- cabeça e auréola ---
	var neck := _proj(up_f * 1.4, 0.3, 28.4 - crouch, au)
	A[&"head"] = _v2(neck) + Vector2(0, -6.0)
	A[&"helmet_top"] = _v2(neck) + Vector2(0, -11.4 * head_scale)
	var hc_ := cos(deg_to_rad(ah))
	var hs_ := sin(deg_to_rad(ah))
	var head_xf := body * Transform2D(deg_to_rad(float(p.head_tilt) * signf(hs_ + 0.0001)), _v2(neck))
	var hw := 5.8 * head_scale * (0.9 + 0.1 * absf(hc_))
	var hw0 := 5.8 * head_scale * 0.95
	bn[B_HEAD] = head_xf * Transform2D(Vector2(hw / hw0, 0), Vector2(0, 1), Vector2.ZERO)
	var back := -signf(hs_) if absf(hs_) > 0.25 else 1.0
	var vx := hs_ * hw * 0.62
	var hf := 0 if back < 0.0 else 1
	if hc_ > -0.25:
		var vk := clampf(hc_ * 0.75 + 0.45, 0.35, 1.0)
		bn[B_VISOR] = head_xf * Transform2D(Vector2(vk, 0), Vector2(0, 1), Vector2(vx, 0))
		hf |= 2
	else:
		bn[B_CREST] = head_xf * Transform2D(0.0, Vector2(-vx * 0.4, 0))
	_group(G_HEAD + hf, 1.6)
	var hc := _proj(up_f * 1.4, -3.2, 37.0 - crouch, ah)
	var halo_depth := -3.2 * hc_ + (1.6 if hc_ < 0.0 else 0.0)
	A[&"halo"] = _v2(hc)
	var hk := 0.78 + 0.22 * absf(hc_)
	bn[B_HALO] = body * Transform2D(Vector2(hk, 0), Vector2(0, 1), _v2(hc))
	var glow := float(p.glow)
	var gr := (7.0 * head_scale + 2.5)
	bn[B_HALO_GLOW] = body * Transform2D(0.0, Vector2(gr, gr), 0.0, _v2(hc)) if glow > 0.05 else LiteSkin.HIDDEN
	_group(G_HALO, halo_depth)

	# --- braços, ombreiras, espada (direito) e escudo (esquerdo) ---
	for side in [RIGHT, LEFT]:
		var key := "r" if side < 0 else "l"
		var sh3 := Vector3(side * 8.4 * bw, 25.4 - crouch, up_f * 1.2 - 0.3)
		var sw := deg_to_rad(float(p[key + "_swing"]))
		var ab := deg_to_rad(float(p[key + "_abd"]))
		var el := deg_to_rad(float(p[key + "_elbow"]))
		var d1 := Vector3(side * sin(ab), -cos(sw) * cos(ab), sin(sw) * cos(ab))
		var elbow := sh3 + d1 * 5.4
		var sw2 := sw + el
		var d2 := Vector3(side * sin(ab) * 0.6, -cos(sw2), sin(sw2)).normalized()
		var hand := elbow + d2 * 5.2
		var ps := _proj(sh3.x, sh3.z, sh3.y, au)
		var pe := _proj(elbow.x, elbow.z, elbow.y, au)
		var ph := _proj(hand.x, hand.z, hand.y, au)
		var b0 := B_ARM_R_UPPER if side < 0 else B_ARM_L_UPPER
		bn[b0] = body * _limb(_v2(ps), _v2(pe), UPPER_L)
		bn[b0 + 1] = body * _limb(_v2(pe), _v2(ph), FORE_L)
		bn[b0 + 2] = body * Transform2D(0.0, _v2(pe))
		bn[b0 + 3] = body * Transform2D(0.0, _v2(ph))
		_group(G_ARM_R if side < 0 else G_ARM_L, (ps.z + ph.z) * 0.5 + 0.2)
		var pd := _proj(sh3.x * 1.05, sh3.z, sh3.y + 1.2, au)
		var pk := 0.85 + 0.15 * absf(cos(deg_to_rad(au)))
		bn[b0 + 4] = body * Transform2D(Vector2(pk / 0.92, 0), Vector2(0, 1), _v2(pd))
		_group(G_PAUL_R if side < 0 else G_PAUL_L, ps.z + 0.6 + (0.0 if ps.z >= 0.0 else -0.4))
		A[StringName(key + "_hand")] = _v2(ph)
		A[StringName(key + "_hand3")] = hand
		A[StringName(key + "_shoulder")] = _v2(ps)
		if side < 0:
			# espada: da mão direita; direção da lâmina no espaço do corpo
			var e := deg_to_rad(float(p.s_elev))
			var yw := deg_to_rad(float(p.s_yaw))
			var dir := Vector3(-cos(e) * sin(yw), sin(e), cos(e) * cos(yw))
			var tip := hand + dir * 15.5 * sword_scale
			var pt := _proj(tip.x, tip.z, tip.y, au)
			var pg := _proj(hand.x, hand.z, hand.y, au)
			A[&"sword_grip"] = _v2(pg)
			A[&"sword_grip3"] = hand
			A[&"sword_tip3"] = tip
			A[&"sword_tip"] = _v2(pt)
			A[&"sword_ang"] = (_v2(pt) - _v2(pg)).angle()
			if _sword_drop.is_empty():
				bn[B_SWORD] = body * _limb(_v2(pg), _v2(pt), 15.5 * sword_scale)
				_group(G_SWORD, pg.z + 0.9)
		else:
			# escudo: preso ao braço esquerdo, à frente da mão
			var c3 := hand + Vector3(-1.6, -1.0, 2.6 + float(p.sh_fwd))
			var pc := _proj(c3.x, c3.z, c3.y, au)
			var front_view := cos(deg_to_rad(au)) >= 0.0
			var view_ang := (au if front_view else signf(au) * (180.0 - absf(au))) * 0.4 + (float(p.sh_yaw) - 18.0) * 0.8
			var face := cos(deg_to_rad(view_ang)) * (1.0 if front_view else -1.0)
			if mirrored and front_view:
				face = -absf(face)
			var fwd_x := sin(deg_to_rad(au))
			A[&"shield_c"] = _v2(pc)
			A[&"shield_c3"] = c3
			A[&"shield_face"] = face
			if _shield_drop.is_empty():
				var arm_z := (ps.z + ph.z) * 0.5 + 0.2
				var sz := pc.z + 1.4 + (1.0 if face > 0.0 else -1.2)
				if mirrored and front_view:
					sz = minf(arm_z - 0.3, -0.3)
				var k := shield_scale
				var sxf := Transform2D(deg_to_rad(float(p.lean) * 0.4 * signf(fwd_x + 0.0001)), Vector2(maxf(absf(face), 0.22) * k, k), 0.0, _v2(pc))
				var edge := 1.6 * (1.0 - absf(face)) * signf(-fwd_x if face >= 0.0 else fwd_x)
				bn[B_SHIELD_EDGE] = body * Transform2D(0.0, Vector2(edge, 0.0)) * sxf
				bn[B_SHIELD] = body * sxf
				_group(G_SHIELD_F if face >= 0.0 else G_SHIELD_B, sz)
	anchors = A
	# ordem por profundidade (estável: empate mantém a ordem de montagem); ordenação nativa por chave
	var n := _depths.size()
	_sort_keys.resize(n)
	for i in n:
		_sort_keys[i] = int((_depths[i] + 1000.0) * 4096.0) * 64 + i
	_sort_keys.sort()
	_order.resize(n)
	for i in n:
		_order[i] = _groups[_sort_keys[i] & 63]
	var tmp := _groups
	_groups = _order
	_order = tmp
	_pose_extras(root)
	return Array(_groups)


func _group(id: int, depth: float) -> void:
	_groups.append(id)
	_depths.append(depth)


## Sombra no chão, espada e escudo soltos (morte) e efeitos da habilidade.
func _pose_extras(root: Transform2D) -> void:
	var bn := _bones
	var fs := 1.0 if _yaw >= 0.0 else -1.0
	var lying := clampf(float(_pose.get(&"tilt", 0.0)) / 88.0, 0.0, 1.0)
	bn[B_GROUND] = Transform2D(0.0, Vector2(1.0 + lying * 1.3, 0.32), 0.0, Vector2(-14.0 * lying * RIG_SCALE * fs, FOOT_Y))
	# espada e escudo soltos (no espaço da raiz, não caem junto com o corpo)
	bn[B_SHIELD_DROP] = LiteSkin.HIDDEN
	bn[B_SWORD_DROP] = LiteSkin.HIDDEN
	if not _shield_drop.is_empty():
		var u := clampf(float(_shield_drop.t) / 0.42, 0.0, 1.0)
		var pos: Vector2 = (_shield_drop.from as Vector2).lerp(_shield_drop.to, u)
		pos.y = lerpf((_shield_drop.from as Vector2).y, (_shield_drop.to as Vector2).y, u * u)
		var flat := lerpf(1.0, 0.5, u * u)
		bn[B_SHIELD_DROP] = root * Transform2D(deg_to_rad(-12.0 * fs * u), Vector2(shield_scale, shield_scale * flat), 0.0, pos)
	if not _sword_drop.is_empty():
		var u := clampf(float(_sword_drop.t) / 0.36, 0.0, 1.0)
		var pos: Vector2 = (_sword_drop.from as Vector2).lerp(_sword_drop.to, u)
		pos.y = lerpf((_sword_drop.from as Vector2).y, (_sword_drop.to as Vector2).y, u * u)
		if u >= 1.0:
			var b := clampf((float(_sword_drop.t) - 0.36) / 0.16, 0.0, 1.0)
			pos.y -= sin(b * PI) * 1.1 * (1.0 - b)
		var ang := lerp_angle(float(_sword_drop.from_ang), float(_sword_drop.to_ang), PaladinPoseLibrary.ease_by(&"out", u))
		bn[B_SWORD_DROP] = root * _limb(pos, pos + Vector2.from_angle(ang) * 15.5 * sword_scale * (0.75 + 0.25 * u), 15.5 * sword_scale)
	# efeitos por baixo: anel no raio real da provocação + onda dourada no chão
	bn[B_TAUNT_RING] = LiteSkin.HIDDEN
	bn[B_GROUND_ARC] = LiteSkin.HIDDEN
	if _ring_t >= 0.0:
		if _ring_t <= PaladinFx.TAUNT_RING_TIME:
			var k := clampf(_ring_t / PaladinFx.TAUNT_RING_TIME, 0.0, 1.0)
			var tr := lerpf(0.35, 1.0, 1.0 - (1.0 - k) * (1.0 - k)) * (1.0 if k < 0.9 else 0.0)
			bn[B_TAUNT_RING] = Transform2D(0.0, Vector2(tr, tr), 0.0, Vector2.ZERO)
		var p := _ring_t / 0.9
		var r := lerpf(10.0, 30.0, ease(clampf(p / 0.6, 0.0, 1.0), 0.4)) / GROUND_ARC_R
		if p < 0.85:
			bn[B_GROUND_ARC] = Transform2D(0.0, Vector2(r, r * 0.36), 0.0, Vector2(0, FOOT_Y))
	# efeitos por cima: contorno do Escudo Sagrado, anel ao subir, faíscas do bloqueio
	bn[B_HOLY_ARC] = LiteSkin.HIDDEN
	bn[B_SHIELD_UP] = LiteSkin.HIDDEN
	for i in 5:
		bn[B_SPARK + i] = LiteSkin.HIDDEN
	if anchors.has(&"shield_c") and _shield_drop.is_empty():
		var sc: Vector2 = _body_xf * (anchors.shield_c as Vector2)
		var g := animator.guard_blend * animator.defense_w
		if g > 0.05:
			var pulse := 0.97 + 0.03 * sin(_time * 5.0)
			bn[B_HOLY_ARC] = Transform2D(0.0, Vector2(pulse, pulse), 0.0, sc)
		if _shield_up_t >= 0.0 and _shield_up_t < 0.35:
			var p := _shield_up_t / 0.35
			var r := lerpf(6.0, 16.0, ease(p, 0.4)) / SHIELD_UP_R
			bn[B_SHIELD_UP] = Transform2D(0.0, Vector2(r, r), 0.0, sc)
		if _block_fx_t >= 0.0 and _block_fx_t < 0.26:
			var p := _block_fx_t / 0.26
			for i in 5:
				var ang := (i - 2) * 0.45 + (0.0 if fs > 0.0 else PI)
				var dir := Vector2.from_angle(ang)
				bn[B_SPARK + i] = _seg_bone(sc + dir * lerpf(3.0, 8.0, p), sc + dir * lerpf(7.0, 10.0, p), 1.0 - p * 0.5)


# --- Peças (montadas uma vez, no espaço canônico) -------------------------------------------

## Membro/segmento ao longo de +x com `length`, larguras `wa` → `wb` (o _quad do desenho original).
func _bake_limb(length: float, wa: float, wb: float, col: Color, shade: float) -> void:
	_poly(PackedVector2Array([Vector2(0, -wa), Vector2(length, -wb), Vector2(length, wb), Vector2(0, wa)]), _c(col, shade))


func _bake_shin(shade: float) -> void:
	_bake_limb(SHIN_L, 2.9, 2.6, ivory_shade, shade)
	# faixa dourada na canela (a 62% da canela)
	var x := SHIN_L * 0.62 * 1.1
	_line(Vector2(x, 2.6), Vector2(x, -2.6), _c(gold, shade), 1.2)


## Bota (vista 3/4): sola + bico pontudo + faixa dourada, no espaço do pé.
func _bake_boot(shade: float) -> void:
	var a := 24.0
	var pts: Array = []
	for c in [[-2.3, -2.2, 0.0], [2.3, -2.2, 0.0], [2.2, 3.9, 0.0], [0.0, 5.2, 0.4], [-2.2, 3.9, 0.0], [-2.2, -0.6, 3.6], [2.2, -0.6, 3.6]]:
		pts.append(_v2(_proj(c[0], c[1], c[2], a)))
	var b := PackedVector2Array()
	for i in [0, 4, 3, 2, 1]:
		b.append(pts[i])
	_poly(Geometry2D.convex_hull(b + PackedVector2Array([pts[5], pts[6]])), _c(ivory, shade))
	_line(pts[5], pts[6], _c(gold, shade), 1.6)


## Joelheira: disco marfim com aro dourado (no espaço do joelho).
func _bake_knee(shade: float) -> void:
	_circle(Vector2(0, -0.3), 2.2, _c(gold, shade))
	_disc(Vector2(-0.4, -0.7), 0.8, _c(gold_light, shade))


## Tabardo no plano do corpo: u = lateral, v = distância abaixo do topo (0..TAB_H).
func _bake_tabard(front: bool) -> void:
	if not front:
		_poly(PackedVector2Array([Vector2(-5.6, 0), Vector2(5.6, 0), Vector2(8.4, TAB_H - 0.7), Vector2(3.0, TAB_H), Vector2(-8.0, TAB_H - 0.4)]), _c(ivory_shade))
		_fill(PackedVector2Array([Vector2(-4.3, 0.5), Vector2(-1.4, 0.5), Vector2(-2.6, TAB_H - 0.6), Vector2(-6.5, TAB_H - 0.8)]), _c(ivory))
		return
	var pts := PackedVector2Array()
	for c in [[-3.6, 0.0], [3.6, 0.0], [4.1, TAB_H], [0.7, TAB_H - 1.8], [0.0, TAB_H - 1.1], [-0.7, TAB_H - 1.8], [-4.1, TAB_H]]:
		pts.append(Vector2(c[0], c[1]))
	_poly(pts, _c(ivory_light if front else ivory))
	if front:
		_fill(PaladinMesh.star4(Vector2(0, 5.4), 1.5 * 0.9, 2.2, 2.4, 0.55), _c(gold))
	_line(Vector2(-3.6, 0), Vector2(3.6, 0), _c(gold_dark), 0.8)


## Peitoral (largura canônica TORSO_W; o giro escala na horizontal): placa + sombra inferior.
func _bake_torso() -> void:
	var w := TORSO_W
	_poly(PackedVector2Array([
		Vector2(-w * 0.92, -6.4), Vector2(w * 0.92, -6.4), Vector2(w, -2.4), Vector2(w * 0.78, 4.6),
		Vector2(-w * 0.78, 4.6), Vector2(-w, -2.4)]), _c(ivory))
	_fill(PackedVector2Array([Vector2(-w * 0.86, 1.8), Vector2(w * 0.86, 1.8), Vector2(w * 0.78, 4.6), Vector2(-w * 0.78, 4.6)]), _c(ivory_shade))


## Lado de trás do peito (volume) quando o corpo está de lado.
func _bake_torso_side() -> void:
	var bx := -TORSO_W
	_fill(PackedVector2Array([Vector2(bx, -2.4), Vector2(bx * 0.92, -6.4), Vector2(bx * 0.55, -6.4), Vector2(bx * 0.6, 4.6), Vector2(bx * 0.78, 4.6)]), _c(ivory_shade))


func _bake_torso_hi() -> void:
	var w := TORSO_W
	_fill(PackedVector2Array([Vector2(-w * 0.62, -5.6), Vector2(-w * 0.08, -5.6), Vector2(-w * 0.2, -3.2), Vector2(-w * 0.6, -3.4)]), _c(ivory_light))


## Frente: gola dourada em V e símbolo solar (o osso desloca pelo giro).
func _bake_torso_front() -> void:
	var w := TORSO_W
	_fill(PackedVector2Array([Vector2(-w * 0.62, -6.4), Vector2(w * 0.62, -6.4), Vector2(0, -3.0)]), _c(gold))
	_fill(PackedVector2Array([Vector2(-w * 0.4, -6.4), Vector2(w * 0.4, -6.4), Vector2(0, -4.2)]), _c(dark))
	_fill(_xf_pts(PaladinMesh.star4(Vector2.ZERO, 2.1 * 0.9, 2.1, 2.1, 0.7), Transform2D(0.0, Vector2(0, -0.6))), _c(gold))
	_disc(Vector2(0, -0.6), 0.9, _c(gold_light))


## Costas: costura central e gola dourada.
func _bake_torso_back() -> void:
	var w := TORSO_W
	_line(Vector2(0, -5.8), Vector2(0, 3.6), _c(ivory_shade), 1.0)
	_line(Vector2(-w * 0.6, -6.2), Vector2(w * 0.6, -6.2), _c(gold), 1.3)


## Cinto dourado.
func _bake_torso_belt() -> void:
	var w := TORSO_W
	_poly(PackedVector2Array([Vector2(-w * 0.8, 3.7), Vector2(w * 0.8, 3.7), Vector2(w * 0.82, 6.1), Vector2(-w * 0.82, 6.1)]), _c(gold))
	_line(Vector2(-w * 0.8, 5.5), Vector2(w * 0.8, 5.5), _c(gold_dark), 0.7)


## Elmo fechado arredondado (largura canônica; o giro escala na horizontal).
func _bake_helm() -> void:
	var w := 5.8 * head_scale * 0.95
	var h := 11.4 * head_scale
	var helm := PackedVector2Array()
	for i in 13:
		helm.append(Vector2(_HELM_COS[i] * w, -h * 0.55 + _HELM_SIN[i] * h * 0.45))
	helm.append(Vector2(w * 0.98, 0.0))
	helm.append(Vector2(-w * 0.98, 0.0))
	_poly(helm, _c(ivory))


func _bake_helm_shade(back: float) -> void:
	var w := 5.8 * head_scale * 0.95
	var h := 11.4 * head_scale
	_fill(PackedVector2Array([Vector2(back * w * 0.94, -0.3), Vector2(back * w * 0.96, -h * 0.55), Vector2(back * w * 0.62, -h * 0.88), Vector2(back * w * 0.55, -0.3)]), _c(ivory_shade))


func _bake_helm_top() -> void:
	var w := 5.8 * head_scale * 0.95
	var h := 11.4 * head_scale
	_fill(PackedVector2Array([Vector2(-w * 0.6, -h * 0.82), Vector2(-w * 0.1, -h * 0.95), Vector2(-w * 0.15, -h * 0.72), Vector2(-w * 0.55, -h * 0.62)]), _c(ivory_light))
	_line(Vector2(-w * 0.98, -0.9), Vector2(w * 0.98, -0.9), _c(gold), 1.1)


## Visor em T estreito com borda dourada e linha dourada no alto (centro em x = 0; o osso desloca).
func _bake_visor() -> void:
	var h := 11.4 * head_scale
	_line(Vector2(0, -h * 0.97), Vector2(0, -h * 0.62), _c(gold), 1.2)
	_fill(PackedVector2Array([Vector2(-3.6, -h * 0.62), Vector2(3.6, -h * 0.62), Vector2(3.6, -h * 0.47),
		Vector2(1.2, -h * 0.47), Vector2(1.2, -h * 0.16), Vector2(-1.2, -h * 0.16), Vector2(-1.2, -h * 0.47), Vector2(-3.6, -h * 0.47)]), _c(gold))
	_fill(PackedVector2Array([Vector2(-2.8, -h * 0.585), Vector2(2.8, -h * 0.585), Vector2(2.8, -h * 0.505),
		Vector2(0.45, -h * 0.505), Vector2(0.45, -h * 0.22), Vector2(-0.45, -h * 0.22), Vector2(-0.45, -h * 0.505), Vector2(-2.8, -h * 0.505)]), _c(visor))


## Auréola simples: anel e uma ponta central (o osso estreita pelo giro).
func _bake_halo() -> void:
	var r := 7.0 * head_scale
	_arc_line(Vector2.ZERO, r, 0.0, TAU, 28, _c(outline), 2.3)
	_arc_line(Vector2.ZERO, r, 0.0, TAU, 28, _c(gold), 1.3)
	for spec in [[Vector2(0, -r - 0.6), 2.5]]:
		_poly(_xf_pts(PaladinMesh.star4(Vector2.ZERO, spec[1] * 0.55, spec[1], spec[1] * 0.75, 0.3 * spec[1]), Transform2D(0.0, spec[0])), _c(gold))


## Antebraço (cotovelo → mão) com o punho dourado a 70%.
func _bake_fore(shade: float) -> void:
	_bake_limb(FORE_L, 2.3, 2.1, ivory, shade)
	var x := FORE_L * 0.7
	_line(Vector2(x, -2.3), Vector2(x, 2.3), _c(gold, shade), 1.4)


func _bake_elbow(shade: float) -> void:
	_disc(Vector2.ZERO, 1.7, _c(gold, shade))
	_disc(Vector2.ZERO, 1.0, _c(ivory_light, shade))


## Ombreira compacta: placa, borda e luz; sem rebites pequenos.
func _bake_pauldron(shade: float) -> void:
	var rx := 5.2 * 0.92 * body_width
	var ry := 4.4
	var pts := PackedVector2Array()
	for i in 13:
		pts.append(Vector2(_PAULDRON_COS[i] * rx, _PAULDRON_SIN[i] * ry + 1.2))
	pts.append(Vector2(rx * 0.95, 2.6))
	pts.append(Vector2(-rx * 0.95, 2.6))
	_poly(pts, _c(ivory, shade))
	_fill(PackedVector2Array([Vector2(-rx * 0.97, 0.9), Vector2(rx * 0.97, 0.9), Vector2(rx * 0.95, 2.6), Vector2(-rx * 0.95, 2.6)]), _c(gold, shade))
	_fill(PackedVector2Array([Vector2(-rx * 0.55, -2.3), Vector2(-rx * 0.05, -2.8), Vector2(-rx * 0.1, -1.4), Vector2(-rx * 0.5, -1.0)]), _c(ivory_light, shade))


## Espada da mão (0,0) até a ponta (L,0): lâmina larga com fio escuro, guarda, punho e pomo.
func _bake_sword() -> void:
	var length := 15.5 * sword_scale
	var bw := 1.45 * sword_scale
	var n := Vector2(0, -1)
	var base := Vector2(1.9, 0)
	var near_tip := Vector2(length - 2.2, 0)
	_poly(PackedVector2Array([base + n * bw, near_tip + n * bw * 0.9, Vector2(length, 0), near_tip - n * bw * 0.9, base - n * bw]), _c(blade))
	_fill(PackedVector2Array([base, Vector2(length, 0), near_tip - n * bw * 0.9, base - n * bw]), _c(blade_dark))
	_poly(PackedVector2Array([Vector2(1.5, -3.2) + Vector2(-0.75, 0), Vector2(1.5, 3.2) + Vector2(-0.75, 0), Vector2(1.5, 3.2) + Vector2(0.75, 0), Vector2(1.5, -3.2) + Vector2(0.75, 0)]), _c(gold))
	_poly(PackedVector2Array([Vector2(-2.2, -0.65), Vector2(1.0, -0.65), Vector2(1.0, 0.65), Vector2(-2.2, 0.65)]), _c(leather))
	_circle(Vector2(-2.7, 0), 1.0, _c(gold))


func _shield_outer() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0.0, -11.0), Vector2(7.0, -7.8), Vector2(6.6, 0.8), Vector2(4.2, 6.5), Vector2(0.0, 11.2), Vector2(-4.2, 6.5), Vector2(-6.6, 0.8), Vector2(-7.0, -7.8)])


## Escudo (espaço do escudo; o osso dá giro, estreitamento e inclinação): face ou verso.
func _bake_shield(front: bool) -> void:
	var outer := _shield_outer()
	var inner := PackedVector2Array()
	for q in outer:
		inner.append(q * 0.78 + Vector2(0, -0.2))
	_poly(outer, _c(gold))
	var half := PackedVector2Array([Vector2(0.0, -8.8), Vector2(5.46, -6.28), Vector2(5.15, 0.42), Vector2(3.28, 4.87), Vector2(0.0, 8.54)])
	if front:
		_fill(inner, _c(ivory))
		_fill(half, _c(ivory_shade))
		_fill(PackedVector2Array([Vector2(-4.4, -7.4), Vector2(-1.4, -7.4), Vector2(-1.8, -4.8), Vector2(-4.2, -3.8)]), _c(ivory_light))
		_fill(PaladinMesh.star4(Vector2(0, -0.8), 3.2, 5.0, 5.6, 1.0), _c(gold))
		_fill(PaladinMesh.circle(Vector2(0, -0.8), 1.65, 10), _c(ivory_light))
	else:
		_fill(inner, _c(wood))
		_fill(half, _c(wood.darkened(0.18)))
		for yy in [-3.0, 2.6]:
			_line(Vector2(-4.2, yy), Vector2(4.2, yy), _c(outline), 2.2)
			_line(Vector2(-4.2, yy), Vector2(4.2, yy), _c(leather.lightened(0.15)), 1.2)
			for xx in [-4.0, 4.0]:
				_disc(Vector2(xx, yy), 0.7, _c(gold))


## Escudo caído no chão (face para cima).
func _bake_shield_drop() -> void:
	var outer := _shield_outer()
	_poly(outer, _c(gold))
	var inner := PackedVector2Array()
	for q in outer:
		inner.append(q * 0.78)
	_poly(inner, _c(ivory))
	_fill(PaladinMesh.star4(Vector2(0, -0.8), 3.2, 5.0, 5.6, 1.0), _c(gold))


static func _xf_pts(pts: PackedVector2Array, xf: Transform2D) -> PackedVector2Array:
	return xf * pts


## Transformação do corpo no quadro.
var _body_xf := Transform2D.IDENTITY


## Debug (F4, junto do debug de combate): direção, estado da apresentação e progresso.
func _draw_debug() -> void:
	var view := get_parent() as UnitView
	if view == null or not view.debug_visible:
		return
	var font := ThemeDB.fallback_font
	var target_dir := "—"
	if unit.target:
		target_dir = PaladinPoseLibrary.DIR_NAMES[PaladinPoseLibrary.dir_from_vector(unit.target.position - unit.position)]
	var lines := [
		"dir %s · yaw %d°" % [PaladinPoseLibrary.DIR_NAMES[animator.dir], roundi(_yaw)],
		"%s %.2f" % [animator.debug_state, animator.debug_progress],
		"alvo %s · golpe %s" % [target_dir, PaladinPoseLibrary.attack_variant(animator.dir)],
	]
	var y := top_y() - 10.0 - lines.size() * 8.0
	for line in lines:
		draw_string_outline(font, Vector2(-60, y), line, HORIZONTAL_ALIGNMENT_CENTER, 120, 7, 3, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(-60, y), line, HORIZONTAL_ALIGNMENT_CENTER, 120, 7, Color(1.0, 0.9, 0.6))
		y += 8.0
