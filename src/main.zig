const builtin = @import("builtin");
const gl = @import("zgl");
const glfw = @import("glfw");
const imgui = @import("imgui");
const impl_gl3 = @import("imgui_impl_opengl3.zig");
const impl_glfw = @import("imgui_impl_glfw.zig");
const std = @import("std");

// It'd be cool
//
// - Commit log
//  - Highlight a commit
//  - Shows the diff
//  - Loads the ticket

pub fn main() anyerror!void {
    _ = glfw.setErrorCallback(errorCallback);

    try glfw.init(.{});
    defer glfw.terminate();

    var hints = glfw.Window.Hints{};
    if (builtin.os.tag.isDarwin()) {
        hints.context_version_major = 3;
        hints.context_version_minor = 2;
        hints.opengl_profile = .opengl_core_profile;
        hints.opengl_forward_compat = true;
    } else {
        hints.context_version_major = 3;
        hints.context_version_minor = 0;
    }

    const window = try glfw.Window.create(640, 480, "Workstation", null, null, hints);
    defer window.destroy();

    try glfw.makeContextCurrent(window);
    try glfw.swapInterval(1);

    imgui.CHECKVERSION();
    _ = imgui.CreateContext();
    defer imgui.DestroyContext();

    imgui.StyleColorsDark();

    _ = try impl_glfw.InitForOpenGL(window, true);
    defer impl_glfw.Shutdown();
    _ = try impl_gl3.Init("#version 150");
    defer impl_gl3.Shutdown();

    while (!window.shouldClose()) {
        try glfw.pollEvents();

        try impl_glfw.NewFrame();
        try impl_gl3.NewFrame();
        imgui.NewFrame();

        var show_demo = true;
        imgui.ShowDemoWindowExt(&show_demo);

        imgui.Render();
        const fb_size = try window.getFramebufferSize();
        gl.viewport(0, 0, fb_size.width, fb_size.height);

        impl_gl3.RenderDrawData(imgui.GetDrawData());
        try window.swapBuffers();
    }
}

fn errorCallback(_: glfw.Error, description: [:0]const u8) void {
    std.debug.panic("Error: {any}\n", .{description});
}

test "basic test" {
    _ = glfw.setErrorCallback(errorCallback);
    try glfw.init(.{});
    defer glfw.terminate();

    imgui.CHECKVERSION();
    _ = imgui.CreateContext();

    const window = try glfw.Window.create(640, 480, "Workstation", null, null, .{ .visible = false });
    defer window.destroy();

    _ = try impl_glfw.InitForOpenGL(window, true);

    _ = try impl_gl3.Init(null);
    defer impl_gl3.Shutdown();
}
