const std = @import("std");
const assert = std.debug.assert;

pub fn Vec2(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,
        const Self = @This();

        pub const zeros: Self = .{ .x = 0, .y = 0 };
        pub const unit_x: Self = .{ .x = 1, .y = 0 };
        pub const unit_y: Self = .{ .x = 0, .y = 1 };

        pub fn new(x: T, y: T) Self {
            return .{ .x = x, .y = y };
        }

        pub fn toVec3(self: Self, z: T) Vec4(T) {
            return .{ .x = self.x, .y = self.y, .z = z };
        }

        pub fn toVec4(self: Self, z: T, w: T) Vec4(T) {
            return .{ .x = self.x, .y = self.y, .z = z, .w = w };
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try formatGeneric(self, T, 2, 1, fmt, options, writer); // Swap row and column for columnvector
        }
    };
}

pub fn Vec3(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,
        z: T,
        const Self = @This();

        pub const zeros: Self = .{ .x = 0, .y = 0, .z = 0 };
        pub const unit_x: Self = .{ .x = 1, .y = 0, .z = 0 };
        pub const unit_y: Self = .{ .x = 0, .y = 1, .z = 0 };
        pub const unit_z: Self = .{ .x = 0, .y = 0, .z = 1 };

        pub fn squaredNorm(self: Self) T {
            return self.x * self.x + self.y * self.y + self.z * self.z;
        }

        pub fn norm(self: Self) T {
            return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
        }

        pub fn isNormalized(self: Self) bool {
            return @abs(self.squaredNorm() - 1.0) <= 1e-4;
        }

        pub fn new(x: T, y: T, z: T) Self {
            return .{ .x = x, .y = y, .z = z };
        }

        pub fn all(value: T) Self {
            return .{ .x = value, .y = value, .z = value };
        }

        pub fn toVec4(self: Self, w: T) Vec4(T) {
            return .{ .x = self.x, .y = self.y, .z = self.z, .w = w };
        }

        pub fn flip(self: Self) Vec3(T) {
            return .{ .x = -self.x, .y = -self.y, .z = -self.z };
        }

        pub fn add(self: Self, other: Self) Self {
            return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z };
        }

        pub fn sub(self: Self, other: Self) Self {
            return .{ .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z };
        }

        pub fn elementwiseMul(self: Self, other: Self) Self {
            return .{ .x = self.x * other.x, .y = self.y * other.y, .z = self.z * other.z };
        }

        pub fn scalarMul(self: Self, other: T) Self {
            return .{ .x = self.x * other, .y = self.y * other, .z = self.z * other };
        }

        pub fn dot(a: Self, b: Self) T {
            return a.x * b.x + a.y * b.y + a.z * b.z;
        }

        pub fn cross(self: Self, other: Self) Self {
            return .{
                .x = self.y * other.z - other.y * self.z,
                .y = self.z * other.x - other.z * self.x,
                .z = self.x * other.y - other.x * self.y,
            };
        }

        pub fn div(self: Self, other: T) Self {
            return .{ .x = self.x / other, .y = self.y / other, .z = self.z / other };
        }

        pub fn scaleUniform(self: Self, value: T) Self {
            return .{ .x = self.x * value, .y = self.y * value, .z = self.z * value };
        }

        pub fn normalized(self: Self) Self {
            const reciprocal = 1.0 / self.norm();
            assert(reciprocal > 0.0);
            return .{ .x = self.x * reciprocal, .y = self.y * reciprocal, .z = self.z * reciprocal };
        }

        pub fn translateInWorldframe(self: *Self, direction: Vec3(T)) void {
            self = self.position.add(direction);
        }

        pub fn translateLocalframe(self: *Self, rot: Quat(T), direction: Vec3(T)) void {
            const local_rotation = rot.rotateVector3(direction);
            self = self.add(local_rotation);
        }

        pub fn translateWorldX(self: *Self, amount: T) void {
            self.x += amount;
        }

        pub fn translateWorldY(self: *Self, amount: T) void {
            self.y += amount;
        }

        pub fn translateWorldZ(self: *Self, amount: T) void {
            self.z += amount;
        }

        pub fn translatePitch(self: *Self, rot: *Quat(T), amount: T) void {
            var localx = rot.pitchAxis();
            localx = localx.scalarMul(amount);
            self.* = self.add(localx);
        }

        pub fn translateYaw(self: *Self, rot: *Quat(T), amount: T) void {
            var localx = rot.yawAxis();
            localx = localx.scalarMul(amount);
            self.* = self.add(localx);
        }

        pub fn translateRoll(self: *Self, rot: *Quat(T), amount: T) void {
            var localx = rot.rollAxis();
            localx = localx.scalarMul(amount);
            self.* = self.add(localx);
        }

        pub fn translateForward(self: *Self, rot: *Quat(T), amount: T) void {
            var local = rot.rollAxis();
            local.z = 0;
            local = local.normalized();
            local = local.scalarMul(amount);
            self.* = self.add(local);
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try formatGeneric(self, T, 3, 1, fmt, options, writer);
        }
    };
}

