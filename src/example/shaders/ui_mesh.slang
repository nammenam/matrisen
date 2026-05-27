// This shader should handle basic UI primitives in 2D and 3D
// circle elipse arc line rect curve bezier spline
// boolean operations stroke fill
// use a combination of meshshading to create meshes of correct size
// use a combo of slug shader and sfd shader
// should handle sharp corners (can utilze the meshshader to aid in that)
// can branch to handle all cases
// Only branch on uniforms or workgroup never on local thread

import common;
import uiprocedures;

// ==========================================
// THE THREE PILLARS OF UI RENDERING
// ==========================================
#define UI_TYPE_ANALYTICAL 0 // SDFs: Rects, Circles, Rounded Boxes
#define UI_TYPE_STROKE 1     // Extruded paths: Bezier borders, Line graphs
#define UI_TYPE_FILL 2       // Vector Graphics: Fonts, SVGs, Winding rules

#define MAX_VERTS 64
#define MAX_PRIMS 64

void emitAnalyticalQuad(uint elementIndex, // Pass this down from uiMesh!
                        UIInstance instance, UIElement *ui, uint localID,
                        out indices uint3 prims[MAX_PRIMS],
                        out vertices UIVaryings verts[MAX_VERTS]) {
  // We only have 1 UI element, so we promise exactly 1 Quad.
  // Thread 0 tells the hardware the exact counts: 4 vertices, 2 primitives.
  if (localID == 0) {
    SetMeshOutputCounts(4, 2);
  }

  // -----------------------------------------------------
  // 4 THREADS WRITE VERTICES
  // -----------------------------------------------------
  if (localID < 4) {
    float2 signs = float2(((localID & 1) != 0) ? 1.0 : -1.0,
                          ((localID & 2) != 0) ? 1.0 : -1.0);
    // Padding for SDF anti-aliasing and stroke thickness
    float padding = (ui.stroke > 0.0 ? ui.stroke : 0.0) + 2.0;
    float2 paddedSize = ui.size + float2(padding * 2.0, padding * 2.0);

    float2 localPixelCoord = signs * (paddedSize / 2.0);

    // Convert to NDC space (Placeholder math until you hook up Transforms)
    // Adjust the 1000.0/600.0 to match your actual screen half-widths
    Transform t = *instance.transform;
    float3 worldPos = applyDualQuat(t, float3(localPixelCoord, 0.0));
    float4 ndcPos = mul(scene.viewproj, float4(worldPos, 1.0));

    verts[localID].position = ndcPos;

    // Pass the raw local coordinates for the SDF fragment math
    verts[localID].texcoord = localPixelCoord;

    // Pass routing info to the Fragment Shader
    verts[localID].elementIndex = elementIndex;
    verts[localID].type = instance.type;
  }

  // -----------------------------------------------------
  // 2 THREADS WRITE PRIMITIVES
  // -----------------------------------------------------
  if (localID < 2) {
    if (localID == 0) {
      prims[localID] = uint3(0, 1, 2);
    } else {
      prims[localID] = uint3(2, 1, 3);
    }
  }
}

