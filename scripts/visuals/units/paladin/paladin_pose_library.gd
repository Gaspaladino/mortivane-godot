class_name PaladinPoseLibrary
extends RefCounted
## Poses do Paladino Vivo 2.5D (só apresentação).
##
## Uma pose é um Dictionary com as chaves de neutral(). Ângulos em radianos, distâncias em unidades
## do rig. Convenções (espaço do corpo, x = esquerda do personagem):
##   spine/head/hips/body_rot = (inclina para a frente, gira para a esquerda, rola)
##   r_arm/l_arm/r_leg/l_leg  = (balanço para a frente, abertura para fora, torção)
##   r_elbow/l_elbow          = dobra (antebraço para a frente) · r_knee/l_knee = dobra (canela para trás)
##   sword                    = orientação da lâmina em relação ao tronco (0 = ponta para a frente;
##                              +x = ponta para baixo; +y = ponta para a esquerda do personagem)
##   shield                   = orientação do escudo em relação ao tronco (0 = de pé, face para a frente)
##   cloth                    = (tabardo da frente para a frente, tabardo de trás para trás, lado)
##   ground                   = 1 → os pés tocam o chão (0 na queda da morte)
## A espada é SEMPRE da mão direita (r_*) e o escudo do braço esquerdo (l_*): nenhuma pose troca.
##
## As direções são poses-base (DIRS): o corpo gira de verdade (yaw) e a apresentação do equipamento
## se ajusta à câmera. Os clipes (idle, walk, attack, taunt, guard, block, hit, push, death) são
## DELTAS somados à pose-base — o mesmo golpe nasce certo em qualquer direção.

enum Dir { DOWN, DOWN_RIGHT, RIGHT, UP_RIGHT, UP, UP_LEFT, LEFT, DOWN_LEFT }
const DIR_NAMES := ["DOWN", "DOWN_RIGHT", "RIGHT", "UP_RIGHT", "UP", "UP_LEFT", "LEFT", "DOWN_LEFT"]

## Pose-base de cada direção da direita (as da esquerda são o mesmo giro para o outro lado; o
## equipamento continua nas mãos certas). yaw: 0 = de frente para a câmera, 90° = perfil direito.
## `shield_cam`: quanto a face do escudo se volta para a câmera (legibilidade); `sword_yaw`: para onde a
## lâmina aponta em repouso (em relação ao tronco; negativo = para o lado direito do personagem).
## `attack`: variante do golpe ( &"flat" horizontal, &"overhead" de cima, &"rising" de baixo).
const DIRS := {
	Dir.DOWN: {yaw = 16.0, shield_cam = 0.22, sword_yaw = -1.05, lean = 0.02, attack = &"rising"},
	Dir.DOWN_RIGHT: {yaw = 40.0, shield_cam = 0.30, sword_yaw = -0.78, lean = 0.04, attack = &"rising"},
	Dir.RIGHT: {yaw = 62.0, shield_cam = 0.52, sword_yaw = -0.36, lean = 0.05, attack = &"flat"},
	Dir.UP_RIGHT: {yaw = 122.0, shield_cam = 0.42, sword_yaw = -0.55, lean = 0.06, attack = &"overhead"},
	Dir.UP: {yaw = 160.0, shield_cam = 0.30, sword_yaw = -0.9, lean = 0.06, attack = &"overhead"},
}

## Momento do impacto dentro do golpe (fração da apresentação) e duração da apresentação (s).
const ATTACK_IMPACT := 0.44
const ATTACK_TIME := 0.78
const TAUNT_TIME := 0.8
const HIT_TIME := 0.22
const BLOCK_TIME := 0.24
const PUSH_TIME := 0.45
const DEATH_TIME := 1.35


static func neutral() -> Dictionary:
	return {
		body_pos = Vector3.ZERO, body_rot = Vector3.ZERO, root = Vector3.ZERO, ground = 1.0,
		hips = Vector3.ZERO, spine = Vector3(0.05, 0.0, 0.0), head = Vector3(0.04, 0.0, 0.0),
		r_arm = Vector3(0.26, 0.32, 0.0), r_elbow = 0.72,
		l_arm = Vector3(0.24, 0.46, 0.0), l_elbow = 0.95,
		sword = Vector3(0.5, -0.72, 0.0), shield = Vector3(0.0, 0.3, 0.0),
		r_leg = Vector3(-0.03, 0.2, -0.26), r_knee = 0.14, r_foot = 0.0,
		l_leg = Vector3(0.10, 0.18, -0.2), l_knee = 0.16, l_foot = 0.0,
		cloth = Vector3(0.02, 0.03, 0.0), halo = Vector2.ZERO,
	}


