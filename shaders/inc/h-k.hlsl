// Helmholtz-Kohlrausch
// From https://github.com/ilia3101/HKE
// Based on Nayatani, Y. (1997). Simple estimation methods for the Helmholtz-Kohlrausch effect

// `uv`: CIE LUV u' and v'
// `adapt_lum`: adating luminance (L_a)
float nayatani_hk_lightness_adjustment_multiplier(float2 uv, float adapt_lum) {
    const float2 d65_uv = cie_xy_to_Luv_uv(float2(0.31271, 0.32902));
    const float u_white = d65_uv[0];
    const float v_white = d65_uv[1];

    uv -= float2(u_white, v_white);

    float theta = atan2(uv[1], uv[0]);

    float q =
        - 0.01585
        - 0.03016 * cos(theta) - 0.04556 * cos(2 * theta)
        - 0.02667 * cos(3 * theta) - 0.00295 * cos(4 * theta)
        + 0.14592 * sin(theta) + 0.05084 * sin(2 * theta)
        - 0.01900 * sin(3 * theta) - 0.00764 * sin(4 * theta);

    float kbr = 0.2717 * (6.469 + 6.362 * pow(adapt_lum, 0.4495)) / (6.469 + pow(adapt_lum, 0.4495));
    float suv = 13.0 * length(uv);

    return 1.0 + (-0.1340 * q + 0.0872 * kbr) * suv;
}

float catmull_rom(float x, float v0,float v1, float v2,float v3) 
{
	float c2 = -.5 * v0	+ 0.5*v2;
	float c3 = v0		+ -2.5*v1 + 2.0*v2 + -.5*v3;
	float c4 = -.5 * v0	+ 1.5*v1 + -1.5*v2 + 0.5*v3;
	return(((c4 * x + c3) * x + c2) * x + v1);
}

// `uv`: CIE LUV u' and v'
// `adapt_lum`: adating luminance (L_a)
float hack_nayatani_hk_lightness_adjustment_multiplier(float2 uv, float adapt_lum) {
    const float2 d65_uv = cie_xy_to_Luv_uv(float2(0.31271, 0.32902));
    const float u_white = d65_uv[0];
    const float v_white = d65_uv[1];

    uv -= float2(u_white, v_white);

    float theta = atan2(uv[1], uv[0]);

    // ----
    // Custom eyeballed q function.

    const uint SAMPLE_COUNT = 16;
    float samples[] = {
        0.05,    // greenish cyan
        0.1,    // greenish cyan
        0.13,    // cyan
        0.06,    // cyan
        -0.4,    // blue
        -0.27,   // purplish-blue
        -0.27,   // magenta
        -0.24,   // magenta
        -0.15,   // purplish-red
        -0.0,   // red
        0.16,    // orange
        0.25,    // reddish-yellow
        0.25,    // yellow
        0.12,   // yellowish-green
        0.02,   // green
        0.02,
    };

    const float t = (theta / M_PI) * 0.5 + 0.5;
    const uint i0 = uint(floor(t * SAMPLE_COUNT)) % SAMPLE_COUNT;
    const uint i1 = (i0 + 1) % SAMPLE_COUNT;
    float q0 = samples[(i0 + SAMPLE_COUNT - 1) % SAMPLE_COUNT];
    float q1 = samples[i0];
    float q2 = samples[i1];
    float q3 = samples[(i1 + 1) % SAMPLE_COUNT];
    const float interp = (t - float(i0) / SAMPLE_COUNT) * SAMPLE_COUNT;
    //float q = q1;
    float q = catmull_rom(interp, q0, q1, q2, q3);
    // ----

    float kbr = 0.2717 * (6.469 + 6.362 * pow(adapt_lum, 0.4495)) / (6.469 + pow(adapt_lum, 0.4495));
    float suv = 13.0 * length(uv);

    // Hack
    return 1.0 + (-0.3 * q + 0.0872 * kbr) * suv;
}
