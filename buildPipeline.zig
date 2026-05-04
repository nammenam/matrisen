const std = @import("std");

pub const Blending = enum { disable, additive, alpha };
pub const Multisampling = enum { none, msam4 };

pub const PipelineDef = struct {
    name: []const u8,
    shader_filename: []const u8,

    vertex: ?[]const u8 = null,
    fragment: ?[]const u8 = null,
    mesh: ?[]const u8 = null,
    compute: ?[]const u8 = null,

    topology: []const u8 = "c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST",
    polygon_mode: []const u8 = "c.VK_POLYGON_MODE_FILL",
    cull_mode: []const u8 = "c.VK_CULL_MODE_NONE",
    front_face: []const u8 = "c.VK_FRONT_FACE_CLOCKWISE",

    multisampling: Multisampling = .msam4,
    blending: Blending = .disable,

    depth_test: bool = true,
    depth_write: bool = true,
    depth_op: []const u8 = "c.VK_COMPARE_OP_LESS",
};

fn compileSlang(
    b: *std.Build,
    shaders_step: *std.Build.Step,
    shaderpath: []const u8,
    filename: []const u8,
    entry: []const u8,
    stage: []const u8,
) *std.Build.Module {
    const shader_src = b.path(b.fmt("{s}/{s}", .{ shaderpath, filename }));

    const cmd = b.addSystemCommand(&.{"slangc"});
    cmd.addFileArg(shader_src);
    cmd.addArgs(&.{ "-target", "spirv", "-fvk-use-scalar-layout" });
    cmd.addArgs(&.{ "-entry", entry, "-stage", stage });
    cmd.addArg("-o");

    const spv_filename = b.fmt("{s}.spv", .{entry});
    const spv_output = cmd.addOutputFileArg(spv_filename);
    shaders_step.dependOn(&cmd.step);

    const gen = b.addWriteFiles();
    _ = gen.addCopyFile(spv_output, spv_filename);
    _ = gen.add(
        b.fmt("{s}_module.zig", .{entry}),
        b.fmt(
            \\const std = @import("std");
            \\const content align(4) = @embedFile("{s}").*;
            \\pub const code_u8 = std.mem.bytesAsSlice(u8, &content);
        , .{spv_filename}),
    );

    return b.createModule(.{
        .root_source_file = gen.getDirectory().path(b, b.fmt("{s}_module.zig", .{entry})),
    });
}
pub fn addPipeline(
    b: *std.Build,
    matrisen: *std.Build.Module,
    shaders_step: *std.Build.Step,
    shaderpath: []const u8,
    def: PipelineDef,
) void {
    var zig: std.ArrayListUnmanaged(u8) = .empty;
    defer zig.deinit(b.allocator);
    const writer = zig.writer(b.allocator);

    writer.print(
        \\const root = @import("matrisen");
        \\const c = root.clibs;
        \\const PipelineBuilder = root.PipelineBuilder;
        \\const Core = root.Core;
        \\
    , .{}) catch @panic("OOM");

    if (def.vertex) |v| writer.print("const vs_code = @import(\"{s}_module\").code_u8;\n", .{v}) catch @panic("OOM");
    if (def.fragment) |f| writer.print("const fs_code = @import(\"{s}_module\").code_u8;\n", .{f}) catch @panic("OOM");
    if (def.mesh) |m| writer.print("const ms_code = @import(\"{s}_module\").code_u8;\n", .{m}) catch @panic("OOM");
    if (def.compute) |cs| writer.print("const cs_code = @import(\"{s}_module\").code_u8;\n", .{cs}) catch @panic("OOM");

    writer.print(
        \\
        \\pub fn init(
        \\    device: c.VkDevice,
        \\    pipelinelayout: c.VkPipelineLayout,
        \\    alloc: ?*c.VkAllocationCallbacks,
        \\) c.VkPipeline {{
        \\
    , .{}) catch @panic("OOM");

    if (def.compute) |_| {
        writer.print(
            \\    const cs_mod = PipelineBuilder.createShaderModule(device, cs_code, alloc) orelse null;
            \\    defer c.vkDestroyShaderModule(device, cs_mod, alloc);
            \\    const stage: c.VkPipelineShaderStageCreateInfo = .{{
            \\        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            \\        .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
            \\        .module = cs_mod,
            \\        .pName = "main",
            \\    }};
            \\    var info: c.VkComputePipelineCreateInfo = .{{
            \\        .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
            \\        .stage = stage,
            \\        .layout = pipelinelayout,
            \\    }};
            \\    var pipeline: c.VkPipeline = undefined;
            \\    _ = c.vkCreateComputePipelines(device, null, 1, &info, alloc, &pipeline);
            \\    return pipeline;
            \\}}
        , .{}) catch @panic("OOM");
    } else {
        const stage_count =
            (if (def.vertex != null) @as(u32, 1) else 0) +
            (if (def.fragment != null) @as(u32, 1) else 0) +
            (if (def.mesh != null) @as(u32, 1) else 0);

        writer.print(
            \\    var builder: PipelineBuilder = .init();
            \\
            \\    var stages: [{d}]c.VkPipelineShaderStageCreateInfo = undefined;
            \\    var stage_count: usize = 0;
            \\
        , .{stage_count}) catch @panic("OOM");

        if (def.vertex) |_| {
            writer.print(
                \\    const vs_mod = PipelineBuilder.createShaderModule(device, vs_code, alloc) orelse null;
                \\    defer c.vkDestroyShaderModule(device, vs_mod, alloc);
                \\    stages[stage_count] = .{{
                \\        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                \\        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
                \\        .module = vs_mod,
                \\        .pName = "main",
                \\    }};
                \\    stage_count += 1;
                \\
            , .{}) catch @panic("OOM");
        }
        if (def.mesh) |_| {
            writer.print(
                \\    const ms_mod = PipelineBuilder.createShaderModule(device, ms_code, alloc) orelse null;
                \\    defer c.vkDestroyShaderModule(device, ms_mod, alloc);
                \\    stages[stage_count] = .{{
                \\        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                \\        .stage = c.VK_SHADER_STAGE_MESH_BIT_EXT,
                \\        .module = ms_mod,
                \\        .pName = "main",
                \\    }};
                \\    stage_count += 1;
                \\
            , .{}) catch @panic("OOM");
        }
        if (def.fragment) |_| {
            writer.print(
                \\    const fs_mod = PipelineBuilder.createShaderModule(device, fs_code, alloc) orelse null;
                \\    defer c.vkDestroyShaderModule(device, fs_mod, alloc);
                \\    stages[stage_count] = .{{
                \\        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                \\        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                \\        .module = fs_mod,
                \\        .pName = "main",
                \\    }};
                \\    stage_count += 1;
                \\
            , .{}) catch @panic("OOM");
        }

        writer.print(
            \\    builder.shader_stages = stages[0..stage_count];
            \\    builder.setInputTopology({s});
            \\    builder.setPolygonMode({s});
            \\    builder.setCullMode({s}, {s});
            \\    builder.setColorAttachmentFormat(Core.renderformat);
            \\    builder.setDepthFormat(Core.depthformat);
            \\
        , .{ def.topology, def.polygon_mode, def.cull_mode, def.front_face }) catch @panic("OOM");

        switch (def.multisampling) {
            .none => writer.print("    builder.setMultisamplingNone();\n", .{}) catch @panic("OOM"),
            .msam4 => writer.print("    builder.setMultisampling4();\n", .{}) catch @panic("OOM"),
        }
        switch (def.blending) {
            .disable => writer.print("    builder.disableBlending();\n", .{}) catch @panic("OOM"),
            .additive => writer.print("    builder.enableBlendingAdditive();\n", .{}) catch @panic("OOM"),
            .alpha => writer.print("    builder.enableBlendingAlpha();\n", .{}) catch @panic("OOM"),
        }
        if (def.depth_test) {
            writer.print("    builder.enableDepthtest({s}, {s});\n", .{
                if (def.depth_write) "true" else "false",
                def.depth_op,
            }) catch @panic("OOM");
        } else {
            writer.print("    builder.disableDepthtest();\n", .{}) catch @panic("OOM");
        }

        writer.print("    return builder.buildPipeline(device, pipelinelayout);\n}}\n", .{}) catch @panic("OOM");
    }

    const gen = b.addWriteFiles();
    const generated_file = gen.add(b.fmt("{s}_pipeline.zig", .{def.name}), zig.items);
    const pipeline_mod = b.createModule(.{ .root_source_file = generated_file });

    // Fix: inject matrisen so generated code can @import("matrisen")
    pipeline_mod.addImport("matrisen", matrisen);

    // Fix: reuse cached shader modules to avoid duplicate SPIRV compilation
    if (def.vertex) |v| pipeline_mod.addImport(
        b.fmt("{s}_module", .{v}),
        compileSlang(b, shaders_step, shaderpath, def.shader_filename, v, "vertex"),
    );
    if (def.fragment) |f| pipeline_mod.addImport(
        b.fmt("{s}_module", .{f}),
        compileSlang(b, shaders_step, shaderpath, def.shader_filename, f, "fragment"),
    );
    if (def.mesh) |m| pipeline_mod.addImport(
        b.fmt("{s}_module", .{m}),
        compileSlang(b, shaders_step, shaderpath, def.shader_filename, m, "mesh"),
    );
    if (def.compute) |cs| pipeline_mod.addImport(
        b.fmt("{s}_module", .{cs}),
        compileSlang(b, shaders_step, shaderpath, def.shader_filename, cs, "compute"),
    );

    matrisen.addImport(def.name, pipeline_mod);
}
