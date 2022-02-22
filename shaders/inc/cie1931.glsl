#include "xyz.hlsl"

// By Paul Malin (https://www.shadertoy.com/view/MstcD7)

// Modified from Paul's version:
// https://www.site.uottawa.ca/~edubois/mdsp/data/ciexyz31.txt
#define standardObserver1931_length 95
const float standardObserver1931_w_min = 360.0;
const float standardObserver1931_w_max = 830.0;
const vec3 standardObserver1931[standardObserver1931_length] = vec3[standardObserver1931_length] (
    vec3(0.000129900000, 0.000003917000, 0.000606100000),   // 360 nm
    vec3(0.000232100000, 0.000006965000, 0.001086000000),   // 365 nm
    vec3(0.000414900000, 0.000012390000, 0.001946000000),   // 370 nm
    vec3(0.000741600000, 0.000022020000, 0.003486000000),   // 375 nm
    vec3(0.001368000000, 0.000039000000, 0.006450001000),   // 380 nm
    vec3(0.002236000000, 0.000064000000, 0.010549990000),   // 385 nm
    vec3(0.004243000000, 0.000120000000, 0.020050010000),   // 390 nm
    vec3(0.007650000000, 0.000217000000, 0.036210000000),   // 395 nm
    vec3(0.014310000000, 0.000396000000, 0.067850010000),   // 400 nm
    vec3(0.023190000000, 0.000640000000, 0.110200000000),   // 405 nm
    vec3(0.043510000000, 0.001210000000, 0.207400000000),   // 410 nm
    vec3(0.077630000000, 0.002180000000, 0.371300000000),   // 415 nm
    vec3(0.134380000000, 0.004000000000, 0.645600000000),   // 420 nm
    vec3(0.214770000000, 0.007300000000, 1.039050100000),   // 425 nm
    vec3(0.283900000000, 0.011600000000, 1.385600000000),   // 430 nm
    vec3(0.328500000000, 0.016840000000, 1.622960000000),   // 435 nm
    vec3(0.348280000000, 0.023000000000, 1.747060000000),   // 440 nm
    vec3(0.348060000000, 0.029800000000, 1.782600000000),   // 445 nm
    vec3(0.336200000000, 0.038000000000, 1.772110000000),   // 450 nm
    vec3(0.318700000000, 0.048000000000, 1.744100000000),   // 455 nm
    vec3(0.290800000000, 0.060000000000, 1.669200000000),   // 460 nm
    vec3(0.251100000000, 0.073900000000, 1.528100000000),   // 465 nm
    vec3(0.195360000000, 0.090980000000, 1.287640000000),   // 470 nm
    vec3(0.142100000000, 0.112600000000, 1.041900000000),   // 475 nm
    vec3(0.095640000000, 0.139020000000, 0.812950100000),   // 480 nm
    vec3(0.057950010000, 0.169300000000, 0.616200000000),   // 485 nm
    vec3(0.032010000000, 0.208020000000, 0.465180000000),   // 490 nm
    vec3(0.014700000000, 0.258600000000, 0.353300000000),   // 495 nm
    vec3(0.004900000000, 0.323000000000, 0.272000000000),   // 500 nm
    vec3(0.002400000000, 0.407300000000, 0.212300000000),   // 505 nm
    vec3(0.009300000000, 0.503000000000, 0.158200000000),   // 510 nm
    vec3(0.029100000000, 0.608200000000, 0.111700000000),   // 515 nm
    vec3(0.063270000000, 0.710000000000, 0.078249990000),   // 520 nm
    vec3(0.109600000000, 0.793200000000, 0.057250010000),   // 525 nm
    vec3(0.165500000000, 0.862000000000, 0.042160000000),   // 530 nm
    vec3(0.225749900000, 0.914850100000, 0.029840000000),   // 535 nm
    vec3(0.290400000000, 0.954000000000, 0.020300000000),   // 540 nm
    vec3(0.359700000000, 0.980300000000, 0.013400000000),   // 545 nm
    vec3(0.433449900000, 0.994950100000, 0.008749999000),   // 550 nm
    vec3(0.512050100000, 1.000000000000, 0.005749999000),   // 555 nm
    vec3(0.594500000000, 0.995000000000, 0.003900000000),   // 560 nm
    vec3(0.678400000000, 0.978600000000, 0.002749999000),   // 565 nm
    vec3(0.762100000000, 0.952000000000, 0.002100000000),   // 570 nm
    vec3(0.842500000000, 0.915400000000, 0.001800000000),   // 575 nm
    vec3(0.916300000000, 0.870000000000, 0.001650001000),   // 580 nm
    vec3(0.978600000000, 0.816300000000, 0.001400000000),   // 585 nm
    vec3(1.026300000000, 0.757000000000, 0.001100000000),   // 590 nm
    vec3(1.056700000000, 0.694900000000, 0.001000000000),   // 595 nm
    vec3(1.062200000000, 0.631000000000, 0.000800000000),   // 600 nm
    vec3(1.045600000000, 0.566800000000, 0.000600000000),   // 605 nm
    vec3(1.002600000000, 0.503000000000, 0.000340000000),   // 610 nm
    vec3(0.938400000000, 0.441200000000, 0.000240000000),   // 615 nm
    vec3(0.854449900000, 0.381000000000, 0.000190000000),   // 620 nm
    vec3(0.751400000000, 0.321000000000, 0.000100000000),   // 625 nm
    vec3(0.642400000000, 0.265000000000, 0.000049999990),   // 630 nm
    vec3(0.541900000000, 0.217000000000, 0.000030000000),   // 635 nm
    vec3(0.447900000000, 0.175000000000, 0.000020000000),   // 640 nm
    vec3(0.360800000000, 0.138200000000, 0.000010000000),   // 645 nm
    vec3(0.283500000000, 0.107000000000, 0.000000000000),   // 650 nm
    vec3(0.218700000000, 0.081600000000, 0.000000000000),   // 655 nm
    vec3(0.164900000000, 0.061000000000, 0.000000000000),   // 660 nm
    vec3(0.121200000000, 0.044580000000, 0.000000000000),   // 665 nm
    vec3(0.087400000000, 0.032000000000, 0.000000000000),   // 670 nm
    vec3(0.063600000000, 0.023200000000, 0.000000000000),   // 675 nm
    vec3(0.046770000000, 0.017000000000, 0.000000000000),   // 680 nm
    vec3(0.032900000000, 0.011920000000, 0.000000000000),   // 685 nm
    vec3(0.022700000000, 0.008210000000, 0.000000000000),   // 690 nm
    vec3(0.015840000000, 0.005723000000, 0.000000000000),   // 695 nm
    vec3(0.011359160000, 0.004102000000, 0.000000000000),   // 700 nm
    vec3(0.008110916000, 0.002929000000, 0.000000000000),   // 705 nm
    vec3(0.005790346000, 0.002091000000, 0.000000000000),   // 710 nm
    vec3(0.004106457000, 0.001484000000, 0.000000000000),   // 715 nm
    vec3(0.002899327000, 0.001047000000, 0.000000000000),   // 720 nm
    vec3(0.002049190000, 0.000740000000, 0.000000000000),   // 725 nm
    vec3(0.001439971000, 0.000520000000, 0.000000000000),   // 730 nm
    vec3(0.000999949300, 0.000361100000, 0.000000000000),   // 735 nm
    vec3(0.000690078600, 0.000249200000, 0.000000000000),   // 740 nm
    vec3(0.000476021300, 0.000171900000, 0.000000000000),   // 745 nm
    vec3(0.000332301100, 0.000120000000, 0.000000000000),   // 750 nm
    vec3(0.000234826100, 0.000084800000, 0.000000000000),   // 755 nm
    vec3(0.000166150500, 0.000060000000, 0.000000000000),   // 760 nm
    vec3(0.000117413000, 0.000042400000, 0.000000000000),   // 765 nm
    vec3(0.000083075270, 0.000030000000, 0.000000000000),   // 770 nm
    vec3(0.000058706520, 0.000021200000, 0.000000000000),   // 775 nm
    vec3(0.000041509940, 0.000014990000, 0.000000000000),   // 780 nm
    vec3(0.000029353260, 0.000010600000, 0.000000000000),   // 785 nm
    vec3(0.000020673830, 0.000007465700, 0.000000000000),   // 790 nm
    vec3(0.000014559770, 0.000005257800, 0.000000000000),   // 795 nm
    vec3(0.000010253980, 0.000003702900, 0.000000000000),   // 800 nm
    vec3(0.000007221456, 0.000002607800, 0.000000000000),   // 805 nm
    vec3(0.000005085868, 0.000001836600, 0.000000000000),   // 810 nm
    vec3(0.000003581652, 0.000001293400, 0.000000000000),   // 815 nm
    vec3(0.000002522525, 0.000000910930, 0.000000000000),   // 820 nm
    vec3(0.000001776509, 0.000000641530, 0.000000000000),   // 825 nm
    vec3(0.000001251141, 0.000000451810, 0.000000000000)   // 830 nm
);