pub fn Vec4(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,
        z: T,
        w: T,
        const Self = @This();

        pub const zeros: Self = .{ .x = 0, .y = 0, .z = 0, .w = 0 };
        pub const unit_w: Self = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
        pub const unit_x: Self = .{ .x = 1, .y = 0, .z = 0, .w = 0 };
        pub const unit_y: Self = .{ .x = 0, .y = 1, .z = 0, .w = 0 };
        pub const unit_z: Self = .{ .x = 0, .y = 0, .z = 1, .w = 0 };
        pub const point_x: Self = .{ .x = 1, .y = 0, .z = 0, .w = 1 };
        pub const point_y: Self = .{ .x = 0, .y = 1, .z = 0, .w = 1 };
        pub const point_z: Self = .{ .x = 0, .y = 0, .z = 1, .w = 1 };

        pub fn new(x: T, y: T, z: T, w: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = w };
        }

        pub fn addPoint(self: Self, other: Self) Self {
            return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z, .w = 1 };
        }

        pub fn add(self: Self, other: Self) Self {
            return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z, .w = other.w };
        }

        pub fn of(x: T, y: T, z: T, w: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = w };
        }

        pub fn toVec3(self: Self) Vec3(T) {
            return .{ .x = self.x, .y = self.y, .z = self.z };
        }

        pub fn nomalized(self: Self) Self {
            return self.toVec3().normalize().to_vec4(self.w);
        }

        pub fn dot(a: Self, b: Self) T {
            return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
        }

        pub fn packU8(self: Self) u32 {
            if (T != f32) @compileError("type must be f32 to use this function");
            const r: u32 = @intFromFloat(@round(std.math.clamp(self.x, 0, 1) * 255.0));
            const g: u32 = @intFromFloat(@round(std.math.clamp(self.y, 0, 1) * 255.0));
            const b: u32 = @intFromFloat(@round(std.math.clamp(self.z, 0, 1) * 255.0));
            const a: u32 = @intFromFloat(@round(std.math.clamp(self.w, 0, 1) * 255.0));
            return ((a << 24) | (b << 16) | (g << 8) | r);
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try formatGeneric(self, T, 4, 1, fmt, options, writer);
        }
    };
}

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

        pub fn mul(ma: Self, mb: Self) Self {
            return .{
                .x = .{ .x = ma.x.x * mb.x.x + ma.y.x * mb.x.y, .y = ma.x.y * mb.x.x + ma.y.y * mb.x.y },
                .y = .{ .x = ma.x.x * mb.y.x + ma.y.x * mb.y.y, .y = ma.x.y * mb.y.x + ma.y.y * mb.y.y },
            };
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try formatGeneric(self, T, 2, 2, fmt, options, writer);
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

        pub fn mul(ma: Self, mb: Self) Self {
            return .{
                .x = .{
                    .x = ma.x.x * mb.x.x + ma.y.x * mb.x.y + ma.z.x * mb.x.z,
                    .y = ma.x.y * mb.x.x + ma.y.y * mb.x.y + ma.z.y * mb.x.z,
                    .z = ma.x.z * mb.x.x + ma.y.z * mb.x.y + ma.z.z * mb.x.z,
                },
                .y = .{
                    .x = ma.x.x * mb.y.x + ma.y.x * mb.y.y + ma.z.x * mb.y.z,
                    .y = ma.x.y * mb.y.x + ma.y.y * mb.y.y + ma.z.y * mb.y.z,
                    .z = ma.x.z * mb.y.x + ma.y.z * mb.y.y + ma.z.z * mb.y.z,
                },
                .z = .{
                    .x = ma.x.x * mb.z.x + ma.y.x * mb.z.y + ma.z.x * mb.z.z,
                    .y = ma.x.y * mb.z.x + ma.y.y * mb.z.y + ma.z.y * mb.z.z,
                    .z = ma.x.z * mb.z.x + ma.y.z * mb.z.y + ma.z.z * mb.z.z,
                },
            };
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try formatGeneric(self, T, 3, 3, fmt, options, writer);
        }
    };
}

