#version 430
#include "../inc/hlsl_to_glsl.glsl"
#include "../inc/math_constants.hlsl"

#include "../inc/cie1931.glsl"
#include "../inc/ipt.hlsl"
#include "../inc/bezold_brucke.hlsl"
#include "../inc/bezold_brucke_brute_force.glsl"

layout(local_size_x = 64, local_size_y = 1) in;
layout(rg32f) uniform image1D output_image;

void main() {
    const int px = int(gl_GlobalInvocationID.x);

    const float theta = ((px + 0.5) / 256) * M_PI * 2.0;

    const float2 xy = float2(cos(theta), sin(theta)) + whiteD65;
    float3 XYZ = CIE_xyY_to_XYZ(float3(xy, 1.0));

    const float3 shifted_XYZ = BB_shift_brute_force_XYZ(XYZ, 1.0);
    const float2 shifted_xy = normalize(CIE_XYZ_to_xyY(shifted_XYZ).xy - whiteD65);

    imageStore(output_image, px, vec4(shifted_xy, 0.0, 0.0));
}
