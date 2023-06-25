const ADF = @import("AtlassianDocumentFormat.zig");
const builtin = @import("builtin");
const fs = std.fs;
const heap = std.heap;
const jira = @import("jira");
const log = std.log;
const mem = std.mem;
const process = std.process;
const std = @import("std");
const gui = @import("gui.zig");
const worker = @import("worker.zig");

const Arena = std.heap.ArenaAllocator;
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const JiraStore = @import("JiraStore.zig");
const RecordingAllocator = @import("RecordingAllocator.zig");

const Workstation = @This();

recording_allocator: RecordingAllocator,
root_allocator: Allocator,

jira_store: JiraStore,

debug_open: bool = true,
exit_requested: bool = false,

work: std.BoundedArray(Work, 32) = .{},

default_display: ?Display = null,

visible_tickets: ArrayList([]const u8) = .{},
buf: [64]u8 = [_]u8{0} ** 64,

mono_13: *gui.Font = undefined,
mono_20: *gui.Font = undefined,

pub fn init(input_allocator: Allocator) !*Workstation {
    var app = try input_allocator.create(Workstation);
    errdefer input_allocator.destroy(app);

    app.* = Workstation{
        .recording_allocator = RecordingAllocator.init(input_allocator),
        .root_allocator = app.recording_allocator.allocator(),
        .jira_store = undefined,
    };
    const alloc = app.root_allocator;

    try app.visible_tickets.append(alloc, try alloc.dupe(u8, "DAVE-1"));

    app.default_display = Display.init(alloc, "Branches", .{ .branches = .{} });

    const url_root = try process.getEnvVarOwned(alloc, "WORKSTATION_URL_ROOT");
    defer alloc.free(url_root);

    app.jira_store = try JiraStore.init(app.root_allocator, url_root);
    errdefer app.jira_store.deinit();

    if (process.getEnvVarOwned(alloc, "WORKSTATION_USERNAME")) |username| {
        defer alloc.free(username);
        if (process.getEnvVarOwned(alloc, "WORKSTATION_PASSWORD")) |password| {
            defer alloc.free(password);
            try app.jira_store.authorize(username, password);
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

    app.work.appendAssumeCapacity(.{
        .allocator = app.default_display.?.arena.allocator(),
        .work_type = .{
            .list_git_branches = .{
                .request = {},
                .response = &app.default_display.?.data.branches.branches_list,
            },
        },
    });

    return app;
}

pub fn deinit(app: *Workstation, input_allocator: Allocator) void {
    if (app.default_display) |d| d.deinit();
    app.jira_store.deinit();

    for (app.visible_tickets.items) |item| app.root_allocator.free(item);
    app.visible_tickets.deinit(app.root_allocator);

    input_allocator.destroy(app);
}

pub fn start_workers(app: *Workstation) !void {
    try app.jira_store.start_worker();
}

pub fn WorkType(comptime req: type, comptime res: type) type {
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
    },
};

pub fn processBackgroundWork(app: *Workstation) !void {
    app.jira_store.processBackgroundWork();
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
                const slice = try linesZ.toOwnedSlice(alloc);
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

                const slice = try lines.toOwnedSlice(alloc);
                list_git_branches.response.* = slice;
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
                    for (branches_list, 0..) |branch, i| {
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
                        for (logs, 0..) |line, i| {
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

fn jsonGet(root: std.json.Value, comptime path: []const u8) ?std.json.Value {
    var here = root;
    comptime var start = 0;
    inline for (path, 0..) |c, i| switch (c) {
        '.' => {
            var itemPath = path[start..i];
            here = here.object.get(itemPath).?;
            start = i + 1;
        },
        else => {},
    };
    return here.object.get(path[start..]);
}

fn renderAdf(app: Workstation, node: ADF.Node) void {
    if (ADF.isInline(node)) {
        gui.SameLine();
    }
    switch (node) {
        .blockquote => |quote| {
            for (quote.content.items) |i| {
                gui.Text2("> ");
                gui.SameLine();
                renderAdf(app, i);
            }
        },
        .bulletList => |list| {
            gui.Indent(); //TODO: It'd be nicer to not indent the first bullets
            defer gui.Unindent();
            for (list.content.items) |li| {
                gui.Bullet();
                renderAdf(app, li);
            }
        },
        .codeBlock => |code_block| {
            gui.Indent();
            defer gui.Unindent();

            gui.NewLine();
            for (code_block.content.items) |i| renderAdf(app, i);
        },
        .doc => |doc| for (doc.content.items) |i| renderAdf(app, i),
        .emoji => |emoji| {
            gui.Text2(emoji.text orelse emoji.short_name);
        },
        .expand => |expand| {
            if (gui.CollapsingHeader_BoolPtr(gui.dupeZ(expand.title orelse ""), null)) {
                for (expand.content.items) |i| renderAdf(app, i);
            }
        },
        .hardBreak => gui.Text2(""),
        .heading => |heading| if (heading.content) |content| {
            gui.PushFont(app.mono_20);
            defer gui.PopFont();

            gui.TextFmt("h{}", .{heading.level});
            if (content.items.len > 0) gui.SameLine(); // TODO: This feels terrible
            for (content.items) |i| renderAdf(app, i);
        },
        .inlineCard => |card| {
            // TODO: this is terrible :(, each card will need to be special cased
            switch (card.url_or_data) {
                .url => |url| gui.Text2(url),
                .data => gui.Text2("Unsupported data card."),
            }
        },
        .listItem => |li| for (li.content.items) |i| renderAdf(app, i),
        .media => gui.Text2("There's some media here"),
        .mediaGroup => |group| for (group.content.items) |i| renderAdf(app, i),
        .mediaSingle => gui.Text2("There's some media here"),
        .mention => |mention| {
            gui.Text2(mention.text orelse mention.id);
        },
        .orderedList => |list| {
            gui.Indent(); //TODO: It'd be nicer to not indent the first bullets
            defer gui.Unindent();
            for (list.content.items, 1..) |li, i| {
                gui.TextFmt("{}.", .{i});
                gui.SameLine();
                renderAdf(app, li);
            }
        },
        .panel => |panel| {
            gui.PushStyleVar_Vec2(gui.StyleVar.CellPadding, .{ .x = 5, .y = 5 });
            defer gui.PopStyleVar();

            if (gui.BeginTableExt("panel", 1, .{}, .{}, 0)) {
                defer gui.EndTable();

                gui.TableNextRow();
                _ = gui.TableNextColumn();

                const color: gui.Vec4 = switch (panel.panel_type) {
                    .info => gui.COLOR_INFO,
                    .note => gui.COLOR_NOTE,
                    .warning => gui.COLOR_WARNING,
                    .success => gui.COLOR_SUCCESS,
                    .@"error" => gui.COLOR_ERROR,
                };
                gui.TableSetBgColor(gui.TableBgTarget.RowBg0, gui.GetColorU32_Vec4(color));

                gui.Indent();
                defer gui.Unindent();

                for (panel.content.items) |i| renderAdf(app, i);
            }
        },
        .paragraph => |paragraph| {
            gui.NewLine();
            if (paragraph.content) |content| for (content.items) |i| renderAdf(app, i);
        },
        .rule => gui.Separator(),
        .status => |status| gui.TextFmt("<{[color]s}>{[text]s}</{[color]s}>", .{ .color = @tagName(status.color), .text = status.text }),
        .table => @panic("This tag is not supported!"),
        .tableCell => @panic("This tag is not supported!"),
        .tableHeader => @panic("This tag is not supported!"),
        .tableRow => @panic("This tag is not supported!"),
        .text => |text| gui.Text2(text.text), // TODO: text.marks
    }
}

pub fn render(app: *Workstation, io: gui.IO) !void {
    if (!io.WantTextInput and gui.IsKeyPressed(.Q)) {
        app.exit_requested = true;
        return;
    }

    var branches_open = true;
    var visible = gui.BeginExt("Branches", &branches_open, .{});
    if (visible) {
        if (app.default_display) |*d| try d.render(app);
    }
    gui.End();

    var view_open_2 = true;
    var visible_2 = gui.BeginExt("Issue", &view_open_2, .{});
    if (visible_2) {
        _ = gui.InputText("Issue Key", &app.buf, app.buf.len);
        const ticket_id = mem.sliceTo(&app.buf, 0);

        const changed = gui.IsItemDeactivatedAfterEdit();
        if (changed) {
            try app.visible_tickets.append(
                app.root_allocator,
                try app.root_allocator.dupe(u8, ticket_id),
            );
        }
    }
    gui.End();

    for (app.visible_tickets.items) |*ticket_id| {
        if (ticket_id.len == 0) continue; // TODO: This index is leaked...

        var view_open = true;
        var visible_3 = gui.BeginExt(gui.printZ("Issue: {s}", .{ticket_id.*}), &view_open, .{});
        if (visible_3) {
            const issue_state = app.jira_store.requestIssue(ticket_id.*);
            switch (issue_state) {
                .fetching => gui.Text2("Fetching"),
                .data => |issue| blk: {
                    gui.Text2(gui.printZ("{s}", .{jsonGet(issue.root, "fields.summary").?.string}));
                    const description_root = jsonGet(issue.root, "fields.description").?;
                    var description = (ADF.inflate(app.root_allocator, description_root) catch |err| {
                        gui.Text2(gui.printZ("Error occurred: {s}", .{@errorName(err)}));
                        if (gui.Button("Crash due to error")) {
                            return err;
                        }
                        break :blk;
                    }) orelse break :blk;
                    defer description.deinit();
                    renderAdf(app.*, description.root);
                },
                .failed => |reason| gui.Text2(reason),
            }
        }

        if (!view_open) {
            app.root_allocator.free(ticket_id.*);
            ticket_id.* = "";
        }
        gui.End();
    }

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
