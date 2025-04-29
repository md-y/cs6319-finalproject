shader_type canvas_item;

uniform sampler2D input_texture: repeat_disable;

void fragment() {
	ivec2 pos = textureSize(input_texture, 0);
	pos.x = int(float(pos.x) * UV.x);
	pos.y = int(float(pos.y) * UV.y);
	vec4 data = texelFetch(input_texture, pos, 0);
	int encoded_color = int(data.a);
	float r = float((encoded_color >> 16) & 0xFF) / 255.0;
	float g = float((encoded_color >> 8) & 0xFF) / 255.0;
	float b = float(encoded_color & 0xFF) / 255.0;
	COLOR = vec4(r, g, b, 1.0);
}
