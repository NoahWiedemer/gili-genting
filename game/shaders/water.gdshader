shader_type spatial;
// Stylized pixelated turquoise water with depth-based color, shoreline foam and sparkles.
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 shallow : source_color = vec4(0.35, 0.92, 0.85, 1.0);
uniform vec4 mid : source_color = vec4(0.08, 0.68, 0.74, 1.0);
uniform vec4 deep : source_color = vec4(0.03, 0.25, 0.42, 1.0);
uniform vec4 foam_col : source_color = vec4(0.95, 1.0, 0.98, 1.0);
uniform float pixel = 16.0;          // pixels per world unit for the stylized look
uniform float depth_scale = 1.4;
uniform float foam_width = 0.07;
uniform float glow = 0.0;            // extra emission at night
uniform float wave_speed = 1.0;
uniform float min_alpha = 0.55;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.8 + TIME * 1.2 * wave_speed) * 0.025 + cos(wpos.z * 0.6 + TIME * wave_speed) * 0.025;
}

void fragment() {
	vec2 p = floor(wpos.xz * pixel) / pixel;   // pixelate in world space
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float water_depth = scene_depth - (-VERTEX.z);
	float d = clamp(water_depth * depth_scale * 0.5, 0.0, 1.0);
	float t = TIME * wave_speed;
	float n = noise(p * 1.7 + vec2(t * 0.25, t * 0.12)) * 0.6 + noise(p * 4.1 - vec2(t * 0.3, -t * 0.2)) * 0.4;
	vec3 col = mix(shallow.rgb, mid.rgb, smoothstep(0.05, 0.45, d + n * 0.12));
	col = mix(col, deep.rgb, smoothstep(0.45, 1.0, d));
	// caustic lines in shallow water
	float caus = smoothstep(0.78, 0.86, noise(p * 3.0 + vec2(t * 0.4, t * 0.33)) * noise(p * 2.3 - vec2(t * 0.2, 0.0)) * 2.2);
	col += caus * (1.0 - d) * 0.22;
	// shoreline foam (stepped)
	float foam_line = foam_width * (0.8 + 0.4 * sin(t * 1.6 + p.x * 2.0 + p.y));
	float foam = step(water_depth, foam_line);
	foam = max(foam, step(water_depth, foam_line * 2.0) * step(0.7, noise(p * 6.0 + t * 0.5)));
	col = mix(col, foam_col.rgb, foam * 0.9);
	// sparkles
	float sp = step(0.994, hash(floor(p * 8.0) + floor(t * 3.0)));
	col += sp * 0.6 * (1.0 - foam);
	ALBEDO = col;
	ALPHA = mix(min_alpha, 0.97, smoothstep(0.0, 0.6, d)) + foam * 0.4;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = col * glow;
}
