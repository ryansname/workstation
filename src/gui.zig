const log = std.log;
const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const imgui = @import("imgui");

pub usingnamespace imgui;

pub fn Text2(text: anytype) void {
    const text_start: [*]const u8 = text.ptr;
    const text_end: [*]const u8 = text.ptr + text.len;
    imgui.TextUnformattedExt(text_start, text_end);
}

var tmp_allocator_instance: ScratchAllocator = undefined;
pub var tmp_allocator: Allocator = undefined;

pub fn scratch() Allocator {
    return tmp_allocator;
}

pub fn dupeZ(in: []const u8) [:0]const u8 {
    return scratch().dupeZ(u8, in) catch unreachable;
}

pub fn printZ(comptime fmt: []const u8, args: anytype) [:0]const u8 {
    return std.fmt.allocPrintZ(scratch(), fmt, args) catch unreachable;
}

pub fn tempBuffer(comptime T: type, count: usize) []T {
    return scratch().alloc(T, count) catch unreachable;
}

pub fn initTmpAllocator(allocator: Allocator) !void {
    tmp_allocator_instance = try ScratchAllocator.init(allocator);
    tmp_allocator = tmp_allocator_instance.allocator();
}

pub fn deinitTmpAllocator(allocator: Allocator) void {
    allocator.free(tmp_allocator_instance.buffer);
}

const ScratchAllocator = struct {
    backup_allocator: Allocator,
    end_index: usize,
    buffer: []u8,

    pub fn init(backup_allocator: Allocator) !ScratchAllocator {
        const scratch_buffer = try backup_allocator.alloc(u8, 2 * 1024 * 1024);

        return ScratchAllocator{
            .backup_allocator = backup_allocator,
            .buffer = scratch_buffer,
            .end_index = 0,
        };
    }

    pub fn allocator(self: *ScratchAllocator) Allocator {
        return Allocator.init(
            self,
            alloc,
            Allocator.NoResize(ScratchAllocator).noResize,
            Allocator.NoOpFree(ScratchAllocator).noOpFree,
        );
    }

    fn alloc(self: *ScratchAllocator, n: usize, ptr_align: u29, len_align: u29, ret_addr: usize) ![]u8 {
        const addr = @ptrToInt(self.buffer.ptr) + self.end_index;
        const adjusted_addr = mem.alignForward(addr, ptr_align);
        const adjusted_index = self.end_index + (adjusted_addr - addr);
        const new_end_index = adjusted_index + n;

        if (new_end_index > self.buffer.len) {
            // if more memory is requested then we have in our buffer leak like a sieve!
            if (n > self.buffer.len) {
                log.warn("\n---------\nwarning: tmp allocated more than is in our temp allocator. This memory WILL leak!\n--------\n", .{});
                return self.backup_allocator.vtable.alloc(self, n, ptr_align, len_align, ret_addr);
            }

            const result = self.buffer[0..n];
            self.end_index = n;
            return result;
        }
        const result = self.buffer[adjusted_index..new_end_index];
        self.end_index = new_end_index;

        return result;
    }
};