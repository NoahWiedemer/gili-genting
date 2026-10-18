shader_type spatial;
// Pixel-art sprite quad (upright, camera never rotates): alpha scissor, shadows, wind sway, hit flash.
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float sway = 0.0;          // wind strength for foliage (world units at top)
uniform float sway_speed = 1.3;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash = 0.0;
uniform float emission = 0.0;      // self-illumination (0..1)
uniform float alpha = 1.0;
uniform bool flip = false;
uniform float rim = 0.25;
uniform float lean = 0.0;          // shifts the top of the sprite sideways (procedural animation)

varying float v_height;

void vertex() {
	v_height = UV.y; // 0 top, 1 bottom
	if (sway > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float k = pow(1.0 - UV.y, 2.0);
		float t = TIME * sway_speed + wp.x * 0.35 + wp.z * 0.21;
		VERTEX.x += (sin(t) * 0.6 + sin(t * 2.3 + 1.7) * 0.25) * sway * k;
	}
	VERTEX.x += lean * (1.0 - UV.y);
	if (flip) {
		UV.x = 1.0 - UV.x;
	}
	// face camera direction for lighting purposes (sprites are upright quads facing +Z)
	NORMAL = vec3(0.0, 0.35, 1.0);
}

void fragment() {
	vec4 c = texture(tex, UV) * tint;
	if (c.a < 0.5) {
		discard;
	}
	if (alpha < 0.999) {
		// ordered dither dissolve (pixel friendly fade)
		ivec2 q = ivec2(FRAGCOORD.xy) % 4;
		int idx = q.x + q.y * 4;
		float b[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		if ((b[idx] + 0.5) / 16.0 > alpha) {
			discard;
		}
	}
	vec3 col = mix(c.rgb, flash_color.rgb, flash);
	ALBEDO = col;
	EMISSION = col * emission + flash_color.rgb * flash * 0.6;
	BACKLIGHT = vec3(rim);
}
