// ┌───────────────┬─────────────────────────────┬────────────────────────────────┐
// │               │ Static (Rarely changes)     │ Dynamic (Changes every frame)  │
// ├───────────────┼─────────────────────────────┼────────────────────────────────┤
// │ CPU Controlled│ GLTF Meshes,                │ UI Vertices, Camera Transforms,│
// │               │ Textures uploaded from disk.│ Player Input state.            │
// ├───────────────┼─────────────────────────────┼────────────────────────────────┤
// │ GPU Controlled│ Procedural Terrain,         │ GPU Culling output             │
// │               │ Baked Lightmaps,            │ (Visible instances),           │
// │               │ Raytracing BVHs.            │ Particle Simulations.          │
// └───────────────┴─────────────────────────────┴────────────────────────────────┘

const std = @import("std");
const errors = @import("errors.zig");
const c = @import("c");
const config = @import("config");
const imageop = @import("imageop.zig");
const Core = @import("Core.zig");
const DescriptorManager = @import("DescriptorManager.zig");
const AsyncContext = @import("AsyncContext.zig");
const Camera = @import("../Camera.zig");
const Arena = @import("Arena.zig").Arena;
const Quat = @import("../math/Quat.zig").Quat(f32);
const DualQuat = @import("../math/Quat.zig").DualQuat(f32);
const Vec2 = @import("../math/Vec.zig").Vec2(f32);
const Vec3 = @import("../math/Vec.zig").Vec3(f32);
const Vec4 = @import("../math/Vec.zig").Vec4(f32);
const Mat2x2 = @import("../math/Mat.zig").Mat2x2(f32);
const Mat3x3 = @import("../math/Mat.zig").Mat3x3(f32);
const Mat4x4 = @import("../math/Mat.zig").Mat4x4(f32);

pub const MAX_GEOMETRY_BYTES = 64 * 1024 * 1024; // 64 MB for verts/indices
pub const MAX_TEXTURES = 4096; // 4 KB for images
pub const MAX_OBJECTS = 4096;
pub const CPU_TRANSFORMS = 100;

pub const AllocatedBuffer = struct {
    buffer: c.VkBuffer,
    allocation: c.VmaAllocation,
    info: c.VmaAllocationInfo,

    pub fn destroy(self: *@This(), gpuallocator: c.VmaAllocator) void {
        c.vmaDestroyBuffer(gpuallocator, self.buffer, self.allocation);
    }
};

pub const AllocatedImage = struct {
    image: c.VkImage,
    allocation: c.VmaAllocation,
    view: c.VkImageView,
    info: c.VmaAllocationInfo,
    bindless_index: u32,

    pub fn destroy(
        self: *@This(),
        gpuallocator: c.VmaAllocator,
        device: c.VkDevice,
        alloc_callbacks: ?*c.VkAllocationCallbacks,
    ) void {
        c.vkDestroyImageView(device, self.view, alloc_callbacks);
        c.vmaDestroyImage(gpuallocator, self.image, self.allocation);
    }
};

// ========================================================================
// GPU STRUCTS (Must match Slang perfectly)
// ========================================================================

pub const Vertex = extern struct {
    position: Vec3 = .zeros,
    uv_x: f32 = 0,
    normal: Vec3 = .zeros,
    uv_y: f32 = 0,
    color: Vec4 = .zeros,
};

pub const BoundingBox = extern struct {
    center: Vec3 = .zeros,
    theta: f32 = 0,
    whd: Vec3 = .zeros,
    phi: f32 = 0,
};

pub const Mesh = extern struct {
    vertexBuffer: u64,
    indexBuffer: u64,
    indexCount: u32,
    pad: u32,
};

pub const UIElement = extern struct {
    vertexBuffer: u64,
    vertexCount: u32,
    pad: u32,
};

pub const MeshInstance = extern struct {
    meshBuffer: u64, // *Mesh
    transformIndex: u32,
    materialIndex: u32,
};

pub const UIInstance = extern struct {
    UIBuffer: u64, // *UIElement
    transformIndex: u32,
    type: u32, // this is how we interpet the vertices
};

pub const VertexCount = extern struct {
    vertexOffset: u32,
    indexOffset: u32,
};

pub const DrawCount = u32;

