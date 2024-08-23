const std = @import("std");
const engine = @import("engine.zig");
const types = @import("types.zig");
const config = @import("config");
const Mat4 = @import("3Dmath.zig").Mat4;
const Vec3 = @import("3Dmath.zig").Vec3;
const Quat = @import("3Dmath.zig").Quat;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.assetloader);
const mem = std.mem;
const math = std.math;
const json = std.json;
const fmt = std.fmt;
const assert = std.debug.assert;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const Data = struct {
    asset: types.Asset,
    scene: ?types.Index = null,
    scenes: ArrayList(types.Scene),
    cameras: ArrayList(types.Camera),
    nodes: ArrayList(types.Node),
    meshes: ArrayList(types.Mesh),
    materials: ArrayList(types.Material),
    skins: ArrayList(types.Skin),
    samplers: ArrayList(types.TextureSampler),
    images: ArrayList(types.Image),
    animations: ArrayList(types.Animation),
    textures: ArrayList(types.Texture),
    accessors: ArrayList(types.Accessor),
    buffer_views: ArrayList(types.BufferView),
    buffers: ArrayList(types.Buffer),
    lights: ArrayList(types.Light),
};



const Self = @This();
arena: *ArenaAllocator,
data: Data,
glb_binary: ?[]align(4) const u8 = null,

pub fn load_gltf_meshes(eng: *engine, path: []const u8) !ArrayList(types.MeshAsset) {
    log.info("Loading gltf file: {s}", .{path});
    const allocator = std.heap.page_allocator;
    const file = try std.fs.cwd().readFileAllocOptions(allocator, path, 1_512_000, null, 4, null);
    defer allocator.free(file);
    var gltf = Self.init(allocator);
    defer deinit(&gltf);

    try gltf.parse(file);

    var meshes = ArrayList(types.MeshAsset).init(allocator);
    var vertices = ArrayList(types.Vertex).init(allocator);
    var indices = ArrayList(u32).init(allocator);
    defer {
        vertices.deinit();
        indices.deinit();
    }
    for (gltf.data.meshes.items) |mesh| {
        var new_mesh: types.MeshAsset = .{
            .name = mesh.name,
            .surfaces = ArrayList(types.GeoSurface).init(allocator),
        };

        indices.clearAndFree();
        vertices.clearAndFree();
        for (mesh.primitives.items) |primitive| {
            var accessor = if (primitive.indices) |idx| blk: {
                break :blk gltf.data.accessors.items[idx];
            } else {
                log.err("No indices found for mesh: {s}", .{mesh.name});
                unreachable;
            };
            const new_surface: types.GeoSurface = .{
                .start_index = @intCast(indices.items.len),
                .count = @intCast(accessor.count),
            };
            log.info("Loading mesh: {s} with {d} indices.", .{mesh.name, accessor.count});
            const initial_vtx = vertices.items.len;
            try indices.ensureTotalCapacity(indices.items.len + @as(usize, @intCast(accessor.count)));
            {
                var it = accessor.iterator(u16, &gltf, gltf.glb_binary.?);
                while (it.next()) |index| {
                    try indices.append(index[0] + @as(u32, @intCast(initial_vtx)));
                }
            }

            for (primitive.attributes.items) |attribute| {
                switch (attribute) {
                    .position => |idx| {
                        accessor = gltf.data.accessors.items[idx];
                        try vertices.ensureTotalCapacity(vertices.items.len + @as(usize, @intCast(accessor.count)));
                        vertices.expandToCapacity();
                        var it = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
                        var i: u32 = 0;
                        while (it.next()) |v| : (i += 1) {
                            const new_vtx = types.Vertex{
                                .position = .{ .x = v[0], .y = v[1], .z = v[2] },
                                .normal = .{ .x = 1, .y = 0, .z = 0 },
                                .color = .{ .x = 1, .y = 1, .z = 1, .w = 1 },
                                .uv_x = 0,
                                .uv_y = 0,
                            };
                            vertices.items[initial_vtx + i] = new_vtx;
                        }
                    },
                    .normal => |idx| {
                        accessor = gltf.data.accessors.items[idx];
                        var it = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
                        var i: u32 = 0;
                        while (it.next()) |n| : (i += 1) {
                            vertices.items[initial_vtx + i].normal = .{ .x = n[0], .y = n[1], .z = n[2] };
                        }
                    },
                    .texcoord => |idx| {
                        accessor = gltf.data.accessors.items[idx];
                        var it = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
                        var i: u32 = 0;
                        while (it.next()) |uv| : (i += 1) {
                            vertices.items[initial_vtx + i].uv_x = uv[0];
                            vertices.items[initial_vtx + i].uv_y = uv[1];
                        }
                    },
                    .color => |idx| {
                        accessor = gltf.data.accessors.items[idx];
                        var it = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
                        var i: u32 = 0;
                        while (it.next()) |c| : (i += 1) {
                            vertices.items[initial_vtx + i].color = .{ .x = c[0], .y = c[1], .z = c[2], .w = c[3] };
                        }
                    },
                    else => {},
                }
            }
            try new_mesh.surfaces.append(new_surface);
        }
        if (config.override_colors) {
            for (vertices.items) |*v| {
                v.color = .{ .x = (v.normal.x + 1)/2, .y = (v.normal.y + 1)/2, .z = (v.normal.z + 1)/2, .w = 1.0 };
            }
        }
        new_mesh.mesh_buffers = eng.upload_mesh(indices.items, vertices.items);
        eng.buffer_deletion_queue.push(new_mesh.mesh_buffers.index_buffer);
        eng.buffer_deletion_queue.push(new_mesh.mesh_buffers.vertex_buffer);
        try meshes.append(new_mesh);
    }
    return meshes;
}

pub fn init(allocator: Allocator) Self {
    var arena = allocator.create(ArenaAllocator) catch {
        @panic("Error while allocating memory for gltf arena.");
    };

    arena.* = ArenaAllocator.init(allocator);

    const alloc = arena.allocator();
    return Self{
        .arena = arena,
        .data = .{
            .asset = types.Asset{ .version = "Undefined" },
            .scenes = ArrayList(types.Scene).init(alloc),
            .nodes = ArrayList(types.Node).init(alloc),
            .cameras = ArrayList(types.Camera).init(alloc),
            .meshes = ArrayList(types.Mesh).init(alloc),
            .materials = ArrayList(types.Material).init(alloc),
            .skins = ArrayList(types.Skin).init(alloc),
            .samplers = ArrayList(types.TextureSampler).init(alloc),
            .images = ArrayList(types.Image).init(alloc),
            .animations = ArrayList(types.Animation).init(alloc),
            .textures = ArrayList(types.Texture).init(alloc),
            .accessors = ArrayList(types.Accessor).init(alloc),
            .buffer_views = ArrayList(types.BufferView).init(alloc),
            .buffers = ArrayList(types.Buffer).init(alloc),
            .lights = ArrayList(types.Light).init(alloc),
        },
    };
}

