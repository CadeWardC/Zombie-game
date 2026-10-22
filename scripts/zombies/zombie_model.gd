class_name ZombieModel
extends RefCounted
## Procedural rigged zombie: a 17-bone skeleton, rigidly skinned low-poly
## body with normal human proportions, outfit variants, and keyframed
## animations built in code (shamble, run, attack, hit, death, idle).
## Meshes, skin and animations are built once and shared by every zombie.

const BONES := [
	# name, parent, rest position (model space)
	["hips", -1, Vector3(0, 0.95, 0)],
	["spine", 0, Vector3(0, 1.1, 0)],
	["chest", 1, Vector3(0, 1.35, 0)],
	["neck", 2, Vector3(0, 1.58, 0)],
	["head", 3, Vector3(0, 1.68, 0)],
	["upper_arm.L", 2, Vector3(0.21, 1.52, 0)],
	["forearm.L", 5, Vector3(0.21, 1.25, 0)],
	["hand.L", 6, Vector3(0.21, 1.0, 0)],
	["upper_arm.R", 2, Vector3(-0.21, 1.52, 0)],
	["forearm.R", 8, Vector3(-0.21, 1.25, 0)],
	["hand.R", 9, Vector3(-0.21, 1.0, 0)],
	["thigh.L", 0, Vector3(0.1, 0.92, 0)],
	["shin.L", 11, Vector3(0.1, 0.5, 0)],
	["foot.L", 12, Vector3(0.1, 0.09, 0)],
	["thigh.R", 0, Vector3(-0.1, 0.92, 0)],
	["shin.R", 14, Vector3(-0.1, 0.5, 0)],
	["foot.R", 15, Vector3(-0.1, 0.09, 0)],
]

## [shirt, pants, shoes, sleeves (0 none, 1 short, 2 long), extra]
const OUTFITS := [
	[Color(0.55, 0.22, 0.18), Color(0.2, 0.26, 0.4), Color(0.12, 0.12, 0.12), 1, ""],     # tee + jeans
	[Color(0.75, 0.75, 0.72), Color(0.22, 0.22, 0.24), Color(0.1, 0.08, 0.06), 2, "tie"], # office
	[Color(0.3, 0.32, 0.3), Color(0.25, 0.25, 0.27), Color(0.8, 0.8, 0.8), 2, "hood"],    # hoodie
	[Color(0.12, 0.16, 0.3), Color(0.1, 0.12, 0.22), Color(0.05, 0.05, 0.05), 2, "badge"], # police
	[Color(0.55, 0.7, 0.75), Color(0.55, 0.7, 0.75), Color(0.85, 0.85, 0.85), 1, ""],     # hospital gown
	[Color(0.85, 0.45, 0.1), Color(0.3, 0.3, 0.28), Color(0.3, 0.2, 0.1), 1, "vest"],     # worker
	[Color(0.3, 0.34, 0.22), Color(0.28, 0.3, 0.2), Color(0.15, 0.12, 0.08), 2, ""],      # camo
	[Color(0.15, 0.15, 0.17), Color(0.15, 0.15, 0.17), Color(0.05, 0.05, 0.05), 2, "tie"], # suit
]
const SKINS := [Color(0.5, 0.56, 0.45), Color(0.45, 0.45, 0.38), Color(0.58, 0.55, 0.47), Color(0.38, 0.35, 0.3)]
const HAIR := [Color(0.1, 0.08, 0.06), Color(0.3, 0.2, 0.12), Color(0.55, 0.5, 0.42), Color(0.2, 0.2, 0.2)]

static var skin: Skin
static var meshes: Array[ArrayMesh] = [] # Ordinary walkers, one per outfit.
static var type_meshes := {} # Zombie type -> Array[ArrayMesh].
static var library: AnimationLibrary
static var _cache := {} # BodyLook key -> ArrayMesh (player zombies, previews).


static func build_assets() -> void:
	if skin != null:
		return
	skin = Skin.new()
	for i in BONES.size():
		skin.add_named_bind(BONES[i][0], Transform3D(Basis.IDENTITY, -(BONES[i][2] as Vector3)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for k in OUTFITS.size():
		meshes.append(_build_mesh(outfit_look(k, rng), rng))
	type_meshes.walker = meshes
	type_meshes.runner = meshes
	type_meshes.crawler = meshes
	var brutes: Array[ArrayMesh] = []
	for k: int in [0, 5, 2]:
		var l := outfit_look(k, rng)
		l.bulk = 1.35
		l.torn = 0.7
		brutes.append(_build_mesh(l, rng))
	type_meshes.brute = brutes
	var screamers: Array[ArrayMesh] = []
	for k: int in [4, 0, 7]:
		var l := outfit_look(k, rng)
		l.bulk = 0.82
		l.mouth = true
		l.hair_style = 1
		screamers.append(_build_mesh(l, rng))
	type_meshes.screamer = screamers
	var soldiers: Array[ArrayMesh] = []
	for col: Color in [Color(0.3, 0.33, 0.22), Color(0.55, 0.5, 0.38)]:
		var l := BodyLook.base(SKINS[rng.randi() % SKINS.size()], HAIR[0])
		l.shirt = col
		l.pants = col.darkened(0.08)
		l.shoes = Color(0.1, 0.09, 0.08)
		l.boots = true
		l.sleeves = 2
		l.extra = "armor"
		l.head = "army_helmet"
		l.head_col = col.darkened(0.1)
		soldiers.append(_build_mesh(l, rng))
	type_meshes.soldier = soldiers
	var scientists: Array[ArrayMesh] = []
	for k in 3:
		var l := outfit_look([1, 0, 7][k], rng)
		l.shirt = Color(0.88, 0.89, 0.88)
		l.extra = "coat"
		l.sleeves = 2
		l.build = k % 2
		l.hair_style = [0, 2, 3][k]
		scientists.append(_build_mesh(l, rng))
	type_meshes.scientist = scientists
	library = _build_animations()


static func outfit_look(k: int, rng: RandomNumberGenerator) -> Dictionary:
	var o: Array = OUTFITS[k % OUTFITS.size()]
	var l := BodyLook.base(SKINS[k % SKINS.size()], HAIR[rng.randi() % HAIR.size()])
	l.shirt = o[0]
	l.pants = o[1]
	l.shoes = o[2]
	l.sleeves = o[3]
	l.extra = o[4]
	return l


## A mesh for any body look, built once and cached (player zombies, the
## character preview).
static func mesh_for(look: Dictionary) -> ArrayMesh:
	var k := BodyLook.key(look)
	if not _cache.has(k):
		var rng := RandomNumberGenerator.new()
		rng.seed = k.hash()
		_cache[k] = _build_mesh(look, rng)
	return _cache[k]


## Creates a zombie body node: Skeleton3D + skinned mesh + AnimationPlayer.
static func instantiate(variant: int) -> Node3D:
	var root := Node3D.new()
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	for i in BONES.size():
		skel.add_bone(BONES[i][0])
		var parent: int = BONES[i][1]
		skel.set_bone_parent(i, parent)
		var local: Vector3 = BONES[i][2] - (BONES[parent][2] if parent >= 0 else Vector3.ZERO)
		skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, local))
		skel.set_bone_pose_position(i, local)
	root.add_child(skel)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = meshes[variant % meshes.size()]
	mi.skin = skin
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	ap.add_animation_library("", library)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return root


