pub const PhysicalDeviceSelectionCriteria = enum {
    First,
    PreferDiscrete,
    PreferIntegrated,
};

pub const PhysicalDeviceSelectOpts = struct { min_api_version: u32 = c.VK_MAKE_VERSION(1, 3, 0), required_extensions: []const [*c]const u8 = &.{}, surface: ?c.VkSurfaceKHR, criteria: PhysicalDeviceSelectionCriteria = .PreferDiscrete };

pub const PhysicalDevice = struct {
    handle: c.VkPhysicalDevice = null,
    properties: c.VkPhysicalDeviceProperties = undefined,
    graphics_queue_family: u32 = undefined,
    present_queue_family: u32 = undefined,
    compute_queue_family: u32 = undefined,
    transfer_queue_family: u32 = undefined,

    const INVALID_QUEUE_FAMILY_INDEX = std.math.maxInt(u32);

    pub fn select(a: std.mem.Allocator, instance: c.VkInstance, opts: PhysicalDeviceSelectOpts) !PhysicalDevice {
        var physical_device_count: u32 = undefined;
        try check_vk(c.vkEnumeratePhysicalDevices(instance, &physical_device_count, null));

        var arena_state = std.heap.ArenaAllocator.init(a);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const physical_devices = try arena.alloc(c.VkPhysicalDevice, physical_device_count);
        try check_vk(c.vkEnumeratePhysicalDevices(instance, &physical_device_count, physical_devices.ptr));

        var suitable_pd: ?PhysicalDevice = null;

        for (physical_devices) |device| {
            const pd = make_physical_device(a, device, opts.surface) catch continue;
            _ = is_physical_device_suitable(a, pd, opts) catch continue;
            switch (opts.criteria) {
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
            return error.vulkan_no_suitable_physical_device;
        }
        const res = suitable_pd.?;

        const device_name = @as([*:0]const u8, @ptrCast(@alignCast(res.properties.deviceName[0..])));
        log.info("Selected physical device: {s}", .{device_name});

        return res;
    }

    fn make_physical_device(a: std.mem.Allocator, device: c.VkPhysicalDevice, surface: ?c.VkSurfaceKHR) !PhysicalDevice {
        var props = std.mem.zeroInit(c.VkPhysicalDeviceProperties, .{});
        c.vkGetPhysicalDeviceProperties(device, &props);

        var graphics_queue_family: u32 = PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX;
        var present_queue_family: u32 = PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX;
        var compute_queue_family: u32 = PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX;
        var transfer_queue_family: u32 = PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX;

        var queue_family_count: u32 = undefined;
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);
        const queue_families = try a.alloc(c.VkQueueFamilyProperties, queue_family_count);
        defer a.free(queue_families);
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

        for (queue_families, 0..) |queue_family, i| {
            const index: u32 = @intCast(i);

            if (graphics_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX and
                queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0)
            {
                graphics_queue_family = index;
            }

            if (surface) |surf| {
                if (present_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX) {
                    var present_support: c.VkBool32 = undefined;
                    try check_vk(c.vkGetPhysicalDeviceSurfaceSupportKHR(device, index, surf, &present_support));
                    if (present_support == c.VK_TRUE) {
                        present_queue_family = index;
                    }
                }
            }

            if (compute_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX and
                queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0)
            {
                compute_queue_family = index;
            }

            if (transfer_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX and
                queue_family.queueFlags & c.VK_QUEUE_TRANSFER_BIT != 0)
            {
                transfer_queue_family = index;
            }

            if (graphics_queue_family != PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX and
                present_queue_family != PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX and
                compute_queue_family != PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX and
                transfer_queue_family != PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX)
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

    fn is_physical_device_suitable(a: std.mem.Allocator, device: PhysicalDevice, opts: PhysicalDeviceSelectOpts) !bool {
        if (device.properties.apiVersion < opts.min_api_version) {
            return false;
        }

        if (device.graphics_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX or
            device.present_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX or
            device.compute_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX or
            device.transfer_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX)
        {
            return false;
        }

        var arena_state = std.heap.ArenaAllocator.init(a);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        if (opts.surface) |surf| {
            const swapchain_support = try SwapchainSupportInfo.init(arena, device.handle, surf);
            defer swapchain_support.deinit(arena);
            if (swapchain_support.formats.len == 0 or swapchain_support.present_modes.len == 0) {
                return false;
            }
        }

        if (opts.required_extensions.len > 0) {
            var device_extension_count: u32 = undefined;
            try check_vk(c.vkEnumerateDeviceExtensionProperties(device.handle, null, &device_extension_count, null));
            const device_extensions = try arena.alloc(c.VkExtensionProperties, device_extension_count);
            try check_vk(c.vkEnumerateDeviceExtensionProperties(device.handle, null, &device_extension_count, device_extensions.ptr));

            _ = blk: for (opts.required_extensions) |req_ext| {
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
};

const DeviceCreateOpts = struct {
    physical_device: PhysicalDevice,
    extensions: []const [*c]const u8 = &.{},
    features: ?c.VkPhysicalDeviceFeatures = null,
    alloc_cb: ?*const c.VkAllocationCallbacks = null,
    pnext: ?*const anyopaque = null,
};

pub const Device = struct {
    handle: c.VkDevice = null,
    graphics_queue: c.VkQueue = null,
    present_queue: c.VkQueue = null,
    compute_queue: c.VkQueue = null,
    transfer_queue: c.VkQueue = null,

    pub fn create(a: std.mem.Allocator, opts: DeviceCreateOpts) !Device {
        var arena_state = std.heap.ArenaAllocator.init(a);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        var queue_create_infos = std.ArrayListUnmanaged(c.VkDeviceQueueCreateInfo){};
        const queue_priorities: f32 = 1.0;
        var queue_family_set = std.AutoArrayHashMapUnmanaged(u32, void){};
        try queue_family_set.put(arena, opts.physical_device.graphics_queue_family, {});
        try queue_family_set.put(arena, opts.physical_device.present_queue_family, {});
        try queue_family_set.put(arena, opts.physical_device.compute_queue_family, {});
        try queue_family_set.put(arena, opts.physical_device.transfer_queue_family, {});
        var qfi_iter = queue_family_set.iterator();
        try queue_create_infos.ensureTotalCapacity(arena, queue_family_set.count());
        while (qfi_iter.next()) |qfi| {
            try queue_create_infos.append(arena, std.mem.zeroInit(c.VkDeviceQueueCreateInfo, .{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = qfi.key_ptr.*,
                .queueCount = 1,
                .pQueuePriorities = &queue_priorities,
            }));
        }

        const device_info = std.mem.zeroInit(c.VkDeviceCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = opts.pnext,
            .queueCreateInfoCount = @as(u32, @intCast(queue_create_infos.items.len)),
            .pQueueCreateInfos = queue_create_infos.items.ptr,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = @as(u32, @intCast(opts.extensions.len)),
            .ppEnabledExtensionNames = opts.extensions.ptr,
            .pEnabledFeatures = if (opts.features) |capture| &capture else null,
        });

        var device: c.VkDevice = undefined;
        try check_vk(c.vkCreateDevice(opts.physical_device.handle, &device_info, opts.alloc_cb, &device));

        var graphics_queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, opts.physical_device.graphics_queue_family, 0, &graphics_queue);
        var present_queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, opts.physical_device.present_queue_family, 0, &present_queue);
        var compute_queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, opts.physical_device.compute_queue_family, 0, &compute_queue);
        var transfer_queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, opts.physical_device.transfer_queue_family, 0, &transfer_queue);

        return .{
            .handle = device,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
            .compute_queue = compute_queue,
            .transfer_queue = transfer_queue,
        };
    }
};
