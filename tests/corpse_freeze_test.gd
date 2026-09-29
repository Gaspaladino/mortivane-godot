extends SceneTree
## Etapa 2 da otimização: cadáver estático.
## Para cada tipo de unidade do catálogo (vivas e sombras): mata a unidade, deixa a morte acontecer
## pelo UnitView real e verifica que
##   - durante a queda o visual continua sendo redesenhado a cada quadro;
##   - depois do tempo de assentamento o UnitView congela: nenhum _draw do corpo, do anel nem da barra;
##   - mover o cadáver só muda a posição do nó (sem redesenho);
##   - reviver (Necromancia no futuro) volta a animar;
##   - ligar o debug volta a redesenhar.

const DT := 1.0 / 60.0
var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	for id in [&"warrior", &"u_warrior", &"arc_battlemage", &"u_arc_battlemage", &"sac_paladin", &"u_sac_paladin"]:
		await _test_unit(id)
	print("corpse_freeze_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("  FALHOU: " + msg)


func _test_unit(id: StringName) -> void:
	var def := UnitCatalog.get_def(id)
	var u := CombatUnit.new(1, CombatUnit.Team.PLAYER, def.to_stats(), Vector2(300, 300))
	var view := UnitView.new(u, def)
	view.set_process(false)   # o teste chama o _process do jogo quadro a quadro
	root.add_child(view)
	await process_frame
	view.set_process(false)   # depois do _ready (o Godot religa o _process no _ready)
	var draws := [0]
	for ci: CanvasItem in [view, view.visual, view._overlay]:
		ci.draw.connect(func() -> void: draws[0] += 1)
	for i in 30:
		view._process(DT)
	await process_frame
	u.take_damage(u.hp)
	# queda: continua redesenhando
	var during := 0
	for i in 30:
		draws[0] = 0
		view._process(DT)
		await process_frame
		during += draws[0]
	_check(during >= 30 and not view.is_frozen(), "%s: durante a queda redesenha todo quadro (%d)" % [id, during])
	var settle := view.visual.corpse_settle_time()
	_check(settle < 5.0, "%s: o cadáver tem tempo de assentamento (%.2f s)" % [id, settle])
	var t := 0.5
	while t < settle + 0.2:
		view._process(DT)
		t += DT
	await process_frame
	_check(view.is_frozen(), "%s: congelado depois de %.2f s" % [id, settle])
	draws[0] = 0
	for i in 120:
		view._process(DT)
		await process_frame
	_check(draws[0] == 0, "%s: 2 s de cadáver sem nenhum redesenho (%d)" % [id, draws[0]])
	# mover o cadáver: só a posição do nó
	u.position += Vector2(10, 0)
	view._process(DT)
	await process_frame
	_check(view.position == u.position and draws[0] == 0, "%s: mover o cadáver não redesenha" % id)
	# debug ligado: redesenha
	view.debug_visible = true
	view._process(DT)
	await process_frame
	_check(draws[0] > 0 and not view.is_frozen(), "%s: debug ligado volta a redesenhar" % id)
	view.debug_visible = false
	# reviver (futuro: Necromancia) volta a animar
	u.state = CombatUnit.State.IDLE
	u.hp = u.max_hp
	view._process(DT)
	_check(not view.is_frozen(), "%s: reviver sai do congelamento" % id)
	view.queue_free()
	await process_frame
