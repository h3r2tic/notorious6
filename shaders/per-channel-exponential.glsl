#include "inc/prelude.glsl"

float3 compress_stimulus(ShaderInput input) {
    return 1.0 - exp(-input.stimulus);
}
