//! This is a simple example of a floating window using SDL2 and Vulkan.
//! It is a work in progress and is not yet functional.
//! The goal is to create a floating window that can be moved around the screen.

const std = @import("std");
const vki = @import("vkInitUtils.zig");
const c = @import("clibs.zig");
const log = std.log.scoped(.vkEngine);
const window_extent = c.VkExtent2D{ .width = 1600, .height = 900 };
const vk_alloc_cbs: ?*c.VkAllocationCallbacks = null;
const check_vk = vki.check_vk;

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
graphics_queue_family: u32 = undefined,
present_queue: c.VkQueue = null,
present_queue_family: u32 = undefined,
swapchain: c.VkSwapchainKHR = null,
swapchain_format: c.VkFormat = undefined,
swapchain_extent: c.VkExtent2D = undefined,
swapchain_images: []c.VkImage = undefined,
swapchain_image_views: []c.VkImageView = undefined,
depth_image_view: c.VkImageView = null,
depth_image: AllocatedImage = undefined,
depth_format: c.VkFormat = undefined,
surface: c.VkSurfaceKHR = null,
deletion_queue: std.ArrayList(VulkanDeleter) = undefined,
image_deletion_queue: std.ArrayList(VmaImageDeleter) = undefined,

const AllocatedImage = struct {
    image: c.VkImage,
    allocation: c.VmaAllocation,
};

const VulkanDeleter = struct {
    object: ?*anyopaque,
    delete_fn: *const fn (entry: *VulkanDeleter, self: *Self) void,

    fn delete(self: *VulkanDeleter, engine: *Self) void {
        self.delete_fn(self, engine);
    }

    fn make(object: anytype, func: anytype) VulkanDeleter {
        const T = @TypeOf(object);
        comptime {
            std.debug.assert(@typeInfo(T) == .Optional);
            const Ptr = @typeInfo(T).Optional.child;
            std.debug.assert(@typeInfo(Ptr) == .Pointer);
            std.debug.assert(@typeInfo(Ptr).Pointer.size == .One);

            const Fn = @TypeOf(func);
            std.debug.assert(@typeInfo(Fn) == .Fn);
        }

        return VulkanDeleter{
            .object = object,
            .delete_fn = struct {
                fn destroy_impl(entry: *VulkanDeleter, self: *Self) void {
                    const obj: @TypeOf(object) = @ptrCast(entry.object);
                    func(self.device, obj, vk_alloc_cbs);
                }
            }.destroy_impl,
        };
    }
};

const VmaImageDeleter = struct {
    image: AllocatedImage,

    fn delete(self: *VmaImageDeleter, engine: *Self) void {
        c.vmaDestroyImage(engine.gpu_allocator, self.image.image, self.image.allocation);
    }
};

// ############################################################################
// section: public ############################################################
// ############################################################################

pub fn init(a: std.mem.Allocator) Self {
    check_sdl(c.SDL_Init(c.SDL_INIT_VIDEO));
    const window = c.SDL_CreateWindow("floating", window_extent.width, window_extent.height, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE) orelse @panic("Failed to create SDL window");
    _ = c.SDL_ShowWindow(window);
    var engine = Self{
        .window = window,
        .cpu_allocator = a,
        .deletion_queue = std.ArrayList(VulkanDeleter).init(a),
        .image_deletion_queue = std.ArrayList(VmaImageDeleter).init(a),
    };
    engine.init_instance();
    check_sdl_bool(c.SDL_Vulkan_CreateSurface(window, engine.instance, vk_alloc_cbs, &engine.surface));
    engine.init_device();    

    const allocator_ci = std.mem.zeroInit(c.VmaAllocatorCreateInfo, .{
        .physicalDevice = engine.gpu,
        .device = engine.device,
        .instance = engine.instance,
    });
    check_vk(c.vmaCreateAllocator(&allocator_ci, &engine.gpu_allocator)) catch @panic("Failed to create VMA allocator");
    engine.init_swapchain();
    return engine;
}

