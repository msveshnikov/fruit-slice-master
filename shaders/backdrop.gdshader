shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
// Painted world backdrop: slight sway parallax, soft vignette, desaturate/darken a touch so 3D fruit pops,
// and an icy tint while the Freeze power-up is active.
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec2 sway = vec2(0.0);
uniform float freeze = 0.0;
uniform float dim = 0.86;

void fragment() {
	vec2 uv = UV * 0.985 + 0.0075 + sway;
	vec3 c = texture(tex, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 0.92) * dim;
	vec2 d = UV - 0.5;
	float v = 1.0 - smoothstep(0.35, 0.85, length(d * vec2(1.25, 1.0)));
	c *= mix(0.62, 1.0, v);
	vec3 ice = vec3(l * 0.7 + 0.15, l * 0.85 + 0.25, l * 1.0 + 0.35);
	c = mix(c, ice, freeze * 0.55);
	ALBEDO = c;
}
