const assert = std.debug.assert;
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

const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const WorkType = @import("workstation.zig").WorkType;

const JiraStore = @This();

allocator: Allocator,

client: jira.Client,
worker: worker.Worker(JiraWork, JiraWorkContext, &processJiraWork),

issue_1: ?StoredIssue = null,
issue_2: ?StoredIssue = null,

const StoredIssue = union(enum) {
    fetching: void,
    failed: []const u8,
    data: jira.IssueBean,
};

const JiraWorkContext = struct {
    client: *jira.Client,
};

const JiraWork = struct {
    allocator: Allocator,

    work_type: union(enum) {
        fetch_issue: WorkType([]const u8, ?StoredIssue),
    },
};

pub fn init(allocator: Allocator) !JiraStore {
    var store = JiraStore{
        .allocator = allocator,
        .client = try jira.Client.init("https://jira.com"),
        .worker = .{ .allocator = allocator },
    };
    errdefer store.deinit();

    return store;
}

pub fn deinit(store: *JiraStore) void {
    store.client.deinit(store.allocator);
    store.worker.deinit();

    if (store.issue_1 != null and store.issue_1.? == .data) store.issue_1.?.data.deinit(store.allocator);
    if (store.issue_2 != null and store.issue_2.? == .data) store.issue_2.?.data.deinit(store.allocator);
}

pub fn start_worker(store: *JiraStore) !void {
    _ = try store.worker.start_worker(.{ .client = &store.client });
}

pub fn authorize(store: *JiraStore, username: []const u8, password: []const u8) !void {
    try store.client.authorize(store.allocator, username, password);
}

pub fn requestIssue(store: *JiraStore, key: []const u8) StoredIssue {
    if (key.len < 6) return .{ .failed = "You must enter a key" };

    var location: *?StoredIssue = if (key[5] == '1') &store.issue_1 else &store.issue_2;

    if (location.*) |issue| return issue;

    const request = store.allocator.dupe(u8, key) catch return .{ .failed = "Failed to allocation key" };
    var submitted = false;
    defer if (!submitted) {
        if (location.* == null) location.* = .{ .failed = "Failed to submit for unknown reason" };
        store.allocator.free(request);
    };

    const result: StoredIssue = .{ .fetching = {} };
    location.* = result;

    store.worker.submit(.{
        .allocator = store.allocator,
        .work_type = .{
            .fetch_issue = .{
                .request = request,
                .response = location,
            },
        },
    }) catch return .{ .failed = "Failed to submit issue to worker" };
    submitted = true;

    return result;
}

fn processJiraWork(arena: heap.ArenaAllocator, context: JiraWorkContext, work: *JiraWork) !void {
    _ = arena;
    switch (work.*.work_type) {
        .fetch_issue => |*fetch_issue| {
            defer work.allocator.free(fetch_issue.request);

            const issue = try jira.getIssue(context.client.*, work.allocator, fetch_issue.request);
            errdefer {
                issue.deinit(work.allocator);
                fetch_issue.response.* = .{.failed};
            }

            log.warn("Summary: {s}", .{issue._200.fields.summary});
            fetch_issue.response.* = .{ .data = issue._200 };
        },
    }
}
