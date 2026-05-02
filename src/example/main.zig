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

pub fn loop(engine: *Core, window: *m.Window) void {
    window.toggleMouseCapture();
    var timer = std.time.Timer.start() catch @panic("Failed to start timer");
    var time: f32 = 0;
    var camera: Camera = .init;

    camera.orientation.rotatePitch(std.math.degreesToRadians(-90));
    camera.distance = 250;

    while (!window.state.quit) {
        const dt_ns = timer.lap();
        const dt_s: f32 = @as(f32, @floatFromInt(dt_ns)) / 1_000_000_000.0;
        time += dt_s;
        window.processInput();
        // camera.firstPerson(window);
        camera.orbit(window);
        engine.updateScene(camera, time);
        engine.nextFrame(window);
    }
}

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();
    var window: m.Window = .init(2000, 1200);
    defer window.deinit();
    var engine: Core = .init(allocator, &window);
    defer engine.deinit();

    try engine.buffermanager.initEngineBuffers(&engine, &engine.descriptormanager);
    engine.buffermanager.initEmptyMesh(&engine);
    loop(&engine, &window);
}
