shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

group_uniforms SculptedClayCreases;
uniform bool enable_clay_creases = true;
uniform float crease_width : hint_range(0.5, 4.0, 0.25) = 1.75;
uniform float crease_threshold : hint_range(0.05, 0.8, 0.01) = 0.22;
uniform float crease_shadow_strength : hint_range(0.0, 0.8, 0.05) = 0.34; // Soft pressed-clay shadow instead of black ink
uniform float rim_highlight_strength : hint_range(0.0, 0.6, 0.02) = 0.16; // Soft rounded clay edge sheen

group_uniforms PolymerClayTexture;
uniform float fingerprint_strength : hint_range(0.0, 0.20, 0.005) = 0.045; // Subtle sculpted thumbprint & ridge grain
uniform float clay_lumpiness : hint_range(0.0, 0.15, 0.005) = 0.035; // Soft organic light variation across flat surfaces
uniform float texture_scale : hint_range(0.5, 3.0, 0.1) = 1.15;

group_uniforms SubsurfaceAndPalette;
uniform float color_softness_steps : hint_range(0.0, 32.0, 1.0) = 0.0; // Keep 0 for smooth sculpted clay gradients
uniform float saturation_boost : hint_range(0.8, 1.4, 0.02) = 1.12; // Rich, playful toy-clay colors
uniform vec3 subsurface_warmth : source_color = vec3(1.03, 0.99, 0.95); // Warm creamy light scatter
uniform float miniature_tilt_shift : hint_range(0.0, 2.5, 0.1) = 0.85; // Subtle tabletop diorama blur at top/bottom edges
uniform float soft_vignette : hint_range(0.0, 0.35, 0.02) = 0.10;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
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

// Procedural swirled fingerprint ridges like real hand-sculpted polymer clay
float fingerprint_pattern(vec2 p) {
	float n1 = value_noise(p * 0.28);
	float n2 = value_noise(p * 0.28 + vec2(11.4, 27.8));
	vec2 swirl = p * 1.15 + vec2(n1, n2) * 3.8;
	float ridges = sin(swirl.x * 3.14159 + sin(swirl.y * 2.4));
	// Break up ridges organically so they only appear in soft patches
	float patch_mask = smoothstep(0.32, 0.72, value_noise(p * 0.14 + vec2(5.2, 3.1)));
	return ridges * patch_mask;
}

float chroma_edge_diff(vec3 a, vec3 b) {
	float lum_a = dot(a, vec3(0.299, 0.587, 0.114));
	float lum_b = dot(b, vec3(0.299, 0.587, 0.114));
	vec3 chroma_a = a - vec3(lum_a);
	vec3 chroma_b = b - vec3(lum_b);
	return length(chroma_a - chroma_b) * 1.4 + abs(lum_a - lum_b) * 0.5;
}

vec3 adjust_saturation(vec3 col, float sat) {
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	return mix(vec3(luma), col, sat);
}

void fragment() {
	vec2 screen_res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;

	// 1. Optional subtle miniature tilt-shift blur at top & bottom of screen (leaves gameplay center razor sharp)
	float dist_from_center_y = abs(uv.y - 0.52);
	float blur_lod = smoothstep(0.26, 0.50, dist_from_center_y) * miniature_tilt_shift;
	vec3 base_col = textureLod(screen_texture, uv, blur_lod).rgb;

	// 2. Sculpted clay seams & soft rounded bevel highlights
	if (enable_clay_creases) {
		vec2 step_uv = SCREEN_PIXEL_SIZE * crease_width;

		vec3 c_l = texture(screen_texture, uv - vec2(step_uv.x, 0.0)).rgb;
		vec3 c_r = texture(screen_texture, uv + vec2(step_uv.x, 0.0)).rgb;
		vec3 c_u = texture(screen_texture, uv - vec2(0.0, step_uv.y)).rgb;
		vec3 c_d = texture(screen_texture, uv + vec2(0.0, step_uv.y)).rgb;

		float max_diff = max(chroma_edge_diff(c_l, c_r), chroma_edge_diff(c_u, c_d));
		float seam = smoothstep(crease_threshold, crease_threshold * 1.85, max_diff);

		// Warm pressed-clay ambient occlusion crease where two shapes meet
		vec3 crease_tint = base_col * vec3(0.72, 0.68, 0.74) * (1.0 - crease_shadow_strength);
		base_col = mix(base_col, crease_tint, seam);

		// Subtle soft highlight just inside upper-left edges to round out blocky primitives
		float top_left_diff = chroma_edge_diff(base_col, c_u) + chroma_edge_diff(base_col, c_l);
		float bevel_glow = smoothstep(crease_threshold * 1.1, crease_threshold * 2.2, top_left_diff);
		base_col += vec3(1.0, 0.97, 0.92) * (bevel_glow * rim_highlight_strength * (1.0 - seam * 0.5));
	}

	if (color_softness_steps > 1.0) {
		base_col = floor(base_col * color_softness_steps + 0.5) / color_softness_steps;
	}

	// 3. Hand-sculpted clay surface grain (thumbprint ridges + soft macro lumpiness)
	vec2 clay_coord = (uv * screen_res) / (3.2 * texture_scale);
	float fp_ridges = fingerprint_pattern(clay_coord);
	float lump_wave = (value_noise(clay_coord * 0.12) - 0.5) + (value_noise(clay_coord * 0.35) - 0.5) * 0.5;

	float luma = dot(base_col, vec3(0.299, 0.587, 0.114));
	float midtone_mask = clamp(1.0 - abs(luma - 0.52) * 1.15, 0.3, 1.0);

	base_col += fp_ridges * fingerprint_strength * midtone_mask;
	base_col += lump_wave * clay_lumpiness * midtone_mask;

	// 4. Warm subsurface-scattering feel & gentle eye-comfort vignette
	vec3 final_col = adjust_saturation(base_col, saturation_boost) * subsurface_warmth;

	if (soft_vignette > 0.001) {
		vec2 centered = SCREEN_UV * 2.0 - 1.0;
		float vig = 1.0 - dot(centered, centered) * soft_vignette;
		final_col *= clamp(vig, 0.0, 1.0);
	}

	COLOR = vec4(clamp(final_col, 0.0, 1.0), 1.0);
}