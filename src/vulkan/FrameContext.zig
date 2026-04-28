const c = @import("../clibs/clibs.zig").libs;
const std = @import("std");
const debug = @import("debug.zig");
const log = std.log.scoped(.framecontext);
const transitionImage = @import("Renderer.zig").transitionImage;
const copyImageToImage = @import("Renderer.zig").copyImageToImage;
const Core = @import("Core.zig");
const Device = @import("Device.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");
const DescriptorAllocator = @import("DescriptorAllocator.zig");

const Self = @This();

acquiresemaphore: c.VkSemaphore = null,
renderfence: c.VkFence = null,
command_pool: c.VkCommandPool = null,
command_buffer: c.VkCommandBuffer = null,
swapchainindex: u32 = 0,
descriptorallocator: DescriptorAllocator = .{},
dynamicset: c.VkDescriptorSet = undefined,

pub fn init(
    self: *Self,
    device: Device,
    physicaldevice: PhysicalDevice,
    allocationcallbacks: ?*c.VkAllocationCallbacks,
) void {
    const semaphore_ci = c.VkSemaphoreCreateInfo{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };

    const fence_ci = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    const command_pool_info = graphics_cmd_pool_info(physicaldevice.graphics_queue_family);
    debug.checkVkPanic(c.vkCreateCommandPool(
        device.handle,
        &command_pool_info,
        allocationcallbacks,
        &self.command_pool,
    ));
    const command_buffer_info = graphics_cmdbuffer_info(self.command_pool);
    debug.checkVkPanic(c.vkAllocateCommandBuffers(
        device.handle,
        &command_buffer_info,
        &self.command_buffer,
    ));
    debug.checkVkPanic(c.vkCreateSemaphore(
        device.handle,
        &semaphore_ci,
        allocationcallbacks,
        &self.acquiresemaphore,
    ));
    debug.checkVkPanic(c.vkCreateFence(
        device.handle,
        &fence_ci,
        allocationcallbacks,
        &self.renderfence,
    ));

    log.info("Created framecontext", .{});
}

pub fn deinit(self: *Self, device: Device, allocationcallbacks: ?*c.VkAllocationCallbacks) void {
    c.vkDestroyCommandPool(device.handle, self.command_pool, allocationcallbacks);
    c.vkDestroyFence(device.handle, self.renderfence, allocationcallbacks);
    c.vkDestroySemaphore(device.handle, self.acquiresemaphore, allocationcallbacks);
}

pub fn beginFrame(self: *Self, core: *Core) !void {
    const timeout: u64 = 4_000_000_000; // 4 seconds

    // Wait for the previous frame to finish
    debug.checkVkPanic(c.vkWaitForFences(core.device.handle, 1, &self.renderfence, c.VK_TRUE, timeout));

    // Acquire the next swapchain image
    const e = c.vkAcquireNextImageKHR(
        core.device.handle,
        core.swapchain.handle,
        timeout,
        self.acquiresemaphore,
        null,
        &self.swapchainindex,
    );
    if (e == c.VK_ERROR_OUT_OF_DATE_KHR) {
        return error.SwapchainOutOfDate;
    }

    // Reset fences and command buffer
    debug.checkVkPanic(c.vkResetFences(core.device.handle, 1, &self.renderfence));
    debug.checkVkPanic(c.vkResetCommandBuffer(self.command_buffer, 0));

    // OPEN COMMAND BUFFER
    const cmd_begin_info: c.VkCommandBufferBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    debug.checkVkPanic(c.vkBeginCommandBuffer(self.command_buffer, &cmd_begin_info));
}

pub fn beginGraphicsPass(self: *Self, core: *Core) void {
    const cmd = self.command_buffer;
    const clearvalue = c.VkClearColorValue{ .float32 = .{ 0.014, 0.014, 0.014, 1 } };

    // Transition the render image so we can draw to it
    transitionImage(
        cmd,
        core.renderimage.image,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    );

    const color_attachment: c.VkRenderingAttachmentInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = core.drawimage.view,
        .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .resolveImageView = core.renderimage.view,
        .resolveImageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .resolveMode = c.VK_RESOLVE_MODE_AVERAGE_BIT,
        .clearValue = .{ .color = clearvalue },
    };

    const depth_attachment: c.VkRenderingAttachmentInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = core.depthimage.view,
        .imageLayout = c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .clearValue = .{ .depthStencil = .{ .depth = 1.0, .stencil = 0.0 } },
    };

    const render_info: c.VkRenderingInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = core.drawextent2d,
        },
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment,
        .pDepthAttachment = &depth_attachment,
    };

    const viewport: c.VkViewport = .{
        .x = 0.0,
        .y = 0.0,
        .width = @as(f32, @floatFromInt(core.drawextent2d.width)),
        .height = @as(f32, @floatFromInt(core.drawextent2d.height)),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor: c.VkRect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = core.drawextent2d,
    };

    // OPEN RENDER PASS
    c.vkCmdBeginRendering(cmd, &render_info);
    c.vkCmdSetViewport(cmd, 0, 1, &viewport);
    c.vkCmdSetScissor(cmd, 0, 1, &scissor);
}

pub fn endGraphicsPass(self: *Self, core: *Core) void {
    const cmd = self.command_buffer;

    // CLOSE RENDER PASS
    c.vkCmdEndRendering(cmd);

    // Transition render image to be read, and swapchain to be written to
    transitionImage(
        cmd,
        core.renderimage.image,
        c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    );
    transitionImage(
        cmd,
        core.swapchain.images[self.swapchainindex],
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    );

    // Blit/Copy the off-screen render image to the actual swapchain image
    copyImageToImage(
        cmd,
        core.renderimage.image,
        core.swapchain.images[self.swapchainindex],
        core.drawextent2d,
        core.swapchain.extent,
    );

    // Transition the swapchain image to a presentable layout
    transitionImage(
        cmd,
        core.swapchain.images[self.swapchainindex],
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    );
}

pub fn endFrame(self: *Self, core: *Core) void {
    const cmd = self.command_buffer;

    // CLOSE COMMAND BUFFER
    debug.checkVkPanic(c.vkEndCommandBuffer(cmd));

    const cmd_info = c.VkCommandBufferSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    };

    const wait_info = c.VkSemaphoreSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = self.acquiresemaphore,
        .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
    };

    const signal_info = c.VkSemaphoreSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = core.swapchain.semaphores[self.swapchainindex],
        .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
    };

    const submit = c.VkSubmitInfo2{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmd_info,
        .waitSemaphoreInfoCount = 1,
        .pWaitSemaphoreInfos = &wait_info,
        .signalSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &signal_info,
    };

    // SUBMIT TO GPU
    debug.checkVkPanic(c.vkQueueSubmit2(core.device.graphics_queue, 1, &submit, self.renderfence));

    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &core.swapchain.semaphores[self.swapchainindex],
        .swapchainCount = 1,
        .pSwapchains = &core.swapchain.handle,
        .pImageIndices = &self.swapchainindex,
    };

    // PRESENT TO WINDOW
    _ = c.vkQueuePresentKHR(core.device.graphics_queue, &present_info);
}

pub fn graphics_cmd_pool_info(queue_family_index: u32) c.VkCommandPoolCreateInfo {
    return c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queue_family_index,
    };
}

pub fn graphics_cmdbuffer_info(pool: c.VkCommandPool) c.VkCommandBufferAllocateInfo {
    return c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
}
