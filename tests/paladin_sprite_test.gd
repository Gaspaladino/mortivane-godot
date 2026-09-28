extends SceneTree
## Teste headless do Paladino Vivo com sprite sheet (PaladinSpriteVisual): recurso SpriteFrames,
## contrato de pivô (sem pulo entre animações), escala, e a escolha da animação pelo estado REAL
## (idle, walk, attack sincronizado com o dano, defend, taunt, hit, death parado no último frame).
## O visual só lê a CombatUnit: nada de gameplay muda.
##   godot --headless -s res://tests/paladin_sprite_test.gd

const VDT := 1.0 / 60.0
const EXPECTED := {idle = [6, true], walk = [8, true], attack = [6, false], defend = [4, false],
	taunt = [3, false], hit = [3, false], death = [6, false]}

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_resources()
	_test_pivot_contract()
	await _test_states()
	await _test_death_holds()
	await _test_sandbox()
	print("paladin_sprite_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


# --- Recursos ---------------------------------------------------------------------------------

func _test_resources() -> void:
	var def := UnitCatalog.get_def(&"sac_paladin")
	_check(def.visual_scene != null and def.visual_scene.resource_path == "res://scenes/units/paladin_sprite_visual.tscn", "Paladino Vivo usa a cena de sprites")
	_check(def.visual_script == PaladinVisual, "visual por código continua como fallback")
	_check(UnitCatalog.get_def(&"u_sac_paladin").visual_scene == null and UnitCatalog.get_def(&"u_sac_paladin").visual_script == ShadowPaladinVisual, "Paladino Sombra continua no visual atual")
	var sf: SpriteFrames = load("res://assets/sprites/paladin_live/paladin_live_frames.tres")
	for anim in EXPECTED:
		_check(sf.has_animation(anim), "animação %s existe" % anim)
		if sf.has_animation(anim):
			_check(sf.get_frame_count(anim) == EXPECTED[anim][0] and sf.get_animation_loop(anim) == EXPECTED[anim][1],
				"%s: %d frames, loop=%s" % [anim, EXPECTED[anim][0], EXPECTED[anim][1]])
	var tex: Texture2D = load("res://assets/sprites/paladin_live/paladin_live_atlas.png")
	_check(tex.get_size() == Vector2(320 * 8, 208 * 7), "atlas 8 × 7 células de 320 × 208")
	var imp := FileAccess.get_file_as_string("res://assets/sprites/paladin_live/paladin_live_atlas.png.import")
	_check(imp.contains("mipmaps/generate=true"), "atlas com mipmaps (reduzido ~2× no jogo sem serrilhar)")


## Em todos os frames de pé, os pés (base do corpo sólido) ficam no pivô da célula (±4 px):
## trocar de animação não faz o Paladino pular.
func _test_pivot_contract() -> void:
	var img: Image = (load("res://assets/sprites/paladin_live/paladin_live_atlas.png") as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var sf: SpriteFrames = load("res://assets/sprites/paladin_live/paladin_live_frames.tres")
	var pivot := Vector2i(160, 192)
	var worst_y := 0
	var worst_x := 0
	for anim in [&"idle", &"walk", &"attack", &"defend", &"taunt", &"hit"]:
		for i in sf.get_frame_count(anim):
			var region := (sf.get_frame_texture(anim, i) as AtlasTexture).region
			var bottom := -1
			for y in range(int(region.size.y) - 1, -1, -1):
				for x in int(region.size.x):
					if img.get_pixel(int(region.position.x) + x, int(region.position.y) + y).a > 0.78:
						bottom = y
						break
				if bottom >= 0:
					break
			var xs := []
			for y in range(bottom - 6, bottom + 1):
				for x in int(region.size.x):
					if img.get_pixel(int(region.position.x) + x, int(region.position.y) + y).a > 0.78:
						xs.append(x)
			var cx := int(round((xs.min() + xs.max()) / 2.0))
			worst_y = maxi(worst_y, absi(bottom - pivot.y))
			worst_x = maxi(worst_x, absi(cx - pivot.x))
	_check(worst_y <= 4 and worst_x <= 4, "pés no pivô em todos os frames de pé (desvio máx. %d px em y, %d em x)" % [worst_y, worst_x])


# --- Estados ----------------------------------------------------------------------------------

func _make(team := CombatUnit.Team.PLAYER) -> UnitView:
	var def := UnitCatalog.get_def(&"sac_paladin")
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
	_check(v.mode == &"attack", "hit durante o golpe só pisca (não interrompe)")
	v._on_animation_finished()
	_tick(v, VDT)
	u.target = null
	u.state = CombatUnit.State.IDLE
	_tick(v, VDT)
	_check(v.mode == &"idle", "depois do golpe volta ao idle")
	# HIT
	v.on_hit()
	_check(v.mode == &"hit" and s.animation == &"hit", "dano → hit")
	v._on_animation_finished()
	_tick(v, VDT)
	_check(v.mode == &"idle", "hit é curto e volta")
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
	_check(v.mode == &"defend" and s.frame == 0 and not s.is_playing(), "espera do escudo → ergue o escudo (frame 0)")
	u.paladin.delay = -1.0
	u.paladin.shield_t = 1.0
	u.paladin.facing = Vector2(1, 0)
	v.on_ability_event(&"shield")
	_tick(v, VDT)
	_check(v.mode == &"defend" and s.frame >= 1, "escudo sobe → clarão da guarda")
	v._on_animation_finished()
	_check(s.frame == 3 and not s.is_playing(), "segura a guarda enquanto o escudo está ativo")
	v.on_ability_event(&"block")
	v.on_hit()
	_check(v.mode == &"defend" and s.frame == 1, "bloqueio (dano reduzido) → clarão; o hit não quebra a guarda")
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
	_check(v.sprite.animation == &"death" and v.sprite.frame == 5 and not v.sprite.is_playing(), "death para no último frame (%s %d)" % [v.sprite.animation, v.sprite.frame])
	_check(v.pick_rect().size.x > v.pick_rect().size.y, "área clicável do corpo deitado")
	_check(is_instance_valid(view) and view.is_inside_tree(), "o corpo continua no campo")
	view.queue_free()
	await process_frame


# --- Sandbox real -----------------------------------------------------------------------------

func _test_sandbox() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.show_sandbox()
	await process_frame
	var sb: SandboxController = main.current_screen
	var battle := sb.arena.battle
	var btn: Button = sb.ui.find_child("Spawn_sac_paladin", true, false)
	_check(btn != null, "botão do Paladino no Sandbox")
	btn.pressed.emit()
	btn.pressed.emit()
	sb.add_unit(UnitCatalog.get_def(&"u_warrior"), CombatUnit.Team.PLAYER)
	sb.add_unit(UnitCatalog.get_def(&"u_sac_paladin"), CombatUnit.Team.PLAYER)
	await process_frame
	var pal: CombatUnit = battle.sim.units[0]
	var view := battle.view_of(pal)
	_check(view.visual is PaladinSpriteVisual, "Paladino Vivo no Sandbox usa a sprite sheet")
	_check(battle.view_of(battle.sim.units[3]).visual is ShadowPaladinVisual, "Paladino Sombra continua o visual atual")
	# seleção pela área clicável do sprite
	sb.select_at(pal.position + Vector2(0, -10))
	_check(sb.selected != null and sb.selected.unit == pal, "clique seleciona o Paladino de sprite")
	_check(pal.max_hp == 120.0 and pal.damage == 13.0 and pal.attack_range == 34.0 and pal.attack_interval == 1.2 and pal.move_speed == 44.0, "stats inalterados")
	sb.start_combat()
	var taunts := [0]
	var shields := [0]
	battle.sim.paladin_taunted.connect(func(_p: CombatUnit, _f: Array) -> void: taunts[0] += 1)
	battle.sim.paladin_shield_raised.connect(func(_p: CombatUnit) -> void: shields[0] += 1)
	var modes := {}
	var t := 0.0
	while not battle.is_finished() and t < 60.0:
		await process_frame
		battle._process(1.0 / 30.0)
		t += 1.0 / 30.0
		for u in battle.sim.units:
			var vis := battle.view_of(u).visual
			if vis is PaladinSpriteVisual:
				modes[vis.mode] = true
	_check(battle.is_finished(), "combate real termina (%.1f s)" % t)
	_check(taunts[0] > 0 and shields[0] > 0, "provocação e Escudo Sagrado continuam acontecendo")
	_check(modes.has(&"walk") and modes.has(&"attack"), "no combate real o sprite anda e ataca (%s)" % str(modes.keys()))
	sb.reset_combat()
	await process_frame
	_check(battle.sim.units.size() == 4 and battle.view_of(battle.sim.units[0]).visual is PaladinSpriteVisual, "Reiniciar recria com o sprite")
	sb.clear_arena()
	await process_frame
	_check(battle.sim.units.is_empty(), "Limpar esvazia")
	main.queue_free()
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
