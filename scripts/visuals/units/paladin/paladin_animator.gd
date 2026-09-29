class_name PaladinAnimator
extends RefCounted
## Decide COMO o Paladino Vivo aparece a partir do que a simulação diz que aconteceu.
## Só LÊ a CombatUnit (posição, estado, alvo, recarga, habilidade) e recebe os eventos repassados
## pela Battle; nunca escreve nada na simulação.
##
## Camadas (somadas sobre a pose-base da direção, PaladinPoseLibrary):
##   locomoção  idle ↔ walk          peso `move_w` suavizado (desacelera/acelera, sem estalo)
##   ação       attack | defesa      attack: preparação pela recarga real, impacto no evento real
##                                    defesa: taunt → guarda pronta (espera 1 s) → guarda (escudo)
##   reações    hit, block, push     aditivas e curtas: voltam sozinhas ao estado anterior
##   morte      pose absoluta        queda pesada → cadáver (arma e escudo se soltam e caem)
## Movimento secundário: molas na espada, no escudo, no tabardo e na auréola.


var look: PaladinRigLook

# --- Estado lido/derivado ---
var dir: PaladinPoseLibrary.Dir = PaladinPoseLibrary.Dir.RIGHT
var lateral := 1.0              # +1 olhando para a direita, −1 para a esquerda (DOWN/UP pendem para cá)
var yaw := 0.0
var move_w := 0.0
var walk_phase := 0.0
var speed := 0.0

# --- Ação: ataque ---
var attack_active := false
var attack_struck := false
var attack_p := 0.0
var attack_w := 0.0
var attack_variant := &"flat"
var attack_dir: PaladinPoseLibrary.Dir = PaladinPoseLibrary.Dir.RIGHT

# --- Ação: defesa (provocação / escudo) ---
var taunt_t := -1.0
var defense_w := 0.0
var guard_blend := 0.0          # 0 = guarda pronta (espera), 1 = guarda com o escudo ativo

# --- Reações ---
var hit_t := -1.0
var block_t := -1.0
var push_t := -1.0
var push_dir := Vector3.ZERO    # no espaço do corpo

# --- Morte ---
var dead := false
var death_t := 0.0
var sword_drop: Dictionary = {}   # {from: Transform3D, t: float}
var shield_drop: Dictionary = {}

# --- Prévia do Sandbox (só apresentação, não toca na unidade) ---
var preview_kind := &""
var preview_dir: PaladinPoseLibrary.Dir = PaladinPoseLibrary.Dir.RIGHT
var preview_t := 0.0

var _t := 0.0
var _last_pos := Vector2.ZERO
var _base: Dictionary = {}
var _spring_sword := Spring.new()
var _spring_shield := Spring.new()
var _spring_cloth := Spring.new()
var _spring_halo := Spring.new()
var _vel_body := Vector3.ZERO
var _first := true

## Para depuração: estado e progresso da apresentação.
var debug_state := &"IDLE"
var debug_progress := 0.0


## Mola criticamente amortecida (segue o alvo com atraso natural, sem oscilar demais).
class Spring:
	var x = null
	var v = null

	func step(target, dt: float, freq: float, damping := 0.85):
		if x == null:
			x = target
			v = target * 0.0
			return x
		if dt <= 0.0:
			return x
		var w := TAU * freq
		var f := 1.0 + 2.0 * dt * damping * w
		var oo := w * w
		var hoo := dt * oo
		var hhoo := dt * hoo
		var det := 1.0 / (f + hhoo)
		var nx = (x * f + v * dt + target * hhoo) * det
		var nv = (v + (target - x) * hoo) * det
		x = nx
		v = nv
		return x


func setup(p_look: PaladinRigLook, unit: CombatUnit) -> void:
	look = p_look
	lateral = 1.0 if unit.team == CombatUnit.Team.PLAYER else -1.0
	dir = PaladinPoseLibrary.Dir.RIGHT if lateral > 0.0 else PaladinPoseLibrary.Dir.LEFT
	yaw = PaladinPoseLibrary.dir_yaw(dir, lateral)
	_last_pos = unit.position
	_base = PaladinPoseLibrary.base_for(dir, yaw)


# --- Eventos (repassados pelo visual) --------------------------------------------------------

func notify_attack() -> void:
	if dead:
		return
	if not attack_active:
		_start_attack(dir)
		attack_p = PaladinPoseLibrary.ATTACK_IMPACT - 0.08   # sem preparação vista: ainda mostra o fim do movimento
	attack_struck = true
	attack_p = maxf(attack_p, PaladinPoseLibrary.ATTACK_IMPACT)


