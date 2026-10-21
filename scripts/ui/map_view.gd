class_name MapView
extends Control
## The world map: the drawn terrain, with the parts you've never seen in
## shadow. Shows the player's position when there is one. Used by the pause
## menu and by lost worlds' memorials.

var player_pos := Vector3.INF
var player_yaw := 0.0
var world_size := 8192.0
var _tex: Texture2D


## Loads a world's map and explored mask from its folder.
func load_world(meta: Dictionary, explored: Image = null) -> void:
	world_size = float(meta.get("size", 8192.0))
	var map_path := GameState.world_file(meta, "map.png")
	if not FileAccess.file_exists(map_path):
		return
	var map := Image.load_from_file(ProjectSettings.globalize_path(map_path))
	if explored == null:
		var ex_path := GameState.world_file(meta, "explored.png")
		if FileAccess.file_exists(ex_path):
			explored = Image.load_from_file(ProjectSettings.globalize_path(ex_path))
	_tex = ImageTexture.create_from_image(compose(map, explored))
	queue_redraw()


## Darkens map pixels whose area was never explored.
static func compose(map: Image, explored: Image) -> Image:
	var out := map.duplicate() as Image
	out.convert(Image.FORMAT_RGB8)
	if explored == null or explored.is_empty():
		return out
	var w := out.get_width()
	var ew := explored.get_width()
	for y in w:
		for x in w:
			var e := explored.get_pixel(x * ew / w, y * ew / w).r
			if e < 0.5:
				var c := out.get_pixel(x, y)
				out.set_pixel(x, y, c.darkened(0.78).lerp(Color(0.05, 0.05, 0.06), 0.3))
	return out


func _draw() -> void:
	var side := minf(size.x, size.y)
	var r := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	draw_rect(r.grow(3.0), Color(0.3, 0.32, 0.3))
	if _tex == null:
		draw_rect(r, Color(0.1, 0.1, 0.1))
		return
	draw_texture_rect(_tex, r, false)
	if player_pos != Vector3.INF:
		var p := r.position + Vector2(player_pos.x, player_pos.z) / world_size * side
		var f := Vector2(-sin(player_yaw), -cos(player_yaw))
		var pts := PackedVector2Array([p + f * 11.0, p + f.rotated(2.5) * 7.0, p + f.rotated(-2.5) * 7.0])
		draw_colored_polygon(pts, Color(1.0, 0.85, 0.2))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color.BLACK, 1.5)
