shader_type canvas_item;
// Solid-color silhouette used by the "white tint" sprites of the evolution
// presentation (PokeRogue used setTintFill(0xFFFFFF) for the same effect).
//
// Godot canvas_item fragment() overwrites COLOR, which would drop the node's
// modulate alpha. Per the official CanvasItem shader semantics, capture the
// vertex COLOR (the CanvasItem modulate / self_modulate) in a varying and reuse
// its alpha in fragment(), so the script-driven fade in/out still works.
// The texture alpha is applied exactly once.
// https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html#color-and-texture
render_mode unshaded;

uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(fill_color.rgb, tex.a * fill_color.a * vertex_color.a);
}
