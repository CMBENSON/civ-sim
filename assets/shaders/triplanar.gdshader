shader_type spatial;

uniform sampler2D texture_atlas;
uniform float texture_scale = 0.1;

varying vec4 mod_color;

void vertex() {
	// Pass the vertex color from the mesh to the fragment shader
	mod_color = COLOR;
}

void fragment() {
	// --- FIX: This is the correct texturing logic ---

	// 1. Determine the correct texture coordinates for each biome
	// We are using a 2x4 texture atlas. The Y coordinate determines the texture type.
	// Grass (0.125), Dirt (0.375), Sand (0.625), Water (0.875)
	// Snow (0.125), Tundra Rock (0.375), Desert Rock (0.625), Mountain Rock (0.875)

	vec2 plains_uv = vec2(0.25, 0.125);
	vec2 tundra_uv = vec2(0.75, 0.125);
	vec2 desert_uv = vec2(0.25, 0.625);
	vec2 mountain_uv = vec2(0.75, 0.875);

	// 2. Select the final UV coordinate based on the vertex color from the mesh
	vec2 final_uv = plains_uv; // Default to plains
	if (mod_color.r > 0.5) { // Tundra uses the Red channel
		final_uv = tundra_uv;
	}
	if (mod_color.b > 0.5) { // Desert uses the Blue channel
		final_uv = desert_uv;
	}
	if (mod_color.a > 0.5) { // Mountains use the Alpha channel
		final_uv = mountain_uv;
	}

	// 3. Perform the triplanar mapping using the correct texture coordinates
	// We are effectively doing three lookups into the atlas based on world position
	vec3 blend_weights = abs(NORMAL);
	blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z);

	// We create a new UV for each direction by adding the world position to our base biome UV
	// This makes the texture tile correctly.
	vec4 x_texture = texture(texture_atlas, final_uv + VERTEX.yz * texture_scale);
	vec4 y_texture = texture(texture_atlas, final_uv + VERTEX.xz * texture_scale);
	vec4 z_texture = texture(texture_atlas, final_uv + VERTEX.xy * texture_scale);

	// 4. Blend the three textures together and set the final color
	vec4 blended_color = x_texture * blend_weights.x + y_texture * blend_weights.y + z_texture * blend_weights.z;
	
	ALBEDO = blended_color.rgb;
}