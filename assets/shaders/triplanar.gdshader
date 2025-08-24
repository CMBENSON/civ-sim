shader_type spatial;

uniform sampler2D texture_atlas;
// --- FIX: Removed detail_texture and texture_scale uniforms ---
uniform float blend_sharpness : hint_range(0.0, 10.0) = 2.0; 

varying vec4 mod_color;

void vertex() {
	mod_color = COLOR;
}

void fragment() {
	// 1. Determine the correct biome colors from our procedural atlas
	vec4 plains_top_color = texture(texture_atlas, vec2(0.25, 0.125));      // Grass
	vec4 plains_side_color = texture(texture_atlas, vec2(0.25, 0.375));     // Dirt
	vec4 tundra_top_color = texture(texture_atlas, vec2(0.75, 0.125));      // Snow
	vec4 tundra_side_color = texture(texture_atlas, vec2(0.75, 0.375));     // Tundra Rock
	vec4 desert_top_color = texture(texture_atlas, vec2(0.25, 0.625));      // Sand
	vec4 desert_side_color = texture(texture_atlas, vec2(0.75, 0.625));     // Desert Rock
	vec4 mountain_top_color = texture(texture_atlas, vec2(0.75, 0.875));   // Mountain Rock
	vec4 mountain_side_color = texture(texture_atlas, vec2(0.75, 0.875));  // Mountain Rock

	// 2. Select the correct pair of colors based on the vertex color from the mesh
	vec4 top_color = plains_top_color;
	vec4 side_color = plains_side_color;

	if (mod_color.r > 0.5) { // Tundra
		top_color = tundra_top_color;
		side_color = tundra_side_color;
	} else if (mod_color.b > 0.5) { // Desert
		top_color = desert_top_color;
		side_color = desert_side_color;
	} else if (mod_color.a > 0.5) { // Mountain
		top_color = mountain_top_color;
		side_color = mountain_side_color;
	}
	
	// 3. Blend between the top and side colors based on the surface normal
	float blend_factor = pow(NORMAL.y, blend_sharpness);
	vec4 final_color = mix(side_color, top_color, blend_factor);
	
	// --- FIX: We now directly output the blended solid color ---
	ALBEDO = final_color.rgb;
}