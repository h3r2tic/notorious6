#version 430
#include "hlsl_to_glsl.glsl"
#include "math_constants.hlsl"

uniform sampler2D input_texture;
uniform float input_ev;
in vec2 input_uv;
out vec4 output_rgba;

struct ShaderInput {
    float3 stimulus;
    float2 uv;
};

ShaderInput prepare_shader_input() {
    ShaderInput shader_input;
    shader_input.stimulus = exp2(input_ev) * max(0.0.xxx, textureLod(input_texture, input_uv, 0).rgb);
    shader_input.uv = input_uv;
    return shader_input;
}

#define SHADER_MAIN_FN output_rgba = vec4(compress_stimulus(prepare_shader_input()), 1.0);
