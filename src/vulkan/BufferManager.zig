const std = @import("std");
const linalg = @import("../linalg.zig");
const errors = @import("errors.zig");
const c = @import("c");
const config = @import("config");
const Core = @import("Core.zig");
const DescriptorManager = @import("DescriptorManager.zig");
const AsyncContext = @import("AsyncContext.zig");
const imageop = @import("imageop.zig");

const Quat = linalg.Quat(f32);
const Vec2 = linalg.Vec2(f32);
const Vec3 = linalg.Vec3(f32);
const Vec4 = linalg.Vec4(f32);
const Mat4x4 = linalg.Mat4x4(f32);

// Limits for the engine
const MAX_GEOMETRY_BYTES = 64 * 1024 * 1024; // 64 MB for verts/indices
pub const MAX_TEXTURES = 4096; // 4 KB for images
pub const MAX_OBJECTS = 10000;
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
    boundingSphere: Vec4,
};

pub const Mesh = extern struct {
    vertexBuffer: u64, // vertexaddr ptr with offset
    indexBuffer: u64, // indexaddr ptr with offset
    indexCount: u32,
    materialIndex: u32,
};

pub const UIElement = extern struct {
    position: Vec2,
    size: Vec2,
    curveStart: u64,
    curveCount: u32,
    _pad: u32,
};

pub const SceneData = extern struct {
    view: Mat4x4,
    proj: Mat4x4,
    viewproj: Mat4x4,
    ambient_color: Vec4,
    sun_direction: Vec4,
    sun_color: Vec4,
    viewport: Vec4,
    // addresses
    transforms: u64, // array of Transform
    cpu_transforms: u64, // array of Transform
    meshes: u64, // array of Mesh
    uielements: u64,
    indirectCommands: u64, // address to the indirect struct
    drawCount: u64, // address to a single u32
    drawMap: u64, // INFO only used by meshshading atm
    // other
    meshcount: u32,
    uielemcount: u32,
};

// ========================================================================
// ResourceManager
// ========================================================================

const Self = @This();

device: c.VkDevice,
gpuallocator: c.VmaAllocator,
alloc_callbacks: ?*c.VkAllocationCallbacks,

global_sampler: c.VkSampler = undefined,

// gpu large buffers
vertexbuffer: AllocatedBuffer = undefined,
indexbuffer: AllocatedBuffer = undefined,
transformbuffer: AllocatedBuffer = undefined,
cpuside_transformbuffer: AllocatedBuffer = undefined,
meshbuffer: AllocatedBuffer = undefined,
indirectbuffer: AllocatedBuffer = undefined,
countbuffer: AllocatedBuffer = undefined,
drawmapbuffer: AllocatedBuffer = undefined,
uibuffer: AllocatedBuffer = undefined,

// Uniforms and binded buffers
scenebuffers: [Core.multibuffering]AllocatedBuffer = @splat(undefined),

// buffer addresses pushed to the gpu via uniform
transformbufferaddr: u64 = undefined,
cpuside_transformbufferaddr: u64 = undefined,
meshbufferaddr: u64 = undefined,
indirectbufferaddr: u64 = undefined,
countbufferaddr: u64 = undefined,
drawmapbufferaddr: u64 = undefined,
uibufferaddr: u64 = undefined,
vertexaddr: u64 = undefined,
indexaddr: u64 = undefined,

// Bump Allocator Trackers
vertex_byte_offset: u32 = 0,
index_byte_offset: u32 = 0,
mesh_object_offset: u32 = 0,
ui_object_offset: u32 = 0,
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
    self.destroy(self.vertexbuffer);
    self.destroy(self.indexbuffer);
    self.destroy(self.transformbuffer);
    self.destroy(self.meshbuffer);
    self.destroy(self.cpuside_transformbuffer);
    self.destroy(self.indirectbuffer);
    self.destroy(self.countbuffer);
    self.destroy(self.drawmapbuffer);
    self.destroy(self.uibuffer);
    c.vkDestroySampler(self.device, self.global_sampler, self.alloc_callbacks);
}

