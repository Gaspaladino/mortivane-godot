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
## Largura do tronco e distância entre os ombros (1.12 = ~20% mais largo que o Guerreiro).
@export_range(0.8, 1.4, 0.01) var body_width := 1.12
@export_range(0.8, 1.5, 0.01) var shield_scale := 1.18
@export_range(0.8, 1.5, 0.01) var sword_scale := 1.4
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
	queue_redraw()


# --- Pose -------------------------------------------------------------------------------


## Pose neutra (valores absolutos). Ângulos em graus. swing: 0 = braço para baixo, 90 = à frente.
## s_elev: elevação da lâmina (0 = horizontal para a frente, −90 = para baixo, 90 = para cima).
## Pronto para lutar: espada erguida na diagonal, para fora (s_elev 52, s_yaw 78), cotovelo dobrado.
## s_yaw: lâmina para fora (lado direito); sh_yaw: face do escudo girada para fora (lado esquerdo).
static func neutral() -> Dictionary:
	return {
		twist = 0.0, lean = 3.0, crouch = 1.0, rootx = 0.0, rooty = 0.0, stance = 0.0,
		r_swing = 14.0, r_abd = 30.0, r_elbow = 44.0, s_elev = 52.0, s_yaw = 78.0,
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


# --- Desenho -----------------------------------------------------------------------------

func _draw() -> void:
	if _pose.is_empty():
		return
	_draw_effects_under()
	_draw_shadow()
	var p := _pose
	var fs := 1.0 if _yaw >= 0.0 else -1.0
	var root := Transform2D(0.0, BODY_SCALE * RIG_SCALE, 0.0, Vector2(0, FOOT_Y))
	# vista da esquerda = espelho do desenho (a pose e as âncoras são as da direita)
	var body_xf := root * Transform2D(0.0, Vector2(fs, 1.0), 0.0, Vector2.ZERO) * Transform2D(deg_to_rad(-float(p.tilt)), Vector2(float(p.rootx), float(p.rooty)))
	var parts := _parts.duplicate()
	parts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_body_xf = body_xf
	_with(body_xf)
	for it in parts:
		(it[1] as Callable).call()
	# arma e escudo soltos (no espaço da raiz, não caem junto com o corpo)
	_with(root)
	_draw_drops()
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_effects_over(body_xf)
	_draw_debug()


func _build_parts(p: Dictionary) -> Array:
	var a := absf(_yaw)          # a pose é sempre montada na vista da direita; o desenho espelha
	var mirrored := _yaw < 0.0
	# no golpe o corpo gira para o perfil (a lâmina corre de lado, sem sumir atrás do escudo)
	if not animator.dead:
		a += (90.0 - a) * 0.45 * animator.attack_w
	var au := a + float(p.twist)
	var ah := au + float(p.head_turn)
	var ca := cos(deg_to_rad(a))
	var cu := cos(deg_to_rad(au))
	var bw := body_width
	var crouch: float = p.crouch
	var lean_x := float(p.lean) * 0.09          # inclinação: o tronco avança na direção da frente
	var up_f := lean_x                           # frente do tronco (unidades F) por causa da inclinação
	var parts: Array = []
	var A := {}

	# --- pernas (yaw do quadril) ---
	for side in [RIGHT, LEFT]:
		var key := "r" if side < 0 else "l"
		var hip := Vector3(side * 4.0 * bw, 13.4 - crouch, 0.0)
		# base firme: pés afastados (mais que o quadril), joelhos levemente dobrados
		var foot := Vector3(side * (7.0 + float(p.stance)) * bw, float(p[key + "l"]), float(p[key + "f"]))
		var dist := Vector2(hip.x - foot.x, hip.y - foot.y).length()
		var knee_push := sqrt(maxf(0.0, 6.9 * 6.9 - dist * dist / 4.0))
		# joelhos dobrados para a frente e um pouco para fora (postura pesada)
		var knee := (hip + foot) / 2.0 + Vector3(side * knee_push * 0.25, 0, knee_push * 0.85)
		var ph := _proj(hip.x, hip.z, hip.y, a)
		var pk := _proj(knee.x, knee.z, knee.y, a)
		var pf := _proj(foot.x, foot.z, foot.y, a)
		var boot: Array = []
		for c in [[-2.3, -2.2, 0.0], [2.3, -2.2, 0.0], [2.2, 3.9, 0.0], [0.0, 5.2, 0.4], [-2.2, 3.9, 0.0], [-2.2, -0.6, 3.6], [2.2, -0.6, 3.6]]:
			boot.append(_proj(foot.x + c[0], foot.z + c[1], foot.y + c[2], a))
		var near := ph.z
		parts.append([near - 0.5, _draw_leg.bind(_v2(ph), _v2(pk), _v2(pf), boot, 1.0 if near >= -0.5 else 0.85)])
	# túnica escura entre as pernas (atrás do tabardo)
	var robe: Array = []
	for c in [[-3.0, 15.0], [3.0, 15.0], [3.6, 6.0], [-3.6, 6.0]]:
		robe.append(_v2(_proj(c[0] * bw, -0.6, c[1] - crouch, a)))
	parts.append([-1.5, _draw_poly.bind(PackedVector2Array(robe), dark, 1.0)])
	# tabardo: frente (com a estrela) e verso
	var tab: float = p.tab
	if ca > -0.35:
		parts.append([4.8 * ca + 0.8, _draw_tabard.bind(a, 5.0, tab, true, crouch)])
	if ca < 0.35:
		parts.append([-4.2 * ca - 0.8, _draw_tabard.bind(a, -4.2, -tab, false, crouch)])

	# --- tronco (yaw do tronco) ---
	var torso_c := _proj(up_f, 0.0, 21.5 - crouch, au)
	parts.append([0.0, _draw_torso.bind(au, crouch, up_f)])
	# --- cabeça e auréola ---
	var neck := _proj(up_f * 1.4, 0.3, 28.4 - crouch, au)
	A[&"head"] = _v2(neck) + Vector2(0, -6.0)
	A[&"helmet_top"] = _v2(neck) + Vector2(0, -11.4 * head_scale)
	parts.append([1.6, _draw_head.bind(_v2(neck), ah, float(p.head_tilt))])
	var hc := _proj(up_f * 1.4, -3.2, 37.0 - crouch, ah)
	var halo_depth := -3.2 * cos(deg_to_rad(ah)) + (1.6 if cos(deg_to_rad(ah)) < 0.0 else 0.0)
	A[&"halo"] = _v2(hc)
	parts.append([halo_depth, _draw_halo.bind(_v2(hc), ah, float(p.glow))])

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
		var shade := 1.0 if ps.z >= -0.5 else 0.82
		parts.append([(ps.z + ph.z) * 0.5 + 0.2, _draw_arm.bind(_v2(ps), _v2(pe), _v2(ph), shade)])
		var pd := _proj(sh3.x * 1.05, sh3.z, sh3.y + 1.2, au)
		parts.append([ps.z + 0.6 + (0.0 if ps.z >= 0.0 else -0.4), _draw_pauldron.bind(_v2(pd), au, side, shade)])
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
				parts.append([pg.z + 0.9, _draw_sword.bind(_v2(pg), _v2(pt))])
		else:
			# escudo: preso ao braço esquerdo, à frente da mão
			var c3 := hand + Vector3(-1.6, -1.0, 2.6 + float(p.sh_fwd))
			var pc := _proj(c3.x, c3.z, c3.y, au)
			# a face do escudo fica quase sempre voltada para a câmera (leitura), girando só um pouco com
			# o corpo; de costas aparece o verso
			var front_view := cos(deg_to_rad(au)) >= 0.0
			var view_ang := (au if front_view else signf(au) * (180.0 - absf(au))) * 0.4 + (float(p.sh_yaw) - 18.0) * 0.8
			var face := cos(deg_to_rad(view_ang)) * (1.0 if front_view else -1.0)
			# vista da esquerda (referência): aparece o verso do escudo, com o punho segurando a alça
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
					sz = minf(arm_z - 0.3, -0.3)   # verso atrás do braço (o punho aparece) e do tronco
				parts.append([sz, _draw_shield.bind(_v2(pc), face, fwd_x, float(p.lean) * 0.4, 1.0)])
	anchors = A
	return parts


func _draw_poly(pts: PackedVector2Array, col: Color, shade: float) -> void:
	_poly(pts, _c(col, shade))


func _quad(a: Vector2, b: Vector2, wa: float, wb: float) -> PackedVector2Array:
	var n := (b - a).orthogonal().normalized() if (b - a).length() > 0.01 else Vector2.RIGHT
	return PackedVector2Array([a + n * wa, b + n * wb, b - n * wb, a - n * wa])


func _draw_leg(hip: Vector2, knee: Vector2, foot: Vector2, boot: Array, shade: float) -> void:
	_poly(_quad(hip, knee, 3.3, 2.9), _c(ivory, shade))
	_poly(_quad(knee, foot + Vector2(0, -1.4), 2.9, 2.6), _c(ivory_shade, shade))
	# faixa dourada na canela
	var gd := knee.lerp(foot, 0.62)
	var gn := (foot - knee).orthogonal().normalized()
	_line(gd + gn * 2.6, gd - gn * 2.6, _c(gold, shade), 1.2)
	# bota: sola + bico pontudo + faixa dourada
	var b := PackedVector2Array()
	for i in [0, 4, 3, 2, 1]:
		b.append(_v2(boot[i]))
	_poly(Geometry2D.convex_hull(b + PackedVector2Array([_v2(boot[5]), _v2(boot[6])])), _c(ivory, shade))
	_line(_v2(boot[5]), _v2(boot[6]), _c(gold, shade), 1.6)
	# joelheira: disco marfim com aro dourado
	_circle(knee + Vector2(0, -0.3), 2.2, _c(gold, shade))
	draw_circle(knee + Vector2(-0.4, -0.7), 0.8, _c(gold_light, shade))


func _draw_tabard(yaw: float, f: float, swing: float, front: bool, crouch: float) -> void:
	var pts := PackedVector2Array()
	var sw := swing * 0.06
	var top := 15.0 - crouch
	var bot := 3.6 - crouch * 0.5
	for c in [[-3.6, top, 0.0], [3.6, top, 0.0], [4.1, bot, sw], [0.7, bot + 1.8, sw], [0.0, bot + 1.1, sw], [-0.7, bot + 1.8, sw], [-4.1, bot, sw]]:
		pts.append(_v2(_proj(c[0], f + c[2], c[1], yaw)))
	var col := ivory_light if front else ivory
	_poly(pts, _c(col))
	if front:
		# estrela dourada simples
		var sc := _v2(_proj(0.0, f + sw * 0.5, 9.6 - crouch * 0.7, yaw))
		var k := clampf(absf(cos(deg_to_rad(yaw))) * 0.8 + 0.2, 0.2, 1.0)
		draw_colored_polygon(_xf_pts(PaladinMesh.star4(Vector2.ZERO, 1.5 * k, 2.2, 2.4, 0.55), Transform2D(0.0, sc)), _c(gold))
	_line(_v2(_proj(-3.6, f, top, yaw)), _v2(_proj(3.6, f, top, yaw)), _c(gold_dark), 0.8)


func _draw_torso(yaw: float, crouch: float, up_f: float) -> void:
	var c := cos(deg_to_rad(yaw))
	var s := sin(deg_to_rad(yaw))
	var bw := body_width
	var w := 8.6 * bw * (0.84 + 0.16 * absf(c))
	var cx := _proj(up_f, 1.0, 21.0 - crouch, yaw)
	var o := Vector2(cx.x, cx.y)
	var fs := signf(s)
	# peitoral: uma placa grande, larga em cima (ombros) e estreitando na cintura
	var plate := PackedVector2Array([
		o + Vector2(-w * 0.92, -6.4), o + Vector2(w * 0.92, -6.4), o + Vector2(w, -2.4), o + Vector2(w * 0.78, 4.6),
		o + Vector2(-w * 0.78, 4.6), o + Vector2(-w, -2.4)])
	_poly(plate, _c(ivory))
	# sombra inferior e lado de trás (volume por luz simples)
	draw_colored_polygon(PackedVector2Array([o + Vector2(-w * 0.86, 1.8), o + Vector2(w * 0.86, 1.8), o + Vector2(w * 0.78, 4.6), o + Vector2(-w * 0.78, 4.6)]), _c(ivory_shade))
	if absf(s) > 0.3:
		var bx := -fs * w
		draw_colored_polygon(PackedVector2Array([o + Vector2(bx, -2.4), o + Vector2(bx * 0.92, -6.4), o + Vector2(bx * 0.55, -6.4), o + Vector2(bx * 0.6, 4.6), o + Vector2(bx * 0.78, 4.6)]), _c(ivory_shade))
	# brilho no alto do peito (luz de cima/esquerda)
	draw_colored_polygon(PackedVector2Array([o + Vector2(-w * 0.62, -5.6), o + Vector2(-w * 0.08, -5.6), o + Vector2(-w * 0.2, -3.2), o + Vector2(-w * 0.6, -3.4)]), _c(ivory_light))
	if c > 0.12:
		# gola dourada em V e símbolo solar (só de frente)
		var ex := s * w * 0.35
		draw_colored_polygon(PackedVector2Array([o + Vector2(-w * 0.62 + ex, -6.4), o + Vector2(w * 0.62 + ex, -6.4), o + Vector2(ex, -3.0)]), _c(gold))
		draw_colored_polygon(PackedVector2Array([o + Vector2(-w * 0.4 + ex, -6.4), o + Vector2(w * 0.4 + ex, -6.4), o + Vector2(ex, -4.2)]), _c(dark))
		var sun := o + Vector2(ex, -0.6)
		var k := clampf(c, 0.3, 1.0)
		draw_colored_polygon(_xf_pts(PaladinMesh.star4(Vector2.ZERO, 2.1 * k, 2.1, 2.1, 0.7), Transform2D(0.0, sun)), _c(gold))
		draw_circle(sun, 0.9, _c(gold_light))
	else:
		# costas: placa com a costura central e gola dourada
		var ex := s * w * 0.3
		_line(o + Vector2(ex, -5.8), o + Vector2(ex, 3.6), _c(ivory_shade), 1.0)
		_line(o + Vector2(-w * 0.6 - ex * 0.2, -6.2), o + Vector2(w * 0.6 - ex * 0.2, -6.2), _c(gold), 1.3)
	# cinto dourado + fivela grande
	var belt := PackedVector2Array([o + Vector2(-w * 0.8, 3.7), o + Vector2(w * 0.8, 3.7), o + Vector2(w * 0.82, 6.1), o + Vector2(-w * 0.82, 6.1)])
	_poly(belt, _c(gold))
	_line(o + Vector2(-w * 0.8, 5.5), o + Vector2(w * 0.8, 5.5), _c(gold_dark), 0.7)
	if c > 0.1:
		var bx := o + Vector2(s * w * 0.4, 4.9)
		_poly(PackedVector2Array([bx + Vector2(-1.8, -1.6), bx + Vector2(1.8, -1.6), bx + Vector2(1.8, 1.6), bx + Vector2(-1.8, 1.6)]), _c(gold_light))
		draw_circle(bx, 0.7, _c(gold_dark))
	# fraldão (placa curta abaixo do cinto)
	draw_colored_polygon(PackedVector2Array([o + Vector2(-w * 0.8, 6.0), o + Vector2(w * 0.8, 6.0), o + Vector2(w * 0.86, 8.4), o + Vector2(-w * 0.86, 8.4)]), _c(ivory_shade))


func _draw_head(neck: Vector2, yaw: float, tilt: float) -> void:
	_with(_body_xf * Transform2D(deg_to_rad(tilt * signf(sin(deg_to_rad(yaw)) + 0.0001)), neck))
	var c := cos(deg_to_rad(yaw))
	var s := sin(deg_to_rad(yaw))
	var hs := head_scale
	var w := 5.8 * hs * (0.9 + 0.1 * absf(c))
	var h := 11.4 * hs
	# elmo fechado arredondado (bucket): base reta, topo em cúpula
	var helm := PackedVector2Array()
	for i in 13:
		helm.append(Vector2(_HELM_COS[i] * w, -h * 0.55 + _HELM_SIN[i] * h * 0.45))
	helm.append(Vector2(w * 0.98, 0.0))
	helm.append(Vector2(-w * 0.98, 0.0))
	_poly(helm, _c(ivory))
	# sombra do lado de trás e brilho no topo
	var back := -signf(s) if absf(s) > 0.25 else 1.0
	draw_colored_polygon(PackedVector2Array([Vector2(back * w * 0.94, -0.3), Vector2(back * w * 0.96, -h * 0.55), Vector2(back * w * 0.62, -h * 0.88), Vector2(back * w * 0.55, -0.3)]), _c(ivory_shade))
	draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.6, -h * 0.82), Vector2(-w * 0.1, -h * 0.95), Vector2(-w * 0.15, -h * 0.72), Vector2(-w * 0.55, -h * 0.62)]), _c(ivory_light))
	_line(Vector2(-w * 0.98, -0.9), Vector2(w * 0.98, -0.9), _c(gold), 1.1)
	var vx := s * w * 0.62
	if c > -0.25:
		# visor em T estreito com borda dourada e linha dourada no alto
		var k := clampf(c * 0.75 + 0.45, 0.35, 1.0)
		_line(Vector2(vx, -h * 0.97), Vector2(vx, -h * 0.62), _c(gold), 1.2)
		var t_gold := PackedVector2Array([Vector2(vx - 3.6 * k, -h * 0.62), Vector2(vx + 3.6 * k, -h * 0.62), Vector2(vx + 3.6 * k, -h * 0.47),
			Vector2(vx + 1.2 * k, -h * 0.47), Vector2(vx + 1.2 * k, -h * 0.16), Vector2(vx - 1.2 * k, -h * 0.16), Vector2(vx - 1.2 * k, -h * 0.47), Vector2(vx - 3.6 * k, -h * 0.47)])
		draw_colored_polygon(t_gold, _c(gold))
		var t_slit := PackedVector2Array([Vector2(vx - 2.8 * k, -h * 0.585), Vector2(vx + 2.8 * k, -h * 0.585), Vector2(vx + 2.8 * k, -h * 0.505),
			Vector2(vx + 0.45 * k, -h * 0.505), Vector2(vx + 0.45 * k, -h * 0.22), Vector2(vx - 0.45 * k, -h * 0.22), Vector2(vx - 0.45 * k, -h * 0.505), Vector2(vx - 2.8 * k, -h * 0.505)])
		draw_colored_polygon(t_slit, _c(visor))
	else:
		# traseira do elmo: crista dourada no centro de trás
		_line(Vector2(-vx * 0.4, -h * 0.97), Vector2(-vx * 0.4, -h * 0.1), _c(gold), 1.2)
	_with(_body_xf)


