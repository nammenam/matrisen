const c = @import("c");
const std = @import("std");

pub fn checkVk(result: c.VkResult) !void {
    return switch (result) {
        c.VK_SUCCESS => {},
        c.VK_NOT_READY => error.vk_not_ready,
        c.VK_TIMEOUT => error.vk_timeout,
        c.VK_EVENT_SET => error.vk_event_set,
        c.VK_EVENT_RESET => error.vk_event_reset,
        c.VK_INCOMPLETE => error.vk_incomplete,
        c.VK_ERROR_OUT_OF_HOST_MEMORY => error.vk_error_out_of_host_memory,
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => error.vk_error_out_of_device_memory,
        c.VK_ERROR_INITIALIZATION_FAILED => error.vk_error_initialization_failed,
        c.VK_ERROR_DEVICE_LOST => error.vk_error_device_lost,
        c.VK_ERROR_MEMORY_MAP_FAILED => error.vk_error_memory_map_failed,
        c.VK_ERROR_LAYER_NOT_PRESENT => error.vk_error_layer_not_present,
        c.VK_ERROR_EXTENSION_NOT_PRESENT => error.vk_error_extension_not_present,
        c.VK_ERROR_FEATURE_NOT_PRESENT => error.vk_error_feature_not_present,
        c.VK_ERROR_INCOMPATIBLE_DRIVER => error.vk_error_incompatible_driver,
        c.VK_ERROR_TOO_MANY_OBJECTS => error.vk_error_too_many_objects,
        c.VK_ERROR_FORMAT_NOT_SUPPORTED => error.vk_error_format_not_supported,
        c.VK_ERROR_FRAGMENTED_POOL => error.vk_error_fragmented_pool,
        c.VK_ERROR_UNKNOWN => error.vk_error_unknown,
        c.VK_ERROR_OUT_OF_POOL_MEMORY => error.vk_error_out_of_pool_memory,
        c.VK_ERROR_INVALID_EXTERNAL_HANDLE => error.vk_error_invalid_external_handle,
        c.VK_ERROR_FRAGMENTATION => error.vk_error_fragmentation,
        c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => error.vk_error_invalid_opaque_capture_address,
        c.VK_PIPELINE_COMPILE_REQUIRED => error.vk_pipeline_compile_required,
        c.VK_ERROR_SURFACE_LOST_KHR => error.vk_error_surface_lost_khr,
        c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => error.vk_error_native_window_in_use_khr,
        c.VK_SUBOPTIMAL_KHR => error.vk_suboptimal_khr,
        c.VK_ERROR_OUT_OF_DATE_KHR => error.vk_error_out_of_date_khr,
        c.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => error.vk_error_incompatible_display_khr,
        c.VK_ERROR_VALIDATION_FAILED_EXT => error.vk_error_validation_failed_ext,
        c.VK_ERROR_INVALID_SHADER_NV => error.vk_error_invalid_shader_nv,
        c.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => error.vk_error_image_usage_not_supported_khr,
        c.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => error.vk_error_video_picture_layout_not_supported_khr,
        c.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => error.vk_error_video_profile_operation_not_supported_khr,
        c.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => error.vk_error_video_profile_format_not_supported_khr,
        c.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => error.vk_error_video_profile_codec_not_supported_khr,
        c.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => error.vk_error_video_std_version_not_supported_khr,
        c.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => error.vk_error_invalid_drm_format_modifier_plane_layout_ext,
        c.VK_ERROR_NOT_PERMITTED_KHR => error.vk_error_not_permitted_khr,
        c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => error.vk_error_full_screen_exclusive_mode_lost_ext,
        c.VK_THREAD_IDLE_KHR => error.vk_thread_idle_khr,
        c.VK_THREAD_DONE_KHR => error.vk_thread_done_khr,
        c.VK_OPERATION_DEFERRED_KHR => error.vk_operation_deferred_khr,
        c.VK_OPERATION_NOT_DEFERRED_KHR => error.vk_operation_not_deferred_khr,
        c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => error.vk_error_compression_exhausted_ext,
        c.VK_ERROR_INCOMPATIBLE_SHADER_BINARY_EXT => error.vk_error_incompatible_shader_binary_ext,
        else => error.vk_errror_unknown,
    };
}

