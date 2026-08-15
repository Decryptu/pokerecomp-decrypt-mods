extends RefCounted

## THE ONE THING IN THIS VIEW THE CARTRIDGE DOES NOT DRAW.
##
## Everything else here is the cartridge's own drawing restated: every shape,
## every colour and every height is read out of what the host decoded. This is
## not. Leaves drift across the daylight and fireflies come out at night, and
## neither is anywhere in the ROM.
##
## So it was OFFERED rather than built, and the reviewer accepted it in round
## thirty-four. It is kept cheap and kept separable for exactly that reason: one
## MultiMesh, one shader, no simulation, nothing stored between frames, and
## removing it is removing this file and the four lines in `diorama.gd` that
## reach it.
##
## THEY RIDE THE CAMERA rather than the map. A mote is a pixel of atmosphere and
## not a thing standing in a place, so there is no reason for one to exist behind
## the player, and a box that follows the aim costs the same on the smallest room
## and on the largest route. `diorama.gd:aim_camera` moves the node.
##
## THE COLOURS ARE INVENTED AND SAY SO. Every other colour in this mod comes off
## the cartridge's own palette; neither of these is sampled, because a mote is
## over the grass as often as over a roof and the atlas has no answer for what is
## under it. Both are the colour of a thing catching light rather than of the
## thing itself, which is what makes them readable at all: a leaf in the drawing's
## own dark green was built first and is invisible over a green world at every
## hour, and a firefly is only ever seen lit.
##
## THE TWO ARE NOT EQUALLY LOUD and that is deliberate. At night a dozen are in
## the frame at once, because a light in the dark is the whole of what a firefly
## is; by day two or three catch the sun and the rest are lost against the world,
## which is also what a real one does.

## How many motes are in the box at once. Small on purpose: the reference's own
## sky is nearly empty, and a cloud of these reads as snow rather than as
## weather.
const COUNT: int = 40
## The box they drift in, in world pixels, centred on wherever the camera is
## aimed. Wider than it is tall, because the shot is a low oblique and a column
## of motes over the player's head is a column nobody sees.
const SPREAD: Vector3 = Vector3(320.0, 96.0, 320.0)
## How far off the ground the box's floor sits. A firefly at ankle height is a
## firefly behind the grass.
const RISE: float = 10.0
## One world pixel, which is the size of a texel on everything else in the frame,
## so a mote is the same grain as the world it drifts over.
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
// A firefly pulses and a leaf does not, so one uniform switches the whole term
// off rather than two shaders carrying nine identical lines between them.
uniform float pulse;

void vertex() {
	// INSTANCE_CUSTOM is the mote's own three phases and its pulse offset, all
	// written once at build time: nothing here is stored between frames.
	vec4 seed = INSTANCE_CUSTOM;
	vec3 home = MODEL_MATRIX[3].xyz;
	vec3 wander = vec3(
		sin((TIME / drift_period.x + seed.x) * 6.2831853),
		sin((TIME / drift_period.y + seed.y) * 6.2831853),
		cos((TIME / drift_period.z + seed.z) * 6.2831853)
	) * drift;
	// WRAPPED INSIDE THE BOX, so a mote that drifts out of one side comes back in
	// at the other and the count in front of the player never falls.
	vec3 at = home + wander;
	vec3 origin = NODE_POSITION_WORLD;
	at = origin + mod(at - origin + spread * 0.5, spread) - spread * 0.5;
	// Billboarded about the mote's own position: a single texel has no side to
	// be seen from.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2],
		vec4(at, 1.0)
	);
	// The pulse is the firefly's whole difference, and it is in the SIZE rather
	// than in the alpha: this renderer draws no transparency anywhere else, and a
	// mote fading through the geometry behind it would be the first.
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
	# Scattered once, from a fixed seed, so a place looks the same on two visits
	# and two runs of a tool photograph the same frame.
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


## Whether anything is drifting at all, which `diorama.gd` hangs the node's own
## visibility on.
func drifting() -> bool:
	return _outside and _time_of_day != CAVE


func _apply() -> void:
	var night: bool = _time_of_day == NIGHT
	material.set_shader_parameter(
		"tone", FIREFLY_COLOR if night else LEAF_COLOR
	)
	material.set_shader_parameter("pulse", 1.0 if night else 0.0)
