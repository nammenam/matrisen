const c = @import("c");
const std = @import("std");
const errors = @import("errors.zig");
const Core = @import("Core.zig");
const Device = @import("Device.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");
const Swapchain = @import("Swapchain.zig");

const Self = @This();

device: c.VkDevice,
queue: c.VkQueue,
alloc_callbacks: ?*c.VkAllocationCallbacks,
acquiresemaphore: c.VkSemaphore, // Signaled by Swapchain when image is ready
fence: c.VkFence, // Signaled by GPU when drawing is done
command_pool: c.VkCommandPool,
command_buffer: c.VkCommandBuffer,
swapchainindex: u32,

pub fn init(
    device: c.VkDevice,
    queue: c.VkQueue,
    physicaldevice: PhysicalDevice,
    alloc_callbacks: ?*c.VkAllocationCallbacks,
) Self {
    var command_pool: c.VkCommandPool = undefined;
    var command_buffer: c.VkCommandBuffer = undefined;
    var acquiresemaphore: c.VkSemaphore = undefined;
    var fence: c.VkFence = undefined;

    const semaphore_ci = c.VkSemaphoreCreateInfo{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    const fence_ci = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    const command_pool_info = graphics_cmd_pool_info(physicaldevice.graphics_queue_family);
    errors.checkVkPanic(c.vkCreateCommandPool(
        device,
        &command_pool_info,
        alloc_callbacks,
        &command_pool,
    ));

    const command_buffer_info = graphics_cmdbuffer_info(command_pool);
    errors.checkVkPanic(
        c.vkAllocateCommandBuffers(device, &command_buffer_info, &command_buffer),
    );

    errors.checkVkPanic(c.vkCreateSemaphore(
        device,
        &semaphore_ci,
        alloc_callbacks,
        &acquiresemaphore,
    ));
    errors.checkVkPanic(c.vkCreateFence(device, &fence_ci, alloc_callbacks, &fence));

    return .{
        .command_pool = command_pool,
        .acquiresemaphore = acquiresemaphore,
        .command_buffer = command_buffer,
        .device = device,
        .fence = fence,
        .swapchainindex = 0,
        .alloc_callbacks = alloc_callbacks,
        .queue = queue,
    };
}

pub fn deinit(self: *Self) void {
    c.vkDestroyCommandPool(self.device, self.command_pool, self.alloc_callbacks);
    c.vkDestroyFence(self.device, self.fence, self.alloc_callbacks);
    c.vkDestroySemaphore(self.device, self.acquiresemaphore, self.alloc_callbacks);
}

pub fn beginFrame(self: *Self, swapchain: *Swapchain) !void {
    const timeout: u64 = 4_000_000_000; // 4 seconds
    errors.checkVkPanic(c.vkWaitForFences(self.device, 1, &self.fence, c.VK_TRUE, timeout));
    const e = c.vkAcquireNextImageKHR(
        self.device,
        swapchain.handle,
        timeout,
        self.acquiresemaphore,
        null,
        &self.swapchainindex,
    );
    if (e == c.VK_ERROR_OUT_OF_DATE_KHR) {
        return error.SwapchainOutOfDate;
    }

    errors.checkVkPanic(c.vkResetFences(self.device, 1, &self.fence));
    errors.checkVkPanic(c.vkResetCommandBuffer(self.command_buffer, 0));

    const cmd_begin_info: c.VkCommandBufferBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    errors.checkVkPanic(c.vkBeginCommandBuffer(self.command_buffer, &cmd_begin_info));
}

pub fn endFrame(self: *Self, swapchain: *Swapchain) void {
    const cmd = self.command_buffer;

    errors.checkVkPanic(c.vkEndCommandBuffer(cmd));

    const cmd_info = c.VkCommandBufferSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    };

    const wait_info = c.VkSemaphoreSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = self.acquiresemaphore,
        // .stageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
    };

    const signal_info = c.VkSemaphoreSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = swapchain.semaphores[self.swapchainindex],
        .stageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
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

    errors.checkVkPanic(c.vkQueueSubmit2(self.queue, 1, &submit, self.fence));

    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &swapchain.semaphores[self.swapchainindex],
        .swapchainCount = 1,
        .pSwapchains = &swapchain.handle,
        .pImageIndices = &self.swapchainindex,
    };

    _ = c.vkQueuePresentKHR(self.queue, &present_info);
}