pub const MeshCount = u32;

pub const UICount = u32;

pub const Position = Vec4;

pub const Orientation = Quat;

pub const Transform = DualQuat;

pub const DeviceBufferAddresses = extern struct {
    transforms: c.VkDeviceAddress,
    cpu_transforms: c.VkDeviceAddress,
    meshes: c.VkDeviceAddress,
    uiobjects: c.VkDeviceAddress,
    indirectCommands: c.VkDeviceAddress,
    drawcount: c.VkDeviceAddress,
    drawMap: c.VkDeviceAddress,
    pad0: c.VkDeviceAddress = 0,
};

pub const SceneData = extern struct {
    addresses: DeviceBufferAddresses,
    viewproj: Mat4x4, // use DualQuat??
    ambient_color: Vec4,
    sun_direction: Vec4,
    sun_color: Vec4,
    viewport: Vec4,
    meshcount: u32,
    uielemcount: u32,
    pad0: u32 = 0,
    pad1: u32 = 0,
};

// ========================================================================
// ResourceManager
// ========================================================================

const Self = @This();

device: c.VkDevice,
gpuallocator: c.VmaAllocator,
alloc_callbacks: ?*c.VkAllocationCallbacks,

global_sampler: c.VkSampler = undefined,

// --- Core arenas ---
static_cpu_arena: Arena = undefined,
dynamic_cpu_arena: Arena = undefined,
static_gpu_arena: Arena = undefined,
dynamic_gpu_arena: Arena = undefined,
readback_arena: Arena = undefined,

// --- Sub-Allocated Arenas ---
// Sub-allocated from static_gpu_arena (Static meshes & UI definitions)
vertex_arena: Arena = undefined,
index_arena: Arena = undefined,
mesh_arena: Arena = undefined,
ui_arena: Arena = undefined,

// Sub-allocated from dynamic_gpu_arena (Double-buffered, GPU-computed objects)
meshinstance_arena: Arena = undefined,
uiinstance_arena: Arena = undefined,
transform_arena: Arena = undefined,
indirect_arena: Arena = undefined,
count_arena: Arena = undefined,
draw_count: Arena = undefined,
drawmap_arena: Arena = undefined,

// Sub-allocated from dynamic_cpu_arena (Double-buffered, Host-visible)
dynamicvertex_arena: Arena = undefined,
cputransform_arena: Arena = undefined,

// Uniforms and binded buffers
scenebuffers: [Core.multibuffering]AllocatedBuffer = @splat(undefined),

texture_count: u32 = 0,

pub fn init(
    device: c.VkDevice,
    gpuallocator: c.VmaAllocator,
    alloc_callbacks: ?*c.VkAllocationCallbacks,
) Self {
    return .{
        .device = device,
        .alloc_callbacks = alloc_callbacks,
        .gpuallocator = gpuallocator,
    };
}

pub fn flush(self: *Self, buffer: AllocatedBuffer, offset: c.VkDeviceSize, size: c.VkDeviceSize) void {
    errors.checkVkPanic(c.vmaFlushAllocation(self.gpuallocator, buffer.allocation, offset, size));
}

pub fn destroyBuffers(self: *Self) void {
    for (&self.scenebuffers) |*buf| buf.destroy(self.gpuallocator);
    c.vkDestroySampler(self.device, self.global_sampler, self.alloc_callbacks);

    if (self.static_cpu_arena.buffer.buffer != null) self.static_cpu_arena.buffer.destroy(self.gpuallocator);
    if (self.dynamic_cpu_arena.buffer.buffer != null) self.dynamic_cpu_arena.buffer.destroy(self.gpuallocator);
    if (self.static_gpu_arena.buffer.buffer != null) self.static_gpu_arena.buffer.destroy(self.gpuallocator);
    if (self.dynamic_gpu_arena.buffer.buffer != null) self.dynamic_gpu_arena.buffer.destroy(self.gpuallocator);
    if (self.readback_arena.buffer.buffer != null) self.readback_arena.buffer.destroy(self.gpuallocator);
}

