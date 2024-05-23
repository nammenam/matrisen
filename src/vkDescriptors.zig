const std = @import("std");
const c = @import("clibs.zig");
const vki = @import("vkUtils.zig");

pub const DescriptorLayoutBuilder = struct {
    bindings: std.ArrayList(c.VkDescriptorSetLayoutBinding),
    const Self = @This();

    pub fn add_binding(self: *Self, binding: u32, descriptor_type: c.VkDescriptorType) void {
        const new_binding = std.mem.zeroInit(c.VkDescriptorSetLayoutBinding, .{
            .binding = binding,
            .descriptorType = descriptor_type,
            .descriptorCount = 1,
        });
        self.bindings.append(new_binding) catch @panic("Failed to append to bindings");
    }

    pub fn clear(self: *Self) void {
        self.bindings.clearAndFree();
    }

    pub fn build(self: *Self, device: c.VkDevice, shader_stages: c.VkShaderStageFlags, pnext: ?*anyopaque, flags: c.VkDescriptorSetLayoutCreateFlags) c.VkDescriptorSetLayout {
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
        vki.check_vk(c.vkCreateDescriptorSetLayout(device, &info, null, &layout)) catch @panic("Failed to create descriptor set layout");
        return layout;
    }
};

pub const DescriptorAllocator = struct {
    pub const PoolSizeRatio = struct {
        ratio: f32,
        type: c.VkDescriptorType,
    };

    pool: c.VkDescriptorPool = undefined,

    pub fn init_pool(self: *DescriptorAllocator, device: c.VkDevice, max_sets: u32, pool_ratios: []PoolSizeRatio, alloc: std.mem.Allocator ) void {
        var pool_sizes = std.ArrayList(c.VkDescriptorPoolSize).init(alloc);
        defer pool_sizes.deinit();
        for (pool_ratios) |ratio| {
            const size = c.VkDescriptorPoolSize{
                .type = ratio.type,
                .descriptorCount = max_sets * @as(u32, @intFromFloat(ratio.ratio)),
            };
            pool_sizes.append(size) catch @panic("Failed to append to pool_sizes");
        }

        const info = c.VkDescriptorPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .flags = 0,
            .maxSets = max_sets,
            .poolSizeCount = @as(u32, @intCast(pool_sizes.items.len)),
            .pPoolSizes = pool_sizes.items.ptr,
        };

        vki.check_vk(c.vkCreateDescriptorPool(device, &info, null, &self.pool)) catch @panic("Failed to create descriptor pool");
    }

    pub fn clear_descriptors(self: *DescriptorAllocator, device: c.VkDevice) void {
        _ = c.vkResetDescriptorPool(device, self.pool, 0);
    }

    pub fn destroy_pool(self: *DescriptorAllocator, device: c.VkDevice) void {
        _ = c.vkDestroyDescriptorPool(device, self.pool, null);
    }

    pub fn allocate(self: *DescriptorAllocator, device: c.VkDevice, layout: c.VkDescriptorSetLayout) c.VkDescriptorSet {
        const info = c.VkDescriptorSetAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext = null,
            .descriptorPool = self.pool,
            .descriptorSetCount = 1,
            .pSetLayouts = &layout,
        };
        var descriptor_set: c.VkDescriptorSet = undefined;
        vki.check_vk(c.vkAllocateDescriptorSets(device, &info, &descriptor_set)) catch @panic("Failed to allocate descriptor set");
        return descriptor_set;
    }
};
