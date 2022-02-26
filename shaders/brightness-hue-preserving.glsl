// TL;DR: Compress brightness, preserve chroma by desaturation.

#include "inc/prelude.glsl"
#include "inc/ictcp.hlsl"
#include "inc/luv.hlsl"
#include "inc/oklab.hlsl"
#include "inc/lab.hlsl"
#include "inc/ycbcr.hlsl"

#define HK_ADJUSTMENT_METHOD 1  // Force Nayatani
#include "inc/helmholtz_kohlrausch.hlsl"

// The space to perform chroma attenuation in. More details in the `compress_stimulus` function.
// Oklab works best, with ICtCp being a close second.
// LUV and None don't provide Abney correction.
#define PERCEPTUAL_SPACE_OKLAB 0
#define PERCEPTUAL_SPACE_ICTCP 2
#define PERCEPTUAL_SPACE_NONE 3

// Brightness compression curves:
#define BRIGHTNESS_COMPRESSION_CURVE_REINHARD 0
#define BRIGHTNESS_COMPRESSION_CURVE_SIRAGUSANO_SMITH 1    // :P

// ----------------------------------------------------------------
// Configurable stuff:

#define BRIGHTNESS_COMPRESSION_CURVE BRIGHTNESS_COMPRESSION_CURVE_SIRAGUSANO_SMITH

// Choose the perceptual space for chroma attenuation.
#define PERCEPTUAL_SPACE PERCEPTUAL_SPACE_OKLAB

// Match target compressed brightness while attenuating chroma.
// Important in the low end, as well as at the high end of blue and red.
#define USE_BRIGHTNESS_LINEAR_CHROMA_ATTENUATION 1

// The stimulus with the highest displayable brightness is not "white" 100% r, g, and b,
// but depends on the Helmholtz-Kohlrausch effect.
// That is somewhat problematic for us, as the display transform here is based on compressing
// brightness to a range of up to a maximum achromatic signal of the output device.
// If `ALLOW_BRIGHTNESS_ABOVE_WHITE` is 0, yellows and greens are never allowed to reach
// full intensity, as that results in brightness above that of "white".
// If `ALLOW_BRIGHTNESS_ABOVE_WHITE` is 1, the compressed stimulus is allowed to exceed
// that range, at the cost of the output brightness curve having an inflection point, with the
// brightness briefly exceeding max, and then going back to max as chroma attenuates.
#define ALLOW_BRIGHTNESS_ABOVE_WHITE 0

// if 1, the gamut will be trimmed at the "notorious 6" corners.
// if 0, the whole gamut is used.
// Not strictly necessary, but smooths-out boundaries where
// achromatic stimulus begins to be added.
#define TRIM_GAMUT_CORNERS 1    // 0 or 1
#define GAMUT_CORNER_CUT_RADII float3(0.25, 0.25, 0.25) // 0..1

// Controls for manual desaturation of lighter than "white" stimulus (greens, yellows);
// see comments in the code for more details.
#define CHROMA_ATTENUATION_START 0.0
#define CHROMA_ATTENUATION_EXPONENT 4.0
// ----------------------------------------------------------------


// Based on the selection, define `linear_to_perceptual` and `perceptual_to_linear`
#if PERCEPTUAL_SPACE == PERCEPTUAL_SPACE_OKLAB
	#define linear_to_perceptual(col) sRGB_to_Oklab(col)
	#define perceptual_to_linear(col) Oklab_to_sRGB(col)
#elif PERCEPTUAL_SPACE == PERCEPTUAL_SPACE_ICTCP
	#define linear_to_perceptual(col) BT709_to_ICtCp(col)
	#define perceptual_to_linear(col) ICtCp_to_BT709(col)
#elif PERCEPTUAL_SPACE == PERCEPTUAL_SPACE_NONE
	#define linear_to_perceptual(col) (col)
	#define perceptual_to_linear(col) (col)
#endif

// Map brightness through a curve yielding values in 0..1, working with linear stimulus values.
float compress_brightness(float v) {
	#if BRIGHTNESS_COMPRESSION_CURVE == BRIGHTNESS_COMPRESSION_CURVE_REINHARD
		// Reinhard
		return v / (v + 1.0);
	#elif BRIGHTNESS_COMPRESSION_CURVE == BRIGHTNESS_COMPRESSION_CURVE_SIRAGUSANO_SMITH
		// From Jed Smith: https://github.com/jedypod/open-display-transform/wiki/tech_tonescale,
        // based on stuff from Daniele Siragusano: https://community.acescentral.com/t/output-transform-tone-scale/3498/14
        // Reinhard with flare compensation.
        const float sx = 1.0;
        const float p = 1.2;
        const float sy = 1.0205;
		return saturate(sy * pow(v / (v + sx), p));
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
        && (pos.x >= 0.0 && pos.y >= 0.0 && pos.z >= 0.0)
#endif
		;
}