pub fn beginGraphicsPass(self: *Self, core: *Core) void {
    const cmd = self.command_buffer;
    const clearvalue = c.VkClearColorValue{ .float32 = .{ 0.014, 0.014, 0.014, 1 } };

    transitionImage(
        cmd,
        core.renderimage.image,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    );
    transitionImage(
        cmd,
        core.drawimage.image,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    );
    transitionImage(
        cmd,
        core.depthimage.image,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
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

pub fn transitionImage(
    cmd: c.VkCommandBuffer,
    image: c.VkImage,
    current_layout: c.VkImageLayout,
    new_layout: c.VkImageLayout,
) void {
    var barrier: c.VkImageMemoryBarrier2 = .{ .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2 };
    barrier.srcStageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    barrier.srcAccessMask = c.VK_ACCESS_2_MEMORY_WRITE_BIT;
    barrier.dstStageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    barrier.dstAccessMask = c.VK_ACCESS_2_MEMORY_WRITE_BIT | c.VK_ACCESS_2_MEMORY_READ_BIT;
    barrier.oldLayout = current_layout;
    barrier.newLayout = new_layout;

    const aspect_mask: u32 = if (new_layout == c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL) blk: {
        break :blk c.VK_IMAGE_ASPECT_DEPTH_BIT;
    } else blk: {
        break :blk c.VK_IMAGE_ASPECT_COLOR_BIT;
    };
    const subresource_range: c.VkImageSubresourceRange = .{
        .aspectMask = aspect_mask,
        .baseMipLevel = 0,
        .levelCount = c.VK_REMAINING_MIP_LEVELS,
        .baseArrayLayer = 0,
        .layerCount = c.VK_REMAINING_ARRAY_LAYERS,
    };

    barrier.image = image;
    barrier.subresourceRange = subresource_range;

    const dep_info: c.VkDependencyInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO_KHR,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &barrier,
    };

    c.vkCmdPipelineBarrier2(cmd, &dep_info);
}

pub fn copyImageToImage(
    cmd: c.VkCommandBuffer,
    src: c.VkImage,
    dst: c.VkImage,
    src_size: c.VkExtent2D,
    dst_size: c.VkExtent2D,
) void {
    var blit_region = c.VkImageBlit2{ .sType = c.VK_STRUCTURE_TYPE_IMAGE_BLIT_2, .pNext = null };
    blit_region.srcOffsets[1].x = @intCast(src_size.width);
    blit_region.srcOffsets[1].y = @intCast(src_size.height);
    blit_region.srcOffsets[1].z = 1;
    blit_region.dstOffsets[1].x = @intCast(dst_size.width);
    blit_region.dstOffsets[1].y = @intCast(dst_size.height);
    blit_region.dstOffsets[1].z = 1;
    blit_region.srcSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    blit_region.srcSubresource.baseArrayLayer = 0;
    blit_region.srcSubresource.layerCount = 1;
    blit_region.srcSubresource.mipLevel = 0;
    blit_region.dstSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    blit_region.dstSubresource.baseArrayLayer = 0;
    blit_region.dstSubresource.layerCount = 1;
    blit_region.dstSubresource.mipLevel = 0;

    var blit_info = c.VkBlitImageInfo2{ .sType = c.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2, .pNext = null };
    blit_info.srcImage = src;
    blit_info.srcImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    blit_info.dstImage = dst;
    blit_info.dstImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    blit_info.regionCount = 1;
    blit_info.pRegions = &blit_region;
    blit_info.filter = c.VK_FILTER_NEAREST;

    c.vkCmdBlitImage2(cmd, &blit_info);
}