const vec2 whiteD65 = vec2(.3127, 0.3290);

vec3 WavelengthToXYZLinear( float fWavelength )
{
    float fPos = ( fWavelength - standardObserver1931_w_min ) / (standardObserver1931_w_max - standardObserver1931_w_min);
    float fIndex = fPos * float(standardObserver1931_length - 1);   // Modified from Paul's version
    float fFloorIndex = floor(fIndex);
    float fBlend = clamp( fIndex - fFloorIndex, 0.0, 1.0 );
    int iIndex0 = int(fFloorIndex);
    int iIndex1 = iIndex0 + 1;
    iIndex1 = min( iIndex1, standardObserver1931_length - 1);

    return mix( standardObserver1931[iIndex0], standardObserver1931[iIndex1], fBlend );
}

vec3 BSpline( const in vec3 a, const in vec3 b, const in vec3 c, const in vec3 d, const in float t)
{
    const mat4 mSplineBasis = mat4( -1.0,  3.0, -3.0, 1.0,
                        3.0, -6.0,  0.0, 4.0,
                       -3.0,  3.0,  3.0, 1.0,
                        1.0,  0.0,  0.0, 0.0) / 6.0; 

    float t2 = t * t;
    vec4 T = vec4(t2 * t, t2, t, 1.0);

    vec4 vWeights = T * mSplineBasis;

    vec3 vResult;

    vec4 vCoeffsX = vec4(a.x, b.x, c.x, d.x);
    vec4 vCoeffsY = vec4(a.y, b.y, c.y, d.y);
    vec4 vCoeffsZ = vec4(a.z, b.z, c.z, d.z);

    vResult.x = dot(vWeights, vCoeffsX);
    vResult.y = dot(vWeights, vCoeffsY);
    vResult.z = dot(vWeights, vCoeffsZ);

    return vResult;
}

