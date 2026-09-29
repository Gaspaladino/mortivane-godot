extends SceneTree
## Teste headless do Paladino Vivo com sprite sheets (PaladinSpriteVisual): recurso SpriteFrames,
## contrato de pivô (sem pulo entre animações), escala, e a escolha da animação pelo estado REAL
## (idle, walk, attack sincronizado com o dano, defend/defend_hold/defend_block, taunt, dano só
## pisca, death parado no último frame).
## O visual só lê a CombatUnit: nada de gameplay muda.
## Desde a etapa do rig 2.5D o Paladino Vivo usa o PaladinRigVisual por padrão; a cena de sprites
## continua no projeto como alternativa (UnitDef.visual_scene) e segue testada aqui.
##   godot --headless -s res://tests/paladin_sprite_test.gd

const VDT := 1.0 / 60.0
const DIR := "res://assets/units/paladin/"
const EXPECTED := {idle = [8, true], walk = [8, true], attack = [8, false], defend = [4, false],
	defend_hold = [4, true], defend_block = [2, false], taunt = [2, false], death = [8, false]}

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_resources()
	_test_pivot_contract()
	await _test_states()
	await _test_death_holds()
	print("paladin_sprite_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


# --- Recursos ---------------------------------------------------------------------------------

func _test_resources() -> void:
	var def := UnitCatalog.get_def(&"sac_paladin")
	_check(def.visual_scene != null and def.visual_scene.resource_path == "res://scenes/units/paladin_rig_visual.tscn", "Paladino Vivo usa o rig 2.5D por padrão")
	_check(load(SPRITE_SCENE) is PackedScene, "cena de sprites continua disponível como alternativa")
	_check(UnitCatalog.get_def(&"u_sac_paladin").visual_scene == null and UnitCatalog.get_def(&"u_sac_paladin").visual_script == ShadowPaladinVisual, "Paladino Sombra continua no visual atual")
	var sf: SpriteFrames = load(DIR + "paladin_frames.tres")
	_check(Array(sf.get_animation_names()).size() == EXPECTED.size() and not sf.has_animation(&"hit"), "só as animações do contrato (sem hit)")
	for anim in EXPECTED:
		_check(sf.has_animation(anim), "animação %s existe" % anim)
		if sf.has_animation(anim):
			_check(sf.get_frame_count(anim) == EXPECTED[anim][0] and sf.get_animation_loop(anim) == EXPECTED[anim][1],
				"%s: %d frames, loop=%s" % [anim, EXPECTED[anim][0], EXPECTED[anim][1]])
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "paladin_frames.json"))
	var cell := Vector2(meta.cell[0], meta.cell[1])
	var tex: Texture2D = load(DIR + "paladin_atlas.png")
	_check(tex.get_size() == Vector2(cell.x * 8, cell.y * 5), "atlas 8 × 5 células de %s" % cell)
	var imp := FileAccess.get_file_as_string(DIR + "paladin_atlas.png.import")
	_check(imp.contains("mipmaps/generate=true"), "atlas com mipmaps (reduzido ~3× no jogo sem serrilhar)")
	# o visual usa o contrato gerado pelo fatiador
	var v: PaladinSpriteVisual = load("res://scenes/units/paladin_sprite_visual.tscn").instantiate()
	_check(v.frame_size == cell and v.frame_pivot == Vector2(meta.pivot[0], meta.pivot[1]), "cena com a célula e o pivô do contrato")
	_check(v.attack_impact_frame == int(meta.attack_impact_frame), "frame de impacto do contrato (%d)" % v.attack_impact_frame)
	_check(v.frames == sf, "cena usa o SpriteFrames novo")
	v.free()
	# as sheets de origem ficam fora da importação do Godot
	_check(FileAccess.file_exists(DIR + "source/.gdignore") and FileAccess.file_exists(DIR + "source/paladin_attack.png"), "sheets originais guardadas em source/ (sem importar)")


