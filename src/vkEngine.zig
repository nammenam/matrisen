const std = @import("std");
const vki = @import("vkUtils.zig");
const d = @import("vkDescriptors.zig");
const c = @import("clibs.zig");
const log = std.log.scoped(.vkEngine);
const window_extent = c.VkExtent2D{ .width = 1600, .height = 900 };
const vk_alloc_cbs: ?*c.VkAllocationCallbacks = null;
const check_vk = vki.check_vk;

const AllocatedBuffer = struct {
    buffer: c.VkBuffer,
    allocation: c.VmaAllocation,
};

const AllocatedImage = struct {
    image: c.VkImage,
    allocation: c.VmaAllocation,
    extent: c.VkExtent3D,
    format: c.VkFormat,
    view: c.VkImageView,
};

const UploadContext = struct {
    upload_fence: c.VkFence = null,
    command_pool: c.VkCommandPool = null,
    command_buffer: c.VkCommandBuffer = null,
};

const FrameData = struct {
    present_semaphore: c.VkSemaphore = null,
    render_semaphore: c.VkSemaphore = null,
    render_fence: c.VkFence = null,
    command_pool: c.VkCommandPool = null,
    main_command_buffer: c.VkCommandBuffer = null,
    object_buffer: AllocatedBuffer = .{ .buffer = null, .allocation = null },
    object_descriptor_set: c.VkDescriptorSet = null,
};

const Self = @This();
cpu_allocator: std.mem.Allocator = undefined,
gpu_allocator: c.VmaAllocator = undefined,
debug_messenger: c.VkDebugUtilsMessengerEXT = null,
window: *c.SDL_Window = undefined,
instance: c.VkInstance = null,
gpu: c.VkPhysicalDevice = null,
gpu_properties: c.VkPhysicalDeviceProperties = undefined,
device: c.VkDevice = null,
graphics_queue: c.VkQueue = null,
present_queue: c.VkQueue = null,
compute_queue: c.VkQueue = null,
transfer_queue: c.VkQueue = null,
graphics_queue_family: u32 = undefined,
present_queue_family: u32 = undefined,
swapchain: c.VkSwapchainKHR = null,
swapchain_format: c.VkFormat = undefined,
swapchain_extent: c.VkExtent2D = undefined,
swapchain_images: []c.VkImage = undefined,
swapchain_image_views: []c.VkImageView = undefined,
depth_image: AllocatedImage = undefined,
draw_image: AllocatedImage = undefined,
draw_extent: c.VkExtent2D = undefined,
surface: c.VkSurfaceKHR = null,
upload_context: UploadContext = .{},
buffer_deletion_queue: std.ArrayList(AllocatedBuffer) = undefined,
image_deletion_queue: std.ArrayList(AllocatedImage) = undefined,
imageview_deletion_queue: std.ArrayList(c.VkImageView) = undefined,
frames: [FRAME_OVERLAP]FrameData = .{FrameData{}} ** FRAME_OVERLAP,
frame_number: u32 = 0,
global_descriptor_allocator: d.DescriptorAllocator = undefined,
draw_image_descriptors: c.VkDescriptorSet = undefined,
draw_image_descriptor_layout: c.VkDescriptorSetLayout = undefined,
gradient_pipeline: c.VkPipeline = null,
gradient_pipeline_layout: c.VkPipelineLayout = null,

const FRAME_OVERLAP = 2;

pub fn init(a: std.mem.Allocator) Self {
    check_sdl(c.SDL_Init(c.SDL_INIT_VIDEO));
    const window = c.SDL_CreateWindow("floating", window_extent.width, window_extent.height, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE) orelse @panic("Failed to create SDL window");
    _ = c.SDL_ShowWindow(window);

    var engine = Self{
        .window = window,
        .cpu_allocator = a,
        .buffer_deletion_queue = std.ArrayList(AllocatedBuffer).init(a),
        .image_deletion_queue = std.ArrayList(AllocatedImage).init(a),
        .imageview_deletion_queue = std.ArrayList(c.VkImageView).init(a),
    };
    engine.init_instance();
    check_sdl_bool(c.SDL_Vulkan_CreateSurface(window, engine.instance, vk_alloc_cbs, &engine.surface));
    engine.init_device();

    const allocator_ci = std.mem.zeroInit(c.VmaAllocatorCreateInfo, .{
        .physicalDevice = engine.gpu,
        .device = engine.device,
        .instance = engine.instance,
        .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    });
    check_vk(c.vmaCreateAllocator(&allocator_ci, &engine.gpu_allocator)) catch @panic("Failed to create VMA allocator");

    engine.init_swapchain();
    engine.init_commands();
    engine.init_sync_structures();
    engine.init_descriptors();
    engine.init_pipelines();
    return engine;
}

