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

    addDeps(exe, target);

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
    addDeps(exe_tests, target);
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    imgui.addTestStep(b, "imgui:test", mode, target);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

fn addDeps(exe: *std.build.LibExeObjStep, target: std.zig.CrossTarget) void {
    imgui.link(exe);

    linkGlad(exe, target);
    linkGlfw(exe, target);

    linkJira(exe, target);

    exe.addLibraryPath("/opt/homebrew/lib/");
    exe.addIncludePath("/opt/homebrew/include/");
}

fn linkGlad(exe: *std.build.LibExeObjStep, target: std.zig.CrossTarget) void {
    _ = target;
    exe.addIncludePath("src/libs/glad/");
    exe.addCSourceFiles(&[_][]const u8{"src/libs/glad/glad.c"}, &[_][]const u8{"-std=c99"});
}

fn linkGlfw(exe: *std.build.LibExeObjStep, target: std.zig.CrossTarget) void {
    if (target.isWindows()) {
        exe.addObjectFile(if (target.getAbi() == .msvc) "libs/Zig-ImGui/examples/lib/win/glfw3.lib" else "libs/Zig-ImGui/examples/lib/win/libglfw3.a");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("shell32");
    } else {
        exe.linkSystemLibrary("glfw");
    }
}

fn linkJira(exe: *std.build.LibExeObjStep, target: std.zig.CrossTarget) void {
    _ = target;
    exe.addPackagePath("jira", "libs/jira-client/jira-client.zig");
    exe.linkSystemLibrary("curl");
}
