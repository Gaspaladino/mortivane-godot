class_name ShadowWarriorVisual
extends WarriorVisual
## Guerreiro Sombra: o Guerreiro morto e reerguido pelo necromante. MESMO rig e mesma leitura
## de classe (elmo fechado, peitoral, espada, capa); convertido pela regra ShadowStyle:
##   - armadura em grafite violeta, capa quase preta com um resto do vermelho original;
##   - contorno roxo em todas as peças (a silhueta se destaca do chão e do fundo);
##   - olhos roxos na fenda do elmo, fissuras de energia no peitoral e no elmo;
##   - a pluma vira uma chama espectral; o fio da espada brilha;
##   - aura suave, névoa roxa no chão e poucos fiapos de fumaça subindo da capa e dos ombros.
## Animação: pesada e ameaçadora (não cambaleante como um zumbi); desaba para frente e se
## desfaz em fumaça ao morrer.


func _init() -> void:
	shadow = true
	# postura e animação
	idle_bob = 0.4
	idle_speed = 1.5
	jitter = 0.16
	posture_lean = 4.0
	head_tilt = 5.0
	head_drop = 0.3
	back_arm_rest = 16.0
	stride = 15.0
	leg_swing = 27.0
	leg_phase_gap = PI * 0.94
	back_leg_amp = 0.9
	walk_bob = 1.0
	walk_lurch = 2.0
	arm_swing = 11.0
	windup_time = 0.24
	strike_time = 0.08
	recover_time = 0.28
	rest_arm = -16.0
	rest_sword = 48.0
	windup_arm = 150.0
	windup_sword = -16.0
	windup_lean = -5.0
	strike_arm = -70.0
	strike_sword = 118.0
	strike_lean = 12.0
	lunge = 3.0
	death_time = 0.8
	death_forward = true


## A paleta viva do Guerreiro, convertida pela regra da sombra.
func _apply_shadow_style(s: ShadowStyle) -> void:
	metal = s.convert(metal)
	metal_dark = s.convert(metal_dark)
	metal_light = s.convert(metal_light).lightened(0.12)
	cloth = s.convert(cloth, 0.22)
	cloth_dark = s.convert(cloth_dark, 0.15)
	plume = s.energy
	leather = s.convert(leather)
	blade = s.convert(blade, 0.3)
	visor = s.body_dark
	visor_glow = s.energy
	flash_color = s.energy_core


## Dissolução da morte termina em 2,4 s (ver _draw_fx_front).
func corpse_settle_time() -> float:
	return maxf(death_time + 1.0, 2.5)


## 1 = de pé; cai a 0 enquanto o corpo escurece na morte.
func _life() -> float:
	return 1.0 - clampf(p_dim / 0.2, 0.0, 1.0)


func _pulse() -> float:
	return ShadowFX.pulse(shadow_style, _time, _seed)


# --- Pontos de extensão do rig -------------------------------------------------------------

# --- Peças e ossos da sombra ---------------------------------------------------------------
## Ossos extras (depois dos do corpo): névoa, aura, 7 brasas da chama, fiapos de fumaça.
const B_MIST := B_EXTRA
const B_AURA := B_EXTRA + 1
const B_EMBER := B_EXTRA + 2
const EMBERS := 7
const B_PUFF := B_EMBER + EMBERS
## Fiapos: 3 fontes × 2 (capa/ombros) + 2 × 1 (pés) + 4 × 3 (dissolução na morte).
const PUFFS := 20


func _extra_bones() -> int:
	return 2 + EMBERS + PUFFS


func _layout_back() -> Array:
	return [[_part("mist", _mist_shape, false, false), B_MIST], [_part("aura", _aura_shape, false, false), B_AURA]]


func _layout_head_back() -> Array:
	var out := []
	for j in EMBERS:
		out.append([_part("ember%d" % j, _ember_shape.bind(j), false, false), B_EMBER + j])
	return out


func _layout_front() -> Array:
	var puff := _part("puff", _puff_shape, false, false)
	var out := []
	for j in PUFFS:
		out.append([puff, B_PUFF + j])
	return out


## Névoa no chão (largura 9): poça roxa + núcleo escuro.
func _mist_shape() -> void:
	_bake.fill(LiteBuilder.ring(Vector2.ZERO, Vector2(9.0 * 1.35, 9.0 * 0.42), 24), Color(shadow_style.smoke, shadow_style.smoke.a * 0.35 * shadow_style.smoke_amount))
	_bake.fill(LiteBuilder.ring(Vector2.ZERO, Vector2(9.0, 9.0 * 0.3), 24), Color(0.02, 0.0, 0.05, 0.42))


