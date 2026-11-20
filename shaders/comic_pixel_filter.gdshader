shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

group_uniforms Pixelation;
uniform bool enable_pixelation = true;
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;

group_uniforms InkOutlines;
uniform bool enable_outlines = true;
uniform vec4 outline_color : source_color = vec4(0.06, 0.07, 0.11, 1.0);
uniform float outline_thickness : hint_range(0.5, 3.0, 0.25) = 1.25;
uniform float edge_threshold : hint_range(0.05, 0.8, 0.01) = 0.20;

group_uniforms RetroPolish;
uniform float color_posterize_steps : hint_range(0.0, 32.0, 1.0) = 0.0;
uniform float scanline_strength : hint_range(0.0, 0.35, 0.01) = 0.06;

float get_luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 screen_res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;

	if (enable_pixelation && pixel_size > 1.0) {
		vec2 grid = screen_res / pixel_size;
		uv = (floor(uv * grid) + 0.5) / grid;
	}

	vec3 base_col = texture(screen_texture, uv).rgb;

	if (color_posterize_steps > 1.0) {
		base_col = floor(base_col * color_posterize_steps + 0.5) / color_posterize_steps;
	}

	float edge = 0.0;
	if (enable_outlines) {
		vec2 step_uv = SCREEN_PIXEL_SIZE * outline_thickness * max(1.0, pixel_size * 0.75);

		vec3 c_tl = texture(screen_texture, uv + vec2(-step_uv.x, -step_uv.y)).rgb;
		vec3 c_t  = texture(screen_texture, uv + vec2(0.0, -step_uv.y)).rgb;
		vec3 c_tr = texture(screen_texture, uv + vec2(step_uv.x, -step_uv.y)).rgb;
		vec3 c_l  = texture(screen_texture, uv + vec2(-step_uv.x, 0.0)).rgb;
		vec3 c_r  = texture(screen_texture, uv + vec2(step_uv.x, 0.0)).rgb;
		vec3 c_bl = texture(screen_texture, uv + vec2(-step_uv.x, step_uv.y)).rgb;
		vec3 c_b  = texture(screen_texture, uv + vec2(0.0, step_uv.y)).rgb;
		vec3 c_br = texture(screen_texture, uv + vec2(step_uv.x, step_uv.y)).rgb;

		// Sobel edge filter across both color channels and brightness
		vec3 gx = -c_tl - 2.0 * c_l - c_bl + c_tr + 2.0 * c_r + c_br;
		vec3 gy = -c_tl - 2.0 * c_t - c_tr + c_bl + 2.0 * c_b + c_br;
		float col_grad = length(gx) + length(gy);

		float luma_grad = abs(get_luma(c_r) - get_luma(c_l)) + abs(get_luma(c_b) - get_luma(c_t));
		float combined = max(col_grad * 0.45, luma_grad * 1.4);

		edge = smoothstep(edge_threshold, edge_threshold * 2.0, combined);
	}

	vec3 final_col = mix(base_col, outline_color.rgb, edge * outline_color.a);

	if (scanline_strength > 0.001) {
		float scan = sin(FRAGCOORD.y * 3.14159) * 0.5 + 0.5;
		final_col *= 1.0 - (scan * scanline_strength);
	}

	COLOR = vec4(final_col, 1.0);
}