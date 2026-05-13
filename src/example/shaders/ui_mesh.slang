import common;

#define kLogBandTextureWidth 12

// struct UIVertex {
//     float4 pos : ATTRIB0;   // xy = object position, zw = normal
//     float4 tex : ATTRIB1;   // xy = em-space coords, zw = glyph/band data
//     float4 jac : ATTRIB2;   // inverse Jacobian (00, 01, 10, 11)
//     float4 bnd : ATTRIB3;   // band scale x, scale y, offset x, offset y
//     float4 col : ATTRIB4;   // vertex color rgba
// };

struct UIVaryings {
    float4 position : SV_Position;
    float2 texcoord : TEXCOORD0;
    nointerpolation uint elementIndex : ELEMENT_INDEX; // Just pass the ID!
};

void SlugUnpack(float4 tex, float4 bnd, out float4 vbnd, out int4 vgly) {
  uint2 g = asuint(tex.zw);
  vgly = int4(int(g.x & 0xFFFFu), int(g.x >> 16u), int(g.y & 0xFFFFu),
              int(g.y >> 16u));
  vbnd = bnd;
}

float2 SlugDilate(float4 pos, float4 tex, float4 jac, float4 m0, float4 m1,
                  float4 m3, float2 dim, out float2 vpos) {
  float2 n = normalize(pos.zw);
  float s = dot(m3.xy, pos.xy) + m3.w;
  float t = dot(m3.xy, n);

  float u = (s * dot(m0.xy, n) - t * (dot(m0.xy, pos.xy) + m0.w)) * dim.x;
  float v = (s * dot(m1.xy, n) - t * (dot(m1.xy, pos.xy) + m1.w)) * dim.y;

  float s2 = s * s;
  float st = s * t;
  float uv = u * u + v * v;
  float2 d = pos.zw * (s2 * (st + sqrt(uv)) / (uv - st * st));

  vpos = pos.xy + d;
  return float2(tex.x + dot(d, jac.xy), tex.y + dot(d, jac.zw));
}

uint CalcRootCode(float y1, float y2, float y3) {
  uint i1 = asuint(y1) >> 31u;
  uint i2 = asuint(y2) >> 30u;
  uint i3 = asuint(y3) >> 29u;

  uint shift = (i2 & 2u) | (i1 & ~2u);
  shift = (i3 & 4u) | (shift & ~4u);

  return ((0x2E74u >> shift) & 0x0101u);
}

float2 SolveHorizPoly(float4 p12, float2 p3) {
  float2 a = p12.xy - p12.zw * 2.0 + p3;
  float2 b = p12.xy - p12.zw;
  float ra = 1.0 / a.y;
  float rb = 0.5 / b.y;

  float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
  float t1 = (b.y - d) * ra;
  float t2 = (b.y + d) * ra;

  if (abs(a.y) < 1.0 / 65536.0)
    t1 = t2 = p12.y * rb;

  return float2((a.x * t1 - b.x * 2.0) * t1 + p12.x,
                (a.x * t2 - b.x * 2.0) * t2 + p12.x);
}

float2 SolveVertPoly(float4 p12, float2 p3) {
  float2 a = p12.xy - p12.zw * 2.0 + p3;
  float2 b = p12.xy - p12.zw;
  float ra = 1.0 / a.x;
  float rb = 0.5 / b.x;

  float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
  float t1 = (b.x - d) * ra;
  float t2 = (b.x + d) * ra;

  if (abs(a.x) < 1.0 / 65536.0)
    t1 = t2 = p12.x * rb;

  return float2((a.y * t1 - b.y * 2.0) * t1 + p12.y,
                (a.y * t2 - b.y * 2.0) * t2 + p12.y);
}

int2 CalcBandLoc(int2 glyphLoc, uint offset) {
  int2 bandLoc = int2(glyphLoc.x + int(offset), glyphLoc.y);
  bandLoc.y += bandLoc.x >> kLogBandTextureWidth;
  bandLoc.x &= (1 << kLogBandTextureWidth) - 1;
  return bandLoc;
}

float CalcCoverage(float xcov, float ycov, float xwgt, float ywgt, int flags) {
  float coverage =
      max(abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0),
          min(abs(xcov), abs(ycov)));

  // Nonzero fill rule (add SLUG_EVENODD variant if you need it later)
  coverage = saturate(coverage);

  return coverage;
} // Helper to evaluate a standard Bezier curve (P0, P1, P2) using Slug's root

