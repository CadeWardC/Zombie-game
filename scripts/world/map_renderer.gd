class_name MapRenderer
extends RefCounted
## Draws a top-down image of the generated world. Used by the map preview
## tool now and, later, as the base of the in-game map.


static func render(gen: WorldGen, px: int) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	var scale := gen.world_size / px
	for j in px:
		for i in px:
			var x := (i + 0.5) * scale
			var z := (j + 0.5) * scale
			var h := gen.terrain.macro_height(x, z)
			var c: Color
			if h < 0.0:
				c = Color(0.16, 0.3, 0.45).darkened(clampf(-h / 80.0, 0.0, 0.5))
			else:
				match gen.terrain.biome_at(x, z, h):
					Terrain.Biome.BEACH: c = Color(0.85, 0.78, 0.55)
					Terrain.Biome.DESERT: c = Color(0.8, 0.64, 0.42)
					Terrain.Biome.FOREST: c = Color(0.2, 0.36, 0.17)
					Terrain.Biome.FARMLAND: c = Color(0.6, 0.6, 0.32)
					Terrain.Biome.MOUNTAIN: c = Color(0.5, 0.48, 0.45).lerp(Color.WHITE, clampf((h - 140.0) / 60.0, 0.0, 1.0))
					_: c = Color(0.4, 0.52, 0.27)
				# Hill shading.
				var dx := gen.terrain.macro_height(x + scale, z) - h
				var dz := gen.terrain.macro_height(x, z + scale) - h
				c = c.lightened(clampf(-(dx + dz) / scale * 0.8, -0.3, 0.3)) if dx + dz < 0.0 else c.darkened(clampf((dx + dz) / scale * 0.8, 0.0, 0.3))
			img.set_pixel(i, j, c)
	for j in px:
		for i in px:
			if gen.hydro.lake_at(Vector2((i + 0.5) * scale, (j + 0.5) * scale)) > -INF:
				img.set_pixel(i, j, Color(0.2, 0.4, 0.6))
	for r in gen.hydro.rivers:
		_polyline(img, r.pts, scale, Color(0.22, 0.42, 0.62), 1)
	for s in gen.settlements.list:
		_disc(img, s.center / scale, s.radius / scale, Color(0.55, 0.55, 0.52))
	for road in gen.roads.roads:
		var col := Color(0.15, 0.15, 0.15)
		var w := 1
		match road.type:
			RoadNetwork.Type.HIGHWAY:
				col = Color(0.9, 0.75, 0.2)
				w = 2
			RoadNetwork.Type.STREET:
				col = Color(0.3, 0.3, 0.3)
		_polyline(img, road.pts, scale, col, w)
	for t in gen.towns:
		for lot in t.lots:
			img.set_pixelv(Vector2i(lot.center / scale).clamp(Vector2i.ZERO, Vector2i(px - 1, px - 1)), Color(0.7, 0.3, 0.25))
	for site in gen.settlements.sites:
		var col := Color(0.72, 0.45, 0.8) if site.type == "research" else (Color(0.6, 0.75, 0.88) if site.type == "airport" else Color(0.85, 0.55, 0.2))
		if site.type == "power_plant":
			col = Color(0.95, 0.85, 0.3)
		_disc(img, site.center / scale, maxf(2.0, site.half.y / scale), col)
	return img


static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in range(int(c.y - r), int(c.y + r) + 1):
		for x in range(int(c.x - r), int(c.x + r) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and Vector2(x, y).distance_to(c) <= r:
				img.set_pixel(x, y, col)


static func _polyline(img: Image, pts: PackedVector2Array, scale: float, col: Color, w: int) -> void:
	for k in pts.size() - 1:
		var a := pts[k] / scale
		var b := pts[k + 1] / scale
		var steps := int(maxf(1.0, a.distance_to(b) * 2.0))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps)
			for oy in range(-w + 1, w):
				for ox in range(-w + 1, w):
					var q := Vector2i(p) + Vector2i(ox, oy)
					if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
						img.set_pixelv(q, col)
