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

    const float2 xy = bb_lut_coord_to_xy_white_offset((px + 0.5) / 64) + whiteD65;
    float3 XYZ = CIE_xyY_to_XYZ(float3(xy, 1.0));

    const float3 shifted_XYZ = BB_shift_brute_force_XYZ(XYZ, 1.0);
    const float2 shifted_xy = normalize(CIE_XYZ_to_xyY(shifted_XYZ).xy - whiteD65) + whiteD65;

    imageStore(output_image, px, vec4(shifted_xy - xy, 0.0, 0.0));
}
