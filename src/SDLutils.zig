const e = @import("vkEngine.zig");
const c = @import("clibs.zig");




pub fn handle_key_up(engine:*e, key_event: c.SDL_KeyboardEvent) void {
    switch (key_event.key) {
        c.SDLK_UP => {
            engine.pc.data1.x += 0.1;
        },
        c.SDLK_DOWN => {
            engine.pc.data1.x -= 0.1;
        },
        else => {}
    }
}

pub fn handle_key_down(engine:*e, key_event: c.SDL_KeyboardEvent) void {
    switch (key_event.key) {
        c.SDLK_UP => {
            engine.pc.data1.w += 0.0;
        },
        else => {}
    }
}
