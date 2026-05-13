// TODO the code is ugly, store intermidiates in variables for
// better readablilty, it does nothing to performace

const std = @import("std");
const log = std.log.scoped(.core);
const errors = @import("errors.zig");
const c = @import("c");
const config = @import("config");

const Camera = @import("../Camera.zig");
const Device = @import("Device.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");
const Swapchain = @import("Swapchain.zig");
const Instance = @import("Instance.zig");
const FrameContext = @import("FrameContext.zig");
const AsyncContext = @import("AsyncContext.zig");
const Window = @import("../Window.zig");
const ResourceManager = @import("BufferManager.zig");
const PipelineManager = @import("PipelineManager.zig");
const DescriptorManager = @import("DescriptorManager.zig");

const Self = @This();

/// Bookkeeping
pub const multibuffering = 2;
pub const renderscale = 1.0;
pub const renderformat: c.VkFormat = c.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const depthformat: c.VkFormat = c.VK_FORMAT_D32_SFLOAT;

framenumber: u64 = 0,
currentframe: u8 = 0,

/// Memory allocators
cpuallocator: std.mem.Allocator,
gpuallocator: c.VmaAllocator,

/// Managers
framecontexts: [multibuffering]FrameContext,
asynccontext: AsyncContext,
pipelinemanager: PipelineManager,
descriptormanager: DescriptorManager,
buffermanager: ResourceManager,

instance: Instance,
device: Device,
physicaldevice: PhysicalDevice,
alloc_callbacks: ?*c.VkAllocationCallbacks,

/// Screen resources
surface: c.VkSurfaceKHR,
swapchain: Swapchain,

// TODO maybe move these into a container for modularity
drawextent3d: c.VkExtent3D, // for resolution scaling
drawextent2d: c.VkExtent2D, //for resolution scaling
drawimage: ResourceManager.AllocatedImage = undefined,
renderimage: ResourceManager.AllocatedImage = undefined,
depthimage: ResourceManager.AllocatedImage = undefined,

pub fn init(allocator: std.mem.Allocator, window: *Window) Self {
    var arenaallocator = std.heap.ArenaAllocator.init(allocator);
    defer arenaallocator.deinit();
    const initallocator = arenaallocator.allocator();

    const alloc_callbacks: ?*c.VkAllocationCallbacks = null;
    const instance: Instance = .init(initallocator, alloc_callbacks);
    const surface = window.createSurface(instance, alloc_callbacks);
    const physicaldevice: PhysicalDevice = .select(initallocator, instance.handle, surface);
    const device: Device = Device.init(initallocator, physicaldevice) catch {
        @panic("");
    };
    const gpuallocator = makeGpuAllocator(physicaldevice.handle, device.handle, instance.handle);

    var windowextent: c.VkExtent2D = .{ .width = 0, .height = 0 };
    window.getSize(&windowextent.width, &windowextent.height);
    const swapchain: Swapchain = .init(
        allocator,
        physicaldevice,
        device.handle,
        surface,
        windowextent,
        alloc_callbacks,
    );
    const drawextent2d = setRenderScale(swapchain.extent, renderscale);
    const drawextent3d: c.VkExtent3D = .{
        .width = drawextent2d.width,
        .height = drawextent2d.height,
        .depth = 1,
    };
    const pipelinemanager: PipelineManager = .init(allocator, device.handle, alloc_callbacks);

    var framecontexts: [multibuffering]FrameContext = undefined;
    for (&framecontexts) |*frame| {
        frame.* = .init(
            device.handle,
            device.graphics_queue,
            physicaldevice,
            alloc_callbacks,
        );
    }
    const asynccontext: AsyncContext = .init(device, physicaldevice, alloc_callbacks);
    var buffermanager: ResourceManager = .init(device.handle, gpuallocator, alloc_callbacks);
    const descriptormanager: DescriptorManager = .init(allocator, device.handle, pipelinemanager);

    const drawimage = buffermanager.createDrawImage(drawextent2d, renderformat);
    const renderimage = buffermanager.createRenderImage(drawextent2d, renderformat);
    const depthimage = buffermanager.createDepthImage(drawextent3d, depthformat);

    return .{
        .cpuallocator = allocator,
        .gpuallocator = gpuallocator,
        .alloc_callbacks = alloc_callbacks,
        .asynccontext = asynccontext,
        .framecontexts = framecontexts,
        .surface = surface,
        .swapchain = swapchain,
        .instance = instance,
        .device = device,
        .physicaldevice = physicaldevice,
        .drawimage = drawimage,
        .renderimage = renderimage,
        .drawextent2d = drawextent2d,
        .drawextent3d = drawextent3d,
        .depthimage = depthimage,
        .pipelinemanager = pipelinemanager,
        .descriptormanager = descriptormanager,
        .buffermanager = buffermanager,
    };
}

