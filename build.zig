const std = @import("std");
const log = std.log.scoped(.build);
const Build = std.Build;

const shaderpath = "src/example/shaders";

pub fn build(b: *Build) !void {
    const alloc = std.heap.smp_allocator;
    var threaded = std.Io.Threaded.init(alloc, .{});
    const io = threaded.io();

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

    const shaders_step = b.step("shaders", "Compile Slang shaders");

    // 1. Open the shaders directory
    var dir = b.build_root.handle.openDir(io, shaderpath, .{ .iterate = true }) catch |err| {
        log.warn("Could not open shader directory: {s}", .{@errorName(err)});
        return err;
    };
    defer dir.close(io);

    var it = dir.iterate();

    // 2. Loop through every file in the directory
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".slang")) continue;

        // Skip common.slang, we don't want to compile it as a standalone executable shader
        if (std.mem.eql(u8, entry.name, "common.slang")) continue;

        // Infer the shader stage based on the filename (e.g., triangle.vert.slang)
        var stage: []const u8 = "compute"; // default fallback
        if (std.mem.indexOf(u8, entry.name, ".vert")) stage = "vertex";
        if (std.mem.indexOf(u8, entry.name, ".frag")) stage = "fragment";
        if (std.mem.indexOf(u8, entry.name, ".mesh")) stage = "mesh";

        // Compile the shader
        const shader_module = compileSlang(b, shaders_step, entry.name, "main", stage, enable_meshshading);

        // Strip ".slang" from the filename to create a clean Zig module name
        // e.g., "triangle.vert.slang" becomes "triangle.vert_spv"
        const base_name = entry.name[0 .. entry.name.len - 6];
        const module_name = b.fmt("{s}_spv", .{base_name});

        // Expose it to your Zig code so you can use @embedFile(module_name)
        exe.root_module.addImport(module_name, shader_module);

        log.info("Registered shader: {s} -> @embedFile(\"{s}\")", .{ entry.name, module_name });
    }

    // ==========================================================

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn compileSlang(
    b: *Build,
    shaders_step: *Build.Step,
    filename: []const u8,
    entry: []const u8,
    stage: []const u8,
    meshshading: bool,
) *Build.Module {
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
    return b.createModule(.{
        .root_source_file = spv_output,
    });
}
