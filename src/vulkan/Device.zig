const c = @import("../clibs/clibs.zig").libs;
const std = @import("std");
const checkVkPanic = @import("debug.zig").checkVkPanic;
const log = std.log.scoped(.device);
const required_device_extensions: []const [*c]const u8 = &.{ "VK_KHR_swapchain", "VK_EXT_mesh_shader" };
const PhysicalDevice = @import("PhysicalDevice.zig");

pub var vkCmdDrawMeshTasksEXT: c.PFN_vkCmdDrawMeshTasksEXT = null;

const Self = @This();

handle: c.VkDevice,
graphics_queue: c.VkQueue,
present_queue: c.VkQueue,
compute_queue: c.VkQueue,
transfer_queue: c.VkQueue,

pub fn init(alloc: std.mem.Allocator, physical_device: PhysicalDevice) Self {
    const alloc_cb: ?*c.VkAllocationCallbacks = null;

    // var meshshading: c.VkPhysicalDeviceMeshShaderFeaturesEXT = .{
    //     .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT,
    //     .taskShader = c.VK_TRUE,
    //     .meshShader = c.VK_TRUE,
    // };
    // var features14: c.VkPhysicalDeviceVulkan14Features = .{
    //     .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_4_FEATURES,
    //     .dynamicRenderingLocalRead = c.VK_TRUE,
    // };
    var features13: c.VkPhysicalDeviceVulkan13Features = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        // .pNext = &features14,
        .dynamicRendering = c.VK_TRUE,
        .synchronization2 = c.VK_TRUE,
    };

    var features12: c.VkPhysicalDeviceVulkan12Features = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .bufferDeviceAddress = c.VK_TRUE,
        .descriptorIndexing = c.VK_TRUE,
        .drawIndirectCount = c.VK_TRUE,
        .pNext = &features13,
    };

    var shader_draw_parameters_features: c.VkPhysicalDeviceShaderDrawParametersFeatures = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES,
        .shaderDrawParameters = c.VK_TRUE,
        .pNext = &features12,
    };

    var deviceFeatures2: c.VkPhysicalDeviceFeatures2 = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
        .pNext = &shader_draw_parameters_features,
        .features = .{ .multiDrawIndirect = c.VK_TRUE },
    };

    var queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo){};
    const queue_priorities: f32 = 1.0;
    var queue_family_set = std.AutoArrayHashMapUnmanaged(u32, void){};
    queue_family_set.put(alloc, physical_device.graphics_queue_family, {}) catch {
        log.err("failed to alloc", .{});
        @panic("");
    };
    queue_family_set.put(alloc, physical_device.present_queue_family, {}) catch {
        log.err("failed to alloc", .{});
        @panic("");
    };
    queue_family_set.put(alloc, physical_device.compute_queue_family, {}) catch {
        log.err("failed to alloc", .{});
        @panic("");
    };
    queue_family_set.put(alloc, physical_device.transfer_queue_family, {}) catch {
        log.err("failed to alloc", .{});
        @panic("");
    };
    var qfi_iter = queue_family_set.iterator();
    queue_create_infos.ensureTotalCapacity(alloc, queue_family_set.count()) catch {
        log.err("failed to alloc", .{});
        @panic("");
    };
    while (qfi_iter.next()) |qfi| {
        queue_create_infos.append(alloc, std.mem.zeroInit(c.VkDeviceQueueCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = qfi.key_ptr.*,
            .queueCount = 1,
            .pQueuePriorities = &queue_priorities,
        })) catch {
            log.err("failed to append", .{});
            @panic("");
        };
    }

    const device_info: c.VkDeviceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &deviceFeatures2,
        .queueCreateInfoCount = @as(u32, @intCast(queue_create_infos.items.len)),
        .pQueueCreateInfos = queue_create_infos.items.ptr,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = @as(u32, @intCast(required_device_extensions.len)),
        .ppEnabledExtensionNames = required_device_extensions.ptr,
        .pEnabledFeatures = null,
    };

    var device: c.VkDevice = undefined;
    checkVkPanic(c.vkCreateDevice(physical_device.handle, &device_info, alloc_cb, &device));

    var graphics_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(device, physical_device.graphics_queue_family, 0, &graphics_queue);
    var present_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(device, physical_device.present_queue_family, 0, &present_queue);
    var compute_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(device, physical_device.compute_queue_family, 0, &compute_queue);
    var transfer_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(device, physical_device.transfer_queue_family, 0, &transfer_queue);

    // TODO fix this ugly ahh pointer thing
    const procAddr: c.PFN_vkCmdDrawMeshTasksEXT = @ptrCast(c.vkGetDeviceProcAddr(device, "vkCmdDrawMeshTasksEXT"));
    if (procAddr == null) {
        @panic("");
    }
    vkCmdDrawMeshTasksEXT = procAddr;
    log.info("created logical device", .{});
    return .{
        .handle = device,
        .graphics_queue = graphics_queue,
        .present_queue = present_queue,
        .compute_queue = compute_queue,
        .transfer_queue = transfer_queue,
    };
}

pub fn deinit() void {}