void EvaluateCurve(float2 P0, float2 P1, float2 P2, float2 renderCoord,
                   inout float xcov, inout float xwgt, inout float ycov,
                   inout float ywgt) {

  // Magic unpacking: p12 holds P0 and P1. p3 holds P2.
  float4 p12 = float4(P0, P1) - float4(renderCoord, renderCoord);
  float2 p3 = P2 - renderCoord;

  // 1. Horizontal Coverage
  uint hcode = CalcRootCode(p12.y, p12.w, p3.y);
  if (hcode != 0u) {
    float2 r = SolveHorizPoly(p12, p3); // Assume 1 pixel per em for this test
    if ((hcode & 1u) != 0u) {
      xcov += saturate(r.x + 0.5);
      xwgt = max(xwgt, saturate(1.0 - abs(r.x) * 2.0));
    }
    if (hcode > 1u) {
      xcov -= saturate(r.y + 0.5);
      xwgt = max(xwgt, saturate(1.0 - abs(r.y) * 2.0));
    }
  }

  // 2. Vertical Coverage
  uint vcode = CalcRootCode(p12.x, p12.z, p3.x);
  if (vcode != 0u) {
    float2 r = SolveVertPoly(p12, p3);
    if ((vcode & 1u) != 0u) {
      ycov -= saturate(r.x + 0.5);
      ywgt = max(ywgt, saturate(1.0 - abs(r.x) * 2.0));
    }
    if (vcode > 1u) {
      ycov += saturate(r.y + 0.5);
      ywgt = max(ywgt, saturate(1.0 - abs(r.y) * 2.0));
    }
  }
}

