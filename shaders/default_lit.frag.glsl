#version 450

layout(location = 0) in vec3 in_color;
layout(location = 2) in vec3 in_normal;

layout(location = 0) out vec4 frag_color;

layout(set = 0, binding = 1) uniform UniformBufferObject {
	vec4 fog_color;
	vec4 fog_distance;
	vec4 ambient_color;
	vec4 sunlight_direction;
	vec4 sunlight_color;
} scene_data;

void main() {
    vec3 normal = (in_normal + 1.0f) / 2.0f;
    frag_color = vec4(normal, 1.0f);
    // frag_color = vec4(in_color, 1.0f);
}

