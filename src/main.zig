const std = @import("std");

const VulkanEngine = @import("vkEngine.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        @panic("Leaked memory");
    };

    var cwd_buff: [1024]u8 = undefined;
    const cwd = std.process.getCwd(&cwd_buff) catch |err| {
        std.debug.print("Unable to get current working directory: {}\n", .{err});
        return err;
    };

    std.log.info("Running from: {s} with PID: {!}\n", .{ cwd, std.os.linux.getpid() });

    var engine = VulkanEngine.init(gpa.allocator());
    defer engine.cleanup();

    engine.run();
}
