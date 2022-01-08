#define float2 vec2
#define float3 vec3
#define float4 vec4
#define static
#define mul(A, B) ((A) * (B))
#define atan2(y, x) atan(y, x)
#define lerp(a, b, t) mix(a, b, t)
#define saturate(a) clamp(a, 0.0, 1.0)

#define float3x3(a, b, c, d, e, f, g, h, i) transpose(mat3(a, b, c, d, e, f, g, h, i))