vec3 WavelengthToXYZSpline( float fWavelength )
{
    float fPos = ( fWavelength - standardObserver1931_w_min ) / (standardObserver1931_w_max - standardObserver1931_w_min);
    float fIndex = fPos * float(standardObserver1931_length - 1);   // Modified from Paul's version
    float fFloorIndex = floor(fIndex);
    float fBlend = clamp( fIndex - fFloorIndex, 0.0, 1.0 );

    int iIndex1 = int(fFloorIndex);
    int iIndex0 = iIndex1 - 1;
    int iIndex2 = iIndex1 + 1;
    int iIndex3 = iIndex1 + 2;

    iIndex0 = clamp( iIndex0, 0, standardObserver1931_length - 1 );
    iIndex1 = clamp( iIndex1, 0, standardObserver1931_length - 1 );
    iIndex2 = clamp( iIndex2, 0, standardObserver1931_length - 1 );
    iIndex3 = clamp( iIndex3, 0, standardObserver1931_length - 1 );
    
    vec3 vA = standardObserver1931[iIndex0];
    vec3 vB = standardObserver1931[iIndex1];
    vec3 vC = standardObserver1931[iIndex2];
    vec3 vD = standardObserver1931[iIndex3];

    return BSpline( vA, vB, vC, vD, fBlend );    
}


struct Chromaticities
{
    vec2 R, G, B, W;
};
    
const Chromaticities Primaries_Rec709 = Chromaticities(
        vec2( 0.6400, 0.3300 ), // R
        vec2( 0.3000, 0.6000 ), // G
        vec2( 0.1500, 0.0600 ),  // B
        vec2( 0.3127, 0.3290 ) ); // W

mat3 RGBtoXYZ( Chromaticities chroma )
{
    // xyz is a projection of XYZ co-ordinates onto to the plane x+y+z = 1
    // so we can reconstruct 'z' from x and y
    
    vec3 R_xyz = CIE_xy_to_xyz( chroma.R );
    vec3 G_xyz = CIE_xy_to_xyz( chroma.G );
    vec3 B_xyz = CIE_xy_to_xyz( chroma.B );
    vec3 W_xyz = CIE_xy_to_xyz( chroma.W );
    
    // We want vectors in the directions R, G and B to form the basis of
    // our matrix...
    
 mat3 mPrimaries = mat3 ( R_xyz, G_xyz, B_xyz );
    
    // but we want to scale R,G and B so they result in the
    // direction W when the matrix is multiplied by (1,1,1)
    
    vec3 W_XYZ = W_xyz / W_xyz.y;
    vec3 vScale = inverse( mPrimaries ) * W_XYZ;
    
    return transpose( mat3( 
        R_xyz * vScale.r, 
        G_xyz * vScale.g, 
        B_xyz * vScale.b ) );
}

mat3 XYZtoRGB( Chromaticities chroma )
{
    return inverse( RGBtoXYZ(chroma) );
}

mat3 Convert( Chromaticities a, Chromaticities b )
{
    return RGBtoXYZ( a ) * XYZtoRGB( b );
}