pub fn run(self: *Self) void {
    // var timer = std.time.Timer.start() catch @panic("Failed to start timer");
    // var delta: f32 = undefined;
    var quit = false;
    var event: c.SDL_Event = undefined;

    while (!quit) {
        while (c.SDL_PollEvent(&event) != 0) {
            if (event.type == c.SDL_EVENT_QUIT) {
                quit = true;
            }
        }
        self.draw();
    }
}

pub fn cleanup(self: *Self) void {
    check_vk(c.vkDeviceWaitIdle(self.device)) catch @panic("Failed to wait for device idle");
    while (self.imageview_deletion_queue.popOrNull()) |entry| {
        c.vkDestroyImageView(self.device, entry, vk_alloc_cbs);
    }
    self.imageview_deletion_queue.deinit();
    while (self.image_deletion_queue.popOrNull()) |entry| {
        c.vmaDestroyImage(self.gpu_allocator, entry.image, entry.allocation);
    }
    self.image_deletion_queue.deinit();
    while (self.buffer_deletion_queue.popOrNull()) |entry| {
        c.vmaDestroyBuffer(self.gpu_allocator, entry.buffer, entry.allocation);
    }
    self.buffer_deletion_queue.deinit();
    c.vkDestroyDescriptorSetLayout(self.device, self.draw_image_descriptor_layout, vk_alloc_cbs);
    self.global_descriptor_allocator.clear_descriptors(self.device);
    self.global_descriptor_allocator.destroy_pool(self.device);
    c.vkDestroyPipelineLayout(self.device, self.gradient_pipeline_layout, vk_alloc_cbs);
    c.vkDestroyPipeline(self.device, self.gradient_pipeline, vk_alloc_cbs);
    for (self.frames) |frame| {
        c.vkDestroyCommandPool(self.device, frame.command_pool, vk_alloc_cbs);
        c.vkDestroyFence(self.device, frame.render_fence, vk_alloc_cbs);
        c.vkDestroySemaphore(self.device, frame.render_semaphore, vk_alloc_cbs);
        c.vkDestroySemaphore(self.device, frame.present_semaphore, vk_alloc_cbs);
    }
    c.vkDestroyFence(self.device, self.upload_context.upload_fence, vk_alloc_cbs);
    c.vkDestroyCommandPool(self.device, self.upload_context.command_pool, vk_alloc_cbs);
    c.vkDestroySwapchainKHR(self.device, self.swapchain, vk_alloc_cbs);
    self.cpu_allocator.free(self.swapchain_image_views);
    self.cpu_allocator.free(self.swapchain_images);
    c.vmaDestroyAllocator(self.gpu_allocator);
    c.vkDestroyDevice(self.device, vk_alloc_cbs);
    c.vkDestroySurfaceKHR(self.instance, self.surface, vk_alloc_cbs);
    if (self.debug_messenger != null) {
        const destroy_fn = vki.get_destroy_debug_utils_messenger_fn(self.instance).?;
        destroy_fn(self.instance, self.debug_messenger, vk_alloc_cbs);
    }
    c.SDL_DestroyWindow(self.window);
    c.vkDestroyInstance(self.instance, vk_alloc_cbs);
    c.SDL_Quit();
}

