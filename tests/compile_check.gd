extends Node
## Loads every script in the project so parse and compile errors show up
## fast, without running the game:
##   godot --headless res://tests/compile_check.tscn


func _ready() -> void:
	var bad := 0
	for path in _scripts("res://scripts") + _scripts("res://tests"):
		var s: Script = load(path)
		if s == null or not s.can_instantiate():
			print("  FAIL  ", path)
			bad += 1
	print("compile check: %d failing" % bad)
	get_tree().quit(1 if bad > 0 else 0)


func _scripts(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + d))
	return out
