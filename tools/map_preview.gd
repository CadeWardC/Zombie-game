extends SceneTree
## Renders a top-down PNG of a generated world, for checking the generator.
## godot --headless -s tools/map_preview.gd -- --seed=N --size=8192 --out=/path/map.png

func _init() -> void:
	var seed_value := 12345
	var size := 8192.0
	var out := "user://map.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed_value = int(a.get_slice("=", 1))
		elif a.begins_with("--size="): size = float(a.get_slice("=", 1))
		elif a.begins_with("--out="): out = a.get_slice("=", 1)
	var t0 := Time.get_ticks_msec()
	var gen := WorldGen.new(seed_value, size)
	gen.generate(func(f, text): print("%6d ms  %s" % [Time.get_ticks_msec() - t0, text]))
	print("generated in %d ms" % (Time.get_ticks_msec() - t0))
	var img := MapRenderer.render(gen, 1024)
	img.save_png(out)
	print("saved ", out)
	quit()
