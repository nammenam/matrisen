const std = @import("std");
const vki = @import("vulkanutils.zig");
const d = @import("descriptors.zig");
const c = @import("clibs.zig");
const m = @import("3Dmath.zig");
const s = @import("SDLutils.zig");
const r = @import("rendertarget.zig");
const PipelineBuilder = @import("pipelinebuilder.zig");
const t = @import("types.zig");
const load = @import("assetloader.zig");
const log = std.log.scoped(.vkEngine);
pub const vk_alloc_cbs: ?*c.VkAllocationCallbacks = null;
const check_vk = vki.check_vk;
const background_color_light: t.ComputePushConstants = .{
    .data1 = m.Vec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.0 },
    .data2 = m.Vec4{ .x = 0.8, .y = 0.8, .z = 0.8, .w = 0.0 },
    .data3 = m.Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
    .data4 = m.Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
};
const background_color_dark: t.ComputePushConstants = .{
    .data1 = m.Vec4{ .x = 0.05, .y = 0.05, .z = 0.05, .w = 0.0 },
    .data2 = m.Vec4{ .x = 0.08, .y = 0.08, .z = 0.08, .w = 0.0 },
    .data3 = m.Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
    .data4 = m.Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
};
const FRAME_OVERLAP = 2;
const render_scale = 1.0;
const GLTFMetallicRoughness = struct {
    opaque_pipeline: t.MaterialPipeline,
    transparent_pipeline: t.MaterialPipeline,
    materiallayout: c.VkDescriptorSetLayout,
    writer: d.DescriptorWriter,

    const MaterialConstants = struct { colorfactors: m.Vec4, metalrough_factors: m.Vec4, padding: [14]m.Vec4 };

    const MaterialResources = struct { colorimage: t.AllocatedImageAndView, colorsampler: c.VkSampler, metalroughimage: t.AllocatedImageAndView, metalroughsampler: c.VkSampler, databuffer: c.VkBuffer, databuffer_offset: u32 };

    pub fn build_pipelines(self: *@This(), engine: *Self) void {

        const vertex_code align(4) = @embedFile("mesh.vert").*;
        const fragment_code align(4) = @embedFile("mesh.frag").*;

        const vertex_module = vki.create_shader_module(self.device, &vertex_code, vk_alloc_cbs) orelse null;
        const fragment_module = vki.create_shader_module(self.device, &fragment_code, vk_alloc_cbs) orelse null;
        if (vertex_module != null) log.info("Created vertex shader module", .{});
        if (fragment_module != null) log.info("Created fragment shader module", .{});

        defer c.vkDestroyShaderModule(self.device, vertex_module, vk_alloc_cbs);
        defer c.vkDestroyShaderModule(self.device, fragment_module, vk_alloc_cbs);

        const matrixrange = c.VkPushConstantRange{
            .offset = 0,
            .size = @sizeOf(t.GPUDrawPushConstants),
            .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT
        };

        var layout_builder = d.DescriptorLayoutBuilder{};
        layout_builder.init(engine.cpu_allocator);
        layout_builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        layout_builder.add_binding(1, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        layout_builder.add_binding(2, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);

        self.materiallayout = layout_builder.build(engine.device, c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT);

        const layouts = [_]c.VkDescriptorSetLayout{ engine.gpuSceneDataDescriptorLayout, self.materialLayout };

        const mesh_layout_info = c.VKPipelineLayoutCreateInfo{
            .setLayoutCount = 2,
            .pSetLayouts = &layouts,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &matrixrange,
        };

        var newlayout: c.VkPipelineLayout = undefined;

        check_vk(c.vkCreatePipelineLayout(engine.device, &mesh_layout_info, null, &newlayout)) catch @panic("Failed to create pipeline layout");

        self.opaque_pipeline.layout = newlayout;
        self.transparent_pipeline.layout = newlayout;

        var pipelineBuilder = PipelineBuilder.init();
        pipelineBuilder.set_shaders(vertex_module, fragment_module);
        pipelineBuilder.set_input_topology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
        pipelineBuilder.set_polygon_mode(c.VK_POLYGON_MODE_FILL);
        pipelineBuilder.set_cull_mode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_CLOCKWISE);
        pipelineBuilder.set_multisampling_none();
        pipelineBuilder.disable_blending();
        pipelineBuilder.enable_depthtest(true, c.VK_COMPARE_OP_GREATER_OR_EQUAL);

        pipelineBuilder.set_color_attachment_format(engine.draw_image_format);
        pipelineBuilder.set_depth_format(engine.depth_image_format);

        pipelineBuilder.pipeline_layout = newlayout;

        self.opaque_pipeline.pipeline = pipelineBuilder.build_pipeline(engine.device);

        pipelineBuilder.enable_blending_additive();
        pipelineBuilder.enable_depthtest(false, .greater_or_equal);

        self.transparent_pipeline.pipeline = pipelineBuilder.build_pipeline(engine.device);
    }

    fn clear_resources(device: c.VkDevice) void {}

    fn write_material(self: *@This(), device: c.VkDevice, pass: t.MaterialPass, resources: MaterialResources, descriptor_allocator: *d.DescriptorAllocatorGrowable) t.MaterialInstance {
        const matdata = t.MaterialInstance;
        matdata.passtype = pass;
        if (pass == t.MaterialPass.Transparent) {
        matdata.pipeline = &self.transparent_pipeline;
        }
        else {
        matdata.pipeline = &self.opaque_pipeline;
        }

        matdata.materialset = descriptor_allocator.allocate(device, self.materiallayout);


        self.writer.clear();
        self.writer.write_buffer(0, resources.dataBuffer, @sizeOf(MaterialConstants), resources.dataBufferOffset, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        self.writer.write_image(1, resources.colorImage.imageView, resources.colorSampler, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        self.writer.write_image(2, resources.metalRoughImage.imageView, resources.metalRoughSampler, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);

        self.writer.update_set(device, matdata.materialSet);

        return matdata;
    }
};



const Self = @This();

resize_request: bool = false,
window: r.WindowManager = undefined,
window_extent: c.VkExtent2D = undefined,
depth_image: t.AllocatedImageAndView = undefined,
depth_image_format: c.VkFormat = undefined,
depth_image_extent: c.VkExtent3D = undefined,
draw_image: t.AllocatedImageAndView = undefined,
draw_image_format: c.VkFormat = undefined,
draw_image_extent: c.VkExtent3D = undefined,
draw_extent: c.VkExtent2D = undefined,
// allocators
cpu_allocator: std.mem.Allocator = undefined,
gpu_allocator: c.VmaAllocator = undefined,
// instance and device
instance: c.VkInstance = null,
gpu: c.VkPhysicalDevice = null,
gpu_properties: c.VkPhysicalDeviceProperties = undefined,
device: c.VkDevice = null,
// queues
graphics_queue: c.VkQueue = null,
present_queue: c.VkQueue = null,
compute_queue: c.VkQueue = null,
transfer_queue: c.VkQueue = null,
graphics_queue_family: u32 = undefined,
present_queue_family: u32 = undefined,
// delete queues
buffer_deletion_queue: vki.BufferDeletionStack = vki.BufferDeletionStack{},
image_deletion_queue: vki.ImageDeletionStack = vki.ImageDeletionStack{},
// imageview_deletion_queue: vki.ImageViewDeletionStack = vki.ImageViewDeletionStack{},
sampler_deletion_queue: vki.SamplerDeletionStack = vki.SamplerDeletionStack{},
pipeline_deletion_queue: vki.PipelineDeletionStack = vki.PipelineDeletionStack{},
pipeline_layout_deletion_queue: vki.PipelineLayoutDeletionStack = vki.PipelineLayoutDeletionStack{},
// swapchain and sync
swapchain: c.VkSwapchainKHR = null,
swapchain_format: c.VkFormat = undefined,
swapchain_extent: c.VkExtent2D = undefined,
swapchain_images: []c.VkImage = undefined,
swapchain_image_views: []c.VkImageView = undefined,
immidiate_fence: c.VkFence = null,
immidiate_command_buffer: c.VkCommandBuffer = null,
immidiate_command_pool: c.VkCommandPool = null,
frames: [FRAME_OVERLAP]t.FrameData = .{t.FrameData{}} ** FRAME_OVERLAP,
frame_number: u32 = 0,
// descriptors
global_descriptor_allocator: d.DescriptorAllocator = undefined,
draw_image_descriptors: c.VkDescriptorSet = undefined,
draw_image_descriptor_layout: c.VkDescriptorSetLayout = undefined,
gradient_pipeline_layout: c.VkPipelineLayout = null,
gradient_pipeline: c.VkPipeline = null,
gpu_scene_data_descriptor_layout: c.VkDescriptorSetLayout = undefined,
single_image_descriptor_layout: c.VkDescriptorSetLayout = undefined,
triangle_pipeline_layout: c.VkPipelineLayout = null,
triangle_pipeline: c.VkPipeline = null,
mesh_pipeline_layout: c.VkPipelineLayout = null,
mesh_pipeline: c.VkPipeline = null,
// other data
white_image: t.AllocatedImageAndView = undefined,
black_image: t.AllocatedImageAndView = undefined,
grey_image: t.AllocatedImageAndView = undefined,
error_checkerboard_image: t.AllocatedImageAndView = undefined,
default_sampler_linear: c.VkSampler = undefined,
default_sampler_nearest: c.VkSampler = undefined,
rectangle: t.GPUMeshBuffers = undefined,
suzanne: std.ArrayList(t.MeshAsset),
scene_data: t.GPUSceneData = undefined,
lua_state: ?*c.lua_State,
debug_messenger: c.VkDebugUtilsMessengerEXT = null,
pc: t.ComputePushConstants = background_color_light,
white: bool = true,

pub fn init(a: std.mem.Allocator) Self {
    const window_extent = c.VkExtent2D{ .width = 1600, .height = 900 };
    const win = try r.WindowManager.init(window_extent);

    var engine = Self{
        .window = win,
        .window_extent = window_extent,
        .cpu_allocator = a,
        .suzanne = std.ArrayList(t.MeshAsset).init(a),
        .lua_state = c.luaL_newstate(),
    };
    engine.buffer_deletion_queue.init(a);
    engine.image_deletion_queue.init(a);
    // engine.imageview_deletion_queue.init(a);
    engine.pipeline_deletion_queue.init(a);
    engine.pipeline_layout_deletion_queue.init(a);
    engine.sampler_deletion_queue.init(a);
    engine.init_instance();
    engine.window.create_surface(&engine);
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
    engine.init_default_data();
    engine.init_pipelines();
    c.luaL_openlibs(engine.lua_state);
    _ = c.SDL_ShowWindow(engine.window.sdl_window);
    return engine;
}

pub fn run(self: *Self) void {
    var timer = std.time.Timer.start() catch @panic("Failed to start timer");
    var delta: u64 = undefined;
    var quit = false;
    var event: c.SDL_Event = undefined;

    while (!quit) {
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    quit = true;
                },
                c.SDL_EVENT_KEY_DOWN => {
                    s.handle_key_down(self, event.key);
                    if (event.key.key == c.SDLK_R) {
                        // Reload and execute Lua script when 'R' is pressed
                        // const script_path = "script.lua";
                        // if (c.luaL_loadfilex(self.lua_state, script_path, null) == 0) {
                        //     if (c.lua_pcallk(self.lua_state, 0, 0, 0, 0, null) != 0) {
                        //         var len: usize = undefined;
                        //         const error_msg = c.lua_tolstring(self.lua_state, -1, &len);
                        //         if (error_msg != null) {
                        //             const error_slice = error_msg[0..len];
                        //             std.log.err("Failed to run script: {s}", .{error_slice});
                        //         } else {
                        //             std.log.err("Failed to run script: Unknown error", .{});
                        //         }
                        //     }
                        // } else {
                        //     std.log.err("Failed to load script: {s}", .{script_path});
                        // }
                        self.pc = if (self.white) blk: {
                            self.white = false;
                            break :blk background_color_dark;
                        } else blk: {
                            self.white = true;
                            break :blk background_color_light;
                        };
                    }
                },
                c.SDL_EVENT_WINDOW_RESIZED => {
                    self.resize_request = true;
                },
                c.SDL_EVENT_KEY_UP => {
                    s.handle_key_up(self, event.key);
                },
                else => {},
            }
        }
        if (self.frame_number % 100 == 0) {
            delta = timer.read();
            log.info("FPS: {d}", .{@as(u32, (@intFromFloat(100_000_000_000.0 / @as(f32, @floatFromInt(delta)))))});
            timer.reset();
        }
        if (self.resize_request) {
            self.resize_swapchain();
        }
        self.draw();
    }
}