func _draw_halo(c: Vector2, yaw: float, glow: float) -> void:
	var k := 0.78 + 0.22 * absf(cos(deg_to_rad(yaw)))
	var r := 7.0 * head_scale
	var col := gold.lerp(holy, glow * 0.5)
	if glow > 0.01:
		draw_circle(c, r + 2.5, Color(holy, 0.18 * glow))
	draw_set_transform_matrix(_body_xf * Transform2D(0.0, Vector2(k, 1.0), 0.0, c))
	# o anel é sempre a mesma forma (raio fixo, no espaço da auréola): malha cacheada (DrawCache,
	# mesma geometria do draw_arc suavizado); o resto do Paladino é projetado e fica no caminho direto
	for ring in [[2.3, _c(outline)], [1.3, _c(col)]]:
		var m := DrawCache.arc_mesh(Vector2.ZERO, r, 0.0, TAU, 28, ring[0])
		if m:
			draw_mesh(m, null, Transform2D.IDENTITY, ring[1])
		else:
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, ring[1], ring[0], true)
	_with(_body_xf)
	# três pontas pequenas (topo maior)
	for spec in [[Vector2(0, -r - 1.2), 3.4, 1.0], [Vector2(-r * k - 0.4, 0), 2.0, 0.8], [Vector2(r * k + 0.4, 0), 2.0, 0.8]]:
		var sp := _xf_pts(PaladinMesh.star4(Vector2.ZERO, spec[1] * 0.55, spec[1], spec[1] * 0.75, 0.3 * spec[1]), Transform2D(0.0, c + spec[0]))
		_poly(sp, _c(col))