pub fn checkVkPanic(result: c.VkResult) void {
    switch (result) {
        c.VK_SUCCESS => {
            return;
        },
        c.VK_NOT_READY => {
            std.log.warn("Not ready", .{});
            return;
        },
        c.VK_TIMEOUT => {
            std.log.warn("Timeout", .{});
            return;
        },
        c.VK_EVENT_SET => {
            std.log.warn("Event set", .{});
            return;
        },
        c.VK_EVENT_RESET => {
            std.log.warn("Event reset", .{});
            return;
        },
        c.VK_INCOMPLETE => {
            std.log.warn("Incomplete", .{});
            return;
        },
        c.VK_ERROR_OUT_OF_HOST_MEMORY => {
            std.log.err("Error out of host memory", .{});
            @panic("");
        },
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => {
            std.log.err("Error out of device memory", .{});
            @panic("");
        },
        c.VK_ERROR_INITIALIZATION_FAILED => {
            std.log.err("Error initialization failed", .{});
            @panic("");
        },
        c.VK_ERROR_DEVICE_LOST => {
            std.log.err("Error device lost", .{});
            @panic("");
        },
        c.VK_ERROR_MEMORY_MAP_FAILED => {
            std.log.err("Error memory map failed", .{});
            @panic("");
        },
        c.VK_ERROR_LAYER_NOT_PRESENT => {
            std.log.err("Error layer not present", .{});
            @panic("");
        },
        c.VK_ERROR_EXTENSION_NOT_PRESENT => {
            std.log.err("Error extension not present", .{});
            @panic("");
        },
        c.VK_ERROR_FEATURE_NOT_PRESENT => {
            std.log.err("Error feature not present", .{});
            @panic("");
        },
        c.VK_ERROR_INCOMPATIBLE_DRIVER => {
            std.log.err("Error incompatible driver", .{});
            @panic("");
        },
        c.VK_ERROR_TOO_MANY_OBJECTS => {
            std.log.err("Error too many objects", .{});
            @panic("");
        },
        c.VK_ERROR_FORMAT_NOT_SUPPORTED => {
            std.log.err("Error format not supported", .{});
            @panic("");
        },
        c.VK_ERROR_FRAGMENTED_POOL => {
            std.log.err("Error fragmented pool", .{});
            @panic("");
        },
        c.VK_ERROR_UNKNOWN => {
            std.log.err("Error unknown", .{});
            @panic("");
        },
        c.VK_ERROR_OUT_OF_POOL_MEMORY => {
            std.log.err("Error out of pool memory", .{});
            @panic("");
        },
        c.VK_ERROR_INVALID_EXTERNAL_HANDLE => {
            std.log.err("Error invalid external handle", .{});
            @panic("");
        },
        c.VK_ERROR_FRAGMENTATION => {
            std.log.err("Error fragmentation", .{});
            @panic("");
        },
        c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => {
            std.log.err("Error invalid opaque capture address", .{});
            @panic("");
        },
        c.VK_PIPELINE_COMPILE_REQUIRED => {
            std.log.err("Pipeline compile required", .{});
            @panic("");
        },
        c.VK_ERROR_SURFACE_LOST_KHR => {
            std.log.err("Error surface lost khr", .{});
            @panic("");
        },
        c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => {
            std.log.err("Error native window in use khr", .{});
            @panic("");
        },
        c.VK_SUBOPTIMAL_KHR => {
            std.log.err("Suboptimal khr", .{});
            @panic("");
        },
        c.VK_ERROR_OUT_OF_DATE_KHR => {
            std.log.err("Error out of date khr", .{});
            @panic("");
        },
        c.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => {
            std.log.err("Error incompatible display khr", .{});
            @panic("");
        },
        c.VK_ERROR_VALIDATION_FAILED_EXT => {
            std.log.err("Error validation failed ext", .{});
            @panic("");
        },
        c.VK_ERROR_INVALID_SHADER_NV => {
            std.log.err("Error invalid shader nv", .{});
            @panic("");
        },
        c.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => {
            std.log.err("Error image usage not supported khr", .{});
            @panic("");
        },
        c.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => {
            std.log.err("Error video picture layout not supported khr", .{});
            @panic("");
        },
        c.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => {
            std.log.err("Error video profile operation not supported khr", .{});
            @panic("");
        },
        c.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => {
            std.log.err("Error video profile format not supported khr", .{});
            @panic("");
        },
        c.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => {
            std.log.err("Error video profile codec not supported khr", .{});
            @panic("");
        },
        c.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => {
            std.log.err("Error video std version not supported khr", .{});
            @panic("");
        },
        c.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => {
            std.log.err("Error invalid drm format modifier plane layout ext", .{});
            @panic("");
        },
        c.VK_ERROR_NOT_PERMITTED_KHR => {
            std.log.err("Error not permitted khr", .{});
            @panic("");
        },
        c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => {
            std.log.err("Error full screen exclusive mode lost ext", .{});
            @panic("");
        },
        c.VK_THREAD_IDLE_KHR => {
            std.log.err("Thread idle khr", .{});
            @panic("");
        },
        c.VK_THREAD_DONE_KHR => {
            std.log.err("Thread done khr", .{});
            @panic("");
        },
        c.VK_OPERATION_DEFERRED_KHR => {
            std.log.err("Operation deferred khr", .{});
            @panic("");
        },
        c.VK_OPERATION_NOT_DEFERRED_KHR => {
            std.log.err("Operation not deferred khr", .{});
            @panic("");
        },
        c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => {
            std.log.err("Error compression exhausted ext", .{});
            @panic("");
        },
        c.VK_ERROR_INCOMPATIBLE_SHADER_BINARY_EXT => {
            std.log.err("Error incompatible shader binary ext", .{});
            @panic("");
        },
        else => {
            std.log.err("Unknown error", .{});
            @panic("");
        },
    }
}
