#include "hlsl_to_glsl.glsl"

uniform sampler2D input_texture;
uniform float input_ev;
in vec2 input_uv;
out vec4 output_rgba;

#define M_PI 3.1415926535897932384626433832795
#define square(x) ((x) * (x))

struct ShaderInput {
    float3 stimulus;
    float2 uv;
};

ShaderInput prepare_shader_input() {
    ShaderInput input;
    input.stimulus = exp2(input_ev) * max(0.0.xxx, textureLod(input_texture, input_uv, 0).rgb);
    input.uv = input_uv;
    return input;
}

#define SHADER_MAIN_FN output_rgba = vec4(compress_stimulus(prepare_shader_input()), 1.0);
