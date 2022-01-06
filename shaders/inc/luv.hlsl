// From https://github.com/williammalo/hsluv-glsl/blob/master/hsluv-glsl.fsh

float hsluv_yToL(float Y){
    return Y <= 0.0088564516790356308 ? Y * 903.2962962962963 : 116.0 * pow(max(0.0, Y), 1.0 / 3.0) - 16.0;
}

float hsluv_lToY(float L) {
    return L <= 8.0 ? L / 903.2962962962963 : pow((L + 16.0) / 116.0, 3.0);
}

float3 xyzToLuv(float3 tuple){
    float X = tuple.x;
    float Y = tuple.y;
    float Z = tuple.z;

    float L = hsluv_yToL(Y);
    
    float div = 1./dot(tuple,float3(1,15,3)); 

    return float3(
        1.,
        (52. * (X*div) - 2.57179),
        (117.* (Y*div) - 6.08816)
    ) * L;
}

float3 luvToXyz(float3 tuple) {
    float L = tuple.x;

    float U = tuple.y / (13.0 * L) + 0.19783000664283681;
    float V = tuple.z / (13.0 * L) + 0.468319994938791;

    float Y = hsluv_lToY(L);
    float X = 2.25 * U * Y / V;
    float Z = (3./V - 5.)*Y - (X/3.);

    return float3(X, Y, Z);
}

float2 cie_xy_to_Luv_uv(float2 xy) {
    return xy * float2(4.0, 9.0) / (-2.0 * xy.x + 12.0 * xy.y + 3.0);
}

float2 cie_XYZ_to_Luv_uv(float3 xyz) {
    return xyz.xy * float2(4.0, 9.0) / dot(xyz, float3(1.0, 15.0, 3.0));
}