/// Column major -- index by mat.col.row. This ensures WGSL and GLSL compatible memory layout
pub fn Mat4x4(comptime T: type) type {
    return extern struct {
        x: Vec4(T),
        y: Vec4(T),
        z: Vec4(T),
        w: Vec4(T),
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

        pub fn transposed(self: Self) Self {
            return .{
                .x = .{ .x = self.x.x, .y = self.y.x, .z = self.z.x, .w = self.w.x },
                .y = .{ .x = self.x.y, .y = self.y.y, .z = self.z.y, .w = self.w.y },
                .z = .{ .x = self.x.z, .y = self.y.z, .z = self.z.z, .w = self.w.z },
                .w = .{ .x = self.x.w, .y = self.y.w, .z = self.z.w, .w = self.w.w },
            };
        }

        pub fn mul(ma: Self, mb: Self) Self {
            return .{
                .x = .{
                    .x = ma.x.x * mb.x.x + ma.y.x * mb.x.y + ma.z.x * mb.x.z + ma.w.x * mb.x.w,
                    .y = ma.x.y * mb.x.x + ma.y.y * mb.x.y + ma.z.y * mb.x.z + ma.w.y * mb.x.w,
                    .z = ma.x.z * mb.x.x + ma.y.z * mb.x.y + ma.z.z * mb.x.z + ma.w.z * mb.x.w,
                    .w = ma.x.w * mb.x.x + ma.y.w * mb.x.y + ma.z.w * mb.x.z + ma.w.w * mb.x.w,
                },
                .y = .{
                    .x = ma.x.x * mb.y.x + ma.y.x * mb.y.y + ma.z.x * mb.y.z + ma.w.x * mb.y.w,
                    .y = ma.x.y * mb.y.x + ma.y.y * mb.y.y + ma.z.y * mb.y.z + ma.w.y * mb.y.w,
                    .z = ma.x.z * mb.y.x + ma.y.z * mb.y.y + ma.z.z * mb.y.z + ma.w.z * mb.y.w,
                    .w = ma.x.w * mb.y.x + ma.y.w * mb.y.y + ma.z.w * mb.y.z + ma.w.w * mb.y.w,
                },
                .z = .{
                    .x = ma.x.x * mb.z.x + ma.y.x * mb.z.y + ma.z.x * mb.z.z + ma.w.x * mb.z.w,
                    .y = ma.x.y * mb.z.x + ma.y.y * mb.z.y + ma.z.y * mb.z.z + ma.w.y * mb.z.w,
                    .z = ma.x.z * mb.z.x + ma.y.z * mb.z.y + ma.z.z * mb.z.z + ma.w.z * mb.z.w,
                    .w = ma.x.w * mb.z.x + ma.y.w * mb.z.y + ma.z.w * mb.z.z + ma.w.w * mb.z.w,
                },
                .w = .{
                    .x = ma.x.x * mb.w.x + ma.y.x * mb.w.y + ma.z.x * mb.w.z + ma.w.x * mb.w.w,
                    .y = ma.x.y * mb.w.x + ma.y.y * mb.w.y + ma.z.y * mb.w.z + ma.w.y * mb.w.w,
                    .z = ma.x.z * mb.w.x + ma.y.z * mb.w.y + ma.z.z * mb.w.z + ma.w.z * mb.w.w,
                    .w = ma.x.w * mb.w.x + ma.y.w * mb.w.y + ma.z.w * mb.w.z + ma.w.w * mb.w.w,
                },
            };
        }

        pub fn add(m1: Self, m2: Self) Self {
            return .{
                .x = .{ .x = m1.x.x + m2.x.x, .y = m1.x.y + m2.x.y, .z = m1.x.z + m2.x.z, .w = m1.x.w + m2.x.w },
                .y = .{ .x = m1.y.x + m2.y.x, .y = m1.y.y + m2.y.y, .z = m1.y.z + m2.y.z, .w = m1.y.w + m2.y.w },
                .z = .{ .x = m1.z.x + m2.z.x, .y = m1.z.y + m2.z.y, .z = m1.z.z + m2.z.z, .w = m1.z.w + m2.z.w },
                .w = .{ .x = m1.w.x + m2.w.x, .y = m1.w.y + m2.w.y, .z = m1.w.z + m2.w.z, .w = m1.w.w + m2.w.w },
            };
        }

        pub fn mulVec4(m: Self, v: Vec4(T)) Vec4(T) {
            _ = m;
            _ = v;
        }

        pub fn translation(v: Vec3(T)) Self {
            return .{
                .x = .{ .x = 1, .y = 0, .z = 0, .w = 0 },
                .y = .{ .x = 0, .y = 1, .z = 0, .w = 0 },
                .z = .{ .x = 0, .y = 0, .z = 1, .w = 0 },
                .w = .{ .x = v.x, .y = v.y, .z = v.z, .w = 1 },
            };
        }

        pub fn lookAt(eye: Vec3(T), target: Vec3(T), up: Vec3(T)) Self {
            // Forward = Target - Eye (Direction we are looking)
            const f = target.sub(eye).normalized();
            // Right = Forward x Up
            const s = f.cross(up).normalized();
            // Recalculated Up = Right x Forward
            const u = s.cross(f);

            return .{
                .x = .{ .x = s.x, .y = u.x, .z = -f.x, .w = 0 },
                .y = .{ .x = s.y, .y = u.y, .z = -f.y, .w = 0 },
                .z = .{ .x = s.z, .y = u.z, .z = -f.z, .w = 0 },
                .w = .{ .x = -s.dot(eye), .y = -u.dot(eye), .z = f.dot(eye), .w = 1 },
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

        /// The result matrix is for a right-handed, zero to one, clipping space.
        pub fn perspective(fovy_rad: T, aspect: T, near: T, far: T) Self {
            const f = 1.0 / @tan(fovy_rad / 2.0);
            return .{
                .x = .{ .x = f / aspect, .y = 0, .z = 0, .w = 0 },
                .y = .{ .x = 0, .y = f, .z = 0, .w = 0 },
                .z = .{ .x = 0, .y = 0, .z = far / (far - near), .w = 1 },
                .w = .{ .x = 0, .y = 0, .z = -(far * near) / (far - near), .w = 0 },
            };
        }

        // TODO: Add a faster version that assume the axis is normalized.
        /// Create a rotation matrix around an arbitrary axis.
        pub fn rotation(axis: Vec3(T), angle_rad: T) Self {
            const c = @cos(angle_rad);
            const s = @sin(angle_rad);
            const t = 1.0 - c;

            const sqr_norm = axis.squaredNorm();
            if (sqr_norm == 0.0) {
                return Self.identity;
            } else if (@abs(sqr_norm - 1.0) > 0.0001) {
                const norm = @sqrt(sqr_norm);
                return rotation(axis.div(norm), angle_rad);
            }

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

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try formatGeneric(self, T, 4, 4, fmt, options, writer);
        }
    };
}

pub fn Quat(comptime T: type) type {
    if (@typeInfo(T) != .float) @compileError("Quaternion must be of type float");

    return struct {
        w: T,
        x: T,
        y: T,
        z: T,

        const Self = @This();
        pub const identity: Self = .{ .w = 1, .x = 0, .y = 0, .z = 0 };

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
                .y = self.x + other.y,
                .z = self.x + other.z,
                .w = self.x + other.w,
            };
        }

        pub fn mul(self: Self, other: Self) Self {
            assert(self.isNormalized());
            assert(other.isNormalized());

            const result: Self = .{
                .x = self.w * other.x + self.x * other.w + self.y * other.z - self.z * other.y,
                .y = self.w * other.y + self.y * other.w + self.z * other.x - self.x * other.z,
                .z = self.w * other.z + self.z * other.w + self.x * other.y - self.y * other.x,
                .w = self.w * other.w - self.x * other.x - self.y * other.y - self.z * other.z,
            };
            return result.normalized();
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
            return .{
                .x = .{ .x = 1 - 2 * y * y - 2 * z * z, .y = 2 * x * y - 2 * w * z, .z = 2 * x * z + 2 * w * y, .w = 0 },
                .y = .{ .x = 2 * x * y + 2 * w * z, .y = 1 - 2 * x * x - 2 * z * z, .z = 2 * y * z - 2 * w * x, .w = 0 },
                .z = .{ .x = 2 * x * z - 2 * w * y, .y = 2 * y * z + 2 * w * x, .z = 1 - 2 * x * x - 2 * y * y, .w = 0 },
                .w = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
            };
        }

        pub fn toAffine(rot: Self, pos: Vec3(T)) Mat4x4(T) {
            const rotation = rot.toMat4x4();
            const translation = Mat4x4(T).translation(.{
                .x = pos.x,
                .y = pos.y,
                .z = pos.z,
            });
            return rotation.mul(translation);
        }

        pub fn view(rot: Self, pos: Vec3(T)) Mat4x4(T) {
            const rotation = rot.toMat4x4();
            const translation = Mat4x4(T).translation(.{
                .x = -pos.x,
                .y = -pos.y,
                .z = -pos.z,
            });
            return rotation.mul(translation);
        }

        pub fn eulerAngles(self: Self) Vec3(T) {
            const pitch = std.math.atan2(2 * (self.w * self.x + self.y * self.z), 1 - 2 * (self.x * self.x + self.y * self.y));
            const roll = std.math.asin(2 * (self.w * self.y - self.x * self.z));
            const yaw = std.math.atan2(2 * (self.w * self.z + self.x * self.y), 1 - 2 * (self.y * self.y + self.z * self.z));
            return .{ .x = pitch, .y = roll, .z = yaw };
        }

        pub fn pitchAxis(self: *Self) Vec3(T) {
            return self.rotateVec3(Vec3(T).unit_x);
        }

        pub fn yawAxis(self: *Self) Vec3(T) {
            return self.rotateVec3(Vec3(T).unit_y);
        }

        pub fn rollAxis(self: *Self) Vec3(T) {
            return self.rotateVec3(Vec3(T).unit_z);
        }

        pub fn rotatePitch(self: *Self, angle: T) void {
            const rotation = Quat(T).aroundAxis(Vec3(T).unit_x, angle);
            self.* = self.mul(rotation);
        }

        pub fn rotateYaw(self: *Self, angle: T) void {
            const rotation = Quat(T).aroundAxis(Vec3(T).unit_y, angle);
            self.* = self.mul(rotation);
        }

        pub fn rotateRoll(self: *Self, angle: T) void {
            const rotation = Quat(T).aroundAxis(Vec3(T).unit_z, angle);
            self.* = self.mul(rotation);
        }

        pub fn rotateWorldX(self: *Self, angle: T) void {
            const rotation = Quat(T).aroundAxis(Vec3(T).unit_x, angle);
            self.* = rotation.mul(self);
        }

        pub fn rotateWorldY(self: *Self, angle: T) void {
            const rotation = Quat(T).aroundAxis(Vec3(T).unit_y, angle);
            self.* = rotation.mul(self);
        }

        pub fn rotateWorldZ(self: *Self, angle: T) void {
            const rotation = Quat(T).aroundAxis(Vec3(T).unit_z, angle);
            self.* = rotation.mul(self.*);
        }

        pub fn rotateWorld(self: *Self, axis: Vec3(T), angle: T) void {
            const rotation = Quat(T).aroundAxis(axis, angle);
            self.* = rotation.mul(self);
        }

        pub fn rotateLocal(self: *Self, axis: Vec3(T), angle: T) void {
            const rotation = Quat(T).aroundAxis(axis, angle);
            self.* = self.mul(rotation);
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try formatGeneric(self, T, 4, 1, fmt, options, writer);
        }
    };
}

