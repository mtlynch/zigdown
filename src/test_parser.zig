const std = @import("std");
const cons = @import("console.zig");
const zd = struct {
    usingnamespace @import("parser.zig");
    usingnamespace @import("render.zig");
    usingnamespace @import("render_html.zig");
    usingnamespace @import("utils.zig");
    usingnamespace @import("blocks.zig");
    usingnamespace @import("inlines.zig");
    usingnamespace @import("leaves.zig");
    usingnamespace @import("containers.zig");
    usingnamespace @import("tokens.zig");
};

pub const HtmlRenderer = zd.HtmlRenderer;
pub const htmlRenderer = zd.htmlRenderer;

pub const ConsoleRenderer = zd.ConsoleRenderer;
pub const consoleRenderer = zd.consoleRenderer;

/// Print indentation for the given depth
fn printIndent(depth: u8) void {
    var i: u8 = 0;
    while (i < depth) {
        std.debug.print("│ ", .{});
        i += 1;
    }
}

/// Print an AST Block (Container or Leaf)
fn printBlock(block: zd.Block, depth: u8) void {
    switch (block) {
        .Container => |c| printContainer(c, depth),
        .Leaf => |l| printLeaf(l, depth),
    }
}

/// Print a Container node and its children
fn printContainer(container: zd.Container, depth: u8) void {
    printIndent(depth);

    std.debug.print("Container: open: {any}, type: {s} with {d} children\n", .{
        container.open,
        @tagName(container.content),
        container.children.items.len,
    });

    for (container.children.items) |child| {
        printBlock(child, depth + 1);
    }
}

/// Print a Leaf node and its content
fn printLeaf(leaf: zd.Leaf, depth: u8) void {
    printIndent(depth);

    std.debug.print("Leaf: open: {any}, type: {s}\n", .{
        leaf.open,
        @tagName(leaf.content),
    });

    // Print leaf-specific content
    switch (leaf.content) {
        .Break => {},
        .Code => printCode(leaf.content.Code, depth + 1),
        .Heading => printHeading(leaf.content.Heading, depth + 1),
        .Paragraph => {},
    }

    // For links and other structured inline elements, we want to show their structure
    if (leaf.inlines.items.len > 0) {
        printIndent(depth + 1);
        std.debug.print("Inline content:\n", .{});
        for (leaf.inlines.items) |inline_item| {
            printInlineElement(inline_item, depth + 2);
        }
    } else {
        // Print each token with its line and column numbers
        for (leaf.raw_contents.items) |token| {
            printIndent(depth + 1);
            std.debug.print("Token: {s}, text: \"{s}\", line: {d}, col: {d}\n", .{
                zd.typeStr(token.kind),
                token.text,
                token.src.row,
                token.src.col,
            });
        }
    }
}

/// Print a Code block
fn printCode(code: zd.Code, depth: u8) void {
    if (code.tag) |tag| {
        printIndent(depth);
        std.debug.print("Language: {s}\n", .{tag});
    }

    if (code.directive) |directive| {
        printIndent(depth);
        std.debug.print("Directive: {s}\n", .{directive});
    }
}

/// Print a Heading block
fn printHeading(heading: zd.Heading, depth: u8) void {
    printIndent(depth);
    std.debug.print("[H{d}]\n", .{heading.level});
}

/// Print an Inline element (Text, Link, etc.)
fn printInlineElement(item: zd.Inline, d: u8) void {
    switch (item.content) {
        .text => |text| {
            printIndent(d);
            std.debug.print("Text: '{s}' [line: {d}, col: {d}]\n", .{
                text.text,
                text.line,
                text.col,
            });
        },
        .link => |link| {
            printIndent(d);
            std.debug.print("Link:\n", .{});
            for (link.text.items) |text| {
                printIndent(d + 1);
                std.debug.print("Text: '{s}' [line: {d}, col: {d}]\n", .{
                    text.text,
                    text.line,
                    text.col,
                });
            }
        },
        .autolink => |autolink| {
            printIndent(d);
            std.debug.print("Autolink: '{s}'\n", .{
                autolink.url,
            });
        },
        .codespan => |codespan| {
            printIndent(d);
            std.debug.print("Codespan: '{s}'\n", .{
                codespan.text,
            });
        },
        .image => |image| {
            printIndent(d);
            std.debug.print("Image: '{s}'\n", .{
                image.src,
            });
        },
        .linebreak => {
            printIndent(d);
            std.debug.print("Linebreak\n", .{});
        },
    }
}

/// Print the entire AST starting from the root block
fn printAST(root: zd.Block) void {
    printBlock(root, 0);
}

pub fn main() !void {
    const text1: []const u8 =
        \\# Heading 1
        \\## Heading 2
        \\### Heading 3
        \\#### Heading 4
        \\
        \\Foo **Bar _baz_**. ~Hi!~
        \\> > Double-nested ~Quote~
        \\> > ...which supports multiple lines, which will be wrapped to the appropriate width by the renderer.
        \\> Note that lazy continuation lines allow this to be included in the previous child.
        \\>
        \\> This should work, too...
        \\> - And so should this!
        \\>
        \\> foo
        \\
        \\Image: ![Some Image](../test/zig-zero.png)
        \\
        \\Link: [Click Me!](https://google.com)
        \\
        \\1. Numlist
        \\2. Foobar
        \\   - With child list
        \\   - this should work?
        \\      1. and this?
        \\      2. Wohooo!!!
        \\1. 2nd item
        \\
        \\- Another list
        \\- more items
        \\```c++
        \\  Some raw code here...
        \\And some more here.
        \\```
        \\para
    ;
    const text = text1;

    const stdout = std.io.getStdOut().writer();
    var style: zd.TextStyle = zd.TextStyle{ .fg_color = .Green, .bold = true };
    cons.printStyled(stdout, style, "\n────────────────── Test Document ──────────────────\n", .{});
    try stdout.print("{s}\n", .{text});
    cons.printStyled(stdout, style, "───────────────────────────────────────────────────\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var p: zd.Parser = zd.Parser.init(alloc, .{ .copy_input = false, .verbose = false });
    defer p.deinit();
    try p.parseMarkdown(text);

    style.fg_color = .Blue;
    cons.printStyled(stdout, style, "─────────────────── Parsed AST ────────────────────\n", .{});
    printAST(p.document);
    cons.printStyled(stdout, style, "───────────────────────────────────────────────────\n", .{});
}