func _draw_arm(sh: Vector2, el: Vector2, hand: Vector2, shade: float) -> void:
	_poly(_quad(sh, el, 2.4, 2.2), _c(ivory_shade, shade))
	_poly(_quad(el, hand, 2.3, 2.1), _c(ivory, shade))
	# punho dourado + manopla marrom
	var n := (hand - el).orthogonal().normalized()
	var cuff := hand.lerp(el, 0.3)
	_line(cuff + n * 2.3, cuff - n * 2.3, _c(gold, shade), 1.4)
	draw_circle(el, 1.7, _c(gold, shade))
	draw_circle(el, 1.0, _c(ivory_light, shade))
	_circle(hand, 2.1, _c(leather, shade))


func _draw_pauldron(c: Vector2, yaw: float, side: float, shade: float) -> void:
	# ombreira grande e arredondada: aumenta bastante a largura da silhueta
	var s := sin(deg_to_rad(yaw))
	var k := 0.85 + 0.15 * absf(cos(deg_to_rad(yaw)))
	var rx := 6.0 * k * body_width
	var ry := 5.2
	var pts := PackedVector2Array()
	for i in 13:
		pts.append(c + Vector2(_PAULDRON_COS[i] * rx, _PAULDRON_SIN[i] * ry + 1.2))
	pts.append(c + Vector2(rx * 0.95, 2.6))
	pts.append(c + Vector2(-rx * 0.95, 2.6))
	_poly(pts, _c(ivory, shade))
	# borda dourada embaixo
	draw_colored_polygon(PackedVector2Array([c + Vector2(-rx * 0.97, 0.9), c + Vector2(rx * 0.97, 0.9), c + Vector2(rx * 0.95, 2.6), c + Vector2(-rx * 0.95, 2.6)]), _c(gold, shade))
	# brilho e rebite dourado (na frente da ombreira)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-rx * 0.55, -2.3), c + Vector2(-rx * 0.05, -2.8), c + Vector2(-rx * 0.1, -1.4), c + Vector2(-rx * 0.5, -1.0)]), _c(ivory_light, shade))
	draw_circle(c + Vector2(s * rx * 0.35, -0.3), 1.4, _c(gold_light, shade))
	draw_circle(c + Vector2(s * rx * 0.35, -0.3), 0.6, _c(gold_dark, shade))
	# rebites na borda dourada
	for i in 3:
		draw_circle(c + Vector2((i - 1) * rx * 0.55, 1.75), 0.45, _c(gold_dark, shade))


