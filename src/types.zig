const std = @import("std");
const m = @import("3Dmath.zig");
const DescriptorAllocatorGrowable = @import("descriptors.zig").DescriptorAllocatorGrowable;
const BufferDeletionStack = @import("vulkanutils.zig").BufferDeletionStack;
const c = @import("clibs.zig");
const Gltf = @import("assetloader.zig");

pub const AllocatedBuffer = struct {
    buffer: c.VkBuffer,
    allocation: c.VmaAllocation,
    info: c.VmaAllocationInfo,
};



pub const AllocatedImage = struct {
    image: c.VkImage,
    allocation: c.VmaAllocation,
};

pub const GPUMeshBuffers = struct {
    vertex_buffer: AllocatedBuffer,
    index_buffer: AllocatedBuffer,
    vertex_buffer_adress: c.VkDeviceAddress,
};

pub const GPUDrawPushConstants = extern struct {
    model: m.Mat4,
    vertex_buffer: c.VkDeviceAddress,
};

pub const GPUSceneData = extern struct {
    view: m.Mat4,
    proj: m.Mat4,
    viewproj: m.Mat4,
    ambient_color: m.Vec4,
    sunlight_dir: m.Vec4,
    sunlight_color: m.Vec4,
};

pub const Vertex = extern struct {
    position: m.Vec3,
    uv_x: f32 = 0.0,
    normal: m.Vec3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    uv_y: f32 = 0.0,
    color: m.Vec4,
};

pub const FrameData = struct {
    swapchain_semaphore: c.VkSemaphore = null,
    render_semaphore: c.VkSemaphore = null,
    render_fence: c.VkFence = null,
    command_pool: c.VkCommandPool = null,
    main_command_buffer: c.VkCommandBuffer = null,
    frame_descriptors: DescriptorAllocatorGrowable = DescriptorAllocatorGrowable{},
    buffer_deletion_queue: BufferDeletionStack = BufferDeletionStack{},
};

pub const ComputePushConstants = extern struct {
    data1: m.Vec4,
    data2: m.Vec4,
    data3: m.Vec4,
    data4: m.Vec4,
};

pub const GeoSurface = struct {
    start_index: u32,
    count: u32,
};

pub const MeshAsset = struct {
    name: []const u8,
    surfaces: std.ArrayList(GeoSurface),
    mesh_buffers: GPUMeshBuffers = undefined,
};

pub const Index = usize;

pub const Node = struct {
    name: []const u8,
    parent: ?Index = null,
    mesh: ?Index = null,
    camera: ?Index = null,
    skin: ?Index = null,
    children: std.ArrayList(Index),
    matrix: ?[16]f32 = null,
    rotation: [4]f32 = [_]f32{ 0, 0, 0, 1 },
    scale: [3]f32 = [_]f32{ 1, 1, 1 },
    translation: [3]f32 = [_]f32{ 0, 0, 0 },
    weights: ?[]usize = null,
    light: ?Index = null,
};

pub const Buffer = struct {
    uri: ?[]const u8 = null,
    byte_length: usize,
};

pub const BufferView = struct {
    buffer: Index,
    byte_length: usize,
    byte_offset: usize = 0,
    byte_stride: ?usize = null,
    target: ?Target = null,
};

pub const Accessor = struct {
    buffer_view: ?Index = null,
    byte_offset: usize = 0,
    component_type: ComponentType,
    type: AccessorType,
    stride: usize,
    count: i32,
    normalized: bool = false,

    pub fn iterator(
        accessor: Accessor,
        comptime T: type,
        gltf: *const Gltf,
        binary: []align(4) const u8,
    ) AccessorIterator(T) {
        if (switch (accessor.component_type) {
            .byte => T != i8,
            .unsigned_byte => T != u8,
            .short => T != i16,
            .unsigned_short => T != u16,
            .unsigned_integer => T != u32,
            .float => T != f32,
        }) {
            std.debug.panic(
                "Mismatch between gltf component '{}' and given type '{}'.",
                .{ accessor.component_type, T },
            );
        }

        if (accessor.buffer_view == null) {
            std.debug.panic("Accessors without buffer_view are not supported yet.", .{});
        }

        const buffer_view = gltf.data.buffer_views.items[accessor.buffer_view.?];

        const comp_size = @sizeOf(T);
        const offset = (accessor.byte_offset + buffer_view.byte_offset) / comp_size;

        const stride = blk: {
            if (buffer_view.byte_stride) |byte_stride| {
                break :blk byte_stride / comp_size;
            } else {
                break :blk accessor.stride / comp_size;
            }
        };

        const total_count: usize = @intCast(accessor.count);
        const datum_count: usize = switch (accessor.type) {
            .scalar => 1,
            .vec2 => 2,
            .vec3 => 3,
            .vec4 => 4,
            .mat4x4 => 16,
            else => {
                std.debug.panic("Accessor type '{}' not implemented.", .{accessor.type});
            },
        };

        const data: [*]const T = @ptrCast(@alignCast(binary.ptr));

        return .{
            .offset = offset,
            .stride = stride,
            .total_count = total_count,
            .datum_count = datum_count,
            .data = data,
            .current = 0,
        };
    }
};

pub fn AccessorIterator(comptime T: type) type {
    return struct {
        offset: usize,
        stride: usize,
        total_count: usize,
        datum_count: usize,
        data: [*]const T,

        current: usize,

        pub fn next(self: *@This()) ?[]const T {
            if (self.current >= self.total_count) return null;

            const slice = (self.data + self.offset + self.current * self.stride)[0..self.datum_count];
            self.current += 1;
            return slice;
        }

        pub fn peek(self: *const @This()) ?[]const T {
            var copy = self.*;
            return copy.next();
        }

        pub fn reset(self: *@This()) void {
            self.current = 0;
        }
    };
}

