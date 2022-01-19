#include "inc/prelude.glsl"

float3 compress_stimulus(ShaderInput shader_input) {
    return 1.0 - exp(-shader_input.stimulus);
}
