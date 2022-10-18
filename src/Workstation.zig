const builtin = @import("builtin");
const fs = std.fs;
const heap = std.heap;
const jira = @import("jira");
const log = std.log;
const mem = std.mem;
const process = std.process;
const std = @import("std");
const gui = @import("gui.zig");

const Arena = std.heap.ArenaAllocator;
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const RecordingAllocator = @import("RecordingAllocator.zig");

const Workstation = @This();

recording_allocator: RecordingAllocator,
root_allocator: Allocator,

client: jira.Client,

debug_open: bool = true,
exit_requested: bool = false,

work: std.BoundedArray(Work, 32) = .{},

default_display: ?Display = null,

issue: JiraIssue = .{ .fetching = {} },

const JiraIssue = union(enum) {
    fetching: void,
    data: jira.IssueBean,
};

pub fn init(input_allocator: Allocator) !*Workstation {
    var app = try input_allocator.create(Workstation);
    errdefer input_allocator.destroy(app);

    app.* = Workstation{
        .recording_allocator = RecordingAllocator.init(input_allocator),
        .root_allocator = app.recording_allocator.allocator(),
        .client = undefined,
    };

    const alloc = app.root_allocator;
    app.default_display = Display.init(alloc, "Branches", .{ .branches = .{} });

    app.client = try jira.Client.init("https://jira.com");
    if (process.getEnvVarOwned(alloc, "WORKSTATION_USERNAME")) |username| {
        defer alloc.free(username);
        if (process.getEnvVarOwned(alloc, "WORKSTATION_PASSWORD")) |password| {
            defer alloc.free(password);
            try app.client.authorize(alloc, username, password);
        } else |err| {
            if (err == error.EnvironmentVariableNotFound) {} else {
                return err;
            }
        }
    } else |err| {
        if (err == error.EnvironmentVariableNotFound) {} else {
            return err;
        }
    }
    errdefer app.client.deinit(alloc);

    app.work.appendAssumeCapacity(.{
        .allocator = app.default_display.?.arena.allocator(),
        .work_type = .{
            .list_git_branches = .{
                .request = {},
                .response = &app.default_display.?.data.branches.branches_list,
            },
        },
    });

    app.work.appendAssumeCapacity(.{
        .allocator = app.root_allocator,
        .work_type = .{
            .fetch_issue = .{
                .request = "DAVE-1",
                .response = &app.issue,
            },
        },
    });
    return app;
}

pub fn deinit(app: *Workstation, input_allocator: Allocator) void {
    if (app.default_display) |d| d.deinit();
    if (app.issue == .data) app.issue.data.deinit(input_allocator);
    app.client.deinit(app.root_allocator);

    input_allocator.destroy(app);
}

fn WorkType(comptime req: type, comptime res: type) type {
    return struct {
        request: req,
        response: *res,
    };
}

const Work = struct {
    allocator: Allocator,
    work_type: union(enum) {
        get_git_status: WorkType(void, ?[]u8),
        list_git_log: WorkType(void, ?[][:0]u8),
        get_git_commit: WorkType([]u8, ?[]u8),
        list_git_branches: WorkType(void, ?[][]u8),
        fetch_issue: WorkType([]const u8, JiraIssue),
    },
};

