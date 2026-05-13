pub const spv = "src/example/shaders/compiled/";
pub const src = "src/example/shaders/";

pub const ShaderType = enum {
    ui,
    raster,
    raster_mesh,
    compute,
};

pub const ShaderDef2 = struct {
    name: []const u8, // name of pipeline
    file: []const u8,
    comp: ?[]const u8 = null,
    vert: ?[]const u8 = null,
    frag: ?[]const u8 = null,
    mesh: ?[]const u8 = null,
};

pub const ShaderDef = union(enum) {
    compute: struct { file: []const u8, entry: []const u8 },
    graphics: struct { file: []const u8, entry_vert: []const u8, entry_frag: []const u8 },
    mesh_graphics: struct { file: []const u8, entry_mesh: []const u8, entry_frag: []const u8 },
    ui: struct { file: []const u8, entry_mesh: []const u8, entry_frag: []const u8 },
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
            .file = "ui.slang",
            .entry_vert = "slugVertex",
            .entry_frag = "slugFragment",
        },
    },
    .{
        .ui = .{
            .file = "ui_mesh.slang",
            .entry_mesh = "uiMesh",
            .entry_frag = "uiFragment",
        },
    },
};

pub const shaders2 = [_]ShaderDef2{
    .{
        .file = "rastermain.slang",
        .vert = "vertexMain",
        .frag = "fragmentMain",
    },
    .{
        .file = "rastermain_mesh.slang",
        .mesh = "meshMain",
        .frag = "meshFragmentMain",
    },
    .{
        .file = "drawcmd.slang",
        .comp = "drawcmdMain",
    },
    .{
        .file = "terrain.slang",
        .comp = "terrainMain",
    },
    .{
        .file = "vectorgfx.slang",
        .vert = "slugVertex",
        .frag = "slugFragment",
    },
    .{
        .file = "vectorgfx.slang",
        .mesh = "slugMesh",
        .frag = "slugFragment",
    },
};
