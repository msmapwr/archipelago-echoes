shader_type canvas_item;
global uniform float crt_effect_strength;
uniform vec2 screen_size = vec2(528.0, 440.0);
varying vec2 local_pixel;

void vertex() {
	local_pixel = VERTEX;
}

void fragment() {
	vec2 position = (local_pixel - screen_size * 0.5) / (min(screen_size.x, screen_size.y) * 0.435);
	float edge = smoothstep(0.65, 1.0, length(position));
	// Stationary phosphor grain; no synthetic blips, temporal flicker or RGB mask.
	float grain = fract(sin(dot(floor(local_pixel), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float strength = crt_effect_strength * (1.0 - smoothstep(1.0, 1.01, length(position)));
	COLOR.rgb *= 1.0 + (grain * 0.018 - edge * 0.055) * strength;
	COLOR.rgb += max(COLOR.rgb - vec3(0.55), vec3(0.0)) * 0.055 * strength;
}