fn draw(self: *Self) void {
    const timeout: u64 = 1_000_000_000; // 1 second in nanonesconds
    const frame = self.frames[@intCast(@mod(self.frame_number, FRAME_OVERLAP))]; // Get the current frame data
    check_vk(c.vkWaitForFences(self.device, 1, &frame.render_fence, c.VK_TRUE, timeout)) catch @panic("Failed to wait for render fence");
    check_vk(c.vkResetFences(self.device, 1, &frame.render_fence)) catch @panic("Failed to reset render fence");
    var swapchain_image_index: u32 = undefined;
    check_vk(c.vkAcquireNextImageKHR(self.device, self.swapchain, timeout, frame.present_semaphore, null, &swapchain_image_index)) catch @panic("Failed to acquire swapchain image");
    const cmd = frame.main_command_buffer;
    check_vk(c.vkResetCommandBuffer(cmd, 0)) catch @panic("Failed to reset command buffer");

    const cmd_begin_info = std.mem.zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });

    self.draw_extent.width = self.draw_image.extent.width;
    self.draw_extent.height = self.draw_image.extent.height;

    check_vk(c.vkBeginCommandBuffer(cmd, &cmd_begin_info)) catch @panic("Failed to begin command buffer");

    transition_image(cmd, self.draw_image.image, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_GENERAL);
    self.draw_background(cmd);
    transition_image(cmd, self.draw_image.image, c.VK_IMAGE_LAYOUT_GENERAL, c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);

    transition_image(cmd, self.swapchain_images[swapchain_image_index], c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    copy_image_to_image(cmd, self.draw_image.image, self.swapchain_images[swapchain_image_index], self.draw_extent, self.swapchain_extent);
    transition_image(cmd, self.swapchain_images[swapchain_image_index], c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);

    check_vk(c.vkEndCommandBuffer(cmd)) catch @panic("Failed to end command buffer");

    const cmd_info = std.mem.zeroInit(c.VkCommandBufferSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    });

    const wait_info = std.mem.zeroInit(c.VkSemaphoreSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = frame.present_semaphore,
        .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
    });

    const signal_info = std.mem.zeroInit(c.VkSemaphoreSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = frame.render_semaphore,
        .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
    });

    const submit = std.mem.zeroInit(c.VkSubmitInfo2, .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmd_info,
        .waitSemaphoreInfoCount = 1,
        .pWaitSemaphoreInfos = &wait_info,
        .signalSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &signal_info,
    });

    check_vk(c.vkQueueSubmit2(self.graphics_queue, 1, &submit, frame.render_fence)) catch @panic("Failed to submit to graphics queue");

    const present_info = std.mem.zeroInit(c.VkPresentInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &frame.render_semaphore,
        .swapchainCount = 1,
        .pSwapchains = &self.swapchain,
        .pImageIndices = &swapchain_image_index,
    });
    check_vk(c.vkQueuePresentKHR(self.graphics_queue, &present_info)) catch @panic("Failed to present swapchain image");
    self.frame_number +%= 1;
}

fn draw_background(self: *Self, cmd: c.VkCommandBuffer) void {
    // const color = std.math.sin(@as(f32, @floatFromInt(self.frame_number)) * 0.01) * 0.5 + 0.5;
    // const clear_value = c.VkClearColorValue{ .float32 = .{ color, color, color, 1.0 } };
    // const clear_range = c.VkImageSubresourceRange{
    //     .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
    //     .baseMipLevel = 0,
    //     .levelCount = c.VK_REMAINING_MIP_LEVELS,
    //     .baseArrayLayer = 0,
    //     .layerCount = c.VK_REMAINING_ARRAY_LAYERS,
    // };
    // c.vkCmdClearColorImage(cmd, self.draw_image.image, c.VK_IMAGE_LAYOUT_GENERAL, &clear_value, 1, &clear_range);
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.gradient_pipeline);
    c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.gradient_pipeline_layout, 0, 1, &self.draw_image_descriptors, 0, null);
    c.vkCmdDispatch(cmd, self.draw_extent.width / 16, self.draw_extent.height / 16, 1);
}

fn transition_image(cmd: c.VkCommandBuffer, image: c.VkImage, current_layout: c.VkImageLayout, new_layout: c.VkImageLayout) void {
    var barrier = std.mem.zeroInit(c.VkImageMemoryBarrier2, .{ .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2 });
    barrier.srcStageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    barrier.srcAccessMask = c.VK_ACCESS_2_MEMORY_WRITE_BIT;
    barrier.dstStageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    barrier.dstAccessMask = c.VK_ACCESS_2_MEMORY_WRITE_BIT | c.VK_ACCESS_2_MEMORY_READ_BIT;
    barrier.oldLayout = current_layout;
    barrier.newLayout = new_layout;

    const aspect_mask: u32 = if (new_layout == c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) c.VK_IMAGE_ASPECT_DEPTH_BIT else c.VK_IMAGE_ASPECT_COLOR_BIT;
    const subresource_range = std.mem.zeroInit(c.VkImageSubresourceRange, .{
        .aspectMask = aspect_mask,
        .baseMipLevel = 0,
        .levelCount = c.VK_REMAINING_MIP_LEVELS,
        .baseArrayLayer = 0,
        .layerCount = c.VK_REMAINING_ARRAY_LAYERS,
    });

    barrier.image = image;
    barrier.subresourceRange = subresource_range;

    const dep_info = std.mem.zeroInit(c.VkDependencyInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO_KHR,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &barrier,
    });

    c.vkCmdPipelineBarrier2(cmd, &dep_info);
}

