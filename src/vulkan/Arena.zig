const std = @import("std");
const c = @import("c");
const errors = @import("errors.zig");
const ResourceManager = @import("ResourceManager.zig");
const AllocatedBuffer = ResourceManager.AllocatedBuffer;
const BumpAllocator = @import("BumpAllocator.zig").BumpAllocator;

pub const Arena = struct {
    buffer: AllocatedBuffer,
    root_device_address: u64,
    allocator: BumpAllocator,

    pub fn init(buffer: AllocatedBuffer, root_device_address: u64, start: u32, capacity_bytes: u32) Arena {
        return .{
            .buffer = buffer,
            .root_device_address = root_device_address,
            .allocator = BumpAllocator.init(start, capacity_bytes),
        };
    }

    pub fn subAllocateArena(self: *Arena, capacity_bytes: u32) !Arena {
        const abs_offset = try self.allocate(capacity_bytes);
        return Arena.init(
            self.buffer,
            self.root_device_address,
            abs_offset,
            capacity_bytes,
        );
    }

    pub fn allocate(self: *Arena, size: u32) !u32 {
        return self.allocator.allocate(size);
    }

    pub fn allocateType(self: *Arena, comptime T: type, count: u32) !u32 {
        return self.allocate(@intCast(@sizeOf(T) * count));
    }

    pub fn getAddress(self: *const Arena, abs_offset: u32) u64 {
        return self.root_device_address + abs_offset;
    }

    pub fn reset(self: *Arena) void {
        self.allocator.reset();
    }
};
