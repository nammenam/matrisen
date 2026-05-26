import common;
// ===================================================
// Slug Algorithm - Vector Graphics Renderer
// Original: Copyright 2017, Eric Lengyel (MIT License)
// ===================================================

#define kLogBandTextureWidth 12

// ==========================================
// VERTEX INPUT / OUTPUT
// ==========================================

struct SlugVertex {
    float4 pos : ATTRIB0;   // xy = object position, zw = normal
    float4 tex : ATTRIB1;   // xy = em-space coords, zw = glyph/band data
    float4 jac : ATTRIB2;   // inverse Jacobian (00, 01, 10, 11)
    float4 bnd : ATTRIB3;   // band scale x, scale y, offset x, offset y
    float4 col : ATTRIB4;   // vertex color rgba
};

struct SlugVaryings {
    float4          position : SV_Position;
    float4          color    : COLOR;
    float2          texcoord : TEXCOORD0;
    nointerpolation float4 banding  : TEXCOORD1;  // band scale + offset, flat over glyph
    nointerpolation int4   glyph    : TEXCOORD2;  // glyph data coords + band max + flags
};

// ==========================================
// SHARED HELPERS
// ==========================================

void SlugUnpack(float4 tex, float4 bnd, out float4 vbnd, out int4 vgly) {
    uint2 g = asuint(tex.zw);
    vgly = int4(
        int(g.x & 0xFFFFu),
        int(g.x >> 16u),
        int(g.y & 0xFFFFu),
        int(g.y >> 16u)
    );
    vbnd = bnd;
}

float2 SlugDilate(
    float4 pos, float4 tex, float4 jac,
    float4 m0, float4 m1, float4 m3,
    float2 dim,
    out float2 vpos)
{
    float2 n = normalize(pos.zw);
    float s  = dot(m3.xy, pos.xy) + m3.w;
    float t  = dot(m3.xy, n);

    float u = (s * dot(m0.xy, n) - t * (dot(m0.xy, pos.xy) + m0.w)) * dim.x;
    float v = (s * dot(m1.xy, n) - t * (dot(m1.xy, pos.xy) + m1.w)) * dim.y;

    float s2 = s * s;
    float st = s * t;
    float uv = u * u + v * v;
    float2 d = pos.zw * (s2 * (st + sqrt(uv)) / (uv - st * st));

    vpos = pos.xy + d;
    return float2(
        tex.x + dot(d, jac.xy),
        tex.y + dot(d, jac.zw)
    );
}

uint CalcRootCode(float y1, float y2, float y3) {
    uint i1 = asuint(y1) >> 31u;
    uint i2 = asuint(y2) >> 30u;
    uint i3 = asuint(y3) >> 29u;

    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift      = (i3 & 4u) | (shift & ~4u);

    return ((0x2E74u >> shift) & 0x0101u);
}

float2 SolveHorizPoly(float4 p12, float2 p3) {
    float2 a  = p12.xy - p12.zw * 2.0 + p3;
    float2 b  = p12.xy - p12.zw;
    float  ra = 1.0 / a.y;
    float  rb = 0.5 / b.y;

    float d  = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
    float t1 = (b.y - d) * ra;
    float t2 = (b.y + d) * ra;

    if (abs(a.y) < 1.0 / 65536.0) t1 = t2 = p12.y * rb;

    return float2(
        (a.x * t1 - b.x * 2.0) * t1 + p12.x,
        (a.x * t2 - b.x * 2.0) * t2 + p12.x
    );
}

float2 SolveVertPoly(float4 p12, float2 p3) {
    float2 a  = p12.xy - p12.zw * 2.0 + p3;
    float2 b  = p12.xy - p12.zw;
    float  ra = 1.0 / a.x;
    float  rb = 0.5 / b.x;

    float d  = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
    float t1 = (b.x - d) * ra;
    float t2 = (b.x + d) * ra;

    if (abs(a.x) < 1.0 / 65536.0) t1 = t2 = p12.x * rb;

    return float2(
        (a.y * t1 - b.y * 2.0) * t1 + p12.y,
        (a.y * t2 - b.y * 2.0) * t2 + p12.y
    );
}

int2 CalcBandLoc(int2 glyphLoc, uint offset) {
    int2 bandLoc = int2(glyphLoc.x + int(offset), glyphLoc.y);
    bandLoc.y   += bandLoc.x >> kLogBandTextureWidth;
    bandLoc.x   &= (1 << kLogBandTextureWidth) - 1;
    return bandLoc;
}