# --- Operações ------------------------------------------------------------------------------

static func mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	if t <= 0.0:
		return a.duplicate()
	if t >= 1.0:
		return b.duplicate()
	var out := {}
	for k in a:
		out[k] = lerp(a[k], b.get(k, a[k]), t)
	return out


## Soma um delta (parcial) com peso.
static func add(base: Dictionary, delta: Dictionary, w := 1.0) -> Dictionary:
	if w == 0.0 or delta.is_empty():
		return base
	var out := base.duplicate()
	for k in delta:
		if out.has(k):
			out[k] = out[k] + delta[k] * w
	return out


## Interpola deltas parciais (chave ausente = zero).
static func mix_delta(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a:
		out[k] = lerp(a[k], b.get(k, a[k] * 0.0), t)
	for k in b:
		if not out.has(k):
			out[k] = lerp(b[k] * 0.0, b[k], t)
	return out


## Trilha de keyframes [[tempo, delta, easing]]: o easing é do trecho que CHEGA naquele keyframe.
static func track(keys: Array, t: float) -> Dictionary:
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if t <= keys[i][0]:
			var t0: float = keys[i - 1][0]
			var t1: float = keys[i][0]
			var u := (t - t0) / maxf(t1 - t0, 1e-5)
			return mix_delta(keys[i - 1][1], keys[i][1], ease_by(keys[i][2], u))
	return keys[keys.size() - 1][1]


static func ease_by(kind: StringName, u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	match kind:
		&"in":
			return pow(u, 2.2)
		&"out":
			return 1.0 - pow(1.0 - u, 3.0)
		&"inout":
			return u * u * (3.0 - 2.0 * u)
		&"back":   # pequeno overshoot
			var c := 1.6
			return 1.0 + (c + 1.0) * pow(u - 1.0, 3.0) + c * pow(u - 1.0, 2.0)
		&"hold":
			return 0.0
	return u


# --- Direções ---------------------------------------------------------------------------------

## yaw (rad) da direção. DOWN e UP pendem para o último lado lateral (`lateral` = +1 direita, −1 esquerda)
## para nunca virarem um desenho chapado de frente/costas.
static func dir_yaw(dir: Dir, lateral := 1.0) -> float:
	var e := _dir_entry(dir)
	var y := deg_to_rad(float(e.yaw))
	if dir in [Dir.DOWN, Dir.UP]:
		return y * (1.0 if lateral >= 0.0 else -1.0)
	return y if _is_right(dir) else -y


static func _is_right(dir: Dir) -> bool:
	return dir in [Dir.DOWN_RIGHT, Dir.RIGHT, Dir.UP_RIGHT]


static func _dir_entry(dir: Dir) -> Dictionary:
	match dir:
		Dir.UP_LEFT:
			return DIRS[Dir.UP_RIGHT]
		Dir.LEFT:
			return DIRS[Dir.RIGHT]
		Dir.DOWN_LEFT:
			return DIRS[Dir.DOWN_RIGHT]
	return DIRS[dir]


static func attack_variant(dir: Dir) -> StringName:
	return _dir_entry(dir).attack


## Direção (8) de um vetor na tela (y para baixo).
static func dir_from_vector(v: Vector2) -> Dir:
	var a := atan2(v.x, v.y)   # 0 = baixo, +90° = direita
	var i := int(round(a / (PI / 4.0)))
	i = posmod(i, 8)
	return [Dir.DOWN, Dir.DOWN_RIGHT, Dir.RIGHT, Dir.UP_RIGHT, Dir.UP, Dir.UP_LEFT, Dir.LEFT, Dir.DOWN_LEFT][i]


## Pose-base da direção: ajusta a apresentação do equipamento para a câmera. `yaw` = giro atual do
## corpo (a câmera fica do lado direito do personagem quando ele olha para a direita).
static func base_for(dir: Dir, yaw: float) -> Dictionary:
	var e := _dir_entry(dir)
	var p := neutral()
	var cam_x := -sin(yaw)          # x (esquerda do personagem) da direção da câmera, no corpo
	var to_cam := signf(cam_x) if absf(cam_x) > 0.05 else 0.0
	var sh: Vector3 = p.shield
	# escudo do lado de longe: a face vira para a câmera (legível); do lado de perto: só um pouco
	# (a estrela continua visível sem virar uma parede na frente do corpo)
	sh.y += float(e.shield_cam) * (to_cam if to_cam < 0.0 else 0.2 * to_cam)
	p.shield = sh
	var sw: Vector3 = p.sword
	sw.y = float(e.sword_yaw)
	p.sword = sw
	var sp: Vector3 = p.spine
	sp.x += float(e.lean)
	p.spine = sp
	return p


# --- Clipes (deltas) --------------------------------------------------------------------------

## Idle de combate: respiração lenta, transferência de peso mínima. `t` em segundos.
static func idle(t: float, look: PaladinRigLook) -> Dictionary:
	var w := TAU / look.idle_cycle
	var b := sin(t * w) * look.breathing
	var s := sin(t * w * 0.5 + 0.6) * look.breathing
	return {
		spine = Vector3(0.012 * b, 0.0, 0.008 * s), head = Vector3(-0.008 * b, 0.0, -0.006 * s),
		r_arm = Vector3(0.012 * b, 0.006 * b, 0.0), l_arm = Vector3(0.01 * b, 0.004 * b, 0.0),
		root = Vector3(0.35 * s, -0.12 * (1.0 - b), 0.0), hips = Vector3(0.0, 0.0, -0.012 * s),
		r_knee = 0.02 * (1.0 - b), l_knee = 0.02 * (1.0 - b),
		sword = Vector3(0.015 * b, 0.0, 0.0), cloth = Vector3(0.01 * s, 0.006 * b, 0.0),
		halo = Vector2(0.0, 0.18 * b),
	}


## Caminhada pesada. `phase` 0..1 (um ciclo = dois passos), `amount` 0..1 (entrada/saída suave).
static func walk(phase: float, amount: float, look: PaladinRigLook) -> Dictionary:
	var th := phase * TAU
	var s := look.stride
	var a := look.walk_amplitude
	var rs := sin(th)
	var ls := -rs
	var r_swing := maxf(0.0, cos(th))          # perna direita indo para a frente
	var l_swing := maxf(0.0, -cos(th))
	var contact := absf(sin(th))               # pernas abertas = contato
	return {
		r_leg = Vector3(s * rs, 0.0, 0.0) * amount, l_leg = Vector3(s * ls, 0.0, 0.0) * amount,
		r_knee = (0.1 + 0.62 * pow(r_swing, 1.4)) * amount, l_knee = (0.1 + 0.62 * pow(l_swing, 1.4)) * amount,
		r_foot = (-0.18 * maxf(0.0, rs) + 0.25 * r_swing * maxf(0.0, -rs)) * amount,
		l_foot = (-0.18 * maxf(0.0, ls) + 0.25 * l_swing * maxf(0.0, -ls)) * amount,
		hips = Vector3(0.0, -0.09 * rs * a, 0.035 * cos(th * 2.0) * a) * amount,
		spine = Vector3(0.07, 0.07 * rs * a, -0.02 * cos(th * 2.0) * a) * amount,
		head = Vector3(-0.03, -0.05 * rs * a, 0.0) * amount,
		root = Vector3(0.0, -look.vertical_bounce * (1.0 - contact) * 0.6 + look.vertical_bounce * 0.3, 0.0) * amount,
		r_arm = Vector3(-0.13 * rs * a, 0.02, 0.0) * amount, l_arm = Vector3(0.05 * rs * a, 0.0, 0.0) * amount,
		sword = Vector3(-0.05 * rs * a, 0.0, 0.0) * amount,
		cloth = Vector3(0.10 + 0.22 * maxf(rs, ls), 0.10, 0.03 * rs) * amount * look.cloth_amplitude,
	}


## Golpe de espada (mão direita). `p` 0..1 da apresentação; impacto em ATTACK_IMPACT.
## O corpo age em cascata: quadril → tronco → ombro → braço → espada (cada um um pouco depois).
static func attack(p: float, variant: StringName, look: PaladinRigLook) -> Dictionary:
	var W := look.windup
	var R := look.body_rotation
	var A := look.sword_arc
	var F := look.follow_through
	var I := ATTACK_IMPACT
	# chaves: [início, fim da antecipação, impacto, acompanhamento, recuperação]
	var body: Array
	var arm: Array
	var blade: Array
	match variant:
		&"overhead":   # de cima para baixo (alvo na diagonal de cima)
			body = [
				[0.0, {}, &"linear"],
				[0.34, {hips = Vector3(0, -0.08 * R, 0), spine = Vector3(-0.16 * W, -0.14 * R, 0), root = Vector3(0, -0.4, -1.6 * W), r_knee = 0.12, l_knee = 0.26, head = Vector3(-0.1, 0.06, 0)}, &"out"],
				[I, {hips = Vector3(0.05, 0.08 * R, 0), spine = Vector3(0.3, 0.1 * R, 0), root = Vector3(0, -1.6, 2.2), l_knee = 0.45, r_knee = 0.2, head = Vector3(0.12, 0, 0)}, &"in"],
				[0.62, {hips = Vector3(0.06, 0.1 * R * F, 0), spine = Vector3(0.36 * F, 0.12 * R * F, 0), root = Vector3(0, -1.8, 2.0), l_knee = 0.48, r_knee = 0.22, head = Vector3(0.14, 0, 0)}, &"out"],
				[1.0, {}, &"inout"],
			]
			arm = [
				[0.0, {}, &"linear"],
				[0.34, {r_arm = Vector3(2.55 * W, 0.2, 0.0), r_elbow = 1.3}, &"out"],
				[I - 0.025, {r_arm = Vector3(1.15, 0.05, 0.0), r_elbow = 0.08}, &"in"],
				[0.62, {r_arm = Vector3(0.55 * F, 0.12, 0.0), r_elbow = 0.35}, &"out"],
				[1.0, {}, &"inout"],
			]
			blade = [
				[0.0, {}, &"linear"],
				[0.34, {sword = Vector3(-2.35 * W * A, 0.55, 0.0)}, &"out"],
				[I - 0.045, {sword = Vector3(0.12, 0.62, 0.0)}, &"in"],
				[0.62, {sword = Vector3(0.85 * F, 0.72, 0.0)}, &"back"],
				[1.0, {}, &"inout"],
			]
		&"rising":   # corte de baixo para cima (alvo na diagonal de baixo)
			body = [
				[0.0, {}, &"linear"],
				[0.34, {hips = Vector3(0, -0.14 * R, 0), spine = Vector3(0.16, -0.26 * R, 0.04), root = Vector3(0, -1.6, -1.2 * W), r_knee = 0.38, l_knee = 0.32}, &"out"],
				[I, {hips = Vector3(0, 0.12 * R, 0), spine = Vector3(0.04, 0.22 * R, -0.03), root = Vector3(0, -0.8, 2.0), l_knee = 0.4, r_knee = 0.18}, &"in"],
				[0.62, {hips = Vector3(0, 0.16 * R * F, 0), spine = Vector3(-0.06, 0.3 * R * F, -0.04), root = Vector3(0, -0.6, 1.8), l_knee = 0.36, r_knee = 0.16}, &"out"],
				[1.0, {}, &"inout"],
			]
			arm = [
				[0.0, {}, &"linear"],
				[0.34, {r_arm = Vector3(-0.4 * W, 0.5, 0.0), r_elbow = 0.35}, &"out"],
				[I - 0.025, {r_arm = Vector3(0.95, 0.12, 0.0), r_elbow = 0.1}, &"in"],
				[0.62, {r_arm = Vector3(1.7 * F, -0.12, 0.0), r_elbow = 0.3}, &"out"],
				[1.0, {}, &"inout"],
			]
			blade = [
				[0.0, {}, &"linear"],
				[0.34, {sword = Vector3(0.35, -0.9 * W * A, 0.0)}, &"out"],
				[I - 0.045, {sword = Vector3(-0.85, 0.7, 0.0)}, &"in"],
				[0.62, {sword = Vector3(-1.6 * F, 1.25 * A * F, 0.2)}, &"back"],
				[1.0, {}, &"inout"],
			]
		_:   # &"flat": diagonal horizontal (alvo ao lado)
			body = [
				[0.0, {}, &"linear"],
				[0.34, {hips = Vector3(0, -0.12 * R, 0), spine = Vector3(-0.06 * W, -0.3 * R, 0.03), root = Vector3(0, -0.7, -1.6 * W), r_knee = 0.22, l_knee = 0.26, head = Vector3(0, 0.12, 0)}, &"out"],
				[I, {hips = Vector3(0, 0.12 * R, 0), spine = Vector3(0.2, 0.24 * R, -0.04), root = Vector3(0, -1.5, 2.4), l_knee = 0.46, r_knee = 0.16, head = Vector3(0.05, -0.1, 0)}, &"in"],
				[0.62, {hips = Vector3(0, 0.16 * R * F, 0), spine = Vector3(0.22, 0.34 * R * F, -0.05), root = Vector3(0, -1.6, 2.2), l_knee = 0.44, r_knee = 0.16, head = Vector3(0.06, -0.12, 0)}, &"out"],
				[1.0, {}, &"inout"],
			]
			arm = [
				[0.0, {}, &"linear"],
				[0.34, {r_arm = Vector3(1.5 * W, 0.75 * W, 0.0), r_elbow = 1.5}, &"out"],
				[I - 0.025, {r_arm = Vector3(1.2, 0.06, 0.0), r_elbow = 0.05}, &"in"],
				[0.62, {r_arm = Vector3(1.0 * F, -0.42 * F, 0.0), r_elbow = 0.35}, &"out"],
				[1.0, {}, &"inout"],
			]
			blade = [
				[0.0, {}, &"linear"],
				[0.34, {sword = Vector3(-2.05 * W * A, -0.35 * W * A, 0.3)}, &"out"],
				[I - 0.045, {sword = Vector3(0.02, 0.5, 0.1)}, &"in"],
				[0.62, {sword = Vector3(0.55 * F, 1.75 * A * F, 0.2)}, &"back"],
				[1.0, {}, &"inout"],
			]
	var d := track(body, p)
	var d_arm := track(arm, p - 0.025)
	var d_blade := track(blade, p - 0.045)
	var out := d.duplicate()
	for k in d_arm:
		out[k] = d_arm[k]
	for k in d_blade:
		out[k] = d_blade[k]
	# o escudo continua protegendo; o tabardo responde ao impacto
	var hit_w := clampf(1.0 - absf(p - I) / 0.2, 0.0, 1.0)
	out[&"cloth"] = Vector3(0.12 * hit_w, 0.14 * hit_w, -0.08 * hit_w)
	out[&"l_arm"] = Vector3(0.12, -0.05, 0.0) * clampf(p * 3.0, 0.0, 1.0) * clampf((1.0 - p) * 3.0, 0.0, 1.0)
	return out


## Provocação: firma os pés, baixa o centro, recua o escudo e o avança, peito aberto, encara.
## `p` 0..1 (TAUNT_TIME). Termina na pose de "guarda pronta" (a espera de 1 s até o escudo).
static func taunt(p: float) -> Dictionary:
	return track([
		[0.0, {}, &"linear"],
		[0.2, {root = Vector3(0, -1.6, 0), r_leg = Vector3(-0.08, 0.1, 0), l_leg = Vector3(0.1, 0.1, 0), r_knee = 0.26, l_knee = 0.3}, &"out"],
		[0.42, {root = Vector3(0, -2.0, -0.6), r_leg = Vector3(-0.1, 0.12, 0), l_leg = Vector3(0.12, 0.12, 0), r_knee = 0.3, l_knee = 0.34,
			l_arm = Vector3(-0.2, 0.25, 0), l_elbow = 0.5, shield = Vector3(0, 0.55, 0), spine = Vector3(0.02, -0.2, 0)}, &"inout"],
		[0.56, {root = Vector3(0, -2.2, 1.2), r_leg = Vector3(-0.12, 0.12, 0), l_leg = Vector3(0.18, 0.12, 0), r_knee = 0.3, l_knee = 0.42,
			l_arm = Vector3(0.5, -0.12, 0), l_elbow = -0.45, shield = Vector3(-0.05, -0.55, 0), spine = Vector3(-0.1, 0.24, 0),
			r_arm = Vector3(-0.35, 0.45, 0), r_elbow = -0.2, sword = Vector3(0.35, -0.7, 0), head = Vector3(-0.1, -0.1, 0),
			cloth = Vector3(0.14, 0.18, 0)}, &"back"],
		[1.0, guard_ready(), &"inout"],
	], p)


## Espera do escudo (depois da provocação): escudo dominante à frente, pés firmes, espada pronta.
static func guard_ready() -> Dictionary:
	return {root = Vector3(0, -2.0, 0.6), r_leg = Vector3(-0.12, 0.12, 0), l_leg = Vector3(0.16, 0.12, 0), r_knee = 0.3, l_knee = 0.38,
		l_arm = Vector3(0.42, -0.1, 0), l_elbow = -0.35, shield = Vector3(-0.04, -0.5, 0), spine = Vector3(-0.04, 0.2, 0),
		r_arm = Vector3(-0.2, 0.3, 0), r_elbow = 0.35, sword = Vector3(0.1, -0.35, 0), head = Vector3(-0.06, -0.08, 0)}


## Escudo Sagrado ativo: postura fechada, centro baixo, corpo atrás do escudo, espada pronta.
static func guard(t: float, look: PaladinRigLook) -> Dictionary:
	var b := sin(t * TAU / 1.4) * look.breathing
	return {root = Vector3(0, -2.6 + 0.12 * b, 0.4), r_leg = Vector3(-0.16, 0.16, 0), l_leg = Vector3(0.2, 0.14, 0), r_knee = 0.4, l_knee = 0.46,
		l_arm = Vector3(0.5, -0.16, 0), l_elbow = -0.3, shield = Vector3(-0.06, -0.62, 0), spine = Vector3(0.12 + 0.01 * b, 0.34, 0),
		r_arm = Vector3(0.1, 0.34, 0), r_elbow = 1.1, sword = Vector3(-0.5, -0.1, 0), head = Vector3(0.02, -0.26, 0),
		cloth = Vector3(0.05, 0.06, 0)}


## Bloqueio (o escudo absorveu um golpe). `p` 0..1 (BLOCK_TIME): recua rápido e volta.
static func block(p: float) -> Dictionary:
	var k := _pulse(p, 0.22)
	return {shield = Vector3(-0.22, 0.12, 0.04) * k, l_arm = Vector3(-0.18, 0.0, 0) * k, l_elbow = 0.35 * k,
		spine = Vector3(-0.07, -0.05, 0) * k, head = Vector3(-0.06, 0, 0) * k, root = Vector3(0, -0.5, -0.9) * k,
		r_knee = 0.1 * k, l_knee = 0.12 * k}


## Dano comum: reação curta de corpo pesado (sem voar para trás). `p` 0..1 (HIT_TIME).
static func hit(p: float) -> Dictionary:
	var k := _pulse(p, 0.25)
	return {spine = Vector3(-0.13, 0.04, 0.03) * k, head = Vector3(-0.1, 0.05, 0.04) * k,
		r_arm = Vector3(-0.08, 0.1, 0) * k, l_arm = Vector3(-0.06, 0.08, 0) * k, r_elbow = 0.1 * k, l_elbow = 0.1 * k,
		root = Vector3(0, -0.7, -0.6) * k, r_knee = 0.12 * k, l_knee = 0.12 * k, cloth = Vector3(0.05, 0.08, 0) * k}


## Empurrão (deslocamento real vindo da simulação): o centro de gravidade quebra na direção do
## empurrão e o pé de trás busca apoio. `dir` = direção do empurrão no espaço do corpo (x esquerda, z frente).
## Nenhum deslocamento aqui: só a postura.
static func push(p: float, dir: Vector3) -> Dictionary:
	var k := _pulse(p, 0.28)
	var step := sin(clampf((p - 0.15) / 0.5, 0.0, 1.0) * PI)
	var back := dir.z < 0.0                      # empurrado para trás
	var lean := Vector3(dir.z * 0.42, 0.0, -dir.x * 0.34)
	var d := {spine = lean * k + Vector3(0, dir.x * 0.1 * k, 0), head = -lean * 0.4 * k,
		root = Vector3(dir.x * 3.4, -1.4, dir.z * 3.4) * k, hips = lean * 0.5 * k,
		l_arm = Vector3(-dir.z * 0.25, 0.15, 0) * k, r_arm = Vector3(-dir.z * 0.2, 0.25, 0) * k,
		cloth = Vector3(-dir.z * 0.3, dir.z * 0.3, dir.x * 0.25) * k}
	# pé de trás (em relação ao empurrão) recua um passo para recuperar o apoio
	if back:
		d[&"r_leg"] = Vector3(-0.5 * step, 0.08 * step, 0)
		d[&"r_knee"] = 0.6 * step
		d[&"l_knee"] = 0.25 * k
	else:
		d[&"l_leg"] = Vector3(0.5 * step, 0.08 * step, 0)
		d[&"l_knee"] = 0.6 * step
		d[&"r_knee"] = 0.25 * k
	return d


## Morte pesada: golpe fatal → postura quebra → joelhos cedem → tronco cai para trás → chão →
## acomodação. `p` 0..1 (DEATH_TIME). Pose ABSOLUTA (não delta): termina no cadáver de costas.
static func death(p: float) -> Dictionary:
	var base := neutral()
	var kneel := add(base, {root = Vector3(0, -12.0, -1.0), r_leg = Vector3(0.95, 0.12, 0), l_leg = Vector3(0.35, 0.2, 0), r_knee = 1.9, l_knee = 1.45,
		spine = Vector3(0.2, -0.1, 0.08), head = Vector3(0.35, 0.1, 0.1), r_arm = Vector3(-0.2, 0.2, 0), r_elbow = -0.4,
		l_arm = Vector3(-0.3, 0.2, 0), l_elbow = -0.8, sword = Vector3(0.6, 0.2, 0)})
	var tip := add(kneel, {spine = Vector3(-0.35, 0.0, 0.05), head = Vector3(-0.25, 0.2, 0.1), body_rot = Vector3(-0.5, 0, 0.0),
		r_arm = Vector3(-0.1, 0.6, 0), l_arm = Vector3(-0.2, 0.7, 0)})
	var corpse := corpse_pose()
	var fatal := add(base, {spine = Vector3(-0.2, 0.08, 0.05), head = Vector3(-0.25, 0.1, 0.05), root = Vector3(0, -1.2, -1.4), r_knee = 0.25, l_knee = 0.2,
		r_arm = Vector3(-0.15, 0.3, 0), l_arm = Vector3(-0.12, 0.2, 0)})
	var impact := add(corpse, {body_pos = Vector3(0, 1.8, 0), spine = Vector3(-0.1, 0, 0), head = Vector3(-0.15, 0, 0)})
	var keys := [
		[0.0, base, &"linear"], [0.11, fatal, &"out"], [0.42, kneel, &"inout"], [0.62, tip, &"in"],
		[0.8, corpse, &"in"], [0.87, impact, &"out"], [1.0, corpse, &"inout"],
	]
	for i in range(1, keys.size()):
		if p <= keys[i][0]:
			var u: float = (p - keys[i - 1][0]) / (keys[i][0] - keys[i - 1][0])
			return mix(keys[i - 1][1], keys[i][1], ease_by(keys[i][2], u))
	return corpse


## Cadáver: deitado de costas, braços abertos, pernas meio dobradas (pose final da morte; base
## futura para a Necromancia). Sem chão automático: o corpo está deitado.
static func corpse_pose() -> Dictionary:
	return add(neutral(), {body_rot = Vector3(-PI / 2.0 - 0.02, 0.0, 0.0), body_pos = Vector3(0, 8.5, 44.0), ground = -1.0,
		root = Vector3(0, 0, 0), spine = Vector3(-0.05, 0, 0.04), head = Vector3(-0.1, 0.55, 0.0),
		r_arm = Vector3(0.1, 1.0, 0.3), r_elbow = 0.5, l_arm = Vector3(0.05, 0.9, 0.2), l_elbow = 0.6,
		r_leg = Vector3(0.35, 0.12, -0.1), r_knee = 0.55, l_leg = Vector3(0.15, 0.08, -0.2), l_knee = 0.3,
		cloth = Vector3(-0.3, -0.2, 0.1), sword = Vector3(0.0, 0.0, 0.0)})


## 0 → 1 rápido (até `peak`) e volta suave a 0.
static func _pulse(p: float, peak: float) -> float:
	if p <= 0.0 or p >= 1.0:
		return 0.0
	if p < peak:
		return ease_by(&"out", p / peak)
	return 1.0 - ease_by(&"inout", (p - peak) / (1.0 - peak))