pub fn parse(self: *Self, file_buffer: []align(4) const u8) !void {
    if (isGlb(file_buffer)) {
        try self.parseGlb(file_buffer);
    } else {
        try self.parseGltfJson(file_buffer);
    }
}

pub fn debugPrint(self: *const Self) void {
    const msg =
        \\
        \\  glTF file info:
        \\
        \\    Node       {}
        \\    Mesh       {}
        \\    Skin       {}
        \\    Animation  {}
        \\    Texture    {}
        \\    Material   {}
        \\
        \\
    ;

    std.debug.print(msg, .{
        self.data.nodes.items.len,
        self.data.meshes.items.len,
        self.data.skins.items.len,
        self.data.animations.items.len,
        self.data.textures.items.len,
        self.data.materials.items.len,
    });

    std.debug.print("  Details:\n\n", .{});

    if (self.data.skins.items.len > 0) {
        std.debug.print("   Skins found:\n", .{});

        for (self.data.skins.items) |skin| {
            std.debug.print("     '{s}' found with {} joint(s).\n", .{
                skin.name,
                skin.joints.items.len,
            });
        }

        std.debug.print("\n", .{});
    }

    if (self.data.animations.items.len > 0) {
        std.debug.print("  Animations found:\n", .{});

        for (self.data.animations.items) |anim| {
            std.debug.print(
                "     '{s}' found with {} sampler(s) and {} channel(s).\n",
                .{ anim.name, anim.samplers.items.len, anim.channels.items.len },
            );
        }

        std.debug.print("\n", .{});
    }
}

pub fn getDataFromBufferView(
    self: *const Self,
    comptime T: type,
    list: *ArrayList(T),
    accessor: types.Accessor,
    binary: []const u8,
) void {
    if (switch (accessor.component_type) {
        .byte => T != i8,
        .unsigned_byte => T != u8,
        .short => T != i16,
        .unsigned_short => T != u16,
        .unsigned_integer => T != u32,
        .float => T != f32,
    }) {
        std.debug.panic(
            "Mismatch between gltf component '{}' and given type '{}'.",
            .{ accessor.component_type, T },
        );
    }

    if (accessor.buffer_view == null) {
        std.debug.panic("Accessors without buffer_view are not supported yet.", .{});
    }

    const buffer_view = self.data.buffer_views.items[accessor.buffer_view.?];

    const comp_size = @sizeOf(T);
    const offset = (accessor.byte_offset + buffer_view.byte_offset) / comp_size;

    const stride = blk: {
        if (buffer_view.byte_stride) |byte_stride| {
            break :blk byte_stride / comp_size;
        } else {
            break :blk accessor.stride / comp_size;
        }
    };

    const total_count = accessor.count;
    const datum_count: usize = switch (accessor.type) {
        // Scalar.
        .scalar => 1,
        // Vec2.
        .vec2 => 2,
        // Vec3.
        .vec3 => 3,
        // Vec4.
        .vec4 => 4,
        // Vec4.
        .mat4x4 => 16,
        else => {
            std.debug.panic("Accessor type '{}' not implemented.", .{accessor.type});
        },
    };

    const data = @as([*]const T, @ptrCast(@alignCast(binary.ptr)));

    var current_count: usize = 0;
    while (current_count < total_count) : (current_count += 1) {
        const slice = (data + offset + current_count * stride)[0..datum_count];
        list.appendSlice(slice) catch unreachable;
    }
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
    self.arena.child_allocator.destroy(self.arena);
}

pub fn getLocalTransform(node: types.Node) Mat4 {
    return blk: {
        if (node.matrix) |mat4x4| {
            break :blk .{
                mat4x4[0..4].*,
                mat4x4[4..8].*,
                mat4x4[8..12].*,
                mat4x4[12..16].*,
            };
        }

        break :blk Mat4.recompose(
            node.translation,
            node.rotation,
            node.scale,
        );
    };
}

pub fn getGlobalTransform(data: *const Data, node: types.Node) Mat4 {
    var parent_index = node.parent;
    var node_transform: Mat4 = getLocalTransform(node);

    while (parent_index != null) {
        const parent = data.nodes.items[parent_index.?];
        const parent_transform = getLocalTransform(parent);

        node_transform = Mat4.mul(parent_transform, node_transform);
        parent_index = parent.parent;
    }

    return node_transform;
}

fn isGlb(glb_buffer: []align(4) const u8) bool {
    const GLB_MAGIC_NUMBER: u32 = 0x46546C67; // 'gltf' in ASCII.
    const fields = @as([*]const u32, @ptrCast(glb_buffer));

    return fields[0] == GLB_MAGIC_NUMBER;
}

fn parseGlb(self: *Self, glb_buffer: []align(4) const u8) !void {
    const GLB_CHUNK_TYPE_JSON: u32 = 0x4E4F534A; // 'JSON' in ASCII.
    const GLB_CHUNK_TYPE_BIN: u32 = 0x004E4942; // 'BIN' in ASCII.

    // Keep track of the moving index in the glb buffer.
    var index: usize = 0;

    // 'cause most of the interesting fields are u32s in the buffer, it's
    // easier to read them with a pointer cast.
    const fields = @as([*]const u32, @ptrCast(glb_buffer));

    // The 12-byte header consists of three 4-byte entries:
    //  u32 magic
    //  u32 version
    //  u32 length
    const total_length = blk: {
        const header = fields[0..3];

        const version = header[1];
        const length = header[2];

        if (!isGlb(glb_buffer)) {
            std.debug.panic("First 32 bits are not equal to magic number.", .{});
        }

        if (version != 2) {
            std.debug.panic("Only glTF spec v2 is supported.", .{});
        }

        index = header.len * @sizeOf(u32);
        break :blk length;
    };

    // Each chunk has the following structure:
    //  u32 chunkLength
    //  u32 chunkType
    //  ubyte[] chunkData
    const json_buffer = blk: {
        const json_chunk = fields[3..6];

        if (json_chunk[1] != GLB_CHUNK_TYPE_JSON) {
            std.debug.panic("First GLB chunk must be JSON data.", .{});
        }

        const json_bytes: u32 = fields[3];
        const start = index + 2 * @sizeOf(u32);
        const end = start + json_bytes;

        const json_buffer = glb_buffer[start..end];

        index = end;
        break :blk json_buffer;
    };

    const binary_buffer = blk: {
        const fields_index = index / @sizeOf(u32);

        const binary_bytes = fields[fields_index];
        const start = index + 2 * @sizeOf(u32);
        const end = start + binary_bytes;

        assert(end == total_length);

        std.debug.assert(start % 4 == 0);
        std.debug.assert(end % 4 == 0);
        const binary: []align(4) const u8 = @alignCast(glb_buffer[start..end]);

        if (fields[fields_index + 1] != GLB_CHUNK_TYPE_BIN) {
            std.debug.panic("Second GLB chunk must be binary data.", .{});
        }

        index = end;
        break :blk binary;
    };

    try self.parseGltfJson(json_buffer);
    self.glb_binary = binary_buffer;

    const buffer_views = self.data.buffer_views.items;

    for (self.data.images.items) |*image| {
        if (image.buffer_view) |buffer_view_index| {
            const buffer_view = buffer_views[buffer_view_index];
            const start = buffer_view.byte_offset;
            const end = start + buffer_view.byte_length;
            image.data = binary_buffer[start..end];
        }
    }
}

