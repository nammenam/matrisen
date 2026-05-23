// TODO this is verry brittle and very prone to bugs need to compartmentalize put memory sensitive
// code into functions write correct once
//
// TODO clean up make more user firendly spit into multiple files, hard to keep track of variables
// that span multiple functions and lifetime (the self. variables)
// the buffers and bumps can be put into a struct that has the buffer, addr, and count
// only store the count and convert to bytes when uploading only

// TODO Need to find out if gpu needs acces to the bump if it is going to write and produce objects
// eg. create a mesh with size unkown to cpu, (this probably needs gpu - cpu sync?)
// or alternativly have two separate buffers, one that gpu writes to and bumps and one that
// cpu writes to and bumps, the gpu can read both, we also need to create compote shaders
// that generate persistent meshes and save to vram not only meshshaders that dont save to vram

// TODO We have two indirections one lookup for the instance
// and one lookup for mesh/uibuffer is it better to have flatter structure with one lookup?
// can we maybe store indices out of bounds if we pack data in the right order? or is that
// too complicated, anyway the structs need to be tweaked for optimal architecture
// in general the system needs to be fast, low memory footprint and not to complex

// TODO find the right data format for UI, how many branches do we want in the shader
// (how many ui primitives ) do we want 3D ui or only 2D, maybe use both and optimize
// again we have to find out how many indierections we want and if we want to store
// indices out of bounds and be clever about ordering, instead of type fields shuld we
// create many buffers that implicitly decide the type

const std = @import("std");
const linalg = @import("../linalg.zig");
const errors = @import("errors.zig");
const c = @import("c");
const config = @import("config");
const Core = @import("Core.zig");
const DescriptorManager = @import("DescriptorManager.zig");
const AsyncContext = @import("AsyncContext.zig");
const imageop = @import("imageop.zig");
const Arena = @import("Arena.zig").Arena;

const Quat = linalg.Quat(f32);
const Vec2 = linalg.Vec2(f32);
const Vec3 = linalg.Vec3(f32);
const Vec4 = linalg.Vec4(f32);
const Mat4x4 = linalg.Mat4x4(f32);

// TODO merge into the new allocated buffer struct
pub const MAX_GEOMETRY_BYTES = 64 * 1024 * 1024; // 64 MB for verts/indices
pub const MAX_TEXTURES = 4096; // 4 KB for images
pub const MAX_DYNAMIC_UI = 4096; // 4 KB for images
pub const MAX_OBJECTS = 4096;
pub const CPU_TRANSFORMS = 100;

pub const AllocatedBuffer = struct {
    buffer: c.VkBuffer,
    allocation: c.VmaAllocation,
    info: c.VmaAllocationInfo,
};

