#include "xyz.hlsl"

// By Paul Malin (https://www.shadertoy.com/view/MstcD7)

#define standardObserver1931_length 81

// Modified from Paul's version:
// CIE 1931 2-deg, XYZ CMFs modified by Judd (1951) and Vos (1978)
// http://cvrl.ioo.ucl.ac.uk/cmfs.htm
const vec3 standardObserver1931[standardObserver1931_length] = vec3[standardObserver1931_length] (
    vec3(0.0026899000, 0.0002000000, 0.0122600000),        // 380 nm
    vec3(0.0053105000, 0.0003955600, 0.0242220000),        // 385 nm
    vec3(0.0107810000, 0.0008000000, 0.0492500000),        // 390 nm
    vec3(0.0207920000, 0.0015457000, 0.0951350000),        // 395 nm
    vec3(0.0379810000, 0.0028000000, 0.1740900000),        // 400 nm
    vec3(0.0631570000, 0.0046562000, 0.2901300000),        // 405 nm
    vec3(0.0999410000, 0.0074000000, 0.4605300000),        // 410 nm
    vec3(0.1582400000, 0.0117790000, 0.7316600000),        // 415 nm
    vec3(0.2294800000, 0.0175000000, 1.0658000000),        // 420 nm
    vec3(0.2810800000, 0.0226780000, 1.3146000000),        // 425 nm
    vec3(0.3109500000, 0.0273000000, 1.4672000000),        // 430 nm
    vec3(0.3307200000, 0.0325840000, 1.5796000000),        // 435 nm
    vec3(0.3333600000, 0.0379000000, 1.6166000000),        // 440 nm
    vec3(0.3167200000, 0.0423910000, 1.5682000000),        // 445 nm
    vec3(0.2888200000, 0.0468000000, 1.4717000000),        // 450 nm
    vec3(0.2596900000, 0.0521220000, 1.3740000000),        // 455 nm
    vec3(0.2327600000, 0.0600000000, 1.2917000000),        // 460 nm
    vec3(0.2099900000, 0.0729420000, 1.2356000000),        // 465 nm
    vec3(0.1747600000, 0.0909800000, 1.1138000000),        // 470 nm
    vec3(0.1328700000, 0.1128400000, 0.9422000000),        // 475 nm
    vec3(0.0919440000, 0.1390200000, 0.7559600000),        // 480 nm
    vec3(0.0569850000, 0.1698700000, 0.5864000000),        // 485 nm
    vec3(0.0317310000, 0.2080200000, 0.4466900000),        // 490 nm
    vec3(0.0146130000, 0.2580800000, 0.3411600000),        // 495 nm
    vec3(0.0048491000, 0.3230000000, 0.2643700000),        // 500 nm
    vec3(0.0023215000, 0.4054000000, 0.2059400000),        // 505 nm
    vec3(0.0092899000, 0.5030000000, 0.1544500000),        // 510 nm
    vec3(0.0292780000, 0.6081100000, 0.1091800000),        // 515 nm
    vec3(0.0637910000, 0.7100000000, 0.0765850000),        // 520 nm
    vec3(0.1108100000, 0.7951000000, 0.0562270000),        // 525 nm
    vec3(0.1669200000, 0.8620000000, 0.0413660000),        // 530 nm
    vec3(0.2276800000, 0.9150500000, 0.0293530000),        // 535 nm
    vec3(0.2926900000, 0.9540000000, 0.0200420000),        // 540 nm
    vec3(0.3622500000, 0.9800400000, 0.0133120000),        // 545 nm
    vec3(0.4363500000, 0.9949500000, 0.0087823000),        // 550 nm
    vec3(0.5151300000, 1.0001000000, 0.0058573000),        // 555 nm
    vec3(0.5974800000, 0.9950000000, 0.0040493000),        // 560 nm
    vec3(0.6812100000, 0.9787500000, 0.0029217000),        // 565 nm
    vec3(0.7642500000, 0.9520000000, 0.0022771000),        // 570 nm
    vec3(0.8439400000, 0.9155800000, 0.0019706000),        // 575 nm
    vec3(0.9163500000, 0.8700000000, 0.0018066000),        // 580 nm
    vec3(0.9770300000, 0.8162300000, 0.0015449000),        // 585 nm
    vec3(1.0230000000, 0.7570000000, 0.0012348000),        // 590 nm
    vec3(1.0513000000, 0.6948300000, 0.0011177000),        // 595 nm
    vec3(1.0550000000, 0.6310000000, 0.0009056400),        // 600 nm
    vec3(1.0362000000, 0.5665400000, 0.0006946700),        // 605 nm
    vec3(0.9923900000, 0.5030000000, 0.0004288500),        // 610 nm
    vec3(0.9286100000, 0.4417200000, 0.0003181700),        // 615 nm
    vec3(0.8434600000, 0.3810000000, 0.0002559800),        // 620 nm
    vec3(0.7398300000, 0.3205200000, 0.0001567900),        // 625 nm
    vec3(0.6328900000, 0.2650000000, 0.0000976940),        // 630 nm
    vec3(0.5335100000, 0.2170200000, 0.0000689440),        // 635 nm
    vec3(0.4406200000, 0.1750000000, 0.0000511650),        // 640 nm
    vec3(0.3545300000, 0.1381200000, 0.0000360160),        // 645 nm
    vec3(0.2786200000, 0.1070000000, 0.0000242380),        // 650 nm
    vec3(0.2148500000, 0.0816520000, 0.0000169150),        // 655 nm
    vec3(0.1616100000, 0.0610000000, 0.0000119060),        // 660 nm
    vec3(0.1182000000, 0.0443270000, 0.0000081489),        // 665 nm
    vec3(0.0857530000, 0.0320000000, 0.0000056006),        // 670 nm
    vec3(0.0630770000, 0.0234540000, 0.0000039544),        // 675 nm
    vec3(0.0458340000, 0.0170000000, 0.0000027912),        // 680 nm
    vec3(0.0320570000, 0.0118720000, 0.0000019176),        // 685 nm
    vec3(0.0221870000, 0.0082100000, 0.0000013135),        // 690 nm
    vec3(0.0156120000, 0.0057723000, 0.0000009152),        // 695 nm
    vec3(0.0110980000, 0.0041020000, 0.0000006477),        // 700 nm
    vec3(0.0079233000, 0.0029291000, 0.0000004635),        // 705 nm
    vec3(0.0056531000, 0.0020910000, 0.0000003330),        // 710 nm
    vec3(0.0040039000, 0.0014822000, 0.0000002382),        // 715 nm
    vec3(0.0028253000, 0.0010470000, 0.0000001703),        // 720 nm
    vec3(0.0019947000, 0.0007401500, 0.0000001221),        // 725 nm
    vec3(0.0013994000, 0.0005200000, 0.0000000871),        // 730 nm
    vec3(0.0009698000, 0.0003609300, 0.0000000615),        // 735 nm
    vec3(0.0006684700, 0.0002492000, 0.0000000432),        // 740 nm
    vec3(0.0004614100, 0.0001723100, 0.0000000304),        // 745 nm
    vec3(0.0003207300, 0.0001200000, 0.0000000216),        // 750 nm
    vec3(0.0002257300, 0.0000846200, 0.0000000155),        // 755 nm
    vec3(0.0001597300, 0.0000600000, 0.0000000112),        // 760 nm
    vec3(0.0001127500, 0.0000424460, 0.0000000081),        // 765 nm
    vec3(0.0000795130, 0.0000300000, 0.0000000058),        // 770 nm
    vec3(0.0000560870, 0.0000212100, 0.0000000042),        // 775 nm
    vec3(0.0000395410, 0.0000149890, 0.0000000030)        // 780 nm
);

float standardObserver1931_w_min = 380.0;
float standardObserver1931_w_max = 780.0;

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