fn parseGltfJson(self: *Self, gltf_json: []const u8) !void {
    const alloc = self.arena.allocator();

    var gltf_parsed = try json.parseFromSlice(json.Value, alloc, gltf_json, .{});
    defer gltf_parsed.deinit();

    const gltf: *json.Value = &gltf_parsed.value;

    if (gltf.object.get("asset")) |json_value| {
        var asset = &self.data.asset;

        if (json_value.object.get("version")) |version| {
            asset.version = try alloc.dupe(u8, version.string);
        } else {
            std.debug.panic("Asset's version is missing.", .{});
        }

        if (json_value.object.get("generator")) |generator| {
            asset.generator = try alloc.dupe(u8, generator.string);
        }

        if (json_value.object.get("copyright")) |copyright| {
            asset.copyright = try alloc.dupe(u8, copyright.string);
        }
    }

    if (gltf.object.get("nodes")) |nodes| {
        for (nodes.array.items, 0..) |item, index| {
            const object = item.object;

            var node = types.Node{
                .name = undefined,
                .children = ArrayList(types.Index).init(alloc),
            };

            if (object.get("name")) |name| {
                node.name = try alloc.dupe(u8, name.string);
            } else {
                node.name = try fmt.allocPrint(alloc, "Node_{}", .{index});
            }

            if (object.get("mesh")) |mesh| {
                node.mesh = parseIndex(mesh);
            }

            if (object.get("camera")) |camera_index| {
                node.camera = parseIndex(camera_index);
            }

            if (object.get("skin")) |skin| {
                node.skin = parseIndex(skin);
            }

            if (object.get("children")) |children| {
                for (children.array.items) |value| {
                    try node.children.append(parseIndex(value));
                }
            }

            if (object.get("rotation")) |rotation| {
                for (rotation.array.items, 0..) |component, i| {
                    node.rotation[i] = parseFloat(f32, component);
                }
            }

            if (object.get("translation")) |translation| {
                for (translation.array.items, 0..) |component, i| {
                    node.translation[i] = parseFloat(f32, component);
                }
            }

            if (object.get("scale")) |scale| {
                for (scale.array.items, 0..) |component, i| {
                    node.scale[i] = parseFloat(f32, component);
                }
            }

            if (object.get("matrix")) |matrix| {
                node.matrix = [16]f32{
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1, 0,
                    0, 0, 0, 1,
                };

                for (matrix.array.items, 0..) |component, i| {
                    node.matrix.?[i] = parseFloat(f32, component);
                }
            }

            if (object.get("extensions")) |extensions| {
                if (extensions.object.get("KHR_lights_punctual")) |lights_punctual| {
                    if (lights_punctual.object.get("light")) |light| {
                        node.light = @as(types.Index, @intCast(light.integer));
                    }
                }
            }

            try self.data.nodes.append(node);
        }
    }

    if (gltf.object.get("cameras")) |cameras| {
        for (cameras.array.items, 0..) |item, index| {
            const object = item.object;

            var camera = types.Camera{
                .name = undefined,
                .type = undefined,
            };

            if (object.get("name")) |name| {
                camera.name = try alloc.dupe(u8, name.string);
            } else {
                camera.name = try fmt.allocPrint(alloc, "Camera_{}", .{index});
            }

            if (object.get("type")) |name| {
                if (mem.eql(u8, name.string, "perspective")) {
                    if (object.get("perspective")) |perspective| {
                        var value = perspective.object;

                        camera.type = .{
                            .perspective = .{
                                .aspect_ratio = parseFloat(
                                    f32,
                                    value.get("aspectRatio").?,
                                ),
                                .yfov = parseFloat(f32, value.get("yfov").?),
                                .zfar = parseFloat(f32, value.get("zfar").?),
                                .znear = parseFloat(f32, value.get("znear").?),
                            },
                        };
                    } else {
                        std.debug.panic("Camera's perspective value is missing.", .{});
                    }
                } else if (mem.eql(u8, name.string, "orthographic")) {
                    if (object.get("orthographic")) |orthographic| {
                        var value = orthographic.object;

                        camera.type = .{
                            .orthographic = .{
                                .xmag = parseFloat(f32, value.get("xmag").?),
                                .ymag = parseFloat(f32, value.get("ymag").?),
                                .zfar = parseFloat(f32, value.get("zfar").?),
                                .znear = parseFloat(f32, value.get("znear").?),
                            },
                        };
                    } else {
                        std.debug.panic("Camera's orthographic value is missing.", .{});
                    }
                } else {
                    std.debug.panic(
                        "Camera's type must be perspective or orthographic.",
                        .{},
                    );
                }
            }

            try self.data.cameras.append(camera);
        }
    }

    if (gltf.object.get("skins")) |skins| {
        for (skins.array.items, 0..) |item, index| {
            const object = item.object;

            var skin = types.Skin{
                .name = undefined,
                .joints = ArrayList(types.Index).init(alloc),
            };

            if (object.get("name")) |name| {
                skin.name = try alloc.dupe(u8, name.string);
            } else {
                skin.name = try fmt.allocPrint(alloc, "Skin_{}", .{index});
            }

            if (object.get("joints")) |joints| {
                for (joints.array.items) |join| {
                    try skin.joints.append(parseIndex(join));
                }
            }

            if (object.get("skeleton")) |skeleton| {
                skin.skeleton = parseIndex(skeleton);
            }

            if (object.get("inverseBindMatrices")) |inv_bind_mat4| {
                skin.inverse_bind_matrices = parseIndex(inv_bind_mat4);
            }

            try self.data.skins.append(skin);
        }
    }

    if (gltf.object.get("meshes")) |meshes| {
        for (meshes.array.items, 0..) |item, index| {
            const object = item.object;

            var mesh: types.Mesh = .{
                .name = undefined,
                .primitives = ArrayList(types.Primitive).init(alloc),
            };

            if (object.get("name")) |name| {
                mesh.name = try alloc.dupe(u8, name.string);
            } else {
                mesh.name = try fmt.allocPrint(alloc, "Mesh_{}", .{index});
            }

            if (object.get("primitives")) |primitives| {
                for (primitives.array.items) |prim_item| {
                    var primitive: types.Primitive = .{
                        .attributes = ArrayList(types.Attribute).init(alloc),
                    };

                    if (prim_item.object.get("mode")) |mode| {
                        primitive.mode = @as(types.Mode, @enumFromInt(mode.integer));
                    }

                    if (prim_item.object.get("indices")) |indices| {
                        primitive.indices = parseIndex(indices);
                    }

                    if (prim_item.object.get("material")) |material| {
                        primitive.material = parseIndex(material);
                    }

                    if (prim_item.object.get("attributes")) |attributes| {
                        if (attributes.object.get("POSITION")) |position| {
                            try primitive.attributes.append(
                                .{
                                    .position = parseIndex(position),
                                },
                            );
                        }

                        if (attributes.object.get("NORMAL")) |normal| {
                            try primitive.attributes.append(
                                .{
                                    .normal = parseIndex(normal),
                                },
                            );
                        }

                        if (attributes.object.get("TANGENT")) |tangent| {
                            try primitive.attributes.append(
                                .{
                                    .tangent = parseIndex(tangent),
                                },
                            );
                        }

                        const texcoords = [_][]const u8{
                            "TEXCOORD_0",
                            "TEXCOORD_1",
                            "TEXCOORD_2",
                            "TEXCOORD_3",
                            "TEXCOORD_4",
                            "TEXCOORD_5",
                            "TEXCOORD_6",
                        };

                        for (texcoords) |tex_name| {
                            if (attributes.object.get(tex_name)) |texcoord| {
                                try primitive.attributes.append(
                                    .{
                                        .texcoord = parseIndex(texcoord),
                                    },
                                );
                            }
                        }

                        const joints = [_][]const u8{
                            "JOINTS_0",
                            "JOINTS_1",
                            "JOINTS_2",
                            "JOINTS_3",
                            "JOINTS_4",
                            "JOINTS_5",
                            "JOINTS_6",
                        };

                        for (joints) |join_count| {
                            if (attributes.object.get(join_count)) |joint| {
                                try primitive.attributes.append(
                                    .{
                                        .joints = parseIndex(joint),
                                    },
                                );
                            }
                        }

                        const weights = [_][]const u8{
                            "WEIGHTS_0",
                            "WEIGHTS_1",
                            "WEIGHTS_2",
                            "WEIGHTS_3",
                            "WEIGHTS_4",
                            "WEIGHTS_5",
                            "WEIGHTS_6",
                        };

                        for (weights) |weight_count| {
                            if (attributes.object.get(weight_count)) |weight| {
                                try primitive.attributes.append(
                                    .{
                                        .weights = parseIndex(weight),
                                    },
                                );
                            }
                        }
                    }

                    try mesh.primitives.append(primitive);
                }
            }

            try self.data.meshes.append(mesh);
        }
    }

    if (gltf.object.get("accessors")) |accessors| {
        for (accessors.array.items) |item| {
            const object = item.object;

            var accessor = types.Accessor{
                .component_type = undefined,
                .type = undefined,
                .count = undefined,
                .stride = undefined,
            };

            if (object.get("componentType")) |component_type| {
                accessor.component_type = @as(types.ComponentType, @enumFromInt(component_type.integer));
            } else {
                std.debug.panic("Accessor's componentType is missing.", .{});
            }

            if (object.get("count")) |count| {
                accessor.count = @as(i32, @intCast(count.integer));
            } else {
                std.debug.panic("Accessor's count is missing.", .{});
            }

            if (object.get("type")) |accessor_type| {
                if (mem.eql(u8, accessor_type.string, "SCALAR")) {
                    accessor.type = .scalar;
                } else if (mem.eql(u8, accessor_type.string, "VEC2")) {
                    accessor.type = .vec2;
                } else if (mem.eql(u8, accessor_type.string, "VEC3")) {
                    accessor.type = .vec3;
                } else if (mem.eql(u8, accessor_type.string, "VEC4")) {
                    accessor.type = .vec4;
                } else if (mem.eql(u8, accessor_type.string, "MAT2")) {
                    accessor.type = .mat2x2;
                } else if (mem.eql(u8, accessor_type.string, "MAT3")) {
                    accessor.type = .mat3x3;
                } else if (mem.eql(u8, accessor_type.string, "MAT4")) {
                    accessor.type = .mat4x4;
                } else {
                    std.debug.panic("Accessor's type '{s}' is invalid.", .{accessor_type.string});
                }
            } else {
                std.debug.panic("Accessor's type is missing.", .{});
            }

            if (object.get("normalized")) |normalized| {
                accessor.normalized = normalized.bool;
            }

            if (object.get("bufferView")) |buffer_view| {
                accessor.buffer_view = parseIndex(buffer_view);
            }

            if (object.get("byteOffset")) |byte_offset| {
                accessor.byte_offset = @as(usize, @intCast(byte_offset.integer));
            }

            const component_size: usize = switch (accessor.component_type) {
                .byte => @sizeOf(i8),
                .unsigned_byte => @sizeOf(u8),
                .short => @sizeOf(i16),
                .unsigned_short => @sizeOf(u16),
                .unsigned_integer => @sizeOf(u32),
                .float => @sizeOf(f32),
            };

            accessor.stride = switch (accessor.type) {
                .scalar => component_size,
                .vec2 => 2 * component_size,
                .vec3 => 3 * component_size,
                .vec4 => 4 * component_size,
                .mat2x2 => 4 * component_size,
                .mat3x3 => 9 * component_size,
                .mat4x4 => 16 * component_size,
            };

            try self.data.accessors.append(accessor);
        }
    }

    if (gltf.object.get("bufferViews")) |buffer_views| {
        for (buffer_views.array.items) |item| {
            const object = item.object;

            var buffer_view = types.BufferView{
                .buffer = undefined,
                .byte_length = undefined,
            };

            if (object.get("buffer")) |buffer| {
                buffer_view.buffer = parseIndex(buffer);
            }

            if (object.get("byteLength")) |byte_length| {
                buffer_view.byte_length = @as(usize, @intCast(byte_length.integer));
            }

            if (object.get("byteOffset")) |byte_offset| {
                buffer_view.byte_offset = @as(usize, @intCast(byte_offset.integer));
            }

            if (object.get("byteStride")) |byte_stride| {
                buffer_view.byte_stride = @as(usize, @intCast(byte_stride.integer));
            }

            if (object.get("target")) |target| {
                buffer_view.target = @as(types.Target, @enumFromInt(target.integer));
            }

            try self.data.buffer_views.append(buffer_view);
        }
    }

    if (gltf.object.get("buffers")) |buffers| {
        for (buffers.array.items) |item| {
            const object = item.object;

            var buffer = types.Buffer{
                .byte_length = undefined,
            };

            if (object.get("uri")) |uri| {
                buffer.uri = uri.string;
            }

            if (object.get("byteLength")) |byte_length| {
                buffer.byte_length = @as(usize, @intCast(byte_length.integer));
            } else {
                std.debug.panic("Buffer's byteLength is missing.", .{});
            }

            try self.data.buffers.append(buffer);
        }
    }

    if (gltf.object.get("scene")) |default_scene| {
        self.data.scene = parseIndex(default_scene);
    }

    if (gltf.object.get("scenes")) |scenes| {
        for (scenes.array.items, 0..) |item, index| {
            const object = item.object;

            var scene = types.Scene{
                .name = undefined,
            };

            if (object.get("name")) |name| {
                scene.name = try alloc.dupe(u8, name.string);
            } else {
                scene.name = try fmt.allocPrint(alloc, "Scene_{}", .{index});
            }

            if (object.get("nodes")) |nodes| {
                scene.nodes = ArrayList(types.Index).init(alloc);

                for (nodes.array.items) |node| {
                    try scene.nodes.?.append(parseIndex(node));
                }
            }

            try self.data.scenes.append(scene);
        }
    }

    if (gltf.object.get("materials")) |materials| {
        for (materials.array.items, 0..) |item, m_index| {
            const object = item.object;

            var material = types.Material{
                .name = undefined,
            };

            if (object.get("name")) |name| {
                material.name = try alloc.dupe(u8, name.string);
            } else {
                material.name = try fmt.allocPrint(alloc, "Material_{}", .{m_index});
            }

            if (object.get("pbrMetallicRoughness")) |pbrMetallicRoughness| {
                var metallic_roughness: types.MetallicRoughness = .{};
                if (pbrMetallicRoughness.object.get("baseColorFactor")) |color_factor| {
                    for (color_factor.array.items, 0..) |factor, i| {
                        metallic_roughness.base_color_factor[i] = parseFloat(f32, factor);
                    }
                }

                if (pbrMetallicRoughness.object.get("metallicFactor")) |factor| {
                    metallic_roughness.metallic_factor = parseFloat(f32, factor);
                }

                if (pbrMetallicRoughness.object.get("roughnessFactor")) |factor| {
                    metallic_roughness.roughness_factor = parseFloat(f32, factor);
                }

                if (pbrMetallicRoughness.object.get("baseColorTexture")) |texture_info| {
                    metallic_roughness.base_color_texture = .{
                        .index = undefined,
                    };

                    if (texture_info.object.get("index")) |index| {
                        metallic_roughness.base_color_texture.?.index = parseIndex(index);
                    }

                    if (texture_info.object.get("texCoord")) |texcoord| {
                        metallic_roughness.base_color_texture.?.texcoord = @as(i32, @intCast(texcoord.integer));
                    }
                }

                if (pbrMetallicRoughness.object.get("metallicRoughnessTexture")) |texture_info| {
                    metallic_roughness.metallic_roughness_texture = .{
                        .index = undefined,
                    };

                    if (texture_info.object.get("index")) |index| {
                        metallic_roughness.metallic_roughness_texture.?.index = parseIndex(index);
                    }

                    if (texture_info.object.get("texCoord")) |texcoord| {
                        metallic_roughness.metallic_roughness_texture.?.texcoord = @as(i32, @intCast(texcoord.integer));
                    }
                }

                material.metallic_roughness = metallic_roughness;
            }

            if (object.get("normalTexture")) |normal_texture| {
                material.normal_texture = .{
                    .index = undefined,
                };

                if (normal_texture.object.get("index")) |index| {
                    material.normal_texture.?.index = parseIndex(index);
                }

                if (normal_texture.object.get("texCoord")) |index| {
                    material.normal_texture.?.texcoord = @as(i32, @intCast(index.integer));
                }

                if (normal_texture.object.get("scale")) |scale| {
                    material.normal_texture.?.scale = parseFloat(f32, scale);
                }
            }

            if (object.get("emissiveTexture")) |emissive_texture| {
                material.emissive_texture = .{
                    .index = undefined,
                };

                if (emissive_texture.object.get("index")) |index| {
                    material.emissive_texture.?.index = parseIndex(index);
                }

                if (emissive_texture.object.get("texCoord")) |index| {
                    material.emissive_texture.?.texcoord = @as(i32, @intCast(index.integer));
                }
            }

            if (object.get("occlusionTexture")) |occlusion_texture| {
                material.occlusion_texture = .{
                    .index = undefined,
                };

                if (occlusion_texture.object.get("index")) |index| {
                    material.occlusion_texture.?.index = parseIndex(index);
                }

                if (occlusion_texture.object.get("texCoord")) |index| {
                    material.occlusion_texture.?.texcoord = @as(i32, @intCast(index.integer));
                }

                if (occlusion_texture.object.get("strength")) |strength| {
                    material.occlusion_texture.?.strength = parseFloat(f32, strength);
                }
            }

            if (object.get("alphaMode")) |alpha_mode| {
                if (mem.eql(u8, alpha_mode.string, "OPAQUE")) {
                    material.alpha_mode = .@"opaque";
                }
                if (mem.eql(u8, alpha_mode.string, "MASK")) {
                    material.alpha_mode = .mask;
                }
                if (mem.eql(u8, alpha_mode.string, "BLEND")) {
                    material.alpha_mode = .blend;
                }
            }

            if (object.get("doubleSided")) |double_sided| {
                material.is_double_sided = double_sided.bool;
            }

            if (object.get("alphaCutoff")) |alpha_cutoff| {
                material.alpha_cutoff = parseFloat(f32, alpha_cutoff);
            }

            if (object.get("emissiveFactor")) |emissive_factor| {
                for (emissive_factor.array.items, 0..) |factor, i| {
                    material.emissive_factor[i] = parseFloat(f32, factor);
                }
            }

            if (object.get("extensions")) |extensions| {
                if (extensions.object.get("KHR_materials_emissive_strength")) |materials_emissive_strength| {
                    if (materials_emissive_strength.object.get("emissiveStrength")) |emissive_strength| {
                        material.emissive_strength = parseFloat(f32, emissive_strength);
                    }
                }

                if (extensions.object.get("KHR_materials_ior")) |materials_ior| {
                    if (materials_ior.object.get("ior")) |ior| {
                        material.ior = parseFloat(f32, ior);
                    }
                }

                if (extensions.object.get("KHR_materials_transmission")) |materials_transmission| {
                    if (materials_transmission.object.get("transmissionFactor")) |transmission_factor| {
                        material.transmission_factor = parseFloat(f32, transmission_factor);
                    }

                    if (materials_transmission.object.get("transmissionTexture")) |transmission_texture| {
                        material.transmission_texture = .{
                            .index = undefined,
                        };

                        if (transmission_texture.object.get("index")) |index| {
                            material.transmission_texture.?.index = parseIndex(index);
                        }

                        if (transmission_texture.object.get("texCoord")) |index| {
                            material.transmission_texture.?.texcoord = @as(i32, @intCast(index.integer));
                        }
                    }
                }
            }

            try self.data.materials.append(material);
        }
    }

    if (gltf.object.get("textures")) |textures| {
        for (textures.array.items) |item| {
            var texture = types.Texture{};

            if (item.object.get("source")) |source| {
                texture.source = parseIndex(source);
            }

            if (item.object.get("sampler")) |sampler| {
                texture.sampler = parseIndex(sampler);
            }

            try self.data.textures.append(texture);
        }
    }

    if (gltf.object.get("animations")) |animations| {
        for (animations.array.items, 0..) |item, index| {
            const object = item.object;

            var animation = types.Animation{
                .samplers = ArrayList(types.AnimationSampler).init(alloc),
                .channels = ArrayList(types.Channel).init(alloc),
                .name = undefined,
            };

            if (item.object.get("name")) |name| {
                animation.name = try alloc.dupe(u8, name.string);
            } else {
                animation.name = try fmt.allocPrint(alloc, "Animation_{}", .{index});
            }

            if (object.get("samplers")) |samplers| {
                for (samplers.array.items) |sampler_item| {
                    var sampler: types.AnimationSampler = .{
                        .input = undefined,
                        .output = undefined,
                    };

                    if (sampler_item.object.get("input")) |input| {
                        sampler.input = parseIndex(input);
                    } else {
                        std.debug.panic("Animation sampler's input is missing.", .{});
                    }

                    if (sampler_item.object.get("output")) |output| {
                        sampler.output = parseIndex(output);
                    } else {
                        std.debug.panic("Animation sampler's output is missing.", .{});
                    }

                    if (sampler_item.object.get("interpolation")) |interpolation| {
                        if (mem.eql(u8, interpolation.string, "LINEAR")) {
                            sampler.interpolation = .linear;
                        }

                        if (mem.eql(u8, interpolation.string, "STEP")) {
                            sampler.interpolation = .step;
                        }

                        if (mem.eql(u8, interpolation.string, "CUBICSPLINE")) {
                            sampler.interpolation = .cubicspline;
                        }
                    }

                    try animation.samplers.append(sampler);
                }
            }

            if (object.get("channels")) |channels| {
                for (channels.array.items) |channel_item| {
                    var channel: types.Channel = .{ .sampler = undefined, .target = .{
                        .node = undefined,
                        .property = undefined,
                    } };

                    if (channel_item.object.get("sampler")) |sampler_index| {
                        channel.sampler = parseIndex(sampler_index);
                    } else {
                        std.debug.panic("Animation channel's sampler is missing.", .{});
                    }

                    if (channel_item.object.get("target")) |target_item| {
                        if (target_item.object.get("node")) |node_index| {
                            channel.target.node = parseIndex(node_index);
                        } else {
                            std.debug.panic("Animation target's node is missing.", .{});
                        }

                        if (target_item.object.get("path")) |path| {
                            if (mem.eql(u8, path.string, "translation")) {
                                channel.target.property = .translation;
                            } else if (mem.eql(u8, path.string, "rotation")) {
                                channel.target.property = .rotation;
                            } else if (mem.eql(u8, path.string, "scale")) {
                                channel.target.property = .scale;
                            } else if (mem.eql(u8, path.string, "weights")) {
                                channel.target.property = .weights;
                            } else {
                                std.debug.panic("Animation path/property is invalid.", .{});
                            }
                        } else {
                            std.debug.panic("Animation target's path/property is missing.", .{});
                        }
                    } else {
                        std.debug.panic("Animation channel's target is missing.", .{});
                    }

                    try animation.channels.append(channel);
                }
            }

            try self.data.animations.append(animation);
        }
    }

    if (gltf.object.get("samplers")) |samplers| {
        for (samplers.array.items) |item| {
            const object = item.object;
            var sampler = types.TextureSampler{};

            if (object.get("magFilter")) |mag_filter| {
                sampler.mag_filter = @as(types.MagFilter, @enumFromInt(mag_filter.integer));
            }

            if (object.get("minFilter")) |min_filter| {
                sampler.min_filter = @as(types.MinFilter, @enumFromInt(min_filter.integer));
            }

            if (object.get("wrapS")) |wrap_s| {
                sampler.wrap_s = @as(types.WrapMode, @enumFromInt(wrap_s.integer));
            }

            if (object.get("wrapt")) |wrap_t| {
                sampler.wrap_t = @as(types.WrapMode, @enumFromInt(wrap_t.integer));
            }

            try self.data.samplers.append(sampler);
        }
    }

    if (gltf.object.get("images")) |images| {
        for (images.array.items) |item| {
            const object = item.object;
            var image = types.Image{};

            if (object.get("uri")) |uri| {
                image.uri = try alloc.dupe(u8, uri.string);
            }

            if (object.get("mimeType")) |mime_type| {
                image.mime_type = try alloc.dupe(u8, mime_type.string);
            }

            if (object.get("bufferView")) |buffer_view| {
                image.buffer_view = parseIndex(buffer_view);
            }

            try self.data.images.append(image);
        }
    }

    if (gltf.object.get("extensions")) |extensions| {
        if (extensions.object.get("KHR_lights_punctual")) |lights_punctual| {
            if (lights_punctual.object.get("lights")) |lights| {
                for (lights.array.items) |item| {
                    const object: json.ObjectMap = item.object;

                    var light = types.Light{
                        .name = null,
                        .type = undefined,
                        .range = math.inf(f32),
                        .spot = null,
                    };

                    if (object.get("name")) |name| {
                        light.name = try alloc.dupe(u8, name.string);
                    }

                    if (object.get("color")) |color| {
                        for (color.array.items, 0..) |component, i| {
                            light.color[i] = parseFloat(f32, component);
                        }
                    }

                    if (object.get("intensity")) |intensity| {
                        light.intensity = parseFloat(f32, intensity);
                    }

                    if (object.get("type")) |@"type"| {
                        if (std.meta.stringToEnum(types.LightType, @"type".string)) |light_type| {
                            light.type = light_type;
                        } else std.debug.panic("Light's type invalid", .{});
                    }

                    if (object.get("range")) |range| {
                        light.range = parseFloat(f32, range);
                    }

                    if (object.get("spot")) |spot| {
                        light.spot = .{};

                        if (spot.object.get("innerConeAngle")) |inner_cone_angle| {
                            light.spot.?.inner_cone_angle = parseFloat(f32, inner_cone_angle);
                        }

                        if (spot.object.get("outerConeAngle")) |outer_cone_angle| {
                            light.spot.?.outer_cone_angle = parseFloat(f32, outer_cone_angle);
                        }
                    }

                    try self.data.lights.append(light);
                }
            }
        }
    }

    // For each node, fill parent indexes.
    for (self.data.scenes.items) |scene| {
        if (scene.nodes) |nodes| {
            for (nodes.items) |node_index| {
                const node = &self.data.nodes.items[node_index];
                fillParents(&self.data, node, node_index);
            }
        }
    }
}

