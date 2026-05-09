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
    matrisen.linkSystemLibrary("SDL3", .{});
    matrisen.linkSystemLibrary("vulkan", .{});
    matrisen.addCSourceFile(.{ .file = b.path("src/systemlibraries/vma.cpp") });
    matrisen.link_libcpp = true;

    const c = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/systemlibraries/clibraries.h"),
    });
    matrisen.addImport("c", c.createModule());

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
    compileSlang(b, matrisen, shaders_step, "rastermain.slang", "vertexMain", "vertex", false);
    compileSlang(b, matrisen, shaders_step, "rastermain.slang", "fragmentMain", "fragment", false);
    compileSlang(b, matrisen, shaders_step, "rastermain_mesh.slang", "meshMain", "mesh", true);
    compileSlang(b, matrisen, shaders_step, "rastermain_mesh.slang", "fragmentMain", "fragment", enable_meshshading);
    compileSlang(b, matrisen, shaders_step, "drawcmd.slang", "drawcmdMain", "compute", enable_meshshading);
    compileSlang(b, matrisen, shaders_step, "terrain.slang", "terrainMain", "compute", enable_meshshading);
    compileSlang(b, matrisen, shaders_step, "vectorgfx.slang", "slugVertex", "vertex", enable_meshshading);
    compileSlang(b, matrisen, shaders_step, "vectorgfx.slang", "slugFragment", "fragment", enable_meshshading);

    b.installArtifact(exe);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

fn compileSlang(
    b: *Build,
    mod: *Build.Module,
    shaders_step: *Build.Step,
    filename: []const u8,
    entry: []const u8,
    stage: []const u8,
    meshshading: bool,
) void {
    const cmd = b.addSystemCommand(&.{"slangc"});

    // Input file
    const shader_src = b.path(b.fmt("{s}/{s}", .{ shaderpath, filename }));
    cmd.addFileArg(shader_src);

    const common_src = b.path(b.fmt("{s}/common.slang", .{shaderpath}));
    cmd.addFileInput(common_src);
    // --------------------------

    if (meshshading) {
        cmd.addArg("-DUSE_MESH_SHADING=1");
    } else {
        cmd.addArg("-DUSE_MESH_SHADING=0");
    }

    cmd.addArgs(&.{ "-target", "spirv", "-fvk-use-scalar-layout" });
    cmd.addArgs(&.{ "-entry", entry, "-stage", stage });
    cmd.addArg("-o");

    // Output file (managed by Zig's cache)
    const spv_filename = b.fmt("{s}.spv", .{entry});
    const spv_output = cmd.addOutputFileArg(spv_filename);

    shaders_step.dependOn(&cmd.step);

    // Return as a module to be embedded
    mod.addImport(entry, b.createModule(.{ .root_source_file = spv_output }));
}
