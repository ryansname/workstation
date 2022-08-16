const builtin = @import("builtin");
const fs = std.fs;
const heap = std.heap;
const log = std.log;
const mem = std.mem;
const std = @import("std");
const gui = @import("gui.zig");

const Arena = std.heap.ArenaAllocator;
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Workstation = @This();

root_allocator: Allocator,

exit_requested: bool = false,

work: std.BoundedArray(Work, 32) = .{},

commit_message: ?[]u8 = null,

default_display: Display,

status: ?[]u8 = null,

pub fn init(alloc: Allocator) !*Workstation {
    var app = try alloc.create(Workstation);
    errdefer alloc.destroy(app);
    app.* = Workstation{
        .root_allocator = alloc,
        .default_display = Display.init(alloc, .{ .branches = .{} }),
    };
    app.work.appendAssumeCapacity(.{ .get_git_status = .{ .request = {}, .response = &app.status } });
    app.work.appendAssumeCapacity(.{ .list_git_branches = .{ .request = {}, .response = &app.default_display.data.branches.branches_list } });
    return app;
}

pub fn deinit(app: *Workstation) void {
    if (app.commit_message) |commit_message| app.root_allocator.free(commit_message);

    if (app.status) |status| app.root_allocator.free(status);

    if (app.default_display.data.branches.branches_list) |branches| {
        for (branches) |branch| app.root_allocator.free(branch);
        app.root_allocator.free(branches);
    }

    const alloc = app.root_allocator;
    app.* = undefined;
    alloc.destroy(app);
}

fn WorkType(comptime req: type, comptime res: type) type {
    return struct {
        request: req,
        response: *res,
    };
}

const Work = union(enum) {
    get_git_status: WorkType(void, ?[]u8),
    list_git_log: WorkType(void, ?[][:0]u8),
    get_git_commit: WorkType([]u8, ?[]u8),
    list_git_branches: WorkType(void, ?[][]u8),
};

pub fn processBackgroundWork(app: *Workstation) !void {
    if (app.work.popOrNull()) |*work| switch (work.*) {
        .get_git_status => |*get_git_status| {
            get_git_status.response.* = try exec(app.root_allocator, &.{ "git", "status", "--porcelain" }, .{});
        },
        .list_git_log => |*list_git_log| {
            var raw_log = try exec(app.root_allocator, &.{ "git", "rev-list", "--all" }, .{});
            defer app.root_allocator.free(raw_log);

            const line_count = mem.count(u8, raw_log, "\n");
            var linesZ = try ArrayList([:0]u8).initCapacity(app.root_allocator, line_count);
            errdefer {
                for (linesZ.items) |item| app.root_allocator.free(item);
                linesZ.deinit(app.root_allocator);
            }

            var log_iter = mem.tokenize(u8, raw_log, "\n");
            while (log_iter.next()) |line| {
                const lineZ = try app.root_allocator.dupeZ(u8, line);
                errdefer app.root_allocator.free(lineZ);

                linesZ.appendAssumeCapacity(lineZ);
            }
            const slice = linesZ.toOwnedSlice(app.root_allocator);
            list_git_log.response.* = slice;
        },
        .get_git_commit => |*get_git_commit| {
            const hash = get_git_commit.request;
            const raw_message = try exec(app.root_allocator, &.{ "git", "rev-list", "--format=%B", "--max-count=1", hash }, .{});
            if (get_git_commit.response.*) |msg| {
                app.root_allocator.free(msg);
            }
            get_git_commit.response.* = raw_message;
        },
        .list_git_branches => |*list_git_branches| {
            var raw_branches = try exec(app.root_allocator, &.{ "git", "for-each-ref", "refs/heads/" }, .{});
            defer app.root_allocator.free(raw_branches);

            const line_count = mem.count(u8, raw_branches, "\n");
            var lines = try ArrayList([]u8).initCapacity(app.root_allocator, line_count);
            errdefer {
                for (lines.items) |item| app.root_allocator.free(item);
                lines.deinit(app.root_allocator);
            }

            var branch_iter = mem.tokenize(u8, raw_branches, "\n");
            while (branch_iter.next()) |branch| {
                lines.appendAssumeCapacity(try app.root_allocator.dupe(u8, branch));
            }

            const slice = lines.toOwnedSlice(app.root_allocator);
            list_git_branches.response.* = slice;
        },
    };
}

