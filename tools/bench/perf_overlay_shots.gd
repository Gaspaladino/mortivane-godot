extends SceneTree
## Capturas do painel de desempenho (F6) no Sandbox real, em tempo real (sem passo fixo).
## args: <saida.png> <aliados> <inimigos> <perfil: warriors|sentinels|paladins|mixed> [segundos=4]
var out := ""
var main: Node
var t := 0.0
var wait := 4.0
var step := 0
const PROFILES := {warriors = [&"warrior"], sentinels = [&"arc_battlemage"], paladins = [&"sac_paladin"],
	mixed = [&"warrior", &"arc_battlemage", &"sac_paladin"]}


func _initialize() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	if step == 0 and t > 0.3:
		step = 1
		var a := OS.get_cmdline_user_args()
		out = a[0]
		var allies := int(a[1])
		var enemies := int(a[2])
		var defs: Array = PROFILES[a[3]]
		wait = float(a[4]) if a.size() > 4 else 4.0
		main._arena_debug = false
		main.show_sandbox()
		var sb: SandboxController = main.current_screen
		for i in allies:
			sb.add_unit(UnitCatalog.get_def(defs[i % defs.size()]), CombatUnit.Team.PLAYER)
		for i in enemies:
			sb.add_unit(UnitCatalog.get_def(defs[(i + 1) % defs.size()]), CombatUnit.Team.ENEMY)
		# F6 de verdade (mesmo caminho do teclado)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F6
		ev.pressed = true
		Input.parse_input_event(ev)
		sb.start_combat()
		t = 0.0
	elif step == 1 and t > wait:
		root.get_texture().get_image().save_png(out)
		print("SHOT ", out)
		return true
	return false
