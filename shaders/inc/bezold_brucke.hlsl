#include "xyz.hlsl"

float BB_XYZ_to_IPT_hue_rotation_degrees(float3 XYZ) {
    const float2 white = float2(.3127, 0.3290);   // D65

    #if 1
        float3 ipt = xyz_to_ipt(XYZ);
        float3 white_offset_ipt = ipt - xyz_to_ipt(CIE_xyY_to_XYZ(float3(white, 1.0)));
        float theta = atan2(white_offset_ipt[2], white_offset_ipt[1]);
    #else
        float2 white_offset = xyY.xy - white;
        float theta = atan2(white_offset[1], white_offset[0]);
    #endif

    const float theta_nudge = 0.0
        + 0.5 * smoothstep(0.7, 0.0, abs(theta - 1.5)) * theta
        + 1.8 * smoothstep(1.0, 0.0, abs(theta - 0.5)) * theta
        - 1.8 * smoothstep(0.4, 0.0, abs(theta - 0.5)) * theta
        ;

    const float green_dip = -6.0 * sin(theta + 1.9) / theta / theta * 5;
    const float blue_red_peak = -1 + 11.0 * min(10, sin(theta_nudge + theta * 3 + 0.9));
    const float window = smoothstep(0.65, 0.0, sin(theta + 2.06));

    //return green_dip;
    //return blue_red_peak * window;
    return
        lerp(blue_red_peak, green_dip, smoothstep(-0.7, -1, sin(theta + 2.4)))
        * window;
}

// Apply Bezold–Brucke shift to XYZ stimulus. Loosely based on
// "Pridmore, R. W. (1999). Bezold–Brucke hue-shift as functions of luminance level,
// luminance ratio, interstimulus interval and adapting white for aperture and object colors.
// Vision Research, 39(23), 3873–3891. doi:10.1016/s0042-6989(99)00085-1"
//
// Custom fit to rotation of IPT chroma.
float3 BB_shift_XYZ(float3 XYZ, float amount) {
    const float2 white = float2(.3127, 0.3290);   // D65

    const float bb_shift_IPT_degrees = BB_XYZ_to_IPT_hue_rotation_degrees(XYZ);

    float3 white_ipt = xyz_to_ipt(CIE_xyY_to_XYZ(float3(white, 1.0)));
    float3 ipt = xyz_to_ipt(XYZ);
    float3 white_offset_ipt = ipt - white_ipt;

    const float bb_shift_radians = amount * bb_shift_IPT_degrees * M_PI / 180.0;
    const float ca = cos(bb_shift_radians);
    const float sa = sin(bb_shift_radians);

    white_offset_ipt.yz = mul(float2x2(ca, sa, -sa, ca), white_offset_ipt.yz);
    return ipt_to_xyz(white_ipt + white_offset_ipt);
}

uniform sampler1D bezold_brucke_lut;
float3 BB_shift_lut_XYZ(float3 XYZ, float amount) {
    const float2 white = float2(.3127, 0.3290);   // D65

    const float3 xyY = CIE_XYZ_to_xyY(XYZ);
    const float2 offset = xyY.xy - white;
    const float theta = fract((atan2(offset.y, offset.x) / M_PI) * 0.5);
    const float2 shifted_xy = lerp(xyY.xy, textureLod(bezold_brucke_lut, theta, 0).xy * length(offset) + white, amount);
    return CIE_xyY_to_XYZ(float3(shifted_xy, xyY.z));
}
