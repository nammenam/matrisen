const m3d = @import("math3d.zig");
const c = @import("clibs.zig");
const std = @import("std");

const Vec2 = m3d.Vec2;
const Vec3 = m3d.Vec3;

pub const Vertex = struct {
    position: Vec3,
    normal: Vec3,
    color: Vec3,
    uv: Vec2,

    pub const vertex_input_description = VertexInputDescription{
        .bindings = &.{
            std.mem.zeroInit(c.VkVertexInputBindingDescription, .{
                .binding = 0,
                .stride = @sizeOf(Vertex),
                .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
            }),
        },
        .attributes = &.{
            std.mem.zeroInit(c.VkVertexInputAttributeDescription, .{
                .location = 0,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "position"),
            }),
            std.mem.zeroInit(c.VkVertexInputAttributeDescription, .{
                .location = 1,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "normal"),
            }),
            std.mem.zeroInit(c.VkVertexInputAttributeDescription, .{
                .location = 2,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "color"),
            }),
            std.mem.zeroInit(c.VkVertexInputAttributeDescription, .{
                .location = 3,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(Vertex, "uv"),
            }),
        },
    };
};


pub const VertexInputDescription = struct {
    bindings: []const c.VkVertexInputBindingDescription,
    attributes: []const c.VkVertexInputAttributeDescription,
    flags: c.VkPipelineVertexInputStateCreateFlags = 0,
};




fn init_default_renderpass(self: *Self) void {
    // Color attachement
    const color_attachment = std.mem.zeroInit(c.VkAttachmentDescription, .{
        .format = self.swapchain_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    });

    const color_attachment_ref = std.mem.zeroInit(c.VkAttachmentReference, .{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    });

    // Depth attachment
    const depth_attachment = std.mem.zeroInit(c.VkAttachmentDescription, .{
        .format = self.depth_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    });

    const depth_attachement_ref = std.mem.zeroInit(c.VkAttachmentReference, .{
        .attachment = 1,
        .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    });

    // Subpass
    const subpass = std.mem.zeroInit(c.VkSubpassDescription, .{
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_ref,
        .pDepthStencilAttachment = &depth_attachement_ref,
    });

    const attachment_descriptions = [_]c.VkAttachmentDescription{
        color_attachment,
        depth_attachment,
    };

    // Subpass color and depth depencies
    const color_dependency = std.mem.zeroInit(c.VkSubpassDependency, .{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    });

    const depth_dependency = std.mem.zeroInit(c.VkSubpassDependency, .{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        .srcAccessMask = c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        .dstStageMask = c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        .dstAccessMask = c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
    });

    const dependecies = [_]c.VkSubpassDependency{
        color_dependency,
        depth_dependency,
    };

    const render_pass_create_info = std.mem.zeroInit(c.VkRenderPassCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = @as(u32, @intCast(attachment_descriptions.len)),
        .pAttachments = attachment_descriptions[0..].ptr,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = @as(u32, @intCast(dependecies.len)),
        .pDependencies = &dependecies[0],
    });

    check_vk(c.vkCreateRenderPass(self.device, &render_pass_create_info, vk_alloc_cbs, &self.render_pass)) catch @panic("Failed to create render pass");
    self.deletion_queue.append(VulkanDeleter.make(self.render_pass, c.vkDestroyRenderPass)) catch @panic("Out of memory");

    log.info("Created render pass", .{});
}
