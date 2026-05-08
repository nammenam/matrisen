const c = @import("../clibs/clibs.zig").libs;
const std = @import("std");
const checkVkPanic = @import("debug.zig").checkVkPanic;
const log = std.log.scoped(.instance);
const Core = @import("Core.zig");

pub const api_version = c.VK_MAKE_VERSION(1, 4, 0);
const Self = @This();

handle: c.VkInstance = null,
debug_messenger: c.VkDebugUtilsMessengerEXT = null,

pub fn init(alloc: std.mem.Allocator, allocationcallbacks: ?*c.VkAllocationCallbacks) Self {
    var sdl_required_extension_count: u32 = undefined;
    const sdl_extensions = c.SDL_Vulkan_GetInstanceExtensions(&sdl_required_extension_count);
    const sdl_extension_slice = sdl_extensions[0..sdl_required_extension_count];
    const engine_name = "matrisen";
    if (api_version > c.VK_MAKE_VERSION(1, 0, 0)) {
        var api_requested = api_version;
        checkVkPanic(c.vkEnumerateInstanceVersion(@ptrCast(&api_requested)));
    }
    var debug = true;
    const required_extensions = sdl_extension_slice;
    const debug_callback: c.PFN_vkDebugUtilsMessengerCallbackEXT = null;

    // Get supported layers and extensions
    var layer_count: u32 = undefined;
    checkVkPanic(c.vkEnumerateInstanceLayerProperties(&layer_count, null));
    const layer_props = alloc.alloc(c.VkLayerProperties, layer_count) catch {
        log.err("failed to alloc", .{});
        @panic("");
    };
    checkVkPanic(c.vkEnumerateInstanceLayerProperties(&layer_count, layer_props.ptr));

    var extension_count: u32 = undefined;
    checkVkPanic(c.vkEnumerateInstanceExtensionProperties(null, &extension_count, null));
    const extension_props = alloc.alloc(c.VkExtensionProperties, extension_count) catch {
        log.err("failed to append", .{});
        @panic("");
    };
    checkVkPanic(c.vkEnumerateInstanceExtensionProperties(null, &extension_count, extension_props.ptr));

    var layers = std.ArrayListUnmanaged([*c]const u8){};
    if (debug) {
        debug = blk: for (layer_props) |layer_prop| {
            const layer_name: [*c]const u8 = @ptrCast(layer_prop.layerName[0..]);
            const validation_layer_name: [*c]const u8 = "VK_LAYER_KHRONOS_validation";
            if (std.mem.eql(u8, std.mem.span(validation_layer_name), std.mem.span(layer_name))) {
                layers.append(alloc, validation_layer_name) catch {
                    log.err("failed to append", .{});
                    @panic("");
                };
                log.info("Validation layers is supported", .{});
                break :blk true;
            }
        } else false;
    }

    var extensions = std.ArrayListUnmanaged([*c]const u8){};
    const ExtensionFinder = struct {
        fn find(name: [*c]const u8, props: []c.VkExtensionProperties) bool {
            for (props) |prop| {
                const prop_name: [*c]const u8 = @ptrCast(prop.extensionName[0..]);
                if (std.mem.eql(u8, std.mem.span(name), std.mem.span(prop_name))) {
                    return true;
                }
            }
            return false;
        }
    };

    for (required_extensions) |required_ext| {
        if (ExtensionFinder.find(required_ext, extension_props)) {
            extensions.append(alloc, required_ext) catch {
                log.err("failed to append", .{});
                @panic("");
            };
        } else {
            log.err("Required vulkan extension not supported: {s}", .{required_ext});
            @panic("");
        }
    }

    if (debug and ExtensionFinder.find("VK_EXT_debug_utils", extension_props)) {
        extensions.append(alloc, "VK_EXT_debug_utils") catch {
            log.err("failed to append", .{});
            @panic("");
        };
    } else {
        debug = false;
    }

    if (debug and ExtensionFinder.find("VK_EXT_device_address_binding_report", extension_props)) {
        extensions.append(alloc, "VK_EXT_device_address_binding_report") catch {
            log.err("failed to append", .{});
            @panic("");
        };
    } else {
        debug = false;
    }

    const app_info: c.VkApplicationInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .apiVersion = api_version,
        .pApplicationName = engine_name,
        .pEngineName = engine_name,
    };

    const instance_info: c.VkInstanceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledLayerCount = @as(u32, @intCast(layers.items.len)),
        .ppEnabledLayerNames = layers.items.ptr,
        .enabledExtensionCount = @as(u32, @intCast(extensions.items.len)),
        .ppEnabledExtensionNames = extensions.items.ptr,
    };

    var instance: c.VkInstance = undefined;
    checkVkPanic(c.vkCreateInstance(&instance_info, allocationcallbacks, &instance));
    log.info("Created vulkan instance", .{});

    const debug_messenger = if (debug) blk: {
        log.info("Created vulkan debug callback messenger.", .{});
        break :blk createDebugCallback(instance, debug_callback, allocationcallbacks);
    } else blk: {
        break :blk null;
    };

    return .{
        .handle = instance,
        .debug_messenger = debug_messenger,
    };
}

