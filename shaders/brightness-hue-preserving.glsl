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
#define PERCEPTUAL_SPACE_NONE 3

// Helmholtz-Kohlrausch adjustment methods
#define HK_ADJUSTMENT_METHOD_NAYATANI 0
#define HK_ADJUSTMENT_METHOD_NONE 1

// ----------------------------------------------------------------
// Configurable stuff:

// Choose the perceptual space for chroma attenuation.
#define PERCEPTUAL_SPACE PERCEPTUAL_SPACE_OKLAB

// Choose the method for performing the H-K adjustment
#define HK_ADJUSTMENT_METHOD HK_ADJUSTMENT_METHOD_NAYATANI

// if 1, the gamut will be trimmed at the "notorious 6" corners.
// if 0, the whole gamut is used.
// Not strictly necessary, but smooths-out boundaries where
// achromatic stimulus begins to be added.
#define TRIM_GAMUT_CORNERS 1    // 0 or 1
#define GAMUT_CORNER_CUT_RADII float3(0.25, 0.25, 0.25) // 0..1
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

float compress_lightness(float v) {
	#if 0
		// From Daniele Siragusano: https://community.acescentral.com/t/output-transform-tone-scale/3498/14
		float n = 100;
		float n_r = 100;
		float g = 1.2;
		float w = 1;
		float t = 0.0;	// toe
		float m = n / n_r;
		float s_1 = w * pow(max(0.0, m), 1.0 / g);
		float fx = pow(max(0.0, v / (v + s_1)), g) * m;
		return max(0.0, fx * fx / (fx + t));
	#elif 0
		// Reinhard
		return v / (v + 1.0);
	#elif 1
		// Hyperbolic, from Jed Smith: https://github.com/jedypod/open-display-transform/wiki/tech_tonescale
        const float sx = 1.0;
        const float p = 1.2;
        const float sy = 1.0205;
		return saturate(sy * pow(v / (v + sx), p));
    #else
		// Ye olde exponential
        return 1.0 - exp(-v);
    #endif
}

float srgb_to_luminance(float3 col) {
    return rgb_to_ycbcr(col).x;
}

// Stimulus-linear luminance adjusted by the Helmholtz-Kohlrausch effect
float srgb_to_hk_adjusted_lightness(float3 input) {
#if HK_ADJUSTMENT_METHOD == HK_ADJUSTMENT_METHOD_NAYATANI
    const float luminance = srgb_to_luminance(input);
    const float3 xyz = RGBToXYZ(input / max(1e-10, luminance));
    const float2 uv = cie_XYZ_to_Luv_uv(xyz);
    const float luv_lightness = hsluv_yToL(luminance);
    const float nayat = nayatani_hk_lightness_adjustment_multiplier(uv);
    return hsluv_lToY(luv_lightness * nayat);
#elif HK_ADJUSTMENT_METHOD == HK_ADJUSTMENT_METHOD_NONE
    return srgb_to_luminance(input);
#endif
}

// A square with the (1, 0) and (0, 1) corners circularly trimmed.
bool is_inside_2d_gamut_slice(float2 pos, float corner_radius) {
	float2 closest = clamp(pos, float2(0, corner_radius), float2(1 - corner_radius, 1));
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
    //input /= srgb_to_luminance(input);
    const float input_luminance = srgb_to_luminance(input);

    // Find the input lightness and compress it. We will then adjust the chromatic input
    // to match that compressed lightness.
	//float input_lightness = input_luminance * hk;
    float input_lightness = srgb_to_hk_adjusted_lightness(input);
    //return input_lightness.xxx;

    //return input_luminance.xxx;
    //return srgb_to_hk_adjusted_lightness(input).xxx;
    const float3 max_intensity_rgb = input / max(input.r, max(input.g, input.b)).xxx;
    float max_intensity_lightness = srgb_to_hk_adjusted_lightness(max_intensity_rgb);
    float max_output_scale = max(1.0, max_intensity_lightness);
    //return max_intensity_lightness.xxx - 1.0;
    //return max_intensity_rgb;

	float compressed_lightness = compress_lightness(input_lightness / max_output_scale) * max_output_scale;

    // Start by simply scaling the stimulus by the ratio between the compressed
    // and original lightness. This will create matching lightness,
    // but potentially out of gamut components.
    //float3 compressed_rgb = input * max(0.0, compressed_lightness / max(1e-10, input_lightness));
    float3 compressed_rgb = compressed_lightness * (max_intensity_rgb / max_intensity_lightness);

    //return compressed_rgb;

    // We now want to map the out-of-gamut stimulus back to what our device can display.
    // Since both the `compressed_rgb` and `compressed_lightness` are of the same
    // lightness, and `compressed_lightness.xxx` is guaranteed to be inside the gamut,
    // we can trace a path from `compressed_rgb` towards `compressed_lightness.xxx`,
    // and stop once we have intersected the target gamut.

    // This has the effect of removing chromatic content from the compressed stimulus,
    // and replacing that with achromatic content. If we do that naively, we run into
    // a perceptual hue shift due to the Abney effect.
    //
    // To counter, we first transform both vertices of the path we want to trace
    // into a perceptual space which preserves sensation of hue, then we trace
    // a straight line in that space until we intersect the gamut.

	const float3 perceptual = linear_to_perceptual(compressed_rgb);
	const float3 perceptual_white = linear_to_perceptual(min(1.0, compressed_lightness).xxx);

    const float chroma_attenuation_start = min(0.7, 1.0 / (max_output_scale));
	float s0 = pow(max(0.0, (compressed_lightness - max_output_scale * chroma_attenuation_start) / (max_output_scale * (1.0 - chroma_attenuation_start))), 3);
	float s1 = 1;

    // The gamut (and the line) is deformed by the perceptual space, making its shape non-trivial.
    // We also potentially use a trimmed gamut to reduce the presence of the "Notorious 6",
    // making the gamut shape difficult to intersect analytically.
    //
    // The search here is performed in a pretty brute-force way, by performing a binary search.
    // The number of iterations is chosen in a very conservative way, and could be reduced.

    {
		float3 perceptual_mid = lerp(perceptual, perceptual_white, s0);
		compressed_rgb = perceptual_to_linear(perceptual_mid);
    }

    if (!is_inside_target_gamut(compressed_rgb)) {
    	for (int i = 0; i < 24; ++i) {
    		float3 perceptual_mid = lerp(perceptual, perceptual_white, lerp(s0, s1, 0.5));
    		compressed_rgb = perceptual_to_linear(perceptual_mid);

    		if (is_inside_target_gamut(compressed_rgb / max_output_scale)) {
                // Mid point inside gamut. Step back.
    			s1 = lerp(s0, s1, 0.5);
    		} else {
                // Mid point outside gamut. Step forward.
    			s0 = lerp(s0, s1, 0.5);
    		}
    	}
    }

    compressed_rgb = saturate(compressed_rgb);

    const float output_lightness = srgb_to_hk_adjusted_lightness(compressed_rgb);
    //return compressed_lightness.xxx;
    //return output_lightness.xxx;
    return compressed_rgb;
}
