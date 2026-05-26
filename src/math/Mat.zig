const std = @import("std");
const assert = std.debug.assert;
const printContainer = @import("printContainer.zig").printContainer;
const Quat = @import("Quat.zig").Quat;
const DualQuat = @import("Quat.zig").DualQuat;
const Vec2 = @import("Vec.zig").Vec2;
const Vec3 = @import("Vec.zig").Vec3;
const Vec4 = @import("Vec.zig").Vec4;

/// Column major -- index by mat.col.row. This ensures WGSL and GLSL compatible memory layout
pub fn Mat2x2(comptime T: type) type {
    return extern struct {
        x: Vec2(T),
        y: Vec2(T),
        const Self = @This();

        pub const identity: Self = .{
            .x = .{ .x = 1, .y = 0 },
            .y = .{ .x = 0, .y = 1 },
        };

        pub const zeros: Self = .{
            .x = .{ .x = 0, .y = 0 },
            .y = .{ .x = 0, .y = 0 },
        };

        pub fn new(x: Vec2(T), y: Vec2(T)) Self {
            return .{ .x = x, .y = y };
        }

        pub fn add(m1: Self, m2: Self) Self {
            return .{
                .x = m1.x.add(m2.x),
                .y = m1.y.add(m2.y),
            };
        }

        pub fn transposed(self: Self) Self {
            return .{
                .x = .{ .x = self.x.x, .y = self.y.x },
                .y = .{ .x = self.x.y, .y = self.y.y },
            };
        }

        pub fn mul(ma: Self, mb: Self) Self {
            const mat = ma.transposed();
            return .{
                .x = .{ .x = mat.x.dot(mb.x), .y = mat.y.dot(mb.x) },
                .y = .{ .x = mat.x.dot(mb.y), .y = mat.y.dot(mb.y) },
            };
        }

        pub fn print(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try printContainer(self, T, 2, 2, fmt, options, writer);
        }
    };
}

