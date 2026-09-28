@tool
class_name BackdropShaderRect
extends ColorRect
## ColorRect com shader do fundo (céu, névoa). Mantém os parâmetros `rect_origin`/`rect_size`
## do shader iguais à posição/tamanho do nó, então dá para mover e redimensionar no editor.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_rect_changed.connect(_sync_rect)
	_sync_rect()


func _sync_rect() -> void:
	var mat := material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("rect_origin", position)
		mat.set_shader_parameter("rect_size", size)
