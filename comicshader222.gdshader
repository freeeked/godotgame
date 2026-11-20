shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform float miniature_tilt_shift : hint_range(0.0, 2.2, 0.1) = 0.75; // Soft tabletop diorama depth at top/bottom
uniform float saturation_boost : hint_range(0.8, 1.3, 0.02) = 1.08;
uniform vec3 warm_studio_light : source_color = vec3(1.02, 0.99, 0.96);
uniform float soft_vignette : hint_range(0.0, 0.3, 0.02) = 0.08;

void fragment() {
	vec2 uv = SCREEN_UV;

	// Subtle miniature macro-lens blur only at the very top and bottom edges
	float dist_y = abs(uv.y - 0.52);
	float blur_lod = smoothstep(0.30, 0.50, dist_y) * miniature_tilt_shift;
	vec3 col = textureLod(screen_texture, uv, blur_lod).rgb;

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation_boost) * warm_studio_light;

	if (soft_vignette > 0.001) {
		vec2 centered = uv * 2.0 - 1.0;
		col *= clamp(1.0 - dot(centered, centered) * soft_vignette, 0.0, 1.0);
	}

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}