#include "catmull_rom.hlsl"

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
    const vec2 white = whiteD65;
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

float XYZ_to_BB_shift_nm(vec3 XYZ) {
    const vec2 white = whiteD65;
    vec3 ipt = xyz_to_ipt(XYZ);
    vec3 white_offset_ipt = ipt - xyz_to_ipt(CIE_xyY_to_XYZ(vec3(white, 1.0)));
    float theta = atan2(white_offset_ipt[2], white_offset_ipt[1]);

    // Piece-wise linear match to Pridmore's plot for 10:100 cd/m^2
    const uint SAMPLE_COUNT = 24;
    vec2 samples[] = {
        vec2(0.0, 0),
        vec2(0.05, -5.0),
        vec2(0.09, -5.0),
        vec2(0.122, -4.0),
        vec2(0.158, 0.0),
        vec2(0.175, 2.3),
        vec2(0.207, 5),
        vec2(0.23, 6),
        vec2(0.25, 6.5),
        vec2(0.3, 4.4),
        vec2(0.332, 3.93),
        vec2(0.42, -4.9),
        vec2(0.463, -6),
        vec2(0.4915, -6),
        vec2(0.5125, 1.42),
        vec2(0.517, 1.9),
        vec2(0.53, 2.55),
        // non-spectrals
        vec2(0.867, 2.55),
        vec2(0.87, 3.35),
        vec2(0.88, 4.8),
        vec2(0.895, 6.15),
        vec2(0.912, 7),
        vec2(0.935, 5.95),
        vec2(0.957, 4.0),
    };

    const float t = fract((-theta / M_PI) * 0.5 + 0.62);

    for (int i = 0; i < SAMPLE_COUNT; ++i) {
        vec2 p0 = samples[i];
        vec2 p1 = samples[(i + 1) % SAMPLE_COUNT];
        float interp = (t - p0.x) / fract(p1.x - p0.x + 1);
        if (t >= p0.x && interp <= 1.0) {
            return lerp(p0.y, p1.y, interp);
        }
    }

    return 0.0;
}

vec3 BB_shift_brute_force_XYZ(vec3 XYZ, float amount) {
    const vec3 xyY = CIE_XYZ_to_xyY(XYZ);
    const float white_offset_magnitude = length(xyY.xy - whiteD65);
    const float bb_shift = XYZ_to_BB_shift_nm(XYZ);

    const float dominant_wavelength = xy_to_dominant_wavelength(xyY.xy);
    if (dominant_wavelength == -1) {
        // Non-spectral stimulus.
        // We could calculate the shift for the two corner vertices of the gamut,
        // then interpolate the shift between them, however the wavelengths
        // get so compressed in the xyY space near limits of vision, that
        // the shift is effectively nullified.
        return XYZ;
    }

    vec3 shifted_xyY = wavelength_to_xyY(dominant_wavelength + bb_shift * amount);
    vec3 adjutsed_xyY =
        vec3(whiteD65 + (shifted_xyY.xy - whiteD65) * white_offset_magnitude / max(1e-10, length((shifted_xyY.xy - whiteD65))), xyY.z);
    return CIE_xyY_to_XYZ(adjutsed_xyY);
}
