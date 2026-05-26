import sys

with open("src/vulkan/ResourceManager.zig", "r") as f:
    lines = f.readlines()

clean_lines = lines[:955]

test_ui = """pub fn testUI(self: *Self, core: *Core) !void {
    const letter_A_curves = [_]Vertex{
        .{ .position = .{ .x = 100, .y = 100, .z = 0 } },
        .{ .position = .{ .x = 200, .y = 300, .z = 0 } },
        .{ .position = .{ .x = 300, .y = 500, .z = 0 } },

        .{ .position = .{ .x = 300, .y = 500, .z = 0 } },
        .{ .position = .{ .x = 400, .y = 300, .z = 0 } },
        .{ .position = .{ .x = 500, .y = 100, .z = 0 } },

        .{ .position = .{ .x = 200, .y = 300, .z = 0 } },
        .{ .position = .{ .x = 300, .y = 300, .z = 0 } },
        .{ .position = .{ .x = 400, .y = 300, .z = 0 } },
    };

    const UI_TYPE_BEZIER_CURVE = 1;
    const curve_bytes = std.mem.sliceAsBytes(&letter_A_curves);

    const vertex_count = letter_A_curves.len;
    const v_size = vertex_count * @sizeOf(Vertex);

    const current_v_offset = try self.vertex_arena.allocate(@intCast(v_size));
    const current_ui_offset = try self.ui_arena.allocate(@sizeOf(UIElement));

    self.upload(&core.asynccontext, curve_bytes, self.vertex_arena.buffer, current_v_offset);

    const mesh = UIElement{
        .vertexBuffer = self.vertex_arena.getAddress(current_v_offset),
        .vertexCount = vertex_count,
        .pad = 0,
    };

    self.upload(&core.asynccontext, std.mem.asBytes(&mesh), self.ui_arena.buffer, current_ui_offset);

    const instance = UIInstance{
        .UIBuffer = self.ui_arena.getAddress(current_ui_offset),
        .transformIndex = 0,
        .type = UI_TYPE_BEZIER_CURVE,
    };

    const current_instance_offset = try self.uiinstance_arena.allocate(@sizeOf(UIInstance));

    for (0..Core.multibuffering) |i| {
        const frame_base_offset = i * MAX_OBJECTS * @sizeOf(UIInstance);
        self.upload(
            &core.asynccontext,
            std.mem.asBytes(&instance),
            self.uiinstance_arena.buffer,
            current_instance_offset + frame_base_offset,
        );
    }
}
"""

with open("src/vulkan/ResourceManager.zig", "w") as f:
    f.writelines(clean_lines)
    f.write(test_ui)
