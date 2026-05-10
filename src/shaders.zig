pub const spv = "src/example/shaders/compiled/";
pub const src = "src/example/shaders/";

pub const ShaderDef = union(enum) {
    compute: struct { file: []const u8, entry: []const u8 },
    graphics: struct { file: []const u8, entry_vert: []const u8, entry_frag: []const u8 },
    mesh_graphics: struct { file: []const u8, entry_mesh: []const u8, entry_frag: []const u8 },
};

pub const shaders = [_]ShaderDef{
    .{
        .graphics = .{
            .file = "rastermain.slang",
            .entry_vert = "vertexMain",
            .entry_frag = "fragmentMain",
        },
    },
    .{
        .mesh_graphics = .{
            .file = "rastermain_mesh.slang",
            .entry_mesh = "meshMain",
            .entry_frag = "meshFragmentMain",
        },
    },
    .{
        .compute = .{
            .file = "drawcmd.slang",
            .entry = "drawcmdMain",
        },
    },
    .{
        .compute = .{
            .file = "terrain.slang",
            .entry = "terrainMain",
        },
    },
    .{
        .graphics = .{
            .file = "vectorgfx.slang",
            .entry_vert = "slugVertex",
            .entry_frag = "slugFragment",
        },
    },
};