// TODO invesigate optimized memory layout and redundant fields
pub const AllocatedImage = struct {
    image: c.VkImage,
    allocation: c.VmaAllocation,
    view: c.VkImageView,
    // info: c.VmaAllocationInfo,
    bindless_index: u32,
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

pub const Transform = extern struct {
    modelMatrix: Mat4x4,
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
    type: u32,
};

pub const GPUCounters = extern struct {
    drawCount: u32,
    vertexOffset: u32,
    indexOffset: u32,
    meshOffset: u32,
    uiVertexOffset: u32,
    uiElementOffset: u32,
    pad0: u32 = 0,
    pad1: u32 = 0,
};

pub const SceneData = extern struct {
    viewproj: Mat4x4,
    ambient_color: Vec4,
    sun_direction: Vec4,
    sun_color: Vec4,
    viewport: Vec4,
    // addresses
    transforms: u64,
    cpu_transforms: u64,
    meshes: u64, // *MeshInstance
    uiobjects: u64, // *UIInstance
    indirectCommands: u64, // *indirecbuffer
    counters: u64, // *GPUCounters
    drawMap: u64, // *uint
    // counts
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

// --- The 4 Core Arenas ---
static_cpu_arena: Arena = undefined,
dynamic_cpu_arena: Arena = undefined,
static_gpu_arena: Arena = undefined,
dynamic_gpu_arena: Arena = undefined,
readback_arena: Arena = undefined,

// gpu large arenas
vertex_arena: Arena = undefined,
dynamicvertex_arena: Arena = undefined,
index_arena: Arena = undefined,
transform_arena: Arena = undefined,
cputransform_arena: Arena = undefined,
mesh_arena: Arena = undefined,
meshinstance_arena: Arena = undefined,
uiinstance_arena: Arena = undefined,
indirect_arena: Arena = undefined,
count_arena: Arena = undefined,
drawmap_arena: Arena = undefined,
ui_arena: Arena = undefined,

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

pub fn destroy(self: *Self, buffer: AllocatedBuffer) void {
    c.vmaDestroyBuffer(self.gpuallocator, buffer.buffer, buffer.allocation);
}

pub fn destroyBuffers(self: *Self) void {
    for (self.scenebuffers) |buf| self.destroy(buf);
    c.vkDestroySampler(self.device, self.global_sampler, self.alloc_callbacks);

    if (self.static_cpu_arena.buffer.buffer != null) self.destroy(self.static_cpu_arena.buffer);
    if (self.dynamic_cpu_arena.buffer.buffer != null) self.destroy(self.dynamic_cpu_arena.buffer);
    if (self.static_gpu_arena.buffer.buffer != null) self.destroy(self.static_gpu_arena.buffer);
    if (self.dynamic_gpu_arena.buffer.buffer != null) self.destroy(self.dynamic_gpu_arena.buffer);
}

// Initializes the memory arenas with MULTI-BUFFERING sizing
pub fn initEngineBuffers(self: *Self, core: *Core, descriptormanager: *DescriptorManager) !void {
    const mb = Core.multibuffering;

    // ====================================================================
    // The 4 Core Arenas (Architecture Upgrade)
    // ====================================================================

    // 1. Static CPU Arena (CPU to GPU, Write once)
    const static_cpu_buf = self.createBuffer(
        128 * 1024 * 1024, // 128 MB
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VMA_MEMORY_USAGE_CPU_ONLY,
    );
    self.static_cpu_arena = Arena.init(static_cpu_buf, 0, 0, 128 * 1024 * 1024);

    // 2. Dynamic CPU Arena (CPU to GPU, Ring buffered or persistently mapped)
    const dynamic_cpu_buf = self.createBuffer(
        64 * 1024 * 1024, // 64 MB
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    self.dynamic_cpu_arena = Arena.init(dynamic_cpu_buf, 0, self.getBufferAddress(dynamic_cpu_buf), 64 * 1024 * 1024);

    // 3. Static GPU Arena (GPU Only, procedural static meshes, loaded once)
    const static_gpu_buf = self.createBuffer(
        256 * 1024 * 1024, // 256 MB
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    self.static_gpu_arena = Arena.init(static_gpu_buf, 0, self.getBufferAddress(static_gpu_buf), 256 * 1024 * 1024);

    // 4. Dynamic GPU Arena (GPU Only, cleared every frame for compute output)
    const dynamic_gpu_buf = self.createBuffer(
        128 * 1024 * 1024, // 128 MB
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    self.dynamic_gpu_arena = Arena.init(dynamic_gpu_buf, 0, self.getBufferAddress(dynamic_gpu_buf), 128 * 1024 * 1024);

    // 5. Readback Arena (GPU to CPU, for retrieving data)
    const readback_buf = self.createBuffer(
        16 * 1024 * 1024, // 16 MB
        c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_TO_CPU,
    );
    self.readback_arena = Arena.init(readback_buf, 0, 0, 16 * 1024 * 1024);

    // ====================================================================
    // Static arenas (change rarely) mega buffers GPU Only
    // ====================================================================

    // Giant Geometry Buffers
    self.vertex_arena = try self.static_gpu_arena.subAllocateArena(MAX_GEOMETRY_BYTES);
    self.index_arena = try self.static_gpu_arena.subAllocateArena(MAX_GEOMETRY_BYTES);
    // list of mesh objects
    self.mesh_arena = try self.static_gpu_arena.subAllocateArena(@sizeOf(Mesh) * MAX_OBJECTS);
    // list of ui objects
    self.ui_arena = try self.static_gpu_arena.subAllocateArena(@sizeOf(UIElement) * MAX_OBJECTS);

    // ====================================================================
    // Dynamic arenas (double buffered) GPU Only
    // ====================================================================

    // list of mesh instances
    self.meshinstance_arena = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(MeshInstance) * MAX_OBJECTS * mb);
    // list of ui instances
    self.uiinstance_arena = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(UIInstance) * MAX_OBJECTS * mb);
    // 3. Compute Buffers
    self.transform_arena = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(Transform) * MAX_OBJECTS * mb);
    if (config.meshshading) {
        self.indirect_arena = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(c.VkDrawMeshTasksIndirectCommandEXT) * MAX_OBJECTS * mb);
    } else {
        self.indirect_arena = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(c.VkDrawIndirectCommand) * MAX_OBJECTS * mb);
    }
    self.count_arena = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(GPUCounters) * mb);
    self.drawmap_arena = try self.dynamic_gpu_arena.subAllocateArena(@sizeOf(u32) * MAX_OBJECTS * mb);

    // ====================================================================
    // Dynamic arenas Host visible (CPU visible)
    // ====================================================================

    self.dynamicvertex_arena = try self.dynamic_cpu_arena.subAllocateArena(@sizeOf(Vertex) * MAX_OBJECTS * mb);
    self.cputransform_arena = try self.dynamic_cpu_arena.subAllocateArena(@sizeOf(Transform) * CPU_TRANSFORMS * mb);

    // 4. Uniform Buffers (Already Double buffered)
    // If you are wondering where the write for the other set (bindless texture is)
    // The other set gets written in uploadTexture //TODO is that right way to do it
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
    var proj = Mat4x4.perspective(std.math.degreesToRadians(60.0), aspect_ratio, 0.1, 1000.0);
    ptr.viewproj = proj.mul(view);

    ptr.ambient_color = Vec4.new(1.0, 0.5, 0.0, 1.0);
    ptr.sun_color = Vec4.new(1.0, 1.0, 0.9, 1.0);
    ptr.sun_direction = Vec3.new(0.2, -0.5, 1.0).normalized().toVec4(0.0);
    ptr.viewport = Vec4.new(2000, 1200, 0, 0);

    // Calculate BDA base addresses
    const b_trans = self.transform_arena.device_address;
    const b_meshes = self.meshinstance_arena.device_address;
    const b_indir = self.indirect_arena.device_address;
    const b_count = self.count_arena.device_address;
    const b_cpu_trans = self.cputransform_arena.device_address;
    const b_drawmap = self.drawmap_arena.device_address;
    const b_ui = self.uiinstance_arena.device_address;

    // Calculate byte offsets for this specific frame
    const frame_u64 = @as(u64, frame_index);
    _ = time;

    // Inject the offset pointers directly into the shader!
    ptr.transforms = b_trans + (frame_u64 * MAX_OBJECTS * @sizeOf(Transform));
    ptr.cpu_transforms = b_cpu_trans + (frame_u64 * CPU_TRANSFORMS * @sizeOf(Transform));
    ptr.counters = b_count + (frame_u64 * @sizeOf(GPUCounters));
    ptr.drawMap = b_drawmap + (frame_u64 * MAX_OBJECTS * @sizeOf(u32));
    ptr.meshes = b_meshes + (frame_u64 * MAX_OBJECTS * @sizeOf(MeshInstance));
    ptr.uiobjects = b_ui + (frame_u64 * MAX_OBJECTS * @sizeOf(UIInstance));
    ptr.meshcount = self.meshinstance_arena.allocator.offset / @sizeOf(MeshInstance);
    ptr.uielemcount = self.uiinstance_arena.allocator.offset / @sizeOf(UIInstance);
    if (config.meshshading) {
        ptr.indirectCommands = b_indir +
            (frame_u64 * MAX_OBJECTS * @sizeOf(c.VkDrawMeshTasksIndirectCommandEXT));
    } else {
        ptr.indirectCommands = b_indir +
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

pub fn requestReadback(self: *Self, cmd: c.VkCommandBuffer, src_buffer: c.VkBuffer, size: c.VkDeviceSize, src_offset: c.VkDeviceSize) !u32 {
    const dst_offset = try self.readback_arena.allocate(@intCast(size));

    const copy_region = c.VkBufferCopy{
        .srcOffset = src_offset,
        .dstOffset = self.readback_arena.base_offset + dst_offset,
        .size = size,
    };

    c.vkCmdCopyBuffer(cmd, src_buffer, self.readback_arena.buffer.buffer, 1, &copy_region);
    return dst_offset;
}

pub fn deinitImage(self: *Self, image: AllocatedImage) void {
    c.vmaDestroyImage(self.gpuallocator, image.image, image.allocation);
    c.vkDestroyImageView(self.device, image.view, self.alloc_callbacks);
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

// TODO move to separate file
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

// TODO move to separate file
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

// TODO move into separate file
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

    self.upload(&core.asynccontext, v_bytes, self.vertex_arena.buffer, self.vertex_arena.base_offset + current_v_offset);
    self.upload(&core.asynccontext, i_bytes, self.index_arena.buffer, self.index_arena.base_offset + current_i_offset);

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
        self.mesh_arena.base_offset + current_mesh_offset,
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
    defer self.destroy(staging);

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

// TODO move into separate file
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
        self.mesh_arena.base_offset + current_mesh_offset,
    );

    const instance = MeshInstance{
        .meshBuffer = self.mesh_arena.getAddress(current_mesh_offset),
        .transformIndex = 0, // No transform for now
        .materialIndex = 0, // Material lives here!
    };

    for (0..Core.multibuffering) |i| {
        const frame_base_offset = i * MAX_OBJECTS * @sizeOf(MeshInstance);
        const current_instance_offset = try self.meshinstance_arena.allocate(@sizeOf(MeshInstance));
        // Wait, meshinstance_arena already accounts for multibuffering sequentially
        // Actually, no, if we allocate here sequentially, it will put instances consecutively, not strided.
        // Let's just stride manually for now if that's what was done.
        
        self.upload(
            &core.asynccontext,
            std.mem.asBytes(&instance),
            self.meshinstance_arena.buffer,
            self.meshinstance_arena.base_offset + frame_base_offset + current_instance_offset / Core.multibuffering,
        );
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
        self.ui_arena.base_offset + current_ui_offset,
    );

    const instance = UIInstance{
        .UIBuffer = self.ui_arena.getAddress(current_ui_offset),
        .transformIndex = 0,
        .type = 0,
    };

    const current_instance_offset = try self.uiinstance_arena.allocate(@sizeOf(UIInstance));
    const normalized_offset = current_instance_offset;

    for (0..Core.multibuffering) |i| {
        const frame_base_offset = i * MAX_OBJECTS * @sizeOf(UIInstance);
        self.upload(
            &core.asynccontext,
            std.mem.asBytes(&instance),
            self.uiinstance_arena.buffer,
            self.uiinstance_arena.base_offset + frame_base_offset + normalized_offset,
        );
    }
}