float CalcCoverage(float xcov, float ycov, float xwgt, float ywgt, int flags) {
    float coverage = max(
        abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0),
        min(abs(xcov), abs(ycov))
    );

    // Nonzero fill rule (add SLUG_EVENODD variant if you need it later)
    coverage = saturate(coverage);

    return coverage;
}


// ==========================================
// VERTEX SHADER
// ==========================================
// // TODO FIX this is broken. Make compute shader that creates meshes for this
// the compute shader is also usefull for the ui meshshaded varient if we want to cahce the mesh
[shader("vertex")]
SlugVaryings slugVertex(uint vertexId: SV_VertexID) {
    SlugVaryings output;

    // Generate a fullscreen triangle without needing a vertex buffer!
    float2 uvs = float2((vertexId << 1) & 2, vertexId & 2);
    output.position = float4(uvs * 2.0f - 1.0f, 0.0f, 1.0f);

    // Scale the UVs to a 0 to 1000 coordinate system for easy curve placement
    output.texcoord = uvs;
    output.color = float4(0.2, 0.8, 1.0, 1.0); // Nice Slug Blue

    return output;
}

// Helper to evaluate a standard Bezier curve (P0, P1, P2) using Slug's root math
void EvaluateCurve(float2 P0, float2 P1, float2 P2, float2 renderCoord,
                   inout float xcov, inout float xwgt, inout float ycov, inout float ywgt) {

    // Magic unpacking: p12 holds P0 and P1. p3 holds P2.
    float4 p12 = float4(P0, P1) - float4(renderCoord, renderCoord);
    float2 p3  = P2 - renderCoord;

    // 1. Horizontal Coverage
    uint hcode = CalcRootCode(p12.y, p12.w, p3.y);
    if (hcode != 0u) {
        float2 r = SolveHorizPoly(p12, p3); // Assume 1 pixel per em for this test
        if ((hcode & 1u) != 0u) {
            xcov += saturate(r.x + 0.5);
            xwgt  = max(xwgt, saturate(1.0 - abs(r.x) * 2.0));
        }
        if (hcode > 1u) {
            xcov -= saturate(r.y + 0.5);
            xwgt  = max(xwgt, saturate(1.0 - abs(r.y) * 2.0));
        }
    }

    // 2. Vertical Coverage
    uint vcode = CalcRootCode(p12.x, p12.z, p3.x);
    if (vcode != 0u) {
        float2 r = SolveVertPoly(p12, p3);
        if ((vcode & 1u) != 0u) {
            ycov -= saturate(r.x + 0.5);
            ywgt  = max(ywgt, saturate(1.0 - abs(r.x) * 2.0));
        }
        if (vcode > 1u) {
            ycov += saturate(r.y + 0.5);
            ywgt  = max(ywgt, saturate(1.0 - abs(r.y) * 2.0));
        }
    }
}

// ==========================================
// FRAGMENT SHADER
// ==========================================

[shader("fragment")]
float4 slugFragment(SlugVaryings input) : SV_Target {
    UIElement* ui = scene.addresses.uiobjects.UIBuffer; // Assuming only 1 UI object for now

    float xcov = 0.0, xwgt = 0.0;
    float ycov = 0.0, ywgt = 0.0;

    // 2. Fetch the curve count (you could store this in UIData or as a vertex input)
    uint vertexCount = ui.vertexCount;

    // 3. Loop over the curves dynamically via BDA!
    for(uint i = 0; i < vertexCount; i+=3) {
        // A standard Slug curve takes up two float4s in memory (P0, P1, P2 packed)
        float3 P0 = ui.vertexBuffer[i].position;
        float3 P1 = ui.vertexBuffer[i+1].position;
        float3 P2 = ui.vertexBuffer[i+2].position;


        EvaluateCurve(P0.xy, P1.xy, P2.xy, input.texcoord, xcov, xwgt, ycov, ywgt);
    }
    // Calculate final coverage using Slug's exact logic
    float coverage = max(
        abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0),
        min(abs(xcov), abs(ycov))
    );
    coverage = saturate(coverage);

    // If coverage is 0, discard the pixel to show the background
    if (coverage <= 0.0) discard;

    return float4(input.color.rgb, coverage);
}
