class_name LitePart
extends RefCounted
## Peça de visual pré-montada: triângulos soltos (lista, sem índices) com cor por vértice, no espaço
## LOCAL da peça. Construída UMA vez por tipo de unidade (LiteBuilder) e compartilhada por todas as
## unidades desse tipo; entra na malha do tipo presa a um osso (LiteSkin).

var pts := PackedVector2Array()
var cols := PackedColorArray()
## Por vértice: x = 1 recebe o clarão de dano (corpo), 0 não recebe (sombra no chão, névoa, aura).
var uvs := PackedVector2Array()


func is_empty() -> bool:
	return pts.is_empty()


func vertex_count() -> int:
	return pts.size()