/// Column major -- index by mat.col.row. This ensures WGSL and GLSL compatible memory layout
pub fn Mat3x3(comptime T: type) type {
    return extern struct {
        x: Vec3(T),
        y: Vec3(T),
        z: Vec3(T),
        const Self = @This();

        pub const identity: Self = .{
            .x = .{ .x = 1, .y = 0, .z = 0 },
            .y = .{ .x = 0, .y = 1, .z = 0 },
            .z = .{ .x = 0, .y = 0, .z = 1 },
        };

        pub const zeros: Self = .{
            .x = .{ .x = 0, .y = 0, .z = 0 },
            .y = .{ .x = 0, .y = 0, .z = 0 },
            .z = .{ .x = 0, .y = 0, .z = 0 },
        };

        pub fn new(x: Vec3(T), y: Vec3(T), z: Vec3(T)) Self {
            return .{ .x = x, .y = y, .z = z };
        }

        pub fn add(m1: Self, m2: Self) Self {
            return .{
                .x = m1.x.add(m2.x),
                .y = m1.y.add(m2.y),
                .z = m1.z.add(m2.z),
            };
        }

        pub fn toQuat(self: Self) Quat(T) {
            const trace = self.x.x + self.y.y + self.z.z;
            if (trace > 0) {
                const s = @sqrt(trace + 1.0) * 2.0; // S=4*qw
                return Quat(T).new(
                    (self.y.z - self.z.y) / s,
                    (self.z.x - self.x.z) / s,
                    (self.x.y - self.y.x) / s,
                    0.25 * s,
                );
            } else if ((self.x.x > self.y.y) and (self.x.x > self.z.z)) {
                const s = @sqrt(1.0 + self.x.x - self.y.y - self.z.z) * 2.0; // S=4*qx
                return Quat(T).new(
                    0.25 * s,
                    (self.x.y + self.y.x) / s,
                    (self.x.z + self.z.x) / s,
                    (self.y.z - self.z.y) / s,
                );
            } else if (self.y.y > self.z.z) {
                const s = @sqrt(1.0 + self.y.y - self.x.x - self.z.z) * 2.0; // S=4*qy
                return Quat(T).new(
                    (self.x.y + self.y.x) / s,
                    0.25 * s,
                    (self.y.z + self.z.y) / s,
                    (self.z.x - self.x.z) / s,
                );
            } else {
                const s = @sqrt(1.0 + self.z.z - self.x.x - self.y.y) * 2.0; // S=4*qz
                return Quat(T).new(
                    (self.x.z + self.z.x) / s,
                    (self.y.z + self.z.y) / s,
                    0.25 * s,
                    (self.x.y - self.y.x) / s,
                );
            }
        }

        pub fn transposed(self: Self) Self {
            return .{
                .x = .{ .x = self.x.x, .y = self.y.x, .z = self.z.x },
                .y = .{ .x = self.x.y, .y = self.y.y, .z = self.z.y },
                .z = .{ .x = self.x.z, .y = self.y.z, .z = self.z.z },
            };
        }

        pub fn mul(ma: Self, mb: Self) Self {
            const mat = ma.transposed();
            return .{
                .x = .{ .x = mat.x.dot(mb.x), .y = mat.y.dot(mb.x), .z = mat.z.dot(mb.x) },
                .y = .{ .x = mat.x.dot(mb.y), .y = mat.y.dot(mb.y), .z = mat.z.dot(mb.y) },
                .z = .{ .x = mat.x.dot(mb.z), .y = mat.y.dot(mb.z), .z = mat.z.dot(mb.z) },
            };
        }

        pub fn lookAt(eye: Vec3(T), target: Vec3(T), up: Vec3(T)) Self {
            const f = target.sub(eye).normalized();
            const s = f.cross(up).normalized();
            const u = s.cross(f);
            return .{
                .x = .{ .x = s.x, .y = u.x, .z = -f.x },
                .y = .{ .x = s.y, .y = u.y, .z = -f.y },
                .z = .{ .x = s.z, .y = u.z, .z = -f.z },
            };
        }

        pub fn print(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try printContainer(self, T, 3, 3, fmt, options, writer);
        }
    };
}