func notify_hit() -> void:
	if dead or (block_t >= 0.0 and block_t < 0.05):
		return   # o golpe foi no escudo: a reação é o bloqueio
	hit_t = 0.0


func notify_block() -> void:
	if not dead:
		block_t = 0.0
		hit_t = -1.0


func notify_taunt() -> void:
	if not dead:
		taunt_t = 0.0


func notify_shield() -> void:
	pass   # a guarda sobe pelo estado real (is_shielded) — o evento só dispara efeitos


## Empurrão vindo da simulação (direção na tela, y para baixo). Só postura: a posição é da simulação.
func notify_push(screen_dir: Vector2) -> void:
	if dead or screen_dir.length() < 0.001:
		return
	var d := screen_dir.normalized()
	var w := Vector3(d.x, 0.0, d.y)
	push_dir = Basis(Vector3.UP, -yaw) * w   # para o espaço do corpo
	push_t = 0.0


## Prévia (Sandbox): &"idle", &"walk", &"attack", &"hit", &"push", &"taunt", &"shield", &"block",
## &"death", ou &"" para voltar ao estado real.
func preview(kind: StringName, p_dir: PaladinPoseLibrary.Dir) -> void:
	preview_kind = kind
	preview_dir = p_dir
	preview_t = 0.0
	dead = false
	death_t = 0.0
	sword_drop.clear()
	shield_drop.clear()
	attack_active = false
	attack_w = 0.0
	taunt_t = -1.0
	match kind:
		&"attack":
			_start_attack(p_dir)
		&"hit":
			hit_t = 0.0
		&"push":
			var sd := Vector2(-1.0 if lateral > 0.0 else 1.0, 0.25)
			notify_push(sd)
		&"taunt":
			taunt_t = 0.0
		&"block":
			block_t = 0.0


# --- Quadro ---------------------------------------------------------------------------------

