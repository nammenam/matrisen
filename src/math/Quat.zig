const std = @import("std");
const assert = std.debug.assert;
const Vec3 = @import("Vec.zig").Vec3;
const Mat4x4 = @import("Mat.zig").Mat4x4;
const printContainer = @import("printContainer.zig").printContainer;

pub fn Quat(comptime T: type) type {
    if (@typeInfo(T) != .float) @compileError("Quaternion must be of type float");

    return extern struct {
        w: T,
        x: T,
        y: T,
        z: T,

        const Self = @This();
        pub const identity: Self = .{ .w = 1, .x = 0, .y = 0, .z = 0 };
        pub const zeros: Self = .{ .w = 0, .x = 0, .y = 0, .z = 0 };

        pub fn new(x: T, y: T, z: T, w: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = w };
        }

        pub fn aroundAxis(axis: Vec3(T), angle: T) Self {
            assert(axis.isNormalized());
            const half_angle = angle / 2.0;
            const sin = @sin(half_angle);
            const cos = @cos(half_angle);
            return .{
                .x = axis.x * sin,
                .y = axis.y * sin,
                .z = axis.z * sin,
                .w = cos,
            };
        }

        pub fn add(self: Self, other: Self) Self {
            return .{
                .x = self.x + other.x,
                .y = self.y + other.y,
                .z = self.z + other.z,
                .w = self.w + other.w,
            };
        }

        pub fn scalarMul(self: Self, scalar: T) Self {
            return .{
                .x = self.x * scalar,
                .y = self.y * scalar,
                .z = self.z * scalar,
                .w = self.w * scalar,
            };
        }

        pub fn mul(self: Self, other: Self) Self {
            // Note: Does not assert normalized to allow dual quat math.
            const result: Self = .{
                .x = self.w * other.x + self.x * other.w + self.y * other.z - self.z * other.y,
                .y = self.w * other.y - self.x * other.z + self.y * other.w + self.z * other.x,
                .z = self.w * other.z + self.x * other.y - self.y * other.x + self.z * other.w,
                .w = self.w * other.w - self.x * other.x - self.y * other.y - self.z * other.z,
            };
            return result;
        }

        pub fn rotateVec3(self: Self, v: Vec3(T)) Vec3(T) {
            const w = self.w;
            const r: Vec3(T) = .{ .x = self.x, .y = self.y, .z = self.z };
            const t = r.cross(v).scalarMul(2.0);
            return v.add(t.scalarMul(w)).add(r.cross(t));
        }

        pub fn inverse(self: Self) Self {
            assert(self.isNormalized());
            return self.conjugate();
        }

        pub fn conjugate(self: Self) Self {
            return .{ .x = -self.x, .y = -self.y, .z = -self.z, .w = self.w };
        }

        pub fn dot(self: Self, other: Self) T {
            return self.x * other.x + self.y * other.y + self.z * other.z + self.w * other.w;
        }

        pub fn normalized(self: Self) Self {
            const reciprocal = 1.0 / self.norm();
            assert(reciprocal > 0.0);
            return .{
                .x = self.x * reciprocal,
                .y = self.y * reciprocal,
                .z = self.z * reciprocal,
                .w = self.w * reciprocal,
            };
        }

        pub fn isNormalized(self: Self) bool {
            return @abs(self.squaredNorm() - 1.0) <= 1e-4;
        }

        pub fn squaredNorm(self: Self) T {
            return self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w;
        }

        pub fn norm(self: Self) T {
            return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w);
        }

        pub fn toMat4x4(self: Self) Mat4x4(T) {
            assert(self.isNormalized());

            const w = self.w;
            const x = self.x;
            const y = self.y;
            const z = self.z;
            return .{ .x = .{
                .x = 1 - 2 * y * y - 2 * z * z,
                .y = 2 * x * y + 2 * w * z,
                .z = 2 * x * z - 2 * w * y,
                .w = 0,
            }, .y = .{
                .x = 2 * x * y - 2 * w * z,
                .y = 1 - 2 * x * x - 2 * z * z,
                .z = 2 * y * z + 2 * w * x,
                .w = 0,
            }, .z = .{
                .x = 2 * x * z + 2 * w * y,
                .y = 2 * y * z - 2 * w * x,
                .z = 1 - 2 * x * x - 2 * y * y,
                .w = 0,
            }, .w = .{
                .x = 0,
                .y = 0,
                .z = 0,
                .w = 1,
            } };
        }

        pub fn toAffine(rot: Self, pos: Vec3(T)) Mat4x4(T) {
            const rotation = rot.toMat4x4();
            const translation = Mat4x4(T).translation(.{
                .x = pos.x,
                .y = pos.y,
                .z = pos.z,
            });
            return translation.mul(rotation);
        }

        pub fn eulerAngles(self: Self) Vec3(T) {
            const pitch = std.math.atan2(
                2 * (self.w * self.x + self.y * self.z),
                1 - 2 * (self.x * self.x + self.y * self.y),
            );
            const roll = std.math.asin(2 * (self.w * self.y - self.x * self.z));
            const yaw = std.math.atan2(
                2 * (self.w * self.z + self.x * self.y),
                1 - 2 * (self.y * self.y + self.z * self.z),
            );
            return .{ .x = pitch, .y = roll, .z = yaw };
        }

        pub fn pitchAxis(self: *const Self) Vec3(T) {
            return self.rotateVec3(Vec3(T).unit_x);
        }

        pub fn yawAxis(self: *const Self) Vec3(T) {
            return self.rotateVec3(Vec3(T).unit_y);
        }

        pub fn rollAxis(self: *const Self) Vec3(T) {
            return self.rotateVec3(Vec3(T).unit_z);
        }

        pub fn rotatePitch(self: *Self, angle: T) void {
            const rotation = Quat(T).aroundAxis(Vec3(T).unit_x, angle);
            self.* = self.mul(rotation).normalized();
        }

        pub fn rotateYaw(self: *Self, angle: T) void {
            const rotation = Quat(T).aroundAxis(Vec3(T).unit_y, angle);
            self.* = self.mul(rotation).normalized();
        }

        pub fn rotateRoll(self: *Self, angle: T) void {
            const rotation = Quat(T).aroundAxis(Vec3(T).unit_z, angle);
            self.* = self.mul(rotation).normalized();
        }

        pub fn rotateWorldX(self: *Self, angle: T) void {
            const rotation = Quat(T).aroundAxis(Vec3(T).unit_x, angle);
            self.* = rotation.mul(self.*).normalized();
        }

        pub fn rotateWorldY(self: *Self, angle: T) void {
            const rotation = Quat(T).aroundAxis(Vec3(T).unit_y, angle);
            self.* = rotation.mul(self.*).normalized();
        }

        pub fn rotateWorldZ(self: *Self, angle: T) void {
            const rotation = Quat(T).aroundAxis(Vec3(T).unit_z, angle);
            self.* = rotation.mul(self.*).normalized();
        }

        pub fn rotateWorld(self: *Self, axis: Vec3(T), angle: T) void {
            const rotation = Quat(T).aroundAxis(axis, angle);
            self.* = rotation.mul(self.*).normalized();
        }

        pub fn rotateLocal(self: *Self, axis: Vec3(T), angle: T) void {
            const rotation = Quat(T).aroundAxis(axis, angle);
            self.* = self.mul(rotation).normalized();
        }

        pub fn print(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try printContainer(self, T, 4, 1, fmt, options, writer);
        }
    };
}

