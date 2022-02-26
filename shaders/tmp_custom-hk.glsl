#include "inc/prelude.glsl"
#include "inc/display_transform.hlsl"

vec3 hsv2rgb(vec3 c) {
    vec3 rgb = clamp( abs(mod(c.x*6.0+vec3(0.0,4.0,2.0),6.0)-3.0)-1.0, 0.0, 1.0 );
    return c.z * lerp( vec3(1.0), rgb, c.y);
}

float hk_equivalent_luminance(float3 sRGB) {
    const HelmholtzKohlrauschEffect hk = hk_from_sRGB(sRGB);
    return srgb_to_equivalent_luminance(hk, sRGB);
}

vec3 compress_stimulus(ShaderInput shader_input) {
    shader_input.uv.x = frac(-shader_input.uv.x - 0.14);
    const float2 quant = float2(42, 24);
    
    const float2 uv = floor(shader_input.uv * quant) / quant;
    //const float2 uv = shader_input.uv;

    float h = uv.x;
    if (frac(uv.x * 20.0 + 0.3) > 0.85) {
        //h = frac(h + 0.5);
    }
    vec3 res = hsv2rgb(float3(h, 0.999, 1.0));
    //return res * smoothstep(1.0, 0.0, uv.y);

    res.x = sRGB_OETF(res.x);
    res.y = sRGB_OETF(res.y);
    res.z = sRGB_OETF(res.z);

    const float desaturation = 0.0;
    res = lerp(res, sRGB_to_luminance(res).xxx, desaturation);

    //return res;
    //res *= 1.0 - uv.y;

    const float3 hsv_output = res;

    //res = lerp(res, res.yyy, 0.5);

#if 0
    if (frac(shader_input.uv.x * 20.0 + 0.3) < 0.7) {
        res = 1.0.xxx;
    }
#endif

    for (int i = 0; i < 2; ++i) {
        res /= hk_equivalent_luminance(res);
    }
    
    res *= pow(smoothstep(1.0, 0.0, uv.y), 1.5) * 6;

#if 1
    res = sRGB_display_transform(res);
#endif

    if (true) {
        float h = shader_input.uv.x;
        vec3 hsv_output = hsv2rgb(float3(h, 0.999, 1.0));
        hsv_output.x = sRGB_OETF(hsv_output.x);
        hsv_output.y = sRGB_OETF(hsv_output.y);
        hsv_output.z = sRGB_OETF(hsv_output.z);
        
        hsv_output = lerp(hsv_output, sRGB_to_luminance(hsv_output).xxx, desaturation);

        hsv_output /= hk_equivalent_luminance(hsv_output);
        hsv_output /= hk_equivalent_luminance(hsv_output);

        //float equiv = sRGB_to_luminance(hsv_output);
        float equiv = log(1.0 / sRGB_to_luminance(hsv_output)) + 0.1;

        /*float above = (1 - shader_input.uv.y) * 2 > equiv ? 1.0 : 0.0;
        if (dFdy(above) != 0.0 || dFdx(above) != 0.0) {
            res *= 0.1;
        }*/

        if (abs((1 - shader_input.uv.y) * 2 - equiv) < 0.01) {
            res *= 0.1;
        }
    }

    return res;
}
