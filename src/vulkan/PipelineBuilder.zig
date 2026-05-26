const std = @import("std");
const c = @import("c");
const errors = @import("errors.zig");
const checkVkPanic = errors.checkVkPanic;
const Core = @import("Core.zig");
const PipelineManager = @import("PipelineManager.zig");

pub const PolygonMode = enum(c_int) {
    fill = c.VK_POLYGON_MODE_FILL,
    line = c.VK_POLYGON_MODE_LINE,
    point = c.VK_POLYGON_MODE_POINT,
};

pub const Stage = enum { vertex, fragment, mesh, compute };

const MAX_STAGES = 2;

const Self = @This();

device: c.VkDevice,
alloc_callbacks: ?*c.VkAllocationCallbacks,

layout: c.VkPipelineLayout,
topology: c_int = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
polygon_mode: c_int = c.VK_POLYGON_MODE_FILL,
cull_mode: c_int = c.VK_CULL_MODE_NONE,
front_face: c_int = c.VK_FRONT_FACE_CLOCKWISE,
stage_count: usize,
shader_stages: [MAX_STAGES]c.VkPipelineShaderStageCreateInfo,
input_assembly: c.VkPipelineInputAssemblyStateCreateInfo,
rasterizer: c.VkPipelineRasterizationStateCreateInfo,
color_blend_attachment: c.VkPipelineColorBlendAttachmentState,
multisample: c.VkPipelineMultisampleStateCreateInfo,
depth_stencil: c.VkPipelineDepthStencilStateCreateInfo,
render_info: c.VkPipelineRenderingCreateInfo,
color_attachment_format: c.VkFormat,

pub fn init(pipeline_manager: *PipelineManager) Self {
    var builder: Self = .{
        .alloc_callbacks = pipeline_manager.alloc_callbacks,
        .device = pipeline_manager.device,
        .shader_stages = @splat(.{}),
        .input_assembly = undefined,
        .rasterizer = undefined,
        .color_blend_attachment = undefined,
        .multisample = undefined,
        .depth_stencil = undefined,
        .render_info = undefined,
        .color_attachment_format = c.VK_FORMAT_UNDEFINED,
        .layout = pipeline_manager.sharedpipelinelayout,
        .stage_count = 0,
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
    code: []const u32,
    alloc_callback: ?*c.VkAllocationCallbacks,
) ?c.VkShaderModule {
    // std.debug.assert(code.len % 4 == 0);

    const shader_module_ci: c.VkShaderModuleCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len * @sizeOf(u32),
        .pCode = code.ptr,
    };

    var shader_module: c.VkShaderModule = undefined;
    errors.checkVkPanic(c.vkCreateShaderModule(device, &shader_module_ci, alloc_callback, &shader_module));
    return shader_module;
}

pub fn addShader(self: *Self, stage: Stage, shader_code: []const u32) void {
    const shader_mod = createShaderModule(self.device, shader_code, self.alloc_callbacks) orelse null;

    var stage_info: c.VkPipelineShaderStageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .module = shader_mod,
        .pName = "main",
    };
    switch (stage) {
        .compute => stage_info.stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
        .vertex => stage_info.stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .fragment => stage_info.stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .mesh => stage_info.stage = c.VK_SHADER_STAGE_MESH_BIT_EXT,
    }
    self.shader_stages[self.stage_count] = stage_info;
    self.stage_count += 1;
}

pub fn buildGraphicsPipeline(self: *Self) c.VkPipeline {
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
        .pStages = &self.shader_stages,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &self.input_assembly,
        .pViewportState = &viewport_state,
        .pRasterizationState = &self.rasterizer,
        .pMultisampleState = &self.multisample,
        .pColorBlendState = &color_blending,
        .pDepthStencilState = &self.depth_stencil,
        .layout = self.layout,
    };

    const dynamic_state = [_]c.VkDynamicState{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
    const dynamic_state_info: c.VkPipelineDynamicStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamic_state.len,
        .pDynamicStates = &dynamic_state[0],
    };

    pipeline_info.pDynamicState = &dynamic_state_info;

    var pipeline: c.VkPipeline = undefined;
    const result = c.vkCreateGraphicsPipelines(self.device, null, 1, &pipeline_info, null, &pipeline);

    for (self.shader_stages[0..self.stage_count]) |stage| {
        c.vkDestroyShaderModule(self.device, stage.module, self.alloc_callbacks);
    }

    if (result == c.VK_SUCCESS) {
        return pipeline;
    } else {
        return null;
    }
}

pub fn buildComputePipeline(self: *Self) c.VkPipeline {
    const pipeline_info = c.VkComputePipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = self.shader_stages[0],
        .layout = self.layout,
    };

    var pipeline: c.VkPipeline = undefined;
    const result = c.vkCreateComputePipelines(self.device, null, 1, &pipeline_info, null, &pipeline);

    for (self.shader_stages[0..self.stage_count]) |stage| {
        c.vkDestroyShaderModule(self.device, stage.module, self.alloc_callbacks);
    }

    if (result == c.VK_SUCCESS) {
        return pipeline;
    } else {
        return null;
    }
}