// Exact distance to a Quadratic Bezier curve
float sdBezier(float2 pos, float2 A, float2 B, float2 C) {
    float2 a = B - A;
    float2 b = A - 2.0 * B + C;
    float2 c = a * 2.0;
    float2 d = A - pos;

    float kk = 1.0 / max(dot(b,b), 0.0001); // Prevent divide by zero
    float kx = kk * dot(a,b);
    float ky = kk * (2.0 * dot(a,a) + dot(d,b)) / 3.0;
    float kz = kk * dot(d,a);

    float res = 0.0;
    float p = ky - kx * kx;
    float p3 = p * p * p;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * p3;

    if(h >= 0.0) {
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0;
        float2 uv = sign(x) * pow(abs(x), float2(1.0/3.0, 1.0/3.0));
        float t = uv.x + uv.y - kx;
        t = clamp(t, 0.0, 1.0);
        float2 qos = d + (c + b * t) * t;
        res = length(qos);
    } else {
        float z = sqrt(-p);
        float v = acos(q / (p * z * 2.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.732050808;
        float3 t = float3(m + m, -n - m, n - m) * z - kx;
        t = clamp(t, 0.0, 1.0);
        float2 qos = d + (c + b * t.x) * t.x;
        float dis = dot(qos,qos);
        res = dis;
        qos = d + (c + b * t.y) * t.y;
        dis = dot(qos,qos);
        res = min(res,dis);
        res = sqrt(res);
    }
    return res;
}

#define UI_TYPE_RECT 0
#define UI_TYPE_BEZIER_CURVE 1

#define MAX_VERTS 64
#define MAX_PRIMS 64

[shader("mesh")]
[outputtopology("triangle")]
[numthreads(32, 1, 1)]
void uiMesh(uint workgroupID : SV_GroupID, uint localID : SV_GroupIndex,
            out indices uint3 prims[MAX_PRIMS],
            out vertices UIVaryings verts[MAX_VERTS]) {

    if (workgroupID >= scene.uielemCount) return;

    UIInstance instance = scene.uiobjects[workgroupID];
    UIElement *ui = instance.UIBuffer;
    uint type = instance.type;

    if (type == UI_TYPE_BEZIER_CURVE) {
        float2 P0 = ui.vertexBuffer[0].position.xy;
        float2 P1 = ui.vertexBuffer[1].position.xy;
        float2 P2 = ui.vertexBuffer[2].position.xy;

        float strokeWidth = 3.0;
        float dist = length(P2 - P0) + length(P1 - P0);
        uint segments = clamp(uint(dist / 15.0), 2, 14);
        // uint segments = 12;
        float thickness = strokeWidth + 5.0;
        uint vCount = (segments + 1) * 2; // 22 vertices
        uint pCount = segments * 2;       // 20 primitives

        SetMeshOutputCounts(vCount, pCount);

        if (localID < vCount) {
            uint sliceIndex = localID / 2;
            bool isTop = (localID % 2 == 0);
            float t = (float)sliceIndex / (float)segments;

            float invT = 1.0 - t;
            float2 centerPos = (invT * invT * P0) + (2.0 * invT * t * P1) + (t * t * P2);

            // Calculate Tangent and Normal
            float2 tangent = 2.0 * invT * (P1 - P0) + 2.0 * t * (P2 - P1);

            // Safe normalize to prevent NaN if control points overlap
            float len = length(tangent);
            float2 normal = len > 0.0001 ? float2(-tangent.y, tangent.x) / len : float2(0.0, 1.0);

            // MASSIVE THICKNESS FOR TESTING (50 pixels in both directions)
            float2 finalPos = centerPos + (normal * thickness * (isTop ? 1.0 : -1.0));

            // Convert to Screen NDC space
            float2 ndcPos = (finalPos / scene.viewport.xy) * 2.0 - 1.0;

            verts[localID].position = float4(ndcPos, 0.0, 1.0);
            verts[localID].texcoord = float2(t, isTop ? 1.0 : 0.0);
            verts[localID].elementIndex = workgroupID;
        }

        // Build the Quad Strip Winding Order
        if (localID < pCount) {
            uint quadIndex = localID / 2;
            uint vBase = quadIndex * 2;

            if (localID % 2 == 0) {
                prims[localID] = uint3(vBase, vBase + 1, vBase + 2);
            } else {
                prims[localID] = uint3(vBase + 2, vBase + 1, vBase + 3);
            }
        }
    }
}


// ==========================================
// FRAGMENT SHADER STROKE
// ==========================================
[shader("fragment")]
float4 uiFragment(UIVaryings in) : SV_Target {
    UIInstance instance = scene.uiobjects[in.elementIndex];
    UIElement *ui = instance.UIBuffer;

    // Default to discard unless we find a curve we are close to
    float minDistance = 99999.0;

    for (uint i = 0; i < ui.vertexCount; i += 3) {
        if (i + 2 >= ui.vertexCount) break;

        float2 P0 = ui.vertexBuffer[i].position.xy;
        float2 P1 = ui.vertexBuffer[i + 1].position.xy;
        float2 P2 = ui.vertexBuffer[i + 2].position.xy;

        float d = sdBezier(in.position.xy, P0, P1, P2);
        minDistance = min(minDistance, d);
    }

    float strokeWidth = 4.0; // Desired pixel thickness of the line
    float edgeRadius = strokeWidth / 2.0;

    // Calculate anti-aliasing (1 pixel fade at the exact edge)
    float coverage = saturate(edgeRadius - minDistance + 0.5);

    // If the pixel is further away than the stroke width, discard!
    if (coverage <= 0.0) discard;

    return float4(1.0, 1.0, 1.0, coverage);
}
// ==========================================
// FRAGMENT SHADER FILL
// ==========================================
// [shader("fragment")]
// float4 uiFragment(UIVaryings in) : SV_Target {
//     float xcov = 0.0, xwgt = 0.0;
//     float ycov = 0.0, ywgt = 0.0;

//     // 1. Fetch the exact UI instance and element
//     UIInstance instance = scene.uiobjects[in.elementIndex];
//     UIElement *ui = instance.UIBuffer;

//     // 2. Loop through the vertices
//     for (uint i = 0; i < ui.vertexCount; i += 3) {
//         if (i + 2 >= ui.vertexCount) break;

//         float2 P0 = ui.vertexBuffer[i].position.xy;
//         float2 P1 = ui.vertexBuffer[i + 1].position.xy;
//         float2 P2 = ui.vertexBuffer[i + 2].position.xy;

//         // FIXED: Passing in.position.xy (Pixel Coordinates) instead of UVs
//         EvaluateCurve(P0, P1, P2, in.position.xy, xcov, xwgt, ycov, ywgt);
//     }

//     float coverage = max(
//         abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0),
//         min(abs(xcov), abs(ycov))
//     );
//     coverage = saturate(coverage);

//     // If the pixel is outside the math curve, drop it.
//     if (coverage <= 0.0) discard;

//     // Output solid white, but use coverage for the anti-aliased alpha edge!
//     return float4(1.0, 1.0, 1.0, coverage);
// }
