const c = @import("c");
const std = @import("std");
const errors = @import("errors.zig");
const log = std.log.scoped(.swapchain);
const Core = @import("Core.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");

const Self = @This();

device: c.VkDevice,
alloc_callbacks: ?*c.VkAllocationCallbacks,
handle: c.VkSwapchainKHR = null,
format: c.VkFormat = undefined,
extent: c.VkExtent2D = .{},
images: []c.VkImage = &.{},
views: []c.VkImageView = &.{},
semaphores: []c.VkSemaphore = &.{},

const CreateOptions = struct {
    physical_device: c.VkPhysicalDevice,
    graphics_queue_family: u32,
    present_queue_family: u32,
    device: c.VkDevice,
    surface: c.VkSurfaceKHR,
    old_swapchain: c.VkSwapchainKHR = null,
    format: c.VkSurfaceFormatKHR = undefined,
    vsync: bool = false,
    triple_buffer: bool = false,
    window_width: u32 = 0,
    window_height: u32 = 0,
    alloc_cb: *?c.VkAllocationCallbacks = null,
};

pub const SupportInfo = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR = undefined,
    formats: []c.VkSurfaceFormatKHR = &.{},
    present_modes: []c.VkPresentModeKHR = &.{},

    pub fn init(
        allocator: std.mem.Allocator,
        device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
    ) SupportInfo {
        var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
        errors.checkVkPanic(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &capabilities));

        var format_count: u32 = undefined;
        errors.checkVkPanic(c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, null));
        const formats = allocator.alloc(c.VkSurfaceFormatKHR, format_count) catch {
            log.err("failed to alloc", .{});
            @panic("");
        };
        errors.checkVkPanic(
            c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, formats.ptr),
        );

        var present_mode_count: u32 = undefined;
        errors.checkVkPanic(
            c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, null),
        );
        const present_modes = allocator.alloc(c.VkPresentModeKHR, present_mode_count) catch {
            log.err("failed to alloc", .{});
            @panic("");
        };
        errors.checkVkPanic(c.vkGetPhysicalDeviceSurfacePresentModesKHR(
            device,
            surface,
            &present_mode_count,
            present_modes.ptr,
        ));

        return .{
            .capabilities = capabilities,
            .formats = formats,
            .present_modes = present_modes,
        };
    }
    pub fn deinit(self: *const SupportInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.formats);
        allocator.free(self.present_modes);
    }
};