fn parseIndex(component: json.Value) usize {
    return switch (component) {
        .integer => |val| @as(usize, @intCast(val)),
        else => std.debug.panic(
            "The json component '{any}' is not valid number.",
            .{component},
        ),
    };
}

fn parseFloat(comptime T: type, component: json.Value) T {
    const type_info = @typeInfo(T);
    if (type_info != .Float) {
        std.debug.panic(
            "Given type '{any}' is not a floating number.",
            .{type_info},
        );
    }

    return switch (component) {
        .float => |val| @as(T, @floatCast(val)),
        .integer => |val| @as(T, @floatFromInt(val)),
        else => std.debug.panic(
            "The json component '{any}' is not a number.",
            .{component},
        ),
    };
}

fn fillParents(data: *Data, node: *types.Node, parent_index: types.Index) void {
    for (node.children.items) |child_index| {
        var child_node = &data.nodes.items[child_index];
        child_node.parent = parent_index;
        fillParents(data, child_node, child_index);
    }
}

test "gltf.parseGlb" {
    const allocator = std.testing.allocator;
    const expectEqualSlices = std.testing.expectEqualSlices;

    // This is the '.glb' file.
    const glb_buf = try std.fs.cwd().readFileAllocOptions(allocator, "test-samples/box_binary/Box.glb", 512_000, null, 4, null);
    defer allocator.free(glb_buf);

    var gltf = Self.init(allocator);
    defer gltf.deinit();

    try expectEqualSlices(u8, gltf.data.asset.version, "Undefined");

    try gltf.parseGlb(glb_buf);

    const mesh = gltf.data.meshes.items[0];
    for (mesh.primitives.items) |primitive| {
        for (primitive.attributes.items) |attribute| {
            switch (attribute) {
                .position => |accessor_index| {
                    var tmp = ArrayList(f32).init(allocator);
                    defer tmp.deinit();

                    const accessor = gltf.data.accessors.items[accessor_index];
                    gltf.getDataFromBufferView(f32, &tmp, accessor, gltf.glb_binary.?);

                    try expectEqualSlices(f32, tmp.items, &[72]f32{
                        -0.50, -0.50, 0.50,  0.50,  -0.50, 0.50,  -0.50, 0.50,  0.50,
                        0.50,  0.50,  0.50,  0.50,  -0.50, 0.50,  -0.50, -0.50, 0.50,
                        0.50,  -0.50, -0.50, -0.50, -0.50, -0.50, 0.50,  0.50,  0.50,
                        0.50,  -0.50, 0.50,  0.50,  0.50,  -0.50, 0.50,  -0.50, -0.50,
                        -0.50, 0.50,  0.50,  0.50,  0.50,  0.50,  -0.50, 0.50,  -0.50,
                        0.50,  0.50,  -0.50, -0.50, -0.50, 0.50,  -0.50, 0.50,  0.50,
                        -0.50, -0.50, -0.50, -0.50, 0.50,  -0.50, -0.50, -0.50, -0.50,
                        -0.50, 0.50,  -0.50, 0.50,  -0.50, -0.50, 0.50,  0.50,  -0.50,
                    });
                },
                else => {},
            }
        }
    }
}

