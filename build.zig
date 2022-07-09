const glfw = @import("libs/mach-glfw/build.zig");
const imgui = @import("libs/Zig-ImGui/zig-imgui/imgui_build.zig");
const std = @import("std");

const ChildProcess = std.ChildProcess;

const assert = std.debug.assert;

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("workstation", "src/main.zig");

    addDeps(b, exe);

    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    addDeps(b, exe_tests);
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    imgui.addTestStep(b, "imgui:test", mode, target);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

fn addDeps(b: *std.build.Builder, target: *std.build.LibExeObjStep) void {
    target.defineCMacro("GLFW_INCLUDE_NONE", null);

    target.addPackagePath("zgl", "libs/zgl/zgl.zig");
    target.linkSystemLibrary("epoxy");

    target.addPackage(glfw.pkg);
    glfw.link(b, target, .{});

    imgui.link(target);

    target.addLibPath("/opt/homebrew/lib/");
    target.addIncludeDir("/opt/homebrew/include/");
}
