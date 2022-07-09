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

    const impl_glfw = .{ .name = "imgui_impl_glfw", .source = std.build.FileSource.relative("libs/Zig-ImGui/examples/imgui_impl_glfw.zig"), .dependencies = &.{imgui.pkg} };
    const impl_opengl = .{ .name = "imgui_impl_opengl3", .source = std.build.FileSource.relative("libs/Zig-ImGui/examples/imgui_impl_opengl3.zig"), .dependencies = &.{imgui.pkg} };
    exe.addPackage(impl_glfw);
    exe.addPackage(impl_opengl);
    exe.addPackagePath("gl", "libs/Zig-ImGui/examples/include/gl.zig");
    exe.addPackagePath("glfw", "libs/Zig-ImGui/examples/include/glfw.zig");
    exe.addSystemIncludePath("libs/Zig-ImGui/examples/include/c_include/");

    linkGlad(exe, target);
    linkGlfw(exe, target);

    exe.addLibPath("/opt/homebrew/lib/");
    exe.addIncludeDir("/opt/homebrew/include/");
}

fn linkGlad(exe: *std.build.LibExeObjStep, target: std.zig.CrossTarget) void {
    _ = target;
    exe.addIncludeDir("libs/Zig-ImGui/examples/include/c_include");
    exe.addCSourceFile("libs/Zig-ImGui/examples/c_src/glad.c", &[_][]const u8{"-std=c99"});
    //exe.linkSystemLibrary("opengl");
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
