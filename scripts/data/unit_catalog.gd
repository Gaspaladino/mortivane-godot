class_name UnitCatalog
extends RefCounted
## Lista das UnitDef disponíveis, lidas de res://data/units/*.tres.
## Nova unidade = novo .tres na pasta; nenhuma lista em código precisa mudar.

const UNITS_DIR := "res://data/units"

static var _cache: Array[UnitDef] = []


static func all() -> Array[UnitDef]:
	if _cache.is_empty():
		_cache = _load_all()
	return _cache


static func for_side(side: CombatUnit.Team) -> Array[UnitDef]:
	return all().filter(func(d: UnitDef) -> bool: return d.side == side)


static func get_def(id: StringName) -> UnitDef:
	for def in all():
		if def.id == id:
			return def
	return null


static func _load_all() -> Array[UnitDef]:
	var defs: Array[UnitDef] = []
	var files := ResourceLoader.list_directory(UNITS_DIR)
	files.sort()
	for file in files:
		# em builds exportados os .tres podem aparecer como .tres.remap
		file = file.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var def := load(UNITS_DIR.path_join(file)) as UnitDef
		if def == null:
			push_error("UnitCatalog: %s não é uma UnitDef." % file)
			continue
		defs.append(def)
	return defs