pub const Scene = struct {
    name: []const u8,
    nodes: ?std.ArrayList(Index) = null,
};

pub const Skin = struct {
    name: []const u8,
    inverse_bind_matrices: ?Index = null,
    skeleton: ?Index = null,
    joints: std.ArrayList(Index),
};

const TextureInfo = struct {
    index: Index,
    texcoord: i32 = 0,
};

const NormalTextureInfo = struct {
    index: Index,
    texcoord: i32 = 0,
    scale: f32 = 1,
};

const OcclusionTextureInfo = struct {
    index: Index,
    texcoord: i32 = 0,
    strength: f32 = 1,
};

pub const MetallicRoughness = struct {
    base_color_factor: [4]f32 = [_]f32{ 1, 1, 1, 1 },
    base_color_texture: ?TextureInfo = null,
    metallic_factor: f32 = 1,
    roughness_factor: f32 = 1,
    metallic_roughness_texture: ?TextureInfo = null,
};

pub const Material = struct {
    name: []const u8,
    metallic_roughness: MetallicRoughness = .{},
    normal_texture: ?NormalTextureInfo = null,
    occlusion_texture: ?OcclusionTextureInfo = null,
    emissive_texture: ?TextureInfo = null,
    emissive_factor: [3]f32 = [_]f32{ 0, 0, 0 },
    alpha_mode: AlphaMode = .@"opaque",
    alpha_cutoff: f32 = 0.5,
    is_double_sided: bool = false,
    emissive_strength: f32 = 1.0,
    ior: f32 = 1.5,
    transmission_factor: f32 = 0.0,
    transmission_texture: ?TextureInfo = null,
};

const AlphaMode = enum {
    @"opaque",
    mask,
    blend,
};

pub const Texture = struct {
    sampler: ?Index = null,
    source: ?Index = null,
};

pub const Image = struct {
    uri: ?[]const u8 = null,
    mime_type: ?[]const u8 = null,
    buffer_view: ?Index = null,
    data: ?[]const u8 = null,
};

pub const WrapMode = enum(u32) {
    clamp_to_edge = 33071,
    mirrored_repeat = 33648,
    repeat = 10497,
};

pub const MinFilter = enum(u32) {
    nearest = 9728,
    linear = 9729,
    nearest_mipmap_nearest = 9984,
    linear_mipmap_nearest = 9985,
    nearest_mipmap_linear = 9986,
    linear_mipmap_linear = 9987,
};

pub const MagFilter = enum(u32) {
    nearest = 9728,
    linear = 9729,
};

pub const TextureSampler = struct {
    mag_filter: ?MagFilter = null,
    min_filter: ?MinFilter = null,
    wrap_s: WrapMode = .repeat,
    wrap_t: WrapMode = .repeat,
};

pub const Attribute = union(enum) {
    position: Index,
    normal: Index,
    tangent: Index,
    texcoord: Index,
    color: Index,
    joints: Index,
    weights: Index,
};

pub const AccessorType = enum {
    scalar,
    vec2,
    vec3,
    vec4,
    mat2x2,
    mat3x3,
    mat4x4,
};

pub const Target = enum(u32) {
    array_buffer = 34962,
    element_array_buffer = 34963,
};

pub const ComponentType = enum(u32) {
    byte = 5120,
    unsigned_byte = 5121,
    short = 5122,
    unsigned_short = 5123,
    unsigned_integer = 5125,
    float = 5126,
};

pub const Mode = enum(u32) {
    points = 0,
    lines = 1,
    line_loop = 2,
    line_strip = 3,
    triangles = 4,
    triangle_strip = 5,
    triangle_fan = 6,
};

pub const TargetProperty = enum {
    translation,
    rotation,
    scale,
    weights,
};

pub const Channel = struct {
    sampler: Index,
    target: struct {
        node: Index,
        property: TargetProperty,
    },
};

pub const Interpolation = enum {
    linear,
    step,
    cubicspline,
};

pub const AnimationSampler = struct {
    input: Index,
    output: Index,
    interpolation: Interpolation = .linear,
};

pub const Animation = struct {
    name: []const u8,
    channels: std.ArrayList(Channel),
    samplers: std.ArrayList(AnimationSampler),
};

pub const Primitive = struct {
    attributes: std.ArrayList(Attribute),
    mode: Mode = .triangles,
    indices: ?Index = null,
    material: ?Index = null,
};

pub const Mesh = struct {
    name: []const u8,
    primitives: std.ArrayList(Primitive),
};

pub const Asset = struct {
    version: []const u8,
    generator: ?[]const u8 = null,
    copyright: ?[]const u8 = null,
};

pub const Camera = struct {
    pub const Perspective = struct {
        aspect_ratio: f32,
        yfov: f32,
        zfar: f32,
        znear: f32,
    };

    pub const Orthographic = struct {
        xmag: f32,
        ymag: f32,
        zfar: f32,
        znear: f32,
    };

    name: []const u8,
    type: union {
        perspective: Perspective,
        orthographic: Orthographic,
    },
};

pub const LightType = enum {
    directional,
    point,
    spot,
};

pub const Light = struct {
    name: ?[]const u8,
    color: [3]f32 = .{ 1, 1, 1 },
    intensity: f32 = 1,
    type: LightType,
    spot: ?LightSpot,
    range: f32,
};

pub const LightSpot = struct {
    inner_cone_angle: f32 = 0,
    outer_cone_angle: f32 = std.math.pi / @as(f32, 4),
};