pub fn formatGeneric(
    self: anytype,
    comptime T: type,
    C: comptime_int,
    R: comptime_int,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    const is_float = switch (@typeInfo(T)) {
        .float => true,
        .int => false,
        else => @compileError("Unsupported type for formatting: " ++ @typeName(T)),
    };
    const ff = std.fmt.format_float;
    const valueOptions = ff.FormatOptions{ .mode = .decimal, .precision = options.precision };
    var buffer: [ff.min_buffer_size]u8 = undefined;
    var column_widths: [C]usize = [_]usize{0} ** C;
    for (0..R) |row| {
        for (0..C) |column| {
            const array: [C][R]T = @bitCast(self);
            const value = array[column][row];
            var slice: []const u8 = undefined;
            if (is_float) {
                slice = try std.fmt.formatFloat(&buffer, value, valueOptions);
            } else {
                slice = try std.fmt.bufPrint(&buffer, "{}", .{value});
            }
            column_widths[column] = @max(column_widths[column], slice.len);
        }
    }
    for (0..R) |row| {
        _ = try writer.write("[ ");
        for (0..C) |column| {
            const array: [C][R]T = @bitCast(self);
            const value = array[column][row];
            var slice: []const u8 = undefined;
            if (is_float) {
                slice = try std.fmt.formatFloat(&buffer, value, valueOptions);
            } else {
                slice = try std.fmt.bufPrint(&buffer, "{}", .{value});
            }
            _ = try writer.write(slice);
            const padding = column_widths[column] - slice.len;
            var pad_buffer: [32]u8 = [_]u8{' '} ** 32; // TODO: Is this enough?
            _ = try writer.write(pad_buffer[0..padding]);
            if (column < C - 1) {
                _ = try writer.write("  "); // Add space between columns
            }
        }
        _ = try writer.write(" ]\n");
    }
}

