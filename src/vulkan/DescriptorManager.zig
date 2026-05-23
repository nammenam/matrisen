const std = @import("std");
const c = @import("c");
const errors = @import("errors.zig");
const Core = @import("Core.zig");
const DescriptorAllocator = @import("DescriptorAllocator.zig");
const Device = @import("Device.zig");
const PipelineManager = @import("PipelineManager.zig");
const DescriptorWriter = @import("DescriptorWriter.zig");
const ResourceManager = @import("ResourceManager.zig");

const Self = @This();

device: c.VkDevice,

// Set 0: Dynamic SceneData
allocators: [Core.multibuffering]DescriptorAllocator,
sets: [Core.multibuffering]c.VkDescriptorSet,

// Set 1: Bindless Textures
bindless_pool: c.VkDescriptorPool,
bindless_set: c.VkDescriptorSet,

pub fn init(allocator: std.mem.Allocator, device: c.VkDevice, pipelinemanager: PipelineManager) Self {
    // ========================================================================
    // 1. Initialize Dynamic SceneData Sets (Set 0) using your Allocator
    // ========================================================================
    var ratios = [_]DescriptorAllocator.PoolSizeRatio{
        .{ .ratio = 1, .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER },
    };
    var sets: [Core.multibuffering]c.VkDescriptorSet = @splat(undefined);
    var allocators: [Core.multibuffering]DescriptorAllocator = @splat(.{});

    for (&sets, &allocators) |*set, *descriptorallocator| {
        descriptorallocator.* = .init(device, 1000, &ratios, allocator);
        set.* = descriptorallocator.allocate(
            allocator,
            device,
            pipelinemanager.descriptorlayout,
            null,
        );
    }

    // ========================================================================
    // 2. Initialize Bindless Texture Set (Set 1) Manually
    // (Because it requires the UPDATE_AFTER_BIND flag)
    // ========================================================================
    var bindless_pool: c.VkDescriptorPool = undefined;
    var bindless_set: c.VkDescriptorSet = undefined;

    const pool_size = c.VkDescriptorPoolSize{
        .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = ResourceManager.MAX_TEXTURES,
    };

    const pool_info = c.VkDescriptorPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .pNext = null,
        .flags = c.VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT, // Critical flag
        .maxSets = 1,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
    };
    errors.checkVkPanic(c.vkCreateDescriptorPool(device, &pool_info, null, &bindless_pool));

    const alloc_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = bindless_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &pipelinemanager.bindless_layout,
    };
    errors.checkVkPanic(c.vkAllocateDescriptorSets(device, &alloc_info, &bindless_set));

    return .{
        .device = device,
        .allocators = allocators,
        .sets = sets,
        .bindless_pool = bindless_pool,
        .bindless_set = bindless_set,
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    c.vkDestroyDescriptorPool(self.device, self.bindless_pool, null);

    for (&self.allocators) |*dynamicallocator| {
        dynamicallocator.deinit(self.device, alloc);
    }
}

pub fn writeDynamicSet(
    self: *Self,
    alloc: std.mem.Allocator,
    data: ResourceManager.AllocatedBuffer,
    frame: u8,
) void {
    var writer = DescriptorWriter.init();
    defer writer.deinit(alloc);

    writer.writeBuffer(
        alloc,
        0,
        data.buffer,
        @sizeOf(ResourceManager.SceneData),
        0,
        c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    );
    writer.updateSet(self.device, self.sets[frame]);
}

// ========================================================================
// Bindless Connector
// ========================================================================

pub fn writeBindlessTexture(
    self: *Self,
    alloc: std.mem.Allocator,
    image_view: c.VkImageView,
    sampler: c.VkSampler,
    index: u32,
) void {
    var writer = DescriptorWriter.init();
    defer writer.deinit(alloc);

    writer.writeImageArray(
        alloc,
        0, // binding
        index, // The exact array slot
        image_view,
        sampler,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    );

    writer.updateSet(self.device, self.bindless_set);
}
