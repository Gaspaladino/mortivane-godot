class_name BackdropAnimated
## Utilidades comuns dos nós animados do fundo. Cada nó animado entra no grupo
## "backdrop_animated" e tem `global_intensity` (0 = parado), ajustado pelo ArenaBackdrop.
## No editor nada se move: as animações só rodam no jogo.

const GROUP := &"backdrop_animated"


static func running() -> bool:
	return not Engine.is_editor_hint()
