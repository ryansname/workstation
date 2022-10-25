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

pub fn Worker(comptime WorkType: type, comptime WorkContext: type, comptime work_fn: *const fn (heap.ArenaAllocator, WorkContext, *WorkType) anyerror!void) type {
    return struct {
        run: bool = true,
        allocator: Allocator,

        semaphore: std.Thread.Semaphore = .{},
        queue: atomic.Queue(WorkType) = atomic.Queue(WorkType).init(),

        const Self = @This();
        const Queue = atomic.Queue(WorkType);
        const Node = Queue.Node;

        pub fn deinit(worker: *Self) void {
            // TODO: deinit the queue;
            worker.run = false;
            worker.semaphore.post();
        }

        pub fn submit(worker: *Self, job: WorkType) !void {
            var node = try worker.allocator.create(Node);
            errdefer worker.allocator.destroy(node);

            node.data = job;
            worker.queue.put(node);
            worker.semaphore.post();
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
                const node = worker.queue.get();
                if (node == null) continue;
                defer worker.allocator.destroy(node.?);

                var arena = heap.ArenaAllocator.init(worker.allocator);
                defer arena.deinit();

                var data = node.?.data;
                log.info("{}", .{data});
                // TODO: worker needs to keep working on error
                _ = work_fn.*(arena, context, &data) catch {};
            }
        }
    };
}
