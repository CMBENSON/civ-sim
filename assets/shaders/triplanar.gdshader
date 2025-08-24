shader_type spatial;
render_mode cull_back;

uniform float texture_scale : hint_range(0.1, 50.0) = 10.0;
uniform float blend_sharpness : hint_range(0.1, 5.0) = 1.5;

/// Colours for different elevation bands (you can tweak these in the material)
uniform vec3 low_color  : hint_color = vec3(0.36, 0.55, 0.22); // grass / plains
uniform vec3 mid_color  : hint_color = vec3(0.50, 0.40, 0.30); // dirt / rock
uniform vec3 high_color : hint_color = vec3(0.92, 0.92, 0.96); // snow / ice

// Compute weights for triplanar blending based on the normal
vec3 triplanar_weights(vec3 normal) {
    vec3 n = abs(normal);
    float sum = n.x + n.y + n.z;
    n /= sum;
    // Sharpen or soften the blend based on the blend_sharpness uniform
    n = pow(n, vec3(blend_sharpness));
    return n / (n.x + n.y + n.z);
}

void fragment() {
    // World position scaled down for height normalisation
    float height_norm = clamp((WORLD_POSITION.y + 10.0) / 100.0, 0.0, 1.0);

    // Compute base colour from height – blend low→mid→high bands
    vec3 base_col = mix(low_color, mid_color, smoothstep(0.15, 0.6, height_norm));
    base_col = mix(base_col, high_color, smoothstep(0.6, 0.9, height_norm));

    // Compute weights for triplanar blending
    vec3 weights = triplanar_weights(NORMAL);

    // Sample world positions along each axis (scaled for tiling if you add textures later)
    vec3 world_scaled = (WORLD_POSITION / texture_scale);

    // Optionally you can add detail textures here using TEXTURE() calls.
    // For now, we modulate the colour slightly based on slope to give variation.
    float slope_factor = 1.0 - dot(abs(NORMAL), vec3(0.0, 1.0, 0.0));
    base_col *= mix(vec3(0.8), vec3(1.2), slope_factor);

    ALBEDO = base_col;
    ROUGHNESS = 0.9;
}
