const c = @import("../clibs/clibs.zig").libs;
const linalg = @import("../linalg.zig");

const Quat = linalg.Quat(f32);
const Vec3 = linalg.Vec3(f32);
const Vec4 = linalg.Vec4(f32);
const Mat4x4 = linalg.Mat4x4(f32);

pub const AllocatedBuffer = struct {
    buffer: c.VkBuffer,
    allocation: c.VmaAllocation,
    info: c.VmaAllocationInfo,
};

// --- 1. GPU STRUCTS (Must match Slang perfectly) ---
pub const Vertex = extern struct {
    position: Vec3 = .zeros,
    uv_x: f32 = 0,
    normal: Vec3 = .zeros,
    uv_y: f32 = 0,
    color: Vec4 = .zeros,
};

pub const Transform = extern struct {
    modelMatrix: Mat4x4,
    boundingSphere: Vec4,
};

pub const Mesh = extern struct {
    vertexBuffer: u64, // globalvertexbuffer ptr with offset
    indexBuffer: u64, // globalindexbuffer ptr with offset
    indexCount: u32,
    materialIndex: u32,
};

pub const UIData = extern struct {
    modelMatrix: Mat4x4,
    viewport: Vec4,
    // These are POINTERS to the data, so they must be exactly 64 bits (u64)
    curveBuffer: u64,
    bandBuffer: u64,
    textureWidth: u32,
    _pad: u32 = 0,
};

pub const SceneData = extern struct {
    view: Mat4x4,
    proj: Mat4x4,
    viewproj: Mat4x4,
    ambient_color: Vec4,
    sun_direction: Vec4,
    sun_color: Vec4,
    // addresses
    transforms: u64, // array of Transform
    cpu_transforms: u64, // array of Transform
    meshes: u64, // array of Mesh
    uidata: u64,
    indirectCommands: u64, // address to the indirect struct
    drawCount: u64, // address to a single u32
    drawMap: u64, // INFO only used by meshshading atm
    // other
    totalObjects: u32,
    _pad: u32 = 0,
};
