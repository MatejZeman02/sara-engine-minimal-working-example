shader_type canvas_item;

uniform vec2 canvas_size;
uniform float checker_size = 16.0;
uniform vec4 color_1 : source_color = vec4(0.4, 0.4, 0.4, 1.0);
uniform vec4 color_2 : source_color = vec4(0.6, 0.6, 0.6, 1.0);

void fragment() {
    vec2 pos = UV * canvas_size;
    vec2 grid = floor(pos / checker_size);
    float checker = mod(grid.x + grid.y, 2.0);
    COLOR = mix(color_1, color_2, checker);
}
