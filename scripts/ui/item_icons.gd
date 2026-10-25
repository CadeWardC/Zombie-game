class_name ItemIcons
extends Node
## Inventory icons, rendered once from the 3D item models into a single
## texture atlas (one draw of one off-screen viewport, a few milliseconds).
## Until it's ready, or on renderers that can't read it back, the inventory
## falls back to coloured tiles with the item's name.

const CELL := 48 # Atlas pixels per inventory cell.
const ATLAS := 1536
const PX := 0.01 # World units per atlas pixel.

static var texture: Texture2D
static var regions := {} # item id -> Rect2 (pixels in the atlas, unrotated)
static var _started := false


## Starts rendering the atlas (call once; needs a node in the scene tree).
static func build(host: Node) -> void:
	if _started:
		return
	_started = true
	var n := ItemIcons.new()
	host.add_child(n)


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(ATLAS, ATLAS)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.environment.ambient_light_energy = 0.8
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ATLAS * PX
	cam.near = 0.1
	cam.far = 100.0
	# Looking along -X: screen right is world -Z, screen up is world +Y.
	cam.transform = Transform3D(Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(1, 0, 0)), Vector3(50, 0, 0))
	vp.add_child(cam)

	# Shelf-pack every item into the atlas and place its model in the matching
	# spot in front of the camera.
	var x := 0
	var y := 0
	var row_h := 0
	var ids := ItemDB.ITEMS.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return ItemDB.ITEMS[a].h > ItemDB.ITEMS[b].h)
	for id: String in ids:
		var d: Dictionary = ItemDB.ITEMS[id]
		var w := int(d.w) * CELL
		var h := int(d.h) * CELL
		if x + w > ATLAS:
			x = 0
			y += row_h
			row_h = 0
		if y + h > ATLAS:
			push_warning("Item icon atlas is full")
			break
		regions[id] = Rect2(x, y, w, h)
		_place(vp, id, Rect2(x, y, w, h))
		x += w
		row_h = maxi(row_h, h)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img and not img.is_empty() and img.get_width() == ATLAS:
		texture = ImageTexture.create_from_image(img)
	vp.queue_free()


func _place(vp: SubViewport, id: String, r: Rect2) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Assets.item_meshes.get(id)
	if mi.mesh == null:
		return
	var cat: String = ItemDB.get_def(id).get("cat", "")
	# Weapons are shown from the side (muzzle right); everything else from a
	# three-quarter view.
	var basis := Basis.IDENTITY
	var flat: bool = cat == "clothing" and not ItemDB.get_def(id).look in ["cap", "beanie", "helmet", "army_helmet", "shoes", "boots"]
	if not (cat in ["melee", "gun", "bow"] or id in ["arrow", "bolt", "scope", "suppressor"] or flat):
		basis = Basis(Vector3.RIGHT, deg_to_rad(18)) * Basis(Vector3.UP, deg_to_rad(125))
	var aabb := Transform3D(basis, Vector3.ZERO) * mi.mesh.get_aabb()
	# Screen axes: horizontal = world -Z, vertical = world Y.
	var size_w := aabb.size.z
	var size_h := aabb.size.y
	var region_w := (r.size.x - 8) * PX
	var region_h := (r.size.y - 8) * PX
	var s := minf(region_w / maxf(size_w, 0.001), region_h / maxf(size_h, 0.001))
	var center := aabb.get_center() * s
	var target_z := -((r.position.x + r.size.x * 0.5) * PX - ATLAS * PX * 0.5)
	var target_y := ATLAS * PX * 0.5 - (r.position.y + r.size.y * 0.5) * PX
	mi.transform = Transform3D(basis.scaled(Vector3(s, s, s)), Vector3(-center.x, target_y - center.y, target_z - center.z))
	vp.add_child(mi)
