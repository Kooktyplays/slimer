shader_type canvas_item;
// The frozen frame behind an ultimate's cutscene: drained of colour, washed in
// the class's tint, vignetted, and flashed white on the hit.

uniform float desaturate : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform float darken : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(g), desaturate);
	c = mix(c, vec3(g) * tint.rgb * 1.5, tint_amount);
	vec2 d = (UV - 0.5) * vec2(1.6, 1.0);
	c *= 1.0 - smoothstep(0.30, 0.95, length(d)) * vignette;
	c *= 1.0 - darken;
	c = mix(c, vec3(1.0), flash);
	COLOR = vec4(c, 1.0);
}
