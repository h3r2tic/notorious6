#include "inc/prelude.glsl"
#include "inc/ictcp.hlsl"
#include "inc/luv.hlsl"
#include "inc/lms.hlsl"
#include "inc/oklab.hlsl"
#include "inc/h-k.hlsl"
#include "inc/ycbcr.hlsl"

// The space to perform chroma attenuation in. More details in the `compress_stimulus` function.
// Oklab works best, with ICtCp being a close second.
// LUV and None don't provide Abney correction.
#define PERCEPTUAL_SPACE_OKLAB 0
#define PERCEPTUAL_SPACE_LUV 1
#define PERCEPTUAL_SPACE_ICTCP 2
#define PERCEPTUAL_SPACE_NONE 4


// ----------------------------------------------------------------
// Configurable stuff:

// Choose the perceptual space for chroma attenuation.
#define PERCEPTUAL_SPACE PERCEPTUAL_SPACE_OKLAB

// if 1, the gamut will be trimmed at the "notorious 6" corners.
// if 0, the whole gamut is used.
#define TRIM_GAMUT_CORNERS 1
#define GAMUT_CORNER_CUT_RADII float3(0.25, 0.25, 0.25)

// Attenuate chroma based on brightness. Very ad-hoc.
// Should probably be part of a look, and not applied here.
#define USE_BRIGTHNESS_DEPENDENT_DESATURATION 0 // 0 or 1
#define BRIGTHNESS_DEPENDENT_DESATURATION_SCALE 1.0 // 0..
#define BRIGTHNESS_DEPENDENT_DESATURATION_START 0.0 // 0..1
#define BRIGTHNESS_DEPENDENT_DESATURATION_EXPONENT 2.0  // 1..
// ----------------------------------------------------------------


// Based on the selection, define `linear_to_perceptual` and `perceptual_to_linear`
#if PERCEPTUAL_SPACE == PERCEPTUAL_SPACE_OKLAB
	#define linear_to_perceptual(col) linear_srgb_to_oklab(col)
	#define perceptual_to_linear(col) oklab_to_linear_srgb(col)
#elif PERCEPTUAL_SPACE == PERCEPTUAL_SPACE_LUV
	#define linear_to_perceptual(col) xyzToLuv(RGBToXYZ(col))
	#define perceptual_to_linear(col) XYZtoRGB(luvToXyz(col))
#elif PERCEPTUAL_SPACE == PERCEPTUAL_SPACE_ICTCP
	#define linear_to_perceptual(col) LinearBT709_to_ICtCp(col)
	#define perceptual_to_linear(col) ICtCp_to_LinearBT709(col)
#elif PERCEPTUAL_SPACE == PERCEPTUAL_SPACE_NONE
	#define linear_to_perceptual(col) (col)
	#define perceptual_to_linear(col) (col)
#endif

float compress_brightness(float v) {
	#if 0
        // Approximately match mid-tones of Reinhard
        v *= 1.3;

		// Siragusano
		float n = 100;
		float n_r = 100;
		float g = 1.2;
		float w = 1;
		float t = 0.01;	// toe
		float m = n / n_r;
		float s_1 = w * pow(max(0.0, m), 1.0 / g);
		float fx = pow(max(0.0, v / (v + s_1)), g) * m;
		return max(0.0, fx * fx / (fx + t));
	#elif 1
		// Reinhard
		return v / (v + 1.0);
    #else
		// Classic exponential
        return 1.0 - exp(-v);
    #endif
}

float srgb_to_luminance(float3 col) {
    return rgb_to_ycbcr(col).x;
}

// Stimulus-linear luminance adjusted by the Helmholtz-Kohlrausch effect
float srgb_to_hk_adjusted_luminance(float3 input) {
    float3 xyz = RGBToXYZ(input);
    float3 lab = XYZToLab(xyz);
    float3 lch = LabToLch(lab);
    
    float L = CalculateFairchildPirrottaLightness(lch);

	return LABToXYZ(float3(L, 0, 0)).y;
}

// A square with the (1, 0) and (0, 1) corners circularly trimmed.
bool is_inside_2d_gamut_slice(float2 pos, float corner_radius) {
	float2 closest = clamp(pos, float2(0, corner_radius), float2(1-corner_radius, 1));
	float2 offset = pos - closest;
	return dot(offset, offset) <= corner_radius * corner_radius * 1.0001;
}

