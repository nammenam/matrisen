const std = @import("std");
const assert = std.debug.assert;
const printContainer = @import("printContainer.zig").printContainer;
const Quat = @import("Quat.zig").Quat;

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

        pub fn all(value: T) Self {
            return .{ .x = value, .y = value };
        }

        pub fn squaredNorm(self: Self) T {
            return self.x * self.x + self.y * self.y;
        }

        pub fn norm(self: Self) T {
            return @sqrt(self.x * self.x + self.y * self.y);
        }

        pub fn isNormalized(self: Self) bool {
            return @abs(self.squaredNorm() - 1.0) <= 1e-4;
        }

        pub fn normalized(self: Self) Self {
            const reciprocal = 1.0 / self.norm();
            assert(reciprocal > 0.0);
            return .{ .x = self.x * reciprocal, .y = self.y * reciprocal };
        }

        pub fn flip(self: Self) Self {
            return .{ .x = -self.x, .y = -self.y };
        }

        pub fn add(self: Self, other: Self) Self {
            return .{ .x = self.x + other.x, .y = self.y + other.y };
        }

        pub fn sub(self: Self, other: Self) Self {
            return .{ .x = self.x - other.x, .y = self.y - other.y };
        }

        pub fn elementwiseMul(self: Self, other: Self) Self {
            return .{ .x = self.x * other.x, .y = self.y * other.y };
        }

        pub fn scalarMul(self: Self, other: T) Self {
            return .{ .x = self.x * other, .y = self.y * other };
        }

        pub fn div(self: Self, other: T) Self {
            return .{ .x = self.x / other, .y = self.y / other };
        }

        pub fn dot(a: Self, b: Self) T {
            return a.x * b.x + a.y * b.y;
        }

        pub fn toVec3(self: Self, z: T) Vec4(T) {
            return .{ .x = self.x, .y = self.y, .z = z };
        }

        pub fn toVec4(self: Self, z: T, w: T) Vec4(T) {
            return .{ .x = self.x, .y = self.y, .z = z, .w = w };
        }

        pub fn print(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try printContainer(self, T, 2, 1, fmt, options, writer);
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

        pub fn new(x: T, y: T, z: T) Self {
            return .{ .x = x, .y = y, .z = z };
        }

        pub fn all(value: T) Self {
            return .{ .x = value, .y = value, .z = value };
        }

        pub fn squaredNorm(self: Self) T {
            return self.x * self.x + self.y * self.y + self.z * self.z;
        }

        pub fn norm(self: Self) T {
            return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
        }

        pub fn isNormalized(self: Self) bool {
            return @abs(self.squaredNorm() - 1.0) <= 1e-4;
        }

        pub fn normalized(self: Self) Self {
            const reciprocal = 1.0 / self.norm();
            assert(reciprocal > 0.0);
            return .{ .x = self.x * reciprocal, .y = self.y * reciprocal, .z = self.z * reciprocal };
        }

        pub fn flip(self: Self) Self {
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

        pub fn div(self: Self, other: T) Self {
            return .{ .x = self.x / other, .y = self.y / other, .z = self.z / other };
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

        pub fn toVec4(self: Self, w: T) Vec4(T) {
            return .{ .x = self.x, .y = self.y, .z = self.z, .w = w };
        }

        pub fn translateInWorldframe(self: *Self, direction: Vec3(T)) void {
            self.* = self.add(direction);
        }

        pub fn translateLocalframe(self: *Self, rot: Quat(T), direction: Vec3(T)) void {
            const local_rotation = rot.rotateVec3(direction);
            self.* = self.add(local_rotation);
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

        pub fn print(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try printContainer(self, T, 3, 1, fmt, options, writer);
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

        pub fn all(value: T) Self {
            return .{ .x = value, .y = value, .z = value, .w = value };
        }

        pub fn of(x: T, y: T, z: T, w: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = w };
        }

        pub fn squaredNorm(self: Self) T {
            return self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w;
        }

        pub fn norm(self: Self) T {
            return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w);
        }

        pub fn isNormalized(self: Self) bool {
            return @abs(self.squaredNorm() - 1.0) <= 1e-4;
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

        pub fn flip(self: Self) Self {
            return .{ .x = -self.x, .y = -self.y, .z = -self.z, .w = -self.w };
        }

        pub fn add(self: Self, other: Self) Self {
            return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z, .w = self.w + other.w };
        }

        pub fn sub(self: Self, other: Self) Self {
            return .{ .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z, .w = self.w - other.w };
        }

        pub fn elementwiseMul(self: Self, other: Self) Self {
            return .{ .x = self.x * other.x, .y = self.y * other.y, .z = self.z * other.z, .w = self.w * other.w };
        }

        pub fn scalarMul(self: Self, other: T) Self {
            return .{ .x = self.x * other, .y = self.y * other, .z = self.z * other, .w = self.w * other };
        }

        pub fn div(self: Self, other: T) Self {
            return .{ .x = self.x / other, .y = self.y / other, .z = self.z / other, .w = self.w / other };
        }

        pub fn dot(a: Self, b: Self) T {
            return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
        }

        pub fn addPoint(self: Self, other: Self) Self {
            return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z, .w = 1 };
        }

        pub fn toVec3(self: Self) Vec3(T) {
            return .{ .x = self.x, .y = self.y, .z = self.z };
        }

        pub fn packU8(self: Self) u32 {
            if (T != f32) @compileError("type must be f32 to use this function");
            const r: u32 = @intFromFloat(@round(std.math.clamp(self.x, 0, 1) * 255.0));
            const g: u32 = @intFromFloat(@round(std.math.clamp(self.y, 0, 1) * 255.0));
            const b: u32 = @intFromFloat(@round(std.math.clamp(self.z, 0, 1) * 255.0));
            const a: u32 = @intFromFloat(@round(std.math.clamp(self.w, 0, 1) * 255.0));
            return ((a << 24) | (b << 16) | (g << 8) | r);
        }

        pub fn print(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try printContainer(self, T, 4, 1, fmt, options, writer);
        }
    };
}

test "Vec2 operations" {
    const v1 = Vec2(f32).new(1.0, 2.0);
    const v2 = Vec2(f32).new(3.0, 4.0);

    const sum = v1.add(v2);
    try std.testing.expectEqual(@as(f32, 4.0), sum.x);
    try std.testing.expectEqual(@as(f32, 6.0), sum.y);

    const dot = v1.dot(v2);
    try std.testing.expectEqual(@as(f32, 11.0), dot); // 3 + 8
}

test "Vec3 operations" {
    const v1 = Vec3(f32).new(1.0, 0.0, 0.0);
    const v2 = Vec3(f32).new(0.0, 1.0, 0.0);

    const cross = v1.cross(v2);
    try std.testing.expectEqual(@as(f32, 0.0), cross.x);
    try std.testing.expectEqual(@as(f32, 0.0), cross.y);
    try std.testing.expectEqual(@as(f32, 1.0), cross.z);

    const norm = v2.norm();
    try std.testing.expectEqual(@as(f32, 1.0), norm);
}

test "Vec4 operations" {
    const v = Vec4(f32).new(1.0, 2.0, 3.0, 4.0);
    const scaled = v.scalarMul(2.0);

    try std.testing.expectEqual(@as(f32, 2.0), scaled.x);
    try std.testing.expectEqual(@as(f32, 8.0), scaled.w);
}
