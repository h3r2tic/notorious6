#include "inc/prelude.glsl"

void main() {
    out_color = textureLod(texture, uv, 0);
}
