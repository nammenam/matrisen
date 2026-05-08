const std = @import("std");
const c = @import("../clibs/clibs.zig").libs;
const debug = @import("debug.zig");
const checkVkPanic = debug.checkVkPanic;
const linalg = @import("../linalg.zig");
const Core = @import("Core.zig");

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
    meshshading: bool = false,
};

const Self = @This();

shader_stages: []c.VkPipelineShaderStageCreateInfo,
input_assembly: c.VkPipelineInputAssemblyStateCreateInfo,
rasterizer: c.VkPipelineRasterizationStateCreateInfo,
color_blend_attachment: c.VkPipelineColorBlendAttachmentState,
multisample: c.VkPipelineMultisampleStateCreateInfo,
depth_stencil: c.VkPipelineDepthStencilStateCreateInfo,
render_info: c.VkPipelineRenderingCreateInfo,
color_attachment_format: c.VkFormat,

pub fn init() Self {
    var builder: Self = .{
        .shader_stages = &.{},
        .input_assembly = undefined,
        .rasterizer = undefined,
        .color_blend_attachment = undefined,
        .multisample = undefined,
        .depth_stencil = undefined,
        .render_info = undefined,
        .color_attachment_format = c.VK_FORMAT_UNDEFINED,
    };
    builder.clear();
    return builder;
}

fn clear(self: *Self) void {
    self.input_assembly = .{ .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO };
    self.rasterizer = .{ .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO };
    self.color_blend_attachment = .{};
    self.multisample = .{ .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO };
    self.depth_stencil = .{ .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO };
    self.render_info = .{ .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO };
}

pub fn buildPipeline(self: *Self, device: c.VkDevice, layout: c.VkPipelineLayout) c.VkPipeline {
    const viewport_state: c.VkPipelineViewportStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };

    const color_blending: c.VkPipelineColorBlendStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &self.color_blend_attachment,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
    };

    const vertex_input_info: c.VkPipelineVertexInputStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    };

    var pipeline_info: c.VkGraphicsPipelineCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = &self.render_info,
        .stageCount = @as(u32, @intCast(self.shader_stages.len)),
        .pStages = self.shader_stages.ptr,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &self.input_assembly,
        .pViewportState = &viewport_state,
        .pRasterizationState = &self.rasterizer,
        .pMultisampleState = &self.multisample,
        .pColorBlendState = &color_blending,
        .pDepthStencilState = &self.depth_stencil,
        .layout = layout,
    };

    const dynamic_state = [_]c.VkDynamicState{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
    const dynamic_state_info: c.VkPipelineDynamicStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamic_state.len,
        .pDynamicStates = &dynamic_state[0],
    };

    pipeline_info.pDynamicState = &dynamic_state_info;

    var pipeline: c.VkPipeline = undefined;
    if (c.vkCreateGraphicsPipelines(device, null, 1, &pipeline_info, null, &pipeline) == c.VK_SUCCESS) {
        return pipeline;
    } else {
        return null;
    }
}

pub fn setInputTopology(self: *Self, topology: c.VkPrimitiveTopology) void {
    self.input_assembly.topology = topology;
    self.input_assembly.primitiveRestartEnable = c.VK_FALSE;
}

pub fn setPolygonMode(self: *Self, mode: c.VkPolygonMode) void {
    self.rasterizer.polygonMode = mode;
    self.rasterizer.lineWidth = 1.0;
}

pub fn setCullMode(self: *Self, mode: c.VkCullModeFlags, front_face: c.VkFrontFace) void {
    self.rasterizer.cullMode = mode;
    self.rasterizer.frontFace = front_face;
}

pub fn setMultisamplingNone(self: *Self) void {
    self.multisample.rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT;
    self.multisample.sampleShadingEnable = c.VK_FALSE;
    self.multisample.minSampleShading = 1.0;
    self.multisample.pSampleMask = null;
    self.multisample.alphaToCoverageEnable = c.VK_FALSE;
    self.multisample.alphaToOneEnable = c.VK_FALSE;
}

pub fn setMultisampling4(self: *Self) void {
    self.multisample.rasterizationSamples = c.VK_SAMPLE_COUNT_4_BIT;
    self.multisample.sampleShadingEnable = c.VK_FALSE;
    self.multisample.minSampleShading = 1.0;
    self.multisample.pSampleMask = null;
    self.multisample.alphaToCoverageEnable = c.VK_FALSE;
    self.multisample.alphaToOneEnable = c.VK_FALSE;
}

pub fn disableBlending(self: *Self) void {
    self.color_blend_attachment.blendEnable = c.VK_FALSE;
    self.color_blend_attachment.colorWriteMask =
        c.VK_COLOR_COMPONENT_R_BIT |
        c.VK_COLOR_COMPONENT_G_BIT |
        c.VK_COLOR_COMPONENT_B_BIT |
        c.VK_COLOR_COMPONENT_A_BIT;
}

pub fn setColorAttachmentFormat(self: *Self, format: c.VkFormat) void {
    self.color_attachment_format = format;
    self.render_info.colorAttachmentCount = 1;
    self.render_info.pColorAttachmentFormats = &self.color_attachment_format;
}

