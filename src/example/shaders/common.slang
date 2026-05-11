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

public struct UIElement {
    public float2 position;
    public float2 size;
    public float4 *curveBuffer;
    public uint curveCount;
    public uint _pad;
};

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

public struct SceneData {
  public float4x4 view;
  public float4x4 proj;
  public float4x4 viewproj;
  public float4 ambient_color;
  public float4 sun_direction;
  public float4 sun_color;
  public float4 viewport;
  // addresses
  public Transform *transforms;
  public Transform *cpu_transforms;
  public Mesh *meshes;
  public UIElement *uielements;
#if USE_MESH_SHADING
  public VkDrawMeshTasksIndirectCommandEXT *indirectCommands;
#else
  public VkDrawIndirectCommand *indirectCommands;
#endif  // other
  public uint *drawCount;
  public uint *drawMap;
  public uint meshCount;
  public uint uielemCount;
};

[[vk::binding(0, 0)]]
public ConstantBuffer<SceneData> scene;

[[vk::binding(0, 1)]]
public Sampler2D globalTextures[];
