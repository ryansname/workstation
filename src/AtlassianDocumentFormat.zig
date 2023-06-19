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
    try writer.writeByteNTimes(' ', nest * 2);
    switch (node) {
        .blockquote => |blockquote| {
            try writer.print("Blockquote\n", .{});
            for (blockquote.content.items) |c| try basicStringRecurse(writer, c, nest + 1);
        },
        .bulletList => |list| {
            try writer.print("<ul>\n", .{});
            for (list.content.items) |c| try basicStringRecurse(writer, c, nest + 1);
        },
        .codeBlock => |code| {
            try writer.print("<code> - {s}\n", .{code.language orelse "<unknown>"});
            for (code.content.items) |c| try basicStringRecurse(writer, c, 0);
        },
        .doc => |doc| {
            try writer.print("Doc - Version: {}\n", .{doc.version});
            for (doc.content.items) |c| try basicStringRecurse(writer, c, nest + 1);
        },
        .emoji => |emoji| {
            try writer.print("{s} - text: {s} - id: {s}\n", .{ emoji.short_name, emoji.text orelse "<null>", emoji.id orelse "<null>" });
        },
        .hardBreak => {},
        .heading => |heading| {
            try writer.print("Heading {}\n", .{heading.level});
            if (heading.content) |hc| for (hc.items) |c| try basicStringRecurse(writer, c, nest + 1);
        },
        .inlineCard => |card| {
            switch (card.url_or_data) {
                .url => |url| try writer.print("Card - {s}\n", .{url}),
                .data => try writer.print("Card - Data (unsupported)\n", .{}),
            }
        },
        .listItem => |item| {
            try writer.print("<li>\n", .{});
            for (item.content.items) |c| try basicStringRecurse(writer, c, nest + 1);
        },
        .media => {
            try writer.print("Media - TODO\n", .{});
        },
        .mediaGroup => |group| {
            try writer.print("Media Group\n", .{});
            for (group.content.items) |c| try basicStringRecurse(writer, c, nest + 1);
        },
        .mediaSingle => {
            try writer.print("Media - TODO\n", .{});
        },
        .mention => |mention| {
            try writer.print("Mention - {s}\n", .{mention.text orelse mention.id});
        },
        .orderedList => |list| {
            try writer.print("<ol> - {}\n", .{list.first_number});
            for (list.content.items) |c| try basicStringRecurse(writer, c, nest + 1);
        },
        .panel => |panel| {
            try writer.print("Panel - {}\n", .{panel.panel_type});
            for (panel.content.items) |c| try basicStringRecurse(writer, c, nest + 1);
        },
        .paragraph => |paragraph| {
            try writer.print("Paragraph\n", .{});
            if (paragraph.content) |pc| for (pc.items) |c| try basicStringRecurse(writer, c, nest + 1);
        },
        .rule => {
            try writer.print("--------- RULE -----------\n", .{});
        },
        .table => {
            unreachable;
        },
        .tableCell => {
            unreachable;
        },
        .tableHeader => {
            unreachable;
        },
        .tableRow => {
            unreachable;
        },
        .text => |text| {
            try writer.print("{s}\n", .{text.text});
        },
    }
}

const FromValueError = MalformedNode || error{OutOfMemory};
const MalformedNode = error{ NodeIsWrongType, MissingRequiredField, UnknownEnumVariant, UnknownNodeType, UnknownPanelType };

fn parseContent(
    comptime contentRequired: bool,
    alloc: Allocator,
    value_obj: std.json.ObjectMap,
) FromValueError!if (contentRequired) ArrayList(Node) else ?ArrayList(Node) {
    if (value_obj.get("content")) |raw_content| switch (raw_content) {
        .array => |raw_content_array| {
            var content = try ArrayList(Node).initCapacity(alloc, raw_content_array.items.len);
            errdefer content.deinit(alloc);

            for (raw_content_array.items) |raw| {
                content.appendAssumeCapacity(try Node.fromValue(alloc, raw));
            }

            return content;
        },
        else => return error.NodeIsWrongType,
    } else if (contentRequired) {
        return error.MissingRequiredField;
    } else return null;
}

