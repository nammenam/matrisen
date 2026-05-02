const std = @import("std");
const Window = @import("Window.zig");
const Quat = @import("linalg.zig").Quat(f32);
const Vec3 = @import("linalg.zig").Vec3(f32);

const Self = @This();

orientation: Quat,
position: Vec3,
pivot: Vec3, // same as position for first person
distance: f32, // 0 if first person

pub const init: Self = .{
    .orientation = .identity,
    .position = .unit_z,
    .pivot = .unit_z,
    .distance = 0.0,
};

pub fn firstPerson(self: *Self, window: *Window) void {
    if (window.state.w) self.pivot.translateForward(&self.orientation, 0.1);
    if (window.state.s) self.pivot.translateForward(&self.orientation, -0.1);
    if (window.state.a) self.pivot.translatePitch(&self.orientation, -0.1);
    if (window.state.d) self.pivot.translatePitch(&self.orientation, 0.1);
    if (window.state.q) self.pivot.translateWorldZ(-0.1);
    if (window.state.e) self.pivot.translateWorldZ(0.1);
    if (window.state.capturemouse) {
        self.orientation.rotatePitch(-window.state.mouse_y / 150);
        self.orientation.rotateWorldZ(-window.state.mouse_x / 150);
    }
    self.position = self.pivot;
}

pub fn orbit(self: *Self, window: *Window) void {
    if (window.state.w) self.pivot.translateForward(&self.orientation, 0.1);
    if (window.state.s) self.pivot.translateForward(&self.orientation, -0.1);
    if (window.state.a) self.pivot.translatePitch(&self.orientation, -0.1);
    if (window.state.d) self.pivot.translatePitch(&self.orientation, 0.1);
    if (window.state.q) self.pivot.translateWorldZ(-0.1);
    if (window.state.e) self.pivot.translateWorldZ(0.1);
    if (window.state.capturemouse) {
        self.orientation.rotatePitch(-window.state.mouse_y / 150);
        self.orientation.rotateWorldZ(-window.state.mouse_x / 150);
    }
    const local_offset = Vec3{ .x = 0.0, .y = 0.0, .z = -self.distance };
    self.position = self.orientation.rotateVec3(local_offset).add(self.pivot);
}