pub fn deinit(self: *Self) void {
    errors.checkVkPanic(c.vkDeviceWaitIdle(self.device.handle));
    defer self.instance.deinit();
    defer c.vkDestroySurfaceKHR(self.instance.handle, self.surface, self.alloc_callbacks);
    defer c.vkDestroyDevice(self.device.handle, self.alloc_callbacks);
    defer c.vmaDestroyAllocator(self.gpuallocator);
    defer self.swapchain.deinit(self.cpuallocator);
    defer self.buffermanager.deinitImage(self.drawimage);
    defer self.buffermanager.deinitImage(self.renderimage);
    defer self.buffermanager.deinitImage(self.depthimage);
    defer for (&self.framecontexts) |*frame| frame.deinit();
    defer self.asynccontext.deinit();
    defer self.pipelinemanager.deinit();
    defer self.descriptormanager.deinit(self.cpuallocator);
    defer self.buffermanager.destroyBuffers();
}

pub fn switch_frame(self: *Self) void {
    self.currentframe = (self.currentframe + 1) % multibuffering;
}

fn makeGpuAllocator(
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    instance: c.VkInstance,
) c.VmaAllocator {
    var gpuallocator: c.VmaAllocator = undefined;
    const allocator_ci: c.VmaAllocatorCreateInfo = .{
        .physicalDevice = physical_device,
        .device = device,
        .instance = instance,
        .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    };
    errors.checkVkPanic(c.vmaCreateAllocator(&allocator_ci, &gpuallocator));
    log.info("created gpu memory allocator", .{});
    return gpuallocator;
}

pub fn resize(self: *Self, window: *Window) void {
    errors.checkVkPanic(c.vkDeviceWaitIdle(self.device.handle));
    self.swapchain.deinit(self.cpuallocator);
    self.buffermanager.deinitImage(self.drawimage);
    self.buffermanager.deinitImage(self.renderimage);
    self.buffermanager.deinitImage(self.depthimage);
    var windowextent: c.VkExtent2D = .{};
    window.getSize(&windowextent.width, &windowextent.height);
    self.swapchain = .init(
        self.cpuallocator,
        self.physicaldevice,
        self.device.handle,
        self.surface,
        windowextent,
        self.alloc_callbacks,
    );
    self.drawextent2d = setRenderScale(self.swapchain.extent, renderscale);
    self.drawextent3d = .{ .width = self.drawextent2d.width, .height = self.drawextent2d.height, .depth = 1 };
    self.drawimage = self.buffermanager.createDrawImage(self.drawextent2d, renderformat);
    self.renderimage = self.buffermanager.createRenderImage(self.drawextent2d, renderformat);
    self.depthimage = self.buffermanager.createDepthImage(self.drawextent3d, depthformat);
}

fn setRenderScale(inputextent: c.VkExtent2D, scale: f32) c.VkExtent2D {
    var outextent: c.VkExtent2D = .{};
    outextent.width = @intFromFloat(@as(f32, @floatFromInt(@min(
        inputextent.width,
        inputextent.width,
    ))) * scale);
    outextent.height = @intFromFloat(@as(f32, @floatFromInt(@min(
        inputextent.height,
        inputextent.height,
    ))) * scale);
    return outextent;
}

pub fn nextFrame(self: *Self, window: *Window) void {
    var frame = &self.framecontexts[self.currentframe];
    const cmd = frame.command_buffer;

    frame.beginFrame(&self.swapchain) catch |err| {
        if (err == error.SwapchainOutOfDate or window.state.resizerequest) {
            self.resize(window);
            window.state.resizerequest = false;
            return;
        }
    };

    const count_offset = @as(u64, self.currentframe) * @sizeOf(u32);

    // 1. Clear State
    self.recordBufferClears(cmd, count_offset);

    // 2. Compute Culling & Command Generation
    self.recordComputePass(cmd);

    // 3. Render Geometry
    self.recordGraphicsPass(frame, cmd, count_offset);

    // Submit
    frame.endFrame(&self.swapchain);
    self.framenumber +%= 1;
    self.switch_frame();
}

fn recordBufferClears(self: *Self, cmd: c.VkCommandBuffer, count_offset: u64) void {
    c.vkCmdFillBuffer(cmd, self.buffermanager.countbuffer.buffer, count_offset, @sizeOf(u32), 0);

    const fill_barrier = c.VkBufferMemoryBarrier{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
        .dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT | c.VK_ACCESS_SHADER_WRITE_BIT,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .buffer = self.buffermanager.countbuffer.buffer,
        .offset = count_offset, // <-- Protects the active frame's memory
        .size = @sizeOf(u32),
    };

    c.vkCmdPipelineBarrier(
        cmd,
        c.VK_PIPELINE_STAGE_TRANSFER_BIT,
        c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        0,
        0,
        null,
        1,
        &fill_barrier,
        0,
        null,
    );
}

