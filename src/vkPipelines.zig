const engine = @import("vkEngine.zig");
const std = @import("std");
const c = @import("clibs.zig");
const vki = @import("vkUtils.zig");
const log = @import("std.log");

fn init_pipelines(e: *engine) void {
    e.init_background_pipelines();
}

fn init_background_pipelines(e: *engine) void {
    const compute_layout = std.mem.zeroInit(c.VkPipelineLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &engine.draw_image_descriptor_layout,
    });

    vki.check_vk(c.vkCreatePipelineLayout(e.device, &compute_layout, null, &e.gradient_pipeline_layout)) catch @panic("Failed to create pipeline layout");

    const comp_code align(4) = @embedFile("gradient.comp").*;
    const comp_module = vki.create_shader_module(engine.device, &comp_code, engine.vk_alloc_cbs) orelse null;
    if (comp_module != null) log.info("Created compute shader module", .{});

    const stage_ci = std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
        .module = comp_module,
        .pName = "main",
    });

    const compute_ci = std.mem.zeroInit(c.VkComputePipelineCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .layout = engine.gradient_pipeline_layout,
        .stage = stage_ci,
    });

    vki.check_vk(c.vkCreateComputePipelines(e.device, null, 1, &compute_ci, null, &e.gradient_pipeline)) catch @panic("Failed to create compute pipeline");

    c.vkDestroyShaderModule(engine.device, comp_module, engine.vk_alloc_cbs);
}
