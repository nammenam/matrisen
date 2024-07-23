const std = @import("std");
const Engine = @import("engine.zig");
const lua = @import("scripting.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        @panic("Leaked memory");
    };

    var engine = Engine.init(gpa.allocator());
    defer engine.cleanup();

    lua.register_lua_functions(&engine); // This must be called after the engine is initialized for &engine to be correct
    engine.run();
}
