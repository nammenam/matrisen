const std = @import("std");
const VulkanEngine = @import("vkEngine.zig");
const lua = @import("scripting.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        @panic("Leaked memory");
    };

    var engine = VulkanEngine.init(gpa.allocator());
    defer engine.cleanup();

    lua.register_lua_functions(&engine); // This must be called after the engine is initialized for &engine to be correct
    engine.run();
}