void emitStrokedCurve(uint elementIndex, UIInstance instance, UIElement *ui,
                      uint localID, out indices uint3 prims[MAX_PRIMS],
                      out vertices UIVaryings verts[MAX_VERTS]) {
  float2 P0 = ui.vertexBuffer[0].position.xy;
  float2 P1 = ui.vertexBuffer[1].position.xy;
  float2 P2 = ui.vertexBuffer[2].position.xy;

  float strokeWidth = 3.0;
  float dist = length(P2 - P0) + length(P1 - P0);
  uint segments = clamp(uint(dist / 15.0), 2, 14);
  float thickness = strokeWidth + 5.0; // Padding for anti-aliasing
  uint vCount = (segments + 1) * 2;
  uint pCount = segments * 2;

  SetMeshOutputCounts(vCount, pCount);

  if (localID < vCount) {
    uint sliceIndex = localID / 2;
    bool isTop = (localID % 2 == 0);
    float t = (float)sliceIndex / (float)segments;

    float invT = 1.0 - t;
    float2 centerPos =
        (invT * invT * P0) + (2.0 * invT * t * P1) + (t * t * P2);

    float2 tangent = 2.0 * invT * (P1 - P0) + 2.0 * t * (P2 - P1);
    float len = length(tangent);
    float2 normal =
        len > 0.0001 ? float2(-tangent.y, tangent.x) / len : float2(0.0, 1.0);

    float2 finalPos = centerPos + (normal * thickness * (isTop ? 1.0 : -1.0));
    float2 ndcPos = (finalPos / scene.viewport.xy) * 2.0 - 1.0;

    verts[localID].position = float4(ndcPos, 0.0, 1.0);
    verts[localID].texcoord = float2(t, isTop ? 1.0 : 0.0);
    verts[localID].elementIndex = elementIndex;
    verts[localID].type = instance.type;
  }

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

void emitBoundingGeometry(uint elementIndex, UIInstance instance, UIElement *ui,
                          uint localID, out indices uint3 prims[MAX_PRIMS],
                          out vertices UIVaryings verts[MAX_VERTS]) {
  // TODO: Emit bounding geometry for closed shapes (Fonts/SVGs).
  // Option A: Tile-based emission (1 Quad per intersected 16x16 grid tile).
  // Option B: Central Triangle Fan (Emit triangles radiating from the shape's
  // center to the perimeter).
  SetMeshOutputCounts(0, 0);
}

[shader("mesh")]
[outputtopology("triangle")]
[numthreads(32, 1, 1)]
void uiMesh(uint workgroupID: SV_GroupID, uint localID: SV_GroupIndex,
            out indices uint3 prims[MAX_PRIMS],
            out vertices UIVaryings verts[MAX_VERTS]) {
  if (workgroupID >= scene.uielemCount)
    return;

  UIInstance instance = scene.addresses.uiobjects[workgroupID];
  UIElement *ui = instance.UIBuffer;
  uint type = instance.type;

  // Uniform Branching: Only one of these executes per workgroup!
  if (type == UI_TYPE_ANALYTICAL) {
    emitAnalyticalQuad(workgroupID, instance, ui, localID, prims, verts);
  } else if (type == UI_TYPE_STROKE) {
    emitStrokedCurve(workgroupID, instance, ui, localID, prims, verts);
  } else if (type == UI_TYPE_FILL) {
    emitBoundingGeometry(workgroupID, instance, ui, localID, prims, verts);
  }
}
// ==========================================
// FRAGMENT SHADER FILL
// ==========================================

float4 solveSDF(UIVaryings in, UIInstance instance, UIElement *ui) {
  // 1. Get the local pixel coordinate relative to the center of the shape.
  // (Assuming your Mesh Shader emitted a quad from -size/2 to +size/2,
  // and passed the local coordinate via in.texcoord)
  float2 p = in.texcoord;

  // 2. Mathematical Signed Distance to a Rounded Box
  float2 b = (ui.size / 2.0) - ui.radius;
  float2 d = abs(p) - b;
  float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - ui.radius;

  // 3. Handle Strokes (Borders)
  if (ui.stroke > 0.0) {
    // If it's a stroke, we want the distance to the *edge* line,
    // effectively hollowing out the inside.
    dist = abs(dist) - (ui.stroke / 2.0);
  }

  // 4. Anti-Aliasing
  float alpha = saturate(0.5 - dist);

  if (alpha <= 0.0)
    discard;

  // 5. Output Final Color
  float4 finalColor = unpackColor(ui.color);
  finalColor.a *= alpha;
  return finalColor;
}

float4 solveStrokeDistance(UIVaryings in, UIInstance instance, UIElement *ui) {
  UIInstance instance = scene.addresses.uiobjects[in.elementIndex];
  UIElement *ui = instance.UIBuffer;

  // Default to discard unless we find a curve we are close to
  float minDistance = 99999.0;

  for (uint i = 0; i < ui.vertexCount; i += 3) {
    if (i + 2 >= ui.vertexCount)
      break;

    float2 P0 = ui.vertexBuffer[i].position.xy;
    float2 P1 = ui.vertexBuffer[i + 1].position.xy;
    float2 P2 = ui.vertexBuffer[i + 2].position.xy;

    float d = sdBezier(in.position.xy, P0, P1, P2);
    minDistance = min(minDistance, d);
  }

  float strokeWidth = ui.stroke; // Desired pixel thickness of the line
  float edgeRadius = strokeWidth / 2.0;

  // Calculate anti-aliasing (1 pixel fade at the exact edge)
  float coverage = saturate(edgeRadius - minDistance + 0.5);

  // If the pixel is further away than the stroke width, discard!
  if (coverage <= 0.0)
    discard;
  return float4(1.0, 1.0, 1.0, coverage);
}

float4 solveWindingFill(UIVaryings in, UIInstance instance, UIElement *ui) {
  float xcov = 0.0, xwgt = 0.0, ycov = 0.0, ywgt = 0.0;

  for (uint i = 0; i < ui.vertexCount; i += 3) {
    if (i + 2 >= ui.vertexCount)
      break;

    float2 P0 = ui.vertexBuffer[i].position.xy;
    float2 P1 = ui.vertexBuffer[i + 1].position.xy;
    float2 P2 = ui.vertexBuffer[i + 2].position.xy;

    EvaluateCurve(P0, P1, P2, in.position.xy, xcov, xwgt, ycov, ywgt);
  }

  float coverage =
      max(abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0),
          min(abs(xcov), abs(ycov)));
  coverage = saturate(coverage);

  if (coverage <= 0.0)
    discard;
  return float4(1.0, 1.0, 1.0, coverage);
}

[shader("fragment")]
float4 uiFragment(UIVaryings in) : SV_Target {
  UIInstance instance = scene.addresses.uiobjects[in.elementIndex];
  UIElement *ui = instance.UIBuffer;

  // Uniform Branching: Automatically uniform over rasterized quads
  if (in.type == UI_TYPE_ANALYTICAL) {
    return solveSDF(in, instance, ui);
  } else if (in.type == UI_TYPE_STROKE) {
    return solveStrokeDistance(in, instance, ui);
  } else if (in.type == UI_TYPE_FILL) {
    return solveWindingFill(in, instance, ui);
  }

  return float4(1.0, 0.0, 1.0, 1.0); // Magenta error fallback
}
