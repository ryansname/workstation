const glfw = @import("glfw");
const std = @import("std");

// It'd be cool
//
// - Commit log
//  - Highlight a commit
//  - Shows the diff
//  - Loads the ticket

pub fn main() anyerror!void {
    try glfw.init(.{});
    defer glfw.terminate();

    const window = try glfw.Window.create(640, 480, "Workstation", null, null, .{});
    defer window.destroy();

    while (!window.shouldClose()) {
        try glfw.pollEvents();
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
