const engine = @import("vkEngine.zig");
const std = @import("std");
const c = @import("clibs.zig");
const t = @import("types.zig");
const vki = @import("vkUtils.zig");
const check_vk = vki.check_vk;
const log = std.log.scoped(.pipelines);

pub fn init_pipelines(self: *engine) void {
    init_background_pipelines(self);
    init_triangle_pipeline(self);
}

fn init_background_pipelines(self: *engine) void {
    var compute_layout = std.mem.zeroInit(c.VkPipelineLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &self.draw_image_descriptor_layout,
    });

    const push_constant_range = std.mem.zeroInit(c.VkPushConstantRange, .{
        .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
        .offset = 0,
        .size = @sizeOf(t.ComputePushConstants),
    });

    compute_layout.pPushConstantRanges = &push_constant_range;
    compute_layout.pushConstantRangeCount = 1;

    check_vk(c.vkCreatePipelineLayout(self.device, &compute_layout, null, &self.gradient_pipeline_layout)) catch @panic("Failed to create pipeline layout");

    const comp_code align(4) = @embedFile("gradient.comp").*;
    const comp_module = vki.create_shader_module(self.device, &comp_code, engine.vk_alloc_cbs) orelse null;
    if (comp_module != null) log.info("Created compute shader module", .{});

    const stage_ci = std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
        .module = comp_module,
        .pName = "main",
    });

    const compute_ci = std.mem.zeroInit(c.VkComputePipelineCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .layout = self.gradient_pipeline_layout,
        .stage = stage_ci,
    });

    check_vk(c.vkCreateComputePipelines(self.device, null, 1, &compute_ci, null, &self.gradient_pipeline)) catch @panic("Failed to create compute pipeline");
    c.vkDestroyShaderModule(self.device, comp_module, engine.vk_alloc_cbs);
    self.pipeline_deletion_queue.append(self.gradient_pipeline) catch @panic("Failed to append gradient pipeline to deletion queue");
    self.pipeline_layout_deletion_queue.append(self.gradient_pipeline_layout) catch @panic("Failed to append gradient pipeline layout to deletion queue");
}

fn init_triangle_pipeline(self: *engine) void {
    const vertex_code align(4) = @embedFile("triangle.vert").*;
    const fragment_code align(4) = @embedFile("triangle.frag").*;
    const vertex_module = vki.create_shader_module(self.device, &vertex_code, engine.vk_alloc_cbs) orelse null;
    const fragment_module = vki.create_shader_module(self.device, &fragment_code, engine.vk_alloc_cbs) orelse null;
    if (vertex_module != null) log.info("Created vertex shader module", .{});
    if (fragment_module != null) log.info("Created fragment shader module", .{});
    const pipeline_layput_info = std.mem.zeroInit(c.VkPipelineLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    });

    check_vk(c.vkCreatePipelineLayout(self.device, &pipeline_layput_info, null, &self.triangle_pipeline_layout)) catch @panic("Failed to create pipeline layout");
    var pipeline_builder = PipelineBuilder.init(self.cpu_allocator);
    defer pipeline_builder.deinit();
    pipeline_builder.pipeline_layout = self.triangle_pipeline_layout;
    pipeline_builder.set_shaders(vertex_module, fragment_module);
    pipeline_builder.set_input_topology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    pipeline_builder.set_polygon_mode(c.VK_POLYGON_MODE_FILL);
    pipeline_builder.set_cull_mode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_COUNTER_CLOCKWISE);
    pipeline_builder.set_multisampling_none();
    pipeline_builder.disable_blending();
    pipeline_builder.disable_depth_test();
    pipeline_builder.set_color_attachment_format(self.draw_image.format);
    pipeline_builder.set_depth_format(c.VK_FORMAT_UNDEFINED);
    self.triangle_pipeline = pipeline_builder.build_pipeline(self.device);
    c.vkDestroyShaderModule(self.device, vertex_module, engine.vk_alloc_cbs);
    c.vkDestroyShaderModule(self.device, fragment_module, engine.vk_alloc_cbs);
    self.pipeline_deletion_queue.append(self.triangle_pipeline) catch @panic("Failed to append triangle pipeline to deletion queue");
    self.pipeline_layout_deletion_queue.append(self.triangle_pipeline_layout) catch @panic("Failed to append triangle pipeline layout to deletion queue");
}

