const c = @import("../clibs/clibs.zig").libs;
const checkVkPanic = @import("debug.zig").checkVkPanic;
const std = @import("std");
const log = std.log.scoped(.images);
const AsyncContext = @import("AsyncContext.zig");
const Vec4 = @import("../linalg.zig").Vec4(f32);
const Core = @import("Core.zig");

const Self = @This();

device: c.VkDevice,
gpuallocator: c.VmaAllocator,
allocationcallbacks: ?*c.VkAllocationCallbacks,

pub fn init(device: c.VkDevice, gpuallocator: c.VmaAllocator, allocationcallbacks: ?*c.VkAllocationCallbacks) Self {
    return .{
        .device = device,
        .allocationcallbacks = allocationcallbacks,
        .gpuallocator = gpuallocator,
    };
}

pub const AllocatedImage = struct {
    image: c.VkImage,
    allocation: c.VmaAllocation,
    view: c.VkImageView,
};

pub fn createDrawImage(
    self: *Self,
    extent: c.VkExtent2D,
    format: c.VkFormat,
) AllocatedImage {
    var drawimage: AllocatedImage = undefined;
    const extent3d: c.VkExtent3D = .{ .width = extent.width, .height = extent.height, .depth = 1 };
    const drawimageci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent3d,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_4_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
            c.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT,
    };

    const drawimageai: c.VmaAllocationCreateInfo = .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };

    checkVkPanic(c.vmaCreateImage(
        self.gpuallocator,
        &drawimageci,
        &drawimageai,
        &drawimage.image,
        &drawimage.allocation,
        null,
    ));
    const draw_image_view_ci: c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = drawimage.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    checkVkPanic(c.vkCreateImageView(
        self.device,
        &draw_image_view_ci,
        self.allocationcallbacks,
        &drawimage.view,
    ));
    return drawimage;
}

pub fn createRenderImage(
    self: *Self,
    extent: c.VkExtent2D,
    format: c.VkFormat,
) AllocatedImage {
    var renderimage: AllocatedImage = undefined;
    const extent3d: c.VkExtent3D = .{ .width = extent.width, .height = extent.height, .depth = 1 };
    const resolved_image_ci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent3d,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
    };

    const resolved_image_ai: c.VmaAllocationCreateInfo = .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };

    checkVkPanic(c.vmaCreateImage(
        self.gpuallocator,
        &resolved_image_ci,
        &resolved_image_ai,
        &renderimage.image,
        &renderimage.allocation,
        null,
    ));
    const resolved_view_ci: c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = renderimage.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    checkVkPanic(c.vkCreateImageView(
        self.device,
        &resolved_view_ci,
        self.allocationcallbacks,
        &renderimage.view,
    ));
    return renderimage;
}

pub fn createDepthImage(
    self: *Self,
    extent: c.VkExtent3D,
    format: c.VkFormat,
) AllocatedImage {
    var depthimage: AllocatedImage = undefined;
    const drawimageai: c.VmaAllocationCreateInfo = .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };

    const depthimageci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_4_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
            c.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT,
    };

    checkVkPanic(c.vmaCreateImage(
        self.gpuallocator,
        &depthimageci,
        &drawimageai,
        &depthimage.image,
        &depthimage.allocation,
        null,
    ));

    const depth_image_view_ci: c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = depthimage.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    checkVkPanic(c.vkCreateImageView(
        self.device,
        &depth_image_view_ci,
        self.allocationcallbacks,
        &depthimage.view,
    ));
    return depthimage;
}

pub fn deinitImage(self: *Self, image: AllocatedImage) void {
    c.vmaDestroyImage(self.gpuallocator, image.image, image.allocation);
    c.vkDestroyImageView(self.device, image.view, self.allocationcallbacks);
}

pub fn create(
    self: *Self,
    size: c.VkExtent3D,
    format: c.VkFormat,
    usage: c.VkImageUsageFlags,
    mipmapped: bool,
) AllocatedImage {
    var new_image: AllocatedImage(1) = undefined;
    var img_info = c.VkImageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = null,
        .usage = usage,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = size,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
    };

    if (mipmapped) {
        const levels = @floor(std.math.log2(@as(f32, @floatFromInt(@max(size.width, size.height)))) + 1);
        img_info.mipLevels = @intFromFloat(levels);
    }

    const alloc_info: c.VmaAllocationCreateInfo = .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };
    checkVkPanic(c.vmaCreateImage(
        self.gpuallocator,
        &img_info,
        &alloc_info,
        &new_image.image,
        &new_image.allocation,
        null,
    ));
    var aspect_flags = c.VK_IMAGE_ASPECT_COLOR_BIT;
    if (format == c.VK_FORMAT_D32_SFLOAT) {
        aspect_flags = c.VK_IMAGE_ASPECT_DEPTH_BIT;
    }

    return new_image;
}

pub fn createView(device: c.VkDevice, image: c.VkImage, format: c.VkFormat, miplevels: u32) c.VkImageView {
    var image_view: c.VkImageView = undefined;

    var aspect_flags = c.VK_IMAGE_ASPECT_COLOR_BIT;
    if (format == c.VK_FORMAT_D32_SFLOAT) {
        aspect_flags = c.VK_IMAGE_ASPECT_DEPTH_BIT;
    }
    const view_info = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .image = image,
        .format = format,
        .subresourceRange = .{
            .aspectMask = @intCast(aspect_flags),
            .baseMipLevel = 0,
            .levelCount = miplevels,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    checkVkPanic(c.vkCreateImageView(device, &view_info, null, &image_view)) catch @panic("failed to make image view");
    return image_view;
}

// pub fn createUpload(
//     self: *Self,
//     data: *anyopaque,
//     size: c.VkExtent3D,
//     format: c.VkFormat,
//     usage: c.VkImageUsageFlags,
//     mipmapped: bool,
// ) AllocatedImage {
//     const data_size = size.width * size.height * size.depth * 4;

//     const staging = buffer.create(
//         self,
//         data_size,
//         c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
//         c.VMA_MEMORY_USAGE_CPU_TO_GPU,
//     );
//     defer c.vmaDestroyBuffer(self.gpuallocator, staging.buffer, staging.allocation);

//     const byte_data = @as([*]u8, @ptrCast(staging.info.pMappedData.?));
//     const byte_src = @as([*]u8, @ptrCast(data));
//     @memcpy(byte_data[0..data_size], byte_src[0..data_size]);

//     const new_image = create(
//         self,
//         size,
//         format,
//         usage | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
//         mipmapped,
//     );
//     AsyncContext.submitBegin(self);
//     const cmd = self.asynccontext.command_buffer;
//     transitionImage(
//         cmd,
//         new_image.image,
//         c.VK_IMAGE_LAYOUT_UNDEFINED,
//         c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
//     );
//     const image_copy_region: c.VkBufferImageCopy = .{
//         .bufferOffset = 0,
//         .bufferRowLength = 0,
//         .bufferImageHeight = 0,
//         .imageSubresource = .{
//             .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
//             .mipLevel = 0,
//             .baseArrayLayer = 0,
//             .layerCount = 1,
//         },
//         .imageExtent = size,
//     };
//     c.vkCmdCopyBufferToImage(
//         cmd,
//         staging.buffer,
//         new_image.image,
//         c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
//         1,
//         &image_copy_region,
//     );
//     transitionImage(
//         cmd,
//         new_image.image,
//         c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
//         c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
//     );
//     AsyncContext.submitEnd(self);
//     return new_image;
// }
