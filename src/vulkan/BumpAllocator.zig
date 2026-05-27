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

    /// Allocates `size` bytes. Returns the absolute byte offset of the allocation.
    pub fn allocate(self: *BumpAllocator, size: u32) !u32 {
        if (self.current + size > self.end) {
            std.log.err(
                "BumpAllocator OOM: current={} size={} end={}",
                .{ self.current, size, self.end },
            );
            return error.OutOfMemory;
        }
        const allocated = self.current;
        self.current += size;
        return allocated;
    }

    pub fn usedBytes(self: *const BumpAllocator) u32 {
        return self.current - self.start;
    }

    pub fn capacityBytes(self: *const BumpAllocator) u32 {
        return self.end - self.start;
    }

    pub fn reset(self: *BumpAllocator) void {
        self.current = self.start;
    }
};