pub fn cleanup(self: *Self) void {
    check_vk(c.vkDeviceWaitIdle(self.device)) catch @panic("Failed to wait for device idle");
    // self.imageview_deletion_queue.deinit(self.device, vk_alloc_cbs);
    self.image_deletion_queue.deinit(self.device, self.gpu_allocator, vk_alloc_cbs);
    self.buffer_deletion_queue.deinit(self.gpu_allocator);
    self.pipeline_deletion_queue.deinit(self.device, vk_alloc_cbs);
    self.pipeline_layout_deletion_queue.deinit(self.device, vk_alloc_cbs);
    self.sampler_deletion_queue.deinit(self.device, vk_alloc_cbs);

    c.vkDestroyDescriptorSetLayout(self.device, self.draw_image_descriptor_layout, vk_alloc_cbs);
    c.vkDestroyDescriptorSetLayout(self.device, self.gpu_scene_data_descriptor_layout, vk_alloc_cbs);
    c.vkDestroyDescriptorSetLayout(self.device, self.single_image_descriptor_layout, vk_alloc_cbs);
    self.global_descriptor_allocator.clear_descriptors(self.device);
    self.global_descriptor_allocator.destroy_pool(self.device);
    for (&self.frames) |*frame| {
        frame.buffer_deletion_queue.deinit(self.gpu_allocator);
        c.vkDestroyCommandPool(self.device, frame.command_pool, vk_alloc_cbs);
        c.vkDestroyFence(self.device, frame.render_fence, vk_alloc_cbs);
        c.vkDestroySemaphore(self.device, frame.render_semaphore, vk_alloc_cbs);
        c.vkDestroySemaphore(self.device, frame.swapchain_semaphore, vk_alloc_cbs);
        frame.frame_descriptors.deinit(self.device);
    }
    c.vkDestroyFence(self.device, self.immidiate_fence, vk_alloc_cbs);
    c.vkDestroyCommandPool(self.device, self.immidiate_command_pool, vk_alloc_cbs);

    c.vkDestroySwapchainKHR(self.device, self.swapchain, vk_alloc_cbs);
    for (self.swapchain_image_views) |view| {
        c.vkDestroyImageView(self.device, view, vk_alloc_cbs);
    }
    self.cpu_allocator.free(self.swapchain_image_views);
    self.cpu_allocator.free(self.swapchain_images);
    c.vmaDestroyAllocator(self.gpu_allocator);
    c.vkDestroyDevice(self.device, vk_alloc_cbs);
    c.vkDestroySurfaceKHR(self.instance, self.window.surface, vk_alloc_cbs);
    if (self.debug_messenger != null) {
        const destroy_fn = vki.get_destroy_debug_utils_messenger_fn(self.instance).?;
        destroy_fn(self.instance, self.debug_messenger, vk_alloc_cbs);
    }
    self.window.deinit();
    c.vkDestroyInstance(self.instance, vk_alloc_cbs);
    c.lua_close(self.lua_state);
}

