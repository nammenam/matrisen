const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zkaos",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = b.host,
        .optimize = optimize,
    });
    exe.linkLibCpp();
    exe.linkLibC();

    exe.linkSystemLibrary("SDL3");    
    exe.linkSystemLibrary("vulkan");

    exe.addCSourceFile(.{ .file = .{ .path = "src/vk_mem_alloc.cpp" }, .flags = &.{ "" } });
    exe.addCSourceFile(.{ .file = .{ .path = "src/stb_image.c" }, .flags = &.{ "" } });

    exe.addIncludePath(.{ .path = "thirdparty/cimgui/" });
    exe.addIncludePath(.{ .path = "thirdparty/cimgui/generator/output/" });

    compile_all_shaders(b, exe);

    const imgui_lib = b.addStaticLibrary(.{
        .name = "cimgui",
        .target = b.host,
        .optimize = optimize,
    });
    imgui_lib.linkLibC();
    imgui_lib.linkLibCpp();
    imgui_lib.addIncludePath(.{ .path = "thirdparty/cimgui/imgui/" });
    // imgui_lib.addIncludePath(.{ .path = "thirdparty/cimgui/" });
    // imgui_lib.addIncludePath(.{ .path = "thirdparty/cimgui/imgui/backends/" });
    // imgui_lib.addIncludePath(.{ .path = "thirdparty/cimgui/generator/output/" });
    imgui_lib.linkSystemLibrary("SDL3");
    imgui_lib.addCSourceFiles(.{
        .files = &.{
            "thirdparty/cimgui/cimgui.cpp",
            "thirdparty/cimgui/imgui/imgui.cpp",
            "thirdparty/cimgui/imgui/imgui_demo.cpp",
            "thirdparty/cimgui/imgui/imgui_draw.cpp",
            "thirdparty/cimgui/imgui/imgui_tables.cpp",
            "thirdparty/cimgui/imgui/imgui_widgets.cpp",
            "thirdparty/cimgui/imgui/backends/imgui_impl_sdl3.cpp",
            "thirdparty/cimgui/imgui/backends/imgui_impl_vulkan.cpp",
        },
    });
    exe.linkLibrary(imgui_lib);


    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = b.host,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Copy documentation artifacts to prefix path");
    docs_step.dependOn(&install_docs.step);
}

fn compile_all_shaders(b: *std.Build, exe: *std.Build.Step.Compile) void {

    const shaders_dir = if (@hasDecl(@TypeOf(b.build_root.handle), "openIterableDir"))
        b.build_root.handle.openIterableDir("shaders", .{}) catch @panic("Failed to open shaders directory")
    else
        b.build_root.handle.openDir("shaders", .{ .iterate = true }) catch @panic("Failed to open shaders directory");

    var file_it = shaders_dir.iterate();
    while (file_it.next() catch @panic("failed to iterate shader directory")) |entry| {
        if (entry.kind == .file) {
            const ext = std.fs.path.extension(entry.name);
            if (std.mem.eql(u8, ext, ".glsl")) {
                const basename = std.fs.path.basename(entry.name);
                const name = basename[0..basename.len - ext.len];
                std.debug.print("found shader file to compile: {s}. compiling with name: {s}\n", .{ entry.name, name });
                add_shader(b, exe, name);
            }
        }
    }
}

fn add_shader(b: *std.Build, exe: *std.Build.Step.Compile, name: []const u8) void {
    const source = std.fmt.allocPrint(b.allocator, "shaders/{s}.glsl", .{name}) catch @panic("OOM");
    const outpath = std.fmt.allocPrint(b.allocator, "shaders/{s}.spv", .{name}) catch @panic("OOM");

    const shader_compilation = b.addSystemCommand(&.{ "glslangValidator" });
    shader_compilation.addArg("-V");
    shader_compilation.addArg("-o");
    const output = shader_compilation.addOutputFileArg(outpath);
    shader_compilation.addFileArg(.{ .path = source });

    exe.root_module.addAnonymousImport(name, .{ .root_source_file = output });
}
