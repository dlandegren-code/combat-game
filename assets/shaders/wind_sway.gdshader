shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_disabled;
// Foliage and hanging cloth, moved by wind.
//
// The Synty meadow pack's own grass and trees rely on a Unity wind shader that does not come
// across to Godot, so this is its Godot equivalent: a vertex displacement that grows with
// height, so a blade of grass leans while its roots stay put, and a hanging shirt swings from
// its pegs rather than sliding sideways.
//
// TWO FREQUENCIES, NOT ONE
// A single sine over the whole scene makes every plant move in lockstep, which reads as a
// pulsing carpet rather than as wind. So the sway is a slow gust plus a faster flutter, and
// both are offset by WORLD position — that phase offset is what makes one bush lag behind the
// next and the whole clearing look like air is moving through it.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.4;

// How far the top of the mesh travels, in metres.
uniform float sway_strength : hint_range(0.0, 1.0) = 0.12;
uniform float gust_speed : hint_range(0.0, 4.0) = 0.55;
uniform float flutter_speed : hint_range(0.0, 8.0) = 2.3;
// Height over which the sway ramps to full. Grass reaches full lean within a metre; a tree
// should be nearly rigid down at head height, so it wants a much larger value.
uniform float sway_height : hint_range(0.1, 20.0) = 1.2;
// Which way the wind blows, in world space.
uniform vec2 wind_dir = vec2(0.85, 0.35);

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Phase from world position, so neighbours are out of step with each other.
	float phase = world.x * 0.35 + world.z * 0.28;
	float gust = sin(TIME * gust_speed + phase);
	float flutter = sin(TIME * flutter_speed + phase * 2.7) * 0.35;
	// Anchored at the bottom: nothing moves at VERTEX.y = 0, everything moves at sway_height.
	float lean = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	lean *= lean;   // eased, so the middle of a tall blade bends less than its tip
	vec2 push = normalize(wind_dir) * (gust + flutter) * sway_strength * lean;
	VERTEX.x += push.x;
	VERTEX.z += push.y;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb;
	// Scissor rather than blended alpha: a clearing full of grass cards has nothing sensible
	// to depth-sort, and holes punched in the depth buffer are what keep it cheap.
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_threshold;
	ROUGHNESS = 0.9;
}
