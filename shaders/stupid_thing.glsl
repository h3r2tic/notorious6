#include "inc/prelude.glsl"
#include "inc/display_transform.hlsl"

float3 compress_stimulus(ShaderInput shader_input) {
    return sRGB_display_transform(shader_input.stimulus);
}
