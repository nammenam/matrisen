//! Copyright (C) 2025 B.W. brage.wis@gmail.com
//! This file is part of MATRISEN.
//! MATRISEN is free software: you can redistribute it and/or modify it under
//! the terms of the GNU General Public License (GPL3)
//! see the LICENSE file or <https://www.gnu.org/licenses/> for more details

const std = @import("std");
const log = std.log.scoped(.core);
const debug = @import("debug.zig");
const linalg = @import("../linalg.zig");
const c = @import("../clibs/clibs.zig").libs;

const Quat = linalg.Quat(f32);
const Vec3 = linalg.Vec3(f32);
const Device = @import("Device.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");
const Swapchain = @import("Swapchain.zig");
const DescriptorLayoutBuilder = @import("DescriptorLayoutBuilder.zig");
const Instance = @import("Instance.zig");
const FrameContext = @import("FrameContext.zig");
const AsyncContext = @import("AsyncContext.zig");
const Window = @import("../Window.zig");
const ImageAllocator = @import("ImageAllocator.zig");
const ImageManager = @import("ImageManager.zig");
const BufferAllocator = @import("BufferAllocator.zig");
const BufferManager = @import("BufferManager.zig");
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
imageallocator: ImageAllocator,
bufferallocator: BufferAllocator,
framecontexts: [multibuffering]FrameContext,
asynccontext: AsyncContext,
pipelinemanager: PipelineManager,
descriptormanager: DescriptorManager,
buffermanager: BufferManager,
// imagemanager: ImageManager = .{},

instance: Instance,
device: Device,
physicaldevice: PhysicalDevice,
allocationcallbacks: ?*c.VkAllocationCallbacks,

/// Screen resources
surface: c.VkSurfaceKHR,
swapchain: Swapchain,
drawextent3d: c.VkExtent3D, // for resolution scaling
drawextent2d: c.VkExtent2D, //for resolution scaling
drawimage: ImageAllocator.AllocatedImage = undefined,
renderimage: ImageAllocator.AllocatedImage = undefined,
depthimage: ImageAllocator.AllocatedImage = undefined,

pub fn init(allocator: std.mem.Allocator, window: *Window) Self {
    var arenaallocator = std.heap.ArenaAllocator.init(allocator);
    defer arenaallocator.deinit();
    const initallocator = arenaallocator.allocator();

    var allocationcallbacks_struct: c.VkAllocationCallbacks = debug.allocationcallbacks();
    _ = &allocationcallbacks_struct;
    const allocationcallbacks: ?*c.VkAllocationCallbacks = null;
    const instance: Instance = .init(initallocator, allocationcallbacks);
    const surface = window.createSurface(instance, allocationcallbacks);
    const physicaldevice: PhysicalDevice = .select(initallocator, instance.handle, surface);
    const device: Device = .init(initallocator, physicaldevice);
    const gpuallocator = makeGpuAllocator(physicaldevice.handle, device.handle, instance.handle);

    var windowextent: c.VkExtent2D = .{ .width = 0, .height = 0 };
    window.getSize(&windowextent.width, &windowextent.height);
    const swapchain: Swapchain = .init(
        allocator,
        physicaldevice,
        device.handle,
        surface,
        windowextent,
        allocationcallbacks,
    );
    const drawextent2d = setRenderScale(swapchain.extent, renderscale);
    const drawextent3d: c.VkExtent3D = .{ .width = drawextent2d.width, .height = drawextent2d.height, .depth = 1 };
    var imageallocator: ImageAllocator = .init(device.handle, gpuallocator, allocationcallbacks);
    const drawimage = imageallocator.createDrawImage(drawextent2d, renderformat);
    const renderimage = imageallocator.createRenderImage(drawextent2d, renderformat);
    const depthimage = imageallocator.createDepthImage(drawextent3d, depthformat);
    const pipelinemanager: PipelineManager = .init(allocator, device.handle, allocationcallbacks);

    var framecontexts: [multibuffering]FrameContext = @splat(.{});
    for (&framecontexts) |*framecontext| framecontext.init(device, physicaldevice, allocationcallbacks);

    const asynccontext: AsyncContext = .init(device, physicaldevice, allocationcallbacks);
    const bufferallocator: BufferAllocator = .init(device.handle, gpuallocator, allocationcallbacks);
    const buffermanager: BufferManager = .init();
    const descriptormanager: DescriptorManager = .init(allocator, device, pipelinemanager);

    return .{
        .cpuallocator = allocator,
        .gpuallocator = gpuallocator,
        .allocationcallbacks = allocationcallbacks,
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
        .imageallocator = imageallocator,
        .bufferallocator = bufferallocator,
        .pipelinemanager = pipelinemanager,
        .descriptormanager = descriptormanager,
        .buffermanager = buffermanager,
    };
}

pub fn deinit(self: *Self) void {
    debug.checkVkPanic(c.vkDeviceWaitIdle(self.device.handle));
    defer self.instance.deinit(self.allocationcallbacks);
    defer c.vkDestroySurfaceKHR(self.instance.handle, self.surface, self.allocationcallbacks);
    defer c.vkDestroyDevice(self.device.handle, self.allocationcallbacks);
    defer c.vmaDestroyAllocator(self.gpuallocator);
    defer self.swapchain.deinit(self.cpuallocator, self.device.handle, self.allocationcallbacks);
    defer self.imageallocator.deinitImage(self.drawimage);
    defer self.imageallocator.deinitImage(self.renderimage);
    defer self.imageallocator.deinitImage(self.depthimage);
    defer for (&self.framecontexts) |*frame| frame.deinit(self.device, self.allocationcallbacks);
    defer self.asynccontext.deinit(self.device, self.allocationcallbacks);
    defer self.pipelinemanager.deinit(self.device.handle, self.allocationcallbacks);
    defer self.descriptormanager.deinit(self.cpuallocator, self.device);
    defer self.buffermanager.destroyBuffers(&self.bufferallocator);
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
    debug.checkVkPanic(c.vmaCreateAllocator(&allocator_ci, &gpuallocator));
    log.info("created gpu memory allocator", .{});
    return gpuallocator;
}