func _draw_sword(grip: Vector2, tip: Vector2) -> void:
	var d := tip - grip
	var len := d.length()
	var u := d / maxf(len, 0.01)
	var n := u.orthogonal()
	var bw := 1.45 * sword_scale
	var base := grip + u * 1.9
	# lâmina larga (curta/média) com fio escuro no meio
	_poly(PackedVector2Array([base + n * bw, grip + u * (len - 2.2) + n * bw * 0.9, tip, grip + u * (len - 2.2) - n * bw * 0.9, base - n * bw]), _c(blade))
	_line(base + u * 0.5, grip + u * (len - 2.6), _c(blade_dark), 0.55)
	# guarda dourada, punho e pomo
	_poly(_quad(grip + u * 1.5 - n * 3.2, grip + u * 1.5 + n * 3.2, 0.75, 0.75), _c(gold))
	_poly(_quad(grip - u * 2.2, grip + u * 1.0, 0.65, 0.65), _c(leather))
	_circle(grip - u * 2.7, 1.0, _c(gold))


## Escudo grande (elemento principal): marfim, borda dourada, sol dourado simples.
## `face` > 0 = frente para a câmera (1 = de frente); < 0 = verso. `fwd_x` = para onde aponta.
func _draw_shield(c: Vector2, face: float, fwd_x: float, tilt_deg: float, shade: float) -> void:
	var k := shield_scale
	var sx := maxf(absf(face), 0.22) * k
	var xf := Transform2D(deg_to_rad(tilt_deg * signf(fwd_x + 0.0001)), Vector2(sx, k), 0.0, c)
	var outer := PackedVector2Array([Vector2(-6.4, -9.8), Vector2(6.4, -9.8), Vector2(6.9, -3.0), Vector2(5.0, 4.8), Vector2(0.0, 10.4), Vector2(-5.0, 4.8), Vector2(-6.9, -3.0)])
	var inner := PackedVector2Array()
	for q in outer:
		inner.append(q * 0.78 + Vector2(0, -0.2))
	# espessura do aro quando visto de lado
	var edge := 1.6 * (1.0 - absf(face)) * signf(-fwd_x if face >= 0.0 else fwd_x)
	var sk := Transform2D(0.0, Vector2(edge, 0.0)) * xf
	_poly(_xf_pts(outer, sk), _c(gold_dark, shade))
	_poly(_xf_pts(outer, xf), _c(gold, shade))
	if face >= 0.0:
		draw_colored_polygon(_xf_pts(inner, xf), _c(ivory, shade))
		# metade sombreada (volume) e brilho no alto
		draw_colored_polygon(_xf_pts(PackedVector2Array([Vector2(0.0, -7.8), Vector2(5.0, -7.8), Vector2(5.4, -2.5), Vector2(3.9, 3.6), Vector2(0.0, 7.9)]), xf), _c(ivory_shade, shade))
		draw_colored_polygon(_xf_pts(PackedVector2Array([Vector2(-4.4, -7.4), Vector2(-1.4, -7.4), Vector2(-1.8, -4.8), Vector2(-4.2, -3.8)]), xf), _c(ivory_light, shade))
		# sol dourado simples no centro
		draw_colored_polygon(_xf_pts(PaladinMesh.star4(Vector2(0, -0.8), 3.2, 5.0, 5.6, 1.0), xf), _c(gold, shade))
		draw_colored_polygon(_xf_pts(PaladinMesh.circle(Vector2(0, -0.8), 1.5, 10), xf), _c(gold_light, shade))
	else:
		# verso: madeira escura com as alças
		draw_colored_polygon(_xf_pts(inner, xf), _c(wood, shade))
		draw_colored_polygon(_xf_pts(PackedVector2Array([Vector2(0.0, -7.8), Vector2(5.0, -7.8), Vector2(5.4, -2.5), Vector2(3.9, 3.6), Vector2(0.0, 7.9)]), xf), _c(wood.darkened(0.18), shade))
		# alças de couro com rebites dourados (o punho segura a de cima)
		for yy in [-3.0, 2.6]:
			_line(xf * Vector2(-4.2, yy), xf * Vector2(4.2, yy), _c(outline, shade), 2.2)
			_line(xf * Vector2(-4.2, yy), xf * Vector2(4.2, yy), _c(leather.lightened(0.15), shade), 1.2)
			for xx in [-4.0, 4.0]:
				draw_circle(xf * Vector2(xx, yy), 0.7, _c(gold, shade))