/// Column major -- index by mat.col.row. This ensures WGSL and GLSL compatible memory layout
pub fn Mat4x4(comptime T: type) type {
    return extern struct {
        x: Vec4(T), // column 1
        y: Vec4(T), // column 2
        z: Vec4(T), // column 3
        w: Vec4(T), // column 4
        const Self = @This();

        pub const identity: Self = .{
            .x = .{ .x = 1, .y = 0, .z = 0, .w = 0 },
            .y = .{ .x = 0, .y = 1, .z = 0, .w = 0 },
            .z = .{ .x = 0, .y = 0, .z = 1, .w = 0 },
            .w = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
        };

        pub const zeros: Self = .{
            .x = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
            .y = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
            .z = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
            .w = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
        };

        pub fn new(x: Vec4(T), y: Vec4(T), z: Vec4(T), w: Vec4(T)) Self {
            return .{
                .x = .{ .x = x.x, .y = y.x, .z = z.x, .w = w.x },
                .y = .{ .x = x.y, .y = y.y, .z = z.y, .w = w.y },
                .z = .{ .x = x.z, .y = y.z, .z = z.z, .w = w.z },
                .w = .{ .x = x.w, .y = y.w, .z = z.w, .w = w.w },
            };
        }

        pub fn transposed(self: Self) Self {
            return .{
                .x = .{ .x = self.x.x, .y = self.y.x, .z = self.z.x, .w = self.w.x },
                .y = .{ .x = self.x.y, .y = self.y.y, .z = self.z.y, .w = self.w.y },
                .z = .{ .x = self.x.z, .y = self.y.z, .z = self.z.z, .w = self.w.z },
                .w = .{ .x = self.x.w, .y = self.y.w, .z = self.z.w, .w = self.w.w },
            };
        }

        pub fn mul(ma: Self, mb: Self) Self {
            const mat = ma.transposed();
            return .{
                .x = .{ .x = mat.x.dot(mb.x), .y = mat.y.dot(mb.x), .z = mat.z.dot(mb.x), .w = mat.w.dot(mb.x) },
                .y = .{ .x = mat.x.dot(mb.y), .y = mat.y.dot(mb.y), .z = mat.z.dot(mb.y), .w = mat.w.dot(mb.y) },
                .z = .{ .x = mat.x.dot(mb.z), .y = mat.y.dot(mb.z), .z = mat.z.dot(mb.z), .w = mat.w.dot(mb.z) },
                .w = .{ .x = mat.x.dot(mb.w), .y = mat.y.dot(mb.w), .z = mat.z.dot(mb.w), .w = mat.w.dot(mb.w) },
            };
        }

        pub fn add(m1: Self, m2: Self) Self {
            return .{
                .x = m1.x.add(m2.x),
                .y = m1.y.add(m2.y),
                .z = m1.z.add(m2.z),
                .w = m1.w.add(m2.w),
            };
        }

        pub fn lookAt(eye: Vec3(T), target: Vec3(T), up: Vec3(T)) Self {
            const f = target.sub(eye).normalized();
            const s = f.cross(up).normalized();
            const u = s.cross(f);
            return .{
                .x = .{ .x = s.x, .y = u.x, .z = -f.x, .w = 0 },
                .y = .{ .x = s.y, .y = u.y, .z = -f.y, .w = 0 },
                .z = .{ .x = s.z, .y = u.z, .z = -f.z, .w = 0 },
                .w = .{ .x = -s.dot(eye), .y = -u.dot(eye), .z = f.dot(eye), .w = 1 },
            };
        }

        pub fn toQuat(self: Self) Quat(T) {
            const m3 = Mat3x3(T).new(self.x.toVec3(), self.y.toVec3(), self.z.toVec3());
            return m3.toQuat();
        }

        pub fn toDualQuat(self: Self) DualQuat(T) {
            const rot = self.toQuat();
            const trans = Vec3(T).new(self.w.x, self.w.y, self.w.z);
            return DualQuat(T).fromTranslationRotation(trans, rot);
        }

        pub fn mulVec4(m: Self, v: Vec4(T)) Vec4(T) {
            const mt = m.transposed();
            return .{
                .x = mt.x.dot(v),
                .y = mt.y.dot(v),
                .z = mt.z.dot(v),
                .w = mt.w.dot(v),
            };
        }

        pub fn translation(v: Vec3(T)) Self {
            return .{
                .x = .{ .x = 1, .y = 0, .z = 0, .w = 0 },
                .y = .{ .x = 0, .y = 1, .z = 0, .w = 0 },
                .z = .{ .x = 0, .y = 0, .z = 1, .w = 0 },
                .w = .{ .x = v.x, .y = v.y, .z = v.z, .w = 1 },
            };
        }

        /// Returns a new matrix obtained by translating the input one.
        pub fn translate(self: Self, v: Vec3(T)) Self {
            return .{
                .x = self.x,
                .y = self.y,
                .z = self.z,
                .w = self.w.add(.{ .x = v.x, .y = v.y, .z = v.z, .w = 1 }),
            };
        }

        /// Create a rotation matrix around an arbitrary axis.
        pub fn rotation(axis: Vec3(T), angle_rad: T) Self {
            const sqr_norm = axis.squaredNorm();
            if (sqr_norm == 0.0) {
                return Self.identity;
            } else if (@abs(sqr_norm - 1.0) > 0.0001) {
                const norm = @sqrt(sqr_norm);
                return rotationNormalized(axis.div(norm), angle_rad);
            }
            return rotationNormalized(axis, angle_rad);
        }

        /// Create a rotation matrix around a normalized axis.
        pub fn rotationNormalized(axis: Vec3(T), angle_rad: T) Self {
            const c = @cos(angle_rad);
            const s = @sin(angle_rad);
            const t = 1.0 - c;

            const x = axis.x;
            const y = axis.y;
            const z = axis.z;

            return .{
                .x = .{ .x = x * x * t + c, .y = y * x * t + z * s, .z = z * x * t - y * s, .w = 0 },
                .y = .{ .x = x * y * t - z * s, .y = y * y * t + c, .z = z * y * t + x * s, .w = 0 },
                .z = .{ .x = x * z * t + y * s, .y = y * z * t - x * s, .z = z * z * t + c, .w = 0 },
                .w = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
            };
        }

        ///Rotates a matrix around an arbitrary axis.
        pub fn rotate(self: Self, axis: Vec3(T), angle_rad: T) Self {
            return mul(rotation(axis, angle_rad), self);
        }

        pub fn scaled(self: Self, v: Vec3(T)) Self {
            var m = self.*;
            m.x.x *= v.x;
            m.y.y *= v.y;
            m.z.z *= v.z;
            return m;
        }

        pub fn print(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try printContainer(self, T, 4, 4, fmt, options, writer);
        }
    };
}

