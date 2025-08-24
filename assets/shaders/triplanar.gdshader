// res://assets/shaders/triplanar.gdshader
shader_type spatial;

uniform sampler2D texture_atlas;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 vertex_color;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((inverse(transpose(MODEL_MATRIX)) * vec4(NORMAL, 0.0)).xyz);
	vertex_color = COLOR;
}

void fragment() {
	vec2 grass_uv = vec2(0.25, 0.125);
	vec2 dirt_uv = vec2(0.25, 0.375);
	vec2 sand_uv = vec2(0.25, 0.625);
	vec2 water_uv = vec2(0.25, 0.875);
	vec2 snow_uv = vec2(0.75, 0.125);
	vec2 tundra_rock_uv = vec2(0.75, 0.375);
	vec2 desert_rock_uv = vec2(0.75, 0.625);
	vec2 mountain_rock_uv = vec2(0.75, 0.875);

	vec2 top_tex_uv;
	vec2 side_tex_uv;

	// --- THIS IS THE FINAL, CORRECTED BIOME LOGIC ---
	// We now check for the specific "Mountain" color signature (black with alpha).
	if (vertex_color.a > 0.5 && vertex_color.r < 0.1 && vertex_color.g < 0.1 && vertex_color.b < 0.1) {
		side_tex_uv = mountain_rock_uv;
		float snow_blend = smoothstep(50.0, 58.0, world_pos.y);
		top_tex_uv = mix(mountain_rock_uv, snow_uv, snow_blend);

	} else if (vertex_color.r > 0.5) { // Tundra (Red channel)
		top_tex_uv = snow_uv;
		side_tex_uv = tundra_rock_uv;

	} else if (vertex_color.b > 0.5) { // Desert (Blue channel)
		top_tex_uv = sand_uv;
		side_tex_uv = desert_rock_uv;

	} else { // Default to Plains (Green channel is dominant)
		top_tex_uv = grass_uv;
		side_tex_uv = dirt_uv;
	}

	// --- Overrides for Beaches and Water ---
	if (world_pos.y < 30.0) {
		top_tex_uv = sand_uv;
		side_tex_uv = sand_uv;
	}
	if (world_pos.y < 28.0) {
		top_tex_uv = water_uv;
		side_tex_uv = water_uv;
	}

	// --- Final Blending Logic ---
	vec3 top_color = texture(texture_atlas, top_tex_uv).rgb;
	vec3 side_color = texture(texture_atlas, side_tex_uv).rgb;

	float slope_blend = smoothstep(0.5, 0.8, world_normal.y);
	ALBEDO = mix(side_color, top_color, slope_blend);
}