## Aura atrás do corpo: elipses concêntricas com alfa crescente para dentro (raios 12 × 21).
func _aura_shape() -> void:
	var a := 0.09 * shadow_style.aura
	for i in 4:
		var s := 1.0 - i * 0.2
		_bake.fill(LiteBuilder.ring(Vector2.ZERO, Vector2(12.0 * s, 21.0 * s), 24), Color(shadow_style.energy, a * (0.55 + i * 0.35)))


## Brasa `j` da chama (raio 1): halo (1,7) + núcleo; cores pela posição na trilha.
func _ember_shape(j: int) -> void:
	var u := float(j) / (EMBERS - 1)
	_bake.disc(Vector2.ZERO, 1.7, Color(shadow_style.energy, 0.22 * (1.0 - u * 0.5)), 12)
	_bake.disc(Vector2.ZERO, 1.0, Color(shadow_style.energy.lerp(shadow_style.energy_core, 0.45 * (1.0 - u)), 0.85 * (1.0 - u * 0.6)), 10)


## Fiapo de fumaça de raio 1 (a forma do ShadowFX.smoke) na opacidade máxima.
func _puff_shape() -> void:
	_bake.fill(PackedVector2Array([
		Vector2(-1.0, 0.4), Vector2(-0.4, -1.2), Vector2(0.2, -2.4), Vector2(0.7, -0.9), Vector2(1.0, 0.5), Vector2(0.0, 1.0),
	]), Color(shadow_style.smoke, shadow_style.smoke.a * shadow_style.smoke_amount * 0.8))


# --- Pose dos ossos extras -----------------------------------------------------------------

func _pose_ground() -> void:
	var lying := clampf(absf(p_rot) / 90.0, 0.0, 1.0)
	var shift := 12.0 * lying * RIG_SCALE * _facing
	var w := (9.0 + 7.0 * lying) / 9.0
	var b := 0.95 + 0.05 * sin((_time + _seed) * 1.3)
	_skin.set_bone(B_MIST, Transform2D(0.0, Vector2(w * b, w), 0.0, Vector2(shift, FOOT_Y)))
	_skin.hide_bone(B_GROUND)


func _pose_extra(root: Transform2D, torso: Transform2D) -> void:
	var k := _life()
	# aura (some quando a energia se apaga)
	if k > 0.5:
		var pulse := 1.0 + 0.03 * sin((_time + _seed) * 1.7 * shadow_style.pulse_speed)
		_skin.set_bone(B_AURA, Transform2D(0.0, Vector2(pulse, pulse), 0.0, Vector2(0, FOOT_Y - 17.0 * RIG_SCALE) + p_offset * RIG_SCALE))
	else:
		_skin.hide_bone(B_AURA)
	# chama espectral: trilha ondulante de brasas presa ao elmo
	var head := _xf[P_HEAD]
	var drag := 1.0 + 0.35 * _walk_w
	var base := Vector2(-1.2, -12.2)
	for j in EMBERS:
		if k <= 0.0:
			_skin.hide_bone(B_EMBER + j)
			continue
		var u := float(j) / (EMBERS - 1)
		var wave := sin(_time * 6.0 - u * 4.0 + _seed) * (0.3 + 1.0 * u)
		var c := base + Vector2(-9.5 * u * drag, -1.0 + 2.8 * u + wave)
		var r := lerpf(2.1, 0.5, u) * (0.9 + 0.1 * sin(_time * 9.0 + j)) * sqrt(k)
		_skin.set_bone(B_EMBER + j, head * Transform2D(0.0, Vector2(r, r), 0.0, c))
	# fumaça: ombros/capa, pés e (na morte) o corpo se desfazendo
	var dissolve := 0.0
	if _death_t >= 0.0:
		dissolve = clampf(_death_t / 0.6, 0.0, 1.0) * (1.0 - clampf((_death_t - 1.2) / 1.2, 0.0, 1.0))
	var sw := -p_cape * 0.12
	var n := _smoke(B_PUFF, torso, PackedVector2Array([Vector2(-2.6, -12.0), Vector2(-9.8 + sw, 1.8), Vector2(-5.0 + sw * 0.6, 2.6)]),
		_time, _seed, 9.0, 1.5, 2, minf(maxf(k, dissolve * 1.8), 1.0))
	n = _smoke(n, root, PackedVector2Array([Vector2(-2.0, 0.0), Vector2(3.0, 0.0)]), _time * 0.8, _seed + 3.0, 5.0, 1.3, 1, k)
	n = _smoke(n, root, PackedVector2Array([Vector2(0, -6), Vector2(0, -14), Vector2(3, -22), Vector2(-3, -26)]),
		_time * 1.3, _seed + 7.0, 14.0, 2.2, 3, dissolve)