fn get_current_frame(self: *Self) *t.FrameData {
    return &self.frames[@intCast(@mod(self.frame_number, FRAME_OVERLAP))];
}

fn draw(self: *Self) void {
    const timeout: u64 = 4_000_000_000; // 4 second in nanonesconds
    var frame = self.get_current_frame();
    check_vk(c.vkWaitForFences(self.device, 1, &frame.render_fence, c.VK_TRUE, timeout)) catch |err| {
        std.log.err("Failed to wait for render fence with error: {s}", .{@errorName(err)});
        @panic("Failed to wait for render fence");
    };

    frame.buffer_deletion_queue.flush(self.gpu_allocator);
    frame.frame_descriptors.clear_pools(self.device);

    var swapchain_image_index: u32 = undefined;
    var e = c.vkAcquireNextImageKHR(self.device, self.swapchain, timeout, frame.swapchain_semaphore, null, &swapchain_image_index);
    if (e == c.VK_ERROR_OUT_OF_DATE_KHR) {
        self.resize_request = true;
        return;
    }

    check_vk(c.vkResetFences(self.device, 1, &frame.render_fence)) catch @panic("Failed to reset render fence");
    check_vk(c.vkResetCommandBuffer(frame.main_command_buffer, 0)) catch @panic("Failed to reset command buffer");

    const cmd = frame.main_command_buffer;
    const cmd_begin_info = std.mem.zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });

    self.draw_extent.width = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain_extent.width, self.draw_image_extent.width))) * render_scale);
    self.draw_extent.height = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain_extent.height, self.draw_image_extent.height))) * render_scale);

    check_vk(c.vkBeginCommandBuffer(cmd, &cmd_begin_info)) catch @panic("Failed to begin command buffer");

    vki.transition_image(cmd, self.draw_image.image, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_GENERAL);
    self.draw_background(cmd);
    vki.transition_image(cmd, self.draw_image.image, c.VK_IMAGE_LAYOUT_GENERAL, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    vki.transition_image(cmd, self.depth_image.image, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL);
    self.draw_geometry(cmd);
    vki.transition_image(cmd, self.draw_image.image, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);

    vki.transition_image(cmd, self.swapchain_images[swapchain_image_index], c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    vki.copy_image_to_image(cmd, self.draw_image.image, self.swapchain_images[swapchain_image_index], self.draw_extent, self.swapchain_extent);
    vki.transition_image(cmd, self.swapchain_images[swapchain_image_index], c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);

    check_vk(c.vkEndCommandBuffer(cmd)) catch @panic("Failed to end command buffer");

    const cmd_info = std.mem.zeroInit(c.VkCommandBufferSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    });

    const wait_info = std.mem.zeroInit(c.VkSemaphoreSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = frame.swapchain_semaphore,
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

    check_vk(c.vkQueueSubmit2(self.graphics_queue, 1, &submit, frame.render_fence)) catch |err| {
        std.log.err("Failed to submit to graphics queue with error: {s}", .{@errorName(err)});
        @panic("Failed to submit to graphics queue");
    };

    const present_info = std.mem.zeroInit(c.VkPresentInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &frame.render_semaphore,
        .swapchainCount = 1,
        .pSwapchains = &self.swapchain,
        .pImageIndices = &swapchain_image_index,
    });
    e = c.vkQueuePresentKHR(self.graphics_queue, &present_info);
    if (e == c.VK_ERROR_OUT_OF_DATE_KHR) {
        self.resize_request = true;
    }
    self.frame_number +%= 1;
}

