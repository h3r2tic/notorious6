#version 430
#include "../inc/hlsl_to_glsl.glsl"
#include "../inc/math.hlsl"

#include "../inc/standard_observer.hlsl"
#include "../inc/ipt.hlsl"
#include "../inc/bezold_brucke.hlsl"

layout(local_size_x = 64, local_size_y = 1) in;
layout(rg32f) uniform image1D output_image;

void main() {
    const int px = int(gl_GlobalInvocationID.x);

    const float2 xy = bb_lut_coord_to_xy_white_offset((px + 0.5) / 64) + white_D65_xy;
    float3 XYZ = CIE_xyY_to_XYZ(float3(xy, 1.0));

    const float3 shifted_XYZ = bezold_brucke_shift_XYZ_brute_force(XYZ, 1.0);
    const float2 shifted_xy = normalize(CIE_XYZ_to_xyY(shifted_XYZ).xy - white_D65_xy) + white_D65_xy;

    imageStore(output_image, px, float4(shifted_xy - xy, 0.0, 0.0));
}