fn copy_image_to_image(cmd: c.VkCommandBuffer, src: c.VkImage, dst: c.VkImage, src_size: c.VkExtent2D, dst_size: c.VkExtent2D) void {
    var blit_region = c.VkImageBlit2{ .sType = c.VK_STRUCTURE_TYPE_IMAGE_BLIT_2, .pNext = null };
    blit_region.srcOffsets[1].x = @intCast(src_size.width);
    blit_region.srcOffsets[1].y = @intCast(src_size.height);
    blit_region.srcOffsets[1].z = 1;
    blit_region.dstOffsets[1].x = @intCast(dst_size.width);
    blit_region.dstOffsets[1].y = @intCast(dst_size.height);
    blit_region.dstOffsets[1].z = 1;
    blit_region.srcSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    blit_region.srcSubresource.baseArrayLayer = 0;
    blit_region.srcSubresource.layerCount = 1;
    blit_region.srcSubresource.mipLevel = 0;
    blit_region.dstSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    blit_region.dstSubresource.baseArrayLayer = 0;
    blit_region.dstSubresource.layerCount = 1;
    blit_region.dstSubresource.mipLevel = 0;

    var blit_info = c.VkBlitImageInfo2{ .sType = c.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2, .pNext = null };
    blit_info.srcImage = src;
    blit_info.srcImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    blit_info.dstImage = dst;
    blit_info.dstImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    blit_info.regionCount = 1;
    blit_info.pRegions = &blit_region;
    blit_info.filter = c.VK_FILTER_LINEAR;

    c.vkCmdBlitImage2(cmd, &blit_info);
}

fn init_descriptors(self: *Self) void {
    var sizes = [_]d.DescriptorAllocator.PoolSizeRatio{
        .{ .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 10 },
    };

    self.global_descriptor_allocator.init_pool(self.device, 10, &sizes, self.cpu_allocator);

    {
        var builder = d.DescriptorLayoutBuilder{ .bindings = std.ArrayList(c.VkDescriptorSetLayoutBinding).init(self.cpu_allocator) };
        defer builder.bindings.deinit();
        builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE);
        self.draw_image_descriptor_layout = builder.build(self.device, c.VK_SHADER_STAGE_COMPUTE_BIT, null, 0);
    }

    self.draw_image_descriptors = self.global_descriptor_allocator.allocate(self.device, self.draw_image_descriptor_layout);

    const image_info = std.mem.zeroInit(c.VkDescriptorImageInfo, .{
        .imageView = self.draw_image.view,
        .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL,
    });

    const write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = self.draw_image_descriptors,
        .dstBinding = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        .pImageInfo = &image_info,
    });

    c.vkUpdateDescriptorSets(self.device, 1, &write, 0, null);
}

fn init_pipelines(self: *Self) void {
    self.init_background_pipelines();
}

fn init_background_pipelines(self: *Self) void {
    const compute_layout = std.mem.zeroInit(c.VkPipelineLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &self.draw_image_descriptor_layout,
    });

    check_vk(c.vkCreatePipelineLayout(self.device, &compute_layout, null, &self.gradient_pipeline_layout)) catch @panic("Failed to create pipeline layout");

    const comp_code align(4) = @embedFile("gradient.comp").*;
    const comp_module = vki.create_shader_module(self.device, &comp_code, vk_alloc_cbs) orelse null;
    if (comp_module != null) log.info("Created compute shader module", .{});

    const stage_ci = std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
        .module = comp_module,
        .pName = "main",
    });

    const compute_ci = std.mem.zeroInit(c.VkComputePipelineCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .layout = self.gradient_pipeline_layout,
        .stage = stage_ci,
    });

    check_vk(c.vkCreateComputePipelines(self.device, null, 1, &compute_ci, null, &self.gradient_pipeline)) catch @panic("Failed to create compute pipeline");

    c.vkDestroyShaderModule(self.device, comp_module, vk_alloc_cbs);
}

fn init_instance(self: *Self) void {
    var sdl_required_extension_count: u32 = undefined;
    const sdl_extensions = c.SDL_Vulkan_GetInstanceExtensions(&sdl_required_extension_count);
    const sdl_extension_slice = sdl_extensions[0..sdl_required_extension_count];

    const instance = vki.Instance.create(std.heap.page_allocator, .{
        .application_name = "zzz",
        .application_version = c.VK_MAKE_VERSION(0, 1, 0),
        .engine_name = "zzz",
        .engine_version = c.VK_MAKE_VERSION(0, 1, 0),
        .api_version = c.VK_MAKE_VERSION(1, 3, 0),
        .debug = true,
        .required_extensions = sdl_extension_slice,
    }) catch |err| {
        log.err("Failed to create vulkan instance with error: {s}", .{@errorName(err)});
        unreachable;
    };
    self.instance = instance.handle;
    self.debug_messenger = instance.debug_messenger;
}