// Initializes the memory arenas with MULTI-BUFFERING sizing
pub fn initEngineBuffers(self: *Self, core: *Core, descriptormanager: *DescriptorManager) !void {
    const mb = Core.multibuffering;

    // ====================================================================
    // Core arenas
    // ====================================================================

    // 1. Static CPU Arena (CPU to GPU, Write once)
    const static_cpu_buf = self.createBuffer(
        128 * 1024 * 1024, // 128 MB
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
            c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    self.static_cpu_arena = Arena.init(static_cpu_buf, 0, 0, 128 * 1024 * 1024);

    // 2. Dynamic CPU Arena (CPU to GPU, Ring buffered or persistently mapped)
    const dynamic_cpu_buf = self.createBuffer(
        64 * 1024 * 1024, // 64 MB
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    {
        const addr = self.getBufferAddress(dynamic_cpu_buf);
        self.dynamic_cpu_arena = Arena.init(dynamic_cpu_buf, addr, 0, 64 * 1024 * 1024);
    }

    // 3. Static GPU Arena (GPU Only, procedural static meshes, loaded once)
    const static_gpu_buf = self.createBuffer(
        256 * 1024 * 1024, // 256 MB
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
            c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    {
        const addr = self.getBufferAddress(static_gpu_buf);
        self.static_gpu_arena = Arena.init(static_gpu_buf, addr, 0, 256 * 1024 * 1024);
    }

    // 4. Dynamic GPU Arena (GPU Only, cleared every frame for compute output)
    const dynamic_gpu_buf = self.createBuffer(
        128 * 1024 * 1024, // 128 MB
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
            c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    {
        const addr = self.getBufferAddress(dynamic_gpu_buf);
        self.dynamic_gpu_arena = Arena.init(dynamic_gpu_buf, addr, 0, 128 * 1024 * 1024);
    }

    // 5. Readback Arena (GPU to CPU, for retrieving data)
    const readback_buf = self.createBuffer(
        16 * 1024 * 1024, // 16 MB
        c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VMA_MEMORY_USAGE_GPU_TO_CPU,
    );
    // does not need device buffer address
    self.readback_arena = Arena.init(readback_buf, 0, 0, 16 * 1024 * 1024);

    // ====================================================================
    // Static arenas (change rarely) mega buffers GPU Only
    // ====================================================================

    self.vertex_arena = try self.static_gpu_arena.subAllocateArena(MAX_GEOMETRY_BYTES);
    self.index_arena = try self.static_gpu_arena.subAllocateArena(MAX_GEOMETRY_BYTES);
    self.mesh_arena = try self.static_gpu_arena.subAllocateArena(@sizeOf(Mesh) * MAX_OBJECTS);
    self.ui_arena = try self.static_gpu_arena.subAllocateArena(@sizeOf(UIElement) * MAX_OBJECTS);

    // ====================================================================
    // Dynamic arenas (double buffered) GPU Only
    // ====================================================================

    self.meshinstance_arena = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(MeshInstance) * MAX_OBJECTS * mb);
    self.uiinstance_arena = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(UIInstance) * MAX_OBJECTS * mb);
    self.transform_arena = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(Transform) * MAX_OBJECTS * mb);
    if (config.meshshading) {
        self.indirect_arena = try self.dynamic_gpu_arena.subAllocateArena(
            @sizeOf(c.VkDrawMeshTasksIndirectCommandEXT) * MAX_OBJECTS * mb,
        );
    } else {
        self.indirect_arena = try self.dynamic_gpu_arena.subAllocateArena(
            @sizeOf(c.VkDrawIndirectCommand) * MAX_OBJECTS * mb,
        );
    }
    self.count_arena = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(VertexCount) * mb);
    self.draw_count = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(DrawCount) * mb);
    self.drawmap_arena = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(u32) * MAX_OBJECTS * mb);

    // ====================================================================
    // Dynamic arenas Host visible (CPU visible)
    // ====================================================================

    self.dynamicvertex_arena = try self.dynamic_cpu_arena.subAllocateArena(@sizeOf(Vertex) * MAX_OBJECTS * mb);
    self.cputransform_arena = try self.dynamic_cpu_arena.subAllocateArena(@sizeOf(Transform) * CPU_TRANSFORMS * mb);

    // ====================================================================
    // Uniforms
    // ====================================================================
    for (&self.scenebuffers, 0..) |*buf, i| {
        buf.* = self.createBuffer(
            @sizeOf(SceneData),
            c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            c.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
        descriptormanager.writeDynamicSet(core.cpuallocator, buf.*, @intCast(i));
    }

    const sampler_info = c.VkSamplerCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = c.VK_FILTER_LINEAR,
        .minFilter = c.VK_FILTER_LINEAR,
        .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .anisotropyEnable = c.VK_TRUE,
        .maxAnisotropy = 16.0,
        .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = c.VK_FALSE,
        .compareEnable = c.VK_FALSE,
        .compareOp = c.VK_COMPARE_OP_ALWAYS,
        .minLod = 0.0,
        .maxLod = c.VK_LOD_CLAMP_NONE,
    };
    errors.checkVkPanic(c.vkCreateSampler(
        self.device,
        &sampler_info,
        self.alloc_callbacks,
        &self.global_sampler,
    ));
    // fill pointers with 0 so we dont crash the gpu
    self.initEmptyMesh(core, 0) catch @panic("Failed to init empty mesh");
    self.initEmptyUI(core, 0) catch @panic("Failed to init empty UI");
}

