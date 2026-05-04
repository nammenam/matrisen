const std = @import("std");
const log = std.log.scoped(.build);
const Build = std.Build;
const builtin = @import("builtin");
const pipelinegen = @import("buildPipeline.zig");

const shaderpath = "src/example/shaders";

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
    matrisen.addOptions("config", options);

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

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // --- SLANG SHADER COMPILATION ---
    // the shaders gets compiled and wrapped in a pipeline builder at build time
    // the result is a module residing in the .zig-cache that can be imported to the
    // pipeline manager only having to change one source file ( + this one) for adding new shaders
    const shaders_step = b.step("shaders", "Compile Slang shaders");

    // 1. The Draw/Culling Compute Pipeline
    pipelinegen.addPipeline(b, matrisen, shaders_step, shaderpath, .{
        .name = "drawcmdpipeline",
        .shader_filename = "drawcmd.slang",
        .compute = "drawcmdMain",
        .meshshading = enable_meshshading,
    });

    // 2. The Default 3D Pipeline (Vertex + Fragment)
    pipelinegen.addPipeline(b, matrisen, shaders_step, shaderpath, .{
        .name = "rasterpipeline",
        .shader_filename = "rastermain.slang",
        .vertex = "vertexMain",
        .fragment = "fragmentMain",
        // .polygon_mode = "c.VK_POLYGON_MODE_LINE", // Wireframe!
        .polygon_mode = "c.VK_POLYGON_MODE_FILL", // Solid!
        .depth_test = true,
        .multisampling = .msam4,
    });

    // 3. The New Mesh Shader Pipeline!
    pipelinegen.addPipeline(b, matrisen, shaders_step, shaderpath, .{
        .name = "rasterpipeline_mesh",
        .shader_filename = "rastermain_mesh.slang",
        .mesh = "meshMain",
        .fragment = "fragmentMain",
        .polygon_mode = "c.VK_POLYGON_MODE_FILL",
        .depth_test = true,
        .multisampling = .msam4,
        .meshshading = enable_meshshading,
    });

    pipelinegen.addPipeline(b, matrisen, shaders_step, shaderpath, .{
        .name = "terrainpipeline",
        .shader_filename = "terrain.slang", // whatever your shader file is called
        .compute = "terrainMain", // whatever your entry point is called
    });
    // 4. Slug Text Pipeline
    pipelinegen.addPipeline(b, matrisen, shaders_step, shaderpath, .{
        .name = "vectorgfxpipeline",
        .shader_filename = "vectorgfx.slang",
        .vertex = "slugVertex",
        .fragment = "slugFragment",
        .cull_mode = "c.VK_CULL_MODE_NONE",
        .blending = .alpha, // Slug usually needs alpha blending
        .depth_test = false,
    });
}