pub fn getDestroyDebugUtilsMessenger(self: *Self) c.PFN_vkDestroyDebugUtilsMessengerEXT {
    return getVulkanInstanceFunct(
        c.PFN_vkDestroyDebugUtilsMessengerEXT,
        self.handle,
        "vkDestroyDebugUtilsMessengerEXT",
    );
}

pub fn defaultDebugCallback(
    severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    msg_type: c.VkDebugUtilsMessageTypeFlagsEXT,
    callback_data: ?*const c.VkDebugUtilsMessengerCallbackDataEXT,
    user_data: ?*anyopaque,
) callconv(.c) c.VkBool32 {
    _ = user_data;
    const severity_str = switch (severity) {
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT => "verbose",
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT => "info",
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT => "warning",
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT => "error",
        else => "unknown",
    };

    const type_str = switch (msg_type) {
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT => "general",
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT => "validation",
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT => "performance",
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_DEVICE_ADDRESS_BINDING_BIT_EXT => "device address",
        else => "unknown",
    };

    const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.pMessage else "NO MESSAGE!";
    log.info("[{s}][{s}]. Message:\n  {s}", .{ severity_str, type_str, message });

    if (severity >= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) {
        @panic("Unrecoverable vulkan error.");
    }

    return c.VK_FALSE;
}

fn getVulkanInstanceFunct(comptime Fn: type, instance: c.VkInstance, name: [*c]const u8) Fn {
    const get_proc_addr: c.PFN_vkGetInstanceProcAddr = @ptrCast(c.SDL_Vulkan_GetVkGetInstanceProcAddr());
    if (get_proc_addr) |get_proc_addr_fn| {
        return @ptrCast(get_proc_addr_fn(instance, name));
    }

    @panic("SDL_Vulkan_GetVkGetInstanceProcAddr returned null");
}

fn createDebugCallback(
    instance: c.VkInstance,
    debug_callback: c.PFN_vkDebugUtilsMessengerCallbackEXT,
    allocationcallbacks: ?*c.VkAllocationCallbacks,
) c.VkDebugUtilsMessengerEXT {
    const create_fn_opt = getVulkanInstanceFunct(
        c.PFN_vkCreateDebugUtilsMessengerEXT,
        instance,
        "vkCreateDebugUtilsMessengerEXT",
    );
    if (create_fn_opt) |create_fn| {
        const create_info = std.mem.zeroInit(c.VkDebugUtilsMessengerCreateInfoEXT, .{
            .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
                c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_DEVICE_ADDRESS_BINDING_BIT_EXT |
                c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            .pfnUserCallback = debug_callback orelse defaultDebugCallback,
            .pUserData = null,
        });
        var debug_messenger: c.VkDebugUtilsMessengerEXT = undefined;
        checkVkPanic(create_fn(instance, &create_info, allocationcallbacks, &debug_messenger));
        log.info("Created vulkan debug messenger.", .{});
        return debug_messenger;
    }
    return null;
}

pub fn deinit(self: *Self, allocationcallbacks: ?*c.VkAllocationCallbacks) void {
    defer c.vkDestroyInstance(self.handle, allocationcallbacks);
    defer if (self.debug_messenger != null) {
        const destroyFn = getDestroyDebugUtilsMessenger(self).?;
        destroyFn(self.handle, self.debug_messenger, allocationcallbacks);
    };
}
