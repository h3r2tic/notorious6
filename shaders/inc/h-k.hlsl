// Helmholtz-Kohlrausch
// From https://github.com/ilia3101/HKE

// `uv`: CIE LUV u' and v'
// `adapt_lum`: adating luminance (L_a); Nayatani 1998 uses 63.66 nits
float nayatani_hk_lightness_adjustment_multiplier(float2 uv, float adapt_lum) {
    const float2 d65_uv = cie_xy_to_Luv_uv(float2(0.31271, 0.32902));
    const float u_white = d65_uv[0];
    const float v_white = d65_uv[1];
    uv -= float2(u_white, v_white);

    float hue = atan2(uv[1], uv[0]);
    float qhue = -0.01585 - 0.03016*cos(hue) - 0.04556*cos(2 * hue) - 0.02667*cos(3 * hue) - 0.00295*cos(4 * hue) + 0.14592*sin(hue) + 0.05084*sin(2 * hue) - 0.01900*sin(3 * hue) - 0.00764*sin(4 * hue);
    float kbr = 0.2717*(6.469 + 6.362*pow(adapt_lum, 0.4495)) / (6.469 + pow(adapt_lum, 0.4495));

    float suv = 13 * pow(square(uv[0]) + square(uv[1]), 0.5);
    float gamma = 1.0 + (-0.1340 * qhue + 0.0872 * kbr) * suv;
    return gamma;
}
