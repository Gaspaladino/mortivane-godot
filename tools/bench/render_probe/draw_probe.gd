extends RefCounted
## Sonda de desenho (SÓ na cópia instrumentada do projeto; ver make_probe_copy.py).
## Toda chamada draw_*(...) dos visuais passa por aqui: conta por origem e pode ser desligada por
## categoria, para medir quantos draw calls cada parte gera. O jogo real nunca carrega este arquivo.
##
## Chave de uma chamada: "<script>|<parte>|<tipo>|<draw_fn>"
##   script = arquivo do visual que desenha (warrior_visual, shadow_fx, unit_view…)
##   parte  = função do visual mais interna que NÃO é utilitário (_draw_sword, _draw_cape…)
##   tipo   = preench. | contorno | silhueta | linha | fx:<efeito> | direto

static var active := false        ## calcula a chave (caro: backtrace) — só quando conta ou pula
static var counting := false
static var counts := {}
static var skip: PackedStringArray = []   ## pula chamadas cuja chave contém algum destes textos
static var calls := 0

const HELPERS := {
	"_poly": "", "_circle": "", "_line": "linha", "_fill_poly": "preench.", "_fill_circle": "preench.",
	"_outline_closed": "contorno", "_rim_poly": "silhueta", "_draw_with_rim": "", "_draw_poly": "",
	"_quad": "", "_xf_pts": "",
}


static func refresh() -> void:
	active = counting or not skip.is_empty()


static func _key(ci: Object, fn: String) -> String:
	var kind := ""
	var part := ""
	var script := ""
	var bts := Engine.capture_script_backtraces(false)
	for bt in bts:
		if bt.get_language_name() != "GDScript":
			continue
		for i in bt.get_frame_count():
			var f: String = bt.get_frame_function(i)
			var file: String = bt.get_frame_file(i).get_file().get_basename()
			if file == "draw_probe":
				continue
			if file == "shadow_fx" or file == "paladin_fx" or file == "draw_cache":
				if kind == "" and file != "draw_cache":
					kind = "fx:" + f
				continue
			if HELPERS.has(f):
				if kind == "" and HELPERS[f] != "":
					kind = HELPERS[f]
				if f == "_circle" and kind == "":
					kind = "contorno" if fn == "draw_mesh" or fn == "draw_arc" else "preench."
				continue
			part = f
			script = file
			break
		break
	if ci.get("_rim_pass") == true:
		kind = "silhueta"
	if kind == "":
		kind = "direto"
	return "%s|%s|%s|%s" % [script, part, kind, fn]


static func _do(ci: CanvasItem, fn: StringName, args: Array) -> void:
	calls += 1
	if active:
		var key := _key(ci, fn)
		for s in skip:
			if key.contains(s):
				return
		if counting:
			counts[key] = counts.get(key, 0) + 1
	ci.callv(fn, args)