pub fn run(_: *Self) void {
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
        draw();
    }
}

pub fn cleanup(self: *Self) void {
    check_vk(c.vkDeviceWaitIdle(self.device)) catch @panic("Failed to wait for device idle");

    for (self.image_deletion_queue.items) |*entry| {
        entry.delete(self);
    }
    self.image_deletion_queue.deinit();

    for (self.deletion_queue.items) |*entry| {
        entry.delete(self);
    }
    self.deletion_queue.deinit();
    self.cpu_allocator.free(self.swapchain_image_viewsa;
    self.cpu_allocator.free(self.swapchain_imagesa;
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

// ############################################################################
// section: private ###########################################################
// ############################################################################

fn init_instance(self: *Self) void {
    var sdl_required_extension_count: u32 = undefined;
    const sdl_extensions = c.SDL_Vulkan_GetInstanceExtensions(&sdl_required_extension_count);
    const sdl_extension_slice = sdl_extensions[0..sdl_required_extension_count];

    const instance = vki.Instance.create(std.heap.page_allocator, .{
        .application_name = "zzz",
        .application_version = c.VK_MAKE_VERSION(0, 1, 0),
        .engine_name = "zzz",
        .engine_version = c.VK_MAKE_VERSION(0, 1, 0),
        .api_version = c.VK_MAKE_VERSION(1, 1, 0),
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

    const shader_draw_parameters_features = std.mem.zeroInit(c.VkPhysicalDeviceShaderDrawParametersFeatures, .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES,
        .shaderDrawParameters = c.VK_TRUE,
    });

    const device = vki.Device.create(self.cpu_allocator, .{
        .physical_device = physical_device,
        .features = std.mem.zeroInit(c.VkPhysicalDeviceFeatures, .{}),
        .alloc_cb = vk_alloc_cbs,
        .pnext = &shader_draw_parameters_features,
    }) catch @panic("Failed to create logical device");

    self.device = device.handle;
    self.graphics_queue = device.graphics_queue;
    self.present_queue = device.present_queue;
}

fn init_swapchain(self: *Self) void {
    var win_width: c_int = undefined;
    var win_height: c_int = undefined;
    check_sdl(c.SDL_GetWindowSize(self.window, &win_width, &win_height));

    const swapchain = vki.Swapchain.create(self.cpu_allocator, .{
        .physical_device = self.gpu,
        .graphics_queue_family = self.graphics_queue_family,
        .present_queue_family = self.present_queue_family,
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

    for (self.swapchain_image_views) |view| {
        self.deletion_queue.append(VulkanDeleter.make(view, c.vkDestroyImageView)) catch @panic("Out of memory");
    }
    self.deletion_queue.append(VulkanDeleter.make(swapchain.handle, c.vkDestroySwapchainKHR)) catch @panic("Out of memory");

    log.info("Created swapchain", .{});

    const extent = c.VkExtent3D{
        .width = self.swapchain_extent.width,
        .height = self.swapchain_extent.height,
        .depth = 1,
    };

    self.depth_format = c.VK_FORMAT_D32_SFLOAT;

    const depth_image_ci = std.mem.zeroInit(c.VkImageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = self.depth_format,
        .extent = extent,
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
        .format = self.depth_format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });

    check_vk(c.vkCreateImageView(self.device, &depth_image_view_ci, vk_alloc_cbs, &self.depth_image_view)) catch @panic("Failed to create depth image view");
    self.deletion_queue.append(VulkanDeleter.make(self.depth_image_view, c.vkDestroyImageView)) catch @panic("Out of memory");
    self.image_deletion_queue.append(VmaImageDeleter{ .image = self.depth_image }) catch @panic("Out of memory");

    log.info("Created depth image", .{});
}

fn draw() void {
    // draw stuff
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
