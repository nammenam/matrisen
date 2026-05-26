const std = @import("std");
const assert = std.debug.assert;
const Vec2 = @import("Vec.zig").Vec2;
const Vec3 = @import("Vec.zig").Vec3;
const Vec4 = @import("Vec.zig").Vec4;
const Mat2x2 = @import("Mat.zig").Mat2x2;
const Mat3x3 = @import("Mat.zig").Mat3x3;
const Mat4x4 = @import("Mat.zig").Mat4x4;
const Quat = @import("Quat.zig").Quat;
const DualQuat = @import("Quat.zig").DualQuat;

pub fn printContainer(
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
            try writer.writeByteNTimes(' ', padding);
            if (column < C - 1) {
                _ = try writer.write("  "); // Add space between columns
            }
        }
        _ = try writer.write(" ]\n");
    }
}

test "printContainer" {
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