// Initializes the memory arenas with MULTI-BUFFERING sizing
pub fn initEngineBuffers(self: *Self, core: *Core, descriptormanager: *DescriptorManager) !void {
    const mb = Core.multibuffering;

    // Giant Geometry Buffers
    self.vertexbuffer = self.create(
        MAX_GEOMETRY_BYTES,
        c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    self.indexbuffer = self.create(
        MAX_GEOMETRY_BYTES,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    // list of objects
    self.meshbuffer = self.create(
        @sizeOf(Mesh) * MAX_OBJECTS, // TODO consider double buffer if meshes change
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    // 3. Compute Buffers
    self.transformbuffer = self.create(
        @sizeOf(Transform) * MAX_OBJECTS * mb, // <--- Ring Buffered!
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    if (config.meshshading) {
        self.indirectbuffer = self.create(
            @sizeOf(c.VkDrawMeshTasksIndirectCommandEXT) * MAX_OBJECTS * mb, // <--- Ring Buffered!
            c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c.VMA_MEMORY_USAGE_GPU_ONLY,
        );
    } else {
        self.indirectbuffer = self.create(
            @sizeOf(c.VkDrawIndirectCommand) * MAX_OBJECTS * mb, // <--- Ring Buffered!
            c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c.VMA_MEMORY_USAGE_GPU_ONLY,
        );
    }
    self.countbuffer = self.create(
        @sizeOf(u32) * mb, // <--- Ring Buffered!
        c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    self.drawmapbuffer = self.create(
        @sizeOf(u32) * MAX_OBJECTS * mb, // <--- Ring Buffered! (One u32 per potential object)
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    self.uibuffer = self.create(
        @sizeOf(UIElement) * 1000, // TODO consider double buffer if meshes change
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY, // TODO figure out what visibility
    );

    self.cpuside_transformbuffer = self.create(
        @sizeOf(Transform) * CPU_TRANSFORMS * mb, // <--- Ring Buffered!
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );

    // 4. Uniform Buffers (Already Double buffered)
    for (&self.scenebuffers, 0..) |*buf, i| {
        buf.* = self.create(
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

    self.transformbufferaddr = self.getBufferAddress(self.transformbuffer);
    self.cpuside_transformbufferaddr = self.getBufferAddress(self.cpuside_transformbuffer);
    self.meshbufferaddr = self.getBufferAddress(self.meshbuffer);
    self.indirectbufferaddr = self.getBufferAddress(self.indirectbuffer);
    self.countbufferaddr = self.getBufferAddress(self.countbuffer);
    self.drawmapbufferaddr = self.getBufferAddress(self.drawmapbuffer);
    self.uibufferaddr = self.getBufferAddress(self.uibuffer);
    self.vertexaddr = self.getBufferAddress(self.vertexbuffer);
    self.indexaddr = self.getBufferAddress(self.indexbuffer);

    // upload base address to prevent crash when no object are loaded
    const base_v_addr = self.vertexaddr;
    const base_i_addr = self.indexaddr;
    const mesh = Mesh{
        .vertexBuffer = base_v_addr,
        .indexBuffer = base_i_addr,
        .indexCount = 0,
        .materialIndex = 0,
    };
    self.upload(&core.asynccontext, std.mem.asBytes(&mesh), self.meshbuffer, 0);
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
    self.upload(&core.asynccontext, v_bytes, self.vertexbuffer, self.vertex_byte_offset);
    self.upload(&core.asynccontext, i_bytes, self.indexbuffer, self.index_byte_offset);

    // Get Base Device Addresses
    const base_v_addr = self.vertexaddr;
    const base_i_addr = self.indexaddr;

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
    self.upload(
        &core.asynccontext,
        std.mem.asBytes(&mesh),
        self.meshbuffer,
        self.mesh_object_offset * @sizeOf(Mesh),
    );
    self.mesh_object_offset += 1;
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
    ptr.viewport = Vec4.new(2000, 1200, 0, 0);

    // Calculate BDA base addresses
    const b_trans = self.transformbufferaddr;
    const b_meshes = self.meshbufferaddr;
    const b_indir = self.indirectbufferaddr;
    const b_count = self.countbufferaddr;
    const b_cpu_trans = self.cpuside_transformbufferaddr;
    const b_drawmap = self.drawmapbufferaddr;
    const b_ui = self.uibufferaddr;

    // Calculate byte offsets for this specific frame
    const frame_u64 = @as(u64, frame_index);
    _ = time;

    // Inject the offset pointers directly into the shader!
    ptr.transforms = b_trans + (frame_u64 * MAX_OBJECTS * @sizeOf(Transform));
    ptr.cpu_transforms = b_cpu_trans + (frame_u64 * CPU_TRANSFORMS * @sizeOf(Transform));
    if (config.meshshading) {
        ptr.indirectCommands = b_indir +
            (frame_u64 * MAX_OBJECTS * @sizeOf(c.VkDrawMeshTasksIndirectCommandEXT));
    } else {
        ptr.indirectCommands = b_indir +
            (frame_u64 * MAX_OBJECTS * @sizeOf(c.VkDrawIndirectCommand));
    }
    ptr.drawCount = b_count + (frame_u64 * @sizeOf(u32));
    ptr.drawMap = b_drawmap + (frame_u64 * MAX_OBJECTS * @sizeOf(u32));
    ptr.meshes = b_meshes;
    ptr.uielements = b_ui;
    ptr.meshcount = self.mesh_object_offset;
    ptr.uielemcount = self.ui_object_offset;
}

pub fn create(
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
    const staging_buffer = self.create(
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

    // 1. Create Staging Buffer
    const staging = self.createBuffer(
        data.len,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    defer self.destroyBuffer(staging);

    // 2. Copy Data to Staging
    const mapped_data = @as([*]u8, @ptrCast(staging.info.pMappedData.?));
    @memcpy(mapped_data[0..data.len], data);

    // 3. Create GPU Image
    var new_image = self.createRawImage(
        extent,
        format,
        c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        mipmapped,
    );

    // 4. Record and Submit Transfer Commands
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

    // 5. Create View & Assign Bindless Index
    new_image.view = self.createImageView(new_image.image, format, if (mipmapped) 0 else 1);
    new_image.bindless_index = self.texture_count;
    self.texture_count += 1;

    // 6. Push to Descriptor Manager
    descriptormanager.writeBindlessTexture(
        self.device,
        new_image.view,
        self.global_sampler,
        new_image.bindless_index,
    );

    return new_image;
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

// TODO move into separate file
pub fn initEmptyMesh(self: *Self, core: *Core) void {
    const vertex_count = 256 * 256;
    const index_count = 255 * 255 * 6; // two triangles per rectangle: 2 * 3 = 6
    const v_size = vertex_count * @sizeOf(Vertex);
    const i_size = index_count * @sizeOf(u32);

    const vertex_addr = self.vertexaddr;
    const index_addr = self.indexaddr;

    self.vertex_byte_offset += v_size;
    self.index_byte_offset += i_size;
    const mesh = Mesh{
        .vertexBuffer = vertex_addr + self.vertex_byte_offset,
        .indexBuffer = index_addr + self.index_byte_offset,
        .indexCount = index_count,
        .materialIndex = 0,
    };

    self.upload(
        &core.asynccontext,
        std.mem.asBytes(&mesh),
        self.meshbuffer,
        self.mesh_object_offset * @sizeOf(Mesh),
    );
    self.mesh_object_offset += 1;
}

// TODO move into separate file
pub fn testUI(self: *Self, core: *Core) void {
    // 1. Pack our 3 curves into an array of Vec4s
    const mock_curves = [_]Vec4{
        // Curve 1: P0(200, 200), P1(500, 300) | P2(800, 200)
        Vec4.new(200, 200, 500, 300),
        Vec4.new(800, 200, 0, 0),

        // Curve 2: P0(800, 200), P1(900, 800) | P2(500, 900)
        Vec4.new(800, 200, 900, 800),
        Vec4.new(500, 900, 0, 0),

        // Curve 3: P0(500, 900), P1(100, 800) | P2(200, 200)
        Vec4.new(500, 900, 100, 800),
        Vec4.new(200, 200, 0, 0),
    };

    const curve_bytes = std.mem.sliceAsBytes(&mock_curves);

    // 2. Safety check for your giant buffer
    if (self.vertex_byte_offset + curve_bytes.len > MAX_GEOMETRY_BYTES) {
        @panic("Giant Geometry Buffer is full!");
    }

    // 3. Calculate the exact 64-bit BDA for where these curves will live
    const base_v_addr = self.vertexaddr;
    const curve_bda = base_v_addr + self.vertex_byte_offset;

    // 4. Upload the raw curve bytes to the global buffer at the current offset
    self.upload(&core.asynccontext, curve_bytes, self.vertexbuffer, self.vertex_byte_offset);

    // 5. Bump the global arena allocator!
    self.vertex_byte_offset += @intCast(curve_bytes.len);

    // 6. Setup the UIData struct
    const ui_data = UIElement{
        .curveStart = curve_bda, // <-- Injecting the BDA inside the global buffer!
        .curveCount = 6,
        .position = .{ .x = 100, .y = 100 },
        .size = .{ .x = 1000, .y = 1000 },
        ._pad = 0,
    };
    self.ui_object_offset += 1;

    // 7. Upload UIData to the UI Buffer
    self.upload(&core.asynccontext, std.mem.asBytes(&ui_data), self.uibuffer, 0);
}
