// pub fn uploadMesh(
//     self: *Self,
//     core: *Core,
//     vertices: []const Vertex,
//     indices: []const u32,
// ) void {
//     const v_size = vertices.len * @sizeOf(Vertex);
//     const i_size = indices.len * @sizeOf(u32);

//     if (self.vertex_byte_offset + v_size > MAX_GEOMETRY_BYTES or
//         self.index_byte_offset + i_size > MAX_GEOMETRY_BYTES)
//     {
//         @panic("Giant Geometry Buffers are full!");
//     }

//     // Cast slices to raw bytes for the upload function
//     const v_bytes = std.mem.sliceAsBytes(vertices);
//     const i_bytes = std.mem.sliceAsBytes(indices);

//     // Upload via Staging Buffer
//     self.upload(&core.asynccontext, v_bytes, self.vertexbuffer, self.vertex_byte_offset);
//     self.upload(&core.asynccontext, i_bytes, self.indexbuffer, self.index_byte_offset);

//     // Get Base Device Addresses
//     const base_v_addr = self.vertexaddr;
//     const base_i_addr = self.indexaddr;

//     // Create the bindless DrawData referencing the exact offsets
//     const mesh = Mesh{
//         .vertexBuffer = base_v_addr + self.vertex_byte_offset,
//         .indexBuffer = base_i_addr + self.index_byte_offset,
//         .indexCount = @as(u32, @intCast(indices.len)),
//         .pad = 0,
//     };

//     // Bump the allocators
//     self.vertex_byte_offset += v_size;
//     self.index_byte_offset += i_size;

//     // push to the objects list
//     self.upload(
//         &core.asynccontext,
//         std.mem.asBytes(&mesh),
//         self.meshbuffer,
//         self.mesh_byte_offset,
//     );
//     self.mesh_byte_offset += @sizeOf(Mesh);
// }

// pub fn uploadTexture(
//     self: *Self,
//     core: *Core,
//     descriptormanager: *DescriptorManager,
//     data: []const u8,
//     extent: c.VkExtent3D,
//     format: c.VkFormat,
//     mipmapped: bool,
// ) AllocatedImage {
//     if (self.texture_count >= MAX_TEXTURES) {
//         @panic("Exceeded maximum bindless textures!");
//     }

//     // 1. Create Staging Buffer
//     const staging = self.createBuffer(
//         data.len,
//         c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
//         c.VMA_MEMORY_USAGE_CPU_TO_GPU,
//     );
//     defer self.destroyBuffer(staging);

//     // 2. Copy Data to Staging
//     const mapped_data = @as([*]u8, @ptrCast(staging.info.pMappedData.?));
//     @memcpy(mapped_data[0..data.len], data);

//     // 3. Create GPU Image
//     var new_image = self.createRawImage(
//         extent,
//         format,
//         c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
//         mipmapped,
//     );

//     // 4. Record and Submit Transfer Commands
//     core.asynccontext.submitBegin();
//     const cmd = core.asynccontext.commandbuffer;

//     imageop.transition(
//         cmd,
//         new_image.image,
//         c.VK_IMAGE_LAYOUT_UNDEFINED,
//         c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
//     );

//     const image_copy_region: c.VkBufferImageCopy = .{
//         .bufferOffset = 0,
//         .bufferRowLength = 0,
//         .bufferImageHeight = 0,
//         .imageSubresource = .{
//             .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
//             .mipLevel = 0,
//             .baseArrayLayer = 0,
//             .layerCount = 1,
//         },
//         .imageExtent = extent,
//     };

//     c.vkCmdCopyBufferToImage(
//         cmd,
//         staging.buffer,
//         new_image.image,
//         c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
//         1,
//         &image_copy_region,
//     );

//     imageop.transition(
//         cmd,
//         new_image.image,
//         c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
//         c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
//     );
//     core.asynccontext.submitEnd();

//     // 5. Create View & Assign Bindless Index
//     new_image.view = self.createImageView(new_image.image, format, if (mipmapped) 0 else 1);
//     new_image.bindless_index = self.texture_count;
//     self.texture_count += 1;

//     // 6. Push to Descriptor Manager
//     descriptormanager.writeBindlessTexture(
//         self.device,
//         new_image.view,
//         self.global_sampler,
//         new_image.bindless_index,
//     );

//     return new_image;
// }
