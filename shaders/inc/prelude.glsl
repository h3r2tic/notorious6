#include "hlsl_to_glsl.glsl"

uniform sampler2D input_texture;
uniform float input_ev;
in vec2 input_uv;
out vec4 output_rgba;

#define M_PI 3.1415926535897932384626433832795
#define square(x) ((x) * (x))