fn recordComputePass(self: *Self, cmd: c.VkCommandBuffer) void {
    const sets_to_bind = [_]c.VkDescriptorSet{
        self.descriptormanager.sets[self.currentframe], // Set 0: SceneData
        self.descriptormanager.bindless_set, // Set 1: Textures
    };

    c.vkCmdBindDescriptorSets(
        cmd,
        c.VK_PIPELINE_BIND_POINT_COMPUTE,
        self.pipelinemanager.sharedpipelinelayout,
        0, // first set
        sets_to_bind.len,
        &sets_to_bind,
        0,
        null,
    );

    // Terrain / FIX run only once
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.pipelinemanager.get("terrainMain"));
    c.vkCmdDispatch(cmd, 16, 16, 1);

    // Mesh Culling
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.pipelinemanager.get("drawcmdMain"));

    // Fixed: Dynamic Dispatch based on exactly how many objects exist
    const dispatch_x = (self.buffermanager.mesh_instance_offset + 63) / 64;
    // const dispatch_x = 1;
    if (dispatch_x > 0) {
        c.vkCmdDispatch(cmd, dispatch_x, 1, 1);
    }

    // Must include SHADER_READ_BIT so the Mesh Shader can safely read drawMap!
    const compute_to_draw_barrier = c.VkMemoryBarrier{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = c.VK_ACCESS_SHADER_WRITE_BIT,
        .dstAccessMask = c.VK_ACCESS_INDIRECT_COMMAND_READ_BIT | c.VK_ACCESS_SHADER_READ_BIT,
    };

    c.vkCmdPipelineBarrier(
        cmd,
        c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        // Block Indirect Draw AND Shader execution until the buffer writes are visible
        c.VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT | c.VK_PIPELINE_STAGE_VERTEX_SHADER_BIT |
            c.VK_PIPELINE_STAGE_MESH_SHADER_BIT_EXT,
        0,
        1,
        &compute_to_draw_barrier,
        0,
        null,
        0,
        null,
    );
}

fn recordGraphicsPass(self: *Self, frame: *FrameContext, cmd: c.VkCommandBuffer, count_offset: u64) void {
    frame.beginGraphicsPass(self);

    if (config.meshshading) {
        c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelinemanager.get("meshMain"));
    } else {
        c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelinemanager.get("vertexMain"));
    }

    const sets_to_bind = [_]c.VkDescriptorSet{
        self.descriptormanager.sets[self.currentframe], // Set 0: SceneData
        self.descriptormanager.bindless_set, // Set 1: Textures
    };

    c.vkCmdBindDescriptorSets(
        cmd,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        self.pipelinemanager.sharedpipelinelayout,
        0, // first set
        sets_to_bind.len,
        &sets_to_bind,
        0,
        null,
    );

    if (config.meshshading) {
        const indirect_offset = @as(u64, self.currentframe) *
            ResourceManager.MAX_OBJECTS * @sizeOf(c.VkDrawMeshTasksIndirectCommandEXT);
        self.device.vkCmdDrawMeshTasksIndirectCountEXT.?(
            cmd,
            self.buffermanager.indirectbuffer.buffer,
            indirect_offset,
            self.buffermanager.countbuffer.buffer,
            count_offset,
            ResourceManager.MAX_OBJECTS,
            @sizeOf(c.VkDrawMeshTasksIndirectCommandEXT),
        );
    } else {
        const indirect_offset = @as(u64, self.currentframe) *
            ResourceManager.MAX_OBJECTS * @sizeOf(c.VkDrawIndirectCommand);
        c.vkCmdDrawIndirectCount(
            cmd,
            self.buffermanager.indirectbuffer.buffer,
            indirect_offset,
            self.buffermanager.countbuffer.buffer,
            count_offset,
            ResourceManager.MAX_OBJECTS,
            @sizeOf(c.VkDrawIndirectCommand),
        );
    }
    if (config.meshshading) {
        c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelinemanager.get("uiMesh"));
        self.device.vkCmdDrawMeshTasksEXT.?(cmd, 1, 1, 1);
    } else {
        // TODO currently this is manually passsing the ids needed to find the right mesh and ui element
        // need to find a way to automatically pass the right info maybe draw indirect
        c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelinemanager.get("slugVertex"));
        c.vkCmdDraw(cmd, 3, 1, 0, 0);
    }

    frame.endGraphicsPass(self);
}

pub fn updateScene(self: *Self, camera: Camera, time: f32) void {
    const aspect = @as(f32, @floatFromInt(self.drawextent2d.width)) /
        @as(f32, @floatFromInt(self.drawextent2d.height));
    self.buffermanager.updateScene(
        self.currentframe,
        aspect,
        camera.orientation,
        camera.position,
        time,
    );
}