fn init_device(self: *Self) void {
    const required_device_extensions: []const [*c]const u8 = &.{
        "VK_KHR_swapchain",
    };

    const physical_device = vki.PhysicalDevice.select(std.heap.page_allocator, self.instance, .{
        .min_api_version = c.VK_MAKE_VERSION(1, 3, 0),
        .required_extensions = required_device_extensions,
        .surface = self.surface,
        .criteria = .PreferDiscrete,
    }) catch |err| {
        log.err("Failed to select physical device with error: {s}", .{@errorName(err)});
        unreachable;
    };

    self.gpu = physical_device.handle;
    self.gpu_properties = physical_device.properties;
    log.info("The GPU has a minimum buffer alignment of {} bytes", .{physical_device.properties.limits.minUniformBufferOffsetAlignment});
    self.graphics_queue_family = physical_device.graphics_queue_family;
    self.present_queue_family = physical_device.present_queue_family;

    var features13 = std.mem.zeroInit(c.VkPhysicalDeviceVulkan13Features, .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .dynamicRendering = c.VK_TRUE,
        .synchronization2 = c.VK_TRUE,
    });

    var features12 = std.mem.zeroInit(c.VkPhysicalDeviceVulkan12Features, .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .bufferDeviceAddress = c.VK_TRUE,
        .descriptorIndexing = c.VK_TRUE,
        .pNext = &features13,
    });

    var shader_draw_parameters_features = std.mem.zeroInit(c.VkPhysicalDeviceShaderDrawParametersFeatures, .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES,
        .shaderDrawParameters = c.VK_TRUE,
        .pNext = &features12,
    });

    const deviceFeatures2 = std.mem.zeroInit(c.VkPhysicalDeviceFeatures2, .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
        .pNext = &shader_draw_parameters_features,
    });

    const device = vki.Device.create(self.cpu_allocator, .{
        .physical_device = physical_device,
        .extensions = required_device_extensions,
        .features = null,
        .alloc_cb = vk_alloc_cbs,
        .pnext = &deviceFeatures2,
    }) catch @panic("Failed to create logical device");

    self.device = device.handle;
    self.graphics_queue = device.graphics_queue;
    self.present_queue = device.present_queue;
    self.compute_queue = device.compute_queue;
    self.transfer_queue = device.transfer_queue;
}

fn init_swapchain(self: *Self) void {
    var win_width: c_int = undefined;
    var win_height: c_int = undefined;
    check_sdl(c.SDL_GetWindowSize(self.window, &win_width, &win_height));

    const swapchain = vki.Swapchain.create(self.cpu_allocator, .{
        .physical_device = self.gpu,
        .graphics_queue_family = self.graphics_queue_family,
        .present_queue_family = self.graphics_queue_family,
        .device = self.device,
        .surface = self.surface,
        .old_swapchain = null,
        .vsync = true,
        .window_width = @intCast(win_width),
        .window_height = @intCast(win_height),
        .alloc_cb = vk_alloc_cbs,
    }) catch @panic("Failed to create swapchain");

    self.swapchain = swapchain.handle;
    self.swapchain_format = swapchain.format;
    self.swapchain_extent = swapchain.extent;
    self.swapchain_images = swapchain.images;
    self.swapchain_image_views = swapchain.image_views;

    for (self.swapchain_image_views) |view|
        self.imageview_deletion_queue.append(view) catch @panic("Out of memory");
    log.info("Created swapchain", .{});
    self.draw_image.extent = c.VkExtent3D{
        .width = @intCast(win_width),
        .height = @intCast(win_height),
        .depth = 1,
    };
    self.draw_image.format = c.VK_FORMAT_R16G16B16A16_SFLOAT;
    const draw_image_ci = std.mem.zeroInit(c.VkImageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = self.draw_image.format,
        .extent = self.draw_image.extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_STORAGE_BIT,
    });
    const draw_image_ai = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    });
    check_vk(c.vmaCreateImage(self.gpu_allocator, &draw_image_ci, &draw_image_ai, &self.draw_image.image, &self.draw_image.allocation, null)) catch @panic("Failed to create draw image");
    const draw_image_view_ci = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = self.draw_image.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = self.draw_image.format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    check_vk(c.vkCreateImageView(self.device, &draw_image_view_ci, vk_alloc_cbs, &self.draw_image.view)) catch @panic("Failed to create draw image view");
    self.imageview_deletion_queue.append(self.draw_image.view) catch @panic("Out of memory");
    self.image_deletion_queue.append(self.draw_image) catch @panic("Out of memory");

    self.depth_image.extent = c.VkExtent3D{
        .width = self.swapchain_extent.width,
        .height = self.swapchain_extent.height,
        .depth = 1,
    };
    self.depth_image.format = c.VK_FORMAT_D32_SFLOAT;
    const depth_image_ci = std.mem.zeroInit(c.VkImageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = self.depth_image.format,
        .extent = self.depth_image.extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
    });
    const depth_image_ai = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    });
    check_vk(c.vmaCreateImage(self.gpu_allocator, &depth_image_ci, &depth_image_ai, &self.depth_image.image, &self.depth_image.allocation, null)) catch @panic("Failed to create depth image");
    const depth_image_view_ci = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = self.depth_image.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = self.depth_image.format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    check_vk(c.vkCreateImageView(self.device, &depth_image_view_ci, vk_alloc_cbs, &self.depth_image.view)) catch @panic("Failed to create depth image view");
    self.imageview_deletion_queue.append(self.depth_image.view) catch @panic("Out of memory");
    self.image_deletion_queue.append(self.depth_image) catch @panic("Out of memory");
    log.info("Created depth image", .{});
}