fn resize_swapchain(self: *Self) void {
    // log.info("Resizing swapchain", .{});
    check_vk(c.vkDeviceWaitIdle(self.device)) catch |err| {
        std.log.err("Failed to wait for device idle with error: {s}", .{@errorName(err)});
        @panic("Failed to wait for device idle");
    };
    c.vkDestroySwapchainKHR(self.device, self.swapchain, vk_alloc_cbs);
    for (self.swapchain_image_views) |view| {
        c.vkDestroyImageView(self.device, view, vk_alloc_cbs);
    }
    self.cpu_allocator.free(self.swapchain_image_views);
    self.cpu_allocator.free(self.swapchain_images);

    var win_width: c_int = undefined;
    var win_height: c_int = undefined;
    check_vk(c.SDL_GetWindowSize(self.window.sdl_window, &win_width, &win_height)) catch @panic("Failed to get window size");
    self.window_extent.width = @intCast(win_width);
    self.window_extent.height = @intCast(win_height);
    self.create_swapchain(self.window_extent.width, self.window_extent.height);
    self.resize_request = false;
}

fn draw_background(self: *Self, cmd: c.VkCommandBuffer) void {
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.gradient_pipeline);
    c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.gradient_pipeline_layout, 0, 1, &self.draw_image_descriptors, 0, null);
    c.vkCmdPushConstants(cmd, self.gradient_pipeline_layout, c.VK_SHADER_STAGE_COMPUTE_BIT, 0, @sizeOf(t.ComputePushConstants), &self.pc);
    c.vkCmdDispatch(cmd, self.window_extent.width / 32, self.window_extent.height / 32, 1);
}

fn draw_geometry(self: *Self, cmd: c.VkCommandBuffer) void {
    const color_attachment = std.mem.zeroInit(c.VkRenderingAttachmentInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.draw_image.view,
        .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
    });
    const depth_attachment = std.mem.zeroInit(c.VkRenderingAttachmentInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.depth_image.view,
        .imageLayout = c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{
            .depthStencil = .{ .depth = 0.0, .stencil = 0.0 },
        },
    });

    const render_info = std.mem.zeroInit(c.VkRenderingInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.draw_extent,
        },
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment,
        .pDepthAttachment = &depth_attachment,
    });

    const gpu_scene_data_buffer = self.create_buffer(@sizeOf(t.GPUSceneData), c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, c.VMA_MEMORY_USAGE_CPU_TO_GPU);
    var frame = self.get_current_frame();
    frame.buffer_deletion_queue.push(gpu_scene_data_buffer);

    const scene_uniform_data: *t.GPUSceneData = @alignCast(@ptrCast(gpu_scene_data_buffer.info.pMappedData.?));
    scene_uniform_data.* = self.scene_data;

    const global_descriptor = frame.frame_descriptors.allocate(self.device, self.gpu_scene_data_descriptor_layout, null);
    {
        var writer = d.DescriptorWriter{};
        writer.init(self.cpu_allocator);
        defer writer.deinit();
        writer.write_buffer(0, gpu_scene_data_buffer.buffer, @sizeOf(t.GPUSceneData), 0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        writer.update_set(self.device, global_descriptor);
    }

    c.vkCmdBeginRendering(cmd, &render_info);
    const viewport = std.mem.zeroInit(c.VkViewport, .{
        .x = 0.0,
        .y = 0.0,
        .width = @as(f32, @floatFromInt(self.draw_extent.width)),
        .height = @as(f32, @floatFromInt(self.draw_extent.height)),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    });

    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.mesh_pipeline);
    const image_set = self.get_current_frame().frame_descriptors.allocate(self.device, self.single_image_descriptor_layout, null);
    {
        var writer = d.DescriptorWriter{};
        writer.init(self.cpu_allocator);
        defer writer.deinit();
        writer.write_image(0, self.error_checkerboard_image.view, self.default_sampler_nearest, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        writer.update_set(self.device, image_set);
    }
    c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.mesh_pipeline_layout, 0, 1, &image_set, 0, null);

    c.vkCmdSetViewport(cmd, 0, 1, &viewport);

    const scissor = std.mem.zeroInit(c.VkRect2D, .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.draw_extent,
    });

    c.vkCmdSetScissor(cmd, 0, 1, &scissor);
    var view = m.Mat4.rotation(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, std.math.pi / 2.0);
    view = view.rotate(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, std.math.pi);
    view = view.translate(.{ .x = 0.0, .y = 0.0, .z = -5.0 });
    const projection = m.Mat4.perspective(70.0, @as(f32, @floatFromInt(self.draw_extent.width)) / @as(f32, @floatFromInt(self.draw_extent.height)), 1000.0, 1.0);
    var model = m.Mat4.mul(projection, view);
    model.i.y *= -1.0;
    var push_constants = t.GPUDrawPushConstants{
        .model = model,
        .vertex_buffer = self.suzanne.items[0].mesh_buffers.vertex_buffer_adress,
    };

    c.vkCmdPushConstants(cmd, self.mesh_pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(t.GPUDrawPushConstants), &push_constants);
    c.vkCmdBindIndexBuffer(cmd, self.suzanne.items[0].mesh_buffers.index_buffer.buffer, 0, c.VK_INDEX_TYPE_UINT32);
    const surface = self.suzanne.items[0].surfaces.items[0];
    c.vkCmdDrawIndexed(cmd, surface.count, 1, surface.start_index, 0, 0);
    c.vkCmdEndRendering(cmd);
}

