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

layout(location = 0) in vec3 inNormal;
layout(location = 1) in vec3 inColor;
layout(location = 2) in vec2 inUV;

layout(location = 0) out vec4 outFragColor;

void main()
{
    vec3 color = inColor;
    vec3 normal = inNormal;
    outFragColor = vec4(color, 1.0);
}
