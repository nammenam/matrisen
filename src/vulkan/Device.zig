const c = @import("../clibs/clibs.zig").libs;
const std = @import("std");
const checkVkPanic = @import("debug.zig").checkVkPanic;
const log = std.log.scoped(.device);
const required_device_extensions: []const [*c]const u8 = &.{ "VK_KHR_swapchain", "VK_EXT_mesh_shader" };
const PhysicalDevice = @import("PhysicalDevice.zig");

const Self = @This();

handle: c.VkDevice,
graphics_queue: c.VkQueue,
present_queue: c.VkQueue,
compute_queue: c.VkQueue,
transfer_queue: c.VkQueue,

vkCmdDrawMeshTasksEXT: c.PFN_vkCmdDrawMeshTasksIndirectCountEXT,

pub fn init(alloc: std.mem.Allocator, physical_device: PhysicalDevice) !Self {
    const alloc_cb: ?*c.VkAllocationCallbacks = null;

    var meshshading: c.VkPhysicalDeviceMeshShaderFeaturesEXT = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT,
        .taskShader = c.VK_TRUE,
        .meshShader = c.VK_TRUE,
        .pNext = null,
    };

    // 2. Vulkan 1.4 Core Features
    var features14: c.VkPhysicalDeviceVulkan14Features = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_4_FEATURES,
        .pNext = &meshshading, // Chain Mesh Shaders here
        .dynamicRenderingLocalRead = c.VK_TRUE,
    };

    // 3. Vulkan 1.3 Core Features
    var features13: c.VkPhysicalDeviceVulkan13Features = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .pNext = &features14, // Chain Vulkan 1.4 here
        .dynamicRendering = c.VK_TRUE,
        .synchronization2 = c.VK_TRUE,
    };

    // 4. Vulkan 1.2 Core Features
    var features12: c.VkPhysicalDeviceVulkan12Features = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .pNext = &features13, // Chain Vulkan 1.3 here
        .bufferDeviceAddress = c.VK_TRUE,
        .descriptorIndexing = c.VK_TRUE,
        .drawIndirectCount = c.VK_TRUE,
    };

    // 5. Shader Draw Parameters (Needed for multidraw indirect often)
    var shader_draw_parameters_features: c.VkPhysicalDeviceShaderDrawParametersFeatures = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES,
        .pNext = &features12, // Chain Vulkan 1.2 here
        .shaderDrawParameters = c.VK_TRUE,
    };

    // 6. Base Features 2 (This goes into device_info.pNext)
    var deviceFeatures2: c.VkPhysicalDeviceFeatures2 = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
        .pNext = &shader_draw_parameters_features,
        .features = .{
            .multiDrawIndirect = c.VK_TRUE,
            .fillModeNonSolid = c.VK_TRUE,
        },
    };

    var queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo){};
    defer queue_create_infos.deinit(alloc);
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
    while (qfi_iter.next()) |qfi| {
        try queue_create_infos.append(alloc, c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = qfi.key_ptr.*,
            .queueCount = 1,
            .pQueuePriorities = &queue_priorities,
        });
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

    const procAddr: c.PFN_vkCmdDrawMeshTasksIndirectCountEXT = @ptrCast(
        c.vkGetDeviceProcAddr(device, "vkCmdDrawMeshTasksIndirectCountEXT"),
    );
    if (procAddr == null) {
        log.err("Failed to load vkCmdDrawMeshTasksIndirectCountEXT", .{});
        return error.ExtensionFunctionNotLoaded;
    }

    log.info("created logical device", .{});

    return .{
        .handle = device,
        .graphics_queue = graphics_queue,
        .present_queue = present_queue,
        .compute_queue = compute_queue,
        .transfer_queue = transfer_queue,
        .vkCmdDrawMeshTasksEXT = procAddr, // Store it in the struct instance
    };
}

// 5. Implemented proper cleanup
pub fn deinit(self: *Self) void {
    if (self.handle != null) {
        c.vkDestroyDevice(self.handle, null);
    }
}