test "gltf.parseGlbTextured" {
    const allocator = std.testing.allocator;
    const expectEqualSlices = std.testing.expectEqualSlices;

    // This is the '.glb' file.
    const glb_buf = try std.fs.cwd().readFileAllocOptions(allocator, "test-samples/box_binary_textured/BoxTextured.glb", 512_000, null, 4, null);
    defer allocator.free(glb_buf);

    var gltf = Self.init(allocator);
    defer gltf.deinit();

    try gltf.parseGlb(glb_buf);

    const test_to_check = try std.fs.cwd().readFileAlloc(allocator, "test-samples/box_binary_textured/test.png", 512_000);
    defer allocator.free(test_to_check);

    const data = gltf.data.images.items[0].data.?;
    try expectEqualSlices(u8, test_to_check, data);
}

test "gltf.parse" {
    const allocator = std.testing.allocator;
    const expectEqualSlices = std.testing.expectEqualSlices;
    const expectEqual = std.testing.expectEqual;

    // This is the '.gltf' file, a json specifying what information is in the
    // model and how to retrieve it inside binary file(s).
    const buf = try std.fs.cwd().readFileAllocOptions(allocator, "test-samples/rigged_simple/RiggedSimple.gltf", 512_000, null, 4, null);
    defer allocator.free(buf);

    var gltf = Self.init(allocator);
    defer gltf.deinit();

    try expectEqualSlices(u8, gltf.data.asset.version, "Undefined");

    try gltf.parse(buf);

    try expectEqualSlices(u8, gltf.data.asset.version, "2.0");
    try expectEqualSlices(u8, gltf.data.asset.generator.?, "COLLADA2GLTF");

    try expectEqual(gltf.data.scene, 0);

    // Nodes.
    const nodes = gltf.data.nodes.items;
    try expectEqualSlices(u8, nodes[0].name, "Z_UP");
    try expectEqualSlices(usize, nodes[0].children.items, &[_]usize{1});
    try expectEqualSlices(u8, nodes[2].name, "Cylinder");
    try expectEqual(nodes[2].skin, 0);

    try expectEqual(gltf.data.buffers.items.len > 0, true);

    // Skin
    const skin = gltf.data.skins.items[0];
    try expectEqualSlices(u8, skin.name, "Armature");
}