# --- Mesh ----------------------------------------------------------------------

class _Builder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var rng: RandomNumberGenerator
	var blood := 0.0

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, bone: int, facing: Vector3) -> void:
		var n := (c - a).cross(b - a)
		if n.dot(facing) < 0.0:
			var t := b
			b = c
			c = t
			n = -n
		n = n.normalized()
		if blood > 0.0 and rng.randf() < blood:
			col = col.lerp(Color(0.35, 0.03, 0.02), rng.randf_range(0.5, 0.9))
		for v in [a, b, c]:
			verts.append(v)
			normals.append(n)
			colors.append(col)
			bones.append_array([bone, 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, bone: int, facing: Vector3) -> void:
		tri(a, b, c, col, bone, facing)
		tri(a, c, d, col, bone, facing)

	## Tapered box: bottom size (x, z) at y0, top size at y1, centred on (cx, cz).
	func tbox(center_xz: Vector2, y0: float, y1: float, bottom: Vector2, top: Vector2, col: Color, bone: int) -> void:
		var c := Vector3(center_xz.x, (y0 + y1) * 0.5, center_xz.y)
		var p := []
		for k in 8:
			var s: Vector2 = top if k & 4 else bottom
			var y := y1 if k & 4 else y0
			p.append(Vector3(center_xz.x + (s.x if k & 1 else -s.x) * 0.5, y, center_xz.y + (s.y if k & 2 else -s.y) * 0.5))
		var faces := [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]
		for f in faces:
			var a: Vector3 = p[f[0]]
			var b: Vector3 = p[f[1]]
			var cc: Vector3 = p[f[2]]
			var d: Vector3 = p[f[3]]
			quad(a, b, cc, d, col, bone, (a + cc) * 0.5 - c)

	func box(center: Vector3, size: Vector3, col: Color, bone: int) -> void:
		tbox(Vector2(center.x, center.z), center.y - size.y * 0.5, center.y + size.y * 0.5, Vector2(size.x, size.z), Vector2(size.x, size.z), col, bone)

	## Tapered six-sided limb from a to b.
	func limb(a: Vector3, b: Vector3, ra: float, rb: float, col: Color, bone: int) -> void:
		var d := (b - a).normalized()
		var u := d.cross(Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.RIGHT).normalized()
		var v := d.cross(u)
		var n := 6
		var mid := (a + b) * 0.5
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var o0 := u * cos(a0) + v * sin(a0)
			var o1 := u * cos(a1) + v * sin(a1)
			quad(a + o0 * ra, a + o1 * ra, b + o1 * rb, b + o0 * rb, col, bone, (o0 + o1) * 0.5)
			tri(a, a + o0 * ra, a + o1 * ra, col, bone, a - mid)
			tri(b, b + o0 * rb, b + o1 * rb, col, bone, b - mid)


static func _build_mesh(l: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
	var b := _Builder.new()
	b.rng = rng
	var zombie: bool = l.zombie
	var shirt: Color = l.shirt
	var pants: Color = l.pants
	var shoes: Color = l.shoes
	var sleeves: int = l.sleeves
	var extra: String = l.extra
	var skin_col: Color = l.skin
	var hair: Color = l.hair
	var fem: bool = int(l.build) == 1
	var bulk: float = l.bulk
	var dark_skin := skin_col.darkened(0.25)
	var bl := 1.0 if zombie else 0.0 # Blood amount.
	var sh := (0.4 if fem else 0.44) * bulk # Shoulder width.
	var arm_x := (0.19 if fem else 0.21) * lerpf(1.0, bulk, 0.8)
	# Torso.
	b.blood = 0.12 * bl
	b.box(Vector3(0, 0.94, 0), Vector3((0.36 if fem else 0.34) * bulk, 0.2, 0.2 * bulk), pants, 0)
	b.tbox(Vector2.ZERO, 1.02, 1.3, Vector2((0.3 if fem else 0.32) * bulk, 0.19 * bulk), Vector2(0.34 * bulk, 0.21 * bulk), shirt, 1)
	b.tbox(Vector2.ZERO, 1.3, 1.58, Vector2(0.34 * bulk, 0.21 * bulk), Vector2(sh, 0.23 * bulk), shirt, 2)
	var front := -0.118 * bulk
	match extra:
		"tie":
			b.box(Vector3(0, 1.38, front), Vector3(0.05, 0.32, 0.01), Color(0.5, 0.08, 0.08), 2)
		"badge":
			b.box(Vector3(0.1, 1.45, front), Vector3(0.05, 0.06, 0.01), Color(0.8, 0.7, 0.3), 2)
		"vest":
			b.box(Vector3(0, 1.38, front), Vector3(0.36 * bulk, 0.06, 0.01), Color(0.85, 0.85, 0.3), 2)
			b.box(Vector3(0, 1.12, front + 0.005), Vector3(0.32 * bulk, 0.05, 0.01), Color(0.85, 0.85, 0.3), 1)
		"hood":
			b.box(Vector3(0, 1.62, 0.11 * bulk), Vector3(0.3, 0.12, 0.1), shirt.darkened(0.1), 2)
		"coat":
			# Long open coat: skirt panels hanging from the hips.
			for side: float in [-1.0, 1.0]:
				b.box(Vector3(0.1 * side * bulk, 0.8, -0.01), Vector3(0.17 * bulk, 0.42, 0.23 * bulk), shirt.darkened(0.04), 11 if side > 0 else 14)
			b.box(Vector3(0, 1.3, front - 0.004), Vector3(0.08, 0.5, 0.01), Color(0.6, 0.62, 0.65), 2)
		"armor":
			var ac := shirt.darkened(0.25)
			b.box(Vector3(0, 1.36, 0), Vector3(sh * 0.95, 0.44, 0.27 * bulk), ac, 2)
			b.box(Vector3(0, 1.1, 0), Vector3(0.36 * bulk, 0.16, 0.25 * bulk), ac, 1)
			for k in 3:
				b.box(Vector3(-0.11 + k * 0.11, 1.24, front - 0.03), Vector3(0.09, 0.11, 0.05), ac.darkened(0.15), 2)
			for side: float in [-1.0, 1.0]:
				b.box(Vector3(arm_x * side, 1.53, 0), Vector3(0.14, 0.06, 0.16), ac, 5 if side > 0 else 8)
	b.blood = 0.04 * bl
	# Neck and head.
	b.limb(Vector3(0, 1.55, 0), Vector3(0, 1.69, 0), 0.05 if fem else 0.055, 0.045 if fem else 0.05, skin_col, 3)
	b.box(Vector3(0, 1.81, -0.005), Vector3(0.19 if fem else 0.2, 0.22, 0.23), skin_col, 4)
	b.box(Vector3(0, 1.695, -0.03), Vector3(0.14 if fem else 0.16, 0.06, 0.17), skin_col if not zombie else dark_skin, 4)
	b.box(Vector3(0, 1.79, -0.125), Vector3(0.04, 0.06, 0.03), skin_col.darkened(0.1), 4)
	for x: float in [-0.05, 0.05]:
		if zombie:
			b.box(Vector3(x, 1.84, -0.118), Vector3(0.05, 0.035, 0.01), Color(0.08, 0.05, 0.04), 4)
		else:
			b.box(Vector3(x, 1.84, -0.118), Vector3(0.045, 0.026, 0.01), Color(0.92, 0.9, 0.86), 4)
			b.box(Vector3(x, 1.84, -0.122), Vector3(0.018, 0.022, 0.01), Color(0.15, 0.1, 0.06), 4)
			b.box(Vector3(x, 1.872, -0.12), Vector3(0.05, 0.01, 0.012), hair.darkened(0.2), 4)
		b.box(Vector3(x * 2.1, 1.8, 0), Vector3(0.02, 0.06, 0.04), dark_skin, 4)
	if l.mouth:
		b.box(Vector3(0, 1.715, -0.118), Vector3(0.09, 0.07, 0.012), Color(0.12, 0.02, 0.02), 4)
	else:
		b.box(Vector3(0, 1.725, -0.118), Vector3(0.09 if zombie else 0.07, 0.02 if zombie else 0.012, 0.01),
				Color(0.3, 0.05, 0.05) if zombie else skin_col.darkened(0.35), 4)
	var beard: int = l.beard
	if beard > 0 and not fem:
		var bc := hair if beard == 2 else hair.lerp(skin_col, 0.55)
		b.box(Vector3(0, 1.715, -0.06), Vector3(0.17, 0.08 if beard == 2 else 0.05, 0.13), bc, 4)
		b.box(Vector3(0, 1.75, -0.122), Vector3(0.1, 0.018, 0.012), bc, 4)
	var head: String = l.head
	var hc: Color = l.head_col
	var style: int = l.hair_style
	if extra == "hood":
		b.box(Vector3(0, 1.88, 0.02), Vector3(0.24, 0.2, 0.26), shirt.darkened(0.1), 4)
	elif head == "helmet":
		b.box(Vector3(0, 1.84, 0.0), Vector3(0.26, 0.28, 0.29), hc, 4)
		b.box(Vector3(0, 1.84, -0.142), Vector3(0.2, 0.08, 0.01), Color(0.15, 0.17, 0.2, 1.0), 4)
	elif head == "army_helmet":
		b.tbox(Vector2(0, 0.0), 1.88, 2.0, Vector2(0.27, 0.3), Vector2(0.2, 0.22), hc, 4)
	else:
		if style != 4:
			var cap_h := 0.02 if style == 3 else 0.05
			b.box(Vector3(0, 1.91 + cap_h * 0.5, 0.01), Vector3(0.215, cap_h, 0.245), hair, 4)
			if style != 3:
				b.box(Vector3(0, 1.86, 0.11), Vector3(0.21, 0.13, 0.03), hair, 4)
				b.box(Vector3(0, 1.9, -0.11), Vector3(0.21, 0.04, 0.03), hair, 4)
			if style == 1:
				b.box(Vector3(0, 1.72, 0.11), Vector3(0.22, 0.24, 0.05), hair, 4)
				for x: float in [-0.105, 0.105]:
					b.box(Vector3(x, 1.75, 0.04), Vector3(0.02, 0.2, 0.12), hair, 4)
			elif style == 2:
				b.box(Vector3(0, 1.82, 0.15), Vector3(0.06, 0.16, 0.05), hair, 4)
		if head == "cap":
			b.box(Vector3(0, 1.94, 0.01), Vector3(0.225, 0.06, 0.25), hc, 4)
			b.box(Vector3(0, 1.915, -0.16), Vector3(0.18, 0.015, 0.1), hc.darkened(0.1), 4)
		elif head == "beanie":
			b.box(Vector3(0, 1.93, 0.01), Vector3(0.23, 0.1, 0.255), hc, 4)
	# Arms: zombies often have a sleeve torn off.
	for side: int in [1, -1]:
		var base := 5 if side == 1 else 8
		var x := arm_x * side
		var torn := rng.randf() < float(l.torn)
		var upper_col := shirt if sleeves >= 1 and not torn else skin_col
		var fore_col := shirt if sleeves == 2 and not torn else skin_col
		var ar := lerpf(1.0, bulk, 0.7) * (0.9 if fem else 1.0)
		b.blood = 0.08 * bl
		b.limb(Vector3(x, 1.53, 0), Vector3(x, 1.25, 0), 0.06 * ar, 0.047 * ar, upper_col, base)
		b.limb(Vector3(x, 1.25, 0), Vector3(x, 1.01, 0), 0.046 * ar, 0.036 * ar, fore_col, base + 1)
		b.blood = 0.0
		b.box(Vector3(x, 0.93, -0.005), Vector3(0.06 * ar, 0.13, 0.09 * ar), skin_col, base + 2)
	# Legs.
	for side: int in [1, -1]:
		var base := 11 if side == 1 else 14
		var x := (0.105 if fem else 0.1) * side * lerpf(1.0, bulk, 0.6)
		var lr := lerpf(1.0, bulk, 0.7)
		b.blood = 0.05 * bl
		b.limb(Vector3(x, 0.92, 0), Vector3(x, 0.5, 0), 0.08 * lr, 0.062 * lr, pants, base)
		b.limb(Vector3(x, 0.5, 0), Vector3(x, 0.1, 0), 0.058 * lr, 0.045 * lr, pants, base + 1)
		b.blood = 0.0
		if l.boots:
			b.box(Vector3(x, 0.14, 0.0), Vector3(0.1, 0.12, 0.12), shoes, base + 1)
		b.box(Vector3(x, 0.045, -0.04), Vector3(0.095, 0.09, 0.25), shoes, base + 2)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = b.verts
	arr[Mesh.ARRAY_NORMAL] = b.normals
	arr[Mesh.ARRAY_COLOR] = b.colors
	arr[Mesh.ARRAY_BONES] = b.bones
	arr[Mesh.ARRAY_WEIGHTS] = b.weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, Assets.material)
	return mesh


# --- Animations ------------------------------------------------------------------

## Keyframes: bone -> [[time, Vector3 euler degrees], ...]. Positive X swings
## a hanging limb forward; negative X leans an upright bone forward.
static func _anim(length: float, loop: bool, keys: Dictionary, hips_pos: Array = []) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for bone in keys:
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath("Skeleton3D:" + bone))
		for k in keys[bone]:
			var e: Vector3 = k[1] * (PI / 180.0)
			if bone.begins_with("upper_arm"):
				e.z = -e.z # Keyframes use "positive = inward"; the rig is the opposite.
			a.rotation_track_insert_key(t, k[0], Quaternion.from_euler(e))
	if not hips_pos.is_empty():
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, NodePath("Skeleton3D:hips"))
		for k in hips_pos:
			a.position_track_insert_key(t, k[0], k[1])
	return a


