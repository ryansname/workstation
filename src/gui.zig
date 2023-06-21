const log = std.log;
const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const imgui = @import("imgui");

pub usingnamespace imgui;

pub inline fn Text2(text: anytype) void {
    imgui.PushTextWrapPos();
    defer imgui.PopTextWrapPos();

    const type_info = @typeInfo(@TypeOf(text));
    if (type_info == .Pointer and @typeInfo(type_info.Pointer.child) == .Array) {
        const text_start: [*]const u8 = &text.*;
        const text_end: [*]const u8 = text_start + text.len;
        imgui.TextUnformattedExt(text_start, text_end);
    } else {
        const text_start: [*]const u8 = text.ptr;
        const text_end: [*]const u8 = text.ptr + text.len;
        imgui.TextUnformattedExt(text_start, text_end);
    }
}

pub inline fn TextFmt(comptime format: []const u8, args: anytype) void {
    const string = printZ(format, args);
    Text2(string);
}

pub inline fn Selectable2(label: []const u8, selected: bool, flags: imgui.SelectableFlags) bool {
    return imgui.Selectable_BoolExt(dupeZ(label), selected, flags, .{ .x = 0, .y = 0 });
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
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = Allocator.noResize,
                .free = Allocator.noFree,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self = @ptrCast(*ScratchAllocator, @alignCast(@alignOf(ScratchAllocator), ctx));
        const addr = @ptrToInt(self.buffer.ptr) + self.end_index;
        const adjusted_addr = mem.alignForwardLog2(addr, log2_ptr_align);
        const adjusted_index = self.end_index + (adjusted_addr - addr);
        const new_end_index = adjusted_index + len;

        if (new_end_index > self.buffer.len) {
            // if more memory is requested then we have in our buffer leak like a sieve!
            if (len > self.buffer.len) {
                log.warn("\n---------\nwarning: tmp allocated more than is in our temp allocator. This memory WILL leak!\n--------\n", .{});
                return self.backup_allocator.vtable.alloc(self, len, log2_ptr_align, ret_addr);
            }

            const result = self.buffer[0..len];
            self.end_index = len;
            return result.ptr;
        }
        const result = self.buffer[adjusted_index..new_end_index];
        self.end_index = new_end_index;

        return result.ptr;
    }
};
