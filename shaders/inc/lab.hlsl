// from Alex Tardiff: http://alextardif.com/Lightness.html

float DegreesToRadians(float degrees) 
{
    return degrees * M_PI / 180.0;
}

float RadiansToDegrees(float radians) 
{
    return radians * (180.0 / M_PI);
}

//Convert RGB with sRGB/Rec.709 primaries to CIE XYZ
//http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
float3 RGBToXYZ(float3 color)
{
    return mul(float3x3(
        0.4124564,  0.3575761,  0.1804375,
        0.2126729,  0.7151522,  0.0721750,
        0.0193339,  0.1191920,  0.9503041
    ), color);
}

//Convert CIE XYZ to RGB with sRGB/Rec.709 primaries
//http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
float3 XYZtoRGB(float3 color)
{
    return mul(float3x3(
         3.2404542, -1.5371385, -0.4985314,
        -0.9692660,  1.8760108,  0.0415560,
         0.0556434, -0.2040259,  1.0572252
    ), color);
}

//http://www.brucelindbloom.com/index.html?Eqn_XYZ_to_Lab.html
float3 XYZToLab(float3 xyz) 
{
    float3 D65 = float3(0.9504, 1.0000, 1.0888);
    
    xyz /= D65;
    xyz = float3(
        xyz.x > 0.008856 ? pow(abs(xyz.x), 1.0 / 3.0) : xyz.x * 7.787 + 16.0 / 116.0,
        xyz.y > 0.008856 ? pow(abs(xyz.y), 1.0 / 3.0) : xyz.y * 7.787 + 16.0 / 116.0,
        xyz.z > 0.008856 ? pow(abs(xyz.z), 1.0 / 3.0) : xyz.z * 7.787 + 16.0 / 116.0
    );

    float l = 116.0 * xyz.y - 16.0;
    float a = 500.0 * (xyz.x - xyz.y);
    float b = 200.0 * (xyz.y - xyz.z);
    
    return float3(l, a, b);
}

// http://www.brucelindbloom.com/index.html?Eqn_Lab_to_XYZ.html
float3 LABToXYZ(float3 lab)
{
	float3 D65 = float3(0.9504, 1.0000, 1.0888);

    float fy = (lab[0] + 16.0) / 116.0;
    float fx = lab[1] / 500.0 + fy;
    float fz = fy - lab[2] / 200.0;
	float3 fxyz = float3(fx, fy, fz);

	float3 xyz = fxyz * fxyz * fxyz;
	return D65 * float3(
        fxyz.x > 0.206893 ? xyz.x : (116.0 * fxyz.x - 16.0) / 903.3,
        fxyz.y > 0.206893 ? xyz.y : (116.0 * fxyz.y - 16.0) / 903.3,
        fxyz.z > 0.206893 ? xyz.z : (116.0 * fxyz.z - 16.0) / 903.3
    );
}

//http://www.brucelindbloom.com/index.html?Eqn_Lab_to_LCH.html
float3 LabToLch(float3 lab) 
{
    float c = sqrt(lab.y * lab.y + lab.z * lab.z);
    float h = atan2(lab.z, lab.y);
    
    if(h >= 0.0)
    {
        h = RadiansToDegrees(h);
    }
    else
    {
        h = RadiansToDegrees(h) + 360.0;
    }
    
    return float3(lab.x, c, h);
}
