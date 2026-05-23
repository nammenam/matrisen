const std = @import("std");
const c = @import("c");
const errors = @import("errors.zig");
const ResourceManager = @import("ResourceManager.zig");
const AllocatedBuffer = ResourceManager.AllocatedBuffer;
const BumpAllocator = @import("BumpAllocator.zig").BumpAllocator;

pub const Arena = struct {
    buffer: AllocatedBuffer,
    base_offset: u32,
    device_address: u64,
    allocator: BumpAllocator,

    pub fn init(buffer: AllocatedBuffer, base_offset: u32, device_address: u64, capacity_bytes: u32) Arena {
        return .{
            .buffer = buffer,
            .base_offset = base_offset,
            .device_address = device_address,
            .allocator = BumpAllocator.init(capacity_bytes),
        };
    }

    pub fn subAllocateArena(self: *Arena, capacity_bytes: u32) !Arena {
        const offset = try self.allocate(capacity_bytes);
        return Arena.init(
            self.buffer,
            self.base_offset + offset,
            self.device_address + offset,
            capacity_bytes,
        );
    }

    pub fn allocate(self: *Arena, size: u32) !u32 {
        return self.allocator.allocate(size);
    }

    pub fn allocateType(self: *Arena, comptime T: type, count: u32) !u32 {
        return self.allocate(@intCast(@sizeOf(T) * count));
    }

    pub fn getAddress(self: *const Arena, offset: u32) u64 {
        return self.device_address + offset;
    }

    pub fn reset(self: *Arena) void {
        self.allocator.reset();
    }
};
