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
    position: Vec3 = .zeros,
    uv_x: f32 = 0,
    normal: Vec3 = .zeros,
    uv_y: f32 = 0,
    color: Vec4 = .zeros,
};

pub const Transform = extern struct {
    modelMatrix: Mat4x4,
    boundingSphere: Vec4,
};

pub const Mesh = extern struct {
    vertexBuffer: u64, // globalvertexbuffer ptr with offset
    indexBuffer: u64, // globalindexbuffer ptr with offset
    indexCount: u32,
    materialIndex: u32,
};

pub const SceneData = extern struct {
    view: Mat4x4,
    proj: Mat4x4,
    viewproj: Mat4x4,
    ambient_color: Vec4,
    sun_direction: Vec4,
    sun_color: Vec4,
    // addresses
    transforms: u64, // array of Transform
    cpu_transforms: u64, // array of Transform
    meshes: u64, // array of Mesh
    indirectCommands: u64, // address to the indirect struct
    drawCount: u64, // address to a single u32

    totalObjects: u32,
    _pad: u32 = 0,
};

const Self = @This();

// Limits for the engine
const MAX_GEOMETRY_BYTES = 64 * 1024 * 1024; // 64 MB for Verts/Indices
const MAX_OBJECTS = 10000;
const CPU_TRANSFORMS = 100;

// The Giant Geometry Buffers
globalvertexbuffer: AllocatedBuffer = undefined,
globalindexbuffer: AllocatedBuffer = undefined,

// Bump Allocator Trackers
vertex_byte_offset: u64 = 0,
index_byte_offset: u64 = 0,
object_offset: u32 = 0,

// Compute & App Arrays
transformbuffer: AllocatedBuffer = undefined,
transformbufferaddr: u64 = undefined,
cpuside_transformbuffer: AllocatedBuffer = undefined,
cpuside_transformbufferaddr: u64 = undefined,
meshbuffer: AllocatedBuffer = undefined,
meshbufferaddr: u64 = undefined,
indirectbuffer: AllocatedBuffer = undefined,
indirectbufferaddr: u64 = undefined,
countbuffer: AllocatedBuffer = undefined,
countbufferaddr: u64 = undefined,

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
    bufferallocator.destroy(self.meshbuffer);
    bufferallocator.destroy(self.cpuside_transformbuffer);
    bufferallocator.destroy(self.indirectbuffer);
    bufferallocator.destroy(self.countbuffer);
}