fn init_commands(self: *Self) void {
    const command_pool_ci = std.mem.zeroInit(c.VkCommandPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = self.graphics_queue_family,
    });

    for (&self.frames) |*frame| {
        check_vk(c.vkCreateCommandPool(self.device, &command_pool_ci, vk_alloc_cbs, &frame.command_pool)) catch log.err("Failed to create command pool", .{});

        const command_buffer_ai = std.mem.zeroInit(c.VkCommandBufferAllocateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = frame.command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        });

        check_vk(c.vkAllocateCommandBuffers(self.device, &command_buffer_ai, &frame.main_command_buffer)) catch @panic("Failed to allocate command buffer");

        log.info("Created command pool and command buffer", .{});
    }

    const upload_command_pool_ci = std.mem.zeroInit(c.VkCommandPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = 0,
        .queueFamilyIndex = self.graphics_queue_family,
    });

    check_vk(c.vkCreateCommandPool(self.device, &upload_command_pool_ci, vk_alloc_cbs, &self.upload_context.command_pool)) catch @panic("Failed to create upload command pool");

    const upload_command_buffer_ai = std.mem.zeroInit(c.VkCommandBufferAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = self.upload_context.command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    });
    check_vk(c.vkAllocateCommandBuffers(self.device, &upload_command_buffer_ai, &self.upload_context.command_buffer)) catch @panic("Failed to allocate upload command buffer");
}

fn init_sync_structures(self: *Self) void {
    const semaphore_ci = std.mem.zeroInit(c.VkSemaphoreCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    });

    const fence_ci = std.mem.zeroInit(c.VkFenceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    });

    for (&self.frames) |*frame| {
        check_vk(c.vkCreateSemaphore(self.device, &semaphore_ci, vk_alloc_cbs, &frame.present_semaphore)) catch @panic("Failed to create present semaphore");
        check_vk(c.vkCreateSemaphore(self.device, &semaphore_ci, vk_alloc_cbs, &frame.render_semaphore)) catch @panic("Failed to create render semaphore");
        check_vk(c.vkCreateFence(self.device, &fence_ci, vk_alloc_cbs, &frame.render_fence)) catch @panic("Failed to create render fence");
    }

    const upload_fence_ci = std.mem.zeroInit(c.VkFenceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    });

    check_vk(c.vkCreateFence(self.device, &upload_fence_ci, vk_alloc_cbs, &self.upload_context.upload_fence)) catch @panic("Failed to create upload fence");
    log.info("Created sync structures", .{});
}

fn check_sdl(res: c_int) void {
    if (res != 0) {
        std.log.err("Detected SDL error: {s}", .{c.SDL_GetError()});
        @panic("SDL error");
    }
}

fn check_sdl_bool(res: c.SDL_bool) void {
    if (res != c.SDL_TRUE) {
        std.log.err("Detected SDL error: {s}", .{c.SDL_GetError()});
        @panic("SDL error");
    }
}
