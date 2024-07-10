const m = @import("math3d.zig");
const e = @import("vkEngine.zig");
const c = @import("clibs.zig");

pub const Vertex = struct {
    Position: m.Vec3,
    uv_x: f32,
    Normal: m.Vec3,
    uv_y: f32,
    Color: u32,
};

pub const GPUMeshBuffers = struct {
    vertex_buffer: e.AllocatedBuffer,
    index_buffer: e.AllocatedBuffer,
    vertex_buffer_adress: c.VkDeviceAddress, 
};

pub const GPUDrawPushConstants = struct {
    model: m.Mat4,
    vertex_buffer : c.VkDeviceAddress,
};

pub const AllocatedBuffer = struct {
    buffer: c.VkBuffer,
    allocation: c.VmaAllocation,
    info: c.VmaAllocationInfo,
};

pub const AllocatedImage = struct {
    image: c.VkImage,
    allocation: c.VmaAllocation,
    extent: c.VkExtent3D,
    format: c.VkFormat,
    view: c.VkImageView,
};

pub const UploadContext = struct {
    upload_fence: c.VkFence = null,
    command_pool: c.VkCommandPool = null,
    command_buffer: c.VkCommandBuffer = null,
};

pub const FrameData = struct {
    present_semaphore: c.VkSemaphore = null,
    render_semaphore: c.VkSemaphore = null,
    render_fence: c.VkFence = null,
    command_pool: c.VkCommandPool = null,
    main_command_buffer: c.VkCommandBuffer = null,
};

pub const ComputePushConstants = struct {
    data1: m.Vec4,
    data2: m.Vec4,
    data3: m.Vec4,
    data4: m.Vec4,
};
