const std = @import("std");
const m = @import("matrisen");
const log = std.log.scoped(.main);
const Core = m.Core;
const Vertex = m.BufferManager.Vertex;
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
    var camerarot: Quat = .identity;
    var camerapos: Vec3 = .{ .x = 0, .y = -5, .z = 2 };

    // flip camera
    // camerarot.rotateRoll(std.math.degreesToRadians(180));
    camerarot.rotatePitch(std.math.degreesToRadians(-90));

    while (!window.state.quit) {
        const dt_ns = timer.lap();
        const dt_s: f32 = @as(f32, @floatFromInt(dt_ns)) / 1_000_000_000.0;
        time += dt_s;
        window.processInput();
        if (window.state.w) camerapos.translateForward(&camerarot, 0.1);
        if (window.state.s) camerapos.translateForward(&camerarot, -0.1);
        if (window.state.a) camerapos.translatePitch(&camerarot, -0.1);
        if (window.state.d) camerapos.translatePitch(&camerarot, 0.1);
        if (window.state.q) camerapos.translateWorldZ(-0.1);
        if (window.state.e) camerapos.translateWorldZ(0.1);
        if (window.state.capturemouse) {
            camerarot.rotatePitch(-window.state.mouse_y / 150);
            camerarot.rotateWorldZ(-window.state.mouse_x / 150);
        }
        engine.updateScene(camerarot, camerapos, time);
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
