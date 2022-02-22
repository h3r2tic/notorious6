#include "inc/prelude.glsl"
#include "inc/ictcp.hlsl"
#include "inc/luv.hlsl"
#include "inc/lms.hlsl"
#include "inc/oklab.hlsl"
#include "inc/lab.hlsl"
#include "inc/h-k.hlsl"
#include "inc/ycbcr.hlsl"
#include "inc/ipt.hlsl"
#include "inc/bezold_brucke.hlsl"

#define BEZOLD_BRUCKE_BRUTE_FORCE 1

#if BEZOLD_BRUCKE_BRUTE_FORCE
#include "inc/cie1931.glsl"
#include "inc/bezold_brucke_brute_force.glsl"
#endif

// The space to perform chroma attenuation in. More details in the `compress_stimulus` function.
// Oklab works well, but fails at pure blues.
// ICtCp seems to work pretty well all around.
// LUV and None don't provide Abney correction.
#define PERCEPTUAL_SPACE_OKLAB 0
#define PERCEPTUAL_SPACE_LUV 1
#define PERCEPTUAL_SPACE_ICTCP 2
#define PERCEPTUAL_SPACE_IPT 3
#define PERCEPTUAL_SPACE_NONE 4

// Helmholtz-Kohlrausch adjustment methods
#define HK_ADJUSTMENT_METHOD_NONE 0
#define HK_ADJUSTMENT_METHOD_NAYATANI 1
#define HK_ADJUSTMENT_METHOD_NAYATANI_HACK 2

// Brightness compression curves:
#define BRIGHTNESS_COMPRESSION_CURVE_REINHARD 0
#define BRIGHTNESS_COMPRESSION_CURVE_SIRAGUSANO_SMITH 1    // :P

// ----------------------------------------------------------------
// Configurable stuff:

#define BRIGHTNESS_COMPRESSION_CURVE BRIGHTNESS_COMPRESSION_CURVE_SIRAGUSANO_SMITH

// Choose the perceptual space for chroma attenuation.
#define PERCEPTUAL_SPACE PERCEPTUAL_SPACE_IPT

// Choose the method for performing the H-K adjustment
#define HK_ADJUSTMENT_METHOD HK_ADJUSTMENT_METHOD_NAYATANI_HACK

// Adapting luminance (L_a) used for the H-K adjustment. 20 cd/m2 was used in Sanders and Wyszecki (1964)
#define HK_ADAPTING_LUMINANCE 20

// Match target compressed brightness while attenuating chroma.
// Important in the low end, as well as at the high end of blue and red.
#define USE_BRIGHTNESS_LINEAR_CHROMA_ATTENUATION 1

// Controls for manual desaturation of lighter than "white" stimulus (greens, yellows);
// see comments in the code for more details.
#define CHROMA_ATTENUATION_START 0.0
#define CHROMA_ATTENUATION_EXPONENT_MIN 3.0
#define CHROMA_ATTENUATION_EXPONENT_MAX 4.0

// ----------------------------------------------------------------

#if 0
    #define USE_BEZOLD_BRUCKE_SHIFT 0
    #define HERPDERP 1
    #define HERPDERP_K 24.0
    #define ASINSHIFT 1
    #define WINDOW_ASINSHIFT 0
    #define SHIFTBIAS 1.03
#else
    #define USE_BEZOLD_BRUCKE_SHIFT 1
    
    #define HERPDERP 0
    #define HERPDERP_K 64.0

    #define ASINSHIFT 1
    #define WINDOW_ASINSHIFT 1
    #define SHIFTBIAS 1.03
#endif

#define BEZOLD_BRUCKE_SHIFT_K 14
#define BEZOLD_BRUCKE_SHIFT_P 1.0

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
#elif PERCEPTUAL_SPACE == PERCEPTUAL_SPACE_IPT
	#define linear_to_perceptual(col) xyz_to_ipt(RGBToXYZ(col))
	#define perceptual_to_linear(col) XYZtoRGB(ipt_to_xyz(col))
#elif PERCEPTUAL_SPACE == PERCEPTUAL_SPACE_NONE
	#define linear_to_perceptual(col) (col)
	#define perceptual_to_linear(col) (col)
#endif

