const std = @import("std");
const c = @import("c");
const errors = @import("errors.zig");
const log = std.log.scoped(.asynccontext);
const Core = @import("Core.zig");
const Device = @import("Device.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");

const Self = @This();

device: Device,
alloc_callbacks: ?*c.VkAllocationCallbacks,
fence: c.VkFence,
commandpool: c.VkCommandPool,
commandbuffer: c.VkCommandBuffer,

pub fn init(
    device: Device,
    physicaldevice: PhysicalDevice,
    alloc_callbacks: ?*c.VkAllocationCallbacks,
) Self {
    const commandpool_ci: c.VkCommandPoolCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = physicaldevice.graphics_queue_family,
    };

    const upload_fence_ci: c.VkFenceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    };
    var fence: c.VkFence = null;
    var commandpool: c.VkCommandPool = null;
    var commandbuffer: c.VkCommandBuffer = null;
    errors.checkVkPanic(c.vkCreateFence(
        device.handle,
        &upload_fence_ci,
        alloc_callbacks,
        &fence,
    ));

    errors.checkVkPanic(c.vkCreateCommandPool(
        device.handle,
        &commandpool_ci,
        alloc_callbacks,
        &commandpool,
    ));

    const upload_commandbuffer_ai: c.VkCommandBufferAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = commandpool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    errors.checkVkPanic(c.vkAllocateCommandBuffers(
        device.handle,
        &upload_commandbuffer_ai,
        &commandbuffer,
    ));
    log.info("Created asynccontext", .{});
    return .{
        .device = device,
        .alloc_callbacks = alloc_callbacks,
        .fence = fence,
        .commandpool = commandpool,
        .commandbuffer = commandbuffer,
    };
}

pub fn deinit(self: *Self) void {
    c.vkDestroyCommandPool(self.device.handle, self.commandpool, self.alloc_callbacks);
    c.vkDestroyFence(self.device.handle, self.fence, self.alloc_callbacks);
}

pub fn submitBegin(self: *Self) void {
    errors.checkVk(c.vkResetFences(self.device.handle, 1, &self.fence)) catch {
        @panic("Failed to reset immidiate fence");
    };
    errors.checkVk(c.vkResetCommandBuffer(self.commandbuffer, 0)) catch {
        @panic("Failed to reset immidiate command buffer");
    };
    const cmd = self.commandbuffer;

    const commmand_begin_ci: c.VkCommandBufferBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    errors.checkVk(c.vkBeginCommandBuffer(cmd, &commmand_begin_ci)) catch {
        @panic("Failed to begin command buffer");
    };
}

pub fn submitEnd(self: *Self) void {
    const cmd = self.commandbuffer;
    errors.checkVk(c.vkEndCommandBuffer(cmd)) catch @panic("Failed to end command buffer");

    const cmd_info: c.VkCommandBufferSubmitInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    };
    const submit_info: c.VkSubmitInfo2 = .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmd_info,
    };
    errors.checkVkPanic(c.vkQueueSubmit2(self.device.graphics_queue, 1, &submit_info, self.fence));
    errors.checkVkPanic(c.vkWaitForFences(self.device.handle, 1, &self.fence, c.VK_TRUE, 1_000_000_000));
}
