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


    exe.linkSystemLibrary("SDL3");    
    exe.linkSystemLibrary("vulkan");
    exe.addCSourceFile(.{ .file = .{ .path = "src/vk_mem_alloc.cpp" }, .flags = &.{ "" } });
    exe.addIncludePath(.{ .path = "thirdparty/vma/" });
    exe.addCSourceFile(.{ .file = .{ .path = "src/stb_image.c" }, .flags = &.{ "" } });
    exe.addIncludePath(.{ .path = "thirdparty/stb/" });
    exe.addIncludePath(.{ .path = "thirdparty/imgui/" });

    exe.linkLibCpp();

    compile_all_shaders(b, exe);



    // Imgui (with cimgui and vulkan + sdl3 backends)
    const imgui_lib = b.addStaticLibrary(.{
        .name = "cimgui",
        .target = b.host,
        .optimize = optimize,
    });
    imgui_lib.addIncludePath(.{ .path = "thirdparty/imgui/" });
    imgui_lib.linkLibCpp();
    imgui_lib.linkSystemLibrary("SDL3");
    imgui_lib.linkLibC();
    imgui_lib.addCSourceFiles(.{
        .files = &.{
            "thirdparty/imgui/imgui.cpp",
            "thirdparty/imgui/imgui_demo.cpp",
            "thirdparty/imgui/imgui_draw.cpp",
            "thirdparty/imgui/imgui_tables.cpp",
            "thirdparty/imgui/imgui_widgets.cpp",
            "thirdparty/imgui/imgui_impl_sdl3.cpp",
            "thirdparty/imgui/imgui_impl_vulkan.cpp",
            "thirdparty/imgui/cimgui.cpp",
            "thirdparty/imgui/cimgui_impl_sdl3.cpp",
            "thirdparty/imgui/cimgui_impl_vulkan.cpp",
        },
    });
    exe.linkLibrary(imgui_lib);
    exe.linkLibC();

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
}

fn compile_all_shaders(b: *std.Build, exe: *std.Build.Step.Compile) void {
    // This is a fix for a change between zig 0.11 and 0.12

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
