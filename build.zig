const builtin = @import("builtin");
const imgui = @import("libs/Zig-ImGui/zig-imgui/imgui_build.zig");
const std = @import("std");

const Build = std.Build;
const ChildProcess = std.ChildProcess;

const assert = std.debug.assert;

pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    // Workaround weird nix / zig / macos behaviour
    if (builtin.os.tag == .macos and b.env_map.get("NIX_LDFLAGS") != null) {
        b.sysroot = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/";
    }

    const exe = b.addExecutable(.{
        .name = "workstation",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    addDeps(b, exe, target, optimize);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .name = "all-tests",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    addDeps(b, exe_tests, target, optimize);

    imgui.addTestStep(b, "imgui:test", optimize, target);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

fn addDeps(b: *std.Build, exe: *std.build.CompileStep, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) void {
    imgui.prepareAndLink(b, exe);

    linkGlad(exe, target);
    linkGlfw(exe, target);

    const jira_client = b.dependency("jira-client", .{
        .optimize = optimize,
        .target = target,
    });
    exe.addModule("jira-client", jira_client.module("jira-client"));
    exe.linkSystemLibrary("libcurl");
}

fn linkGlad(exe: *std.build.CompileStep, target: std.zig.CrossTarget) void {
    _ = target;
    exe.addIncludePath("src/libs/glad/");
    exe.addCSourceFiles(&[_][]const u8{"src/libs/glad/glad.c"}, &[_][]const u8{"-std=c99"});
}

fn linkGlfw(exe: *std.build.CompileStep, target: std.zig.CrossTarget) void {
    if (target.isWindows()) {
        exe.addObjectFile(if (target.getAbi() == .msvc) "libs/Zig-ImGui/examples/lib/win/glfw3.lib" else "libs/Zig-ImGui/examples/lib/win/libglfw3.a");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("shell32");
    } else {
        exe.linkSystemLibrary("glfw3");
    }
}
