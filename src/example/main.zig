const std = @import("std");
const m = @import("matrisen");
const log = std.log.scoped(.main);
const Core = m.Core;
const Vertex = m.BufferManager.Vertex;
const Camera = m.Camera;
const BufferManager = m.BufferManager;
const Quat = m.linalg.Quat(f32);
const Vec2 = m.linalg.Vec2(f32);
const Vec3 = m.linalg.Vec3(f32);
const Vec4 = m.linalg.Vec4(f32);
const Mat4x4 = m.linalg.Mat4x4(f32);
const Mesh = m.BufferManager.Mesh;

pub fn loop(io: std.Io, engine: *Core, window: *m.Window) !void {
    window.toggleMouseCapture();
    const t_start = std.Io.Clock.awake.now(io);
    var t = std.Io.Clock.awake.now(io);

    var time: f32 = 0;
    var camera: Camera = .init;

    camera.orientation.rotatePitch(std.math.degreesToRadians(-90));
    camera.distance = 250;

    while (!window.state.quit) {
        // const dt = @as(f32, @floatFromInt(t.untilNow(io, .awake).toNanoseconds())) / 1_000_000_000;
        t = std.Io.Clock.awake.now(io);
        // std.debug.print("delta time is {0:2} s      ", .{dt});
        time = @as(f32, @floatFromInt(t_start.untilNow(io, .awake).toNanoseconds())) / 1_000_000_000;
        // std.debug.print("time is  {0:2} s", .{time});
        std.debug.print("                                                                  \r", .{});
        window.processInput();
        // camera.firstPerson(window);
        camera.orbit(window);
        engine.updateScene(camera, time);
        engine.nextFrame(window);
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;
    var window: m.Window = .init(2000, 1200);
    defer window.deinit();
    var engine: Core = .init(allocator, &window);
    defer engine.deinit();

    try engine.buffermanager.initEngineBuffers(&engine, &engine.descriptormanager);
    engine.buffermanager.initEmptyMesh(&engine, 256 * 256);
    engine.buffermanager.testUI(&engine);
    try loop(io, &engine, &window);
}
