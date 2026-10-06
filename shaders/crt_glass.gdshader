shader_type canvas_item;

// Character CRT glass: restrained line structure and edge falloff.
// The radar PPI draws its own phosphor response and does not use an RGB mask.
uniform float line_strength : hint_range(0.0, 0.03) = 0.004;
uniform float edge_strength : hint_range(0.0, 0.2) = 0.08;

void fragment() {
	float line_structure = 0.5 + 0.5 * cos(UV.y * 636.0 * 6.2831853);
	vec2 centered = (UV - vec2(0.5)) * vec2(1.55, 1.15);
	float edge = smoothstep(0.44, 0.83, length(centered));
	float reflection = exp(-pow((UV.x + UV.y * 0.45 - 0.42) * 8.0, 2.0)) * 0.018;
	float alpha = line_structure * line_strength + edge * edge_strength + reflection;
	COLOR = vec4(0.04, 0.10, 0.07, alpha);
}