pub fn getMeshInstanceCount(self: *const Self) u32 {
    return self.meshinstance_arena.allocator.offset / @sizeOf(MeshInstance) / Core.multibuffering;
}

pub fn getUIInstanceCount(self: *const Self) u32 {
    return self.uiinstance_arena.allocator.offset / @sizeOf(UIInstance) / Core.multibuffering;
}

// Writes the SceneData with dynamic offsets based on the frame
pub fn updateScene(self: *Self, frame_index: u8, aspect_ratio: f32, camera: Camera, time: f32) void {
    var ptr = @as(*SceneData, @ptrCast(@alignCast(self.scenebuffers[frame_index].info.pMappedData.?)));

    const view = camera.view();
    var proj = Camera.perspective(std.math.degreesToRadians(60.0), aspect_ratio, 0.1, 1000.0);
    ptr.viewproj = proj.mul(view);

    ptr.ambient_color = Vec4.new(1.0, 0.5, 0.0, 1.0);
    ptr.sun_color = Vec4.new(1.0, 1.0, 0.9, 1.0);
    ptr.sun_direction = Vec3.new(0.2, -0.5, 1.0).normalized().toVec4(0.0);
    ptr.viewport = Vec4.new(2000, 1200, 0, 0);

    // Calculate BDA base addresses
    const b_trans = self.transform_arena.getAddress(self.transform_arena.allocator.start);
    const b_meshes = self.meshinstance_arena.getAddress(self.meshinstance_arena.allocator.start);
    const b_indir = self.indirect_arena.getAddress(self.indirect_arena.allocator.start);
    const b_cpu_trans = self.cputransform_arena.getAddress(self.cputransform_arena.allocator.start);
    const b_drawmap = self.drawmap_arena.getAddress(self.drawmap_arena.allocator.start);
    const b_ui = self.uiinstance_arena.getAddress(self.uiinstance_arena.allocator.start);

    // Calculate byte offsets for this specific frame
    const frame_u64 = @as(u64, frame_index);
    _ = time;

    // Inject the offset pointers directly into the shader!
    ptr.addresses.transforms = b_trans + (frame_u64 * MAX_OBJECTS * @sizeOf(Transform));
    ptr.addresses.cpu_transforms = b_cpu_trans + (frame_u64 * CPU_TRANSFORMS * @sizeOf(Transform));
    ptr.addresses.drawcount = self.draw_count.getAddress(self.draw_count.allocator.start) + (frame_u64 * @sizeOf(DrawCount));
    ptr.addresses.drawMap = b_drawmap + (frame_u64 * MAX_OBJECTS * @sizeOf(u32));
    ptr.addresses.meshes = b_meshes + (frame_u64 * MAX_OBJECTS * @sizeOf(MeshInstance));
    ptr.addresses.uiobjects = b_ui + (frame_u64 * MAX_OBJECTS * @sizeOf(UIInstance));
    ptr.meshcount = @intCast((self.meshinstance_arena.allocator.current - self.meshinstance_arena.allocator.start) / @sizeOf(MeshInstance));
    ptr.uielemcount = @intCast((self.uiinstance_arena.allocator.current - self.uiinstance_arena.allocator.start) / @sizeOf(UIInstance));
    if (config.meshshading) {
        ptr.addresses.indirectCommands = b_indir +
            (frame_u64 * MAX_OBJECTS * @sizeOf(c.VkDrawMeshTasksIndirectCommandEXT));
    } else {
        ptr.addresses.indirectCommands = b_indir +
            (frame_u64 * MAX_OBJECTS * @sizeOf(c.VkDrawIndirectCommand));
    }
}

