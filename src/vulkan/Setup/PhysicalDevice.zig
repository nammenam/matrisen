const c = @import("../clibs/clibs.zig").libs;
const std = @import("std");
const log = std.log.scoped(.physicaldevice);
const checkVkPanic = @import("debug.zig").checkVkPanic;
const config = @import("config");
const api_version = @import("Instance.zig").api_version;
const required_device_extensions: []const [*c]const u8 = &.{ "VK_KHR_swapchain", "VK_EXT_mesh_shader" };
const Core = @import("Core.zig");
const SwapchainSupportInfo = @import("Swapchain.zig").SupportInfo;

pub var vkCmdDrawMeshTasksEXT: c.PFN_vkCmdDrawMeshTasksEXT = null;
const INVALID_QUEUE_FAMILY_INDEX = std.math.maxInt(u32);

const PhysicalDeviceSelectionCriteria = enum {
    First,
    PreferDiscrete,
    PreferIntegrated,
};

const Self = @This();

handle: c.VkPhysicalDevice = null,
properties: c.VkPhysicalDeviceProperties = undefined,
graphics_queue_family: u32 = undefined,
present_queue_family: u32 = undefined,
compute_queue_family: u32 = undefined,
transfer_queue_family: u32 = undefined,

pub fn select(alloc: std.mem.Allocator, instance: c.VkInstance, surface: c.VkSurfaceKHR) Self {
    const criteria = PhysicalDeviceSelectionCriteria.PreferDiscrete;
    var physical_device_count: u32 = undefined;
    checkVkPanic(c.vkEnumeratePhysicalDevices(instance, &physical_device_count, null));

    const physical_devices = alloc.alloc(c.VkPhysicalDevice, physical_device_count) catch {
        log.err("failed to alloc", .{});
        @panic("");
    };
    checkVkPanic(c.vkEnumeratePhysicalDevices(instance, &physical_device_count, physical_devices.ptr));

    var suitable_pd: ?Self = null;

    for (physical_devices) |device| {
        const pd = makePhysicalDevice(alloc, device, surface) catch continue;
        _ = isPhysicalDeviceSuitable(alloc, pd, surface) catch continue;
        switch (criteria) {
            PhysicalDeviceSelectionCriteria.First => {
                suitable_pd = pd;
                break;
            },
            PhysicalDeviceSelectionCriteria.PreferDiscrete => {
                if (pd.properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
                    suitable_pd = pd;
                    break;
                } else if (suitable_pd == null) {
                    suitable_pd = pd;
                }
            },
            PhysicalDeviceSelectionCriteria.PreferIntegrated => {
                if (pd.properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
                    suitable_pd = pd;
                    break;
                } else if (suitable_pd == null) {
                    suitable_pd = pd;
                }
            },
        }
    }

    if (suitable_pd == null) {
        log.err("No suitable physical device found.", .{});
        @panic("");
    }
    const res = suitable_pd.?;

    const device_name = @as([*:0]const u8, @ptrCast(@alignCast(res.properties.deviceName[0..])));
    log.info("Selected physical device: {s}", .{device_name});
    return res;
}

fn makePhysicalDevice(
    a: std.mem.Allocator,
    device: c.VkPhysicalDevice,
    surface: ?c.VkSurfaceKHR,
) !Self {
    var props = std.mem.zeroInit(c.VkPhysicalDeviceProperties, .{});
    c.vkGetPhysicalDeviceProperties(device, &props);

    var graphics_queue_family: u32 = INVALID_QUEUE_FAMILY_INDEX;
    var present_queue_family: u32 = INVALID_QUEUE_FAMILY_INDEX;
    var compute_queue_family: u32 = INVALID_QUEUE_FAMILY_INDEX;
    var transfer_queue_family: u32 = INVALID_QUEUE_FAMILY_INDEX;

    var queue_family_count: u32 = undefined;
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);
    const queue_families = a.alloc(c.VkQueueFamilyProperties, queue_family_count) catch {
        log.err("failed to alloc", .{});
        @panic("");
    };
    defer a.free(queue_families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

    for (queue_families, 0..) |queue_family, i| {
        const index: u32 = @intCast(i);

        if (graphics_queue_family == INVALID_QUEUE_FAMILY_INDEX and
            queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0)
        {
            graphics_queue_family = index;
        }

        if (surface) |surf| {
            if (present_queue_family == INVALID_QUEUE_FAMILY_INDEX) {
                var present_support: c.VkBool32 = undefined;
                checkVkPanic(c.vkGetPhysicalDeviceSurfaceSupportKHR(device, index, surf, &present_support));
                if (present_support == c.VK_TRUE) {
                    present_queue_family = index;
                }
            }
        }

        if (compute_queue_family == INVALID_QUEUE_FAMILY_INDEX and
            queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0)
        {
            compute_queue_family = index;
        }

        if (transfer_queue_family == INVALID_QUEUE_FAMILY_INDEX and
            queue_family.queueFlags & c.VK_QUEUE_TRANSFER_BIT != 0)
        {
            transfer_queue_family = index;
        }

        if (graphics_queue_family != INVALID_QUEUE_FAMILY_INDEX and
            present_queue_family != INVALID_QUEUE_FAMILY_INDEX and
            compute_queue_family != INVALID_QUEUE_FAMILY_INDEX and
            transfer_queue_family != INVALID_QUEUE_FAMILY_INDEX)
        {
            break;
        }
    }

    return .{
        .handle = device,
        .properties = props,
        .graphics_queue_family = graphics_queue_family,
        .present_queue_family = present_queue_family,
        .compute_queue_family = compute_queue_family,
        .transfer_queue_family = transfer_queue_family,
    };
}

fn isPhysicalDeviceSuitable(
    alloc: std.mem.Allocator,
    device: Self,
    surface: ?c.VkSurfaceKHR,
) !bool {
    if (device.properties.apiVersion < api_version) {
        return false;
    }

    if (device.graphics_queue_family == INVALID_QUEUE_FAMILY_INDEX or
        device.present_queue_family == INVALID_QUEUE_FAMILY_INDEX or
        device.compute_queue_family == INVALID_QUEUE_FAMILY_INDEX or
        device.transfer_queue_family == INVALID_QUEUE_FAMILY_INDEX)
    {
        return false;
    }

    if (surface) |surf| {
        const swapchain_support = SwapchainSupportInfo.init(alloc, device.handle, surf);
        defer swapchain_support.deinit(alloc);
        if (swapchain_support.formats.len == 0 or swapchain_support.present_modes.len == 0) {
            return false;
        }
    }

    if (required_device_extensions.len > 0) {
        var device_extension_count: u32 = undefined;
        checkVkPanic(c.vkEnumerateDeviceExtensionProperties(device.handle, null, &device_extension_count, null));
        const device_extensions = alloc.alloc(c.VkExtensionProperties, device_extension_count) catch {
            log.err("failed to alloc", .{});
            @panic("");
        };
        checkVkPanic(c.vkEnumerateDeviceExtensionProperties(
            device.handle,
            null,
            &device_extension_count,
            device_extensions.ptr,
        ));

        _ = blk: for (required_device_extensions) |req_ext| {
            for (device_extensions) |device_ext| {
                const device_ext_name: [*c]const u8 = @ptrCast(device_ext.extensionName[0..]);
                if (std.mem.eql(u8, std.mem.span(req_ext), std.mem.span(device_ext_name))) {
                    break :blk true;
                }
            }
        } else return false;
    }

    return true;
}

pub fn deinit() void {}
