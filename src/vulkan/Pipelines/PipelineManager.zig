const std = @import("std");
const c = @import("../clibs/clibs.zig").libs;
const checkVkPanic = @import("debug.zig").checkVkPanic;
const DescriptorLayoutBuilder = @import("DescriptorLayoutBuilder.zig");

const Self = @This();

sharedpipelinelayout: c.VkPipelineLayout,
descriptorlayout: c.VkDescriptorSetLayout,

rasterpipeline: c.VkPipeline,
meshrasterpipeline: c.VkPipeline,
drawcmdpipeline: c.VkPipeline,
uipipeline: c.VkPipeline,
terrainpipeline: c.VkPipeline,

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
            c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT | c.VK_SHADER_STAGE_COMPUTE_BIT |
                c.VK_SHADER_STAGE_MESH_BIT_EXT,
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

    const vertexMain align(4) = @embedFile(@import("vertexMain")).*;
    const fragmentMain align(4) = @embedFile(@import("fragmentMain")).*;
    const meshMain align(4) = @embedFile(@import("meshMain")).*;
    // const fragmentMain align(4) = @embedFile(@import("fragmentMain")).*;
    const drawcmdMain align(4) = @embedFile(@import("drawcmdMain")).*;
    const terrainMain align(4) = @embedFile(@import("terrainMain")).*;
    const slugVertex align(4) = @embedFile(@import("slugVertex")).*;
    const slugMesh align(4) = @embedFile(@import("slugMesh")).*;
    const slugFragment align(4) = @embedFile(@import("slugFragment")).*;

    // Delegate pipeline creation to their respective files
    const rasterpipeline = Rasterpipeline.init(device, sharedpipelinelayout, allocationcallbacks);
    const meshrasterpipeline = Meshrasterpipeline.init(device, sharedpipelinelayout, allocationcallbacks);
    const drawcmdpipeline = Drawcmdpipeline.init(device, sharedpipelinelayout, allocationcallbacks);
    const terrainpipeline = Terrainpipeline.init(device, sharedpipelinelayout, allocationcallbacks);
    const uipipeline = UIpipeline.init(device, sharedpipelinelayout, allocationcallbacks);

    return .{
        .rasterpipeline = rasterpipeline,
        .meshrasterpipeline = meshrasterpipeline,
        .drawcmdpipeline = drawcmdpipeline,
        .terrainpipeline = terrainpipeline,
        .uipipeline = uipipeline,
        .sharedpipelinelayout = sharedpipelinelayout,
        .descriptorlayout = descriptorlayout,
    };
}

pub fn deinit(self: *Self, device: c.VkDevice, allocationcallbacks: ?*c.VkAllocationCallbacks) void {
    c.vkDestroyDescriptorSetLayout(device, self.descriptorlayout, allocationcallbacks);
    c.vkDestroyPipelineLayout(device, self.sharedpipelinelayout, allocationcallbacks);
    c.vkDestroyPipeline(device, self.rasterpipeline, allocationcallbacks);
    c.vkDestroyPipeline(device, self.meshrasterpipeline, allocationcallbacks);
    c.vkDestroyPipeline(device, self.drawcmdpipeline, allocationcallbacks);
    c.vkDestroyPipeline(device, self.terrainpipeline, allocationcallbacks);
}
