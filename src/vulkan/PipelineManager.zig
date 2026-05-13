// TODO rework pipeline management, use a lot of comptime

const std = @import("std");
const c = @import("c");
const checkVkPanic = @import("errors.zig").checkVkPanic;
const config = @import("config");
const DescriptorLayoutBuilder = @import("DescriptorLayoutBuilder.zig");
const PipelineBuilder = @import("PipelineBuilder.zig");
const MAX_TEXTURES = @import("BufferManager.zig").MAX_TEXTURES;

const shaders = @import("../shaders.zig");

const renderformat = @import("Core.zig").renderformat;
const depthformat = @import("Core.zig").depthformat;

const Self = @This();

device: c.VkDevice,
alloc_callbacks: ?*c.VkAllocationCallbacks,

sharedpipelinelayout: c.VkPipelineLayout,
descriptorlayout: c.VkDescriptorSetLayout, // <- Set 0
bindless_layout: c.VkDescriptorSetLayout, // <- Set 1

pipelines: [shaders.shaders.len]c.VkPipeline,

pub fn init(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    alloc_callbacks: ?*c.VkAllocationCallbacks,
) Self {
    // ========================================================================
    // 1. SceneData Layout (Set 0)
    // ========================================================================
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

    // ========================================================================
    // 2. Bindless Texture Layout (Set 1)
    // ========================================================================
    var bindless_layout: c.VkDescriptorSetLayout = undefined;
    {
        var builder: DescriptorLayoutBuilder = .init();
        defer builder.deinit(allocator);

        // Use the new array function!
        builder.addBindingArray(allocator, 0, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, MAX_TEXTURES);

        // Bindless requires these specific flags to work
        const binding_flags = c.VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT |
            c.VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT;

        var extended_info = c.VkDescriptorSetLayoutBindingFlagsCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
            .pNext = null,
            .bindingCount = 1,
            .pBindingFlags = @ptrCast(&binding_flags),
        };

        // Build it using your existing builder functions
        bindless_layout = builder.build(
            device,
            c.VK_SHADER_STAGE_FRAGMENT_BIT | c.VK_SHADER_STAGE_COMPUTE_BIT,
            &extended_info, // Passed to pNext
            c.VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT, // Passed to flags
        );
    }
    // ========================================================================
    // 3. Shared Pipeline Layout (Set 0 + Set 1)
    // ========================================================================
    const descriptorlayouts = [_]c.VkDescriptorSetLayout{ descriptorlayout, bindless_layout };
    const layoutinfo = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = 0,
        .setLayoutCount = descriptorlayouts.len, // Now contains 2 layouts
        .pSetLayouts = &descriptorlayouts,
        .pushConstantRangeCount = 0,
    };

    var sharedpipelinelayout: c.VkPipelineLayout = undefined;
    checkVkPanic(c.vkCreatePipelineLayout(device, &layoutinfo, null, &sharedpipelinelayout));

    var self = Self{
        .device = device,
        .alloc_callbacks = alloc_callbacks,
        .sharedpipelinelayout = sharedpipelinelayout,
        .descriptorlayout = descriptorlayout,
        .bindless_layout = bindless_layout,
        .pipelines = undefined,
    };

    inline for (shaders.shaders, 0..) |def, i| {
        self.pipelines[i] = switch (def) {
            .compute => |s| blk: {
                const code = comptime embedSpv("../../" ++ shaders.spv ++ s.entry ++ ".spv");
                break :blk self.buildCompute(code);
            },
            .graphics => |s| blk: {
                const vert = comptime embedSpv("../../" ++ shaders.spv ++ s.entry_vert ++ ".spv");
                const frag = comptime embedSpv("../../" ++ shaders.spv ++ s.entry_frag ++ ".spv");
                break :blk self.buildGraphics(vert, frag);
            },
            .mesh_graphics => |s| blk: {
                const mesh = comptime embedSpv("../../" ++ shaders.spv ++ s.entry_mesh ++ ".spv");
                const frag = comptime embedSpv("../../" ++ shaders.spv ++ s.entry_frag ++ ".spv");
                break :blk self.buildMeshGraphics(mesh, frag);
            },
            .ui => |s| blk: {
                const mesh = comptime embedSpv("../../" ++ shaders.spv ++ s.entry_mesh ++ ".spv");
                const frag = comptime embedSpv("../../" ++ shaders.spv ++ s.entry_frag ++ ".spv");
                break :blk self.buildUI(mesh, frag);
            },
        };
    }

    return self;
}

