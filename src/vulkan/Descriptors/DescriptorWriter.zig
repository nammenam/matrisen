const std = @import("std");
const c = @import("../clibs/clibs.zig").libs;

writes: std.ArrayList(c.VkWriteDescriptorSet) = undefined,
buffer_infos: std.ArrayList(c.VkDescriptorBufferInfo) = undefined,
image_infos: std.ArrayList(c.VkDescriptorImageInfo) = undefined,

pub fn init() @This() {
    return .{
        .writes = .empty,
        .buffer_infos = .empty,
        .image_infos = .empty,
    };
}

pub fn deinit(self: *@This(), a: std.mem.Allocator) void {
    self.writes.deinit(a);
    self.buffer_infos.deinit(a);
    self.image_infos.deinit(a);
}

pub fn writeBuffer(
    self: *@This(),
    a: std.mem.Allocator,
    binding: u32,
    buffer: c.VkBuffer,
    size: usize,
    offset: usize,
    ty: c.VkDescriptorType,
) void {
    const info_container = struct {
        var info: c.VkDescriptorBufferInfo = c.VkDescriptorBufferInfo{};
    };
    info_container.info = c.VkDescriptorBufferInfo{ .buffer = buffer, .offset = offset, .range = size };
    self.buffer_infos.append(a, info_container.info) catch @panic("failed to append");
    const write = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstBinding = binding,
        .dstSet = null,
        .descriptorCount = 1,
        .descriptorType = ty,
        .pBufferInfo = &info_container.info,
    };
    self.writes.append(a, write) catch @panic("failed to append");
}

pub fn writeImage(
    self: *@This(),
    a: std.mem.Allocator,
    binding: u32,
    image: c.VkImageView,
    sampler: c.VkSampler,
    layout: c.VkImageLayout,
    ty: c.VkDescriptorType,
) void {
    const info_container = struct {
        var info: c.VkDescriptorImageInfo = c.VkDescriptorImageInfo{};
    };
    info_container.info = c.VkDescriptorImageInfo{ .sampler = sampler, .imageView = image, .imageLayout = layout };

    self.image_infos.append(a, info_container.info) catch @panic("append failed");
    const write = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstBinding = binding,
        .dstSet = null,
        .descriptorCount = 1,
        .descriptorType = ty,
        .pImageInfo = &info_container.info,
    };
    self.writes.append(a, write) catch @panic("append failed");
}

pub fn clear(self: *@This(), a: std.mem.Allocator) void {
    self.writes.clearAndFree(a);
    self.buffer_infos.clearAndFree(a);
    self.image_infos.clearAndFree(a);
}

pub fn updateSet(self: *@This(), device: c.VkDevice, set: c.VkDescriptorSet) void {
    for (self.writes.items) |*write| {
        write.*.dstSet = set;
    }
    c.vkUpdateDescriptorSets(device, @intCast(self.writes.items.len), self.writes.items.ptr, 0, null);
}