test "gltf.parse (cameras)" {
    const allocator = std.testing.allocator;
    const expectEqual = std.testing.expectEqual;

    const buf = try std.fs.cwd().readFileAllocOptions(allocator, "test-samples/cameras/Cameras.gltf", 512_000, null, 4, null);
    defer allocator.free(buf);

    var gltf = Self.init(allocator);
    defer gltf.deinit();

    try gltf.parse(buf);

    try expectEqual(gltf.data.nodes.items[1].camera, 0);
    try expectEqual(gltf.data.nodes.items[2].camera, 1);

    const camera_0 = gltf.data.cameras.items[0];
    try expectEqual(camera_0.type.perspective, types.Camera.Perspective{
        .aspect_ratio = 1.0,
        .yfov = 0.7,
        .zfar = 100,
        .znear = 0.01,
    });

    const camera_1 = gltf.data.cameras.items[1];
    try expectEqual(camera_1.type.orthographic, types.Camera.Orthographic{
        .xmag = 1.0,
        .ymag = 1.0,
        .zfar = 100,
        .znear = 0.01,
    });
}

test "gltf.getDataFromBufferView" {
    const allocator = std.testing.allocator;
    const expectEqualSlices = std.testing.expectEqualSlices;

    const buf = try std.fs.cwd().readFileAllocOptions(allocator, "test-samples/box/Box.gltf", 512_000, null, 4, null);
    defer allocator.free(buf);

    // This is the '.bin' file containing all the gltf underneath data.
    const binary = try std.fs.cwd().readFileAllocOptions(
        allocator,
        "test-samples/box/Box0.bin",
        5_000_000,
        null,
        // From gltf spec, data from BufferView should be 4 bytes aligned.
        4,
        null,
    );
    defer allocator.free(binary);

    var gltf = Self.init(allocator);
    defer gltf.deinit();

    try gltf.parse(buf);

    const mesh = gltf.data.meshes.items[0];
    for (mesh.primitives.items) |primitive| {
        for (primitive.attributes.items) |attribute| {
            switch (attribute) {
                .position => |accessor_index| {
                    var tmp = ArrayList(f32).init(allocator);
                    defer tmp.deinit();

                    const accessor = gltf.data.accessors.items[accessor_index];
                    gltf.getDataFromBufferView(f32, &tmp, accessor, binary);

                    try expectEqualSlices(f32, tmp.items, &[72]f32{
                        // zig fmt: off
                        -0.50, -0.50, 0.50, 0.50, -0.50, 0.50, -0.50, 0.50, 0.50,
                        0.50, 0.50, 0.50, 0.50, -0.50, 0.50, -0.50, -0.50, 0.50, 
                        0.50, -0.50, -0.50, -0.50, -0.50, -0.50, 0.50, 0.50, 0.50, 
                        0.50, -0.50, 0.50, 0.50, 0.50, -0.50, 0.50, -0.50, -0.50, 
                        -0.50, 0.50, 0.50, 0.50, 0.50, 0.50, -0.50, 0.50, -0.50, 
                        0.50, 0.50, -0.50, -0.50, -0.50, 0.50, -0.50, 0.50, 0.50, 
                        -0.50, -0.50, -0.50, -0.50, 0.50, -0.50, -0.50, -0.50, -0.50, 
                        -0.50, 0.50, -0.50, 0.50, -0.50, -0.50, 0.50, 0.50, -0.50,
                    });
                },
                else => {},
            }
        }
    }
}