pub fn createBuffer(
    self: *Self,
    alloc_size: usize,
    usage: c.VkBufferUsageFlags,
    memory_usage: c.VmaMemoryUsage,
) AllocatedBuffer {
    const buffer_info: c.VkBufferCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = alloc_size,
        .usage = usage,
    };

    const vma_alloc_info: c.VmaAllocationCreateInfo = .{
        .usage = memory_usage,
        .flags = c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
    };

    var new_buffer: AllocatedBuffer = undefined;
    errors.checkVkPanic(c.vmaCreateBuffer(
        self.gpuallocator,
        &buffer_info,
        &vma_alloc_info,
        &new_buffer.buffer,
        &new_buffer.allocation,
        &new_buffer.info,
    ));
    return new_buffer;
}

pub fn upload(
    self: *Self,
    asynccontext: *AsyncContext,
    data_slice: []const u8,
    buffer: AllocatedBuffer,
    dst_offset: c.VkDeviceSize,
) void {
    const size = data_slice.len;

    // Create staging buffer (CPU visible)
    const staging_buffer = self.createBuffer(
        size,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VMA_MEMORY_USAGE_CPU_ONLY,
    );
    defer c.vmaDestroyBuffer(self.gpuallocator, staging_buffer.buffer, staging_buffer.allocation);

    if (staging_buffer.info.pMappedData) |mapped_data_ptr| {
        const byte_data_ptr = @as([*]u8, @ptrCast(mapped_data_ptr));
        const staging_slice = byte_data_ptr[0..size];
        @memcpy(staging_slice, data_slice);
    } else {
        std.log.err("Failed to map staging buffer.", .{});
        @panic("");
    }

    // Copy from Staging to Giant Buffer at the correct offset
    asynccontext.submitBegin();
    const copy_region = c.VkBufferCopy{
        .srcOffset = 0,
        .dstOffset = dst_offset,
        .size = size,
    };
    const cmd = asynccontext.commandbuffer;
    c.vkCmdCopyBuffer(cmd, staging_buffer.buffer, buffer.buffer, 1, &copy_region);
    asynccontext.submitEnd();
}

pub fn getBufferAddress(self: *Self, buffer: AllocatedBuffer) c.VkDeviceAddress {
    const deviceaddressinfo = c.VkBufferDeviceAddressInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        .pNext = null, // Always initialize pNext
        .buffer = buffer.buffer,
    };
    const adr = c.vkGetBufferDeviceAddress(self.device, &deviceaddressinfo);
    if (adr == 0) {
        std.log.err("Failed to get buffer device address for SSBO. Is the feature enabled?", .{});
        c.vmaDestroyBuffer(self.gpuallocator, buffer.buffer, buffer.allocation);
        @panic("");
    }
    return adr;
}

pub fn requestReadback(
    self: *Self,
    cmd: c.VkCommandBuffer,
    src_buffer: c.VkBuffer,
    size: c.VkDeviceSize,
    src_offset: c.VkDeviceSize,
) !u32 {
    const dst_offset = try self.readback_arena.allocate(@intCast(size));

    const copy_region = c.VkBufferCopy{
        .srcOffset = src_offset,
        .dstOffset = dst_offset,
        .size = size,
    };

    c.vkCmdCopyBuffer(cmd, src_buffer, self.readback_arena.buffer.buffer, 1, &copy_region);
    return dst_offset;
}

