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
  public float3 normal; // TODO pack normals 32bits octahedral
  public float uv_y;
  public float4 color; // TODO pack into 32bits
};

public struct UIVertex {
  public float3 position;
  public uint normal;
  public float2 uv;
  public uint color;
  public uint tangent;
};

public struct Transform {
  public float4x4 modelMatrix;
};

public struct BoundingBox {
  public float3 center;
  public float theta; // around world z
  public float3 whd;  // width heigth depth
  public float phi;   // around world y or x
};

public struct UIElement {
  public Vertex *vertexBuffer; // TODO use UIVertex instead
  public uint vertexCount;     // number of vertices
  public uint pad;
};

public struct Mesh {
  public Vertex *vertexBuffer; // start of vertexbuffer
  public uint *indexBuffer;    // start of indexbuffer
  public uint indexCount;
  public uint pad;
};

public struct UIInstance {
  public UIElement *UIBuffer; // two levels of lookup, first ui then vertex
  public uint transformIndex;
  // Packing the state!
  // Bits 0-7:   Type (0=Rect, 1=Circle, 2=Line, 3=Bezier)
  // Bits 8-15:  Flags (1=Filled, 2=Hovered, 4=Disabled)
  // Bits 16-31: Material/Style Index (Points to a buffer with colors/thickness)
  public uint type;
  // public float thickness; // For lines can be separate buffer for reuse
};

public struct MeshInstance {
  public Mesh *meshBuffer; // two levels of lookup, first meshbuffer then vertex
  public uint transformIndex;
  public uint materialIndex; // can be arbitrarly packed
};

public struct GPUCounters {
  public uint drawCount;
  public uint vertexOffset;
  public uint indexOffset;
  public uint meshOffset;
  public uint uiVertexOffset;
  public uint uiElementOffset;
  public uint pad0;
  public uint pad1;
};

public struct SceneData {
  public float4x4 viewproj;
  public float4 ambient_color;
  public float4 sun_direction;
  public float4 sun_color;
  public float4 viewport;
  // addresses
  public Transform *transforms;     // written by gpu (can be written by cpu)
  public Transform *cpu_transforms; // written by cpu only
  public MeshInstance *meshes;      // written by cpu (and gpu?)
  public UIInstance *uiobjects;     // written by cpu (and gpu?)
  // can add more objecttypes here
#if USE_MESH_SHADING
  public VkDrawMeshTasksIndirectCommandEXT *indirectCommands;
#else
  public VkDrawIndirectCommand *indirectCommands;
#endif
  public GPUCounters *counters; // written to by cpu (cleared) and gpu
  public uint *drawMap;   // shader to shader cpu not concerned
  // counts
  public uint meshCount;   // number of meshInstance uploaded/prepared by cpu
  public uint uielemCount; // number of UIInstance uplaoded/prepared by cpu
  public uint pad0;
  public uint pad1;
};

[[vk::binding(0, 0)]]
public ConstantBuffer<SceneData> scene;

[[vk::binding(0, 1)]]
public Sampler2D globalTextures[];
