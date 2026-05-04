module common;

public struct VkDrawIndirectCommand {
  public uint vertexCount;
  public uint instanceCount;
  public uint firstVertex;
  public uint firstInstance;
};

public struct VkDrawMeshTasksIndirectCommandEXT {
  public uint groupCountX;
  public uint groupCountY;
  public uint groupCountZ;
}

public struct Vertex {
  public float3 position;
  public float uv_x;
  public float3 normal;
  public float uv_y;
  public float4 color;
};

public struct Transform {
  public float4x4 modelMatrix;
  public float4 boundingSphere; // xyz = center, w = radius
};

public struct Mesh {
  public Vertex *vertexBuffer;
  public uint *indexBuffer;
  public uint indexCount;
  public uint materialIndex;
};

// --- ONE DESCRIPTOR TO RULE THEM ALL ---
public struct SceneData {
  public float4x4 view;
  public float4x4 proj;
  public float4x4 viewproj;
  public float4 ambient_color;
  public float4 sun_direction;
  public float4 sun_color;
  // addresses
  public Transform *transforms;
  public Transform *cpu_transforms;
  public Mesh *meshes;
#if USE_MESH_SHADING
  public VkDrawMeshTasksIndirectCommandEXT *indirectCommands;
  public uint *drawCount;
  public uint *drawMap;
#else
  public VkDrawIndirectCommand *indirectCommands;
  public uint *drawCount;
  public uint *drawMap;
#endif  // other
  public uint totalObjects;
  public uint _pad;
};

[[vk::binding(0, 0)]]
public ConstantBuffer<SceneData> scene;