const Display = struct {
    arena: Arena,
    expanded: bool = true,
    child: ?*Display = null,

    data: union(enum) {
        branches: struct {
            branches_list: ?[][]u8 = null,
            selected_branch_index: ?usize = null,
        },
        commits: struct {
            logs: ?[][:0]u8 = null,
            selected_commit_index: ?usize = null,
        },
    },

    fn init(alloc: Allocator, data: anytype) Display {
        return Display{
            .arena = Arena.init(alloc),
            .data = data,
        };
    }

    fn render(this: *Display, app: *Workstation) Allocator.Error!void {
        const alloc = this.arena.allocator();
        if (gui.CollapsingHeader_BoolPtr(@tagName(this.data), &this.expanded)) {
            switch (this.data) {
                .branches => |*branches| {
                    if (branches.branches_list == null) {
                        gui.Text2(gui.printZ("Loading", .{}));
                        return;
                    }
                    const branches_list = branches.branches_list.?;

                    if (branches.selected_branch_index) |branch_index| {
                        gui.Text2(branches_list[branch_index]);
                    }
                    for (branches_list) |branch, i| {
                        const is_selected = branches.selected_branch_index == i;
                        const selected = gui.Selectable2(branch, is_selected, .{});
                        if (selected) {
                            branches.selected_branch_index = i;
                            var child = try alloc.create(Display);
                            child.* = Display.init(alloc, .{ .commits = .{} });
                            this.child = child;
                            var commits = &child.data.commits;
                            app.work.appendAssumeCapacity(.{ .list_git_log = .{ .request = {}, .response = &commits.logs } });
                        }
                    }
                },
                .commits => |*commits| {
                    if (commits.logs) |logs| {
                        for (logs) |line, i| {
                            const is_selected = commits.selected_commit_index == i;
                            const selected = gui.Selectable_BoolExt(line, is_selected, .{}, .{ .x = 0, .y = 0 });
                            if (selected) {
                                commits.selected_commit_index = i;
                                // try app.work.append(.{ .get_git_commit = .{ .request = mem.sliceTo(line, ' '), .response = &app.commit_message } });
                            }
                        }
                    }
                    gui.Text2(gui.printZ("TODO", .{}));
                },
            }
        }
        if (this.child) |child| try child.render(app);
    }
};

pub fn render(app: *Workstation) !void {
    if (gui.IsKeyPressed(.Q)) {
        app.exit_requested = true;
        return;
    }

    var view_open = true;
    var visible = gui.BeginExt("Branches", &view_open, .{});
    defer gui.End();
    if (!visible) return;

    try app.default_display.render(app);
}

fn exec(alloc: Allocator, cmd: []const []const u8, args: struct {
    dir: ?fs.Dir = null,
}) ![:0]u8 {
    var exec_result = try std.ChildProcess.exec(.{
        .allocator = alloc,
        .argv = cmd,
        .cwd_dir = args.dir,
        .max_output_bytes = 50 * 1024 * 1025,
    });
    errdefer alloc.free(exec_result.stdout);
    defer alloc.free(exec_result.stderr);

    if (exec_result.term != .Exited and exec_result.term.Exited != 0) {
        log.warn("Exec failed: {}", .{exec_result.term});
    }
    if (exec_result.stderr.len > 0) {
        log.warn("{s} (errer): {s}", .{ cmd[0], exec_result.stderr });
    }

    if (builtin.mode == .Debug) {
        defer alloc.free(exec_result.stdout);
        return alloc.dupeZ(u8, exec_result.stdout);
    } else {
        return exec_result.stdout;
    }
}
