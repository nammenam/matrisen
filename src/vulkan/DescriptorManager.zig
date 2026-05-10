const std = @import("std");
const c = @import("c");
const Core = @import("Core.zig");
const DescriptorAllocator = @import("DescriptorAllocator.zig");
const Device = @import("Device.zig");
const PipelineManager = @import("PipelineManager.zig");
const DescriptorWriter = @import("DescriptorWriter.zig");
const BufferManager = @import("BufferManager.zig");

const Self = @This();

device: c.VkDevice,
allocators: [Core.multibuffering]DescriptorAllocator,
sets: [Core.multibuffering]c.VkDescriptorSet,

pub fn init(allocator: std.mem.Allocator, device: c.VkDevice, pipelinemanager: PipelineManager) Self {
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
    return .{
        .allocators = allocators,
        .sets = sets,
        .device = device,
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    for (&self.allocators) |*dynamicallocator| dynamicallocator.deinit(self.device, alloc);
}

// pub fn writeStaticSet(
//     self: *Self,
//     meshbuffer: BufferManager.AllocatedBuffer, // Binding 0
//     instancebuffer: BufferManager.AllocatedBuffer, // Binding 1
// ) void {
//     var writer = DescriptorWriter.init();
//     defer writer.deinit(self.allocator);
//     writer.writeBuffer(
//         self.allocator, // Use the passed allocator, not self.cpuallocator (unless intentional)
//         0, // Binding Index
//         meshbuffer.buffer,
//         c.VK_WHOLE_SIZE,
//         0, // Offset
//         c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
//     );

//     writer.writeBuffer(
//         self.allocator,
//         1, // Binding Index
//         instancebuffer.buffer,
//         c.VK_WHOLE_SIZE,
//         0,
//         c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
//     );
//     writer.updateSet(self.device, self.staticset);
// }

pub fn writeDynamicSet(
    self: *Self,
    alloc: std.mem.Allocator,
    data: BufferManager.AllocatedBuffer,
    frame: u8,
) void {
    var writer = DescriptorWriter.init();
    defer writer.deinit(alloc);
    writer.writeBuffer(
        alloc,
        0,
        data.buffer,
        @sizeOf(BufferManager.SceneData),
        0,
        c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    );
    writer.updateSet(self.device, self.sets[frame]);
}
