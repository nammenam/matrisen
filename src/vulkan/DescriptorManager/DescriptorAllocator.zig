const std = @import("std");
const debug = @import("debug.zig");
const c = @import("../clibs/clibs.zig").libs;

pub const PoolSizeRatio = struct {
    ratio: f32,
    type: c.VkDescriptorType,
};

const Self = @This();

ready_pools: std.ArrayList(c.VkDescriptorPool) = .empty,
full_pools: std.ArrayList(c.VkDescriptorPool) = .empty,
ratios: std.ArrayList(PoolSizeRatio) = .empty,
sets_per_pool: u32 = 0,

pub fn init(
    device: c.VkDevice,
    initial_sets: u32,
    pool_ratios: []PoolSizeRatio,
    alloc: std.mem.Allocator,
) Self {
    var self: Self = .{};
    self.ratios.clearAndFree(alloc);
    self.ratios.appendSlice(alloc, pool_ratios) catch @panic("Failed to append to ratios");
    const new_pool = create_pool(device, initial_sets, pool_ratios, std.heap.page_allocator);
    self.sets_per_pool = @intFromFloat(@as(f32, @floatFromInt(initial_sets)) * 1.5);
    self.ready_pools.append(alloc, new_pool) catch @panic("Failed to append to ready_pools");
    return self;
}

pub fn deinit(self: *@This(), device: c.VkDevice, a: std.mem.Allocator) void {
    self.clear_pools(device, a);
    self.destroy_pools(device, a);
    self.ready_pools.deinit(a);
    self.full_pools.deinit(a);
    self.ratios.deinit(a);
}

pub fn clear_pools(self: *@This(), device: c.VkDevice, a: std.mem.Allocator) void {
    for (self.ready_pools.items) |pool| {
        _ = c.vkResetDescriptorPool(device, pool, 0);
    }
    for (self.full_pools.items) |pool| {
        _ = c.vkResetDescriptorPool(device, pool, 0);
    }
    self.full_pools.clearAndFree(a);
}

pub fn destroy_pools(self: *@This(), device: c.VkDevice, a: std.mem.Allocator) void {
    for (self.ready_pools.items) |pool| {
        _ = c.vkDestroyDescriptorPool(device, pool, null);
    }
    self.ready_pools.clearAndFree(a);
    for (self.full_pools.items) |pool| {
        _ = c.vkDestroyDescriptorPool(device, pool, null);
    }
    self.full_pools.clearAndFree(a);
}

pub fn allocate(
    self: *@This(),
    a: std.mem.Allocator,
    device: c.VkDevice,
    layout: c.VkDescriptorSetLayout,
    pNext: ?*anyopaque,
) c.VkDescriptorSet {
    var pool_to_use = self.get_pool(device);

    var info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = pNext,
        .descriptorPool = pool_to_use,
        .descriptorSetCount = 1,
        .pSetLayouts = &layout,
    };
    var descriptor_set: c.VkDescriptorSet = undefined;
    const result = c.vkAllocateDescriptorSets(device, &info, &descriptor_set);
    if (result == c.VK_ERROR_OUT_OF_POOL_MEMORY or result == c.VK_ERROR_FRAGMENTED_POOL) {
        self.full_pools.append(a, pool_to_use) catch @panic("Failed to append to full_pools");
        pool_to_use = self.get_pool(device);
        info.descriptorPool = pool_to_use;
        debug.checkVkPanic(c.vkAllocateDescriptorSets(device, &info, &descriptor_set));
    }
    self.ready_pools.append(a, pool_to_use) catch @panic("Failed to append to full_pools");
    return descriptor_set;
}

fn get_pool(self: *@This(), device: c.VkDevice) c.VkDescriptorPool {
    var new_pool: c.VkDescriptorPool = undefined;
    if (self.ready_pools.items.len != 0) {
        new_pool = self.ready_pools.pop().?;
    } else {
        new_pool = create_pool(device, self.sets_per_pool, self.ratios.items, std.heap.page_allocator);
        self.sets_per_pool = @intFromFloat(@as(f32, @floatFromInt(self.sets_per_pool)) * 1.5);
        if (self.sets_per_pool > 4092) {
            self.sets_per_pool = 4092;
        }
    }
    return new_pool;
}

fn create_pool(
    device: c.VkDevice,
    set_count: u32,
    pool_ratios: []PoolSizeRatio,
    alloc: std.mem.Allocator,
) c.VkDescriptorPool {
    var pool_sizes: std.ArrayList(c.VkDescriptorPoolSize) = .empty;
    defer pool_sizes.deinit(alloc);
    for (pool_ratios) |ratio| {
        const size = c.VkDescriptorPoolSize{
            .type = ratio.type,
            .descriptorCount = set_count * @as(u32, @intFromFloat(ratio.ratio)),
        };
        pool_sizes.append(alloc, size) catch @panic("Failed to append to pool_sizes");
    }

    const info = c.VkDescriptorPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = 0,
        .maxSets = set_count,
        .poolSizeCount = @as(u32, @intCast(pool_sizes.items.len)),
        .pPoolSizes = pool_sizes.items.ptr,
    };

    var pool: c.VkDescriptorPool = undefined;
    debug.checkVkPanic(c.vkCreateDescriptorPool(device, &info, null, &pool));
    return pool;
}