## Pose do quadro. `rig` é consultado só para soltar arma/escudo na morte (posição atual deles).
func update(delta: float, unit: CombatUnit, rig: PaladinRig) -> Dictionary:
	_t += delta
	var pal := unit.paladin
	var moved := unit.position - _last_pos
	_last_pos = unit.position
	if _first:
		_first = false
		moved = Vector2.ZERO
	var alive := unit.is_alive()
	var pv := preview_kind != &""
	if pv:
		preview_t += delta

	# --- empurrão real: deslocamento que a caminhada não explica (a simulação moveu a unidade) ---
	if alive and not pv and delta > 0.0:
		var expected := unit.move_speed * delta if unit.state == CombatUnit.State.MOVING else 0.0
		if moved.length() > expected * 1.35 + 0.35:
			notify_push(moved)

	# --- velocidade e peso da caminhada ---
	var walking := false
	var move_vec := Vector2.ZERO
	if pv:
		walking = preview_kind == &"walk"
		move_vec = _dir_vector(preview_dir) if walking else Vector2.ZERO
		speed = look.walk_reference_speed if walking else 0.0
	elif alive and delta > 0.0:
		walking = moved.length() > 0.01
		move_vec = moved
		speed = lerpf(speed, moved.length() / delta, 1.0 - exp(-delta * 10.0))
	var walk_target := 1.0 if walking and attack_w < 0.5 else 0.0
	move_w = move_toward(move_w, walk_target, delta * (4.5 if walk_target > move_w else 5.5))
	walk_phase = fposmod(walk_phase + delta * clampf(speed / look.walk_reference_speed, 0.4, 1.8) / look.walk_cycle * (1.0 if move_w > 0.01 else 0.0), 1.0)

	# --- direção ---
	var face := Vector2.ZERO
	if pv:
		face = _dir_vector(preview_dir)
	elif alive:
		if pal and pal.is_shielded() and pal.facing != Vector2.ZERO:
			face = pal.facing
		elif (attack_active or unit.state == CombatUnit.State.ATTACKING) and unit.target:
			face = unit.target.position - unit.position
		elif walking:
			face = move_vec
		elif unit.target:
			face = unit.target.position - unit.position
	if face.length() > 0.001 and not dead:
		if absf(face.x) > 0.2 * face.length():
			lateral = signf(face.x)
		dir = _quantize(face, dir)
	var target_yaw := PaladinPoseLibrary.dir_yaw(dir, lateral)
	if dead:
		# cai de costas atravessado na tela (3/4), para o cadáver ficar legível
		target_yaw = lateral * 1.2 if death_t > 0.12 * PaladinPoseLibrary.DEATH_TIME else yaw
	yaw = _approach_angle(yaw, target_yaw, delta)
	_base = PaladinPoseLibrary.mix(_base, PaladinPoseLibrary.base_for(dir, yaw), 1.0 - exp(-delta * 10.0)) if not _base.is_empty() else PaladinPoseLibrary.base_for(dir, yaw)

	# --- ataque (sincronizado com a recarga real e o evento de dano) ---
	if alive and not pv:
		var lead := _time_to_impact(unit)
		var windup := PaladinPoseLibrary.ATTACK_IMPACT * PaladinPoseLibrary.ATTACK_TIME
		if not attack_active and lead >= 0.0 and lead <= windup:
			_start_attack(dir)
			attack_p = clampf((windup - lead) / PaladinPoseLibrary.ATTACK_TIME, 0.0, PaladinPoseLibrary.ATTACK_IMPACT - 0.01)
		if attack_active and not attack_struck:
			if lead < 0.0 and attack_p < PaladinPoseLibrary.ATTACK_IMPACT - 0.1:
				attack_active = false   # o alvo sumiu antes do golpe: desiste (a camada some suave)
			else:
				var goal := (windup - maxf(lead, 0.0)) / PaladinPoseLibrary.ATTACK_TIME if lead >= 0.0 else attack_p + delta / PaladinPoseLibrary.ATTACK_TIME
				attack_p = clampf(maxf(attack_p, goal), 0.0, PaladinPoseLibrary.ATTACK_IMPACT - 0.005)   # segura antes do impacto
	if attack_active and (attack_struck or pv):
		attack_p += delta / PaladinPoseLibrary.ATTACK_TIME
		if pv and not attack_struck and attack_p >= PaladinPoseLibrary.ATTACK_IMPACT:
			attack_struck = true
		if attack_p >= 1.0:
			attack_active = false
			attack_p = 1.0
	attack_w = move_toward(attack_w, 1.0 if attack_active else 0.0, delta * (9.0 if attack_active else 5.0))

	# --- defesa (provocação → espera → escudo) ---
	var preparing := false
	var shielded := false
	if pv:
		preparing = preview_kind == &"taunt" and preview_t > PaladinPoseLibrary.TAUNT_TIME and preview_t < PaladinPoseLibrary.TAUNT_TIME + 1.0
		shielded = (preview_kind == &"taunt" and preview_t >= PaladinPoseLibrary.TAUNT_TIME + 1.0 and preview_t < PaladinPoseLibrary.TAUNT_TIME + 2.5) \
			or (preview_kind in [&"shield", &"block"] and preview_t < 2.2)
	elif alive and pal:
		preparing = pal.is_preparing()
		shielded = pal.is_shielded()
	if taunt_t >= 0.0:
		taunt_t += delta
		if taunt_t >= PaladinPoseLibrary.TAUNT_TIME:
			taunt_t = -1.0   # taunt(1) == guarda pronta: a espera/escudo continuam sem salto
	var defending := taunt_t >= 0.0 or preparing or shielded
	defense_w = move_toward(defense_w, 1.0 if defending else 0.0, delta * (7.0 if defending else 3.2))
	guard_blend = move_toward(guard_blend, 1.0 if shielded else 0.0, delta * 4.5)

	# --- reações ---
	hit_t = _advance(hit_t, delta, PaladinPoseLibrary.HIT_TIME)
	block_t = _advance(block_t, delta, PaladinPoseLibrary.BLOCK_TIME)
	push_t = _advance(push_t, delta, PaladinPoseLibrary.PUSH_TIME)

	# --- composição ---
	var pose := _base
	var act := maxf(attack_w, defense_w)
	pose = PaladinPoseLibrary.add(pose, PaladinPoseLibrary.idle(_t, look), 1.0 - move_w * 0.85)
	pose = PaladinPoseLibrary.add(pose, PaladinPoseLibrary.walk(walk_phase, move_w, look), 1.0 - act)
	if defense_w > 0.0:
		var d: Dictionary
		if taunt_t >= 0.0:
			d = PaladinPoseLibrary.taunt(clampf(taunt_t / PaladinPoseLibrary.TAUNT_TIME, 0.0, 1.0))
		else:
			d = PaladinPoseLibrary.mix_delta(PaladinPoseLibrary.guard_ready(), PaladinPoseLibrary.guard(_t, look), guard_blend)
		pose = PaladinPoseLibrary.add(pose, d, defense_w * (1.0 - attack_w * 0.55))
	if attack_w > 0.0:
		pose = PaladinPoseLibrary.add(pose, PaladinPoseLibrary.attack(attack_p, attack_variant, look), attack_w)
	if hit_t >= 0.0:
		pose = PaladinPoseLibrary.add(pose, PaladinPoseLibrary.hit(hit_t / PaladinPoseLibrary.HIT_TIME))
	if block_t >= 0.0:
		pose = PaladinPoseLibrary.add(pose, PaladinPoseLibrary.block(block_t / PaladinPoseLibrary.BLOCK_TIME))
	if push_t >= 0.0:
		pose = PaladinPoseLibrary.add(pose, PaladinPoseLibrary.push(push_t / PaladinPoseLibrary.PUSH_TIME, push_dir))

	# --- morte ---
	var dying := (not alive and not pv) or (pv and preview_kind == &"death")
	if dying:
		if not dead:
			dead = true
			death_t = 0.0
			attack_active = false
			taunt_t = -1.0
		death_t += delta
		var dp := clampf(death_t / PaladinPoseLibrary.DEATH_TIME, 0.0, 1.0)
		pose = PaladinPoseLibrary.mix(pose, PaladinPoseLibrary.death(dp), clampf(death_t / 0.08, 0.0, 1.0))
		_update_drops(rig, dp, delta)
	elif dead:   # só na prévia: volta a ficar de pé
		dead = false
		sword_drop.clear()
		shield_drop.clear()
		rig.overrides.clear()
	if pv and preview_kind != &"walk" and preview_t > _preview_length(preview_kind):
		preview_kind = &""

	# --- movimento secundário (molas) ---
	var sm := look.secondary_motion
	if move_vec.length() > 0.0 and delta > 0.0:
		var v3 := Basis(Vector3.UP, -yaw) * Vector3(move_vec.x, 0.0, move_vec.y) / maxf(delta, 1e-4)
		_vel_body = _vel_body.lerp(v3, 1.0 - exp(-delta * 8.0))
	else:
		_vel_body = _vel_body.lerp(Vector3.ZERO, 1.0 - exp(-delta * 8.0))
	if sm > 0.0 and not dead:
		# no golpe a espada acompanha quase sem atraso (o impacto precisa cair no quadro do dano)
		var sword_hz := lerpf(30.0, 11.0, clampf(sm, 0.0, 1.5) / 1.5) * (1.0 + attack_w * 2.5)
		pose[&"sword"] = _spring_sword.step(pose.sword, delta, sword_hz)
		pose[&"shield"] = _spring_shield.step(pose.shield, delta, lerpf(30.0, 7.5, clampf(sm, 0.0, 1.5) / 1.5))
		var cloth_goal: Vector3 = pose.cloth + Vector3(clampf(_vel_body.z * 0.004, -0.2, 0.25), clampf(_vel_body.z * 0.004, -0.2, 0.25), clampf(-_vel_body.x * 0.003, -0.15, 0.15)) * look.cloth_amplitude
		pose[&"cloth"] = _spring_cloth.step(cloth_goal, delta, lerpf(12.0, 2.6, clampf(look.cloth_inertia, 0.0, 2.0) / 2.0), 0.55)
		pose[&"halo"] = _spring_halo.step(pose.halo, delta, 3.0, 0.7)
	_update_debug(pose)
	return pose


