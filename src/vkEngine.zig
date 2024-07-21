const std = @import("std");
const vki = @import("vkUtils.zig");
const d = @import("vkDescriptors.zig");
const c = @import("clibs.zig");
const m = @import("math3d.zig");
const s = @import("SDLutils.zig");
const r = @import("rendertarget.zig");
const p = @import("pipelines.zig");
const t = @import("types.zig");
const log = std.log.scoped(.vkEngine);
pub const vk_alloc_cbs: ?*c.VkAllocationCallbacks = null;
const check_vk = vki.check_vk;

const Self = @This();
// targets
window: r.WindowManager = undefined,
depth_image: t.AllocatedImage = undefined,
depth_image_view: c.VkImageView = undefined,
depth_image_format: c.VkFormat = undefined,
depth_image_extent: c.VkExtent3D = undefined,
draw_image: t.AllocatedImage = undefined,
draw_image_view: c.VkImageView = undefined,
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
buffer_deletion_queue: std.ArrayList(t.AllocatedBuffer) = undefined,
image_deletion_queue: std.ArrayList(t.AllocatedImage) = undefined,
imageview_deletion_queue: std.ArrayList(c.VkImageView) = undefined,
pipeline_deletion_queue: std.ArrayList(c.VkPipeline) = undefined,
pipeline_layout_deletion_queue: std.ArrayList(c.VkPipelineLayout) = undefined,
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
// pipelines
gradient_pipeline_layout: c.VkPipelineLayout = null,
gradient_pipeline: c.VkPipeline = null,
triangle_pipeline_layout: c.VkPipelineLayout = null,
triangle_pipeline: c.VkPipeline = null,
mesh_pipeline_layout: c.VkPipelineLayout = null,
mesh_pipeline: c.VkPipeline = null,

rectangle: t.GPUMeshBuffers = undefined,
// other
lua_state: ?*c.lua_State,
debug_messenger: c.VkDebugUtilsMessengerEXT = null,
pc: t.ComputePushConstants = .{
    .data1 = m.Vec4{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 },
    .data2 = m.Vec4{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 0.0 },
    .data3 = m.Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
    .data4 = m.Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
},

const FRAME_OVERLAP = 2;

pub fn init(a: std.mem.Allocator) Self {
    const win = try r.WindowManager.init(.{ .width = 1600, .height = 900 });

    var engine = Self{
        .window = win,
        .cpu_allocator = a,
        .buffer_deletion_queue = std.ArrayList(t.AllocatedBuffer).init(a),
        .image_deletion_queue = std.ArrayList(t.AllocatedImage).init(a),
        .imageview_deletion_queue = std.ArrayList(c.VkImageView).init(a),
        .pipeline_deletion_queue = std.ArrayList(c.VkPipeline).init(a),
        .pipeline_layout_deletion_queue = std.ArrayList(c.VkPipelineLayout).init(a),
        .lua_state = c.luaL_newstate(),
    };

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
    p.init_pipelines(&engine);
    c.luaL_openlibs(engine.lua_state);
    return engine;
}

