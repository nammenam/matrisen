const std = @import("std");
const debug = @import("debug.zig");
const c = @import("../clibs/clibs.zig").libs;

const Self = @This();

bindings: std.ArrayList(c.VkDescriptorSetLayoutBinding) = undefined,

pub fn init() Self {
    return .{ .bindings = .empty };
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    self.bindings.deinit(gpa);
}

pub fn addBinding(
    self: *Self,
    allocator: std.mem.Allocator,
    binding: u32,
    descriptor_type: c.VkDescriptorType,
) void {
    const new_binding: c.VkDescriptorSetLayoutBinding = .{
        .binding = binding,
        .descriptorType = descriptor_type,
        .descriptorCount = 1,
    };
    self.bindings.append(allocator, new_binding) catch @panic("Failed to append to bindings");
}

pub fn clear(self: *Self) void {
    self.bindings.clearAndFree();
}

pub fn build(
    self: *Self,
    device: c.VkDevice,
    shader_stages: c.VkShaderStageFlags,
    pnext: ?*anyopaque,
    flags: c.VkDescriptorSetLayoutCreateFlags,
) c.VkDescriptorSetLayout {
    for (self.bindings.items) |*binding| {
        binding.stageFlags |= shader_stages;
    }

    const info = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = @as(u32, @intCast(self.bindings.items.len)),
        .pBindings = self.bindings.items.ptr,
        .flags = flags,
        .pNext = pnext,
    };
    var layout: c.VkDescriptorSetLayout = undefined;
    debug.checkVkPanic(c.vkCreateDescriptorSetLayout(device, &info, null, &layout));
    return layout;
}
