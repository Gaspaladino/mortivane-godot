extends SceneTree
## Revisão visual/performance isolada, sem simular combate.
## godot --path . --resolution 1120x620 -s res://tools/bench/paladin_refinement_review.gd -- poses=/tmp/poses.png
## godot --path . --resolution 900x500 -s res://tools/bench/paladin_refinement_review.gd -- unit=sac_paladin
## A medição exclui cenário, UI e HP; não representa o FPS de uma batalha completa.

var views: Array[UnitView] = []
var frames := 0
var pose_path := ""
var unit_id := &"sac_paladin"
var objects_before := 0
var cpu_us := 0
var draw_calls := 0.0
var samples := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("poses="):
			pose_path = arg.trim_prefix("poses=")
		elif arg.begins_with("unit="):
			unit_id = StringName(arg.trim_prefix("unit="))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	RenderingServer.set_default_clear_color(Color("34363e"))
	_build.call_deferred()

func _build() -> void:
	objects_before = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	if pose_path.is_empty():
		for i in 40:
			_make(unit_id, Vector2(35 + (i % 10) * 80, 75 + (i / 10) * 100), 1.0, i + 1)
	else:
		var labels := Node2D.new()
		root.add_child(labels)
		labels.draw.connect(func():
			var font := ThemeDB.fallback_font
			for d in 8:
				labels.draw_string(font, Vector2(45 + d * 135, 20), PaladinPoseLibrary.DIR_NAMES[d], HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
			for r in 4:
				labels.draw_string(font, Vector2(4, 55 + r * 140), ["idle", "walk", "attack", "shield"][r], HORIZONTAL_ALIGNMENT_LEFT, -1, 13))
		for r in 4:
			for d in 8:
				var v := _make(&"sac_paladin", Vector2(75 + d * 135, 135 + r * 140), 2.4, 10)
				var pal := v.visual as PaladinLiveVisual
				pal.preview([&"idle", &"walk", &"attack", &"shield"][r], d)
				for i in (18 if r == 2 else 30):
					pal.update_visual(1.0 / 60.0)
				pal.queue_redraw()

func _make(id: StringName, pos: Vector2, zoom: float, uid: int) -> UnitView:
	var def := UnitCatalog.get_def(id)
	var unit := CombatUnit.new(uid, CombatUnit.Team.PLAYER, def.to_stats(), Vector2.ZERO)
	var holder := Node2D.new()
	holder.position = pos
	holder.scale = Vector2.ONE * zoom
	root.add_child(holder)
	var v := UnitView.new(unit, def)
	holder.add_child(v)
	v.process_mode = Node.PROCESS_MODE_DISABLED
	v.get_node("Overlay").hide()
	views.append(v)
	return v

func _process(_delta: float) -> bool:
	if views.is_empty():
		return false
	frames += 1
	if not pose_path.is_empty():
		if frames == 5:
			var err := root.get_texture().get_image().save_png(pose_path)
			print("poses: ", error_string(err), " ", pose_path)
			quit(0 if err == OK else 1)
		return false
	var start := Time.get_ticks_usec()
	for v in views:
		v.visual.update_visual(1.0 / 60.0)
	var used := Time.get_ticks_usec() - start
	if frames > 30:
		cpu_us += used
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		samples += 1
	if frames == 90:
		var body := views[0].visual as CodeDrawnUnitVisual
		print(JSON.stringify({"unit":unit_id, "count":views.size(), "body_draw_calls":draw_calls / samples,
			"visual_cpu_ms":cpu_us / 1000.0 / samples, "objects_added":int(Performance.get_monitor(Performance.OBJECT_COUNT)) - objects_before,
			"nodes_per_unit":views[0].get_child_count() + 1, "bones_per_unit":body._skin.bone_count,
			"vertices_shared_mesh":body._mesh.surface_get_array_len(0)}))
		return true
	return false