const PipelineBuilder = struct {
    shader_stages: std.ArrayList(c.VkPipelineShaderStageCreateInfo),
    input_assembly: c.VkPipelineInputAssemblyStateCreateInfo,
    rasterizer: c.VkPipelineRasterizationStateCreateInfo,
    color_blend_attachment: c.VkPipelineColorBlendAttachmentState,
    multisample: c.VkPipelineMultisampleStateCreateInfo,
    pipeline_layout: c.VkPipelineLayout,
    depth_stencil: c.VkPipelineDepthStencilStateCreateInfo,
    render_info: c.VkPipelineRenderingCreateInfo,
    color_attachment_format: c.VkFormat,

    fn init(alloc: std.mem.Allocator) PipelineBuilder {
        var builder: PipelineBuilder = .{
            .shader_stages = std.ArrayList(c.VkPipelineShaderStageCreateInfo).init(alloc),    
            .input_assembly = undefined,
            .rasterizer = undefined,
            .color_blend_attachment = undefined,
            .multisample = undefined,
            .pipeline_layout = undefined,
            .depth_stencil = undefined,
            .render_info = undefined,
            .color_attachment_format = c.VK_FORMAT_UNDEFINED,
        };
        builder.clear();
        return builder;
    }

    fn deinit(self: *PipelineBuilder) void {
        self.shader_stages.deinit();
    }

    fn clear(self: *PipelineBuilder) void {
        self.input_assembly = std.mem.zeroInit(c.VkPipelineInputAssemblyStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        });
        self.rasterizer = std.mem.zeroInit(c.VkPipelineRasterizationStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        });
        self.color_blend_attachment = std.mem.zeroInit(c.VkPipelineColorBlendAttachmentState, .{});
        self.multisample = std.mem.zeroInit(c.VkPipelineMultisampleStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        });
        self.depth_stencil = std.mem.zeroInit(c.VkPipelineDepthStencilStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        });
        self.render_info = std.mem.zeroInit(c.VkPipelineRenderingCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        });
        self.pipeline_layout = std.mem.zeroes(c.VkPipelineLayout);
        self.shader_stages.clearAndFree();
    }

    fn build_pipeline(self: *PipelineBuilder, device: c.VkDevice) c.VkPipeline {
        const viewport_state = std.mem.zeroInit(c.VkPipelineViewportStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount = 1,
        });

        const color_blending = std.mem.zeroInit(c.VkPipelineColorBlendStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .attachmentCount = 1,
            .pAttachments = &self.color_blend_attachment,
            .logicOpEnable = c.VK_FALSE,
            .logicOp = c.VK_LOGIC_OP_COPY,
        });

        const vertex_input_info = std.mem.zeroInit(c.VkPipelineVertexInputStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        });

        var pipeline_info = std.mem.zeroInit(c.VkGraphicsPipelineCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = &self.render_info,
            .stageCount = @as(u32,@intCast(self.shader_stages.items.len)),
            .pStages = self.shader_stages.items.ptr,
            .pVertexInputState = &vertex_input_info,
            .pInputAssemblyState = &self.input_assembly,
            .pViewportState = &viewport_state,
            .pRasterizationState = &self.rasterizer,
            .pMultisampleState = &self.multisample,
            .pColorBlendState = &color_blending,
            .pDepthStencilState = &self.depth_stencil,
            .layout = self.pipeline_layout,
        });

        const dynamic_state = [_]c.VkDynamicState{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
        const dynamic_state_info = std.mem.zeroInit(c.VkPipelineDynamicStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamic_state.len,
            .pDynamicStates = &dynamic_state[0]
        });

        pipeline_info.pDynamicState = &dynamic_state_info;

        var pipeline: c.VkPipeline = undefined;
        if (c.vkCreateGraphicsPipelines(device, null, 1, &pipeline_info, null, &pipeline) == c.VK_SUCCESS) {
            return pipeline;
        } else {
            log.err("Failed to create graphics pipeline", .{});
            return null;
        }
    }

    fn set_shaders(self: *PipelineBuilder, vertex: c.VkShaderModule, fragment: c.VkShaderModule) void {
        self.shader_stages.clearAndFree();
        self.shader_stages.append(std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vertex,
            .pName = "main",
        })) catch @panic("Failed to append vertex shader stage");
        self.shader_stages.append(std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = fragment,
            .pName = "main",
        })) catch @panic("Failed to append fragment shader stage");
    }

    fn set_input_topology(self: *PipelineBuilder, topology: c.VkPrimitiveTopology) void {
        self.input_assembly.topology = topology;
        self.input_assembly.primitiveRestartEnable = c.VK_FALSE;
    }

    fn set_polygon_mode(self: *PipelineBuilder, mode: c.VkPolygonMode) void {
        self.rasterizer.polygonMode = mode;
        self.rasterizer.lineWidth = 1.0;
    }

    fn set_cull_mode(self: *PipelineBuilder, mode: c.VkCullModeFlags, front_face: c.VkFrontFace) void {
        self.rasterizer.cullMode = mode;
        self.rasterizer.frontFace = front_face;
    }

    fn set_multisampling_none(self: *PipelineBuilder) void {
        self.multisample.rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT;
        self.multisample.sampleShadingEnable = c.VK_FALSE;
        self.multisample.minSampleShading = 1.0;
        self.multisample.pSampleMask = null;
        self.multisample.alphaToCoverageEnable = c.VK_FALSE;
        self.multisample.alphaToOneEnable = c.VK_FALSE;
    }

    fn disable_blending(self: *PipelineBuilder) void {
        self.color_blend_attachment.blendEnable = c.VK_FALSE;
        self.color_blend_attachment.colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT;
    }

    fn set_color_attachment_format(self: *PipelineBuilder, format: c.VkFormat) void {
        self.color_attachment_format = format;
        self.render_info.colorAttachmentCount = 1;
        self.render_info.pColorAttachmentFormats = &self.color_attachment_format;
    }

    fn set_depth_format(self: *PipelineBuilder, format: c.VkFormat) void {
        self.render_info.depthAttachmentFormat = format;
    }

    fn disable_depth_test(self: *PipelineBuilder) void {
        self.depth_stencil.depthTestEnable = c.VK_FALSE;
        self.depth_stencil.depthWriteEnable = c.VK_FALSE;
        self.depth_stencil.depthCompareOp = c.VK_COMPARE_OP_NEVER;
        self.depth_stencil.depthBoundsTestEnable = c.VK_FALSE;
        self.depth_stencil.stencilTestEnable = c.VK_FALSE;
        self.depth_stencil.minDepthBounds = 0.0;
        self.depth_stencil.maxDepthBounds = 1.0;
        self.depth_stencil.front = std.mem.zeroInit(c.VkStencilOpState, .{});
        self.depth_stencil.back = std.mem.zeroInit(c.VkStencilOpState, .{});
    }
};
