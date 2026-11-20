shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

group_uniforms ChunkyPixelGrid;
uniform bool enable_pixelation = true;
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 3.0; // 3.0 or 4.0 gives chunky, cohesive blocks

group_uniforms SoftComicOutlines;
uniform bool enable_outlines = true;
uniform float outline_thickness_blocks : hint_range(1.0, 3.0, 1.0) = 1.0; // Measured in whole pixel blocks so lines stay uniform
uniform float edge_threshold : hint_range(0.05, 0.8, 0.01) = 0.28; // Higher threshold ignores shadow bands on blobs & floors
uniform float ink_darkness : hint_range(0.0, 1.0, 0.05) = 0.58; // Darkens the object's own color instead of harsh pure black
uniform vec4 ink_tint : source_color = vec4(0.10, 0.11, 0.18, 1.0); // Subtle cool navy undertone mixed into outlines

group_uniforms EyeComfortAndPolish;
uniform float color_posterize_steps : hint_range(0.0, 32.0, 1.0) = 18.0; // Gentle cel-like color grouping (0 = off)
uniform float saturation_boost : hint_range(0.8, 1.3, 0.02) = 1.06;
uniform float warm_highlight_tint : hint_range(0.0, 0.2, 0.01) = 0.04; // Takes the harsh digital edge off whites/blues
uniform float soft_vignette : hint_range(0.0, 0.4, 0.02) = 0.12;

// Compare perceptual color distance while discounting pure brightness/shadow shifts
float color_edge_diff(vec3 a, vec3 b) {
	float lum_a = dot(a, vec3(0.299, 0.587, 0.114));
	float lum_b = dot(b, vec3(0.299, 0.587, 0.114));
	vec3 chroma_a = a - vec3(lum_a);
	vec3 chroma_b = b - vec3(lum_b);
	// Weight hue/color boundaries higher than shadow boundaries so floor shadows don't get outlined
	return length(chroma_a - chroma_b) * 1.45 + abs(lum_a - lum_b) * 0.45;
}

void fragment() {
	vec2 screen_res = 1.0 / SCREEN_PIXEL_SIZE;
	float block = enable_pixelation ? max(1.0, pixel_size) : 1.0;
	vec2 grid = screen_res / block;

	// Snap UV to the exact center of each chunky pixel block
	vec2 uv = (floor(SCREEN_UV * grid) + 0.5) / grid;
	vec3 base_col = texture(screen_texture, uv).rgb;

	// 1. Crisp block-aligned outlines (1 whole pixel block thick)
	float edge = 0.0;
	vec3 neighbor_darkest = base_col;
	if (enable_outlines) {
		vec2 step_uv = (vec2(1.0) / grid) * outline_thickness_blocks;

		vec3 c_l = texture(screen_texture, uv - vec2(step_uv.x, 0.0)).rgb;
		vec3 c_r = texture(screen_texture, uv + vec2(step_uv.x, 0.0)).rgb;
		vec3 c_u = texture(screen_texture, uv - vec2(0.0, step_uv.y)).rgb;
		vec3 c_d = texture(screen_texture, uv + vec2(0.0, step_uv.y)).rgb;

		float diff_h = color_edge_diff(c_l, c_r);
		float diff_v = color_edge_diff(c_u, c_d);
		float max_diff = max(diff_h, diff_v);

		edge = smoothstep(edge_threshold, edge_threshold * 1.65, max_diff);
		neighbor_darkest = min(base_col, min(min(c_l, c_r), min(c_u, c_d)));
	}

	// 2. Gentle color posterization for a smooth illustrated feel
	if (color_posterize_steps > 1.0) {
		base_col = floor(base_col * color_posterize_steps + 0.5) / color_posterize_steps;
	}

	// 3. Surface-tinted ink outline (deepened object color + subtle navy tint)
	vec3 colored_ink = mix(neighbor_darkest * (1.0 - ink_darkness), ink_tint.rgb, 0.35);
	vec3 final_col = mix(base_col, colored_ink, edge);

	// 4. Eye-comfort color grading (mild warmth + soft edge vignette instead of flickering scanlines)
	float luma = dot(final_col, vec3(0.299, 0.587, 0.114));
	final_col = mix(vec3(luma), final_col, saturation_boost);
	final_col += vec3(warm_highlight_tint, warm_highlight_tint * 0.7, 0.0) * luma;

	if (soft_vignette > 0.001) {
		vec2 centered = SCREEN_UV * 2.0 - 1.0;
		float vig = 1.0 - dot(centered, centered) * soft_vignette;
		final_col *= clamp(vig, 0.0, 1.0);
	}

	COLOR = vec4(final_col, 1.0);
}