## Fiapos subindo de `sources` (mesma conta do ShadowFX.smoke); o esmaecer vira encolher.
## Devolve o próximo osso livre.
func _smoke(bone: int, space: Transform2D, sources: PackedVector2Array, time: float, seed: float,
		rise: float, size: float, count: int, k: float) -> int:
	for si in sources.size():
		for j in count:
			if k <= 0.0:
				_skin.hide_bone(bone)
			else:
				var h := ShadowFX._hash(si * 7.0 + j, seed)
				var u := fposmod(time * (0.32 + 0.18 * h) + h + float(j) / count, 1.0)
				var p := sources[si] + Vector2(sin(u * 5.0 + h * 9.0) * 1.6 + u * 1.2, -rise * u)
				var r := size * (1.0 - 0.55 * u) * (0.8 + 0.4 * h) * sin(u * PI) * k
				_skin.set_bone(bone, space * Transform2D(0.0, Vector2(r, r), 0.0, p))
			bone += 1
	return bone


## Capa rasgada em pontas irregulares.
func _cape_shape(pts: PackedVector2Array) -> PackedVector2Array:
	var a := pts[2]
	var b := pts[3]
	var c := pts[4]
	return PackedVector2Array([
		pts[0], pts[1],
		a + Vector2(-0.4, 0.8), a.lerp(b, 0.35) + Vector2(0.3, -2.2), a.lerp(b, 0.6) + Vector2(0, 1.2),
		b + Vector2(0, -0.8), b.lerp(c, 0.5) + Vector2(0.2, -2.6), c,
	])


## Barra da capa com um fio de energia.
func _draw_cape_extra(shape: PackedVector2Array) -> void:
	_pline(shape.slice(2), Color(shadow_style.energy, 0.45), 0.8)


## Pluma → base escura (peça do elmo); a chama espectral são brasas com ossos (_pose_extra).
func _draw_plume() -> void:
	var base := Vector2(-1.2, -12.2)
	_poly(PackedVector2Array([base + Vector2(1.2, 0.2), base + Vector2(-2.4, -1.8), base + Vector2(-4.6, 0.6), base + Vector2(-1.6, 1.2)]), _c(metal_dark))


## Olhos: dois pontos roxos na fenda do elmo (lidos mesmo de longe).
func _draw_visor() -> void:
	var slit := PackedVector2Array([Vector2(1.0, -6.9), Vector2(6.2, -7.2), Vector2(6.2, -5.7), Vector2(1.0, -5.6)])
	_fill(slit, _c(visor))
	LiteShadowParts.eye(self, Vector2(3.4, -6.3), 0.75, shadow_style)
	LiteShadowParts.eye(self, Vector2(5.4, -6.4), 0.7, shadow_style)


## Fissuras de energia no peitoral.
func _draw_torso_wear() -> void:
	LiteShadowParts.crack(self, PackedVector2Array([Vector2(-1.4, -12.4), Vector2(-0.4, -10.2), Vector2(-1.8, -8.2), Vector2(-0.6, -5.8), Vector2(-1.4, -3.2)]), shadow_style)
	LiteShadowParts.crack(self, PackedVector2Array([Vector2(-0.4, -10.2), Vector2(1.6, -9.4), Vector2(2.4, -8.0)]), shadow_style, 0.8)


func _draw_helmet_wear() -> void:
	LiteShadowParts.crack(self, PackedVector2Array([Vector2(-3.8, -11.4), Vector2(-2.3, -9.9), Vector2(-3.1, -8.4)]), shadow_style, 0.8)


## Lâmina lascada (a arma do Guerreiro, gasta pela morte).
func _blade_shape() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-1.25, -1.9), Vector2(1.25, -1.9), Vector2(1.15, -7.6), Vector2(0.4, -8.4),
		Vector2(1.05, -9.6), Vector2(1.0, -13.4), Vector2(0.0, -15.8), Vector2(-1.1, -13.4),
	])


## Fio da espada aceso em roxo.
func _draw_blade_extra() -> void:
	LiteShadowParts.crack(self, PackedVector2Array([Vector2(0, -2.4), Vector2(0.1, -8.0), Vector2(-0.1, -13.6)]), shadow_style, 1.0, 0.6)