pub fn immediate_submit(self: *Self, submit_ctx: anytype) void {
    comptime {
        var Context = @TypeOf(submit_ctx);
        var is_ptr = false;
        switch (@typeInfo(Context)) {
            .Struct, .Union, .Enum => {},
            .Pointer => |ptr| {
                if (ptr.size != .One) {
                    @compileError("Context must be a type with a submit function. " ++ @typeName(Context) ++ "is a multi element pointer");
                }
                Context = ptr.child;
                is_ptr = true;
                switch (Context) {
                    .Struct, .Union, .Enum, .Opaque => {},
                    else => @compileError("Context must be a type with a submit function. " ++ @typeName(Context) ++ "is a pointer to a non struct/union/enum/opaque type"),
                }
            },
            else => @compileError("Context must be a type with a submit method. Cannot use: " ++ @typeName(Context)),
        }

        if (!@hasDecl(Context, "submit")) {
            @compileError("Context should have a submit method");
        }

        const submit_fn_info = @typeInfo(@TypeOf(Context.submit));
        if (submit_fn_info != .Fn) {
            @compileError("Context submit method should be a function");
        }

        if (submit_fn_info.Fn.params.len != 2) {
            @compileError("Context submit method should have two parameters");
        }

        if (submit_fn_info.Fn.params[0].type != Context) {
            @compileError("Context submit method first parameter should be of type: " ++ @typeName(Context));
        }

        if (submit_fn_info.Fn.params[1].type != c.VkCommandBuffer) {
            @compileError("Context submit method second parameter should be of type: " ++ @typeName(c.VkCommandBuffer));
        }
    }
    check_vk(c.vkResetFences(self.device, 1, &self.immidiate_fence)) catch @panic("Failed to reset immidiate fence");
    check_vk(c.vkResetCommandBuffer(self.immidiate_command_buffer, 0)) catch @panic("Failed to reset immidiate command buffer");
    const cmd = self.immidiate_command_buffer;

    const commmand_begin_ci = std.mem.zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });
    check_vk(c.vkBeginCommandBuffer(cmd, &commmand_begin_ci)) catch @panic("Failed to begin command buffer");

    submit_ctx.submit(cmd);

    check_vk(c.vkEndCommandBuffer(cmd)) catch @panic("Failed to end command buffer");

    const cmd_info = std.mem.zeroInit(c.VkCommandBufferSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    });
    const submit_info = std.mem.zeroInit(c.VkSubmitInfo2, .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmd_info,
    });

    check_vk(c.vkQueueSubmit2(self.graphics_queue, 1, &submit_info, self.immidiate_fence)) catch @panic("Failed to submit to graphics queue");
    check_vk(c.vkWaitForFences(self.device, 1, &self.immidiate_fence, c.VK_TRUE, 1_000_000_000)) catch @panic("Failed to wait for immidiate fence");
}

fn create_buffer(self: *Self, alloc_size: usize, usage: c.VkBufferUsageFlags, memory_usage: c.VmaMemoryUsage) t.AllocatedBuffer {
    const buffer_info = std.mem.zeroInit(c.VkBufferCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = alloc_size,
        .usage = usage,
    });

    const vma_alloc_info = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = memory_usage,
        .flags = c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
    });

    var new_buffer: t.AllocatedBuffer = undefined;
    check_vk(c.vmaCreateBuffer(self.gpu_allocator, &buffer_info, &vma_alloc_info, &new_buffer.buffer, &new_buffer.allocation, &new_buffer.info)) catch @panic("Failed to create buffer");
    return new_buffer;
}

