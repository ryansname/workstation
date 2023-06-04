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
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .free = free,
        },
    };
}

fn alloc(
    ctx: *anyopaque,
    len: usize,
    log2_ptr_align: u8,
    ret_addr: usize,
) ?[*]u8 {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ctx));

    const result = self.parent_allocator.rawAlloc(len, log2_ptr_align, ret_addr);
    self.bytes_allocated += if (result != null) len else 0;
    return result;
}

fn resize(
    ctx: *anyopaque,
    buf: []u8,
    log2_buf_align: u8,
    new_len: usize,
    ret_addr: usize,
) bool {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ctx));

    self.bytes_allocated -= buf.len;
    defer self.bytes_allocated += new_len;

    return self.parent_allocator.rawResize(buf, log2_buf_align, new_len, ret_addr);
}

fn free(
    ctx: *anyopaque,
    buf: []u8,
    log2_buf_align: u8,
    ret_addr: usize,
) void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ctx));

    self.bytes_allocated -= buf.len;
    self.parent_allocator.rawFree(buf, log2_buf_align, ret_addr);
}
