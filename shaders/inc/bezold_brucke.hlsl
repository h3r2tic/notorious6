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

// Assigns uniform angles to hue in CIE 1931, however that doesn't mean much.
#define BB_LUT_LUT_MAPPING_ANGULAR 0

// Probably the best bang/buck.
#define BB_LUT_LUT_MAPPING_QUAD 1

// Not really an improvement.
#define BB_LUT_LUT_MAPPING_ROTATED_QUAD 2
#define BB_LUT_LUT_MAPPING_ROTATED_QUAD_ANGLE 0.8595

// Select the encoding method
#define BB_LUT_LUT_MAPPING BB_LUT_LUT_MAPPING_QUAD


float bb_xy_white_offset_to_lut_coord(float2 offset) {
    #if BB_LUT_LUT_MAPPING == BB_LUT_LUT_MAPPING_ANGULAR
        return fract((atan2(offset.y, offset.x) / M_PI) * 0.5);
    #elif BB_LUT_LUT_MAPPING == BB_LUT_LUT_MAPPING_QUAD
        offset /= max(abs(offset.x), abs(offset.y));
        float sgn = (offset.x + offset.y) > 0.0 ? 1.0 : -1.0;
        // NOTE: needs a `frac` if the sampler's U wrap mode is not REPEAT.
        return sgn * (0.125 * (offset.x - offset.y) + 0.25);
    #elif BB_LUT_LUT_MAPPING == BB_LUT_LUT_MAPPING_ROTATED_QUAD
        const float angle = BB_LUT_LUT_MAPPING_ROTATED_QUAD_ANGLE;
        offset = mul(float2x2(cos(angle), sin(angle), -sin(angle), cos(angle)), offset);
        offset /= max(abs(offset.x), abs(offset.y));
        float sgn = (offset.x + offset.y) > 0.0 ? 1.0 : -1.0;
        // NOTE: needs a `frac` if the sampler's U wrap mode is not REPEAT.
        return sgn * (0.125 * (offset.x - offset.y) + 0.25);
    #endif
}

float2 bb_lut_coord_to_xy_white_offset(float coord) {
    #if BB_LUT_LUT_MAPPING == BB_LUT_LUT_MAPPING_ANGULAR
        const float theta = coord * M_PI * 2.0;
        return float2(cos(theta), sin(theta));
    #elif BB_LUT_LUT_MAPPING == BB_LUT_LUT_MAPPING_QUAD
        float side = (coord < 0.5 ? 1.0 : -1.0);
        float t = frac(coord * 2);
        return side * normalize(
            lerp(float2(-1, 1), float2(1, -1), t)
            + lerp(float2(0, 0), float2(1, 1), 1 - abs(t - 0.5) * 2)
        );
    #elif BB_LUT_LUT_MAPPING == BB_LUT_LUT_MAPPING_ROTATED_QUAD
        float side = (coord < 0.5 ? 1.0 : -1.0);
        float t = frac(coord * 2);
        float2 offset = side * normalize(lerp(float2(-1, 1), float2(1, -1), t) + lerp(float2(0, 0), float2(1, 1), 1 - abs(t - 0.5) * 2));
        const float angle = BB_LUT_LUT_MAPPING_ROTATED_QUAD_ANGLE;
        return mul(offset, float2x2(cos(angle), sin(angle), -sin(angle), cos(angle)));
    #endif
}

uniform sampler1D bezold_brucke_lut;
float3 BB_shift_lut_XYZ(float3 XYZ, float amount) {
    const float2 white = float2(.3127, 0.3290);   // D65

    const float3 xyY = CIE_XYZ_to_xyY(XYZ);
    const float2 offset = xyY.xy - white;

    const float lut_coord = bb_xy_white_offset_to_lut_coord(offset);

    const float2 shifted_xy = xyY.xy + textureLod(bezold_brucke_lut, lut_coord, 0).xy * length(offset) * amount;
    return CIE_xyY_to_XYZ(float3(shifted_xy, xyY.z));
}
