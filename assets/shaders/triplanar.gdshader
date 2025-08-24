shader_type spatial;
render_mode cull_back;

uniform float texture_scale  : hint_range(0.1, 50.0) = 10.0;
uniform float blend_sharpness : hint_range(0.1, 5.0)  = 1.5;

/// Colours for different elevation bands (adjust as needed)
uniform vec3 low_color  = vec3(0.36, 0.55, 0.22); // grass / plains
uniform vec3 mid_color  = vec3(0.50, 0.40, 0.30); // dirt / rock
uniform vec3 high_color = vec3(0.92, 0.92, 0.96); // snow / ice

// Compute weights for triplanar blending based on the surface normal
vec3 triplanar_weights(vec3 normal) {
    vec3 n = abs(normal);
    float sum = n.x + n.y + n.z;
    n /= sum;
    n = pow(n, vec3(blend_sharpness));
    return n / (n.x + n.y + n.z);
}

void fragment() {
    // Use the local vertex height as a proxy for world height.
    float height_norm = clamp((VERTEX.y + 10.0) / 100.0, 0.0, 1.0);

    // Blend the colours based on height: low→mid→high bands
    vec3 base_col = mix(low_color, mid_color, smoothstep(0.15, 0.6, height_norm));
    base_col = mix(base_col, high_color, smoothstep(0.6, 0.9, height_norm));

    // Compute triplanar weights (unused here, available for future texturing)
    vec3 weights = triplanar_weights(NORMAL);

    // Modulate colour by slope to add variation (flatter surfaces appear darker)
    float slope_factor = 1.0 - dot(abs(NORMAL), vec3(0.0, 1.0, 0.0));
    base_col *= mix(vec3(0.8), vec3(1.2), slope_factor);

    ALBEDO    = base_col;
    ROUGHNESS = 0.9;
}
