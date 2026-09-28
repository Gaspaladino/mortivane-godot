extends SceneTree
## Teste headless da regra visual "sombra necromântica" (ShadowStyle + ShadowFX):
## toda unidade revivida (u_*) tem visual de sombra convertido da versão viva, com a mesma
## silhueta de classe; a versão viva continua normal; nada disso altera stats.
##   godot --headless -s res://tests/shadow_visual_test.gd

const DT := 1.0 / 60.0

var _failures := 0


func _initialize() -> void:
	_test_style()
	_test_catalog_rule()
	for pair in [[&"warrior", &"u_warrior"], [&"arc_battlemage", &"u_arc_battlemage"]]:
		_test_pair(pair[0], pair[1])
	print("shadow_visual_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _test_style() -> void:
	var st := ShadowStyle.get_default()
	_check(st != null and st.resource_path == ShadowStyle.DEFAULT_PATH, "estilo padrão vem de data/visuals/shadow_style.tres (editável)")
	var steel := Color("b8bfc9")
	var gold := Color("d9a93c")
	_check(st.convert(steel).get_luminance() < steel.get_luminance() * 0.5, "convert escurece o corpo")
	var dark_gold := st.convert(gold)
	var kept_gold := st.convert(gold, 1.0)
	_check(kept_gold.r - kept_gold.b > dark_gold.r - dark_gold.b + 0.1, "convert(keep) preserva o matiz de acentos (ex.: ouro)")
	_check(st.energy.b > st.energy.g and st.energy.r > st.energy.g, "energia do necromante é roxa")
	for i in 50:
		var p := ShadowFX.pulse(st, i * 0.37, 1.0)
		if p < -0.001 or p > 1.001:
			_check(false, "pulse fora de 0..1 (%.2f)" % p)
			break


## Regra do projeto: u_* = sombra; o resto = viva.
func _test_catalog_rule() -> void:
	for def in UnitCatalog.all():
		if def.visual_script == null:
			continue
		var v: UnitVisual = _make(def.id)
		var is_undead := String(def.id).begins_with("u_")
		var shadow: bool = v is CodeDrawnUnitVisual and v.shadow
		_check(shadow == is_undead, "%s: %s" % [def.id, "visual de sombra" if is_undead else "visual vivo"])
		v.free()


func _test_pair(living_id: StringName, shadow_id: StringName) -> void:
	var live: CodeDrawnUnitVisual = _make(living_id)
	var dead: CodeDrawnUnitVisual = _make(shadow_id)
	var tag := String(shadow_id)
	_check(live.shadow_style == null and dead.shadow_style == ShadowStyle.get_default(), "%s: estilo só na sombra" % tag)
	_check(dead.outline == dead.shadow_style.edge and dead.outline != live.outline, "%s: contorno da regra" % tag)
	# mesma classe: mesmo rig/silhueta (área clicável e altura da barra de HP iguais)
	_check(live.pick_rect() == dead.pick_rect() and is_equal_approx(live.top_y(), dead.top_y()), "%s: mesma silhueta da classe viva" % tag)
	# corpo convertido: bem mais escuro que o vivo
	var pairs := {"metal": "metal", "robe": "robe"}
	for key in pairs:
		if key in live:
			var lc: Color = live.get(key)
			var dc: Color = dead.get(key)
			_check(dc.get_luminance() < lc.get_luminance() * 0.75, "%s: %s escurecido (%.2f → %.2f)" % [tag, key, lc.get_luminance(), dc.get_luminance()])
	# energia roxa (olhos/brilho) na sombra
	var glow_key := "visor_glow" if "visor_glow" in dead else "glow"
	var g: Color = dead.get(glow_key)
	_check(g.a > 0.5 and g.b > g.g and g.r > g.g, "%s: brilho roxo (%s)" % [tag, glow_key])
	# anima (fumaça/pulsação dependem do tempo) sem mexer na CombatUnit
	var u := dead.unit
	var snap := [u.hp, u.max_hp, u.damage, u.attack_range, u.attack_interval, u.move_speed, u.position, u.state]
	for i in 30:
		dead.update_visual(DT)
	_check([u.hp, u.max_hp, u.damage, u.attack_range, u.attack_interval, u.move_speed, u.position, u.state] == snap, "%s: visual não altera a unidade" % tag)
	# morte: a energia se apaga
	u.die()
	for i in 180:
		dead.update_visual(DT)
	_check(dead.call(&"_life") == 0.0, "%s: na morte a energia se apaga" % tag)
	live.free()
	dead.free()


func _make(id: StringName) -> UnitVisual:
	var def := UnitCatalog.get_def(id)
	var unit := CombatUnit.new(1, def.side, def.to_stats(), Vector2(300, 380))
	var v: UnitVisual = def.visual_script.new()
	v.setup(unit, def)
	return v


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
