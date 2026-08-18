shader_type canvas_item;
render_mode unshaded;

// Hit flash. Lerps the sprite towards a flat colour without touching alpha,
// which `modulate` cannot do - modulate multiplies, so it can only ever
// darken or tint, never blow a sprite to white.

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.rgb = mix(c.rgb, flash_color.rgb, flash);
	COLOR = c * COLOR;
}
