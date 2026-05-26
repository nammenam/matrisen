const std = @import("std");

pub const BumpAllocator = struct {
    start: u32,
    end: u32,
    current: u32,

    pub fn init(start: u32, capacity: u32) BumpAllocator {
        return .{
            .start = start,
            .end = start + capacity,
            .current = start,
        };
    }

    pub fn allocate(self: *BumpAllocator, size: u32) !u32 {
        if (self.current + size > self.end) {
            return error.OutOfMemory;
        }
        const allocated = self.current;
        self.current += size;
        return allocated;
    }

    pub fn reset(self: *BumpAllocator) void {
        self.current = self.start;
    }
};
