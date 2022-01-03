uniform sampler2D texture;
in vec2 uv;
out vec4 out_color;

void main() {
    out_color = textureLod(texture, uv, 0);
}
