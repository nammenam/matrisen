const std = @import("std");
const log = std.log.scoped(.defaultpipeline);
const c = @import("../../clibs/clibs.zig").libs;
const PipelineBuilder = @import("../PipelineBuilder.zig");
const Core = @import("../Core.zig");

pub fn init(
    device: c.VkDevice,
    pipelinelayout: c.VkPipelineLayout,
    allocationcallbacks: ?*c.VkAllocationCallbacks,
) c.VkPipeline {
    // Import the Slang modules generated in build.zig
    const vertex_code = @import("vertexMain").code_u8;
    const fragment_code = @import("fragmentMain").code_u8;

    const vertex_module = PipelineBuilder.createShaderModule(
        device,
        vertex_code,
        allocationcallbacks,
    ) orelse null;
    const fragment_module = PipelineBuilder.createShaderModule(
        device,
        fragment_code,
        allocationcallbacks,
    ) orelse null;

    if (vertex_module != null) log.info("Created vertex shader module", .{});
    if (fragment_module != null) log.info("Created fragment shader module", .{});

    defer c.vkDestroyShaderModule(device, vertex_module, allocationcallbacks);
    defer c.vkDestroyShaderModule(device, fragment_module, allocationcallbacks);

    const vertex: c.VkPipelineShaderStageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vertex_module,
        .pName = "main",
    };
    const fragment: c.VkPipelineShaderStageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragment_module,
        .pName = "main",
    };

    var shaders: [2]c.VkPipelineShaderStageCreateInfo = .{ vertex, fragment };
    var pipelineBuilder: PipelineBuilder = .init();
    pipelineBuilder.shader_stages = &shaders;
    pipelineBuilder.setInputTopology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    // pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_FILL);
    pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_LINE);
    pipelineBuilder.setCullMode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_CLOCKWISE);
    pipelineBuilder.setMultisampling4();
    pipelineBuilder.disableBlending();
    pipelineBuilder.enableDepthtest(true, c.VK_COMPARE_OP_LESS);
    pipelineBuilder.setColorAttachmentFormat(Core.renderformat);
    pipelineBuilder.setDepthFormat(Core.depthformat);

    return pipelineBuilder.buildPipeline(device, pipelinelayout);
}
