const c = @import("../clibs/clibs.zig").libs;
const AllocatedImage = @import("ImageAllocator.zig").AllocatedImage;

textures: AllocatedImage = undefined,
depths: AllocatedImage = undefined,
extent3d: c.VkExtent3D = undefined,
extent2d: c.VkExtent2D = undefined,
samplers: c.VkSampler = undefined,

// pub fn createDefaultTextures(self: *self) void {
//     const size = c.VkExtent3D{ .width = 1, .height = 1, .depth = 1 };
//     var white: u32 = Vec4.packU8(.{ .x = 1, .y = 1, .z = 1, .w = 1 });
//     var grey: u32 = Vec4.packU8(.{ .x = 0.2, .y = 0.2, .z = 0.2, .w = 1 });
//     const grey1 = Vec4.packU8(.{ .x = 0.05, .y = 0.05, .z = 0.05, .w = 1 });
//     const grey2 = Vec4.packU8(.{ .x = 0.08, .y = 0.08, .z = 0.08, .w = 1 });
//     var black: u32 = Vec4.packU8(.{ .x = 0, .y = 0, .z = 0, .w = 1 });

//     self.textures[0] = create_upload(
//         self,
//         &white,
//         size,
//         c.VK_FORMAT_R8G8B8A8_UNORM,
//         c.VK_IMAGE_USAGE_SAMPLED_BIT,
//         false,
//     );
//     self.textures[1] = create_upload(
//         self,
//         &grey,
//         size,
//         c.VK_FORMAT_R8G8B8A8_UNORM,
//         c.VK_IMAGE_USAGE_SAMPLED_BIT,
//         false,
//     );
//     self.textures[2] = create_upload(
//         self,
//         &black,
//         size,
//         c.VK_FORMAT_R8G8B8A8_UNORM,
//         c.VK_IMAGE_USAGE_SAMPLED_BIT,
//         false,
//     );
//     self.textures[1].views[0] = create_view(
//         self.device_handle,
//         self.textures[1].image,
//         c.VK_FORMAT_R8G8B8A8_UNORM,
//         1,
//     );

//     var checker = [_]u32{0} ** (16 * 16);
//     for (0..16) |x| {
//         for (0..16) |y| {
//             const tile = ((x % 2) ^ (y % 2));
//             checker[y * 16 + x] = if (tile == 1) grey1 else grey2;
//         }
//     }
//     self.textures[3] = create_upload(
//         self,
//         &checker,
//         .{ .width = 16, .height = 16, .depth = 1 },
//         c.VK_FORMAT_R8G8B8A8_UNORM,
//         c.VK_IMAGE_USAGE_SAMPLED_BIT,
//         false,
//     );

//     var sampl = c.VkSamplerCreateInfo{
//         .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
//         .magFilter = c.VK_FILTER_NEAREST,
//         .minFilter = c.VK_FILTER_NEAREST,
//     };

//     checkVkPanic(c.vkCreateSampler(self.device_handle, &sampl, null, &self.samplers[0]));
//     sampl.magFilter = c.VK_FILTER_LINEAR;
//     sampl.minFilter = c.VK_FILTER_LINEAR;
//     checkVkPanic(c.vkCreateSampler(self.device_handle, &sampl, null, &self.samplers[1]));
// }
