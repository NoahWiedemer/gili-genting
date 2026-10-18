shader_type spatial;
// Soft drifting cloud shadows multiplied onto the ground.
render_mode blend_mul, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float strength = 0.28;
uniform vec2 wind = vec2(0.35, 0.12);
uniform float scale = 0.045;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz * scale + wind * TIME * 0.05;
	float n = noise(p) * 0.6 + noise(p * 2.3 + 4.1) * 0.3 + noise(p * 5.1) * 0.1;
	float sh = smoothstep(0.55, 0.75, n);
	ALBEDO = vec3(1.0 - sh * strength);
}
