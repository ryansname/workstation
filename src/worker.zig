const atomic = std.atomic;
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

pub fn CreateWorkType(comptime RequestType: type, comptime ResponseType: type) type {
    return struct {
        request: RequestType,
        response: ?ResponseType = null,
    };
}

pub fn Worker(comptime WorkType: type, comptime WorkContext: type, comptime work_fn: *const fn (heap.ArenaAllocator, WorkContext, *WorkType) void) type {
    return struct {
        run: bool = true,
        allocator: Allocator,

        semaphore: std.Thread.Semaphore = .{},
        submissions: atomic.Queue(WorkType) = atomic.Queue(WorkType).init(),
        results: atomic.Queue(WorkType) = atomic.Queue(WorkType).init(),

        const Self = @This();
        const Queue = atomic.Queue(WorkType);
        const Node = Queue.Node;

        pub fn deinit(worker: *Self) void {
            worker.run = false;

            while (worker.submissions.get()) |node| {
                worker.allocator.destroy(node);
            }
            while (worker.results.get()) |node| {
                worker.allocator.destroy(node);
            }

            worker.semaphore.post();
        }

        pub fn submit(worker: *Self, job: WorkType) !void {
            var node = try worker.allocator.create(Node);
            errdefer worker.allocator.destroy(node);

            node.data = job;
            worker.submissions.put(node);
            worker.semaphore.post();
        }

        pub fn poll(worker: *Self) ?WorkType {
            const node = worker.results.get();
            if (node == null) return null;
            defer worker.allocator.destroy(node.?);

            const result = node.?.data;
            return result;
        }

        pub fn start_worker(worker: *Self, context: WorkContext) !void {
            var new_thread = try std.Thread.spawn(.{}, Self.thread_start, .{ worker, context });
            _ = new_thread;
        }

        fn thread_start(worker: *Self, context: WorkContext) void {
            log.info("Worker started", .{});
            defer worker.deinit();

            while (worker.run) {
                worker.semaphore.wait();
                if (!worker.run) continue;
                const node = worker.submissions.get();
                if (node == null) continue;

                var arena = heap.ArenaAllocator.init(worker.allocator);
                defer arena.deinit();

                var data = &node.?.data;
                work_fn.*(arena, context, data);

                worker.results.put(node.?);
            }
        }
    };
}