// Map brightness through a curve yielding values in 0..1, working with linear stimulus values.
float compress_brightness(float v) {
	#if BRIGHTNESS_COMPRESSION_CURVE == BRIGHTNESS_COMPRESSION_CURVE_REINHARD
		// Reinhard
        const float k = 1.0;
		return pow(pow(v, k) / (pow(v, k) + 1.0), 1.0 / k);
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

float soft_shoulder(float x, float k, float p) {
    return x / pow(pow(x / k, p) + 1.0, 1.0 / p);
}

float srgb_to_luminance(float3 col) {
    return rgb_to_ycbcr(col).x;
}

// Stimulus-linear luminance adjusted by the Helmholtz-Kohlrausch effect
float srgb_to_hk_adjusted_brightness(float3 shader_input) {
#if HK_ADJUSTMENT_METHOD == HK_ADJUSTMENT_METHOD_NAYATANI
    const float luminance = srgb_to_luminance(shader_input);
    const float2 uv = cie_XYZ_to_Luv_uv(RGBToXYZ(shader_input));
    const float luv_brightness = hsluv_yToL(luminance);
    const float mult = nayatani_hk_lightness_adjustment_multiplier(uv, HK_ADAPTING_LUMINANCE);
    return hsluv_lToY(luv_brightness * mult);
#elif HK_ADJUSTMENT_METHOD == HK_ADJUSTMENT_METHOD_NAYATANI_HACK
    const float luminance = srgb_to_luminance(shader_input);
    const float2 uv = cie_XYZ_to_Luv_uv(RGBToXYZ(shader_input));
    const float luv_brightness = hsluv_yToL(luminance);
    const float mult = hack_nayatani_hk_lightness_adjustment_multiplier(uv, HK_ADAPTING_LUMINANCE);
    return hsluv_lToY(luv_brightness) * pow(mult, 3.5);
#elif HK_ADJUSTMENT_METHOD == HK_ADJUSTMENT_METHOD_NONE
    return srgb_to_luminance(shader_input);
#endif
}

float3 compress_stimulus(ShaderInput shader_input) {
    // herp derp saturation of cones
    if (HERPDERP) {
        float3 stimulus = shader_input.stimulus;
        const float input_brightness = srgb_to_hk_adjusted_brightness(stimulus);

        const float k = HERPDERP_K;
        const float p = 1.0;
        stimulus = Primaries_BT2020_to_LMS(Primaries_BT709_to_BT2020(stimulus));
        stimulus /= k;
        stimulus = max(stimulus, 0.0.xxx);
        stimulus = stimulus * pow(pow(stimulus, p.xxx) + 1.0, -1.0 / p.xxx);
        stimulus *= k;
        stimulus = Primaries_BT2020_to_BT709(Primaries_LMS_to_BT2020(stimulus));
        
        stimulus *= input_brightness / max(1e-10, srgb_to_hk_adjusted_brightness(stimulus));
        shader_input.stimulus = stimulus;
    }

    if (USE_BEZOLD_BRUCKE_SHIFT) {
        const float input_brightness = srgb_to_hk_adjusted_brightness(shader_input.stimulus);

        const float k = BEZOLD_BRUCKE_SHIFT_K;
        const float p = BEZOLD_BRUCKE_SHIFT_P;
        const float t = srgb_to_luminance(shader_input.stimulus) / k;
        float shift_amount = t * pow(pow(t, p) + 1.0, -1.0 / p);
        //return shift_amount.xxx;

        #if BEZOLD_BRUCKE_BRUTE_FORCE
            float3 stimulus = XYZtoRGB(BB_shift_brute_force_XYZ(RGBToXYZ(shader_input.stimulus), shift_amount));
        #else
            float3 stimulus = XYZtoRGB(BB_shift_XYZ(RGBToXYZ(shader_input.stimulus), shift_amount));
        #endif

        stimulus *= input_brightness / max(1e-10, srgb_to_hk_adjusted_brightness(stimulus));
        
        shader_input.stimulus = stimulus;
    }

    // Find the shader_input brightness adjusted by the Helmholtz-Kohlrausch effect.
    const float input_brightness = srgb_to_hk_adjusted_brightness(shader_input.stimulus);

    // The highest displayable intensity stimulus with the same chromaticity as the shader_input,
    // and its associated brightness.
    const float3 max_intensity_rgb = shader_input.stimulus / max(shader_input.stimulus.r, max(shader_input.stimulus.g, shader_input.stimulus.b)).xxx;
    float max_intensity_brightness = srgb_to_hk_adjusted_brightness(max_intensity_rgb);
    //return max_intensity_brightness.xxx - 1.0;
    //return saturate(max_intensity_rgb);

    const float max_output_scale = 1.0;

    // Compress the brightness. We will then adjust the chromatic shader_input stimulus to match this.
    // Note that this is not the non-linear "L*", but a 0..`max_output_scale` value as a multilpier
    // over the maximum achromatic luminance.
    const float compressed_achromatic_luminance = compress_brightness(input_brightness / max_output_scale) * max_output_scale;
    //const float compressed_achromatic_luminance = smoothstep(0.1, 0.9, shader_input.uv.x);

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
    
    // We'll make the transition towards white smoother in areas of high chromatic strength.
    //float chroma_strength = length(rgb_to_ycbcr(max_intensity_rgb).yz);
    float chroma_strength = LabToLch(XYZToLab(RGBToXYZ(max_intensity_rgb))).y / 100.0 * 0.4;
    //float chroma_strength = 1;

    const float chroma_attenuation_start = CHROMA_ATTENUATION_START;
    const float chroma_attenuation_exponent = lerp(CHROMA_ATTENUATION_EXPONENT_MAX, CHROMA_ATTENUATION_EXPONENT_MIN, chroma_strength);
    const float chroma_attenuation_t = saturate(
        (compressed_achromatic_luminance - min(1, max_intensity_brightness) * chroma_attenuation_start)
        / ((SHIFTBIAS * max_output_scale - min(1, max_intensity_brightness) * chroma_attenuation_start))
    );

#if ASINSHIFT
    float chroma_attenuation = asin(pow(chroma_attenuation_t, 3.0)) / M_PI * 2;
    
    if (WINDOW_ASINSHIFT) {
        const float compressed_achromatic_luminance2 = compress_brightness(0.125 * input_brightness / max_output_scale) * max_output_scale;
        const float chroma_attenuation_t2 = saturate(
            (compressed_achromatic_luminance2 - min(1, max_intensity_brightness) * 0.5)
            / ((max_output_scale - min(1, max_intensity_brightness) * 0.5))
        );

        chroma_attenuation = lerp(chroma_attenuation, 1.0,
            1.0 - saturate(1.0 - pow(chroma_attenuation_t2, 4))
        );
    }
#else
    const float chroma_attenuation = pow(chroma_attenuation_t, chroma_attenuation_exponent);
#endif

    {
		const float3 perceptual_mid = lerp(perceptual, perceptual_white, chroma_attenuation);
		compressed_rgb = perceptual_to_linear(perceptual_mid);

        #if USE_BRIGHTNESS_LINEAR_CHROMA_ATTENUATION
            for (int i = 0; i < 2; ++i) {
                const float current_brightness = srgb_to_hk_adjusted_brightness(compressed_rgb);
                compressed_rgb *= compressed_achromatic_luminance / max(1e-10, current_brightness);
            }
        #endif
    }

    // At this stage we still have out of gamut colors.
    // This takes a silly twist now. So far we've been careful to preserve hue...
    // Now we're going to let the channels clip, but apply a per-channel roll-off.
    // This sacrificies hue accuracy and brightness to retain saturation.

    if (true) {
        compressed_rgb = max(compressed_rgb, 0.0.xxx);

        const float p = 12.0;
        compressed_rgb = compressed_rgb * pow(pow(compressed_rgb, p.xxx) + 1.0, -1.0 / p.xxx);

        const float max_comp = max(compressed_rgb.r, max(compressed_rgb.g, compressed_rgb.b));
        const float max_comp_dist = max(max_comp - compressed_rgb.r, max(max_comp - compressed_rgb.g, max_comp - compressed_rgb.b));

        // Rescale so we can reach 100% white. Avoid rescaling very highly saturated colors,
        // as that would reintroduce discontinuities.
        compressed_rgb /= pow(lerp(0.5, 1.0, max_comp_dist), 1.0 / p);
    }

    //return srgb_to_hk_adjusted_brightness(compressed_rgb).xxx;
    //return compressed_achromatic_luminance.xxx;

    return compressed_rgb;
}
