const std = @import("std");
const linalg = @import("../linalg.zig");
const debug = @import("debug.zig");
const c = @import("../clibs/clibs.zig").libs;
const DescriptorWriter = @import("DescriptorWriter.zig");
const Quat = linalg.Quat(f32);
const Vec3 = linalg.Vec3(f32);
const Vec4 = linalg.Vec4(f32);
const Mat4x4 = linalg.Mat4x4(f32);
const Core = @import("Core.zig");
const Device = @import("Device.zig");
const AllocatedBuffer = @import("BufferAllocator.zig").AllocatedBuffer;
const BufferAllocator = @import("BufferAllocator.zig");
const DescriptorManager = @import("DescriptorManager.zig");

pub const MaterialConstants = extern struct {
    colorfactors: Vec4,
    metalrough_factors: Vec4,
    padding: [14]Vec4,
};

pub const SceneData = extern struct {
    view: Mat4x4 = .zeros,
    proj: Mat4x4 = .zeros,
    viewproj: Mat4x4 = .zeros,
    ambient_color: Vec4 = .zeros,
    sunlight_dir: Vec4 = .zeros,
    sunlight_color: Vec4 = .zeros,
    objects: u64 = 0, // SBBO address
};

pub const ObjectData = extern struct {
    modelmatrix: Mat4x4 = .zeros,
    vertexbuffer: u64 = 0, // 64-bit address
    indexbuffer: u64 = 0, // 64-bit address
    materialindex: u32 = 0,
    _pad1: u32 = 0,
    _pad2: u32 = 0,
    _pad3: u32 = 0,
};

pub const Vertex = extern struct {
    position: Vec3,
    uv_x: f32,
    normal: Vec3,
    uv_y: f32,
    color: Vec4,

    pub fn new(
        p1: f32,
        p2: f32,
        p3: f32,
        n1: f32,
        n2: f32,
        n3: f32,
        c1: f32,
        c2: f32,
        c3: f32,
        c4: f32,
        x: f32,
        y: f32,
    ) Vertex {
        return .{
            .position = .new(p1, p2, p3),
            .normal = .new(n1, n2, n3),
            .color = .new(c1, c2, c3, c4),
            .uv_x = x,
            .uv_y = y,
        };
    }
};

pub const GeoSurface = struct {
    start_index: u32,
    count: u32,
};

pub const MeshAsset = struct {
    surfaces: std.ArrayList(GeoSurface),
    vertices: []Vertex = undefined,
    indices: []u32 = undefined,
};

const Self = @This();

const MAX_VERTICES = 10_000;
const MAX_INDICES = 10_000;
const MAX_INSTANCES = 1000;

globalvertexbuffer: AllocatedBuffer = undefined,
globalindexbuffer: AllocatedBuffer = undefined,
// Trackers for the Ring Buffer
dynamicvertexoffset: u32 = 0,
dynamicindexoffset: u32 = 0,
objecttablebuffer: AllocatedBuffer = undefined,
// contains data updated evry frame trough uniform
scenebuffers: [Core.multibuffering]AllocatedBuffer = @splat(undefined),
indirectbuffer: AllocatedBuffer = undefined,

pub fn init() Self {
    return .{};
}

pub fn destroyBuffers(self: *Self, bufferallocator: *BufferAllocator) void {
    for (self.scenebuffers) |buf| bufferallocator.destroy(buf);
    bufferallocator.destroy(self.globalvertexbuffer);
    bufferallocator.destroy(self.globalindexbuffer);
    bufferallocator.destroy(self.objecttablebuffer);
    bufferallocator.destroy(self.indirectbuffer);
}