## Em todos os frames de pé, o chão (última linha com massa de corpo; ponta de espada não conta)
## fica na linha do pivô (±2 px), e no idle os pés ficam centrados no pivô: trocar de animação não
## faz o Paladino pular nem afundar.
func _test_pivot_contract() -> void:
	var img: Image = (load(DIR + "paladin_atlas.png") as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var sf: SpriteFrames = load(DIR + "paladin_frames.tres")
	var v: PaladinSpriteVisual = load("res://scenes/units/paladin_sprite_visual.tscn").instantiate()
	var pivot := Vector2i(v.frame_pivot)
	v.free()
	var worst_y := 0
	var worst_idle_x := 0
	for anim in [&"idle", &"walk", &"attack", &"defend", &"defend_hold", &"defend_block", &"taunt"]:
		for i in sf.get_frame_count(anim):
			var region := Rect2i((sf.get_frame_texture(anim, i) as AtlasTexture).region)
			var bottom := -1
			for y in range(region.size.y - 1, -1, -1):
				var count := 0
				for x in region.size.x:
					if img.get_pixel(region.position.x + x, region.position.y + y).a > 0.78:
						count += 1
				if count >= 15:
					bottom = y
					break
			worst_y = maxi(worst_y, absi(bottom - pivot.y))
			if anim == &"idle":
				var xs := []
				for y in range(bottom - 5, bottom + 1):
					for x in region.size.x:
						if img.get_pixel(region.position.x + x, region.position.y + y).a > 0.78:
							xs.append(x)
				worst_idle_x = maxi(worst_idle_x, absi(int(round((xs.min() + xs.max()) / 2.0)) - pivot.x))
	_check(worst_y <= 2, "chão no pivô em todos os frames de pé (desvio máx. %d px)" % worst_y)
	_check(worst_idle_x <= 2, "idle: pés centrados no pivô (desvio máx. %d px)" % worst_idle_x)


# --- Estados ----------------------------------------------------------------------------------

const SPRITE_SCENE := "res://scenes/units/paladin_sprite_visual.tscn"


## Paladino Vivo com a cena de sprites escolhida (cópia da UnitDef; o catálogo não muda).
func _sprite_def() -> UnitDef:
	var def: UnitDef = UnitCatalog.get_def(&"sac_paladin").duplicate()
	def.visual_scene = load(SPRITE_SCENE)
	return def


func _make(team := CombatUnit.Team.PLAYER) -> UnitView:
	var def := _sprite_def()
	var u := CombatUnit.new(1, team, def.to_stats(), Vector2(400, 380))
	var view := UnitView.new(u, def)
	root.add_child(view)
	view.process_mode = Node.PROCESS_MODE_DISABLED   # o teste dirige o visual quadro a quadro
	return view


func _tick(v: PaladinSpriteVisual, seconds: float, move := Vector2.ZERO) -> void:
	for i in int(round(seconds / VDT)):
		v.unit.position += move * VDT
		v.update_visual(VDT)


func _test_states() -> void:
	var view := _make()
	await process_frame
	var v := view.visual as PaladinSpriteVisual
	_check(v != null, "UnitView cria o PaladinSpriteVisual pela cena")
	if v == null:
		return
	var u := v.unit
	var snap := [u.hp, u.max_hp, u.damage, u.attack_range, u.attack_interval, u.move_speed, u.radius]
	var s := v.sprite
	# pivô e escala
	_check(s.offset == v.frame_size / 2.0 - v.frame_pivot and s.position == Vector2(0, v.foot_y), "pivô do contrato nos pés da unidade")
	_check(is_equal_approx(s.scale.x, v.sprite_scale), "escala exposta aplicada ao sprite")
	var height := v.art_height * v.sprite_scale
	_check(height > 35.0 * 1.15 and height < 35.0 * 1.6, "maior que o Guerreiro (~35), sem virar chefe (%.1f)" % height)
	_check(v.top_y() < v.foot_y - height, "barra de HP acima da cabeça")
	# IDLE contínuo (não reinicia a cada quadro)
	_tick(v, 0.2)
	_check(v.mode == &"idle" and s.animation == &"idle" and s.is_playing(), "parado → idle em loop")
	s.frame = 3
	_tick(v, 0.1)
	_check(s.frame == 3, "idle não reinicia a cada quadro")
	# WALK com a velocidade real
	u.state = CombatUnit.State.MOVING
	_tick(v, 0.4, Vector2(u.move_speed, 0))
	_check(v.mode == &"walk" and s.animation == &"walk", "andando → walk")
	_check(absf(s.speed_scale - 1.0) < 0.15, "walk no ritmo da velocidade real (speed_scale %.2f)" % s.speed_scale)
	# ATTACK: preparação pela recarga real, segura antes do impacto, impacto NO evento de dano
	var foe := CombatUnit.new(2, CombatUnit.Team.ENEMY, UnitCatalog.get_def(&"warrior").to_stats(), u.position + Vector2(30, 0))
	u.target = foe
	u.state = CombatUnit.State.ATTACKING
	u.cooldown = 0.6
	_tick(v, 0.1)
	_check(v.mode != &"attack", "fora da janela de preparação ainda não ataca")
	u.cooldown = 0.2
	_tick(v, VDT)
	_check(v.mode == &"attack" and s.frame < v.attack_impact_frame, "preparação começa pela recarga real (frame %d)" % s.frame)
	u.cooldown = 0.01
	s.frame = v.attack_impact_frame - 1
	_tick(v, VDT)
	_check(s.frame == v.attack_impact_frame - 1 and not s.is_playing(), "segura antes do impacto até o dano real")
	u.cooldown = u.attack_interval
	v.on_attack_performed()
	_check(s.animation == &"attack" and s.frame == v.attack_impact_frame and s.is_playing(), "frame de impacto no instante do dano")
	v.on_hit()
	_check(v.mode == &"attack", "dano durante o golpe só pisca (não interrompe)")
	v._on_animation_finished()
	_tick(v, VDT)
	u.target = null
	u.state = CombatUnit.State.IDLE
	_tick(v, VDT)
	_check(v.mode == &"idle", "depois do golpe volta ao idle")
	# DANO: não há sheet de hit → pisca e recua um pouco, sem trocar a animação
	v.on_hit()
	_tick(v, VDT)
	_check(v.mode == &"idle" and s.modulate != Color.WHITE and s.position.x != 0.0, "dano → pisca e recua (sem trocar a animação)")
	_tick(v, 0.2)
	_check(s.modulate == Color.WHITE and s.position == Vector2(0, v.foot_y), "o recuo volta ao lugar")
	# TAUNT (evento real)
	v.on_ability_event(&"taunt")
	_tick(v, VDT)
	_check(v.mode == &"taunt" and s.animation == &"taunt", "provocação → taunt")
	v._on_animation_finished()
	_tick(v, VDT)
	_check(v.mode == &"idle", "taunt volta ao estado real")
	# DEFEND: espera do escudo, escudo ativo, bloqueio
	u.paladin.delay = 0.5
	_tick(v, VDT)
	_check(v.mode == &"defend" and s.frame == 0 and not s.is_playing(), "espera do escudo → guarda erguida (defend, frame 0)")
	u.paladin.delay = -1.0
	u.paladin.shield_t = 1.0
	u.paladin.facing = Vector2(1, 0)
	v.on_ability_event(&"shield")
	_tick(v, VDT)
	_check(v.mode == &"defend" and s.frame >= 1 and s.is_playing(), "escudo sobe → giro e clarão (defend)")
	v._on_animation_finished()
	_tick(v, VDT)
	_check(v.mode == &"defend_hold" and s.animation == &"defend_hold" and s.is_playing(), "segura a guarda em loop enquanto o escudo está ativo")
	v.on_ability_event(&"block")
	v.on_hit()
	_tick(v, VDT)
	_check(v.mode == &"defend_block" and s.animation == &"defend_block", "bloqueio (dano reduzido) → clarão; o dano não quebra a guarda")
	v._on_animation_finished()
	_tick(v, VDT)
	_check(v.mode == &"defend_hold", "depois do clarão volta à guarda")
	u.paladin.shield_t = 0.0
	_tick(v, 0.3)
	_check(v.mode == &"idle", "escudo acabou → idle")
	# espelho: inimigo olha para a esquerda
	u.team = CombatUnit.Team.ENEMY
	u.target = CombatUnit.new(3, CombatUnit.Team.PLAYER, UnitCatalog.get_def(&"u_warrior").to_stats(), u.position - Vector2(80, 0))
	_tick(v, VDT)
	_check(s.flip_h, "olhando para a esquerda: sprite espelhado")
	u.target = null
	_check([u.hp, u.max_hp, u.damage, u.attack_range, u.attack_interval, u.move_speed, u.radius] == snap, "visual não altera stats")
	view.queue_free()
	await process_frame


## Morte: toca uma vez e PARA no último frame (o corpo fica no campo), mesmo com eventos tardios.
func _test_death_holds() -> void:
	var view := _make()
	view.process_mode = Node.PROCESS_MODE_INHERIT   # aqui o sprite anima de verdade
	await process_frame
	var v := view.visual as PaladinSpriteVisual
	v.unit.die()
	await _frames(12)
	_check(v.mode == &"death" and v.sprite.animation == &"death", "morto → death")
	v.on_attack_performed()
	v.on_ability_event(&"taunt")
	v.on_hit()
	var t := 0.0
	while v.sprite.is_playing() and t < 3.0:
		await process_frame
		t += get_root().get_process_delta_time()
	await _frames(10)
	_check(v.sprite.animation == &"death" and v.sprite.frame == 7 and not v.sprite.is_playing(), "death para no último frame (%s %d)" % [v.sprite.animation, v.sprite.frame])
	_check(v.pick_rect().size.x > v.pick_rect().size.y, "área clicável do corpo deitado")
	_check(is_instance_valid(view) and view.is_inside_tree(), "o corpo continua no campo")
	view.queue_free()
	await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
