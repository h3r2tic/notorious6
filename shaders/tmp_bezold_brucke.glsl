#include "inc/prelude.glsl"
#include "inc/cie1931.glsl"
#include "inc/ipt.hlsl"
#include "inc/bezold_brucke.hlsl"
#include "inc/bezold_brucke_brute_force.glsl"

#define IMAGE_PASSTHROUGH 0

vec3 compress_stimulus(ShaderInput shader_input) {
    //float wavelength = lerp(standardObserver1931_w_min, standardObserver1931_w_max, shader_input.uv.x);
    float wavelength = lerp(410, 650, shader_input.uv.x);    

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

    const float bb_shift = XYZ_to_BB_shift_nm(XYZ);

    if (abs(ordinate - bb_shift) < 0.05) {
        return 1.1.xxx;
    }

    {
        vec3 shifted_XYZ = BB_shift_XYZ(XYZ, 1.0);
        //vec3 shifted_XYZ = BB_shift_brute_force_XYZ(XYZ, 1.0);
                
        vec3 shifted_sRGB = shifted_XYZ * XYZtoRGB(Primaries_Rec709);

        float shifted_wavelength = xy_to_dominant_wavelength(CIE_XYZ_to_xyY(shifted_XYZ).xy);
        float wavelength_shift = shifted_wavelength - wavelength;

        if (abs(ordinate - wavelength_shift) < 0.08) {
            return 1.0.xxx;
        }

        #if !IMAGE_PASSTHROUGH
            if (shader_input.uv.y > 0.7) {
                return shifted_sRGB * 0.3;
            }
        #endif
    }

    if (shader_input.uv.y > 0.3) {
        float3 xyY = wavelength_to_xyY(wavelength + bb_shift);
        XYZ = CIE_xyY_to_XYZ(xyY);
    } else {
        //XYZ *= 2.0;
    }

    vec3 sRGB = XYZ * XYZtoRGB(Primaries_Rec709);

    #if IMAGE_PASSTHROUGH
        return shader_input.stimulus * 0.05;
    #endif

    return sRGB * 0.3;
    //return abs(wavelength - wavelength1).xxx;
}