// TODO move into separate file
pub fn testSlugFont(self: *Self, core: *Core) !void {
    // A simple letter "A" made of quadratic bezier curves
    // P0, P1, P2 for each segment
    const letter_A_curves = [_]Vertex{
        // Left leg
        .{ .position = .{ .x = 100, .y = 100, .z = 0 } },
        .{ .position = .{ .x = 200, .y = 300, .z = 0 } },
        .{ .position = .{ .x = 300, .y = 500, .z = 0 } },

        // Right leg
        .{ .position = .{ .x = 300, .y = 500, .z = 0 } },
        .{ .position = .{ .x = 400, .y = 300, .z = 0 } },
        .{ .position = .{ .x = 500, .y = 100, .z = 0 } },

        // Crossbar
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

    // Upload via Staging Buffer
    self.upload(&core.asynccontext, curve_bytes, self.vertex_arena.buffer, self.vertex_arena.base_offset + current_v_offset);

    // 3. Build the ui using the PRE-BUMP offsets
    const mesh = UIElement{
        .vertexBuffer = self.vertex_arena.getAddress(current_v_offset),
        .vertexCount = vertex_count,
        .pad = 0,
    };

    self.upload(&core.asynccontext, std.mem.asBytes(&mesh), self.ui_arena.buffer, self.ui_arena.base_offset + current_ui_offset);

    // 5. Build the Instance pointing to the PRE-BUMP mesh offset
    const instance = UIInstance{
        .UIBuffer = self.ui_arena.getAddress(current_ui_offset),
        .transformIndex = 0,
        .type = UI_TYPE_BEZIER_CURVE,
    };

    const current_instance_offset = try self.uiinstance_arena.allocate(@sizeOf(UIInstance));
    const normalized_offset = current_instance_offset;

    for (0..Core.multibuffering) |i| {
        const frame_base_offset = i * MAX_OBJECTS * @sizeOf(UIInstance);
        self.upload(
            &core.asynccontext,
            std.mem.asBytes(&instance),
            self.uiinstance_arena.buffer,
            self.uiinstance_arena.base_offset + frame_base_offset + normalized_offset,
        );
    }
}