pub fn init(
    allocator: std.mem.Allocator,
    physicaldevice: PhysicalDevice,
    device: c.VkDevice,
    surface: c.VkSurfaceKHR,
    windowextent: c.VkExtent2D,
    alloc_callbacks: ?*c.VkAllocationCallbacks,
) Self {
    const old_swapchain = null;
    const vsync = true;
    const desired_format = .{
        .format = c.VK_FORMAT_B8G8R8A8_SRGB,
        .colorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
    };

    const supportinfo: SupportInfo = .init(allocator, physicaldevice.handle, surface);
    defer supportinfo.deinit(allocator);
    var format = supportinfo.formats[0];
    for (supportinfo.formats) |f| {
        if (f.format == desired_format.format and
            f.colorSpace == desired_format.colorSpace)
        {
            format = f;
            break;
        }
    }
    const present_mode = pickPresentMode(supportinfo.present_modes, vsync);
    // const present_mode_str = switch (present_mode) {
    //     c.VK_PRESENT_MODE_FIFO_RELAXED_KHR => "FIFO Relaxed",
    //     c.VK_PRESENT_MODE_MAILBOX_KHR => "Mailbox",
    //     c.VK_PRESENT_MODE_FIFO_KHR => "FIFO",
    //     else => "unknown",
    // };
    // const format_str = switch (format.format) {
    //     c.VK_FORMAT_B8G8R8A8_SRGB => "B8G8R8A8 SRBG",
    //     else => "unknown",
    // };
    // log.info("format: {s}, present mode: {s}", .{ format_str, present_mode_str });
    var supportedextent = c.VkExtent2D{ .width = windowextent.width, .height = windowextent.height };
    supportedextent.width = @max(supportinfo.capabilities.minImageExtent.width, @min(
        supportinfo.capabilities.maxImageExtent.width,
        supportedextent.width,
    ));
    supportedextent.height = @max(supportinfo.capabilities.minImageExtent.height, @min(
        supportinfo.capabilities.maxImageExtent.height,
        supportedextent.height,
    ));
    if (supportinfo.capabilities.currentExtent.width != std.math.maxInt(u32)) {
        supportedextent = supportinfo.capabilities.currentExtent;
    }

    const image_count = blk: {
        const desired_count = supportinfo.capabilities.minImageCount + 1;
        if (supportinfo.capabilities.maxImageCount > 0) {
            break :blk @min(desired_count, supportinfo.capabilities.maxImageCount);
        }
        break :blk desired_count;
    };

    var swapchain_info: c.VkSwapchainCreateInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = image_count,
        .imageFormat = format.format,
        .imageColorSpace = format.colorSpace,
        .imageExtent = supportedextent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .preTransform = supportinfo.capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = old_swapchain,
    };

    if (physicaldevice.graphics_queue_family != physicaldevice.present_queue_family) {
        const queue_family_indices: []const u32 = &.{
            physicaldevice.graphics_queue_family,
            physicaldevice.present_queue_family,
        };
        swapchain_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        swapchain_info.queueFamilyIndexCount = 2;
        swapchain_info.pQueueFamilyIndices = queue_family_indices.ptr;
    } else {
        swapchain_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    }

    var swapchain: c.VkSwapchainKHR = undefined;
    errors.checkVkPanic(c.vkCreateSwapchainKHR(
        device,
        &swapchain_info,
        alloc_callbacks,
        &swapchain,
    ));
    errdefer c.vkDestroySwapchainKHR(device, swapchain, alloc_callbacks);

    // Try and fetch the images from the swpachain.
    var swapchain_image_count: u32 = undefined;
    errors.checkVkPanic(c.vkGetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, null));
    const swapchain_images = allocator.alloc(c.VkImage, swapchain_image_count) catch {
        log.err("failed to alloc", .{});
        @panic("");
    };
    errdefer allocator.free(swapchain_images);
    errors.checkVkPanic(c.vkGetSwapchainImagesKHR(
        device,
        swapchain,
        &swapchain_image_count,
        swapchain_images.ptr,
    ));

    // Create image views for the swapchain images.
    const swapchain_image_views = allocator.alloc(c.VkImageView, swapchain_image_count) catch {
        log.err("failed to alloc", .{});
        @panic("");
    };
    errdefer allocator.free(swapchain_image_views);

    const semaphores = allocator.alloc(c.VkSemaphore, swapchain_image_count) catch {
        log.err("failed to alloc", .{});
        @panic("");
    };
    errdefer allocator.free(semaphores);

    const semaphore_ci = c.VkSemaphoreCreateInfo{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    for (swapchain_images, swapchain_image_views, semaphores) |img, *view, *semaphore| {
        view.* = createImageViews(device, img, format.format);
        errors.checkVkPanic(c.vkCreateSemaphore(
            device,
            &semaphore_ci,
            alloc_callbacks,
            semaphore,
        ));
    }

    return .{
        .handle = swapchain,
        .extent = supportedextent,
        .format = format.format,
        .images = swapchain_images,
        .views = swapchain_image_views,
        .semaphores = semaphores,
        .device = device,
        .alloc_callbacks = alloc_callbacks,
    };
}

pub fn deinit(
    self: *Self,
    allocator: std.mem.Allocator,
) void {
    c.vkDestroySwapchainKHR(self.device, self.handle, self.alloc_callbacks);
    for (self.views, self.semaphores) |view, semaphore| {
        c.vkDestroyImageView(self.device, view, null);
        c.vkDestroySemaphore(self.device, semaphore, self.alloc_callbacks);
    }
    allocator.free(self.views);
}

fn pickPresentMode(modes: []const c.VkPresentModeKHR, vsync: bool) c.VkPresentModeKHR {
    if (vsync == true) {
        for (modes) |mode| {
            if (mode == c.VK_PRESENT_MODE_FIFO_RELAXED_KHR) {
                return mode;
            }
        }
    } else {
        for (modes) |mode| {
            if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
                return mode;
            }
        }
    }
    // fallback
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn makeExtent(capabilities: c.VkSurfaceCapabilitiesKHR, opts: CreateOptions) c.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    }

    var extent = c.VkExtent2D{
        .width = opts.window_width,
        .height = opts.window_height,
    };

    extent.width = @max(capabilities.minImageExtent.width, @min(capabilities.maxImageExtent.width, extent.width));
    extent.height = @max(capabilities.minImageExtent.height, @min(capabilities.maxImageExtent.height, extent.height));

    return extent;
}

fn createImageViews(device: c.VkDevice, img: c.VkImage, format: c.VkFormat) c.VkImageView {
    const view_info = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = img,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .components = .{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });

    var image_view: c.VkImageView = undefined;
    errors.checkVkPanic(c.vkCreateImageView(device, &view_info, null, &image_view));
    return image_view;
}