pub fn createImage(
    self: *Self,
    size: c.VkExtent3D,
    format: c.VkFormat,
    usage: c.VkImageUsageFlags,
    mipmapped: bool,
) AllocatedImage {
    var new_image: AllocatedImage(1) = undefined;
    var img_info = c.VkImageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = null,
        .usage = usage,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = size,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
    };

    if (mipmapped) {
        const levels = @floor(std.math.log2(@as(f32, @floatFromInt(@max(size.width, size.height)))) + 1);
        img_info.mipLevels = @intFromFloat(levels);
    }

    const alloc_info: c.VmaAllocationCreateInfo = .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };
    errors.checkVkPanic(c.vmaCreateImage(
        self.gpuallocator,
        &img_info,
        &alloc_info,
        &new_image.image,
        &new_image.allocation,
        null,
    ));
    var aspect_flags = c.VK_IMAGE_ASPECT_COLOR_BIT;
    if (format == c.VK_FORMAT_D32_SFLOAT) {
        aspect_flags = c.VK_IMAGE_ASPECT_DEPTH_BIT;
    }

    return new_image;
}

pub fn createView(device: c.VkDevice, image: c.VkImage, format: c.VkFormat, miplevels: u32) c.VkImageView {
    var image_view: c.VkImageView = undefined;

    var aspect_flags = c.VK_IMAGE_ASPECT_COLOR_BIT;
    if (format == c.VK_FORMAT_D32_SFLOAT) {
        aspect_flags = c.VK_IMAGE_ASPECT_DEPTH_BIT;
    }
    const view_info = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .image = image,
        .format = format,
        .subresourceRange = .{
            .aspectMask = @intCast(aspect_flags),
            .baseMipLevel = 0,
            .levelCount = miplevels,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    errors.checkVkPanic(
        c.vkCreateImageView(device, &view_info, null, &image_view),
    ) catch @panic("failed to make image view");
    return image_view;
}

pub fn createDrawImage(
    self: *Self,
    extent: c.VkExtent2D,
    format: c.VkFormat,
) AllocatedImage {
    var drawimage: AllocatedImage = undefined;
    const extent3d: c.VkExtent3D = .{ .width = extent.width, .height = extent.height, .depth = 1 };
    const drawimageci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent3d,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_4_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
            c.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT,
    };

    const drawimageai: c.VmaAllocationCreateInfo = .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };

    errors.checkVkPanic(c.vmaCreateImage(
        self.gpuallocator,
        &drawimageci,
        &drawimageai,
        &drawimage.image,
        &drawimage.allocation,
        null,
    ));
    const draw_image_view_ci: c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = drawimage.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    errors.checkVkPanic(c.vkCreateImageView(
        self.device,
        &draw_image_view_ci,
        self.alloc_callbacks,
        &drawimage.view,
    ));
    return drawimage;
}

pub fn createRenderImage(
    self: *Self,
    extent: c.VkExtent2D,
    format: c.VkFormat,
) AllocatedImage {
    var renderimage: AllocatedImage = undefined;
    const extent3d: c.VkExtent3D = .{ .width = extent.width, .height = extent.height, .depth = 1 };
    const resolved_image_ci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent3d,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
    };

    const resolved_image_ai: c.VmaAllocationCreateInfo = .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };

    errors.checkVkPanic(c.vmaCreateImage(
        self.gpuallocator,
        &resolved_image_ci,
        &resolved_image_ai,
        &renderimage.image,
        &renderimage.allocation,
        null,
    ));
    const resolved_view_ci: c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = renderimage.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    errors.checkVkPanic(c.vkCreateImageView(
        self.device,
        &resolved_view_ci,
        self.alloc_callbacks,
        &renderimage.view,
    ));
    return renderimage;
}

pub fn createDepthImage(
    self: *Self,
    extent: c.VkExtent3D,
    format: c.VkFormat,
) AllocatedImage {
    var depthimage: AllocatedImage = undefined;
    const drawimageai: c.VmaAllocationCreateInfo = .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };

    const depthimageci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_4_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
            c.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT,
    };

    errors.checkVkPanic(c.vmaCreateImage(
        self.gpuallocator,
        &depthimageci,
        &drawimageai,
        &depthimage.image,
        &depthimage.allocation,
        null,
    ));

    const depth_image_view_ci: c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = depthimage.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    errors.checkVkPanic(c.vkCreateImageView(
        self.device,
        &depth_image_view_ci,
        self.alloc_callbacks,
        &depthimage.view,
    ));
    return depthimage;
}