pub fn upload_mesh(self: *Self, indices: []u32, vertices: []t.Vertex) t.GPUMeshBuffers {
    const index_buffer_size = @sizeOf(u32) * indices.len;
    const vertex_buffer_size = @sizeOf(t.Vertex) * vertices.len;

    var new_surface: t.GPUMeshBuffers = undefined;
    new_surface.vertex_buffer = self.create_buffer(vertex_buffer_size, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
        c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT, c.VMA_MEMORY_USAGE_GPU_ONLY);

    const device_address_info = std.mem.zeroInit(c.VkBufferDeviceAddressInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        .buffer = new_surface.vertex_buffer.buffer,
    });

    new_surface.vertex_buffer_adress = c.vkGetBufferDeviceAddress(self.device, &device_address_info);
    new_surface.index_buffer = self.create_buffer(index_buffer_size, c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT |
        c.VK_BUFFER_USAGE_TRANSFER_DST_BIT, c.VMA_MEMORY_USAGE_GPU_ONLY);

    const staging = self.create_buffer(index_buffer_size + vertex_buffer_size, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, c.VMA_MEMORY_USAGE_CPU_ONLY);
    defer c.vmaDestroyBuffer(self.gpu_allocator, staging.buffer, staging.allocation);

    const data: *anyopaque = staging.info.pMappedData.?;

    const byte_data = @as([*]u8, @ptrCast(data));
    @memcpy(byte_data[0..vertex_buffer_size], std.mem.sliceAsBytes(vertices));
    @memcpy(byte_data[vertex_buffer_size..], std.mem.sliceAsBytes(indices));
    const submit_ctx = struct {
        vertex_buffer: c.VkBuffer,
        index_buffer: c.VkBuffer,
        staging_buffer: c.VkBuffer,
        vertex_buffer_size: usize,
        index_buffer_size: usize,
        fn submit(sself: @This(), cmd: c.VkCommandBuffer) void {
            const vertex_copy_region = std.mem.zeroInit(c.VkBufferCopy, .{
                .srcOffset = 0,
                .dstOffset = 0,
                .size = sself.vertex_buffer_size,
            });

            const index_copy_region = std.mem.zeroInit(c.VkBufferCopy, .{
                .srcOffset = sself.vertex_buffer_size,
                .dstOffset = 0,
                .size = sself.index_buffer_size,
            });

            c.vkCmdCopyBuffer(cmd, sself.staging_buffer, sself.vertex_buffer, 1, &vertex_copy_region);
            c.vkCmdCopyBuffer(cmd, sself.staging_buffer, sself.index_buffer, 1, &index_copy_region);
        }
    }{
        .vertex_buffer = new_surface.vertex_buffer.buffer,
        .index_buffer = new_surface.index_buffer.buffer,
        .staging_buffer = staging.buffer,
        .vertex_buffer_size = vertex_buffer_size,
        .index_buffer_size = index_buffer_size,
    };
    self.immediate_submit(submit_ctx);
    return new_surface;
}

