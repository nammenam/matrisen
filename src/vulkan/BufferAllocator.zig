const std = @import("std");
const c = @import("../clibs/clibs.zig").libs;
const linalg = @import("../linalg.zig");
const debug = @import("debug.zig");
const Core = @import("Core.zig");
const AsyncContext = @import("AsyncContext.zig");
const Vec3 = linalg.Vec3(f32);
const Vec4 = linalg.Vec4(f32);
const Mat4x4 = linalg.Mat4x4(f32);

const Self = @This();

device: c.VkDevice,
gpuallocator: c.VmaAllocator,
allocationcallbacks: ?*c.VkAllocationCallbacks,

pub const AllocatedBuffer = struct {
    buffer: c.VkBuffer,
    allocation: c.VmaAllocation,
    info: c.VmaAllocationInfo,
};

pub fn init(device: c.VkDevice, gpuallocator: c.VmaAllocator, allocationcallbacks: ?*c.VkAllocationCallbacks) Self {
    return .{
        .device = device,
        .allocationcallbacks = allocationcallbacks,
        .gpuallocator = gpuallocator,
    };
}

pub fn flush(self: *Self, buffer: AllocatedBuffer, offset: c.VkDeviceSize, size: c.VkDeviceSize) void {
    debug.checkVkPanic(c.vmaFlushAllocation(self.gpuallocator, buffer.allocation, offset, size));
}

pub fn destroy(self: *Self, buffer: AllocatedBuffer) void {
    c.vmaDestroyBuffer(self.gpuallocator, buffer.buffer, buffer.allocation);
}

pub fn createIndirect(self: *Self, command_count: u32) AllocatedBuffer {
    const indirect_buffer = create(
        self,
        @sizeOf(c.VkDrawIndexedIndirectCommand) * command_count,
        c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_ONLY,
    );
    return indirect_buffer;
}

pub fn create(
    self: *Self,
    alloc_size: usize,
    usage: c.VkBufferUsageFlags,
    memory_usage: c.VmaMemoryUsage,
) AllocatedBuffer {
    const buffer_info: c.VkBufferCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = alloc_size,
        .usage = usage,
    };

    const vma_alloc_info: c.VmaAllocationCreateInfo = .{
        .usage = memory_usage,
        .flags = c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
    };

    var new_buffer: AllocatedBuffer = undefined;
    debug.checkVkPanic(c.vmaCreateBuffer(
        self.gpuallocator,
        &buffer_info,
        &vma_alloc_info,
        &new_buffer.buffer,
        &new_buffer.allocation,
        &new_buffer.info,
    ));
    return new_buffer;
}

pub fn createIndex(core: *Core, size: c.VkDeviceSize) AllocatedBuffer {
    const index_buffer = create(
        core,
        size,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    return index_buffer;
}

pub fn upload(core: *Core, data_slice: []const u8, buffer: AllocatedBuffer, dst_offset: c.VkDeviceSize) void {
    const size = data_slice.len;

    // Create staging buffer (CPU visible)
    const staging_buffer = create(
        &core.bufferallocator,
        size,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VMA_MEMORY_USAGE_CPU_ONLY,
    );
    defer c.vmaDestroyBuffer(core.gpuallocator, staging_buffer.buffer, staging_buffer.allocation);

    if (staging_buffer.info.pMappedData) |mapped_data_ptr| {
        const byte_data_ptr = @as([*]u8, @ptrCast(mapped_data_ptr));
        const staging_slice = byte_data_ptr[0..size];
        @memcpy(staging_slice, data_slice);
    } else {
        std.log.err("Failed to map staging buffer.", .{});
        @panic("");
    }

    // Copy from Staging to Giant Buffer at the correct offset
    core.asynccontext.submitBegin(core);
    const copy_region = c.VkBufferCopy{
        .srcOffset = 0,
        .dstOffset = dst_offset, // <--- Use the offset here!
        .size = size,
    };
    const cmd = core.asynccontext.commandbuffer;
    c.vkCmdCopyBuffer(cmd, staging_buffer.buffer, buffer.buffer, 1, &copy_region);
    core.asynccontext.submitEnd(core);
}

pub fn getBufferAddress(self: *Self, buffer: AllocatedBuffer) c.VkDeviceAddress {
    const deviceaddressinfo = c.VkBufferDeviceAddressInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        .pNext = null, // Always initialize pNext
        .buffer = buffer.buffer,
    };
    const adr = c.vkGetBufferDeviceAddress(self.device, &deviceaddressinfo);
    if (adr == 0) {
        std.log.err("Failed to get buffer device address for SSBO. Is the feature enabled?", .{});
        c.vmaDestroyBuffer(self.gpuallocator, buffer.buffer, buffer.allocation);
        @panic("");
    }
    return adr;
}