pub fn resize(self: *Self, window: *Window) void {
    debug.checkVkPanic(c.vkDeviceWaitIdle(self.device.handle));
    self.swapchain.deinit(self.cpuallocator, self.device.handle, self.allocationcallbacks);
    self.imageallocator.deinitImage(self.drawimage);
    self.imageallocator.deinitImage(self.renderimage);
    self.imageallocator.deinitImage(self.depthimage);
    var windowextent: c.VkExtent2D = .{};
    window.getSize(&windowextent.width, &windowextent.height);
    self.swapchain = .init(
        self.cpuallocator,
        self.physicaldevice,
        self.device.handle,
        self.surface,
        windowextent,
        self.allocationcallbacks,
    );
    self.drawextent2d = setRenderScale(self.swapchain.extent, renderscale);
    self.drawextent3d = .{ .width = self.drawextent2d.width, .height = self.drawextent2d.height, .depth = 1 };
    self.drawimage = self.imageallocator.createDrawImage(self.drawextent2d, renderformat);
    self.renderimage = self.imageallocator.createRenderImage(self.drawextent2d, renderformat);
    self.depthimage = self.imageallocator.createDepthImage(self.drawextent3d, depthformat);
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
    var frame = self.framecontexts[self.currentframe];
    const cmd = frame.command_buffer;

    // 1. OPEN COMMAND BUFFER
    frame.beginFrame(self) catch |err| {
        if (err == error.SwapchainOutOfDate or window.state.resizerequest) {
            self.resize(window);
            window.state.resizerequest = false;
            return;
        }
    };

    const count_offset = @as(u64, self.currentframe) * @sizeOf(u32);
    const indirect_offset = @as(u64, self.currentframe) * 10000 * @sizeOf(c.VkDrawIndirectCommand);
    // ==========================================================
    // 2. RESET COUNT BUFFER
    // ==========================================================
    // Fill the 4-byte count buffer with 0 before compute starts
    c.vkCmdFillBuffer(cmd, self.buffermanager.countbuffer.buffer, count_offset, @sizeOf(u32), 0);

    // Barrier: Ensure FillBuffer is done before the Compute Shader reads/writes it
    const fill_barrier = c.VkBufferMemoryBarrier{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
        .dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT | c.VK_ACCESS_SHADER_WRITE_BIT,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .buffer = self.buffermanager.countbuffer.buffer,
        .offset = 0,
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

    // ==========================================================
    // 3. COMPUTE PASS (Culling)
    // ==========================================================
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.pipelinemanager.computepipeline);
    c.vkCmdBindDescriptorSets(
        cmd,
        c.VK_PIPELINE_BIND_POINT_COMPUTE,
        self.pipelinemanager.sharedpipelinelayout,
        0,
        1,
        &self.descriptormanager.dynamicsets[self.currentframe],
        0,
        null,
    );
    c.vkCmdDispatch(cmd, 1, 1, 1); // Dispatch threads based on object count

    // ==========================================================
    // 4. MEMORY BARRIER (Block graphics until compute is done)
    // ==========================================================
    // We use a global memory barrier here to cover BOTH the indirect buffer and count buffer easily
    const compute_to_draw_barrier = c.VkMemoryBarrier{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = c.VK_ACCESS_SHADER_WRITE_BIT,
        .dstAccessMask = c.VK_ACCESS_INDIRECT_COMMAND_READ_BIT,
    };
    c.vkCmdPipelineBarrier(
        cmd,
        c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        c.VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT,
        0,
        1,
        &compute_to_draw_barrier,
        0,
        null,
        0,
        null,
    );

    // ==========================================================
    // 5. GRAPHICS PASS (Dynamic Rendering)
    // ==========================================================
    frame.beginGraphicsPass(self);

    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelinemanager.defaultpipeline);
    c.vkCmdBindDescriptorSets(
        cmd,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        self.pipelinemanager.sharedpipelinelayout,
        0,
        1,
        &self.descriptormanager.dynamicsets[self.currentframe],
        0,
        null,
    );

    c.vkCmdDrawIndirectCount(
        cmd,
        self.buffermanager.indirectbuffer.buffer,
        indirect_offset,
        self.buffermanager.countbuffer.buffer,
        count_offset,
        10000,
        @sizeOf(c.VkDrawIndirectCommand),
    );
    frame.endGraphicsPass(self);

    // 6. CLOSE & SUBMIT
    frame.endFrame(self);
    self.framenumber +%= 1;
    self.switch_frame();
}

pub fn updateScene(self: *Self, camerarot: Quat, camerapos: Vec3, time: f32) void {
    // self.buffermanager.rotateDummy(self.currentframe, self.framenumber);
    const aspect = @as(f32, @floatFromInt(self.drawextent2d.width)) /
        @as(f32, @floatFromInt(self.drawextent2d.height));
    self.buffermanager.updateScene(
        &self.bufferallocator,
        self.currentframe,
        aspect,
        camerarot,
        camerapos,
        time,
    );
}