test "mat4AlignmentAndSize" {
    try std.testing.expect(@alignOf(Mat4x4(f32)) == @alignOf([4][4]f32));
    try std.testing.expect(@alignOf([4][4]f32) == @alignOf([16]f32));
    try std.testing.expect(@sizeOf(Mat4x4(f32)) == @sizeOf([4][4]f32));
    try std.testing.expect(@sizeOf([4][4]f32) == @sizeOf([16]f32));
}

test "printTuple" {
    const Vec2f32 = Vec2(f32);
    const Vec2u32 = Vec2(u32);
    const Vec3f32 = Vec3(f32);
    const Vec3u32 = Vec3(u32);
    const Mat4x4u32 = Mat4x4(f32);
    var mat: Mat4x4u32 = .identity;
    var vec3: Vec2f32 = .zeros;
    var vec3u32: Vec2u32 = .zeros;
    vec3u32.x = 1000;
    vec3.x = 1.890;
    mat.x.w = 1.231;
    std.debug.print("{}\n", .{vec3});
    std.debug.print("{}\n", .{vec3u32});
    std.debug.print("{}\n", .{Vec3f32.zeros});
    std.debug.print("{}\n", .{Vec3u32.zeros});
    std.debug.print("{}\n", .{mat});
}

const bench = @import("benchmarking");

/// benchmarking program
pub fn main() !void {
    try bench.benchmark(Testbench, .{});
}

const Testbench = struct {
    const C = Mat4x4(f32).identity;
    const D = Mat4x4(f32).identity;

    pub fn directMul() void {
        _ = C.mul(&D);
    }
};