# --- Interno ----------------------------------------------------------------------------------

func _start_attack(d: PaladinPoseLibrary.Dir) -> void:
	attack_active = true
	attack_struck = false
	attack_p = 0.0
	attack_dir = d
	attack_variant = PaladinPoseLibrary.attack_variant(d)


static func _advance(t: float, delta: float, length: float) -> float:
	if t < 0.0:
		return t
	t += delta
	return t if t < length else -1.0


func _approach_angle(from: float, to: float, delta: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	var step := diff * (1.0 - exp(-delta * look.turn_speed))
	var max_step := look.turn_speed * 1.2 * delta
	return from + clampf(step, -max_step, max_step)


## Quantiza em 8 direções com histerese (não fica trocando na fronteira entre duas).
func _quantize(v: Vector2, current: PaladinPoseLibrary.Dir) -> PaladinPoseLibrary.Dir:
	var a := atan2(v.x, v.y)
	var cur := int(current) * PI / 4.0
	if absf(wrapf(a - cur, -PI, PI)) < PI / 8.0 + 0.14:
		return current
	return PaladinPoseLibrary.dir_from_vector(v)


static func _dir_vector(d: PaladinPoseLibrary.Dir) -> Vector2:
	var a := int(d) * PI / 4.0
	return Vector2(sin(a), cos(a))


## Segundos até o dano previsto; −1 = nenhum golpe a caminho.
## No alcance: a recarga real; chegando: distância que falta ÷ velocidade (recarga já pronta).
static func _time_to_impact(unit: CombatUnit) -> float:
	var t := unit.target
	if t == null or not t.is_alive():
		return -1.0
	if unit.state == CombatUnit.State.ATTACKING and unit.cooldown > 0.0:
		return unit.cooldown
	if unit.cooldown <= 0.0 and unit.move_speed > 0.0:
		var gap := unit.position.distance_to(t.position) - unit.attack_range
		if gap > 0.0:
			return gap / unit.move_speed
		return 0.0
	return -1.0


## Espada e escudo se soltam na queda: saem de onde estavam e caem no chão ao lado do corpo.
func _update_drops(rig: PaladinRig, dp: float, dt: float) -> void:
	if rig == null:
		return
	if sword_drop.is_empty() and dp >= 0.46:
		sword_drop = {from = rig.bone(&"sword"), t = 0.0}
	if shield_drop.is_empty() and dp >= 0.56:
		shield_drop = {from = rig.bone(&"shield"), t = 0.0}
	if not sword_drop.is_empty():
		sword_drop.t += dt
		rig.overrides[&"sword"] = _drop(sword_drop, Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)).rotated(Vector3.UP, 0.35), Vector3(-19.0, 0.9, -12.0)), 0.42)
	if not shield_drop.is_empty():
		shield_drop.t += dt
		# o escudo escorrega do braço esquerdo e para além dos pés, face para cima (visível)
		rig.overrides[&"shield"] = _drop(shield_drop, Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)).rotated(Vector3.UP, -0.6), Vector3(13.0, 1.2, 31.0)), 0.48)


