class_name Textures
extends RefCounted
## Textures generated in code at startup (no image files to ship).

## Road atlas columns (U ranges). V repeats every ROAD_V_METRES along a road.
const U_HIGHWAY := Vector2(0.0, 0.25)
const U_ROAD := Vector2(0.25, 0.5)
const U_STREET := Vector2(0.5, 0.7)
const U_SIDEWALK := Vector2(0.7, 0.85)
const U_DIRT := Vector2(0.85, 1.0)
const U_PLAIN := 0.53 # Unmarked asphalt, for intersections.
const ROAD_V_METRES := 12.0
const SIZE := 256


static func road_atlas() -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 4242
	noise.frequency = 0.16
	var crack := FastNoiseLite.new()
	crack.seed = 99
	crack.frequency = 0.04
	crack.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	for y in SIZE:
		var v := float(y) / SIZE
		for x in SIZE:
			var u := float(x) / SIZE
			var n := noise.get_noise_2d(x, y) * 0.03
			var asphalt := Color(0.21, 0.21, 0.22).lightened(n) if n > 0.0 else Color(0.21, 0.21, 0.22).darkened(-n)
			if crack.get_noise_2d(x, y) > 0.86:
				asphalt = asphalt.darkened(0.35)
			var c := asphalt
			if u < U_HIGHWAY.y:
				c = _highway(_local(u, U_HIGHWAY), v, asphalt)
			elif u < U_ROAD.y:
				c = _two_lane(_local(u, U_ROAD), v, asphalt)
			elif u < U_STREET.y:
				c = asphalt.lightened(0.04)
			elif u < U_SIDEWALK.y:
				c = Color(0.62, 0.61, 0.58).lightened(n * 2.0)
				# Expansion joints every 1.5 m.
				if fposmod(v * ROAD_V_METRES, 1.5) < 0.04:
					c = c.darkened(0.25)
			else:
				c = Color(0.45, 0.38, 0.28).lightened(n * 4.0)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _local(u: float, range_: Vector2) -> float:
	return (u - range_.x) / (range_.y - range_.x)


static func _dash(v: float) -> bool:
	# 3 m dash, 9 m gap.
	return fposmod(v * ROAD_V_METRES, 12.0) < 3.0


static func _highway(lu: float, v: float, base: Color) -> Color:
	var white := Color(0.85, 0.85, 0.8)
	var yellow := Color(0.85, 0.7, 0.15)
	if lu < 0.025 or lu > 0.975:
		return white
	if (lu > 0.46 and lu < 0.48) or (lu > 0.52 and lu < 0.54):
		return yellow
	if (absf(lu - 0.25) < 0.01 or absf(lu - 0.75) < 0.01) and _dash(v):
		return white
	return base


static func _two_lane(lu: float, v: float, base: Color) -> Color:
	var white := Color(0.85, 0.85, 0.8)
	var yellow := Color(0.85, 0.7, 0.15)
	if lu < 0.04 or lu > 0.96:
		return white
	if (lu > 0.47 and lu < 0.49) or (lu > 0.51 and lu < 0.53 and _dash(v)):
		return yellow
	return base


static func water_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform vec4 water_color : source_color = vec4(0.09, 0.2, 0.24, 1.0);
uniform vec4 sky_color : source_color = vec4(0.55, 0.62, 0.66, 1.0);

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	// Cheap animated ripples from a few sine waves (no textures).
	float dx = cos(wp.x * 0.45 + t * 1.3) * 0.5 + cos((wp.x + wp.z) * 0.9 + t * 2.1) * 0.35;
	float dz = cos(wp.z * 0.38 - t * 1.1) * 0.5 + cos((wp.x - wp.z) * 0.7 - t * 1.7) * 0.35;
	vec3 n_world = normalize(vec3(dx * 0.06, 1.0, dz * 0.06));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(water_color.rgb, sky_color.rgb * 0.6, fres);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	ALPHA = mix(0.78, 0.96, fres);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m
