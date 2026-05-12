import common;

struct AssembledVertex {
  float4 position : SV_Position;
  float3 normal : NORMAL;
  float3 color : COLOR;
  float2 uv : UV;
}

static const uint NUM_THREADS = 32;
static const uint MAX_VERTS = 96;
static const uint MAX_PRIMS = 32;

// ==========================================
// MESH SHADER
// ==========================================
[shader("mesh")]
[outputtopology("triangle")]
[numthreads(NUM_THREADS, 1, 1)]
void meshMain(uint3 groupId: SV_GroupID, uint groupIndex: SV_GroupIndex,
              out vertices AssembledVertex outVerts[MAX_VERTS],
              out indices uint3 outIndices[MAX_PRIMS]) {
  uint instanceId = groupId.y;
  Mesh * mesh = scene.meshes[instanceId].meshBuffer;

  uint totalTriangles = mesh.indexCount / 3;
  uint globalTriangleIndex = (groupId.x * NUM_THREADS) + groupIndex;

  // Slang standard library max() to prevent underflow
  uint trianglesInGroup =
      min(NUM_THREADS, max(0, totalTriangles - (groupId.x * NUM_THREADS)));

  if (groupIndex == 0) {
    SetMeshOutputCounts(trianglesInGroup * 3, trianglesInGroup);
  }

  if (globalTriangleIndex < totalTriangles) {
    uint i0 = mesh.indexBuffer[globalTriangleIndex * 3 + 0];
    uint i1 = mesh.indexBuffer[globalTriangleIndex * 3 + 1];
    uint i2 = mesh.indexBuffer[globalTriangleIndex * 3 + 2];

    Vertex v0 = mesh.vertexBuffer[i0];
    Vertex v1 = mesh.vertexBuffer[i1];
    Vertex v2 = mesh.vertexBuffer[i2];

    uint vOffset = groupIndex * 3;

    // Slang allows clean struct initialization!
    outVerts[vOffset + 0] = { mul(scene.viewproj, float4(v0.position, 1.0)),
                              v0.normal, v0.color.rgb,
                              float2(v0.uv_x, v0.uv_y) };
    outVerts[vOffset + 1] = { mul(scene.viewproj, float4(v1.position, 1.0)),
                              v1.normal, v1.color.rgb,
                              float2(v1.uv_x, v1.uv_y) };
    outVerts[vOffset + 2] = { mul(scene.viewproj, float4(v2.position, 1.0)),
                              v2.normal, v2.color.rgb,
                              float2(v2.uv_x, v2.uv_y) };

    outIndices[groupIndex] = uint3(vOffset, vOffset + 1, vOffset + 2);
  }
}

// ==========================================
// FRAGMENT SHADER
// ==========================================
[shader("fragment")]
float4 meshFragmentMain(AssembledVertex in) : SV_Target {
  return float4(in.color, 1.0);
}