fn create_image(self: *Self, size: c.VkExtent3D, format: c.VkFormat, usage: c.VkImageUsageFlags, mipmapped: bool) t.AllocatedImageAndView {
    var new_image: t.AllocatedImageAndView = undefined;
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

    const alloc_info = c.VmaAllocationCreateInfo{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };
    vki.check_vk(c.vmaCreateImage(self.gpu_allocator, &img_info, &alloc_info, &new_image.image, &new_image.allocation, null)) catch @panic("failed to make image");
    var aspect_flags = c.VK_IMAGE_ASPECT_COLOR_BIT;
    if (format == c.VK_FORMAT_D32_SFLOAT) {
        aspect_flags = c.VK_IMAGE_ASPECT_DEPTH_BIT;
    }

    const view_info = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .image = new_image.image,
        .format = format,
        .subresourceRange = .{
            .aspectMask = @intCast(aspect_flags),
            .baseMipLevel = 0,
            .levelCount = img_info.mipLevels,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    vki.check_vk(c.vkCreateImageView(self.device, &view_info, null, &new_image.view)) catch @panic("failed to make image view");
    return new_image;
}

fn create_upload_image(self: *Self, data: *anyopaque, size: c.VkExtent3D, format: c.VkFormat, usage: c.VkImageUsageFlags, mipmapped: bool) t.AllocatedImageAndView {
    const data_size = size.width * size.height * size.depth * 4;

    const staging = self.create_buffer(data_size, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, c.VMA_MEMORY_USAGE_CPU_TO_GPU);
    defer c.vmaDestroyBuffer(self.gpu_allocator, staging.buffer, staging.allocation);

    const byte_data = @as([*]u8, @ptrCast(staging.info.pMappedData.?));
    const byte_src = @as([*]u8, @ptrCast(data));
    @memcpy(byte_data[0..data_size], byte_src[0..data_size]);

    const new_image = self.create_image(size, format, usage | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT, mipmapped);
    const submit_ctx = struct {
        image: c.VkImage,
        size: c.VkExtent3D,
        staging_buffer: c.VkBuffer,
        fn submit(sself: @This(), cmd: c.VkCommandBuffer) void {
            vki.transition_image(cmd, sself.image, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
            const image_copy_region = c.VkBufferImageCopy{
                .bufferOffset = 0,
                .bufferRowLength = 0,
                .bufferImageHeight = 0,
                .imageSubresource = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .mipLevel = 0,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
                .imageExtent = sself.size,
            };
            c.vkCmdCopyBufferToImage(cmd, sself.staging_buffer, sself.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &image_copy_region);
            vki.transition_image(cmd, sself.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        }
    }{
        .image = new_image.image,
        .size = size,
        .staging_buffer = staging.buffer,
    };

    self.immediate_submit(submit_ctx);
    return new_image;
}

fn destroy_image(self: *Self, img: t.AllocatedImageAndView) void {
    c.vkDestroyImageView(self.device, img.view, vk_alloc_cbs);
    c.vmaDestroyImage(self.gpu_allocator, img.image, img.allocation);
}

fn init_default_data(self: *Self) void {
    self.suzanne = load.load_gltf_meshes(self, "assets/icosphere.glb") catch @panic("Failed to load suzanne mesh");
    const size = c.VkExtent3D{ .width = 1, .height = 1, .depth = 1 };
    var white: u32 = m.Vec4.packU8(.{ .x = 1, .y = 1, .z = 1, .w = 1 });
    var grey: u32 = m.Vec4.packU8(.{ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1 });
    var black: u32 = m.Vec4.packU8(.{ .x = 0, .y = 0, .z = 0, .w = 0 });
    const magenta: u32 = m.Vec4.packU8(.{ .x = 1, .y = 0, .z = 1, .w = 1 });

    self.white_image = self.create_upload_image(&white, size, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT, false);
    self.grey_image = self.create_upload_image(&grey, size, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT, false);
    self.black_image = self.create_upload_image(&black, size, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT, false);

    var checker = [_]u32{0} ** (16 * 16);
    for (0..16) |x| {
        for (0..16) |y| {
            const tile = ((x % 2) ^ (y % 2));
            checker[y * 16 + x] = if (tile == 1) black else magenta;
        }
    }

    self.error_checkerboard_image = self.create_upload_image(&checker, .{ .width = 16, .height = 16, .depth = 1 }, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT, false);

    var sampl = c.VkSamplerCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = c.VK_FILTER_NEAREST,
        .minFilter = c.VK_FILTER_NEAREST,
    };
    vki.check_vk(c.vkCreateSampler(self.device, &sampl, null, &self.default_sampler_nearest)) catch @panic("falied to make sampler");
    sampl.magFilter = c.VK_FILTER_LINEAR;
    sampl.minFilter = c.VK_FILTER_LINEAR;
    vki.check_vk(c.vkCreateSampler(self.device, &sampl, null, &self.default_sampler_linear)) catch @panic("failed to make sampler");
    self.sampler_deletion_queue.push(self.default_sampler_nearest);
    self.sampler_deletion_queue.push(self.default_sampler_linear);
    self.image_deletion_queue.push(self.white_image);
    self.image_deletion_queue.push(self.grey_image);
    self.image_deletion_queue.push(self.black_image);
    self.image_deletion_queue.push(self.error_checkerboard_image);

    std.log.info("Initialized default data", .{});
}

fn init_descriptors(self: *Self) void {
    var sizes = [_]d.DescriptorAllocator.PoolSizeRatio{
        .{ .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 10 },
    };

    self.global_descriptor_allocator.init_pool(self.device, 10, &sizes, self.cpu_allocator);

    {
        var builder = d.DescriptorLayoutBuilder{};
        builder.init(self.cpu_allocator);
        defer builder.bindings.deinit();
        builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE);
        self.draw_image_descriptor_layout = builder.build(self.device, c.VK_SHADER_STAGE_COMPUTE_BIT, null, 0);
    }
    {
        var builder = d.DescriptorLayoutBuilder{};
        builder.init(self.cpu_allocator);
        defer builder.bindings.deinit();
        builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        self.gpu_scene_data_descriptor_layout = builder.build(self.device, c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT, null, 0);
    }
    {
        var builder = d.DescriptorLayoutBuilder{};
        builder.init(self.cpu_allocator);
        defer builder.bindings.deinit();
        builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        self.single_image_descriptor_layout = builder.build(self.device, c.VK_SHADER_STAGE_FRAGMENT_BIT, null, 0);
    }

    self.draw_image_descriptors = self.global_descriptor_allocator.allocate(self.device, self.draw_image_descriptor_layout);

    var writer = d.DescriptorWriter{};
    writer.init(self.cpu_allocator);
    defer writer.deinit();
    writer.write_image(0, self.draw_image.view, null, c.VK_IMAGE_LAYOUT_GENERAL, c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE);
    writer.update_set(self.device, self.draw_image_descriptors);

    for (&self.frames) |*frame| {
        var ratios = [_]d.DescriptorAllocatorGrowable.PoolSizeRatio{ .{ .ratio = 3, .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE }, .{ .ratio = 3, .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER }, .{ .ratio = 3, .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER }, .{ .ratio = 4, .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER } };
        frame.frame_descriptors.init(self.device, 1000, &ratios, self.cpu_allocator);
        frame.buffer_deletion_queue.init(self.cpu_allocator);
    }
    log.info("Initialized descriptors", .{});
}

fn init_instance(self: *Self) void {
    var sdl_required_extension_count: u32 = undefined;
    const sdl_extensions = c.SDL_Vulkan_GetInstanceExtensions(&sdl_required_extension_count);
    const sdl_extension_slice = sdl_extensions[0..sdl_required_extension_count];

    const instance = vki.Instance.create(std.heap.page_allocator, .{
        .application_name = "matrisen",
        .application_version = c.VK_MAKE_VERSION(0, 0, 1),
        .engine_name = "matrisen",
        .engine_version = c.VK_MAKE_VERSION(0, 0, 1),
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
        .surface = self.window.surface,
        // .criteria = .PreferIntegrated,
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

fn create_swapchain(self: *Self, width: u32, height: u32) void {
    const swapchain = vki.Swapchain.create(self.cpu_allocator, .{
        .physical_device = self.gpu,
        .graphics_queue_family = self.graphics_queue_family,
        .present_queue_family = self.graphics_queue_family,
        .device = self.device,
        .surface = self.window.surface,
        .old_swapchain = null,
        .vsync = false,
        .format = .{ .format = c.VK_FORMAT_B8G8R8A8_SRGB, .colorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR },
        .window_width = width,
        .window_height = height,
        .alloc_cb = vk_alloc_cbs,
    }) catch @panic("Failed to create swapchain");

    self.swapchain = swapchain.handle;
    self.swapchain_format = swapchain.format;
    self.swapchain_extent = swapchain.extent;
    self.swapchain_images = swapchain.images;
    self.swapchain_image_views = swapchain.image_views;
}

fn init_swapchain(self: *Self) void {
    self.create_swapchain(self.window_extent.width, self.window_extent.height);
    log.info("Created swapchain", .{});

    self.draw_image_extent = c.VkExtent3D{
        .width = self.window_extent.width,
        .height = self.window_extent.height,
        .depth = 1,
    };

    self.draw_image_format = c.VK_FORMAT_R16G16B16A16_SFLOAT;
    const draw_image_ci = std.mem.zeroInit(c.VkImageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = self.draw_image_format,
        .extent = self.draw_image_extent,
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
        .format = self.draw_image_format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });

    check_vk(c.vkCreateImageView(self.device, &draw_image_view_ci, vk_alloc_cbs, &self.draw_image.view)) catch @panic("Failed to create draw image view");

    self.depth_image_extent = self.draw_image_extent;
    self.depth_image_format = c.VK_FORMAT_D32_SFLOAT;
    const depth_image_ci = std.mem.zeroInit(c.VkImageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = self.depth_image_format,
        .extent = self.depth_image_extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
    });

    check_vk(c.vmaCreateImage(self.gpu_allocator, &depth_image_ci, &draw_image_ai, &self.depth_image.image, &self.depth_image.allocation, null)) catch @panic("Failed to create depth image");

    const depth_image_view_ci = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = self.depth_image.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = self.depth_image_format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    check_vk(c.vkCreateImageView(self.device, &depth_image_view_ci, vk_alloc_cbs, &self.depth_image.view)) catch @panic("Failed to create depth image view");

    self.image_deletion_queue.push(self.draw_image);
    self.image_deletion_queue.push(self.depth_image);

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

    check_vk(c.vkCreateCommandPool(self.device, &command_pool_ci, vk_alloc_cbs, &self.immidiate_command_pool)) catch @panic("Failed to create upload command pool");

    const upload_command_buffer_ai = std.mem.zeroInit(c.VkCommandBufferAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = self.immidiate_command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    });
    check_vk(c.vkAllocateCommandBuffers(self.device, &upload_command_buffer_ai, &self.immidiate_command_buffer)) catch @panic("Failed to allocate upload command buffer");
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
        check_vk(c.vkCreateSemaphore(self.device, &semaphore_ci, vk_alloc_cbs, &frame.swapchain_semaphore)) catch @panic("Failed to create present semaphore");
        check_vk(c.vkCreateSemaphore(self.device, &semaphore_ci, vk_alloc_cbs, &frame.render_semaphore)) catch @panic("Failed to create render semaphore");
        check_vk(c.vkCreateFence(self.device, &fence_ci, vk_alloc_cbs, &frame.render_fence)) catch @panic("Failed to create render fence");
    }

    const upload_fence_ci = std.mem.zeroInit(c.VkFenceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    });

    check_vk(c.vkCreateFence(self.device, &upload_fence_ci, vk_alloc_cbs, &self.immidiate_fence)) catch @panic("Failed to create upload fence");
    log.info("Created sync structures", .{});
}

