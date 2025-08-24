shader_type spatial;

uniform sampler2D texture_atlas;
uniform float blend_sharpness : hint_range(0.0, 10.0) = 2.0;

varying vec4 mod_color;

void vertex() {
	mod_color = COLOR;
}

void fragment() {
	// Use the vertex color directly from the VoxelMesher for biome colors
	vec4 biome_color = mod_color;

	// Apply basic lighting for depth perception, but keep colors stable
	float light_factor = max(0.4, dot(NORMAL, vec3(0.0, 1.0, 0.0)));

	// Use the biome color directly with minimal lighting variation
	vec3 final_color = biome_color.rgb * light_factor;

	// Clamp to valid color range
	final_color = clamp(final_color, 0.0, 1.0);

	ALBEDO = final_color;
}