static func _build_animations() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var L := 1.5
	var h := Vector3(0, 0.95, 0)
	# Limping shamble: arms reaching forward, head lolling, left leg drags.
	lib.add_animation("walk", _anim(L, true, {
		"hips": [[0.0, Vector3(0, 6, 4)], [L * 0.5, Vector3(0, -6, -4)], [L, Vector3(0, 6, 4)]],
		"spine": [[0.0, Vector3(-14, 0, 0)], [L, Vector3(-14, 0, 0)]],
		"chest": [[0.0, Vector3(-6, -5, 0)], [L * 0.5, Vector3(-8, 5, 0)], [L, Vector3(-6, -5, 0)]],
		"head": [[0.0, Vector3(10, 0, 18)], [L * 0.5, Vector3(18, 0, 12)], [L, Vector3(10, 0, 18)]],
		"upper_arm.L": [[0.0, Vector3(70, 0, -8)], [L * 0.5, Vector3(82, 0, -5)], [L, Vector3(70, 0, -8)]],
		"upper_arm.R": [[0.0, Vector3(84, 0, 6)], [L * 0.5, Vector3(72, 0, 8)], [L, Vector3(84, 0, 6)]],
		"forearm.L": [[0.0, Vector3(12, 0, 0)], [L, Vector3(12, 0, 0)]],
		"forearm.R": [[0.0, Vector3(20, 0, 0)], [L, Vector3(20, 0, 0)]],
		"thigh.L": [[0.0, Vector3(14, 0, 0)], [L * 0.5, Vector3(-12, 0, 0)], [L, Vector3(14, 0, 0)]],
		"shin.L": [[0.0, Vector3(-6, 0, 0)], [L * 0.5, Vector3(-10, 0, 0)], [L, Vector3(-6, 0, 0)]],
		"thigh.R": [[0.0, Vector3(-22, 0, 0)], [L * 0.5, Vector3(26, 0, 0)], [L, Vector3(-22, 0, 0)]],
		"shin.R": [[0.0, Vector3(-30, 0, 0)], [L * 0.25, Vector3(-45, 0, 0)], [L * 0.5, Vector3(-5, 0, 0)], [L, Vector3(-30, 0, 0)]],
	}, [[0.0, h], [L * 0.25, h - Vector3(0, 0.04, 0)], [L * 0.5, h], [L * 0.75, h - Vector3(0, 0.05, 0)], [L, h]]))
	var R := 0.7
	lib.add_animation("run", _anim(R, true, {
		"hips": [[0.0, Vector3(0, 10, 0)], [R * 0.5, Vector3(0, -10, 0)], [R, Vector3(0, 10, 0)]],
		"spine": [[0.0, Vector3(-24, 0, 0)], [R, Vector3(-24, 0, 0)]],
		"chest": [[0.0, Vector3(-6, -10, 0)], [R * 0.5, Vector3(-6, 10, 0)], [R, Vector3(-6, -10, 0)]],
		"head": [[0.0, Vector3(20, 0, 8)], [R * 0.5, Vector3(24, 0, -8)], [R, Vector3(20, 0, 8)]],
		"upper_arm.L": [[0.0, Vector3(95, 0, -10)], [R * 0.5, Vector3(55, 0, -15)], [R, Vector3(95, 0, -10)]],
		"upper_arm.R": [[0.0, Vector3(55, 0, 15)], [R * 0.5, Vector3(95, 0, 10)], [R, Vector3(55, 0, 15)]],
		"forearm.L": [[0.0, Vector3(20, 0, 0)], [R, Vector3(20, 0, 0)]],
		"forearm.R": [[0.0, Vector3(20, 0, 0)], [R, Vector3(20, 0, 0)]],
		"thigh.L": [[0.0, Vector3(45, 0, 0)], [R * 0.5, Vector3(-35, 0, 0)], [R, Vector3(45, 0, 0)]],
		"shin.L": [[0.0, Vector3(-20, 0, 0)], [R * 0.5, Vector3(-70, 0, 0)], [R, Vector3(-20, 0, 0)]],
		"thigh.R": [[0.0, Vector3(-35, 0, 0)], [R * 0.5, Vector3(45, 0, 0)], [R, Vector3(-35, 0, 0)]],
		"shin.R": [[0.0, Vector3(-70, 0, 0)], [R * 0.5, Vector3(-20, 0, 0)], [R, Vector3(-70, 0, 0)]],
	}, [[0.0, h], [R * 0.25, h + Vector3(0, 0.05, 0)], [R * 0.5, h], [R * 0.75, h + Vector3(0, 0.05, 0)], [R, h]]))
	var A := 0.9
	lib.add_animation("attack", _anim(A, false, {
		"spine": [[0.0, Vector3(-14, 0, 0)], [A * 0.35, Vector3(-30, 0, 0)], [A, Vector3(-14, 0, 0)]],
		"chest": [[0.0, Vector3(-6, 0, 0)], [A * 0.35, Vector3(-12, 0, 0)], [A, Vector3(-6, 0, 0)]],
		"head": [[0.0, Vector3(10, 0, 10)], [A * 0.35, Vector3(-15, 0, 0)], [A * 0.5, Vector3(25, 0, 0)], [A, Vector3(10, 0, 10)]],
		"upper_arm.L": [[0.0, Vector3(75, 0, -8)], [A * 0.3, Vector3(130, 0, -25)], [A * 0.5, Vector3(80, 0, 10)], [A, Vector3(75, 0, -8)]],
		"upper_arm.R": [[0.0, Vector3(80, 0, 6)], [A * 0.3, Vector3(130, 0, 25)], [A * 0.5, Vector3(80, 0, -10)], [A, Vector3(80, 0, 6)]],
		"forearm.L": [[0.0, Vector3(12, 0, 0)], [A * 0.3, Vector3(5, 0, 0)], [A * 0.5, Vector3(50, 0, 0)], [A, Vector3(12, 0, 0)]],
		"forearm.R": [[0.0, Vector3(20, 0, 0)], [A * 0.3, Vector3(5, 0, 0)], [A * 0.5, Vector3(50, 0, 0)], [A, Vector3(20, 0, 0)]],
		"thigh.L": [[0.0, Vector3(0, 0, 0)], [A * 0.35, Vector3(20, 0, 0)], [A, Vector3(0, 0, 0)]],
		"thigh.R": [[0.0, Vector3(0, 0, 0)], [A * 0.35, Vector3(-15, 0, 0)], [A, Vector3(0, 0, 0)]],
	}))
	var H := 0.4
	lib.add_animation("hit", _anim(H, false, {
		"spine": [[0.0, Vector3(-14, 0, 0)], [H * 0.3, Vector3(12, 8, 0)], [H, Vector3(-14, 0, 0)]],
		"head": [[0.0, Vector3(10, 0, 10)], [H * 0.3, Vector3(-30, 15, 0)], [H, Vector3(10, 0, 10)]],
		"upper_arm.L": [[0.0, Vector3(70, 0, -8)], [H * 0.3, Vector3(30, 0, -30)], [H, Vector3(70, 0, -8)]],
		"upper_arm.R": [[0.0, Vector3(84, 0, 6)], [H * 0.3, Vector3(40, 0, 30)], [H, Vector3(84, 0, 6)]],
	}))
	var D := 1.0
	lib.add_animation("death", _anim(D, false, {
		"hips": [[0.0, Vector3(0, 0, 0)], [D * 0.6, Vector3(85, 0, 5)], [D, Vector3(90, 0, 5)]],
		"spine": [[0.0, Vector3(-14, 0, 0)], [D * 0.6, Vector3(5, 0, 0)], [D, Vector3(0, 0, 0)]],
		"head": [[0.0, Vector3(10, 0, 10)], [D * 0.7, Vector3(-30, 0, 30)], [D, Vector3(-20, 0, 40)]],
		"upper_arm.L": [[0.0, Vector3(70, 0, -8)], [D * 0.6, Vector3(160, 0, -40)], [D, Vector3(170, 0, -60)]],
		"upper_arm.R": [[0.0, Vector3(84, 0, 6)], [D * 0.6, Vector3(150, 0, 50)], [D, Vector3(160, 0, 70)]],
		"thigh.L": [[0.0, Vector3(0, 0, 0)], [D * 0.6, Vector3(-40, 0, 10)], [D, Vector3(-80, 0, 15)]],
		"thigh.R": [[0.0, Vector3(0, 0, 0)], [D * 0.6, Vector3(-20, 0, -10)], [D, Vector3(-70, 0, -20)]],
		"shin.L": [[0.0, Vector3(0, 0, 0)], [D, Vector3(-20, 0, 0)]],
		"shin.R": [[0.0, Vector3(0, 0, 0)], [D, Vector3(-40, 0, 0)]],
	}, [[0.0, h], [D * 0.6, Vector3(0, 0.35, 0.3)], [D, Vector3(0, 0.18, 0.45)]]))
	var I := 3.0
	lib.add_animation("idle", _anim(I, true, {
		"hips": [[0.0, Vector3(0, 0, 3)], [I * 0.5, Vector3(0, 0, -3)], [I, Vector3(0, 0, 3)]],
		"spine": [[0.0, Vector3(-10, 0, 0)], [I * 0.5, Vector3(-14, 0, 0)], [I, Vector3(-10, 0, 0)]],
		"head": [[0.0, Vector3(25, 10, 15)], [I * 0.5, Vector3(30, -10, 20)], [I, Vector3(25, 10, 15)]],
		"upper_arm.L": [[0.0, Vector3(8, 0, -6)], [I, Vector3(8, 0, -6)]],
		"upper_arm.R": [[0.0, Vector3(14, 0, 6)], [I, Vector3(14, 0, 6)]],
		"forearm.L": [[0.0, Vector3(10, 0, 0)], [I, Vector3(10, 0, 0)]],
		"forearm.R": [[0.0, Vector3(16, 0, 0)], [I, Vector3(16, 0, 0)]],
		"shin.R": [[0.0, Vector3(-8, 0, 0)], [I, Vector3(-8, 0, 0)]],
	}))
	# Crawlers: lying prone, hauling themselves along with their arms.
	var prone := Vector3(0, 0.2, 0.05)
	var C := 1.6
	lib.add_animation("crawl", _anim(C, true, {
		"hips": [[0.0, Vector3(-82, 0, 6)], [C * 0.5, Vector3(-82, 0, -6)], [C, Vector3(-82, 0, 6)]],
		"spine": [[0.0, Vector3(8, 0, 0)], [C, Vector3(8, 0, 0)]],
		"chest": [[0.0, Vector3(6, -8, 0)], [C * 0.5, Vector3(6, 8, 0)], [C, Vector3(6, -8, 0)]],
		"head": [[0.0, Vector3(55, 0, 8)], [C * 0.5, Vector3(50, 0, -8)], [C, Vector3(55, 0, 8)]],
		"upper_arm.L": [[0.0, Vector3(170, 0, -10)], [C * 0.5, Vector3(100, 0, -20)], [C, Vector3(170, 0, -10)]],
		"upper_arm.R": [[0.0, Vector3(100, 0, 20)], [C * 0.5, Vector3(170, 0, 10)], [C, Vector3(100, 0, 20)]],
		"forearm.L": [[0.0, Vector3(10, 0, 0)], [C * 0.5, Vector3(60, 0, 0)], [C, Vector3(10, 0, 0)]],
		"forearm.R": [[0.0, Vector3(60, 0, 0)], [C * 0.5, Vector3(10, 0, 0)], [C, Vector3(60, 0, 0)]],
		"thigh.L": [[0.0, Vector3(-5, 0, 8)], [C * 0.5, Vector3(8, 0, 4)], [C, Vector3(-5, 0, 8)]],
		"thigh.R": [[0.0, Vector3(8, 0, -4)], [C * 0.5, Vector3(-5, 0, -8)], [C, Vector3(8, 0, -4)]],
		"shin.L": [[0.0, Vector3(-20, 0, 0)], [C, Vector3(-20, 0, 0)]],
		"shin.R": [[0.0, Vector3(-35, 0, 0)], [C, Vector3(-35, 0, 0)]],
	}, [[0.0, prone], [C * 0.5, prone + Vector3(0, 0.02, 0)], [C, prone]]))
	lib.add_animation("crawl_idle", _anim(I, true, {
		"hips": [[0.0, Vector3(-84, 0, 3)], [I * 0.5, Vector3(-84, 0, -3)], [I, Vector3(-84, 0, 3)]],
		"spine": [[0.0, Vector3(4, 0, 0)], [I, Vector3(4, 0, 0)]],
		"head": [[0.0, Vector3(30, 15, 10)], [I * 0.5, Vector3(40, -15, 10)], [I, Vector3(30, 15, 10)]],
		"upper_arm.L": [[0.0, Vector3(120, 0, -25)], [I, Vector3(120, 0, -25)]],
		"upper_arm.R": [[0.0, Vector3(110, 0, 25)], [I, Vector3(110, 0, 25)]],
		"forearm.L": [[0.0, Vector3(40, 0, 0)], [I, Vector3(40, 0, 0)]],
		"forearm.R": [[0.0, Vector3(50, 0, 0)], [I, Vector3(50, 0, 0)]],
		"shin.L": [[0.0, Vector3(-20, 0, 0)], [I, Vector3(-20, 0, 0)]],
		"shin.R": [[0.0, Vector3(-30, 0, 0)], [I, Vector3(-30, 0, 0)]],
	}, [[0.0, prone], [I, prone]]))
	var G := 0.9
	lib.add_animation("crawl_attack", _anim(G, false, {
		"hips": [[0.0, Vector3(-82, 0, 0)], [G * 0.3, Vector3(-70, 0, 0)], [G, Vector3(-82, 0, 0)]],
		"spine": [[0.0, Vector3(8, 0, 0)], [G * 0.3, Vector3(20, 0, 0)], [G, Vector3(8, 0, 0)]],
		"head": [[0.0, Vector3(55, 0, 0)], [G * 0.3, Vector3(70, 0, 0)], [G * 0.5, Vector3(20, 0, 0)], [G, Vector3(55, 0, 0)]],
		"upper_arm.L": [[0.0, Vector3(150, 0, -10)], [G * 0.3, Vector3(175, 0, -30)], [G * 0.5, Vector3(130, 0, 5)], [G, Vector3(150, 0, -10)]],
		"upper_arm.R": [[0.0, Vector3(150, 0, 10)], [G * 0.3, Vector3(175, 0, 30)], [G * 0.5, Vector3(130, 0, -5)], [G, Vector3(150, 0, 10)]],
		"forearm.L": [[0.0, Vector3(20, 0, 0)], [G * 0.5, Vector3(70, 0, 0)], [G, Vector3(20, 0, 0)]],
		"forearm.R": [[0.0, Vector3(20, 0, 0)], [G * 0.5, Vector3(70, 0, 0)], [G, Vector3(20, 0, 0)]],
	}, [[0.0, prone], [G * 0.3, prone + Vector3(0, 0.08, -0.1)], [G, prone]]))
	lib.add_animation("crawl_death", _anim(0.6, false, {
		"hips": [[0.0, Vector3(-82, 0, 0)], [0.6, Vector3(-88, 0, 10)]],
		"head": [[0.0, Vector3(50, 0, 0)], [0.6, Vector3(-10, 0, 40)]],
		"upper_arm.L": [[0.0, Vector3(140, 0, -10)], [0.6, Vector3(100, 0, -50)]],
		"upper_arm.R": [[0.0, Vector3(140, 0, 10)], [0.6, Vector3(160, 0, 40)]],
	}, [[0.0, prone], [0.6, prone - Vector3(0, 0.06, 0)]]))
	# Screamers throw their head back and shriek.
	var S := 1.4
	lib.add_animation("scream", _anim(S, false, {
		"spine": [[0.0, Vector3(-14, 0, 0)], [S * 0.25, Vector3(12, 0, 0)], [S * 0.8, Vector3(10, 0, 0)], [S, Vector3(-14, 0, 0)]],
		"chest": [[0.0, Vector3(-6, 0, 0)], [S * 0.25, Vector3(10, 0, 0)], [S, Vector3(-6, 0, 0)]],
		"head": [[0.0, Vector3(10, 0, 10)], [S * 0.25, Vector3(-40, 0, 0)], [S * 0.5, Vector3(-35, 5, 0)], [S * 0.8, Vector3(-40, -5, 0)], [S, Vector3(10, 0, 10)]],
		"upper_arm.L": [[0.0, Vector3(70, 0, -8)], [S * 0.25, Vector3(30, 0, -70)], [S * 0.8, Vector3(35, 0, -75)], [S, Vector3(70, 0, -8)]],
		"upper_arm.R": [[0.0, Vector3(84, 0, 6)], [S * 0.25, Vector3(30, 0, 70)], [S * 0.8, Vector3(35, 0, 75)], [S, Vector3(84, 0, 6)]],
		"forearm.L": [[0.0, Vector3(12, 0, 0)], [S * 0.25, Vector3(40, 0, 0)], [S, Vector3(12, 0, 0)]],
		"forearm.R": [[0.0, Vector3(20, 0, 0)], [S * 0.25, Vector3(40, 0, 0)], [S, Vector3(20, 0, 0)]],
	}))
	# Subdued (a turned player, knocked down and waiting for the cure).
	var down := Vector3(0, 0.18, 0.45)
	lib.add_animation("subdued", _anim(I, true, {
		"hips": [[0.0, Vector3(90, 0, 5)], [I, Vector3(90, 0, 5)]],
		"spine": [[0.0, Vector3(0, 0, 0)], [I * 0.5, Vector3(-8, 0, 0)], [I, Vector3(0, 0, 0)]],
		"head": [[0.0, Vector3(-20, 0, 40)], [I * 0.3, Vector3(-30, 0, 20)], [I * 0.7, Vector3(-15, 0, 45)], [I, Vector3(-20, 0, 40)]],
		"upper_arm.L": [[0.0, Vector3(170, 0, -60)], [I * 0.4, Vector3(140, 0, -40)], [I, Vector3(170, 0, -60)]],
		"upper_arm.R": [[0.0, Vector3(160, 0, 70)], [I * 0.6, Vector3(130, 0, 50)], [I, Vector3(160, 0, 70)]],
		"thigh.L": [[0.0, Vector3(-80, 0, 15)], [I * 0.5, Vector3(-60, 0, 15)], [I, Vector3(-80, 0, 15)]],
		"thigh.R": [[0.0, Vector3(-70, 0, -20)], [I, Vector3(-70, 0, -20)]],
		"shin.L": [[0.0, Vector3(-20, 0, 0)], [I * 0.5, Vector3(-50, 0, 0)], [I, Vector3(-20, 0, 0)]],
		"shin.R": [[0.0, Vector3(-40, 0, 0)], [I, Vector3(-40, 0, 0)]],
	}, [[0.0, down], [I, down]]))
	# Living survivors (other players): upright, arms at their sides.
	var HW := 1.0
	lib.add_animation("h_idle", _anim(I, true, {
		"spine": [[0.0, Vector3(0, 0, 0)], [I * 0.5, Vector3(-2, 0, 0)], [I, Vector3(0, 0, 0)]],
		"head": [[0.0, Vector3(0, 0, 0)], [I * 0.5, Vector3(3, 5, 0)], [I, Vector3(0, 0, 0)]],
		"upper_arm.L": [[0.0, Vector3(4, 0, -4)], [I, Vector3(4, 0, -4)]],
		"upper_arm.R": [[0.0, Vector3(4, 0, 4)], [I, Vector3(4, 0, 4)]],
		"forearm.L": [[0.0, Vector3(8, 0, 0)], [I, Vector3(8, 0, 0)]],
		"forearm.R": [[0.0, Vector3(8, 0, 0)], [I, Vector3(8, 0, 0)]],
	}))
	for spec: Array in [["h_walk", HW, 22.0, 28.0, 0.03], ["h_run", 0.62, 45.0, 50.0, 0.06]]:
		var n: String = spec[0]
		var T: float = spec[1]
		var arm: float = spec[2]
		var leg: float = spec[3]
		var bob: float = spec[4]
		var lean := -4.0 if n == "h_walk" else -14.0
		lib.add_animation(n, _anim(T, true, {
			"spine": [[0.0, Vector3(lean, 4, 0)], [T * 0.5, Vector3(lean, -4, 0)], [T, Vector3(lean, 4, 0)]],
			"upper_arm.L": [[0.0, Vector3(-arm, 0, -5)], [T * 0.5, Vector3(arm, 0, -5)], [T, Vector3(-arm, 0, -5)]],
			"upper_arm.R": [[0.0, Vector3(arm, 0, 5)], [T * 0.5, Vector3(-arm, 0, 5)], [T, Vector3(arm, 0, 5)]],
			"forearm.L": [[0.0, Vector3(15, 0, 0)], [T * 0.5, Vector3(arm, 0, 0)], [T, Vector3(15, 0, 0)]],
			"forearm.R": [[0.0, Vector3(arm, 0, 0)], [T * 0.5, Vector3(15, 0, 0)], [T, Vector3(arm, 0, 0)]],
			"thigh.L": [[0.0, Vector3(leg, 0, 0)], [T * 0.5, Vector3(-leg, 0, 0)], [T, Vector3(leg, 0, 0)]],
			"thigh.R": [[0.0, Vector3(-leg, 0, 0)], [T * 0.5, Vector3(leg, 0, 0)], [T, Vector3(-leg, 0, 0)]],
			"shin.L": [[0.0, Vector3(-5, 0, 0)], [T * 0.25, Vector3(-leg * 1.4, 0, 0)], [T * 0.5, Vector3(-5, 0, 0)], [T, Vector3(-5, 0, 0)]],
			"shin.R": [[0.0, Vector3(-5, 0, 0)], [T * 0.5, Vector3(-5, 0, 0)], [T * 0.75, Vector3(-leg * 1.4, 0, 0)], [T, Vector3(-5, 0, 0)]],
		}, [[0.0, h], [T * 0.25, h + Vector3(0, bob, 0)], [T * 0.5, h], [T * 0.75, h + Vector3(0, bob, 0)], [T, h]]))
	var ch := Vector3(0, 0.62, 0)
	lib.add_animation("h_crouch", _anim(HW * 1.2, true, {
		"spine": [[0.0, Vector3(-25, 0, 0)], [HW * 1.2, Vector3(-25, 0, 0)]],
		"head": [[0.0, Vector3(20, 0, 0)], [HW * 1.2, Vector3(20, 0, 0)]],
		"upper_arm.L": [[0.0, Vector3(25, 0, -8)], [HW * 0.6, Vector3(35, 0, -8)], [HW * 1.2, Vector3(25, 0, -8)]],
		"upper_arm.R": [[0.0, Vector3(35, 0, 8)], [HW * 0.6, Vector3(25, 0, 8)], [HW * 1.2, Vector3(35, 0, 8)]],
		"forearm.L": [[0.0, Vector3(40, 0, 0)], [HW * 1.2, Vector3(40, 0, 0)]],
		"forearm.R": [[0.0, Vector3(40, 0, 0)], [HW * 1.2, Vector3(40, 0, 0)]],
		"thigh.L": [[0.0, Vector3(75, 0, 0)], [HW * 0.6, Vector3(55, 0, 0)], [HW * 1.2, Vector3(75, 0, 0)]],
		"thigh.R": [[0.0, Vector3(55, 0, 0)], [HW * 0.6, Vector3(75, 0, 0)], [HW * 1.2, Vector3(55, 0, 0)]],
		"shin.L": [[0.0, Vector3(-100, 0, 0)], [HW * 1.2, Vector3(-100, 0, 0)]],
		"shin.R": [[0.0, Vector3(-100, 0, 0)], [HW * 1.2, Vector3(-100, 0, 0)]],
	}, [[0.0, ch], [HW * 1.2, ch]]))
	return lib