pub fn run(self: *Self) void {
    // var timer = std.time.Timer.start() catch @panic("Failed to start timer");
    // var delta: f32 = undefined;
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
                        const script_path = "script.lua";
                        if (c.luaL_loadfilex(self.lua_state, script_path, null) == 0) {
                            if (c.lua_pcallk(self.lua_state, 0, 0, 0, 0, null) != 0) {
                                var len: usize = undefined;
                                const error_msg = c.lua_tolstring(self.lua_state, -1, &len);
                                if (error_msg != null) {
                                    const error_slice = error_msg[0..len];
                                    std.log.err("Failed to run script: {s}", .{error_slice});
                                } else {
                                    std.log.err("Failed to run script: Unknown error", .{});
                                }
                            }
                        } else {
                            std.log.err("Failed to load script: {s}", .{script_path});
                        }
                    }
                },
                c.SDL_EVENT_KEY_UP => {
                    s.handle_key_up(self, event.key);
                },
                else => {},
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
    while (self.pipeline_deletion_queue.popOrNull()) |entry| {
        c.vkDestroyPipeline(self.device, entry, vk_alloc_cbs);
    }
    self.pipeline_deletion_queue.deinit();
    while (self.pipeline_layout_deletion_queue.popOrNull()) |entry| {
        c.vkDestroyPipelineLayout(self.device, entry, vk_alloc_cbs);
    }
    self.pipeline_layout_deletion_queue.deinit();

    c.vkDestroyDescriptorSetLayout(self.device, self.draw_image_descriptor_layout, vk_alloc_cbs);
    self.global_descriptor_allocator.clear_descriptors(self.device);
    self.global_descriptor_allocator.destroy_pool(self.device);
    for (self.frames) |frame| {
        c.vkDestroyCommandPool(self.device, frame.command_pool, vk_alloc_cbs);
        c.vkDestroyFence(self.device, frame.render_fence, vk_alloc_cbs);
        c.vkDestroySemaphore(self.device, frame.render_semaphore, vk_alloc_cbs);
        c.vkDestroySemaphore(self.device, frame.present_semaphore, vk_alloc_cbs);
    }
    c.vkDestroyFence(self.device, self.immidiate_fence, vk_alloc_cbs);
    c.vkDestroyCommandPool(self.device, self.immidiate_command_pool, vk_alloc_cbs);
    c.vkDestroySwapchainKHR(self.device, self.swapchain, vk_alloc_cbs);
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

    var data: ?*anyopaque = undefined;
    check_vk(c.vmaMapMemory(self.gpu_allocator, staging.allocation, &data)) catch @panic("Failed to map memory");
    defer c.vmaDestroyBuffer(self.gpu_allocator, staging.buffer, staging.allocation);
    defer c.vmaUnmapMemory(self.gpu_allocator, staging.allocation);
    const byte_data = @as([*]u8, @ptrCast(data.?))[0..(vertex_buffer_size + index_buffer_size)];
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

    self.draw_extent.width = self.draw_image_extent.width;
    self.draw_extent.height = self.draw_image_extent.height;

    check_vk(c.vkBeginCommandBuffer(cmd, &cmd_begin_info)) catch @panic("Failed to begin command buffer");

    vki.transition_image(cmd, self.draw_image.image, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_GENERAL);
    self.draw_background(cmd);
    vki.transition_image(cmd, self.draw_image.image, c.VK_IMAGE_LAYOUT_GENERAL, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
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
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.gradient_pipeline);
    c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.gradient_pipeline_layout, 0, 1, &self.draw_image_descriptors, 0, null);
    c.vkCmdPushConstants(cmd, self.gradient_pipeline_layout, c.VK_SHADER_STAGE_COMPUTE_BIT, 0, @sizeOf(t.ComputePushConstants), &self.pc);
    c.vkCmdDispatch(cmd, self.draw_extent.width / 16, self.draw_extent.height / 16, 1);
}

fn draw_geometry(self: *Self, cmd: c.VkCommandBuffer) void {
    const color_attachment = std.mem.zeroInit(c.VkRenderingAttachmentInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.draw_image_view,
        .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
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
    });

    c.vkCmdBeginRendering(cmd, &render_info);
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.triangle_pipeline);
    const viewport = std.mem.zeroInit(c.VkViewport, .{
        .x = 0.0,
        .y = 0.0,
        .width = @as(f32, @floatFromInt(self.draw_extent.width)),
        .height = @as(f32, @floatFromInt(self.draw_extent.height)),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    });

    c.vkCmdSetViewport(cmd, 0, 1, &viewport);

    const scissor = std.mem.zeroInit(c.VkRect2D, .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.draw_extent,
    });

    c.vkCmdSetScissor(cmd, 0, 1, &scissor);
    c.vkCmdDraw(cmd, 3, 1, 0, 0);
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.mesh_pipeline);
    const push_constants = t.GPUDrawPushConstants{
        .model = m.Mat4.IDENTITY,
        .vertex_buffer = self.rectangle.vertex_buffer_adress,
    };

    c.vkCmdPushConstants(cmd, self.mesh_pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(t.GPUDrawPushConstants), &push_constants);
    c.vkCmdBindIndexBuffer(cmd, self.rectangle.index_buffer.buffer, 0, c.VK_INDEX_TYPE_UINT32);
    c.vkCmdDrawIndexed(cmd, 6, 1, 0, 0, 0);
    c.vkCmdEndRendering(cmd);
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

