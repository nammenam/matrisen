const std = @import("std");
const log = std.log.scoped(.computepipeline);
const c = @import("../../clibs/clibs.zig").libs;
const checkVkPanic = @import("../debug.zig").checkVkPanic;
const PipelineBuilder = @import("../PipelineBuilder.zig");

pub fn init(
    device: c.VkDevice,
    pipelinelayout: c.VkPipelineLayout,
    allocationcallbacks: ?*c.VkAllocationCallbacks,
) c.VkPipeline {
    // Import the Slang module generated in build.zig
    const compute_code = @import("drawMain").code_u8;

    const compute_module = PipelineBuilder.createShaderModule(
        device,
        compute_code,
        allocationcallbacks,
    ) orelse @panic("Failed to create compute shader module");

    log.info("Created compute shader module", .{});
    defer c.vkDestroyShaderModule(device, compute_module, allocationcallbacks);

    const shader_stage = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
        .module = compute_module,
        .pName = "main", // Must match your Slang entry point!
    };

    const compute_info = c.VkComputePipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = shader_stage,
        .layout = pipelinelayout,
    };

    var pipeline: c.VkPipeline = undefined;
    checkVkPanic(c.vkCreateComputePipelines(device, null, 1, &compute_info, allocationcallbacks, &pipeline));

    return pipeline;
}
