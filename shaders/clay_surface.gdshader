shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.2, 1.0) = 0.62;
uniform float subsurface_wrap : hint_range(0.0, 0.6) = 0.28; // Soft creamy light wrap like polymer clay

group_uniforms SculptedClaySurface;
uniform float world_tex_scale : hint_range(0.2, 4.0) = 1.15;
uniform float fingerprint_bump : hint_range(0.0, 1.0) = 0.32;
uniform float lumpiness_bump : hint_range(0.0, 1.0) = 0.25;

group_uniforms StopMotionLife;
uniform float stop_motion_fps : hint_range(0.0, 24.0, 1.0) = 10.0; // 10-12 FPS gives authentic claymation "boil" (0 = off)
uniform float boil_wobble_amount : hint_range(0.0, 0.04, 0.002) = 0.012;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(
			mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x),
			mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x),
			f.y
		),
		mix(
			mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x),
			mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x),
			f.y
		),
		f.z
	);
}

// 3D swirled thumbprint + hand-pressed dimple height field in world space
float clay_height(vec3 pos, float step_time) {
	vec3 p = pos * world_tex_scale + vec3(step_time * 0.37, step_time * 0.19, step_time * 0.53);
	float lump = noise3d(p * 1.4) * lumpiness_bump;

	vec3 swirl = p * 5.5 + vec3(noise3d(p * 2.2)) * 2.6;
	float ridges = sin(swirl.x * 3.14159 + sin(swirl.y * 2.5 + swirl.z * 2.1));
	float patch_mask = smoothstep(0.35, 0.72, noise3d(p * 1.8 + vec3(4.2)));

	return lump + ridges * patch_mask * fingerprint_bump * 0.25;
}

void vertex() {
	vec3 world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float step_t = (stop_motion_fps > 0.5) ? floor(TIME * stop_motion_fps) : 0.0;

	// Subtle hand-molded vertex boil so static blocks and blobs feel alive
	if (boil_wobble_amount > 0.0001) {
		float w = noise3d(world_p * 2.8 + vec3(step_t * 1.7)) - 0.5;
		VERTEX += NORMAL * (w * boil_wobble_amount);
	}

	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float step_t = (stop_motion_fps > 0.5) ? floor(TIME * stop_motion_fps) : 0.0;

	// Perturb the 3D surface normal using world-space clay height derivatives
	float eps = 0.035;
	float h0 = clay_height(v_world_pos, step_t);
	vec3 grad = vec3(
		clay_height(v_world_pos + vec3(eps, 0.0, 0.0), step_t) - h0,
		clay_height(v_world_pos + vec3(0.0, eps, 0.0), step_t) - h0,
		clay_height(v_world_pos + vec3(0.0, 0.0, eps), step_t) - h0
	) / eps;

	vec3 world_n = normalize(v_world_normal - grad * 0.22);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);

	// Slight tonal variation inside pressed clay dimples
	ALBEDO = albedo_color.rgb * (1.0 + (h0 - 0.12) * 0.18);
	ROUGHNESS = clamp(roughness - h0 * 0.15, 0.25, 0.95);
	SPECULAR = 0.42;
}

void light() {
	// Wrap diffuse lighting softens harsh polygon corners like real polymer clay
	float raw_ndotl = dot(NORMAL, LIGHT);
	float wrapped_ndotl = clamp((raw_ndotl + subsurface_wrap) / (1.0 + subsurface_wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * wrapped_ndotl * ATTENUATION;

	// Soft clay sheen highlight
	vec3 half_vec = normalize(VIEW + LIGHT);
	float spec = pow(max(dot(NORMAL, half_vec), 0.0), mix(48.0, 10.0, ROUGHNESS));
	SPECULAR_LIGHT += LIGHT_COLOR * spec * 0.28 * ATTENUATION;
}