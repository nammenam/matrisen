const c = @import("clibs.zig");
const engine = @import("engine.zig");
const std = @import("std");

pub const WindowManager = struct {
    window: *c.SDL_Window,
    surface: c.VkSurfaceKHR,

    pub fn init(window_extent: c.VkExtent2D) !WindowManager {
        check_sdl(c.SDL_Init(c.SDL_INIT_VIDEO));
        const window = c.SDL_CreateWindow("matrisen", @intCast(window_extent.width), @intCast(window_extent.height), c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_UTILITY) orelse @panic("Failed to create SDL window");
        _ = c.SDL_ShowWindow(window);
        return .{ .window = window, .surface = undefined };
    }

    pub fn deinit(self: *WindowManager) void {
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    pub fn create_surface(self: *WindowManager, e: *engine) void {
        check_sdl(c.SDL_Vulkan_CreateSurface(self.window, e.instance, engine.vk_alloc_cbs, &self.surface));
    }
};

// pub const HeadlessRenderer = struct {
//     image: c.VkImage,
//     // Other necessary fields...
//
//     pub fn init(width: u32, height: u32) !HeadlessRenderer {
//         // Create VkImage for rendering
//     }
//
//     pub fn deinit(self: *HeadlessRenderer) void {
//         // Clean up resources
//     }
//
//     pub fn getRenderTarget(self: *HeadlessRenderer) RenderTarget {
//         return RenderTarget{ .image = &self.image };
//     }
// };

pub fn check_sdl(res: c_int) void {
    if (res != 0) {
        std.log.err("Detected SDL error: {s}", .{c.SDL_GetError()});
        @panic("SDL error");
    }
}

fn check_sdl_bool(res: c.SDL_bool) void {
    if (res != c.SDL_TRUE) {
        std.log.err("Detected SDL error: {s}", .{c.SDL_GetError()});
        @panic("SDL error");
    }
}