/// DEBUG dummy data
pub fn initDummy(self: *Self, bufferallocator: *BufferAllocator, descriptormanager: *DescriptorManager) void {
    const scenedata: SceneData = .{};
    const objectdata: ObjectData = .{};
    self.objecttablebuffer = bufferallocator.create(
        @sizeOf(ObjectData),
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU, // cpu for now
    );
    const objectdataptr: *ObjectData = @ptrCast(@alignCast(self.objecttablebuffer.info.pMappedData.?));
    objectdataptr.* = objectdata;
    for (&self.scenebuffers, 0..) |*buf, i| {
        buf.* = bufferallocator.create(
            @sizeOf(SceneData),
            c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            c.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
        const scenedataptr: *SceneData = @ptrCast(@alignCast(buf.info.pMappedData.?));
        scenedataptr.* = scenedata;
        scenedataptr.objects = bufferallocator.getBufferAddress(self.objecttablebuffer);
        descriptormanager.writeDynamicSet(buf.*, @intCast(i));
    }
}

/// DEBUG test data
pub fn initTest(
    self: *Self,
    bufferallocator: *BufferAllocator,
    descriptormanager: *DescriptorManager,
) !void {
    // --- 2. Create Global Geometry Buffers ---
    // Note: Must include SHADER_DEVICE_ADDRESS_BIT to get the u64 pointer!
    self.globalvertexbuffer = bufferallocator.create(
        @sizeOf(Vertex) * MAX_VERTICES,
        c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT |
            c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU, // Simple CPU write for now
    );

    self.globalindexbuffer = bufferallocator.create(
        @sizeOf(u32) * MAX_INDICES,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT |
            c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU, // Simple CPU write for now
    );

    // --- 3. Upload Cube Data ---
    // Get mapped pointers
    const v_ptr = @as([*]Vertex, @ptrCast(@alignCast(self.globalvertexbuffer.info.pMappedData.?)));
    const i_ptr = @as([*]u32, @ptrCast(@alignCast(self.globalindexbuffer.info.pMappedData.?)));

    // Define Cube (8 vertices)
    const cube_verts = [_]Vertex{
        Vertex.new(-0.5, -0.5, 0.5, 0, 0, 1, 1, 1, 1, 1, 0, 0), // 0
        Vertex.new(0.5, -0.5, 0.5, 0, 0, 1, 0, 1, 0, 1, 1, 0), // 1
        Vertex.new(0.5, 0.5, 0.5, 0, 0, 1, 0, 0, 1, 1, 1, 1), // 2
        Vertex.new(-0.5, 0.5, 0.5, 0, 0, 1, 1, 1, 0, 1, 0, 1), // 3
        Vertex.new(0.5, -0.5, -0.5, 0, 0, -1, 1, 0, 1, 1, 0, 0), // 4
        Vertex.new(-0.5, -0.5, -0.5, 0, 0, -1, 0, 1, 1, 1, 1, 0), // 5
        Vertex.new(-0.5, 0.5, -0.5, 0, 0, -1, 1, 1, 1, 1, 1, 1), // 6
        Vertex.new(0.5, 0.5, -0.5, 0, 0, -1, 0, 0, 1, 1, 0, 1), // 7
    };
    const quad_verts = [_]Vertex{
        Vertex.new(-100.0, -100.0, 0.0, 0, 0, 1, 0.1, 0.1, 0.1, 0, 0, 0), // 0
        Vertex.new(100.0, -100.0, 0.0, 0, 0, 1, 0.1, 0.1, 0.1, 0, 1, 0), // 1
        Vertex.new(100.0, 100.0, 0.0, 0, 0, 1, 0.1, 0.1, 0.1, 0, 1, 1), // 2
        Vertex.new(-100.0, 100.0, 0.0, 0, 0, 1, 0.1, 0.1, 0.1, 0, 0, 1), // 3
    };
    // 36 indices
    const cube_indices = [_]u32{
        0, 1, 2, 2, 3, 0, // Front
        1, 4, 7, 7, 2, 1, // Right
        4, 5, 6, 6, 7, 4, // Back
        5, 0, 3, 3, 6, 5, // Left
        5, 4, 1, 1, 0, 5, // Bottom
        3, 2, 7, 7, 6, 3, // Top
    };
    // 6 indices
    const quad_indices = [_]u32{
        0, 1, 2, 2, 3, 0, // Front
    };

    @memcpy(v_ptr[0..quad_verts.len], &quad_verts);
    @memcpy(v_ptr[quad_verts.len .. cube_verts.len + quad_verts.len], &cube_verts);
    @memcpy(i_ptr[0..quad_indices.len], &quad_indices);
    @memcpy(i_ptr[quad_indices.len .. cube_indices.len + quad_indices.len], &cube_indices);

    // We need the base pointer of the buffer to store in our MeshTable
    const vertex_addr = bufferallocator.getBufferAddress(self.globalvertexbuffer);
    const index_addr = bufferallocator.getBufferAddress(self.globalindexbuffer);

    // --- 5. reate & Fill Tables ---
    self.objecttablebuffer = bufferallocator.create(
        @sizeOf(ObjectData) * MAX_INSTANCES,
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU, // cpu for now
    );

    // --- 1. Create Scene Buffers (Double Buffered) ---
    const scenedata: SceneData = .{};
    for (&self.scenebuffers, 0..) |*buf, i| {
        buf.* = bufferallocator.create(
            @sizeOf(SceneData),
            c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            c.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
        const scenedataptr: *SceneData = @ptrCast(@alignCast(buf.info.pMappedData.?));
        scenedataptr.* = scenedata;
        scenedataptr.objects = bufferallocator.getBufferAddress(self.objecttablebuffer);
        descriptormanager.writeDynamicSet(buf.*, @intCast(i));
    }
    // 1. Calculate size for Double/Triple Buffering
    // If we support 1000 objects, and have 2 frames in flight, we need space for 2000.
    self.indirectbuffer = bufferallocator.create(
        @sizeOf(c.VkDrawIndirectCommand) * MAX_INSTANCES,
        c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU, //cpu for now
    );

    // --- 6. Set up the Scene Objects ---
    const obj_ptr = @as([*]ObjectData, @ptrCast(@alignCast(self.objecttablebuffer.info.pMappedData.?)));
    const cmd_ptr = @as([*]c.VkDrawIndirectCommand, @ptrCast(@alignCast(self.indirectbuffer.info.pMappedData.?)));

    // Mesh Entry 0: The Cube
    // Since we only uploaded one mesh at offset 0, the address is Base + 0
    // Create 3 Instances
    for (0..3) |i| {
        // Init Instance (Matrices will be updated in rotateDummy)
        const pose: Mat4x4 = .identity;
        obj_ptr[i] = ObjectData{
            .modelmatrix = pose,
            .vertexbuffer = vertex_addr + quad_verts.len * @sizeOf(Vertex), // offset into the buffer
            .indexbuffer = index_addr + quad_indices.len * @sizeOf(u32), // offset into the buffer
            .materialindex = 0,
            ._pad1 = 0,
            ._pad2 = 0,
            ._pad3 = 0,
        };
        // Init Draw Command
        cmd_ptr[i] = c.VkDrawIndirectCommand{
            .vertexCount = cube_indices.len, // 36 indices, // This becomes gl_VertexIndex
            .instanceCount = 1,
            .firstVertex = 0, // Offset in vertex array (0 since we fetched indices manually)
            .firstInstance = @intCast(i), // this becomes gl_BaseInstance
        };
    }
    const pose: Mat4x4 = .identity;
    obj_ptr[3] = ObjectData{
        .modelmatrix = pose,
        .vertexbuffer = vertex_addr, // offset into the buffer
        .indexbuffer = index_addr, // offset into the buffer
        .materialindex = 0,
        ._pad1 = 0,
        ._pad2 = 0,
        ._pad3 = 0,
    };
    // Init Draw Command
    cmd_ptr[3] = c.VkDrawIndirectCommand{
        .vertexCount = quad_indices.len, // 36 indices, // This becomes gl_VertexIndex
        .instanceCount = 1,
        .firstVertex = 0, // Offset in vertex array (0 since we fetched indices manually)
        .firstInstance = 3, // this becomes gl_BaseInstance
    };
}

/// DEBUG
pub fn rotateDummy(self: *Self, frameindex: u8, time: f32) void {
    const base_ptr = @as([*]ObjectData, @ptrCast(@alignCast(self.objecttablebuffer.info.pMappedData.?)));
    var frame_offset = @as(usize, @intCast(frameindex)) * MAX_INSTANCES;
    frame_offset = 0; // no double buffering for now
    const inst_ptr = base_ptr + frame_offset; // Pointer arithmetic
    const angle = time * std.math.pi; // Half rotation per second
    {
        const rot = Mat4x4.rotation(Vec3.unit_y, angle);
        inst_ptr[0].modelmatrix = rot.translate(.new(-2.0, 5.0, 2.0));
    }
    {
        const rot = Mat4x4.rotation(Vec3.unit_x, angle);
        inst_ptr[1].modelmatrix = rot.translate(.new(0.0, 2.0, 2.0));
    }
    {
        const rot = Mat4x4.rotation(Vec3.unit_z, angle);
        inst_ptr[2].modelmatrix = rot.translate(.new(2.0, 5.0, 2.0));
    }
}

/// DEBUG
pub fn updateScene(
    self: *Self,
    frame_index: u8,
    aspect_ratio: f32,
    camerarot: Quat,
    camerapos: Vec3,
    time: f32,
) void {
    var ptr = @as(*SceneData, @ptrCast(@alignCast(self.scenebuffers[frame_index].info.pMappedData.?)));
    const view = camerarot.view(camerapos);
    const fov_radians = std.math.degreesToRadians(60.0);
    var proj = Mat4x4.perspective(fov_radians, aspect_ratio, 0.1, 1000.0);
    ptr.view = view;
    ptr.proj = proj;
    ptr.viewproj = proj.mul(view);
    ptr.ambient_color = Vec4.new(1.0, 0.5, 0.0, 1.0);
    ptr.sunlight_color = Vec4.new(1.0, 1.0, 0.9, 1.0);
    const sun_dir = Vec3.new(0.2, -0.5, 1.0).normalized();
    ptr.sunlight_dir = sun_dir.toVec4(0.0);
    // _ = delta;
    self.rotateDummy(frame_index, time);
}

fn initGrid() []Vertex {
    const numlinesx = 99;
    const numlinesy = 99;
    const totalLines = numlinesx + numlinesy + 1;
    var lines: [totalLines]Vertex = undefined;
    const spacing = 1;
    const halfWidth = (numlinesx - 1) * spacing * 0.5;
    const halfDepth = (numlinesy - 1) * spacing * 0.5;
    const color: Vec4 = .new(0.024, 0.024, 0.024, 1.0);
    const xcolor: Vec4 = .new(1.000, 0.162, 0.078, 1.0);
    const ycolor: Vec4 = .new(0.529, 0.949, 0.204, 1.0);
    const zcolor: Vec4 = .new(0.114, 0.584, 0.929, 1.0);
    const rgba8: f32 = @bitCast(color.packU8());
    const xcol: f32 = @bitCast(xcolor.packU8());
    const ycol: f32 = @bitCast(ycolor.packU8());
    const zcol: f32 = @bitCast(zcolor.packU8());
    var i: u32 = 0;
    while (i < numlinesx) : (i += 1) {
        const floati: f32 = @floatFromInt(i); // X coord changes
        const x = (floati * spacing) - halfDepth;
        const p0: Vec3 = .new(x, -halfWidth, 0); // Z extent fixed
        const p1: Vec3 = .new(x, halfWidth, 0); // Z extent fixed
        const p2: Vec4 = .zeros;
        // No allocation needed here, append moves the struct
        if (i == numlinesx / 2) {
            lines[i] = .new(p0, p1, p2, 0.2, ycol);
        } else {
            lines[i] = .new(p0, p1, p2, 0.08, rgba8);
        }
    }
    var j: u32 = 0;
    while (j < numlinesy) : (j += 1) {
        const floatj: f32 = @floatFromInt(j);
        const y = (floatj * spacing) - halfWidth; // Z coord changes
        const p0: Vec3 = .new(-halfDepth, y, 0); // X extent fixed
        const p1: Vec3 = .new(halfDepth, y, 0); // X extent fixed
        const p2: Vec4 = .zeros;
        if (j == numlinesy / 2) {
            lines[i + j] = .new(p0, p1, p2, 0.2, xcol);
        } else {
            lines[i + j] = .new(p0, p1, p2, 0.08, rgba8);
        }
    }

    const p0: Vec3 = .new(0, 0, -halfDepth); // X extent fixed
    const p1: Vec3 = .new(0, 0, halfDepth); // X extent fixed
    const p2: Vec4 = .zeros;
    lines[i + j] = .new(p0, p1, p2, 0.2, zcol);
}
