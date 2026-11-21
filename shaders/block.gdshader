shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2DArray tex : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;

void fragment() {
	vec2 uv = UV;
	if (UV2.y > 0.5) {
		uv += vec2(TIME * 0.04, sin(TIME * 0.6 + UV.y * 3.0) * 0.05);
	}
	vec4 c = texture(tex, vec3(uv, UV2.x));
	ALBEDO = c.rgb * COLOR.r;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	AO = COLOR.g;
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	EMISSION = c.rgb * COLOR.b * 2.2;
}