pub fn deinit(self: *Self) void {
    c.vkDestroyDescriptorSetLayout(self.device, self.bindless_layout, self.alloc_callbacks);
    c.vkDestroyDescriptorSetLayout(self.device, self.descriptorlayout, self.alloc_callbacks);
    c.vkDestroyPipelineLayout(self.device, self.sharedpipelinelayout, self.alloc_callbacks);
    for (self.pipelines) |pipeline| {
        c.vkDestroyPipeline(self.device, pipeline, self.alloc_callbacks);
    }
}

fn embedSpv(comptime path: []const u8) []const u32 {
    const bytes = @embedFile(path);
    comptime std.debug.assert(bytes.len % 4 == 0);
    return comptime @as([]const u32, @alignCast(std.mem.bytesAsSlice(u32, bytes)));
}

pub fn get(self: *Self, comptime name: []const u8) c.VkPipeline {
    inline for (shaders.shaders, 0..) |def, i| {
        const matches = switch (def) {
            .compute => |s| comptime std.mem.eql(u8, s.entry, name),
            .graphics => |s| comptime std.mem.eql(u8, s.entry_vert, name),
            .mesh_graphics => |s| comptime std.mem.eql(u8, s.entry_mesh, name),
            .ui => |s| comptime std.mem.eql(u8, s.entry_mesh, name),
        };
        if (matches) return self.pipelines[i];
    }
    @compileError("no pipeline named: " ++ name);
}

pub fn buildCompute(self: *Self, compute_code: []const u32) c.VkPipeline {
    var builder: PipelineBuilder = .init(self);
    builder.addShader(.compute, compute_code);
    return builder.buildComputePipeline();
}

pub fn buildGraphics(self: *Self, vertex_code: []const u32, fragment_code: []const u32) c.VkPipeline {
    var pipelineBuilder: PipelineBuilder = .init(self);
    pipelineBuilder.addShader(.vertex, vertex_code);
    pipelineBuilder.addShader(.fragment, fragment_code);
    pipelineBuilder.setInputTopology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_FILL);
    // pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_POINT);
    // pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_LINE);
    pipelineBuilder.setCullMode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_CLOCKWISE);
    pipelineBuilder.setMultisampling4();
    pipelineBuilder.disableBlending();
    pipelineBuilder.enableDepthtest(true, c.VK_COMPARE_OP_LESS);
    pipelineBuilder.setColorAttachmentFormat(renderformat);
    pipelineBuilder.setDepthFormat(depthformat);
    return pipelineBuilder.buildGraphicsPipeline();
}

pub fn buildMeshGraphics(self: *Self, vertex_code: []const u32, fragment_code: []const u32) c.VkPipeline {
    var pipelineBuilder: PipelineBuilder = .init(self);
    pipelineBuilder.addShader(.mesh, vertex_code);
    pipelineBuilder.addShader(.fragment, fragment_code);
    pipelineBuilder.setInputTopology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_FILL);
    // pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_POINT);
    // pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_LINE);
    pipelineBuilder.setCullMode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_CLOCKWISE);
    pipelineBuilder.setMultisampling4();
    pipelineBuilder.disableBlending();
    pipelineBuilder.enableDepthtest(true, c.VK_COMPARE_OP_LESS);
    pipelineBuilder.setColorAttachmentFormat(renderformat);
    pipelineBuilder.setDepthFormat(depthformat);
    return pipelineBuilder.buildGraphicsPipeline();
}

pub fn buildUI(self: *Self, vertex_code: []const u32, fragment_code: []const u32) c.VkPipeline {
    var pipelineBuilder: PipelineBuilder = .init(self);
    pipelineBuilder.addShader(.mesh, vertex_code);
    pipelineBuilder.addShader(.fragment, fragment_code);

    // CRITICAL FOR UI:
    pipelineBuilder.setInputTopology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    pipelineBuilder.enableBlendingAlpha(); // Transparent curves!
    pipelineBuilder.enableDepthtest(false, c.VK_COMPARE_OP_ALWAYS); // Draw on top of everything!

    pipelineBuilder.setInputTopology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_FILL);
    // pipelineBuilder.setPolygonMode(c.VK_POLYGON_MODE_LINE);
    pipelineBuilder.setCullMode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_CLOCKWISE);
    pipelineBuilder.setMultisampling4(); // Assuming your UI target is MSAA

    pipelineBuilder.setColorAttachmentFormat(renderformat);
    pipelineBuilder.setDepthFormat(depthformat);

    return pipelineBuilder.buildGraphicsPipeline();
}
