class_name RenderCompare
extends Node
## Comparação de custo de render das unidades (ferramenta de DEBUG do Sandbox; F7 — ver Main).
##
## Troca, só na TELA, como as MESMAS unidades são desenhadas, para medir no próprio PC com o painel F6:
##   NORMAL   — o jogo como é
##   FROZEN   — mesmos desenhos, mas os UnitView param de atualizar/redesenhar (sem _draw por quadro):
##              o que sobra é o custo de ENVIAR/RENDERIZAR os draw calls; a diferença para o normal é o
##              custo de MONTAR o desenho (CPU/GDScript). Com o combate rodando, as unidades congelam na
##              tela (a simulação segue normal).
##   SQUARES  — cada unidade vira UM quadrado simples (limite inferior do custo por unidade)
##   MERGED   — SIMULAÇÃO da solução proposta: cada unidade vira UM triangle array com o MESMO número
##              de triângulos do visual real (medido), refeito e reenviado todo quadro = 1 draw call
##              por unidade. Mostra quanto se ganharia juntando o desenho de cada unidade num lote.
## Não muda CombatUnit, simulação, IA, stats nem os visuais: só esconde/mostra nós e adiciona um nó
## temporário por unidade. Voltar ao NORMAL desfaz tudo.

enum Mode { NORMAL, FROZEN, SQUARES, MERGED }
const NAMES := ["normal", "congelado (sem redesenho)", "quadrados", "lote simulado (1 draw call/unid.)"]
## Triângulos por unidade do visual real (monitor RENDER_TOTAL_PRIMITIVES_IN_FRAME, 40 unidades
## paradas; tools/bench/render_breakdown.gd).
const TRIS := {
	&"warrior": 1879, &"u_warrior": 5044, &"arc_battlemage": 2322, &"u_arc_battlemage": 3981,
	&"sac_paladin": 3998, &"u_sac_paladin": 5631,
}
const NODE_NAME := "RenderCompare"

var battle: Battle
var mode := Mode.NORMAL
var _applied := {}   # instance id do UnitView → modo aplicado


func _ready() -> void:
	set_process(false)


func cycle() -> void:
	set_mode((mode + 1) % Mode.size() as Mode)


func set_mode(value: Mode) -> void:
	mode = value
	set_process(true)   # aplica aos UnitView (e aos que nascerem, ex.: Reiniciar); para sozinho no NORMAL


func mode_name() -> String:
	return NAMES[mode]


func _process(_delta: float) -> void:
	if battle == null or not battle.is_inside_tree():
		return
	var seen := {}
	var pending := false
	for child in battle.get_node(battle.entities_path).get_children():
		var uv := child as UnitView
		if uv == null:
			continue
		var id := uv.get_instance_id()
		seen[id] = true
		if _applied.get(id, Mode.NORMAL) != mode:
			_apply(uv)
			_applied[id] = mode
		pending = pending or mode != Mode.NORMAL
	for id in _applied.keys():
		if not seen.has(id):
			_applied.erase(id)
	if not pending:
		set_process(false)   # tudo no normal: custo zero


func _apply(uv: UnitView) -> void:
	# volta ao normal
	var old := uv.get_node_or_null(NODE_NAME)
	if old:
		uv.remove_child(old)   # sai já (o nome fica livre para o nó novo)
		old.queue_free()
	uv.visual.visible = true
	uv.get_node("Overlay").visible = true
	uv.set_process(true)
	uv.visual.queue_redraw()
	match mode:
		Mode.FROZEN:
			uv.set_process(false)
		Mode.SQUARES, Mode.MERGED:
			uv.visual.visible = false
			uv.get_node("Overlay").visible = false
			var n := Node2D.new()
			n.name = NODE_NAME
			if mode == Mode.SQUARES:
				var col := Color(0.4, 0.8, 0.5) if uv.unit.team == CombatUnit.Team.PLAYER else Color(0.9, 0.4, 0.35)
				n.draw.connect(func(): n.draw_rect(Rect2(-8, -24, 16, 24), col))
			else:
				var arrays := _merged_arrays(TRIS.get(uv.unit.def_id, 3500), uv.unit.id)
				n.draw.connect(func():
					RenderingServer.canvas_item_add_triangle_array(n.get_canvas_item(), PackedInt32Array(), arrays[0], arrays[1]))
				get_tree().process_frame.connect(n.queue_redraw)   # redesenha todo quadro, como um visual animado
			uv.add_child(n)


## `tris` triângulos pequenos na área do corpo (≈ 20×34 px), com cor por vértice.
static func _merged_arrays(tris: int, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.resize(tris * 3)
	cols.resize(tris * 3)
	for i in tris:
		var c := Vector2(rng.randf_range(-10, 10), rng.randf_range(-34, 0))
		var col := Color(rng.randf_range(0.3, 0.9), rng.randf_range(0.3, 0.9), rng.randf_range(0.3, 0.9))
		for k in 3:
			pts[i * 3 + k] = c + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			cols[i * 3 + k] = col
	return [pts, cols]
