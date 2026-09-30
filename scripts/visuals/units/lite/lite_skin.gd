class_name LiteSkin
extends RefCounted
## Corpo de unidade como MALHA ESTÁTICA com ossos (skinning 2D na GPU).
##
## A malha de um tipo de unidade (todas as peças prontas, em ordem de desenho, cada vértice preso ao
## osso da sua peça) é montada UMA vez e compartilhada. Cada unidade tem só um esqueleto: a cada quadro
## a CPU atualiza as transformações dos ossos (a pose) — nenhuma geometria é refeita nem reenviada, e o
## CanvasItem guarda um único comando (a malha) = 1 draw call, sem _draw por quadro.
##
## Regras do Godot (Compatibility): a malha precisa de bones/weights/UV; o esqueleto 2D precisa da
## "base" = transformação global do CanvasItem (atualizada quando o nó se move).

## Osso escondido: escala zero (a peça some sem mudar a malha).
const HIDDEN := Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)

static var _meshes := {}

var skeleton: RID
var bone_count := 0
## Nº de atualizações de osso enviadas (diagnóstico/testes: a pose anda sem redesenho).
var updates := 0


func _init(bones: int) -> void:
	bone_count = bones
	skeleton = RenderingServer.skeleton_create()
	RenderingServer.skeleton_allocate_data(skeleton, bones, true)
	for i in bones:
		RenderingServer.skeleton_bone_set_transform_2d(skeleton, i, HIDDEN)


func attach(ci: CanvasItem) -> void:
	RenderingServer.canvas_item_attach_skeleton(ci.get_canvas_item(), skeleton)


func set_base(global_xf: Transform2D) -> void:
	RenderingServer.skeleton_set_base_transform_2d(skeleton, global_xf)


func set_bone(i: int, xf: Transform2D) -> void:
	RenderingServer.skeleton_bone_set_transform_2d(skeleton, i, xf)
	updates += 1


func hide_bone(i: int) -> void:
	RenderingServer.skeleton_bone_set_transform_2d(skeleton, i, HIDDEN)
	updates += 1


func release() -> void:
	if skeleton.is_valid():
		RenderingServer.free_rid(skeleton)
		skeleton = RID()


## Malha do tipo (cache por `key`): `layout` = [[LitePart, osso], ...] em ordem de desenho.
static func mesh(key: String, layout: Array) -> ArrayMesh:
	var m: ArrayMesh = _meshes.get(key)
	if m:
		return m
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for entry in layout:
		var part: LitePart = entry[0]
		if part == null or part.pts.is_empty():
			continue
		var bone: int = entry[1]
		var n := part.pts.size()
		pts.append_array(part.pts)
		cols.append_array(part.cols)
		uvs.append_array(part.uvs)
		var b := PackedInt32Array()
		b.resize(n * 4)
		b.fill(0)
		var w := PackedFloat32Array()
		w.resize(n * 4)
		w.fill(0.0)
		for v in n:
			b[v * 4] = bone
			w[v * 4] = 1.0
		bones.append_array(b)
		weights.append_array(w)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	m = ArrayMesh.new()
	if not pts.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	_meshes[key] = m
	return m


static func mesh_count() -> int:
	return _meshes.size()


static func clear_meshes() -> void:
	_meshes.clear()
