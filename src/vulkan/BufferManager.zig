const std = @import("std");
const linalg = @import("../linalg.zig");
const debug = @import("debug.zig");
const c = @import("../clibs/clibs.zig").libs;
const Core = @import("Core.zig");
const BufferAllocator = @import("BufferAllocator.zig");
const DescriptorManager = @import("DescriptorManager.zig");
const AllocatedBuffer = BufferAllocator.AllocatedBuffer;

const Quat = linalg.Quat(f32);
const Vec3 = linalg.Vec3(f32);
const Vec4 = linalg.Vec4(f32);
const Mat4x4 = linalg.Mat4x4(f32);

// --- 1. GPU STRUCTS (Must match Slang perfectly) ---
pub const Vertex = extern struct {
    position: Vec3,
    uv_x: f32,
    normal: Vec3,
    uv_y: f32,
    color: Vec4,
};

pub const TransformData = extern struct {
    modelMatrix: Mat4x4,
    boundingSphere: Vec4,
};

pub const DrawData = extern struct {
    vertexBuffer: u64,
    indexBuffer: u64,
    materialIndex: u32,
    _pad: u32 = 0,
};

pub const SceneData = extern struct {
    view: Mat4x4,
    proj: Mat4x4,
    viewproj: Mat4x4,
    ambient_color: Vec4,
    sun_direction: Vec4,
    sun_color: Vec4,

    transforms: u64,
    draws: u64,
    indirectCommands: u64,
    drawCount: u64,
};

// --- 2. MANAGER DEFINITION ---
const Self = @This();

// Limits for the engine
const MAX_GEOMETRY_BYTES = 64 * 1024 * 1024; // 64 MB for Verts/Indices
const MAX_OBJECTS = 10_000;

// The Giant Geometry Buffers
globalvertexbuffer: AllocatedBuffer = undefined,
globalindexbuffer: AllocatedBuffer = undefined,

// Bump Allocator Trackers
vertex_byte_offset: u64 = 0,
index_byte_offset: u64 = 0,

// Compute & App Arrays
transformbuffer: AllocatedBuffer = undefined,
drawbuffer: AllocatedBuffer = undefined,
indirectbuffer: AllocatedBuffer = undefined,
countbuffer: AllocatedBuffer = undefined,

// Uniforms
scenebuffers: [Core.multibuffering]AllocatedBuffer = @splat(undefined),

pub fn init() Self {
    return .{};
}

pub fn destroyBuffers(self: *Self, bufferallocator: *BufferAllocator) void {
    for (self.scenebuffers) |buf| bufferallocator.destroy(buf);
    bufferallocator.destroy(self.globalvertexbuffer);
    bufferallocator.destroy(self.globalindexbuffer);
    bufferallocator.destroy(self.transformbuffer);
    bufferallocator.destroy(self.drawbuffer);
    bufferallocator.destroy(self.indirectbuffer);
    bufferallocator.destroy(self.countbuffer);
}

// Initializes the memory arenas with MULTI-BUFFERING sizing
pub fn initEngineBuffers(self: *Self, core: *Core, descriptormanager: *DescriptorManager) !void {
    const allocator = &core.bufferallocator;
    const mb = Core.multibuffering; // Usually 2 or 3

    // 1. Giant Geometry Buffers (Static, no double-buffering needed)
    self.globalvertexbuffer = allocator.create(
        MAX_GEOMETRY_BYTES,
        c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    self.globalindexbuffer = allocator.create(
        MAX_GEOMETRY_BYTES,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    // 2. Data Arrays (CPU-written Ring Buffers)
    self.transformbuffer = allocator.create(
        @sizeOf(TransformData) * MAX_OBJECTS * mb, // <--- Ring Buffered!
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    self.drawbuffer = allocator.create(
        @sizeOf(DrawData) * MAX_OBJECTS * mb, // <--- Ring Buffered!
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );

    // 3. Compute Buffers (GPU-written Ring Buffers)
    self.indirectbuffer = allocator.create(
        @sizeOf(c.VkDrawIndirectCommand) * MAX_OBJECTS * mb, // <--- Ring Buffered!
        c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    self.countbuffer = allocator.create(
        @sizeOf(u32) * mb, // <--- Ring Buffered!
        c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    // 4. Uniform Buffers (Already Double buffered)
    for (&self.scenebuffers, 0..) |*buf, i| {
        buf.* = allocator.create(
            @sizeOf(SceneData),
            c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            c.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
        descriptormanager.writeDynamicSet(buf.*, @intCast(i));
    }
}

// App calls this to push a mesh into the Giant Buffer.
// Returns the DrawData struct with the correct 64-bit pointers!
pub fn uploadMesh(
    self: *Self,
    core: *Core,
    vertices: []const Vertex,
    indices: []const u32,
    material_idx: u32,
) DrawData {
    const v_size = vertices.len * @sizeOf(Vertex);
    const i_size = indices.len * @sizeOf(u32);

    if (self.vertex_byte_offset + v_size > MAX_GEOMETRY_BYTES or
        self.index_byte_offset + i_size > MAX_GEOMETRY_BYTES)
    {
        @panic("Giant Geometry Buffers are full!");
    }

    // Cast slices to raw bytes for the upload function
    const v_bytes = std.mem.sliceAsBytes(vertices);
    const i_bytes = std.mem.sliceAsBytes(indices);

    // Upload via Staging Buffer
    core.bufferallocator.upload(core, v_bytes, self.globalvertexbuffer, self.vertex_byte_offset);
    core.bufferallocator.upload(core, i_bytes, self.globalindexbuffer, self.index_byte_offset);

    // Get Base Device Addresses
    const base_v_addr = core.bufferallocator.getBufferAddress(self.globalvertexbuffer);
    const base_i_addr = core.bufferallocator.getBufferAddress(self.globalindexbuffer);

    // Create the bindless DrawData referencing the exact offsets
    const draw_data = DrawData{
        .vertexBuffer = base_v_addr + self.vertex_byte_offset,
        .indexBuffer = base_i_addr + self.index_byte_offset,
        .materialIndex = material_idx,
    };

    // Bump the allocators
    self.vertex_byte_offset += v_size;
    self.index_byte_offset += i_size;

    return draw_data;
}
