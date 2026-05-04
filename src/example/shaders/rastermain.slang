import common;

struct AssembledVertex {
  float4 position : SV_Position;
  float3 normal : NORMAL;
  float3 color : COLOR;
  float2 uv : UV;
};

// ==========================================
// VERTEX SHADER
// ==========================================
[shader("vertex")]
AssembledVertex vertexMain(uint vertexId: SV_VertexID,
                           uint instanceId: SV_InstanceID) {
  AssembledVertex out;

  // Transform transform = scene.transforms[instanceId];
  Mesh mesh = scene.meshes[instanceId];

  uint index = mesh.indexBuffer[vertexId];
  Vertex vert = mesh.vertexBuffer[index];

  // float4 worldPos = mul(transform.modelMatrix, float4(vert.position, 1.0));
  float4 worldPos = float4(vert.position, 1.0);
  out.position = mul(scene.viewproj, worldPos);
  out.normal = vert.normal;
  out.color = vert.color.rgb;

  return out;
}

// ==========================================
// FRAGMENT SHADER
// ==========================================
[shader("fragment")]
float4 fragmentMain(AssembledVertex in) : SV_Target {
  return float4(in.color, 1.0);
}