pub fn processBackgroundWork(app: *Workstation) !void {
    if (app.work.popOrNull()) |*work| {
        const alloc = work.allocator;
        switch (work.*.work_type) {
            .get_git_status => |*get_git_status| {
                get_git_status.response.* = try exec(alloc, &.{ "git", "status", "--porcelain" }, .{});
            },
            .list_git_log => |*list_git_log| {
                var raw_log = try exec(alloc, &.{ "git", "rev-list", "--all" }, .{});
                defer alloc.free(raw_log);

                const line_count = mem.count(u8, raw_log, "\n");
                var linesZ = try ArrayList([:0]u8).initCapacity(alloc, line_count);
                errdefer {
                    for (linesZ.items) |item| alloc.free(item);
                    linesZ.deinit(alloc);
                }

                var log_iter = mem.tokenize(u8, raw_log, "\n");
                while (log_iter.next()) |line| {
                    const lineZ = try alloc.dupeZ(u8, line);
                    errdefer alloc.free(lineZ);

                    linesZ.appendAssumeCapacity(lineZ);
                }
                const slice = linesZ.toOwnedSlice(alloc);
                list_git_log.response.* = slice;
            },
            .get_git_commit => |*get_git_commit| {
                const hash = get_git_commit.request;
                const raw_message = try exec(alloc, &.{ "git", "rev-list", "--format=%B", "--max-count=1", hash }, .{});
                if (get_git_commit.response.*) |msg| {
                    alloc.free(msg);
                }
                get_git_commit.response.* = raw_message;
            },
            .list_git_branches => |*list_git_branches| {
                var raw_branches = try exec(alloc, &.{ "git", "for-each-ref", "refs/heads/" }, .{});
                defer alloc.free(raw_branches);

                const line_count = mem.count(u8, raw_branches, "\n");
                var lines = try ArrayList([]u8).initCapacity(alloc, line_count);
                errdefer {
                    for (lines.items) |item| alloc.free(item);
                    lines.deinit(alloc);
                }

                var branch_iter = mem.tokenize(u8, raw_branches, "\n");
                while (branch_iter.next()) |branch| {
                    lines.appendAssumeCapacity(try alloc.dupe(u8, branch));
                }

                const slice = lines.toOwnedSlice(alloc);
                list_git_branches.response.* = slice;
            },
            .fetch_issue => |*fetch_issue| {
                const issue = try jira.getIssue(app.client, alloc, fetch_issue.request);
                log.warn("Summary: {s}", .{issue._200.fields.summary});
                fetch_issue.response.* = .{ .data = issue._200 };
            },
        }
    }
}

const Display = struct {
    arena: Arena,
    header: []const u8,

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
        commit: struct {
            message: ?[]u8 = null,
        },
    },

    fn init(alloc: Allocator, header: []const u8, data: anytype) Display {
        return Display{
            .arena = Arena.init(alloc),
            .header = header,
            .data = data,
        };
    }

    fn deinit(self: Display) void {
        self.arena.deinit();
    }

    fn initNewChild(self: *Display, header: []const u8, new_child: anytype) Allocator.Error!*Display {
        const alloc = self.arena.allocator();
        if (self.child == null) {
            self.child = try alloc.create(Display);
        } else {
            self.child.?.deinit();
        }

        self.child.?.* = Display.init(alloc, header, new_child);
        return self.child.?;
    }

    fn render(this: *Display, app: *Workstation) Allocator.Error!void {
        gui.SetNextItemOpen(this.expanded);
        this.expanded = gui.CollapsingHeader_TreeNodeFlags(gui.printZ("{s}###{s}", .{ this.header, @tagName(this.data) }));
        if (this.expanded) {
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
                            const child = try this.initNewChild(branch, .{ .commits = .{} });
                            var commits = &child.data.commits;
                            app.work.appendAssumeCapacity(.{
                                .allocator = child.arena.allocator(),
                                .work_type = .{ .list_git_log = .{ .request = {}, .response = &commits.logs } },
                            });
                            this.expanded = false;
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
                                const child = try this.initNewChild(line, .{ .commit = .{} });
                                var commit = &child.data.commit;
                                app.work.appendAssumeCapacity(.{
                                    .allocator = child.arena.allocator(),
                                    .work_type = .{ .get_git_commit = .{ .request = mem.sliceTo(line, ' '), .response = &commit.message } },
                                });
                                this.expanded = false;
                            }
                        }
                    }
                },
                .commit => |*commit| {
                    if (commit.message) |message| {
                        gui.Text2(message);
                    }
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
    if (visible) {
        if (app.default_display) |*d| try d.render(app);
    }
    gui.End();

    var view_open_2 = true;
    var visible_2 = gui.BeginExt("Issue", &view_open_2, .{});
    if (visible_2) {
        switch (app.issue) {
            .fetching => gui.Text2(gui.printZ("{}", .{app.issue.fetching})),
            .data => |issue| gui.Text2(gui.printZ("{s}", .{issue.fields.summary})),
        }
    }
    gui.End();

    visible = gui.BeginExt("Debug", &app.debug_open, .{});
    if (visible) {
        gui.TextFmt("Memory: {}", .{app.recording_allocator.bytes_allocated});
    }
    gui.End();
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
