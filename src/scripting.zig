const engine = @import("engine.zig");
const c = @import("clibs.zig");
const Vec4 = @import("3Dmath.zig").Vec4;

pub fn set_push_constant(l: ?*c.lua_State) callconv(.C) c_int {
    const self = @as(*engine, @alignCast(@ptrCast(c.lua_touserdata(l.?, c.lua_upvalueindex(1)))));
    const index = c.luaL_checkinteger(l.?, 1);
    const x = @as(f32, @floatCast(c.luaL_checknumber(l.?, 2)));
    const y = @as(f32, @floatCast(c.luaL_checknumber(l.?, 3)));
    const z = @as(f32, @floatCast(c.luaL_checknumber(l.?, 4)));
    const w = @as(f32, @floatCast(c.luaL_checknumber(l.?, 5)));
    const new_vec = Vec4{ .x = x, .y = y, .z = z, .w = w };

    switch (index) {
        1 => self.*.pc.data1 = new_vec,
        2 => self.*.pc.data2 = new_vec,
        3 => self.*.pc.data3 = new_vec,
        4 => self.*.pc.data4 = new_vec,
        else => return 0,
    }
    return 0;
}

pub fn register_lua_functions(self: *engine) void {
    const lua_fn: c.lua_CFunction = &set_push_constant;
    c.lua_pushlightuserdata(self.lua_state, self);
    c.lua_pushcclosure(self.lua_state, lua_fn, 1);
    c.lua_setglobal(self.lua_state, "set_push_constant");
}