fn getAttrs(
    value_obj: std.json.ObjectMap,
) FromValueError!?std.json.ObjectMap {
    return if (value_obj.get("attrs")) |attrs| switch (attrs) {
        .object => |obj| return obj,
        else => return error.NodeIsWrongType,
    } else null;
}

pub const Node = union(enum) {
    const StatusColor = enum { neutral, purple, blue, red, yellow, green };

    blockquote: struct { content: ArrayList(Node) },
    bulletList: struct { content: ArrayList(Node) },
    codeBlock: struct { content: ArrayList(Node), language: ?[]const u8 },
    doc: struct { content: ArrayList(Node), version: i64 },
    emoji: struct { id: ?[]const u8, short_name: []const u8, text: ?[]const u8 },
    hardBreak,
    heading: struct { content: ?ArrayList(Node), level: u3 },
    inlineCard: struct { url_or_data: union(enum) { url: []const u8, data: void } },
    listItem: struct { content: ArrayList(Node) },
    media,
    mediaGroup: struct { content: ArrayList(Node) },
    mediaSingle,
    mention: struct { access_level: ?[]const u8, id: []const u8, text: ?[]const u8, user_type: ?[]const u8 },
    orderedList: struct { content: ArrayList(Node), first_number: u32 },
    panel: struct { content: ArrayList(Node), panel_type: PanelType },
    paragraph: struct { content: ?ArrayList(Node) },
    rule,
    status: struct { text: []const u8, color: StatusColor },
    table,
    tableCell,
    tableHeader,
    tableRow,
    text: struct { text: []const u8, marks: []const Mark },

    fn fromValue(alloc: Allocator, value: std.json.Value) FromValueError!Node {
        if (value != .object) return error.NodeIsWrongType;
        const value_obj = value.object;
        const ty = value_obj.get("type") orelse return error.MissingRequiredField;
        if (ty != .string) return error.NodeIsWrongType;

        var node_type = std.meta.stringToEnum(@typeInfo(Node).Union.tag_type.?, ty.string) orelse return error.UnknownNodeType;

        switch (node_type) {
            .blockquote => {
                return .{ .blockquote = .{ .content = try parseContent(true, alloc, value_obj) } };
            },
            .bulletList => {
                return .{ .bulletList = .{ .content = try parseContent(true, alloc, value_obj) } };
            },
            .codeBlock => {
                const attrs = try getAttrs(value_obj);
                const language = if (attrs) |a| if (a.get("language")) |language| switch (language) {
                    .string => |str| str,
                    else => return error.NodeIsWrongType,
                } else null else null;
                return .{ .codeBlock = .{ .content = try parseContent(true, alloc, value_obj), .language = language } };
            },
            .doc => {
                return .{
                    .doc = .{
                        .version = value_obj.get("version").?.integer, // TODO: Safely
                        .content = try parseContent(true, alloc, value_obj),
                    },
                };
            },
            .emoji => {
                const attrs = (try getAttrs(value_obj)) orelse return error.MissingRequiredField;
                const short_name = switch (attrs.get("shortName") orelse return error.MissingRequiredField) {
                    .string => |str| str,
                    else => return error.NodeIsWrongType,
                };
                const id = if (attrs.get("id")) |id| switch (id) {
                    .string => |str| str,
                    else => return error.NodeIsWrongType,
                } else null;
                const text = if (attrs.get("text")) |text| switch (text) {
                    .string => |str| str,
                    else => return error.NodeIsWrongType,
                } else null;
                return .{ .emoji = .{
                    .id = id,
                    .short_name = short_name,
                    .text = text,
                } };
            },
            .hardBreak => return .{ .hardBreak = {} },
            .heading => {
                const attrs = try getAttrs(value_obj) orelse return error.MissingRequiredField;
                const level = switch (attrs.get("level") orelse return error.MissingRequiredField) {
                    .integer => |integer| integer,
                    else => return error.NodeIsWrongType,
                };
                return .{ .heading = .{ .content = try parseContent(false, alloc, value_obj), .level = @intCast(u3, level) } }; // TODO: intcast safety
            },
            .inlineCard => {
                const attrs = try getAttrs(value_obj) orelse return error.MissingRequiredField;
                const url = if (attrs.get("url")) |id| switch (id) {
                    .string => |str| str,
                    else => return error.NodeIsWrongType,
                } else null;
                const has_data = attrs.contains("data");

                if (url == null and !has_data) return error.MissingRequiredField;

                return .{ .inlineCard = .{ .url_or_data = if (url) |u| .{ .url = u } else .{ .data = {} } } };
            },
            .listItem => {
                return .{ .listItem = .{ .content = try parseContent(true, alloc, value_obj) } };
            },
            .media => {
                return .{ .media = {} }; // TODO: Support media
            },
            .mediaGroup => {
                return .{ .mediaGroup = .{ .content = try parseContent(true, alloc, value_obj) } };
            },
            .mediaSingle => {
                return .{ .mediaSingle = {} }; // TODO: Support mediaSingle
            },
            .mention => {
                const attrs = try getAttrs(value_obj) orelse return error.MissingRequiredField;

                const id = if (attrs.get("id")) |id| switch (id) {
                    .string => |str| str,
                    else => return error.NodeIsWrongType,
                } else return error.MissingRequiredField;

                const access_level = if (attrs.get("accessLevel")) |access_level| switch (access_level) {
                    .string => |str| str,
                    else => return error.NodeIsWrongType,
                } else null;
                const text = if (attrs.get("text")) |text| switch (text) {
                    .string => |str| str,
                    else => return error.NodeIsWrongType,
                } else null;
                const user_type = if (attrs.get("userType")) |user_type| switch (user_type) {
                    .string => |str| str,
                    else => return error.NodeIsWrongType,
                } else null;

                return .{ .mention = .{
                    .access_level = access_level,
                    .id = id,
                    .text = text,
                    .user_type = user_type,
                } };
            },
            .orderedList => {
                const attrs = try getAttrs(value_obj);
                const first_number = if (attrs) |a| if (a.get("order")) |order| switch (order) {
                    .integer => |integer| integer,
                    else => return error.NodeIsWrongType,
                } else 1 else 1;
                return .{ .orderedList = .{ .content = try parseContent(true, alloc, value_obj), .first_number = @intCast(u32, first_number) } }; // TODO: intcast safety
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
            .paragraph => {
                return .{ .paragraph = .{ .content = try parseContent(false, alloc, value_obj) } };
            },
            .rule => {
                return .{ .rule = {} };
            },
            .status => {
                const attrs = (try getAttrs(value_obj)) orelse return error.MissingRequiredField;

                const text = if (attrs.get("text")) |text| switch (text) {
                    .string => text.string,
                    else => return error.NodeIsWrongType,
                } else return error.MissingRequiredField;

                const color_str = if (attrs.get("color")) |color| switch (color) {
                    .string => color.string,
                    else => return error.NodeIsWrongType,
                } else return error.MissingRequiredField;
                const color = std.meta.stringToEnum(StatusColor, color_str) orelse return error.UnknownEnumVariant;

                return .{ .status = .{ .text = text, .color = color } };
            },
            .table => {
                return .{ .table = {} }; // TODO: Support tables!
            },
            .tableCell => {
                return .{ .tableCell = {} }; // TODO: Support tables!
            },
            .tableHeader => {
                return .{ .tableHeader = {} }; // TODO: Support tables!
            },
            .tableRow => {
                return .{ .tableRow = {} }; // TODO: Support tables!
            },
            .text => {
                return .{ .text = .{ .text = value_obj.get("text").?.string, .marks = &[0]Mark{} } }; //TODO: Safely + marks field
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
