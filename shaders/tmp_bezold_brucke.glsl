#include "inc/prelude.glsl"
#include "inc/cie1931.glsl"
#include "inc/ipt.hlsl"
#include "inc/bezold_brucke.hlsl"

// Bezold–Brucke shift loosely based on
// "Pridmore, R. W. (1999). Bezold–Brucke hue-shift as functions of luminance level,
// luminance ratio, interstimulus interval and adapting white for aperture and object colors.
// Vision Research, 39(23), 3873–3891. doi:10.1016/s0042-6989(99)00085-1"

// Returns a lerp factor over p2 and p3 or -1 on miss
float intersect_line_segment(vec2 p0, vec2 dir, vec2 p2, vec2 p3) 
{
    vec2 P = p2;
    vec2 R = p3 - p2;  
    vec2 Q = p0;
    vec2 S = dir;

    vec2 N = vec2(S.y, -S.x);
    float t = dot(Q-P, N) / dot(R, N);

    if (t == clamp(t, 0.0, 1.0) && dot(dir, p2 - p0) >= 0.0) {
        return t;
    } else {
        return -1.0;
    }
}

vec3 wavelength_to_xyY( float fWavelength )
{
    float fPos = ( fWavelength - standardObserver1931_w_min ) / (standardObserver1931_w_max - standardObserver1931_w_min);
    float fIndex = fPos * float(standardObserver1931_length - 1);
    float fFloorIndex = floor(fIndex);
    float fBlend = clamp( fIndex - fFloorIndex, 0.0, 1.0 );
    int iIndex0 = int(fFloorIndex);
    int iIndex1 = iIndex0 + 1;
    iIndex1 = min( iIndex1, standardObserver1931_length - 1);
    return mix( CIE_XYZ_to_xyY(standardObserver1931[iIndex0]), CIE_XYZ_to_xyY(standardObserver1931[iIndex1]), fBlend );
}

float xy_to_dominant_wavelength(vec2 xy) {
    vec2 white = whiteD65;
    vec2 dir = xy - white;

    for (int i = 0; i + 1 < standardObserver1931_length; ++i) {
    //for (int i = standardObserver1931_length - 2; i >= 0; --i) {
        vec2 locus_xy0 = CIE_XYZ_to_xyY(standardObserver1931[i]).xy;
        vec2 locus_xy1 = CIE_XYZ_to_xyY(standardObserver1931[i + 1]).xy;

        float hit = intersect_line_segment(white, dir, locus_xy0, locus_xy1);
        if (hit != -1.0) {
            return standardObserver1931_w_min
                + (standardObserver1931_w_max - standardObserver1931_w_min) / float(standardObserver1931_length - 1)
                * (float(i) + hit);
        }
    }

    return -1.0;
}

vec2 intersect_gamut(vec2 xy) {
    vec2 white = whiteD65;
    vec2 dir = xy - white;

    for (int i = 0; i + 1 < standardObserver1931_length; ++i) {
        vec2 locus_xy0 = CIE_XYZ_to_xyY(standardObserver1931[i]).xy;
        vec2 locus_xy1 = CIE_XYZ_to_xyY(standardObserver1931[i + 1]).xy;

        float hit = intersect_line_segment(white, dir, locus_xy0, locus_xy1);
        if (hit != -1.0) {
            return locus_xy0 + (locus_xy1 - locus_xy0) * hit;
        }
    }

    return vec2(-1.0);
}

float XYZ_to_BB_shift_degrees(float3 XYZ) {
    vec2 white = whiteD65;
    #if 1
        vec3 ipt = xyz_to_ipt(XYZ);
        vec3 white_offset_ipt = ipt - xyz_to_ipt(CIE_xyY_to_XYZ(vec3(white, 1.0)));
        float theta = atan2(white_offset_ipt[2], white_offset_ipt[1]);
    #else
        vec2 white_offset = xyY.xy - white;
        float theta = atan2(white_offset[1], white_offset[0]);
    #endif

    //return (theta.xxx / M_PI) * 0.5 + 0.5;

    const float theta_nudge = 0.0
        + 0.4 * smoothstep(0.7, 0.0, abs(theta - 1.5)) * theta
        + 1.5 * smoothstep(1.0, 0.0, abs(theta - 0.5)) * theta
        - 1.4 * smoothstep(0.4, 0.0, abs(theta - 0.575)) * theta * theta
        ;

    return 6.0 * sin(theta_nudge + theta * 3 + 0.77) + 1.0;
}

vec3 compress_stimulus(ShaderInput shader_input) {
    float wavelength = lerp(standardObserver1931_w_min, standardObserver1931_w_max, shader_input.uv.x);
    //float wavelength = lerp(410, 650, shader_input.uv.x);    

    // nulls for the 10:100 cd/m^2 6500K case
    const float null_wavelengths[4] = float[4](481, 506, 578, 620);

    for (int i = 0; i < 4; ++i) {
        if (abs(wavelength - null_wavelengths[i]) < 0.25) {
            return 1.0.xxx;
        }
    }

    const float ordinate = (shader_input.uv.y * 2 - 1) * 10;     // -10 .. 10
    if (abs(ordinate) < 0.03) {
        return 0.0.xxx;
    }

    float3 xyY = wavelength_to_xyY(wavelength);
    float3 XYZ = CIE_xyY_to_XYZ(xyY);

    const float bb_shift = XYZ_to_BB_shift_degrees(XYZ);
    const float bb_shift_IPT_degrees = BB_XYZ_to_IPT_hue_rotation_degrees(XYZ);

    if (abs(ordinate - bb_shift) < 0.05) {
        return 0.0.xxx;
    }

    {
        vec2 white = whiteD65;
        vec3 white_ipt = xyz_to_ipt(CIE_xyY_to_XYZ(vec3(white, 1.0)));
        vec3 ipt = xyz_to_ipt(XYZ);
        vec3 white_offset_ipt = ipt - white_ipt;
        const float bb_shift_radians = -bb_shift_IPT_degrees * M_PI / 180.0;

        const mat2 hue_rot_matrix = mat2(cos(bb_shift_radians), sin(bb_shift_radians), -sin(bb_shift_radians), cos(bb_shift_radians));

#if 1
        white_offset_ipt.yz = mul(hue_rot_matrix, white_offset_ipt.yz);
        float3 shifted_XYZ = ipt_to_xyz(white_ipt + white_offset_ipt);
#else
        float3 shifted_xyY = xyY;
        shifted_xyY.xy = mul(hue_rot_matrix, shifted_xyY.xy - whiteD65) + whiteD65;
        float3 shifted_XYZ = CIE_xyY_to_XYZ(shifted_xyY);
#endif
        vec3 shifted_sRGB = shifted_XYZ * XYZtoRGB(Primaries_Rec709);

        float shifted_wavelength = xy_to_dominant_wavelength(CIE_XYZ_to_xyY(shifted_XYZ).xy);
        float wavelength_shift = shifted_wavelength - wavelength;

        if (abs(ordinate - wavelength_shift) < 0.05) {
            return 1.0.xxx;
        }

        if (shader_input.uv.y > 0.7)
        {
            return shifted_sRGB * 0.3;
        }
    }

    if (shader_input.uv.y > 0.3) {
        float3 xyY = wavelength_to_xyY(wavelength + bb_shift);
        XYZ = CIE_xyY_to_XYZ(xyY);
    } else {
        //XYZ *= 2.0;
    }

    vec3 sRGB = XYZ * XYZtoRGB(Primaries_Rec709);

    return sRGB * 0.3;
    //return abs(wavelength - wavelength1).xxx;
}
