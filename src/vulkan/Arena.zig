const std = @import("std");
const c = @import("c");
const ResourceManager = @import("ResourceManager.zig");
const AllocatedBuffer = ResourceManager.AllocatedBuffer;
const BumpAllocator = @import("BumpAllocator.zig").BumpAllocator;

// TODO add typed handles for u32 and stuff Meshidx = enum(u32) { _ } or Meshidx = u32
// to make compiler handles misuse of indexes

/// An Arena is a sub-range of a GPU buffer.
///
/// Two flavours:
///
///   1. Single-buffered  (frames == 1)
///      Plain bump allocator over a contiguous region.
///
///   2. Multi-buffered   (frames > 1)
///      The region is split into `frames` equal slots of `slot_stride` bytes.
///      `allocator` only walks over ONE slot's worth of bytes.
///      The layout inside the buffer is:
///
///        [ frame-0 slot_stride bytes ][ frame-1 slot_stride bytes ] ...
///
/// All child arenas carved from a root arena inherit `buffer_base_address`,
/// which is the vkGetBufferDeviceAddress result for the underlying VkBuffer.
/// This lets any arena compute a raw VkBuffer byte offset at any time without
/// needing to pass the buffer base around externally.
pub const Arena = struct {
    buffer: AllocatedBuffer,

    /// Device address of byte 0 of the underlying VkBuffer.
    /// Identical for every arena carved from the same buffer.
    /// Set once in the 5 root arenas; propagated to all children.
    buffer_base_address: u64,

    /// Device address of the start of THIS arena's frame-0 region.
    ///   = buffer_base_address + byte offset of this arena within the buffer.
    root_device_address: u64,

    /// Bump allocator that walks within ONE frame's slot (start is always 0).
    allocator: BumpAllocator,

    /// Capacity of a single frame's region in bytes.
    /// For single-buffered arenas this equals the total capacity.
    slot_stride: u32,

    /// Number of buffered frames (1 = single-buffered).
    frames: u32,

    // ------------------------------------------------------------------ //
    // Construction
    // ------------------------------------------------------------------ //

    /// Used by ResourceManager for the 5 root arenas that each own a VkBuffer.
    /// `buffer_base` is vkGetBufferDeviceAddress (0 for CPU-only buffers like readback).
    pub fn init(
        buffer: AllocatedBuffer,
        buffer_base: u64,
        capacity_bytes: u32,
    ) Arena {
        return .{
            .buffer = buffer,
            .buffer_base_address = buffer_base,
            .root_device_address = buffer_base, // root starts at byte 0
            .allocator = BumpAllocator.init(0, capacity_bytes),
            .slot_stride = capacity_bytes,
            .frames = 1,
        };
    }

    /// Carve out a single-buffered child arena of `capacity_bytes`.
    pub fn subAllocateArena(self: *Arena, capacity_bytes: u32) !Arena {
        const offset = try self.allocator.allocate(capacity_bytes);
        return .{
            .buffer = self.buffer,
            .buffer_base_address = self.buffer_base_address,
            .root_device_address = self.root_device_address + offset,
            .allocator = BumpAllocator.init(0, capacity_bytes),
            .slot_stride = capacity_bytes,
            .frames = 1,
        };
    }

    /// Carve out a typed, multi-buffered child arena.
    ///
    /// `max_elements` — capacity per frame.
    /// Total bytes reserved from parent: @sizeOf(T) * max_elements * frame_count.
    ///
    /// Example:
    ///   self.meshinstance_arena = try dynamic_gpu_arena
    ///       .subAllocateArenaTyped(MeshInstance, MAX_OBJECTS, 2);
    pub fn subAllocateArenaTyped(
        self: *Arena,
        comptime T: type,
        max_elements: u32,
        frame_count: u32,
    ) !Arena {
        const stride = @sizeOf(T) * max_elements;
        const total = stride * frame_count;
        const offset = try self.allocator.allocate(total);
        return .{
            .buffer = self.buffer,
            .buffer_base_address = self.buffer_base_address,
            .root_device_address = self.root_device_address + offset,
            .allocator = BumpAllocator.init(0, stride), // walks one frame only
            .slot_stride = stride,
            .frames = frame_count,
        };
    }

    // ------------------------------------------------------------------ //
    // Allocation
    // ------------------------------------------------------------------ //

    /// Allocate `size` raw bytes. Returns byte offset from this arena's base.
    pub fn allocate(self: *Arena, size: u32) !u32 {
        return self.allocator.allocate(size);
    }

    /// Allocate `count` values of type T.
    /// Returns a 0-based slot index (element index, NOT bytes).
    /// Pass this to getAddressForFrame / getBufferOffsetForFrame.
    pub fn allocateTyped(self: *Arena, comptime T: type, count: u32) !u32 {
        const byte_offset = try self.allocator.allocate(@sizeOf(T) * count);
        return byte_offset / @sizeOf(T);
    }

    /// Number of T elements allocated so far within one frame's slot.
    pub fn countAllocated(self: *const Arena, comptime T: type) u32 {
        return self.allocator.usedBytes() / @sizeOf(T);
    }

    // ------------------------------------------------------------------ //
    // Address helpers
    // ------------------------------------------------------------------ //

    /// GPU device address for a raw byte offset from this arena's base (frame 0).
    pub fn getAddress(self: *const Arena, byte_offset: u32) u64 {
        return self.root_device_address + byte_offset;
    }

    /// GPU device address for element `slot_index` in frame `frame_index`.
    ///
    ///   addr = root_device_address        <- frame-0 base of this arena
    ///        + frame_index * slot_stride  <- jump to the right frame
    ///        + slot_index * @sizeOf(T)    <- jump to the element
    pub fn getFrameAddress(
        self: *const Arena,
        comptime T: type,
        slot_index: usize,
        frame_index: usize,
    ) u64 {
        std.debug.assert(frame_index < self.frames);
        return self.root_device_address + frame_index * self.slot_stride + slot_index * @sizeOf(T);
    }

    /// Raw VkBuffer byte offset for element `slot_index` in frame `frame_index`.
    /// Use this for VkBufferCopy.dstOffset etc.
    ///
    ///   vkbuffer_offset = getAddressForFrame(...) - buffer_base_address
    pub fn getBufferOffsetForFrame(
        self: *const Arena,
        comptime T: type,
        slot_index: usize,
        frame_index: usize,
    ) u64 {
        std.debug.assert(frame_index < self.frames);
        return self.getFrameAddress(T, slot_index, frame_index) - self.buffer_base_address;
    }

    /// GPU address of the very start of frame `frame_index`.
    /// Feed directly into SceneData.addresses fields.
    pub fn getFrameBaseAddress(self: *const Arena, frame_index: usize) u64 {
        std.debug.assert(frame_index < self.frames);
        return self.root_device_address + frame_index * self.slot_stride;
    }

    // ------------------------------------------------------------------ //
    // Lifecycle
    // ------------------------------------------------------------------ //

    pub fn reset(self: *Arena) void {
        self.allocator.reset();
    }
};
