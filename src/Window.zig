const c = @import("c");
const std = @import("std");
const log = std.log.scoped(.window);
const Core = @import("vulkan/Core.zig");
const Instance = @import("vulkan/Instance.zig");

const Self = @This();

handle: *c.SDL_Window,
state: State = .{},

pub fn init(width: u32, height: u32) Self {
    checkSdl(c.SDL_Init(c.SDL_INIT_VIDEO));
    const flags = c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_UTILITY;
    const window = c.SDL_CreateWindow("matrisen", @intCast(width), @intCast(height), flags) orelse {
        @panic("Failed to create SDL window");
    };
    checkSdl(c.SDL_ShowWindow(window));
    return .{ .handle = window };
}

pub fn deinit(self: *Self) void {
    c.SDL_DestroyWindow(self.handle);
    c.SDL_Quit();
}

pub fn createSurface(
    self: *Self,
    instance: Instance,
    alloc_callbacks: ?*c.VkAllocationCallbacks,
) c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;
    checkSdl(c.SDL_Vulkan_CreateSurface(
        self.handle,
        instance.handle,
        alloc_callbacks,
        &surface,
    ));
    log.info("created surface", .{});
    return surface;
}

pub fn getSize(self: *Self, width: *u32, height: *u32) void {
    var w: c_int = undefined;
    var h: c_int = undefined;
    checkSdl(c.SDL_GetWindowSize(self.handle, &w, &h));
    width.* = @intCast(w);
    height.* = @intCast(h);
}

pub const State = packed struct {
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    w: bool = false,
    s: bool = false,
    a: bool = false,
    d: bool = false,
    q: bool = false,
    e: bool = false,
    tab: bool = false,
    quit: bool = false,
    capturemouse: bool = false,
    resizerequest: bool = false,
};

pub fn processInput(self: *Self) void {
    var event: c.SDL_Event = undefined;
    self.state.mouse_x = 0;
    self.state.mouse_y = 0;
    while (c.SDL_PollEvent(&event) == true) {
        switch (event.type) {
            c.SDL_EVENT_QUIT => {
                self.state.quit = true;
            },
            c.SDL_EVENT_KEY_DOWN => {
                switch (event.key.scancode) {
                    c.SDL_SCANCODE_W => self.state.w = true,
                    c.SDL_SCANCODE_S => self.state.s = true,
                    c.SDL_SCANCODE_A => self.state.a = true,
                    c.SDL_SCANCODE_D => self.state.d = true,
                    c.SDL_SCANCODE_Q => self.state.q = true,
                    c.SDL_SCANCODE_E => self.state.e = true,
                    c.SDL_SCANCODE_TAB => {
                        toggleMouseCapture(self);
                    },
                    else => {},
                }
            },
            c.SDL_EVENT_KEY_UP => {
                switch (event.key.scancode) {
                    c.SDL_SCANCODE_W => self.state.w = false,
                    c.SDL_SCANCODE_S => self.state.s = false,
                    c.SDL_SCANCODE_A => self.state.a = false,
                    c.SDL_SCANCODE_D => self.state.d = false,
                    c.SDL_SCANCODE_Q => self.state.q = false,
                    c.SDL_SCANCODE_E => self.state.e = false,
                    c.SDL_SCANCODE_TAB => {},
                    else => {},
                }
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                self.state.mouse_x = event.motion.xrel;
                self.state.mouse_y = event.motion.yrel;
            },
            c.SDL_EVENT_WINDOW_RESIZED => {
                self.state.resizerequest = true;
            },
            else => {},
        }
    }
}

pub fn toggleMouseCapture(self: *Self) void {
    self.state.capturemouse = !self.state.capturemouse;
    checkSdl(c.SDL_SetWindowRelativeMouseMode(self.handle, self.state.capturemouse));
}

pub fn checkSdl(res: bool) void {
    if (res != true) {
        std.log.err("Detected SDL error: {s}", .{c.SDL_GetError()});
        @panic("SDL error");
    }
}
