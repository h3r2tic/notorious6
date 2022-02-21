#include "xyz.hlsl"

float BB_XYZ_to_IPT_hue_rotation_degrees(float3 XYZ) {
    const vec2 white = vec2(.3127, 0.3290);   // D65

    #if 1
        vec3 ipt = xyz_to_ipt(XYZ);
        vec3 white_offset_ipt = ipt - xyz_to_ipt(CIE_xyY_to_XYZ(vec3(white, 1.0)));
        float theta = atan2(white_offset_ipt[2], white_offset_ipt[1]);
    #else
        vec2 white_offset = xyY.xy - white;
        float theta = atan2(white_offset[1], white_offset[0]);
    #endif

    const float theta_nudge = 0.0
        + 0.5 * smoothstep(0.7, 0.0, abs(theta - 1.5)) * theta
        + 1.8 * smoothstep(1.0, 0.0, abs(theta - 0.5)) * theta
        - 1.8 * smoothstep(0.4, 0.0, abs(theta - 0.575)) * theta * theta
        ;

    const float green_dip = -7.0 * sin(theta + 1.9) / theta / theta * 5;
    const float blue_red_peak = 10.0 * min(10, sin(theta_nudge + theta * 3 + 0.77));
    const float window = smoothstep(0.7, 0.0, sin(theta + 2.09));

    //return green_dip;
    //return blue_red_peak * window;
    return
        mix(blue_red_peak, green_dip, smoothstep(-0.6, -1, sin(theta + 2.4)))
        * window;
}

// Apply Bezold–Brucke shift to XYZ stimulus. Loosely based on
// "Pridmore, R. W. (1999). Bezold–Brucke hue-shift as functions of luminance level,
// luminance ratio, interstimulus interval and adapting white for aperture and object colors.
// Vision Research, 39(23), 3873–3891. doi:10.1016/s0042-6989(99)00085-1"
//
// Custom fit to rotation of IPT chroma.
float3 BB_shift_XYZ(float3 XYZ, float amount) {
    const vec2 white = vec2(.3127, 0.3290);   // D65

    const float bb_shift_IPT_degrees = BB_XYZ_to_IPT_hue_rotation_degrees(XYZ);

    vec3 white_ipt = xyz_to_ipt(CIE_xyY_to_XYZ(vec3(white, 1.0)));
    vec3 ipt = xyz_to_ipt(XYZ);
    vec3 white_offset_ipt = ipt - white_ipt;

    const float bb_shift_radians = amount * -bb_shift_IPT_degrees * M_PI / 180.0;
    const mat2 hue_rot_matrix = mat2(cos(bb_shift_radians), sin(bb_shift_radians), -sin(bb_shift_radians), cos(bb_shift_radians));

    white_offset_ipt.yz = mul(hue_rot_matrix, white_offset_ipt.yz);
    return ipt_to_xyz(white_ipt + white_offset_ipt);
}