static func _drop(state: Dictionary, rest: Transform3D, length: float) -> Transform3D:
	var from: Transform3D = state.from
	var u := clampf(float(state.t) / length, 0.0, 1.0)
	var fall := u * u   # gravidade
	var pos := from.origin.lerp(rest.origin, u)
	pos.y = lerpf(from.origin.y, rest.origin.y, fall)
	if u >= 1.0:
		var bt := clampf((float(state.t) - length) / 0.18, 0.0, 1.0)
		pos.y = rest.origin.y + sin(bt * PI) * 1.4 * (1.0 - bt)   # quique curto no chão
	var q := from.basis.get_rotation_quaternion().slerp(rest.basis.get_rotation_quaternion(), ease(u, 0.6))
	var sc := from.basis.get_scale()
	return Transform3D(Basis(q).scaled(sc), pos)


func _preview_length(kind: StringName) -> float:
	match kind:
		&"attack":
			return PaladinPoseLibrary.ATTACK_TIME + 0.3
		&"hit":
			return PaladinPoseLibrary.HIT_TIME + 0.3
		&"push":
			return PaladinPoseLibrary.PUSH_TIME + 0.3
		&"taunt":
			return PaladinPoseLibrary.TAUNT_TIME + 2.9
		&"shield":
			return 2.6
		&"block":
			return 2.6
		&"death":
			return INF   # a prévia da morte fica no cadáver até outra prévia
		&"idle":
			return 3.0
	return 0.0


func _update_debug(pose: Dictionary) -> void:
	if dead:
		debug_state = &"DEATH" if death_t < PaladinPoseLibrary.DEATH_TIME else &"CORPSE"
		debug_progress = clampf(death_t / PaladinPoseLibrary.DEATH_TIME, 0.0, 1.0)
	elif attack_active:
		debug_state = StringName("ATTACK_" + String(attack_variant).to_upper())
		debug_progress = attack_p
	elif taunt_t >= 0.0:
		debug_state = &"TAUNT"
		debug_progress = taunt_t / PaladinPoseLibrary.TAUNT_TIME
	elif defense_w > 0.5:
		debug_state = &"SHIELD_ACTIVE" if guard_blend > 0.5 else &"GUARD_READY"
		debug_progress = guard_blend
	elif move_w > 0.5:
		debug_state = &"WALK"
		debug_progress = walk_phase
	else:
		debug_state = &"IDLE"
		debug_progress = fposmod(_t / look.idle_cycle, 1.0)
	if block_t >= 0.0:
		debug_state = StringName(String(debug_state) + "+BLOCK")
	if hit_t >= 0.0:
		debug_state = StringName(String(debug_state) + "+HIT")
	if push_t >= 0.0:
		debug_state = StringName(String(debug_state) + "+PUSH")
