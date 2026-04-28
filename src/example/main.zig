const std = @import("std");
const m = @import("matrisen");
const log = std.log.scoped(.main);
const Core = m.Core;
const Quat = m.linalg.Quat(f32);
const Vec3 = m.linalg.Vec3(f32);
const Vec4 = m.linalg.Vec4(f32);
const Mat4x4 = m.linalg.Mat4x4(f32);

pub fn loop(engine: *Core, window: *m.Window) void {
    window.toggleMouseCapture();
    var timer = std.time.Timer.start() catch @panic("Failed to start timer");
    var delta: u64 = undefined;
    var time: f32 = 0;
    var camerarot: Quat = .identity;
    var camerapos: Vec3 = .{ .x = 0, .y = -5, .z = 2 };
    // flip camera
    // camerarot.rotateRoll(std.math.degreesToRadians(180));
    // start
    camerarot.rotatePitch(std.math.degreesToRadians(-90));
    // self.initScene(engine);

    while (!window.state.quit) {
        delta = timer.read();
        window.processInput();
        if (window.state.w) camerapos.translateForward(&camerarot, 0.1);
        if (window.state.s) camerapos.translateForward(&camerarot, -0.1);
        if (window.state.a) camerapos.translatePitch(&camerarot, -0.1);
        if (window.state.d) camerapos.translatePitch(&camerarot, 0.1);
        if (window.state.q) camerapos.translateWorldZ(-0.1);
        if (window.state.e) camerapos.translateWorldZ(0.1);
        camerarot.rotatePitch(-window.state.mouse_y / 150);
        camerarot.rotateWorldZ(-window.state.mouse_x / 150);
        engine.updateScene(camerarot, camerapos, time);
        engine.nextFrame(window);
        time += @as(f32, @floatFromInt(delta)) / 100_000;
        timer.reset();
    }
}

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();
    var window: m.Window = .init(2000, 1200);
    defer window.deinit();
    var engine: Core = .init(allocator, &window);
    defer engine.deinit();

    // 1. Initialize empty GPU buffers
    try engine.buffermanager.initEngineBuffers(&engine, &engine.descriptormanager);

    // 2. Load/Generate meshes and upload them
    // const my_cube_verts = undefined;
    // const my_cube_indices = undefined;
    // const cube_draw_data = engine.buffermanager.uploadMesh(&engine, &my_cube_verts, &my_cube_indices, 0);

    // 3. Write DrawData to the GPU Array (you'd do this for however many instances you want)
    // const draws_ptr = @as(
    // [*]DrawData,
    // @ptrCast(@alignCast(engine.buffermanager.drawbuffer.info.pMappedData.?)),
    // );
    // draws_ptr[0] = cube_draw_data;
    // draws_ptr[1] = cube_draw_data; // Instance 2 of the cube!

    loop(&engine, &window);
}