fn init_pipelines(self: *Self) void {
    init_background_pipelines(self);
    init_mesh_pipeline(self);
}

fn init_mesh_pipeline(self: *Self) void {
    const vertex_code align(4) = @embedFile("triangle_mesh.vert").*;
    // const fragment_code align(4) = @embedFile("triangle.frag").*;
    const fragment_code align(4) = @embedFile("tex_image.frag").*;

    const vertex_module = vki.create_shader_module(self.device, &vertex_code, vk_alloc_cbs) orelse null;
    const fragment_module = vki.create_shader_module(self.device, &fragment_code, vk_alloc_cbs) orelse null;
    if (vertex_module != null) log.info("Created vertex shader module", .{});
    if (fragment_module != null) log.info("Created fragment shader module", .{});
    const buffer_range = std.mem.zeroInit(c.VkPushConstantRange, .{
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
        .offset = 0,
        .size = @sizeOf(t.GPUDrawPushConstants),
    });
    const pipeline_layout_info = std.mem.zeroInit(c.VkPipelineLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &buffer_range,
        .pSetLayouts = &self.single_image_descriptor_layout,
        .setLayoutCount = 1,
    });

    check_vk(c.vkCreatePipelineLayout(self.device, &pipeline_layout_info, null, &self.mesh_pipeline_layout)) catch @panic("Failed to create pipeline layout");
    var pipeline_builder = PipelineBuilder.init(self.cpu_allocator);
    defer pipeline_builder.deinit();
    pipeline_builder.pipeline_layout = self.mesh_pipeline_layout;
    pipeline_builder.set_shaders(vertex_module, fragment_module);
    pipeline_builder.set_input_topology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    pipeline_builder.set_polygon_mode(c.VK_POLYGON_MODE_FILL);
    pipeline_builder.set_cull_mode(c.VK_CULL_MODE_BACK_BIT, c.VK_FRONT_FACE_CLOCKWISE);
    pipeline_builder.set_multisampling_none();
    pipeline_builder.disable_blending();
    // pipeline_builder.enable_blending_additive();
    // pipeline_builder.enable_blending_alpha();
    // pipeline_builder.disable_depth_test();
    pipeline_builder.enable_depth_test(true, c.VK_COMPARE_OP_GREATER_OR_EQUAL);
    pipeline_builder.set_color_attachment_format(self.draw_image_format);
    pipeline_builder.set_depth_format(self.depth_image_format);
    self.mesh_pipeline = pipeline_builder.build_pipeline(self.device);
    c.vkDestroyShaderModule(self.device, vertex_module, vk_alloc_cbs);
    c.vkDestroyShaderModule(self.device, fragment_module, vk_alloc_cbs);
    self.pipeline_deletion_queue.push(self.mesh_pipeline);
    self.pipeline_layout_deletion_queue.push(self.mesh_pipeline_layout);
}

fn init_background_pipelines(self: *Self) void {
    var compute_layout = std.mem.zeroInit(c.VkPipelineLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &self.draw_image_descriptor_layout,
    });

    const push_constant_range = std.mem.zeroInit(c.VkPushConstantRange, .{
        .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
        .offset = 0,
        .size = @sizeOf(t.ComputePushConstants),
    });

    compute_layout.pPushConstantRanges = &push_constant_range;
    compute_layout.pushConstantRangeCount = 1;

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
    self.pipeline_deletion_queue.push(self.gradient_pipeline);
    self.pipeline_layout_deletion_queue.push(self.gradient_pipeline_layout);
}
