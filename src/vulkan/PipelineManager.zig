const std = @import("std");
const c = @import("c");
const checkVkPanic = @import("errors.zig").checkVkPanic;
const DescriptorLayoutBuilder = @import("DescriptorLayoutBuilder.zig");
const PipelineBuilder = @import("PipelineBuilder.zig");

const renderformat = @import("Core.zig").renderformat;
const depthformat = @import("Core.zig").depthformat;

const Self = @This();

device: c.VkDevice,
alloc_callbacks: ?*c.VkAllocationCallbacks,

sharedpipelinelayout: c.VkPipelineLayout,
descriptorlayout: c.VkDescriptorSetLayout,

rasterpipeline: c.VkPipeline = undefined,
meshrasterpipeline: c.VkPipeline = undefined,
drawcmdpipeline: c.VkPipeline = undefined,
uipipeline: c.VkPipeline = undefined,
terrainpipeline: c.VkPipeline = undefined,

pub fn init(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    alloc_callbacks: ?*c.VkAllocationCallbacks,
) Self {
    var descriptorlayout: c.VkDescriptorSetLayout = undefined;
    {
        var builder: DescriptorLayoutBuilder = .init();
        defer builder.deinit(allocator);

        // SceneData Uniform Buffer
        builder.addBinding(allocator, 0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);

        // Shared layout: Visible to Compute, Vertex, Mesh and Fragment
        descriptorlayout = builder.build(
            device,
            c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT |
                c.VK_SHADER_STAGE_COMPUTE_BIT | c.VK_SHADER_STAGE_MESH_BIT_EXT,
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

    var pipeline_manager = Self{
        .device = device,
        .alloc_callbacks = alloc_callbacks,
        .sharedpipelinelayout = sharedpipelinelayout,
        .descriptorlayout = descriptorlayout,
    };
    // Delegate pipeline creation to their respective files
    // TODO phase this out of init and into separate application level function
    pipeline_manager.addGraphicsPipeline(@import("vertexMain"), @import("fragmentMain"));
    pipeline_manager.addMeshGraphicsPipeline(@import("meshMain"), @import("meshFragmentMain"));
    pipeline_manager.addGraphicsPipeline(@import("slugVertex"), @import("slugFragment"));
    pipeline_manager.addComputePipeline(@import("drawcmdMain"));
    pipeline_manager.addComputePipeline(@import("terrainMain"));

    return pipeline_manager;
}

pub fn deinit(self: *Self) void {
    c.vkDestroyDescriptorSetLayout(self.device, self.descriptorlayout, self.alloc_callbacks);
    c.vkDestroyPipelineLayout(self.device, self.sharedpipelinelayout, self.alloc_callbacks);
    c.vkDestroyPipeline(self.device, self.rasterpipeline, self.alloc_callbacks);
    c.vkDestroyPipeline(self.device, self.meshrasterpipeline, self.alloc_callbacks);
    c.vkDestroyPipeline(self.device, self.drawcmdpipeline, self.alloc_callbacks);
    c.vkDestroyPipeline(self.device, self.terrainpipeline, self.alloc_callbacks);
    c.vkDestroyPipeline(self.device, self.uipipeline, self.alloc_callbacks);
}

pub fn addComputePipeline(self: *Self, compute_code: anytype) void {
    var builder: PipelineBuilder = .init(self.device, self.alloc_callbacks);
    builder.addShader(.compute, compute_code);
    self.pipelines.add(builder.buildComputePipeline());
}

pub fn addGraphicsPipeline(self: *Self, vertex_code: anytype, fragment_code: anytype) void {
    var pipelineBuilder: PipelineBuilder = .init(self.device, self.alloc_callbacks);
    pipelineBuilder.addShader(.vertex, vertex_code);
    pipelineBuilder.addShader(.fragment, fragment_code);
    pipelineBuilder.setInputTopology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    // pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_FILL);
    // pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_POINT);
    pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_LINE);
    pipelineBuilder.setCullMode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_CLOCKWISE);
    pipelineBuilder.setMultisampling4();
    pipelineBuilder.disableBlending();
    pipelineBuilder.enableDepthtest(true, c.VK_COMPARE_OP_LESS);
    pipelineBuilder.setColorAttachmentFormat(renderformat);
    pipelineBuilder.setDepthFormat(depthformat);
    self.pipelines.add(pipelineBuilder.buildPipeline());
}

pub fn addMeshGraphicsPipeline(self: *Self, vertex_code: anytype, fragment_code: anytype) void {
    var pipelineBuilder: PipelineBuilder = .init(self.device, self.alloc_callbacks);
    pipelineBuilder.addShader(.mesh, vertex_code);
    pipelineBuilder.addShader(.fragment, fragment_code);
    pipelineBuilder.setInputTopology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    // pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_FILL);
    // pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_POINT);
    pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_LINE);
    pipelineBuilder.setCullMode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_CLOCKWISE);
    pipelineBuilder.setMultisampling4();
    pipelineBuilder.disableBlending();
    pipelineBuilder.enableDepthtest(true, c.VK_COMPARE_OP_LESS);
    pipelineBuilder.setColorAttachmentFormat(renderformat);
    pipelineBuilder.setDepthFormat(depthformat);
    self.pipelines.add(pipelineBuilder.buildPipeline());
}
