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
}; // Total: 32 bytes

// TODO fix this
public struct Transform {
  public float4 real;
  public float4 dual;
};

public struct BoundingBox {
  public float3 center;
  public float theta; // around world z
  public float3 whd;  // width heigth depth
  public float phi;   // around world y or x
};

public struct UIElement {
  public UIVertex *vertexBuffer;
  public uint vertexCount;
  public uint color;
  public float2 size;
  public float radius;
  public float stroke;
};

public struct Mesh {
  public Vertex *vertexBuffer; // start of vertexbuffer
  public uint *indexBuffer;    // start of indexbuffer
  public uint indexCount;
  public uint pad;
};

public struct UIInstance {
  public UIElement *UIBuffer; // two levels of lookup, first ui then vertex
  public Transform *transform;
  public uint type;
  public uint pad;
};

public struct MeshInstance {
  public Mesh *meshBuffer; // two levels of lookup, first meshbuffer then vertex
  public Transform *transform;
  public uint materialIndex; // can be arbitrarly packed
  public uint pad;
};

public struct DeviceBufferAddresses {
  public MeshInstance *meshes;      // written by cpu (and gpu?)
  public UIInstance *uiobjects;     // written by cpu (and gpu?)
#if USE_MESH_SHADING
  public VkDrawMeshTasksIndirectCommandEXT *indirectCommands;
#else
  public VkDrawIndirectCommand *indirectCommands;
#endif
  public uint *drawcount; // written to by cpu (cleared) and gpu
  public uint *drawMap;   // shader to shader cpu not concerned
  public uint pad0;
  public uint pad1;
};

public struct SceneData {
  public DeviceBufferAddresses addresses;
  public float4x4 viewproj;
  public float4 ambient_color;
  public float4 sun_direction;
  public float4 sun_color;
  public float4 viewport;
  public uint meshCount;   // number of meshInstance uploaded/prepared by cpu
  public uint uielemCount; // number of UIInstance uplaoded/prepared by cpu
  public uint pad0;
  public uint pad1;
};

[[vk::binding(0, 0)]]
public ConstantBuffer<SceneData> scene;

[[vk::binding(0, 1)]]
public Sampler2D globalTextures[];


// DualQuat transformation helper
public float3 applyDualQuat(Transform t, float3 pos) {
    // Dual Quaternion transformation:
    // NewPos = RealPart * pos * conj(RealPart) + 2 * DualPart * conj(RealPart)
    float3 r = t.real.xyz;
    float3 d = t.dual.xyz;

    // Standard DualQuat rotation + translation
    return pos + 2.0 * cross(r, cross(r, pos) + t.real.w * pos) + 2.0 * (t.real.w * d - t.dual.w * r + cross(r, d));
}
