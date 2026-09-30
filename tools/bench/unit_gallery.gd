extends SceneTree
## Galeria de poses das tropas, de perto (referência visual e comparação antes/depois). Só leitura.
## args (depois de --): <saida.png> [zoom=2.6] [ids=warrior,u_warrior,...]
## Colunas: parado · parado+0,7 s · andando · preparando · golpe · recebendo dano · habilidade · morrendo · cadáver.
## Cada visual é dirigido direto (UnitView sem _process): a CombatUnit fica parada na célula e o
## visual recebe os mesmos eventos/estados que a Battle mandaria.

const IDS := [&"warrior", &"u_warrior", &"arc_battlemage", &"u_arc_battlemage", &"sac_paladin", &"u_sac_paladin"]
const POSES := ["parado", "parado+0,7s", "andando", "preparando", "golpe", "dano", "habilidade", "morrendo", "cadáver"]
const CELL := Vector2(118, 124)
const DT := 1.0 / 60.0

var out := ""
var zoom := 2.6
var ids: Array = IDS
var frames := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	if a.size() > 1:
		zoom = float(a[1])
	if a.size() > 2:
		ids = Array(a[2].split(",")).map(func(s): return StringName(s))
	RenderingServer.set_default_clear_color(Color(0.23, 0.24, 0.27))
	var cw := CELL.x * zoom / 2.6
	var ch := CELL.y * zoom / 2.6
	var font := ThemeDB.fallback_font
	var labels := Node2D.new()
	root.add_child(labels)
	labels.draw.connect(func():
		for c in POSES.size():
			labels.draw_string(font, Vector2(92 + c * cw, 16), POSES[c], HORIZONTAL_ALIGNMENT_CENTER, cw, 12)
		for r in ids.size():
			labels.draw_string(font, Vector2(4, 26 + (r + 0.6) * ch), String(ids[r]), HORIZONTAL_ALIGNMENT_LEFT, 86, 11))
	var id := 1000
	for r in ids.size():
		var def := UnitCatalog.get_def(ids[r])
		for c in POSES.size():
			var holder := Node2D.new()
			holder.position = Vector2(92 + (c + 0.5) * cw, 26 + (r + 0.78) * ch)
			holder.scale = Vector2(zoom, zoom)
			root.add_child(holder)
			id += 2
			_pose(holder, def, POSES[c], id)


func _pose(world: Node2D, def: UnitDef, pose: String, id: int) -> void:
	var stats := def.to_stats({})
	var unit := CombatUnit.new(id, CombatUnit.Team.PLAYER, stats, Vector2.ZERO)
	var foe := CombatUnit.new(id + 1, CombatUnit.Team.ENEMY, stats, Vector2(60, 0))
	unit.target = foe
	var view := UnitView.new(unit, def)
	world.add_child(view)
	var v := view.visual
	var step := func(n: int):
		for i in n:
			v.update_visual(DT)
	match pose:
		"parado":
			step.call(20)
		"parado+0,7s":
			step.call(62)
		"andando":
			unit.state = CombatUnit.State.MOVING
			for i in 24:
				unit.position.x += unit.move_speed * DT
				foe.position.x += unit.move_speed * DT
				v.update_visual(DT)
		"preparando":
			step.call(10)
			unit.state = CombatUnit.State.ATTACKING
			unit.cooldown = 0.04
			step.call(12)
		"golpe":
			unit.state = CombatUnit.State.ATTACKING
			step.call(10)
			v.on_attack_performed()
			step.call(4)
		"dano":
			step.call(10)
			v.on_hit()
			step.call(3)
		"habilidade":
			step.call(10)
			unit.state = CombatUnit.State.ATTACKING
			if unit.paladin:
				v.on_ability_event(&"taunt")
				v.on_ability_event(&"shield")
			v.on_attack_performed()
			step.call(12)
		"morrendo":
			step.call(10)
			unit.die()
			step.call(16)
		"cadáver":
			step.call(10)
			unit.die()
			step.call(200)
	v.queue_redraw()
	view.get_node("Overlay").visible = false


func _process(_delta: float) -> bool:
	frames += 1
	if frames <= 3:
		# o _ready do UnitView roda depois do _initialize e copia unit.position: volta cada um à célula
		for holder in root.get_children():
			for v in holder.get_children():
				if v is UnitView:
					v.set_process(false)   # o _ready religa o _process (que copiaria unit.position)
					v.position = Vector2.ZERO
	if frames == 4:
		root.get_texture().get_image().save_png(out)
		print("SHOT ", out)
		return true
	return false