pub fn DualQuat(comptime T: type) type {
    if (@typeInfo(T) != .float) @compileError("DualQuaternion must be of type float");

    return extern struct {
        real: Quat(T),
        dual: Quat(T),

        const Self = @This();

        pub const identity: Self = .{
            .real = Quat(T).identity,
            .dual = Quat(T).zeros,
        };

        pub fn new(real: Quat(T), dual: Quat(T)) Self {
            return .{ .real = real, .dual = dual };
        }

        pub fn fromTranslationRotation(translation: Vec3(T), rotation: Quat(T)) Self {
            const t_quat = Quat(T).new(translation.x, translation.y, translation.z, 0.0);
            return .{
                .real = rotation,
                .dual = t_quat.mul(rotation).scalarMul(0.5),
            };
        }

        pub fn add(self: Self, other: Self) Self {
            return .{
                .real = self.real.add(other.real),
                .dual = self.dual.add(other.dual),
            };
        }

        pub fn mul(self: Self, other: Self) Self {
            return .{
                .real = self.real.mul(other.real),
                .dual = self.real.mul(other.dual).add(self.dual.mul(other.real)),
            };
        }

        pub fn conjugate(self: Self) Self {
            return .{ .real = self.real.conjugate(), .dual = self.dual.conjugate() };
        }

        pub fn normalized(self: Self) Self {
            const mag = self.real.norm();
            assert(mag > 0.0);
            const reciprocal = 1.0 / mag;
            return .{
                .real = self.real.scalarMul(reciprocal),
                .dual = self.dual.scalarMul(reciprocal),
            };
        }

        pub fn getTranslation(self: Self) Vec3(T) {
            const t_quat = self.dual.scalarMul(2.0).mul(self.real.conjugate());
            return .{ .x = t_quat.x, .y = t_quat.y, .z = t_quat.z };
        }

        pub fn getRotation(self: Self) Quat(T) {
            return self.real;
        }

        pub fn transformPoint(self: Self, p: Vec3(T)) Vec3(T) {
            return self.getRotation().rotateVec3(p).add(self.getTranslation());
        }

        pub fn toMat4x4(self: Self) Mat4x4(T) {
            const norm_dq = self.normalized();
            return Quat(T).toAffine(norm_dq.getRotation(), norm_dq.getTranslation());
        }

        pub fn print(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try printContainer(self, T, 8, 1, fmt, options, writer);
        }
    };
}

