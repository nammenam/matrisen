const std = @import("std");
const c = @import("../clibs/clibs.zig").libs;
const defaultpipline = @import("pipelines/default.zig");
const computepipeline_mod = @import("pipelines/compute.zig"); // Import the new module
const checkVkPanic = @import("debug.zig").checkVkPanic;
const Core = @import("Core.zig");
const DescriptorLayoutBuilder = @import("DescriptorLayoutBuilder.zig");

const Self = @This();

sharedpipelinelayout: c.VkPipelineLayout,
descriptorlayout: c.VkDescriptorSetLayout,
defaultpipeline: c.VkPipeline,
computepipeline: c.VkPipeline,

pub fn init(allocator: std.mem.Allocator, device: c.VkDevice, allocationcallbacks: ?*c.VkAllocationCallbacks) Self {
    var descriptorlayout: c.VkDescriptorSetLayout = undefined;
    {
        var builder: DescriptorLayoutBuilder = .init();
        defer builder.deinit(allocator);

        // SceneData Uniform Buffer
        builder.addBinding(allocator, 0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);

        // Shared layout: Visible to Compute, Vertex, and Fragment!
        descriptorlayout = builder.build(
            device,
            c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT | c.VK_SHADER_STAGE_COMPUTE_BIT,
            null,
            0,
        );
    }

    const descriptorlayouts: [1]c.VkDescriptorSetLayout = .{descriptorlayout};
    const layoutinfo = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = 0,
        .setLayoutCount = 1,
        .pSetLayouts = &descriptorlayouts,
        .pushConstantRangeCount = 0,
    };

    var sharedpipelinelayout: c.VkPipelineLayout = undefined;
    checkVkPanic(c.vkCreatePipelineLayout(device, &layoutinfo, null, &sharedpipelinelayout));

    // Delegate pipeline creation to their respective files
    const pipeline = defaultpipline.init(device, sharedpipelinelayout, allocationcallbacks);
    const computepipe = computepipeline_mod.init(device, sharedpipelinelayout, allocationcallbacks);

    return .{
        .defaultpipeline = pipeline,
        .computepipeline = computepipe,
        .sharedpipelinelayout = sharedpipelinelayout,
        .descriptorlayout = descriptorlayout,
    };
}

pub fn deinit(self: *Self, device: c.VkDevice, allocationcallbacks: ?*c.VkAllocationCallbacks) void {
    c.vkDestroyDescriptorSetLayout(device, self.descriptorlayout, allocationcallbacks);
    c.vkDestroyPipelineLayout(device, self.sharedpipelinelayout, allocationcallbacks);
    c.vkDestroyPipeline(device, self.defaultpipeline, allocationcallbacks);
    c.vkDestroyPipeline(device, self.computepipeline, allocationcallbacks);
}
