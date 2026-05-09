const std = @import("std");
const log = std.log.scoped(.build);
const Build = std.Build;

const shaderpath = "src/example/shaders";

pub fn build(b: *Build) !void {
    // const alloc = std.heap.smp_allocator;
    // var threaded = std.Io.Threaded.init(alloc, .{});
    // const io = threaded.io();

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = b.addOptions();
    const enable_meshshading = b.option(bool, "meshshading", "Enable meshshading") orelse false;
    options.addOption(bool, "meshshading", enable_meshshading);

    const matrisen = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
    });
    matrisen.addImport("config", options.createModule());

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

    exe.root_module.addImport("config", options.createModule());
    exe.root_module.linkSystemLibrary("SDL3", .{});
    exe.root_module.linkSystemLibrary("vulkan", .{});

    // add vma

    const shaders_step = b.step("shaders", "Compile Slang shaders");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Explicitly compile the three entry points from your scene.slang file
    addSlangShader(b, matrisen, shaders_step, "rastermain.slang", "vertexMain", "vertex");
    addSlangShader(b, matrisen, shaders_step, "rastermain.slang", "fragmentMain", "fragment");
    addSlangShader(b, matrisen, shaders_step, "rastermain_mesh.slang", "meshMain", "mesh");
    addSlangShader(b, matrisen, shaders_step, "rastermain_mesh.slang", "fragmentMain", "fragment");
    addSlangShader(b, matrisen, shaders_step, "drawcmd.slang", "drawcmdMain", "compute");
    addSlangShader(b, matrisen, shaders_step, "terrain.slang", "terrainMain", "compute");
    addSlangShader(b, matrisen, shaders_step, "vectorgfx.slang", "slugVertex", "vertex");
    addSlangShader(b, matrisen, shaders_step, "vectorgfx.slang", "slugFragment", "fragment");

    b.installArtifact(exe);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

fn addSlangShader(
    b: *std.Build,
    mod: *std.Build.Module,
    shaders_step: *std.Build.Step,
    filename: []const u8,
    entry_point: []const u8,
    stage: []const u8,
) void {
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

    const shader_module = b.createModule(.{ .root_source_file = spv_output });

    const import_name = b.fmt("{s}", .{entry_point});
    mod.addImport(import_name, shader_module);
}