// Initializes the memory arenas with MULTI-BUFFERING sizing
pub fn initEngineBuffers(self: *Self, core: *Core, descriptormanager: *DescriptorManager) !void {
    const allocator = &core.bufferallocator;
    const mb = Core.multibuffering;

    // Giant Geometry Buffers
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

    // list of objects
    self.meshbuffer = allocator.create(
        @sizeOf(Mesh) * MAX_OBJECTS, // TODO consider double buffer if meshes change
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    // 3. Compute Buffers
    self.transformbuffer = allocator.create(
        @sizeOf(Transform) * MAX_OBJECTS * mb, // <--- Ring Buffered!
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );
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

    self.cpuside_transformbuffer = allocator.create(
        @sizeOf(Transform) * CPU_TRANSFORMS * mb, // <--- Ring Buffered!
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
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

    self.transformbufferaddr = core.bufferallocator.getBufferAddress(self.transformbuffer);
    self.cpuside_transformbufferaddr = core.bufferallocator.getBufferAddress(self.cpuside_transformbuffer);
    self.meshbufferaddr = core.bufferallocator.getBufferAddress(self.meshbuffer);
    self.indirectbufferaddr = core.bufferallocator.getBufferAddress(self.indirectbuffer);
    self.countbufferaddr = core.bufferallocator.getBufferAddress(self.countbuffer);

    // upload base address to prevent crash when no object are loaded
    const base_v_addr = core.bufferallocator.getBufferAddress(self.globalvertexbuffer);
    const base_i_addr = core.bufferallocator.getBufferAddress(self.globalindexbuffer);
    const mesh = Mesh{
        .vertexBuffer = base_v_addr,
        .indexBuffer = base_i_addr,
        .indexCount = 0,
        .materialIndex = 0,
    };
    BufferAllocator.upload(core, std.mem.asBytes(&mesh), self.meshbuffer, 0);
}

// App calls this to push a mesh into the Giant Buffer.
// Returns the DrawData struct with the correct 64-bit pointers!
pub fn uploadMesh(
    self: *Self,
    core: *Core,
    vertices: []const Vertex,
    indices: []const u32,
    material_idx: u32,
) void {
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
    BufferAllocator.upload(core, v_bytes, self.globalvertexbuffer, self.vertex_byte_offset);
    BufferAllocator.upload(core, i_bytes, self.globalindexbuffer, self.index_byte_offset);

    // Get Base Device Addresses
    const base_v_addr = core.bufferallocator.getBufferAddress(self.globalvertexbuffer);
    const base_i_addr = core.bufferallocator.getBufferAddress(self.globalindexbuffer);

    // Create the bindless DrawData referencing the exact offsets
    const mesh = Mesh{
        .vertexBuffer = base_v_addr + self.vertex_byte_offset,
        .indexBuffer = base_i_addr + self.index_byte_offset,
        .indexCount = @as(u32, @intCast(indices.len)),
        .materialIndex = material_idx,
    };

    // Bump the allocators
    self.vertex_byte_offset += v_size;
    self.index_byte_offset += i_size;

    // push to the objects list
    BufferAllocator.upload(core, std.mem.asBytes(&mesh), self.meshbuffer, self.object_offset * @sizeOf(Mesh));
    self.object_offset += 1;
}

// Writes the SceneData with dynamic offsets based on the frame
pub fn updateScene(
    self: *Self,
    frame_index: u8,
    aspect_ratio: f32,
    camerarot: Quat,
    camerapos: Vec3,
    time: f32,
) void {
    var ptr = @as(*SceneData, @ptrCast(@alignCast(self.scenebuffers[frame_index].info.pMappedData.?)));

    ptr.view = camerarot.view(camerapos);
    ptr.proj = Mat4x4.perspective(std.math.degreesToRadians(60.0), aspect_ratio, 0.1, 1000.0);
    ptr.viewproj = ptr.proj.mul(ptr.view);

    ptr.ambient_color = Vec4.new(1.0, 0.5, 0.0, 1.0);
    ptr.sun_color = Vec4.new(1.0, 1.0, 0.9, 1.0);
    ptr.sun_direction = Vec3.new(0.2, -0.5, 1.0).normalized().toVec4(0.0);

    // Calculate BDA base addresses
    const b_trans = self.transformbufferaddr;
    const b_meshes = self.meshbufferaddr;
    const b_indir = self.indirectbufferaddr;
    const b_count = self.countbufferaddr;
    const b_cpu_trans = self.cpuside_transformbufferaddr;

    // Calculate byte offsets for this specific frame
    const frame_u64 = @as(u64, frame_index);
    _ = time;

    // Inject the offset pointers directly into the shader!
    ptr.transforms = b_trans + (frame_u64 * MAX_OBJECTS * @sizeOf(Transform));
    ptr.cpu_transforms = b_cpu_trans + (frame_u64 * CPU_TRANSFORMS * @sizeOf(Transform));
    ptr.indirectCommands = b_indir + (frame_u64 * MAX_OBJECTS * @sizeOf(c.VkDrawIndirectCommand));
    ptr.drawCount = b_count + (frame_u64 * @sizeOf(u32));
    ptr.meshes = b_meshes;

    ptr.totalObjects = self.object_offset;
}

pub fn initEmptyMesh(self: *Self, core: *Core) void {
    const vertex_count = 256 * 256;
    const index_count = 255 * 255 * 6;
    const v_size = vertex_count * @sizeOf(Vertex);
    const i_size = index_count * @sizeOf(u32);

    const vertex_addr = core.bufferallocator.getBufferAddress(self.globalvertexbuffer);
    const index_addr = core.bufferallocator.getBufferAddress(self.globalindexbuffer);

    self.vertex_byte_offset += v_size;
    self.index_byte_offset += i_size;
    const mesh = Mesh{
        .vertexBuffer = vertex_addr + self.vertex_byte_offset,
        .indexBuffer = index_addr + self.index_byte_offset,
        .indexCount = index_count,
        .materialIndex = 0,
    };

    BufferAllocator.upload(core, std.mem.asBytes(&mesh), self.meshbuffer, self.object_offset * @sizeOf(Mesh));
    self.object_offset += 1;
}