test "Quat initialization" {
    const q = Quat(f32).identity;
    try std.testing.expectEqual(@as(f32, 1.0), q.w);
    try std.testing.expectEqual(@as(f32, 0.0), q.x);
}

test "Quat operations" {
    var q1 = Quat(f32).new(1, 0, 0, 0); // 180 deg around x
    const q2 = Quat(f32).new(0, 1, 0, 0); // 180 deg around y
    const q3 = q1.mul(q2);
    try std.testing.expectEqual(@as(f32, 1.0), q3.z);
    try std.testing.expectEqual(@as(f32, 0.0), q3.w);

    const v = Vec3(f32).unit_y;
    const v_rot = q1.rotateVec3(v); // 180 around X makes Y into -Y
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), v_rot.y, 1e-4);
}

test "DualQuat initialization" {
    const dq = DualQuat(f32).identity;
    try std.testing.expectEqual(@as(f32, 1.0), dq.real.w);
    try std.testing.expectEqual(@as(f32, 0.0), dq.dual.w);
}

test "DualQuat translation" {
    const t = Vec3(f32).new(10, 20, 30);
    const rot = Quat(f32).identity;
    const dq = DualQuat(f32).fromTranslationRotation(t, rot);

    const ext_t = dq.getTranslation();
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), ext_t.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), ext_t.y, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), ext_t.z, 1e-4);

    const p = Vec3(f32).zeros;
    const p_trans = dq.transformPoint(p);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), p_trans.x, 1e-4);
}

test "DualQuat transformation" {
    const t = Vec3(f32).new(5, 0, 0);
    const rot = Quat(f32).aroundAxis(Vec3(f32).unit_y, std.math.pi / 2.0); // 90 deg around Y
    const dq = DualQuat(f32).fromTranslationRotation(t, rot);

    const p = Vec3(f32).new(1, 0, 0); // Point at x=1
    const p_trans = dq.transformPoint(p);

    // Rotate 90 deg around Y -> (0, 0, -1)
    // Translate by (5, 0, 0) -> (5, 0, -1)
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), p_trans.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), p_trans.y, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), p_trans.z, 1e-4);
}
