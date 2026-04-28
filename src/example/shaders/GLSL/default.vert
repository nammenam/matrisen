#version 460 core
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

struct Vertex {
    vec3 position;
    float uv_x;
    vec3 normal;
    float uv_y;
    vec4 color;
};

layout(buffer_reference, scalar) buffer Vertices { Vertex v[]; };
layout(buffer_reference, scalar) buffer Indices { uint i[]; };

struct ObjectData {
    mat4 modelMatrix;
    Vertices vertexBuffer; // 64-bit address
    Indices  indexBuffer;  // 64-bit address
    uint materialIndex;
    uint _pad1;
    uint _pad2;
    uint _pad3;
};

layout(buffer_reference, scalar) buffer ObjectTable { ObjectData o[]; };

// --- SET 0: GLOBALS (Your SceneData) ---
layout(set = 0, binding = 0, std140) uniform SceneData {
    mat4 view;
    mat4 proj;
    mat4 viewproj;
    vec4 ambient_color;
    vec4 sun_direction;
    vec4 sun_color;
    ObjectTable objects;
} scene; // <--- Accessed as 'scene.viewproj'

layout(location = 0) out vec3 outNormal;
layout(location = 1) out vec3 outColor;
layout(location = 2) out vec2 outUV;

void main()
{
    // TODO test the new bindless
    // Vulkan Y-coordinate is down, so (0, -0.5) is top
    const vec3 positions[3] = vec3[3](
        vec3(0.0, -0.5, 0.0),
        vec3(0.5, 0.5, 0.0),
        vec3(-0.5, 0.5, 0.0)
    );

    const vec3 colors[3] = vec3[3](
        vec3(1.0, 0.0, 0.0), // Red
        vec3(0.0, 1.0, 0.0), // Green
        vec3(0.0, 0.0, 1.0)  // Blue
    );

    ObjectData obj = scene.objects.o[gl_BaseInstance];
    uint index = obj.indexBuffer.i[gl_VertexIndex];
    Vertex vert = obj.vertexBuffer.v[index];
    vec4 worldPos = obj.modelMatrix * vec4(vert.position, 1.0);
    gl_Position = scene.viewproj * worldPos;
    outNormal = vert.normal; // (Should multiply by normal matrix in real app)
    outColor  = vert.color.rgb;
    outUV     = vec2(vert.uv_x, vert.uv_y);
}
