// 1. Move this to the top so SceneData knows what it is!
struct VkDrawIndirectCommand {
  uint vertexCount;
  uint instanceCount;
  uint firstVertex;
  uint firstInstance;
};

struct Vertex {
  float3 position;
  float uv_x;
  float3 normal;
  float uv_y;
  float4 color;
};

// --- BUFFER 1: Fast, dense array for Culling & Transforms ---
struct TransformData {
  float4x4 modelMatrix;
  float4 boundingSphere; // xyz = center, w = radius
};

// --- BUFFER 2: Read later by the Graphics Pipeline ---
struct DrawData {
  Vertex *vertexBuffer;
  uint *indexBuffer;
  uint materialIndex;
  uint _pad;
};

// --- ONE DESCRIPTOR TO RULE THEM ALL ---
struct SceneData {
  float4x4 view;
  float4x4 proj;
  float4x4 viewproj;
  float4 ambient_color;
  float4 sun_direction;
  float4 sun_color;

  TransformData *transforms; // Replaces ObjectData
  DrawData *draws;           // Replaces ObjectData

  VkDrawIndirectCommand *indirectCommands; // Replaces Binding 1
  uint *drawCount;                         // Replaces Binding 2
};

[[vk::binding(0, 0)]]
ConstantBuffer<SceneData> scene;

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

  // Read from our newly split arrays!
  TransformData transform = scene.transforms[instanceId];
  DrawData draw = scene.draws[instanceId];

  // Follow the bindless pointers
  uint index = draw.indexBuffer[vertexId];
  Vertex vert = draw.vertexBuffer[index];

  float4 worldPos = mul(transform.modelMatrix, float4(vert.position, 1.0));
  out.position = mul(scene.viewproj, worldPos);
  out.normal = vert.normal;
  out.color = vert.color.rgb;
  out.uv = float2(vert.uv_x, vert.uv_y);

  return out;
}

// ==========================================
// FRAGMENT SHADER
// ==========================================
[shader("fragment")]
float4 fragmentMain(AssembledVertex in) : SV_Target {
  return float4(in.color, 1.0);
}

// ==========================================
// COMPUTE SHADER (Culling)
// ==========================================
[shader("compute")]
[numthreads(64, 1, 1)]
void computeMain(uint3 threadId: SV_DispatchThreadID) {
  uint objIndex = threadId.x;

  // TODO: Add actual frustum culling using
  // scene.transforms[objIndex].boundingSphere

  bool isVisible = (objIndex % 2 == 0);

  if (isVisible) {
    uint drawIndex;
    // Atomically increment the count buffer via the SceneData pointer!
    InterlockedAdd(scene.drawCount[0], 1, drawIndex);

    // Write the draw command to the tightly packed slot
    scene.indirectCommands[drawIndex].vertexCount =
        3; // (Or read from draw.indexCount if you add it to DrawData)
    scene.indirectCommands[drawIndex].instanceCount = 1;
    scene.indirectCommands[drawIndex].firstVertex = 0;
    scene.indirectCommands[drawIndex].firstInstance = objIndex;
  }
}
