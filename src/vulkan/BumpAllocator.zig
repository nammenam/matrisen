const std = @import("std");

pub const BumpAllocator = struct {
    offset: u32 = 0,
    capacity: u32,

    pub fn init(capacity: u32) BumpAllocator {
        return .{
            .capacity = capacity,
        };
    }

    pub fn allocate(self: *BumpAllocator, size: u32) !u32 {
        if (self.offset + size > self.capacity) {
            return error.OutOfMemory;
        }
        const current = self.offset;
        self.offset += size;
        return current;
    }

    pub fn reset(self: *BumpAllocator) void {
        self.offset = 0;
    }
};
