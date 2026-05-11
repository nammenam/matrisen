const std = @import("std");
const log = std.log.scoped(.build);
const Build = std.Build;
const shaders = @import("src/shaders.zig");

pub fn build(b: *Build) !void {
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

    // replace all the manual compileSlang calls with:
    for (shaders.shaders) |def| {
        switch (def) {
            .compute => |s| {
                compileSlang(b, shaders_step, s.file, s.entry, "compute", enable_meshshading);
            },
            .graphics => |s| {
                compileSlang(b, shaders_step, s.file, s.entry_vert, "vertex", enable_meshshading);
                compileSlang(b, shaders_step, s.file, s.entry_frag, "fragment", enable_meshshading);
            },
            .mesh_graphics => |s| {
                compileSlang(b, shaders_step, s.file, s.entry_mesh, "mesh", enable_meshshading);
                compileSlang(b, shaders_step, s.file, s.entry_frag, "fragment", enable_meshshading);
            },
        }
    }

    exe.step.dependOn(shaders_step);
    b.installArtifact(exe);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

fn compileSlang(
    b: *Build,
    shaders_step: *Build.Step,
    filename: []const u8,
    entry: []const u8,
    stage: []const u8,
    meshshading: bool,
) void {
    const cmd = b.addSystemCommand(&.{"slangc"});
    const shader_src = b.path(b.fmt("{s}/{s}", .{ shaders.src, filename }));
    cmd.addFileArg(shader_src);

    const common_src = b.path(b.fmt("{s}/common.slang", .{shaders.src}));
    cmd.addFileInput(common_src);

    if (meshshading) {
        cmd.addArg("-DUSE_MESH_SHADING=1");
    } else {
        cmd.addArg("-DUSE_MESH_SHADING=0");
    }

    cmd.addArgs(&.{ "-target", "spirv", "-fvk-use-scalar-layout" });
    cmd.addArgs(&.{ "-entry", entry, "-stage", stage });
    cmd.addArg("-o");

    const out_path = b.fmt("{s}/{s}.spv", .{ shaders.spv, entry });
    cmd.addArg(out_path);

    shaders_step.dependOn(&cmd.step);
    // no more addImport needed
}
