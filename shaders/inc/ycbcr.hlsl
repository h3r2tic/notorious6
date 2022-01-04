float3 rgb_to_ycbcr(float3 col) {
    return mul(float3x3(0.2126, 0.7152, 0.0722, -0.1146,-0.3854, 0.5, 0.5,-0.4542,-0.0458), col);
}

float3 ycbcr_to_rgb(float3 col) {
    return max(0.0.xxx, mul(float3x3(1.0, 0.0, 1.5748, 1.0, -0.1873, -.4681, 1.0, 1.8556, 0.0), col));
}
