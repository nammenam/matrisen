import common;

// ===================================================
// Slug Algorithm - Vector Graphics Renderer
// Translated to Slang by Claude and Brage
// Original: Copyright 2017, Eric Lengyel (MIT License)
// ===================================================

#define kLogBandTextureWidth 12

// ==========================================
// SLUG DATA STRUCTURES
// ==========================================

struct SlugPushConstants {
    float4x4 mvp;           // Model-view-projection matrix
    float4   viewport;      // Viewport dimensions in pixels
};

[[vk::push_constant]]
SlugPushConstants push;

// Textures for curve and band data
[[vk::binding(1, 0)]] Texture2D<float4>  curveTexture;
[[vk::binding(2, 0)]] Texture2D<uint4>   bandTexture;
[[vk::binding(3, 0)]] SamplerState       slugSampler;

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

// ==========================================
// VERTEX SHADER
// ==========================================

[shader("vertex")]
SlugVaryings slugVertex(SlugVertex input) {
    SlugVaryings output;

    float2 p;
    output.texcoord = SlugDilate(
        input.pos, input.tex, input.jac,
        push.mvp[0], push.mvp[1], push.mvp[3],
        push.viewport.xy,
        p
    );

    output.position.x = p.x * push.mvp[0].x + p.y * push.mvp[0].y + push.mvp[0].w;
    output.position.y = p.x * push.mvp[1].x + p.y * push.mvp[1].y + push.mvp[1].w;
    output.position.z = p.x * push.mvp[2].x + p.y * push.mvp[2].y + push.mvp[2].w;
    output.position.w = p.x * push.mvp[3].x + p.y * push.mvp[3].y + push.mvp[3].w;

    SlugUnpack(input.tex, input.bnd, output.banding, output.glyph);
    output.color = input.col;
    return output;
}

// ==========================================
// FRAGMENT HELPERS
// ==========================================

// Texel fetch helper - matches HLSL Load semantics
float4 CurveLoad(int2 coord) {
    return curveTexture.Load(int3(coord, 0));
}

uint4 BandLoad(int2 coord) {
    return bandTexture.Load(int3(coord, 0));
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

float SlugRender(float2 renderCoord, float4 bandTransform, int4 glyphData) {
    float2 emsPerPixel  = fwidth(renderCoord);
    float2 pixelsPerEm  = 1.0 / emsPerPixel;

    int2 bandMax    = glyphData.zw;
    bandMax.y      &= 0x00FF;

    int2 bandIndex  = clamp(
        int2(renderCoord * bandTransform.xy + bandTransform.zw),
        int2(0, 0),
        bandMax
    );
    int2 glyphLoc   = glyphData.xy;

    float xcov = 0.0;
    float xwgt = 0.0;

    // Horizontal band
    uint2 hbandData = BandLoad(int2(glyphLoc.x + bandIndex.y, glyphLoc.y)).xy;
    int2  hbandLoc  = CalcBandLoc(glyphLoc, hbandData.y);

    for (int ci = 0; ci < int(hbandData.x); ci++) {
        int2   curveLoc = int2(BandLoad(int2(hbandLoc.x + ci, hbandLoc.y)).xy);
        float4 p12      = CurveLoad(curveLoc) - float4(renderCoord, renderCoord);
        float2 p3       = CurveLoad(int2(curveLoc.x + 1, curveLoc.y)).xy - renderCoord;

        if (max(max(p12.x, p12.z), p3.x) * pixelsPerEm.x < -0.5) break;

        uint code = CalcRootCode(p12.y, p12.w, p3.y);
        if (code != 0u) {
            float2 r = SolveHorizPoly(p12, p3) * pixelsPerEm.x;

            if ((code & 1u) != 0u) {
                xcov += saturate(r.x + 0.5);
                xwgt  = max(xwgt, saturate(1.0 - abs(r.x) * 2.0));
            }
            if (code > 1u) {
                xcov -= saturate(r.y + 0.5);
                xwgt  = max(xwgt, saturate(1.0 - abs(r.y) * 2.0));
            }
        }
    }

    float ycov = 0.0;
    float ywgt = 0.0;

    // Vertical band
    uint2 vbandData = BandLoad(int2(glyphLoc.x + bandMax.y + 1 + bandIndex.x, glyphLoc.y)).xy;
    int2  vbandLoc  = CalcBandLoc(glyphLoc, vbandData.y);

    for (int ci = 0; ci < int(vbandData.x); ci++) {
        int2   curveLoc = int2(BandLoad(int2(vbandLoc.x + ci, vbandLoc.y)).xy);
        float4 p12      = CurveLoad(curveLoc) - float4(renderCoord, renderCoord);
        float2 p3       = CurveLoad(int2(curveLoc.x + 1, curveLoc.y)).xy - renderCoord;

        if (max(max(p12.y, p12.w), p3.y) * pixelsPerEm.y < -0.5) break;

        uint code = CalcRootCode(p12.x, p12.z, p3.x);
        if (code != 0u) {
            float2 r = SolveVertPoly(p12, p3) * pixelsPerEm.y;

            if ((code & 1u) != 0u) {
                ycov -= saturate(r.x + 0.5);
                ywgt  = max(ywgt, saturate(1.0 - abs(r.x) * 2.0));
            }
            if (code > 1u) {
                ycov += saturate(r.y + 0.5);
                ywgt  = max(ywgt, saturate(1.0 - abs(r.y) * 2.0));
            }
        }
    }

    return CalcCoverage(xcov, ycov, xwgt, ywgt, glyphData.w);
}

// ==========================================
// FRAGMENT SHADER
// ==========================================

[shader("fragment")]
float4 slugFragment(SlugVaryings input) : SV_Target {
    float coverage = SlugRender(input.texcoord, input.banding, input.glyph);
    return input.color * coverage;
}
