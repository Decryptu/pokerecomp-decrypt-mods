extends RefCounted

## Leaves drifting across the daylight and fireflies at night: the one thing in
## this view the cartridge does not draw, so it is kept cheap and separable. One
## MultiMesh, one shader, no simulation, nothing stored between frames, and
## removing it is this file plus four lines in `diorama.gd`.
##
## They ride the camera rather than the map, since a mote is atmosphere and not a
## thing standing in a place. `diorama.gd:aim_camera` moves the node.
##
## The colours are invented and say so. A mote is over grass as often as over a
## roof, so the atlas has no answer for what is under it. Both are the colour of
## a thing catching light: a leaf in the drawing's own dark green is invisible
## over a green world at every hour, and a firefly is only ever seen lit.
##
## The two are not equally loud. At night a dozen are in frame at once; by day two
## or three catch the sun and the rest are lost against the world.

## How many are in the box at once. Small: a cloud of these reads as snow.
const COUNT: int = 40
## The box they drift in, in world pixels, centred on the camera's aim. Wider
## than tall, since the shot is a low oblique.
const SPREAD: Vector3 = Vector3(320.0, 96.0, 320.0)
## How far off the ground the box's floor sits. A firefly at ankle height is a
## firefly behind the grass.
const RISE: float = 10.0
## One world pixel, so a mote is the same grain as the world it drifts over.
const SIZE: float = 1.0

## How long one drift cycle takes, in seconds, and how far a mote travels in one.
## Three periods that share no factor, so a mote never retraces its own path.
const DRIFT_PERIOD: Vector3 = Vector3(11.0, 7.0, 13.0)
const DRIFT: Vector3 = Vector3(28.0, 14.0, 28.0)

## Fireflies at night and leaves by day, and nothing in a cave. Indexed by the
## host's own time of day.
const NIGHT: int = 2
const CAVE: int = 3

const LEAF_COLOR := Color(0.85, 0.76, 0.33)
const FIREFLY_COLOR := Color(0.78, 0.98, 0.55)

const CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec3 spread;
uniform vec3 drift;
uniform vec3 drift_period;
uniform vec4 tone : source_color;
// A firefly pulses and a leaf does not, so one uniform switches the term off
// rather than two shaders carrying the same nine lines.
uniform float pulse;

void vertex() {
	// The mote's three phases and its pulse offset, written once at build time.
	vec4 seed = INSTANCE_CUSTOM;
	vec3 home = MODEL_MATRIX[3].xyz;
	vec3 wander = vec3(
		sin((TIME / drift_period.x + seed.x) * 6.2831853),
		sin((TIME / drift_period.y + seed.y) * 6.2831853),
		cos((TIME / drift_period.z + seed.z) * 6.2831853)
	) * drift;
	// Wrapped inside the box, so one drifting out of a side comes back in at the
	// other and the count in front of the player never falls.
	vec3 at = home + wander;
	vec3 origin = NODE_POSITION_WORLD;
	at = origin + mod(at - origin + spread * 0.5, spread) - spread * 0.5;
	// Billboarded about the mote's own position: a single texel has no side to
	// be seen from.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2],
		vec4(at, 1.0)
	);
	// The pulse is in the SIZE rather than the alpha: this renderer draws no
	// transparency anywhere else.
	float lit = 1.0 - pulse * 0.5 * (1.0 + sin((TIME / 1.7 + seed.w) * 6.2831853));
	VERTEX *= max(lit, 0.0);
}

void fragment() {
	ALBEDO = tone.rgb;
}
"""

var material: ShaderMaterial = null
var mesh: MultiMesh = null

var _outside: bool = true
var _time_of_day: int = 1


func _init() -> void:
	var shader := Shader.new()
	shader.code = CODE
	material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("spread", SPREAD)
	material.set_shader_parameter("drift", DRIFT)
	material.set_shader_parameter("drift_period", DRIFT_PERIOD)
	mesh = MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	mesh.mesh = _quad()
	mesh.instance_count = COUNT
	# A fixed seed, so two visits look the same and a tool shoots the same frame.
	var noise := RandomNumberGenerator.new()
	noise.seed = 0x3f10e5
	for index: int in COUNT:
		var home := Vector3(
			noise.randf_range(-0.5, 0.5) * SPREAD.x,
			noise.randf_range(0.0, 1.0) * SPREAD.y + RISE,
			noise.randf_range(-0.5, 0.5) * SPREAD.z
		)
		mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, home))
		mesh.set_instance_custom_data(index, Color(
			noise.randf(), noise.randf(), noise.randf(), noise.randf()
		))
	_apply()


func _quad() -> ArrayMesh:
	var half: float = SIZE * 0.5
	var vertices := PackedVector3Array([
		Vector3(-half, -half, 0.0), Vector3(half, -half, 0.0),
		Vector3(half, half, 0.0), Vector3(-half, half, 0.0),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var made := ArrayMesh.new()
	made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return made


func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = time_of_day
	_apply()


## A cave has no weather and a room has no sky for a leaf to fall out of.
func set_outside(outside: bool) -> void:
	_outside = outside
	_apply()


## Whether anything is drifting, which `diorama.gd` hangs visibility on.
func drifting() -> bool:
	return _outside and _time_of_day != CAVE


func _apply() -> void:
	var night: bool = _time_of_day == NIGHT
	material.set_shader_parameter(
		"tone", FIREFLY_COLOR if night else LEAF_COLOR
	)
	material.set_shader_parameter("pulse", 1.0 if night else 0.0)
