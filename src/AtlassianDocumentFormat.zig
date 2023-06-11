//! https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/

const assert = std.debug.assert;
const mem = std.mem;
const std = @import("std");

const Allocator = mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

const Self = @This();

arena: std.heap.ArenaAllocator,
root: Node,

pub fn inflate(alloc: Allocator, root: std.json.Value) !?Self {
    if (root == .null) return null;

    var arena = std.heap.ArenaAllocator.init(alloc);
    errdefer arena.deinit();

    var root_node = try Node.fromValue(arena.allocator(), root);
    if (root_node != .doc) return error.MalformedNode;

    return Self{ .arena = arena, .root = root_node };
}

pub fn deinit(self: Self) void {
    self.arena.deinit();
}

pub fn basicString(self: *Self) ![]const u8 {
    var buffer = ArrayList(u8){};
    var writer = buffer.writer(self.arena.allocator());
    try basicStringRecurse(writer, self.root, 0);
    return buffer.items;
}

// This is not the best way to do this, but it is *A* way.
fn basicStringRecurse(writer: anytype, node: Node, nest: u32) !void {
    try writer.writeByteNTimes('\t', nest);
    switch (node) {
        .blockquote => {},
        .bulletList => {},
        .codeBlock => {},
        .doc => |doc| {
            try writer.print("Doc - Version: {}\n", .{doc.version});
            for (doc.content.items) |c| try basicStringRecurse(writer, c, nest + 1);
        },
        .emoji => {},
        .hardBreak => {},
        .heading => {},
        .inlineCard => {},
        .listItem => {},
        .media => {},
        .mediaGroup => {},
        .mediaSingle => {},
        .mention => {},
        .orderedList => {},
        .panel => |panel| {
            try writer.print("Panel - {}\n", .{panel.panel_type});
            for (panel.content.items) |c| try basicStringRecurse(writer, c, nest + 1);
        },
        .paragraph => |paragraph| {
            try writer.print("Paragraph\n", .{});
            if (paragraph.content) |pc| for (pc.items) |c| try basicStringRecurse(writer, c, nest + 1);
        },
        .rule => {},
        .table => {},
        .tableCell => {},
        .tableHeader => {},
        .tableRow => {},
        .text => |text| {
            try writer.print("{s}\n", .{text.text});
        },
    }
}

const Node = union(enum) {
    blockquote,
    bulletList,
    codeBlock,
    doc: struct { content: ArrayList(Node), version: i64 },
    emoji,
    hardBreak,
    heading,
    inlineCard,
    listItem,
    media,
    mediaGroup,
    mediaSingle,
    mention,
    orderedList,
    panel: struct { content: ArrayList(Node), panel_type: PanelType },
    paragraph: struct { content: ?ArrayList(Node) },
    rule,
    table,
    tableCell,
    tableHeader,
    tableRow,
    text: struct { text: []const u8, marks: []const Mark },

    fn fromValue(alloc: Allocator, value: std.json.Value) !Node {
        if (value != .object) return error.MalformedNode;
        const value_obj = value.object;
        const ty = value_obj.get("type") orelse return error.MalformedNode;
        if (ty != .string) return error.MalformedNode;

        // var node_type = std.meta.stringToEnum(NodeType, ty.string) orelse return error.MalformedNode;
        var node_type = std.meta.stringToEnum(@typeInfo(Node).Union.tag_type.?, ty.string) orelse return error.MalformedNode;

        switch (node_type) {
            .doc => {
                const raw_content = value_obj.get("content").?.array; // TODO: Safely
                var content = try ArrayList(Node).initCapacity(alloc, raw_content.items.len);
                errdefer content.deinit(alloc);

                for (raw_content.items) |raw| {
                    content.appendAssumeCapacity(try Node.fromValue(alloc, raw));
                }

                return .{
                    .doc = .{
                        .version = value_obj.get("version").?.integer, // TODO: Safely
                        .content = content,
                    },
                };
            },
            .panel => {
                const raw_content = value_obj.get("content").?.array; // TODO: Safely
                var content = try ArrayList(Node).initCapacity(alloc, raw_content.items.len);
                errdefer content.deinit(alloc);

                for (raw_content.items) |raw| {
                    content.appendAssumeCapacity(try Node.fromValue(alloc, raw));
                }

                const panel_type_str = value_obj.get("attrs").?.object.get("panelType").?.string; // TODO Safely
                return .{
                    .panel = .{
                        .content = content,
                        .panel_type = std.meta.stringToEnum(PanelType, panel_type_str) orelse return error.UnknownPanelType,
                    },
                };
            },
            .paragraph => if (value_obj.get("content")) |raw_content| {
                const raw_content_array = raw_content.array; // TODO: Safely
                var content = try ArrayList(Node).initCapacity(alloc, raw_content_array.items.len);
                errdefer content.deinit(alloc);

                for (raw_content_array.items) |raw| {
                    content.appendAssumeCapacity(try Node.fromValue(alloc, raw));
                }

                return .{ .paragraph = .{ .content = content } };
            } else return .{ .paragraph = .{ .content = ArrayList(Node){} } },
            .text => {
                return .{ .text = .{ .text = value_obj.get("text").?.string, .marks = &[0]Mark{} } }; //TODO: Safely + marks field
            },
            else => {
                std.log.err("Unsupported node type: {}", .{node_type});
                unreachable;
            },
        }

        unreachable;
    }
};

const Mark = union(enum) {
    code,
    em,
    link,
    strike,
    strong,
    subsup,
    textColor,
    underline,
};

const PanelType = enum { info, note, warning, success, errorPanel };
