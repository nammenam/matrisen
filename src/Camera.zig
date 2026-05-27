// ┌──────────────────────────────────────────────────────────────────────────────┐
// │  World coordinate system is righthanded z up                                 │
// │  Camera local coordinate system is righthanded y up                          │
// │                                                                              │
// │                                                                              │
// │                                                                              │
// │                                                                              │
// │                                                                              │
// │                                                                              │
// └──────────────────────────────────────────────────────────────────────────────┘

const std = @import("std");
const Window = @import("Window.zig");
const Quat = @import("math/Quat.zig").Quat(f32);
const Mat4x4 = @import("math/Mat.zig").Mat4x4(f32);
const Vec3 = @import("math/Vec.zig").Vec3(f32);

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
    if (window.state.w) self.pivot.translateForward(&self.orientation, -0.1);
    if (window.state.s) self.pivot.translateForward(&self.orientation, 0.1);
    if (window.state.a) self.pivot.translatePitch(&self.orientation, -0.1);
    if (window.state.d) self.pivot.translatePitch(&self.orientation, 0.1);
    if (window.state.q) self.pivot.translateWorldZ(-0.1);
    if (window.state.e) self.pivot.translateWorldZ(0.1);
    if (window.state.capturemouse) {
        self.orientation.rotatePitch(window.state.mouse_y / 150);
        self.orientation.rotateWorldZ(window.state.mouse_x / 150);
    }
    self.position = self.pivot;
}

pub fn orbit(self: *Self, window: *Window) void {
    if (window.state.w) self.pivot.translateForward(&self.orientation, -0.1);
    if (window.state.s) self.pivot.translateForward(&self.orientation, 0.1);
    if (window.state.a) self.pivot.translatePitch(&self.orientation, -0.1);
    if (window.state.d) self.pivot.translatePitch(&self.orientation, 0.1);
    if (window.state.q) self.pivot.translateWorldZ(-0.1);
    if (window.state.e) self.pivot.translateWorldZ(0.1);
    if (window.state.capturemouse) {
        self.orientation.rotatePitch(window.state.mouse_y / 150);
        self.orientation.rotateWorldZ(window.state.mouse_x / 150);
    }
    const local_offset = Vec3{ .x = 0.0, .y = 0.0, .z = self.distance };
    self.position = self.orientation.rotateVec3(local_offset).add(self.pivot);
}

/// The result matrix maps a Right-Handed, Y-Up view space (looking down -Z)
/// to a Zero-to-One clipping space.
/// near, far and fov creates the "box" that we can see, anything outside will
/// be cut off in the rendering (hidden inside the gpu)
pub fn perspective(fovy_rad: f32, aspect: f32, near: f32, far: f32) Mat4x4 {
    const y = 1.0 / @tan(fovy_rad / 2.0); // 90 deg fov -> y ~= 1 => no distortion
    const x = y / aspect; // x is longer than y. Needs to be square
    const z = -far / (far - near); // normalize: [near, far] -> [0, 1]
    const w = -(far * near) / (far - near); // z offset?
    return .new(
        .new(x, 0, 0, 0),
        .new(0, y, 0, 0),
        .new(0, 0, z, w),
        .new(0, 0, -1, 0), // w = -z (becomes perspective divide later in gpu)
    );
}

/// The result matrix maps a Right-Handed, Y-Up view space (looking down -Z)
/// to a Zero-to-One clipping space.
pub fn orthographic(ortho_height: f32, aspect: f32, near: f32, far: f32) Mat4x4 {
    const y = 2.0 / ortho_height;
    const x = 2.0 / (ortho_height * aspect);
    const z = -1.0 / (far - near); // Maps -Z to [0, 1]
    const w = -near / (far - near); // ?
    return .new(
        .new(x, 0, 0, 0),
        .new(0, y, 0, 0),
        .new(0, 0, z, w),
        .new(0, 0, 0, 1), // Ortho has no perspective divide
    );
}

pub fn view(cam: Self) Mat4x4 {
    const rotation = cam.orientation.inverse().toMat4x4();
    const translation = Mat4x4.translation(.{
        .x = -cam.position.x,
        .y = -cam.position.y,
        .z = -cam.position.z,
    });
    return rotation.mul(translation);
}