pub fn uploadMesh(
    self: *Self,
    core: *Core,
    vertices: []const Vertex,
    indices: []const u32,
) !void {
    const v_size = vertices.len * @sizeOf(Vertex);
    const i_size = indices.len * @sizeOf(u32);

    const v_bytes = std.mem.sliceAsBytes(vertices);
    const i_bytes = std.mem.sliceAsBytes(indices);

    const current_v_offset = try self.vertex_arena.allocate(@intCast(v_size));
    const current_i_offset = try self.index_arena.allocate(@intCast(i_size));
    const current_mesh_offset = try self.mesh_arena.allocate(@sizeOf(Mesh));

    self.upload(&core.asynccontext, v_bytes, self.vertex_arena.buffer, current_v_offset);
    self.upload(&core.asynccontext, i_bytes, self.index_arena.buffer, current_i_offset);

    const mesh = Mesh{
        .vertexBuffer = self.vertex_arena.getAddress(current_v_offset),
        .indexBuffer = self.index_arena.getAddress(current_i_offset),
        .indexCount = @as(u32, @intCast(indices.len)),
        .pad = 0,
    };

    self.upload(
        &core.asynccontext,
        std.mem.asBytes(&mesh),
        self.mesh_arena.buffer,
        current_mesh_offset,
    );
}

pub fn uploadTexture(
    self: *Self,
    core: *Core,
    descriptormanager: *DescriptorManager,
    data: []const u8,
    extent: c.VkExtent3D,
    format: c.VkFormat,
    mipmapped: bool,
) AllocatedImage {
    if (self.texture_count >= MAX_TEXTURES) {
        @panic("Exceeded maximum bindless textures!");
    }

    const staging = self.createBuffer(
        data.len,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VMA_MEMORY_USAGE_CPU_ONLY, // Changed from CPU_TO_GPU
    );
    defer staging.destroy(self.gpuallocator);

    const mapped_data = @as([*]u8, @ptrCast(staging.info.pMappedData.?));
    @memcpy(mapped_data[0..data.len], data);

    var new_image = self.createImage(
        extent,
        format,
        c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        mipmapped,
    );

    core.asynccontext.submitBegin();
    const cmd = core.asynccontext.commandbuffer;

    imageop.transition(
        cmd,
        new_image.image,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    );

    const image_copy_region: c.VkBufferImageCopy = .{
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageExtent = extent,
    };

    c.vkCmdCopyBufferToImage(
        cmd,
        staging.buffer,
        new_image.image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &image_copy_region,
    );

    imageop.transition(
        cmd,
        new_image.image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    );
    core.asynccontext.submitEnd();

    new_image.view = createView(self.device, new_image.image, format, if (mipmapped) 0 else 1);
    new_image.bindless_index = self.texture_count;
    self.texture_count += 1;

    descriptormanager.writeBindlessTexture(
        self.device,
        new_image.view,
        self.global_sampler,
        new_image.bindless_index,
    );

    return new_image;
}

pub fn initEmptyMesh(self: *Self, core: *Core, size: usize) !void {
    const vertex_count = size;
    const index_count = size * 6;
    const v_size = vertex_count * @sizeOf(Vertex);
    const i_size = index_count * @sizeOf(u32);

    const current_v_offset = try self.vertex_arena.allocate(@intCast(v_size));
    const current_i_offset = try self.index_arena.allocate(@intCast(i_size));

    var current_mesh_offset: u32 = 0;
    if (size != 0) {
        current_mesh_offset = try self.mesh_arena.allocate(@sizeOf(Mesh));
    }

    const mesh = Mesh{
        .vertexBuffer = self.vertex_arena.getAddress(current_v_offset),
        .indexBuffer = self.index_arena.getAddress(current_i_offset),
        .indexCount = @intCast(index_count),
        .pad = 0,
    };

    self.upload(
        &core.asynccontext,
        std.mem.asBytes(&mesh),
        self.mesh_arena.buffer,
        current_mesh_offset,
    );

    const instance = MeshInstance{
        .meshBuffer = self.mesh_arena.getAddress(current_mesh_offset),
        .transformIndex = 0, // No transform for now
        .materialIndex = 0, // Material lives here!
    };

    const current_instance_offset = try self.meshinstance_arena.allocate(@sizeOf(MeshInstance));

    for (0..Core.multibuffering) |i| {
        const frame_base_offset = i * MAX_OBJECTS * @sizeOf(MeshInstance);
        const offset = current_instance_offset + frame_base_offset;
        self.upload(&core.asynccontext, std.mem.asBytes(&instance), self.meshinstance_arena.buffer, offset);
    }
}