float3 compress_stimulus(ShaderInput shader_input) {
    const HelmholtzKohlrauschEffect hk = hk_from_sRGB(shader_input.stimulus);
    
    // Find the shader_input brightness adjusted by the Helmholtz-Kohlrausch effect.
    const float input_brightness = srgb_to_equivalent_luminance(hk, shader_input.stimulus);

    // The highest displayable intensity stimulus with the same chromaticity as the shader_input,
    // and its associated brightness.
    const float3 max_intensity_rgb = shader_input.stimulus / max(shader_input.stimulus.r, max(shader_input.stimulus.g, shader_input.stimulus.b)).xxx;
    float max_intensity_brightness = srgb_to_equivalent_luminance(hk, max_intensity_rgb);
    //return max_intensity_brightness.xxx - 1.0;
    //return max_intensity_rgb;

    #if ALLOW_BRIGHTNESS_ABOVE_WHITE
        // The `max_intensity_rgb` stimulus can potentially be lighter than "white".
        //
        // This is by how much the output brightness will be allowed to exceed
        // the brightness of the highest luminance achromatic stimulus of the target gamut.
        float max_output_scale = max(1.0, max_intensity_brightness);
    #else
        float max_output_scale = 1.0;
    #endif

    // Compress the brightness. We will then adjust the chromatic shader_input stimulus to match this.
    // Note that this is not the non-linear "L*", but a 0..`max_output_scale` value as a multilpier
    // over the maximum achromatic luminance.
    const float compressed_achromatic_luminance = compress_brightness(input_brightness / max_output_scale) * max_output_scale;

    // Scale the chromatic stimulus so that its luminance matches `compressed_achromatic_luminance`.
    // TODO: Overly simplistic, and does not accurately map the brightness.
    //
    // This will create (mostly) matching brightness, but potentially out of gamut components.
    float3 compressed_rgb = (max_intensity_rgb / max_intensity_brightness) * compressed_achromatic_luminance;

    // The achromatic stimulus we'll interpolate towards to fix out-of-gamut stimulus.
    const float clamped_compressed_achromatic_luminance = min(1.0, compressed_achromatic_luminance);

    // We now want to map the out-of-gamut stimulus back to what our device can display.
    // Since both the `compressed_rgb` and `clamped_compressed_achromatic_luminance` are of the same-ish
    // brightness, and `clamped_compressed_achromatic_luminance.xxx` is guaranteed to be inside the gamut,
    // we can trace a path from `compressed_rgb` towards `clamped_compressed_achromatic_luminance.xxx`,
    // and stop once we have intersected the target gamut.

    // This has the effect of removing chromatic content from the compressed stimulus,
    // and replacing that with achromatic content. If we do that naively, we run into
    // a perceptual hue shift due to the Abney effect.
    //
    // To counter, we first transform both vertices of the path we want to trace
    // into a perceptual space which preserves sensation of hue, then we trace
    // a straight line _inside that space_ until we intersect the gamut.

	const float3 perceptual = linear_to_perceptual(compressed_rgb);
	const float3 perceptual_white = linear_to_perceptual(clamped_compressed_achromatic_luminance.xxx);

    // Values lighter than "white" are already within the gamut, so our brightness compression is "done".
    // Perceptually they look wrong though, as they don't follow the desaturation that other stimulus does.
    // We fix that manually here by biasing the interpolation towards "white" at the end of the brightness range.
    // This "fixes" the yellows and greens.
    const float chroma_attenuation = pow(
        saturate(
            (compressed_achromatic_luminance - max_output_scale * CHROMA_ATTENUATION_START)
            / (max_output_scale * (1.0 - CHROMA_ATTENUATION_START))
        ), CHROMA_ATTENUATION_EXPONENT
    );

    // The gamut (and the line) is deformed by the perceptual space, making its shape non-trivial.
    // We also potentially use a trimmed gamut to reduce the presence of the "Notorious 6",
    // making the gamut shape difficult to intersect analytically.
    //
    // The search here is performed in a pretty brute-force way, by performing a binary search.
    // The number of iterations is chosen in a very conservative way, and could be reduced.

    // Start and end points of our binary search. We'll refine those as we go.
	float s0 = chroma_attenuation;
	float s1 = 1;

    {
		float3 perceptual_mid = lerp(perceptual, perceptual_white, s0);
		compressed_rgb = perceptual_to_linear(perceptual_mid);
        const HelmholtzKohlrauschEffect hk = hk_from_sRGB(compressed_rgb);

        #if USE_BRIGHTNESS_LINEAR_CHROMA_ATTENUATION
            for (int i = 0; i < 2; ++i) {
                const float current_brightness = srgb_to_equivalent_luminance(hk, compressed_rgb);
                compressed_rgb *= clamped_compressed_achromatic_luminance / max(1e-10, current_brightness);
            }
        #endif
    }

    if (!is_inside_target_gamut(compressed_rgb)) {
    	for (int i = 0; i < 24; ++i) {
    		float3 perceptual_mid = lerp(perceptual, perceptual_white, lerp(s0, s1, 0.5));
    		compressed_rgb = perceptual_to_linear(perceptual_mid);
            const HelmholtzKohlrauschEffect hk = hk_from_sRGB(compressed_rgb);

            #if USE_BRIGHTNESS_LINEAR_CHROMA_ATTENUATION
                const float current_brightness = srgb_to_equivalent_luminance(hk, compressed_rgb);
                compressed_rgb *= clamped_compressed_achromatic_luminance / max(1e-10, current_brightness);
            #endif

            // Note: allow to exceed the gamut when `max_output_scale` > 1.0.
            // If we don't, we get a sharp cut to "white" with ALLOW_BRIGHTNESS_ABOVE_WHITE.
    		if (is_inside_target_gamut(compressed_rgb / max_output_scale)) {
                // Mid point inside gamut. Step back.
    			s1 = lerp(s0, s1, 0.5);
    		} else {
                // Mid point outside gamut. Step forward.
    			s0 = lerp(s0, s1, 0.5);
    		}
    	}
    }

#if ALLOW_BRIGHTNESS_ABOVE_WHITE
    // HACK: if `ALLOW_BRIGHTNESS_ABOVE_WHITE` is enabled, we may still have a stimulus
    // value outside of the target gamut. We could clip here, but this works too.
    compressed_rgb /= max(1.0, max(compressed_rgb.r, max(compressed_rgb.g, compressed_rgb.b)));
#endif

    //return hk_equivalent_luminance(compressed_rgb).xxx;
    //return compressed_achromatic_luminance.xxx;

    return compressed_rgb;
}
