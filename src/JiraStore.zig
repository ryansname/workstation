const assert = std.debug.assert;
const builtin = @import("builtin");
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const jira = @import("jira-client");
const json = std.json;
const log = std.log;
const mem = std.mem;
const process = std.process;
const std = @import("std");
const gui = @import("gui.zig");
const worker = @import("worker.zig");

const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMapUnmanaged;

const JiraStore = @This();

allocator: Allocator,

url_root: []const u8,
client: jira.Client,
worker: worker.Worker(JiraWork, JiraWorkContext, &processJiraWork),

issues: StringHashMap(StoredIssue),

const IssueBean = json.ValueTree;

const StoredIssue = union(enum) {
    fetching: void,
    failed: []const u8,
    data: IssueBean,

    fn deinit(self: *StoredIssue, allocator: Allocator) void {
        _ = allocator;
        switch (self.*) {
            .data => |*d| d.deinit(),
            else => {},
        }
    }
};

const JiraWorkContext = struct {
    client: *jira.Client,
};

const JiraWork = struct {
    allocator: Allocator,

    work_type: union(enum) {
        fetch_issue: worker.CreateWorkType([]const u8, StoredIssue),
    },
};

pub fn init(allocator: Allocator, url_root_in: []const u8) !JiraStore {
    const url_root = try allocator.dupe(u8, url_root_in);
    var store = JiraStore{
        .allocator = allocator,
        .url_root = url_root,
        .client = try jira.Client.init(url_root),
        .worker = .{ .allocator = allocator },
        .issues = StringHashMap(StoredIssue){},
    };
    errdefer store.deinit();

    return store;
}

pub fn deinit(store: *JiraStore) void {
    store.allocator.free(store.url_root);
    store.worker.deinit();

    store.client.deinit(store.allocator);

    var iterator = store.issues.iterator();
    while (iterator.next()) |entry| {
        log.info("Deinit @ {*}: {s}", .{ entry.key_ptr.*, entry.key_ptr.* });
        store.allocator.free(entry.key_ptr.*);
        entry.value_ptr.deinit(store.allocator);
    }
    store.issues.deinit(store.allocator);
}

pub fn start_worker(store: *JiraStore) !void {
    _ = try store.worker.start_worker(.{ .client = &store.client });
}

pub fn authorize(store: *JiraStore, username: []const u8, password: []const u8) !void {
    try store.client.authorize(store.allocator, username, password);
}

pub fn processBackgroundWork(store: *JiraStore) void {
    while (store.worker.poll()) |work_item| switch (work_item.work_type) {
        .fetch_issue => |issue| store.issues.putAssumeCapacity(issue.request, issue.response.?),
    };
}

pub fn requestIssue(store: *JiraStore, key: []const u8) StoredIssue {
    store.issues.ensureUnusedCapacity(store.allocator, 1) catch return .{ .failed = "Failed to allocate storage" };
    const issue_key = store.allocator.dupe(u8, key) catch return .{ .failed = "Failed to allocate storage" };

    var map_entry = store.issues.getOrPutAssumeCapacity(issue_key);
    var location: *StoredIssue = map_entry.value_ptr;

    if (map_entry.found_existing) {
        store.allocator.free(issue_key);
        return location.*;
    }

    log.info("Alloc @ {*}: {s}", .{ map_entry.key_ptr.*, map_entry.key_ptr.* });

    const result: StoredIssue = .{ .fetching = {} };
    location.* = result;

    store.worker.submit(.{
        .allocator = store.allocator,
        .work_type = .{
            .fetch_issue = .{
                .request = map_entry.key_ptr.*,
            },
        },
    }) catch return .{ .failed = "Failed to submit issue to worker" };

    return result;
}

fn processJiraWork(arena: heap.ArenaAllocator, context: JiraWorkContext, work: *JiraWork) void {
    _ = arena;
    switch (work.*.work_type) {
        .fetch_issue => |*fetch_issue| {
            const issue = jira.getIssue(context.client.*, work.allocator, fetch_issue.request) catch |err| {
                fetch_issue.response = .{ .failed = @errorName(err) };
                return;
            };

            log.warn("Request for {s} = {any}", .{ fetch_issue.request, issue });
            fetch_issue.response = switch (issue) {
                .unspecified => |res| blk: {
                    log.warn("Unspecified error for request: {} - {s}", .{ res.status_code, res.body });
                    break :blk .{ .failed = "Unspecified error code" };
                },
                ._200 => |res| .{ .data = res },
                else => .{ .failed = @tagName(issue) },
            };
        },
    }
}
