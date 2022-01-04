#include "inc/prelude.glsl"

vec3 compress_stimulus(vec3 stimulus) {
    return 1.0 - exp(-stimulus);
}
