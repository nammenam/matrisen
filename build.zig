const std = @import("std");
const log = std.log.scoped(.build);
const Build = std.Build;
const builtin = @import("builtin");

const shaderpath = "src/example/shaders";

pub fn build(b: *Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = b.addOptions();
    const version_opt = b.option(
        []const u8,
        "version",
        "overrides the version reported",
    ) orelse v: {
        var code: u8 = undefined;
        const git_describe = b.runAllowFail(&[_][]const u8{
            "git", "describe", "--tags",
        }, &code, .Ignore) catch {
            break :v "<unk>";
        };
        break :v std.mem.trim(u8, git_describe, " \n\r");
    };
    options.addOption([]const u8, "version", version_opt);

    const matrisen = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "exe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/example/main.zig"),
            .optimize = optimize,
            .target = target,
            .imports = &.{
                .{ .name = "matrisen", .module = matrisen },
            },
        }),
    });

    // Add these two lines to bypass the internal Zig linker bug:
    exe.use_llvm = true;
    exe.use_lld = true;

    exe.root_module.addOptions("config", options);
    exe.linkLibCpp();
    exe.linkLibC();
    exe.linkSystemLibrary("SDL3");
    exe.linkSystemLibrary("vulkan");
    exe.addCSourceFile(.{ .file = b.path("src/clibs/vk_mem_alloc.cpp"), .flags = &.{} });
    exe.addCSourceFile(.{ .file = b.path("src/clibs/stb_image.c"), .flags = &.{} });

    // --- SLANG SHADER COMPILATION ---
    const shaders_step = b.step("shaders", "Compile Slang shaders");

    // Explicitly compile the three entry points from your scene.slang file
    addSlangShader(b, matrisen, shaders_step, "pbr.slang", "vertexMain", "vertex");
    addSlangShader(b, matrisen, shaders_step, "pbr.slang", "fragmentMain", "fragment");
    addSlangShader(b, matrisen, shaders_step, "draw.slang", "drawMain", "compute");
    addSlangShader(b, matrisen, shaders_step, "terrain.slang", "terain", "compute");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

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
