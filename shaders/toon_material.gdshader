shader_type spatial;
render_mode specular_disabled, ambient_light_disabled, diffuse_toon;

uniform float shade_steps : hint_range(2.0, 8.0, 1.0) = 4.0;
uniform float shade_sharpness : hint_range(0.1, 1.0, 0.1) = 0.8;
uniform float rim_strength : hint_range(0.0, 1.0, 0.05) = 0.3;
uniform vec4 rim_color : source_color = vec4(0.15, 0.15, 0.2, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.1, 0.05, 0.15, 1.0);

void fragment() {
	vec3 normal = normalize(NORMAL);
	vec3 view_dir = normalize(VIEW);
	vec3 light_dir = normalize(LIGHT);
	float n_dot_l = dot(normal, light_dir);
	float shade = floor(n_dot_l * shade_steps) / shade_steps;
	shade = mix(shade, round(shade), shade_sharpness);
	ALBEDO = ALBEDO * mix(shadow_color.rgb, vec3(1.0), shade);
	float rim = 1.0 - abs(dot(normal, view_dir));
	EMISSION = rim_color.rgb * pow(rim, 3.0) * rim_strength;
}