bool is_inside_target_gamut(float3 pos) {
	const float3 rgb_corner_radii = GAMUT_CORNER_CUT_RADII;

	return true
#if TRIM_GAMUT_CORNERS
        // Trim red except where green is high or blue is high
		&& (is_inside_2d_gamut_slice(pos.rg, rgb_corner_radii.r) && is_inside_2d_gamut_slice(pos.rb, rgb_corner_radii.r))
        // Trim green except where red is high or blue is high
		&& (is_inside_2d_gamut_slice(pos.gr, rgb_corner_radii.g) && is_inside_2d_gamut_slice(pos.gb, rgb_corner_radii.g))
        // Trim blue except where red is high or green is high
		&& (is_inside_2d_gamut_slice(pos.br, rgb_corner_radii.b) && is_inside_2d_gamut_slice(pos.bg, rgb_corner_radii.b))
#else
        // Just a box.
		&& (pos.x <= 1.0 && pos.y <= 1.0 && pos.z <= 1.0)
#endif
		;
}

float3 compress_stimulus(float3 input) {
    // Find the input brightness and compress it. We will then adjust the chromatic input
    // to match that compressed brightness.
	const float input_brightness = srgb_to_hk_adjusted_luminance(input);
	const float compressed_brightness = compress_brightness(input_brightness);

    // Start by simply scaling the stimulus by the ratio between the compressed
    // and original brightness. This will create matching brightness,
    // but potentially out of gamut components.
    float3 compressed_rgb = input * max(0.0, compressed_brightness / max(1e-5, input_brightness));

    // We now want to map the out-of-gamut stimulus back to what our device can display.
    // Since both the `compressed_rgb` and `compressed_brightness` are of the same
    // brightness, and `compressed_brightness.xxx` is guaranteed to be inside the gamut,
    // we can trace a path from `compressed_rgb` towards `compressed_brightness.xxx`,
    // and stop once we have intersected the target gamut.

    // This has the effect of removing chromatic content from the compressed stimulus,
    // and replacing that with achromatic content. If we do that naively, we run into
    // a perceptual hue shift due to the Abney effect.
    //
    // To counter, we first transform both vertices of the path we want to trace
    // into a perceptual space which preserves sensation of hue, then we trace
    // a straight line in that space until we intersect the gamut.

	const float3 perceptual = linear_to_perceptual(compressed_rgb);
	const float3 perceptual_white = linear_to_perceptual(compressed_brightness.xxx);

	float3 compressed_0 = compressed_rgb;

#if USE_BRIGTHNESS_DEPENDENT_DESATURATION
    const float3 max_possible_component = 1.0 / float3(0.2126, 0.7152, 0.0722);
    const float max_component = max(
        compressed_rgb.r / max_possible_component.r, max(
        compressed_rgb.g / max_possible_component.g,
        compressed_rgb.b / max_possible_component.b));

    float s0 = saturate(smoothstep(BRIGTHNESS_DEPENDENT_DESATURATION_START, 1.0,
        pow(max_component, BRIGTHNESS_DEPENDENT_DESATURATION_EXPONENT)
    ) * BRIGTHNESS_DEPENDENT_DESATURATION_SCALE);
#else
	float s0 = 0;
#endif

	float s1 = 1;

    // The gamut (and the line) is deformed by the perceptual space, making its shape non-trivial.
    // We also potentially use a trimmed gamut to reduce the presence of the "Notorious 6",
    // making the gamut shape difficult to intersect analytically.
    //
    // The search here is performed in a pretty brute-force way, by performing a binary search.
    // The number of iterations is chosen in a very conservative way, and could be reduced.

	for (int i = 0; i < 24; ++i) {
		float3 perceptual_mid = lerp(perceptual, perceptual_white, lerp(s0, s1, 0.5));
		compressed_rgb = perceptual_to_linear(perceptual_mid);

		if (is_inside_target_gamut(compressed_rgb)) {
            // Mid point inside gamut. Step back.
			s1 = lerp(s0, s1, 0.5);
		} else {
            // Mid point outside gamut. Step forward.
			s0 = lerp(s0, s1, 0.5);
		}
	}

    return compressed_rgb;
}
