fn addSlangShader(b: *std.Build, mod: *std.Build.Module, shaders_step: *std.Build.Step, filename: []const u8, entry_point: []const u8, stage: []const u8) void {
    const shader_src = b.path(b.fmt("{s}/{s}", .{ shaderpath, filename }));

    const cmd = b.addSystemCommand(&.{"slangc"});
    cmd.addFileArg(shader_src);
    cmd.addArg("-target");
    cmd.addArg("spirv");

    // Crucial for Buffer Device Address and exact struct matching with Zig!
    cmd.addArg("-fvk-use-scalar-layout");

    cmd.addArg("-entry");
    cmd.addArg(entry_point);
    cmd.addArg("-stage");
    cmd.addArg(stage);
    cmd.addArg("-o");

    const spv_output = cmd.addOutputFileArg(b.fmt("{s}.spv", .{entry_point}));
    shaders_step.dependOn(&cmd.step);

    const gen = b.addWriteFiles();
    _ = gen.addCopyFile(spv_output, "shader.spv");

    // Create the Zig wrapper so we can @import the SPIR-V byte arrays
    const wrapper_path = gen.add("shader.zig",
        \\const std = @import("std");
        \\const content align(4) = @embedFile("shader.spv").*;
        \\pub const bytes = content;
        \\pub const code_u8 = std.mem.bytesAsSlice(u8, &content);
    );

    const shader_module = b.createModule(.{ .root_source_file = wrapper_path });

    const import_name = b.fmt("{s}", .{entry_point});
    mod.addImport(import_name, shader_module);
}