fn init_default_data(self: *Self) void {
    var rect_vertices = [_]t.Vertex{
        .{ .position = m.Vec3{ .x = 0.5, .y = -0.5, .z = 0.0 }, .color = m.Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 } },
        .{ .position = m.Vec3{ .x = 0.5, .y = 0.5, .z = 0.0 }, .color = m.Vec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 } },
        .{ .position = m.Vec3{ .x = -0.5, .y = -0.5, .z = 0.0 }, .color = m.Vec4{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 1.0 } },
        .{ .position = m.Vec3{ .x = -0.5, .y = 0.5, .z = 0.0 }, .color = m.Vec4{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 } },
    };
    var rect_indices = [_]u32{ 0, 1, 2, 2, 1, 3 };
    self.rectangle = self.upload_mesh(&rect_indices, &rect_vertices);
    self.buffer_deletion_queue.append(self.rectangle.vertex_buffer) catch @panic("Out of memory");
    self.buffer_deletion_queue.append(self.rectangle.index_buffer) catch @panic("Out of memory");
    std.log.info("Initialized default data", .{});
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
        .imageView = self.draw_image_view,
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
    r.check_sdl(c.SDL_GetWindowSize(self.window.window, &win_width, &win_height));

    const swapchain = vki.Swapchain.create(self.cpu_allocator, .{
        .physical_device = self.gpu,
        .graphics_queue_family = self.graphics_queue_family,
        .present_queue_family = self.graphics_queue_family,
        .device = self.device,
        .surface = self.window.surface,
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
    self.draw_image_extent = c.VkExtent3D{
        .width = @intCast(win_width),
        .height = @intCast(win_height),
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
    check_vk(c.vkCreateImageView(self.device, &draw_image_view_ci, vk_alloc_cbs, &self.draw_image_view)) catch @panic("Failed to create draw image view");
    self.imageview_deletion_queue.append(self.draw_image_view) catch @panic("Out of memory");
    self.image_deletion_queue.append(self.draw_image) catch @panic("Out of memory");

    self.depth_image_extent = c.VkExtent3D{
        .width = self.swapchain_extent.width,
        .height = self.swapchain_extent.height,
        .depth = 1,
    };
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
        .format = self.depth_image_format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    check_vk(c.vkCreateImageView(self.device, &depth_image_view_ci, vk_alloc_cbs, &self.depth_image_view)) catch @panic("Failed to create depth image view");
    self.imageview_deletion_queue.append(self.depth_image_view) catch @panic("Out of memory");
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
        check_vk(c.vkCreateSemaphore(self.device, &semaphore_ci, vk_alloc_cbs, &frame.present_semaphore)) catch @panic("Failed to create present semaphore");
        check_vk(c.vkCreateSemaphore(self.device, &semaphore_ci, vk_alloc_cbs, &frame.render_semaphore)) catch @panic("Failed to create render semaphore");
        check_vk(c.vkCreateFence(self.device, &fence_ci, vk_alloc_cbs, &frame.render_fence)) catch @panic("Failed to create render fence");
    }

    const upload_fence_ci = std.mem.zeroInit(c.VkFenceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    });

    check_vk(c.vkCreateFence(self.device, &upload_fence_ci, vk_alloc_cbs, &self.immidiate_fence)) catch @panic("Failed to create upload fence");
    log.info("Created sync structures", .{});
}
