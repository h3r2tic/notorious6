// From https://github.com/botman99/ColorBlindSimulation

float3 RgbToLms(float3 colRgb)
{
	float3 colLms;
	colLms.x = 0.31399022 * colRgb.x + 0.63951294 * colRgb.y + 0.04649755 * colRgb.z;
	colLms.y = 0.15537241 * colRgb.x + 0.75789446 * colRgb.y + 0.08670142 * colRgb.z;
	colLms.z = 0.01775239 * colRgb.x + 0.10944209 * colRgb.y + 0.87256922 * colRgb.z;
	return colLms;
}

float3 LmsToRgb(float3 colLms)
{
	float3 colRgb;
	colRgb.x =  5.47221206 * colLms.x - 4.64196010 * colLms.y + 0.16963708 * colLms.z,
	colRgb.y = -1.12524190 * colLms.x + 2.29317094 * colLms.y - 0.16789520 * colLms.z,
	colRgb.z =  0.02980165 * colLms.x - 0.19318073 * colLms.y + 1.16364789 * colLms.z;
	return colRgb;
}