pub fn initEmptyUI(self: *Self, core: *Core, size: usize) !void {
    const vertex_count = size;
    const v_size = vertex_count * @sizeOf(Vertex);

    const current_v_offset = try self.vertex_arena.allocate(@intCast(v_size));
    var current_ui_offset: u32 = 0;
    if (size != 0) {
        current_ui_offset = try self.ui_arena.allocate(@sizeOf(UIElement));
    }

    const mesh = UIElement{
        .vertexBuffer = self.vertex_arena.getAddress(current_v_offset),
        .vertexCount = @intCast(vertex_count),
        .pad = 0,
    };

    self.upload(
        &core.asynccontext,
        std.mem.asBytes(&mesh),
        self.ui_arena.buffer, // The pool of geometry structs
        current_ui_offset,
    );

    const instance = UIInstance{
        .UIBuffer = self.ui_arena.getAddress(current_ui_offset),
        .transformIndex = 0,
        .type = 0,
    };

    const current_instance_offset = try self.uiinstance_arena.allocate(@sizeOf(UIInstance));

    for (0..Core.multibuffering) |i| {
        const frame_base_offset = i * MAX_OBJECTS * @sizeOf(UIInstance);
        self.upload(
            &core.asynccontext,
            std.mem.asBytes(&instance),
            self.uiinstance_arena.buffer,
            current_instance_offset + frame_base_offset,
        );
    }
}

pub fn testUI(self: *Self, core: *Core) !void {
    const letter_A_curves = [_]Vertex{
        .{ .position = .{ .x = 100, .y = 100, .z = 0 } },
        .{ .position = .{ .x = 200, .y = 300, .z = 0 } },
        .{ .position = .{ .x = 300, .y = 500, .z = 0 } },

        .{ .position = .{ .x = 300, .y = 500, .z = 0 } },
        .{ .position = .{ .x = 400, .y = 300, .z = 0 } },
        .{ .position = .{ .x = 500, .y = 100, .z = 0 } },

        .{ .position = .{ .x = 200, .y = 300, .z = 0 } },
        .{ .position = .{ .x = 300, .y = 300, .z = 0 } },
        .{ .position = .{ .x = 400, .y = 300, .z = 0 } },
    };

    const UI_TYPE_BEZIER_CURVE = 1;
    const curve_bytes = std.mem.sliceAsBytes(&letter_A_curves);

    const vertex_count = letter_A_curves.len;
    const v_size = vertex_count * @sizeOf(Vertex);

    const current_v_offset = try self.vertex_arena.allocate(@intCast(v_size));
    const current_ui_offset = try self.ui_arena.allocate(@sizeOf(UIElement));

    self.upload(&core.asynccontext, curve_bytes, self.vertex_arena.buffer, current_v_offset);

    const mesh = UIElement{
        .vertexBuffer = self.vertex_arena.getAddress(current_v_offset),
        .vertexCount = vertex_count,
        .pad = 0,
    };

    self.upload(&core.asynccontext, std.mem.asBytes(&mesh), self.ui_arena.buffer, current_ui_offset);

    const instance = UIInstance{
        .UIBuffer = self.ui_arena.getAddress(current_ui_offset),
        .transformIndex = 0,
        .type = UI_TYPE_BEZIER_CURVE,
    };

    const current_instance_offset = try self.uiinstance_arena.allocate(@sizeOf(UIInstance));

    for (0..Core.multibuffering) |i| {
        const frame_base_offset = i * MAX_OBJECTS * @sizeOf(UIInstance);
        self.upload(
            &core.asynccontext,
            std.mem.asBytes(&instance),
            self.uiinstance_arena.buffer,
            current_instance_offset + frame_base_offset,
        );
    }
}
           self.uiinstance_arena.buffer,
            current_instance_offset + frame_base_offset,
        );
    }
}