test "gltf.parse (lights)" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;

    const buf = try std.fs.cwd().readFileAllocOptions(
        allocator,
        "test-samples/khr_lights_punctual/Lights.gltf",
        512_000,
        null,
        4,
        null
    );
    defer allocator.free(buf);

    var gltf = Self.init(allocator);
    defer gltf.deinit();

    try gltf.parse(buf);

    try expectEqual(@as(usize, 3), gltf.data.lights.items.len);

    try expect(gltf.data.lights.items[0].name != null);
    try expect(std.mem.eql(u8, "Light", gltf.data.lights.items[0].name.?));
    try expectEqual([3]f32 { 1, 1, 1 }, gltf.data.lights.items[0].color);
    try expectEqual(@as(f32, 1000), gltf.data.lights.items[0].intensity);
    try expectEqual(types.LightType.point, gltf.data.lights.items[0].type);

    try expect(gltf.data.lights.items[1].name != null);
    try expect(std.mem.eql(u8, "Light.001", gltf.data.lights.items[1].name.?));
    try expectEqual([3]f32 { 1, 1, 1 }, gltf.data.lights.items[1].color);
    try expectEqual(@as(f32, 1000), gltf.data.lights.items[1].intensity);
    try expectEqual(types.LightType.spot, gltf.data.lights.items[1].type);

    try expect(gltf.data.lights.items[1].spot != null);
    try expectEqual(@as(f32, 0), gltf.data.lights.items[1].spot.?.inner_cone_angle);
    try expectEqual(@as(f32, 1), gltf.data.lights.items[1].spot.?.outer_cone_angle);

    try expect(gltf.data.lights.items[2].name != null);
    try expect(std.mem.eql(u8, "Light.002", gltf.data.lights.items[2].name.?));
    try expectEqual([3]f32 { 1, 1, 1 }, gltf.data.lights.items[2].color);
    try expectEqual(@as(f32, 1000), gltf.data.lights.items[2].intensity);
    try expectEqual(types.LightType.directional, gltf.data.lights.items[2].type);

    try expect(gltf.data.nodes.items[0].light != null);
    try expectEqual(@as(?types.Index, 0), gltf.data.nodes.items[0].light);
}
