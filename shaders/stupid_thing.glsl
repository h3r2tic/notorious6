#include "inc/prelude.glsl"
#include "inc/display_transform.hlsl"

float3 compress_stimulus(ShaderInput shader_input) {
    return display_transform_sRGB(shader_input.stimulus);
}
