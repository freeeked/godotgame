shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

group_uniforms CrayonOutlines;
uniform bool enable_outlines = true;
uniform float stroke_thickness : hint_range(0.5, 4.0, 0.25) = 1.75;
uniform float stroke_wobble : hint_range(0.0, 3.0, 0.1) = 1.15; // Hand-drawn wax irregularity along edges
uniform float edge_threshold : hint_range(0.05, 0.8, 0.01) = 0.24; // Ignores soft floor shadows & blob shading
uniform float wax_ink_darkness : hint_range(0.0, 1.0, 0.05) = 0.52; // Deepens each shape's own color instead of harsh black
uniform float wax_ink_saturation : hint_range(1.0, 1.8, 0.05) = 1.35; // Gives outlines a rich colored-wax pigment

group_uniforms WaxAndPaperTexture;
uniform float paper_grain_strength : hint_range(0.0, 0.25, 0.01) = 0.065; // Gentle tooth so the screen never feels noisy
uniform float wax_stroke_strength : hint_range(0.0, 0.25, 0.01) = 0.075; // Diagonal crayon shading texture in midtones
uniform float texture_scale : hint_range(0.5, 3.0, 0.1) = 1.25;
uniform float pixel_chunkiness : hint_range(1.0, 6.0, 1.0) = 2.0; // 1.0 = smooth crayon, 2.0-3.0 = chunky pixel-crayon hybrid

group_uniforms EyeComfortPalette;
uniform float color_steps : hint_range(0.0, 32.0, 1.0) = 16.0; // Soft waxy color banding (0 = off)
uniform float saturation_boost : hint_range(0.8, 1.35, 0.02) = 1.10;
uniform vec3 paper_warmth : source_color = vec3(1.02, 0.99, 0.94); // Warm cream paper tint to prevent eye fatigue
uniform float soft_vignette : hint_range(0.0, 0.35, 0.02) = 0.10;

// Smooth value noise for organic hand-drawn edge wobble and paper fiber
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Measures hue/chroma boundaries while discounting smooth lighting gradients
float chroma_edge_diff(vec3 a, vec3 b) {
	float lum_a = dot(a, vec3(0.299, 0.587, 0.114));
	float lum_b = dot(b, vec3(0.299, 0.587, 0.114));
	vec3 chroma_a = a - vec3(lum_a);
	vec3 chroma_b = b - vec3(lum_b);
	return length(chroma_a - chroma_b) * 1.5 + abs(lum_a - lum_b) * 0.42;
}

vec3 adjust_saturation(vec3 col, float sat) {
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	return mix(vec3(luma), col, sat);
}

void fragment() {
	vec2 screen_res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;

	// Optional chunky pixel-grid quantization so crayon look still pairs with blocky platforming
	if (pixel_chunkiness > 1.0) {
		vec2 grid = screen_res / pixel_chunkiness;
		uv = (floor(uv * grid) + 0.5) / grid;
	}

	// Screen-space coordinates scaled consistently regardless of resolution
	vec2 paper_coord = (uv * screen_res) / (3.0 * texture_scale);

	// 1. Subtle organic wobble for hand-drawn crayon outlines
	vec2 wobble_offset = vec2(
		value_noise(paper_coord * 0.18) - 0.5,
		value_noise(paper_coord * 0.18 + vec2(17.3, 9.2)) - 0.5
	) * SCREEN_PIXEL_SIZE * stroke_wobble * 2.2;

	vec3 base_col = texture(screen_texture, uv).rgb;

	// 2. Waxy hue-matched outlines (blue crayon on blue blocks, green on green, etc.)
	float edge = 0.0;
	vec3 outline_source = base_col;
	if (enable_outlines) {
		vec2 step_uv = SCREEN_PIXEL_SIZE * stroke_thickness * max(1.0, pixel_chunkiness * 0.65);
		vec2 sample_uv = uv + wobble_offset;

		vec3 c_l = texture(screen_texture, sample_uv - vec2(step_uv.x, 0.0)).rgb;
		vec3 c_r = texture(screen_texture, sample_uv + vec2(step_uv.x, 0.0)).rgb;
		vec3 c_u = texture(screen_texture, sample_uv - vec2(0.0, step_uv.y)).rgb;
		vec3 c_d = texture(screen_texture, sample_uv + vec2(0.0, step_uv.y)).rgb;

		float max_diff = max(chroma_edge_diff(c_l, c_r), chroma_edge_diff(c_u, c_d));

		// Break up the outline slightly with paper grain so it looks like textured wax rather than a vector line
		float wax_breakup = mix(0.82, 1.15, value_noise(paper_coord * 0.85));
		edge = smoothstep(edge_threshold, edge_threshold * 1.75, max_diff * wax_breakup);

		outline_source = min(base_col, min(min(c_l, c_r), min(c_u, c_d)));
	}

	// 3. Soft waxy color quantization
	if (color_steps > 1.0) {
		base_col = floor(base_col * color_steps + 0.5) / color_steps;
	}

	// 4. Diagonal crayon stroke & construction-paper tooth
	float fine_paper = value_noise(paper_coord * 1.6) - 0.5;
	// 45-degree diagonal hatching pattern like hand-colored crayon strokes
	vec2 diag_coord = vec2(paper_coord.x + paper_coord.y, (paper_coord.x - paper_coord.y) * 0.16);
	float crayon_hatching = value_noise(diag_coord * 1.35) - 0.5;

	float luma = dot(base_col, vec3(0.299, 0.587, 0.114));
	// Concentrate wax strokes in midtones so bright highlights stay clean and readable
	float midtone_mask = 1.0 - abs(luma - 0.55) * 1.2;
	midtone_mask = clamp(midtone_mask, 0.25, 1.0);

	base_col += fine_paper * paper_grain_strength;
	base_col += crayon_hatching * wax_stroke_strength * midtone_mask;

	// 5. Blend in rich, saturated wax outline
	vec3 crayon_ink = adjust_saturation(outline_source, wax_ink_saturation) * (1.0 - wax_ink_darkness);
	vec3 final_col = mix(base_col, crayon_ink, edge * 0.92);

	// 6. Warm cream paper tone + gentle saturation for eye comfort
	final_col = adjust_saturation(final_col, saturation_boost) * paper_warmth;

	if (soft_vignette > 0.001) {
		vec2 centered = SCREEN_UV * 2.0 - 1.0;
		float vig = 1.0 - dot(centered, centered) * soft_vignette;
		final_col *= clamp(vig, 0.0, 1.0);
	}

	COLOR = vec4(clamp(final_col, 0.0, 1.0), 1.0);
}