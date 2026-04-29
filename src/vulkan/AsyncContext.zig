const std = @import("std");
const c = @import("../clibs/clibs.zig").libs;
const debug = @import("debug.zig");
const log = std.log.scoped(.asynccontext);
const Core = @import("Core.zig");
const Device = @import("Device.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");

const Self = @This();

fence: c.VkFence,
commandpool: c.VkCommandPool,
commandbuffer: c.VkCommandBuffer,

pub fn init(device: Device, physicaldevice: PhysicalDevice, allocationcallbacks: ?*c.VkAllocationCallbacks) Self {
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
    debug.checkVkPanic(c.vkCreateFence(
        device.handle,
        &upload_fence_ci,
        allocationcallbacks,
        &fence,
    ));

    debug.checkVkPanic(c.vkCreateCommandPool(
        device.handle,
        &commandpool_ci,
        allocationcallbacks,
        &commandpool,
    ));

    const upload_commandbuffer_ai: c.VkCommandBufferAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = commandpool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    debug.checkVkPanic(c.vkAllocateCommandBuffers(
        device.handle,
        &upload_commandbuffer_ai,
        &commandbuffer,
    ));
    log.info("Created asynccontext", .{});
    return .{
        .fence = fence,
        .commandpool = commandpool,
        .commandbuffer = commandbuffer,
    };
}

pub fn deinit(self: *Self, device: Device, allocationcallbacks: ?*c.VkAllocationCallbacks) void {
    c.vkDestroyCommandPool(device.handle, self.commandpool, allocationcallbacks);
    c.vkDestroyFence(device.handle, self.fence, allocationcallbacks);
}

pub fn submitBegin(self: *Self, core: *Core) void {
    debug.checkVk(c.vkResetFences(core.device.handle, 1, &self.fence)) catch {
        @panic("Failed to reset immidiate fence");
    };
    debug.checkVk(c.vkResetCommandBuffer(self.commandbuffer, 0)) catch {
        @panic("Failed to reset immidiate command buffer");
    };
    const cmd = self.commandbuffer;

    const commmand_begin_ci: c.VkCommandBufferBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    debug.checkVk(c.vkBeginCommandBuffer(cmd, &commmand_begin_ci)) catch {
        @panic("Failed to begin command buffer");
    };
}

pub fn submitEnd(self: *Self, core: *Core) void {
    const cmd = self.commandbuffer;
    debug.checkVk(c.vkEndCommandBuffer(cmd)) catch @panic("Failed to end command buffer");

    const cmd_info: c.VkCommandBufferSubmitInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    };
    const submit_info: c.VkSubmitInfo2 = .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmd_info,
    };
    debug.checkVkPanic(c.vkQueueSubmit2(core.device.graphics_queue, 1, &submit_info, self.fence));
    debug.checkVkPanic(c.vkWaitForFences(core.device.handle, 1, &self.fence, c.VK_TRUE, 1_000_000_000));
}