pub fn setDepthFormat(self: *Self, format: c.VkFormat) void {
    self.render_info.depthAttachmentFormat = format;
}

pub fn disableDepthtest(self: *Self) void {
    self.depth_stencil.depthTestEnable = c.VK_FALSE;
    self.depth_stencil.depthWriteEnable = c.VK_FALSE;
    self.depth_stencil.depthCompareOp = c.VK_COMPARE_OP_NEVER;
    self.depth_stencil.depthBoundsTestEnable = c.VK_FALSE;
    self.depth_stencil.stencilTestEnable = c.VK_FALSE;
    self.depth_stencil.minDepthBounds = 0.0;
    self.depth_stencil.maxDepthBounds = 1.0;
    self.depth_stencil.front = .{};
    self.depth_stencil.back = .{};
}

pub fn enableDepthtest(self: *Self, depthwrite_enable: bool, op: c.VkCompareOp) void {
    self.depth_stencil.depthTestEnable = c.VK_TRUE;
    self.depth_stencil.depthWriteEnable = if (depthwrite_enable) c.VK_TRUE else c.VK_FALSE;
    self.depth_stencil.depthCompareOp = op;
    self.depth_stencil.depthBoundsTestEnable = c.VK_FALSE;
    self.depth_stencil.stencilTestEnable = c.VK_FALSE;
    self.depth_stencil.minDepthBounds = 0.0;
    self.depth_stencil.maxDepthBounds = 1.0;
    self.depth_stencil.front = .{};
    self.depth_stencil.back = .{};
}

pub fn enableBlendingAdditive(self: *Self) void {
    self.color_blend_attachment.blendEnable = c.VK_TRUE;
    self.color_blend_attachment.srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA;
    self.color_blend_attachment.dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE;
    self.color_blend_attachment.colorBlendOp = c.VK_BLEND_OP_ADD;
    self.color_blend_attachment.srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE;
    self.color_blend_attachment.dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO;
    self.color_blend_attachment.alphaBlendOp = c.VK_BLEND_OP_ADD;
    self.color_blend_attachment.colorWriteMask =
        c.VK_COLOR_COMPONENT_R_BIT |
        c.VK_COLOR_COMPONENT_G_BIT |
        c.VK_COLOR_COMPONENT_B_BIT |
        c.VK_COLOR_COMPONENT_A_BIT;
}

pub fn enableBlendingAlpha(self: *Self) void {
    self.color_blend_attachment.blendEnable = c.VK_TRUE;
    self.color_blend_attachment.srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA;
    self.color_blend_attachment.dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    self.color_blend_attachment.colorBlendOp = c.VK_BLEND_OP_ADD;
    self.color_blend_attachment.srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE;
    self.color_blend_attachment.dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO;
    self.color_blend_attachment.alphaBlendOp = c.VK_BLEND_OP_ADD;
    self.color_blend_attachment.colorWriteMask =
        c.VK_COLOR_COMPONENT_R_BIT |
        c.VK_COLOR_COMPONENT_G_BIT |
        c.VK_COLOR_COMPONENT_B_BIT |
        c.VK_COLOR_COMPONENT_A_BIT;
}
pub fn createShaderModule(
    device: c.VkDevice,
    code: []const u8,
    alloc_callback: ?*c.VkAllocationCallbacks,
) ?c.VkShaderModule {
    std.debug.assert(code.len % 4 == 0);

    const data: *const u32 = @ptrCast(@alignCast(code.ptr));

    const shader_module_ci: c.VkShaderModuleCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len,
        .pCode = data,
    };

    var shader_module: c.VkShaderModule = undefined;
    debug.checkVkPanic(c.vkCreateShaderModule(device, &shader_module_ci, alloc_callback, &shader_module));
    return shader_module;
}
const std = @import("std");

\\const std = @import("std");
\\const content align(4) = @embedFile("{s}").*;
\\pub const code_u8 = std.mem.bytesAsSlice(u8, &content);


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

    if (def.vertex) |v| pipeline_mod.addImport(
        b.fmt("{s}_module", .{v}),
        compileSlang(b, shaders_step, shaderpath, def.shader_filename, v, "vertex", def.meshshading),
    );
    if (def.fragment) |f| pipeline_mod.addImport(
        b.fmt("{s}_module", .{f}),
        compileSlang(b, shaders_step, shaderpath, def.shader_filename, f, "fragment", def.meshshading),
    );
    if (def.mesh) |m| pipeline_mod.addImport(
        b.fmt("{s}_module", .{m}),
        compileSlang(b, shaders_step, shaderpath, def.shader_filename, m, "mesh", def.meshshading),
    );
    if (def.compute) |cs| pipeline_mod.addImport(
        b.fmt("{s}_module", .{cs}),
        compileSlang(b, shaders_step, shaderpath, def.shader_filename, cs, "compute", def.meshshading),
    );

    matrisen.addImport(def.name, pipeline_mod);
}

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