static func _xf_pts(pts: PackedVector2Array, xf: Transform2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = xf * pts[i]
	return out


func _draw_drops() -> void:
	var fs := 1.0 if _yaw >= 0.0 else -1.0
	if not _shield_drop.is_empty():
		var u := clampf(float(_shield_drop.t) / 0.42, 0.0, 1.0)
		var pos: Vector2 = (_shield_drop.from as Vector2).lerp(_shield_drop.to, u)
		pos.y = lerpf((_shield_drop.from as Vector2).y, (_shield_drop.to as Vector2).y, u * u)
		# o escudo tomba e fica deitado (achatado), a face para cima
		var flat := lerpf(1.0, 0.5, u * u)
		var xf := Transform2D(deg_to_rad(-12.0 * fs * u), Vector2(shield_scale, shield_scale * flat), 0.0, pos)
		var outer := PackedVector2Array([Vector2(-6.4, -9.8), Vector2(6.4, -9.8), Vector2(6.9, -3.0), Vector2(5.0, 4.8), Vector2(0.0, 10.4), Vector2(-5.0, 4.8), Vector2(-6.9, -3.0)])
		_poly(_xf_pts(outer, xf), _c(gold))
		var inner := PackedVector2Array()
		for q in outer:
			inner.append(q * 0.78)
		_poly(_xf_pts(inner, xf), _c(ivory))
		draw_colored_polygon(_xf_pts(PaladinMesh.star4(Vector2(0, -0.8), 3.2, 5.0, 5.6, 1.0), xf), _c(gold))
	if not _sword_drop.is_empty():
		var u := clampf(float(_sword_drop.t) / 0.36, 0.0, 1.0)
		var pos: Vector2 = (_sword_drop.from as Vector2).lerp(_sword_drop.to, u)
		pos.y = lerpf((_sword_drop.from as Vector2).y, (_sword_drop.to as Vector2).y, u * u)
		if u >= 1.0:
			var b := clampf((float(_sword_drop.t) - 0.36) / 0.16, 0.0, 1.0)
			pos.y -= sin(b * PI) * 1.1 * (1.0 - b)
		var ang := lerp_angle(float(_sword_drop.from_ang), float(_sword_drop.to_ang), PaladinPoseLibrary.ease_by(&"out", u))
		_draw_sword(pos, pos + Vector2.from_angle(ang) * 15.5 * sword_scale * (0.75 + 0.25 * u))


func _draw_shadow() -> void:
	var lying := clampf(float(_pose.get(&"tilt", 0.0)) / 88.0, 0.0, 1.0)
	var fs := 1.0 if _yaw >= 0.0 else -1.0
	draw_set_transform(Vector2(-14.0 * lying * RIG_SCALE * fs, FOOT_Y), 0.0, Vector2(1.0 + lying * 1.3, 0.32))
	draw_circle(Vector2.ZERO, 12.5, Color(0, 0, 0, 0.32))
	draw_set_transform(Vector2.ZERO)


## Transformação do corpo no quadro (as partes que mudam a transformação voltam para ela).
var _body_xf := Transform2D.IDENTITY


# --- Efeitos (simples, separados do corpo) ------------------------------------------------

func _draw_effects_under() -> void:
	if _ring_t >= 0.0:
		PaladinFx.taunt_ring(self, _ring_t, 1.0, Color("f0c674"))
		var p := _ring_t / 0.9
		draw_set_transform(Vector2(0, FOOT_Y), 0.0, Vector2(1.0, 0.36))
		draw_arc(Vector2.ZERO, lerpf(10.0, 30.0, ease(clampf(p / 0.6, 0.0, 1.0), 0.4)), 0.0, TAU, 40, Color(gold_light, 0.5 * (1.0 - p)), 1.6, true)
		draw_set_transform(Vector2.ZERO)


func _draw_effects_over(body_xf: Transform2D) -> void:
	if not anchors.has(&"shield_c") or not _shield_drop.is_empty():
		return
	var sc: Vector2 = body_xf * (anchors.shield_c as Vector2)
	var g := animator.guard_blend * animator.defense_w
	if g > 0.05:
		# Escudo Sagrado ativo: contorno dourado sutil em volta do escudo
		var pulse := 0.8 + 0.2 * sin(_time * 5.0)
		draw_arc(sc, 11.0 * RIG_SCALE * shield_scale, 0.0, TAU, 32, Color(holy, 0.35 * g * pulse), 1.4, true)
	if _shield_up_t >= 0.0 and _shield_up_t < 0.35:
		var p := _shield_up_t / 0.35
		draw_arc(sc, lerpf(6.0, 16.0, ease(p, 0.4)), 0.0, TAU, 32, Color(gold_light, 0.8 * (1.0 - p)), 1.4, true)
	if _block_fx_t >= 0.0 and _block_fx_t < 0.26:
		var p := _block_fx_t / 0.26
		var fs := 1.0 if _yaw >= 0.0 else -1.0
		for i in 5:
			var ang := (i - 2) * 0.45 + (0.0 if fs > 0.0 else PI)
			var dir := Vector2.from_angle(ang)
			draw_line(sc + dir * lerpf(3.0, 8.0, p), sc + dir * lerpf(7.0, 10.0, p), Color(gold_light, 1.0 - p), 1.2, true)


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
