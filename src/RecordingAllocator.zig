const std = @import("std");
const Allocator = std.mem.Allocator;

/// This allocator is used in front of another allocator and logs to `std.log`
/// on every call to the allocator.
/// For logging to a `std.io.Writer` see `std.heap.LogToWriterAllocator`
parent_allocator: Allocator,
bytes_allocated: usize = 0,

const Self = @This();

pub fn init(parent_allocator: Allocator) Self {
    return .{
        .parent_allocator = parent_allocator,
    };
}

pub fn allocator(self: *Self) Allocator {
    return Allocator.init(self, alloc, resize, free);
}

fn alloc(
    self: *Self,
    len: usize,
    ptr_align: u29,
    len_align: u29,
    ra: usize,
) error{OutOfMemory}![]u8 {
    const result = try self.parent_allocator.rawAlloc(len, ptr_align, len_align, ra);
    self.bytes_allocated += result.len;
    return result;
}

fn resize(
    self: *Self,
    buf: []u8,
    buf_align: u29,
    new_len: usize,
    len_align: u29,
    ra: usize,
) ?usize {
    if (self.parent_allocator.rawResize(buf, buf_align, new_len, len_align, ra)) |resized_len| {
        self.bytes_allocated -= buf.len;
        self.bytes_allocated += resized_len;
        return resized_len;
    }

    return null;
}

fn free(
    self: *Self,
    buf: []u8,
    buf_align: u29,
    ra: usize,
) void {
    self.parent_allocator.rawFree(buf, buf_align, ra);
    self.bytes_allocated -= buf.len;
}