/// Generates multiplication functions to fit dimentions
fn mulGeneric(a: anytype, b: anytype) type {
    _ = a;
    _ = b;
    return type;
}

test "mat4AlignmentAndSize" {
    try std.testing.expect(@alignOf(Mat4x4(f32)) == @alignOf([4][4]f32));
    try std.testing.expect(@alignOf([4][4]f32) == @alignOf([16]f32));
    try std.testing.expect(@sizeOf(Mat4x4(f32)) == @sizeOf([4][4]f32));
    try std.testing.expect(@sizeOf([4][4]f32) == @sizeOf([16]f32));
}

test "Mat2x2 operations" {
    const Mat2 = Mat2x2(f32);
    const m1 = Mat2{ .x = .{ .x = 1, .y = 2 }, .y = .{ .x = 3, .y = 4 } };
    const m2 = Mat2{ .x = .{ .x = 2, .y = 0 }, .y = .{ .x = 1, .y = 2 } };

    const result = m1.mul(m2);
    try std.testing.expectEqual(@as(f32, 2.0), result.x.x);
    try std.testing.expectEqual(@as(f32, 4.0), result.x.y);
    try std.testing.expectEqual(@as(f32, 7.0), result.y.x);
    try std.testing.expectEqual(@as(f32, 10.0), result.y.y);
}

test "Mat3x3 identity multiplication" {
    const Mat3 = Mat3x3(f32);
    const m1 = Mat3{
        .x = .{ .x = 1, .y = 2, .z = 3 },
        .y = .{ .x = 4, .y = 5, .z = 6 },
        .z = .{ .x = 7, .y = 8, .z = 9 },
    };

    const id = Mat3.identity;
    const result = m1.mul(id);

    try std.testing.expectEqual(@as(f32, 1.0), result.x.x);
    try std.testing.expectEqual(@as(f32, 5.0), result.y.y);
    try std.testing.expectEqual(@as(f32, 9.0), result.z.z);
}

test "Mat4x4 translation and mulVec4" {
    const Mat4 = Mat4x4(f32);
    const trans = Mat4.translation(.{ .x = 5.0, .y = -3.0, .z = 2.0 });

    const p = Vec4(f32).new(1.0, 1.0, 1.0, 1.0);
    const result = trans.mulVec4(p);

    try std.testing.expectEqual(@as(f32, 6.0), result.x);
    try std.testing.expectEqual(@as(f32, -2.0), result.y);
    try std.testing.expectEqual(@as(f32, 3.0), result.z);
    try std.testing.expectEqual(@as(f32, 1.0), result.w);
}
