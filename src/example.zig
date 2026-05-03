const std = @import("std");
const Allocator = std.mem.Allocator;
const scripty = @import("root.zig"); // In your case this would be @import("scripty")

/// A Scripty VM is created by providing a Context and a Value type which
/// make up the Scripty evaluation context.
const ExampleInterpreter = scripty.VM(ExampleContext, ExampleValue);

test ExampleInterpreter {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    const arena = arena_state.allocator();

    const src = "$site.link()";
    var ctx: ExampleContext = .{
        .version = "v0",
        .page = .{
            .title = "Home",
            .content = "<p>Welcome!</p>",
        },
        .site = .{
            .name = "Example Website",
            .hostname = "example.com",
        },
        ._force_https = true,
    };

    var vm: ExampleInterpreter = .{};
    const result = while (true) break vm.run(arena, &ctx, src, .{}) catch |err| switch (err) {
        error.Interrupt => continue, // builtin functions can trigger interrupts if they wish
        error.OutOfMemory => std.process.fatal("oom", .{}),
        error.Quota => unreachable, // we are running with infinite quota, see RunOptions
    };

    const value: ExampleValue = result.value;
    try std.testing.expectEqualStrings("https://example.com", value.string);
}

/// This is the type definition for your evaluation context. Every Scripty
/// expression will start by accessing a field of this struct (e.g. `$version`,
/// `$page`, `$site`).
///
/// You have the ability to personalize the behavior of Scripty whenever
/// evaluating a field navigation expression (eg `$page.title`).
/// By using `scripty.defaultDot` the expression will be mapped 1:1 to struct
/// navigation (i.e. `$page.title` will return the `title` field of `Page`).
/// When usind `scripty.defaultDot`, any field that start with an underscore
/// will NOT be accessible through Scripty. This is useful to make available
/// resources such as allocators to builtin function implementations, while
/// preventing the user from being able to access them directly.
///
/// See below the definition of `ExampleValue` to learn the possible values
/// that a Scripty expression can evaluate to.
const ExampleContext = struct {
    version: []const u8,
    page: Page,
    site: Site,

    // Private, `defaultDot` won't make it accessible to users.
    _force_https: bool,

    // Whether the value should be passed by copy or by pointer to
    // functions.
    pub const PassByRef = true;
    pub const dot = scripty.defaultDot(ExampleContext, ExampleValue, false);
    pub const Builtins = struct {};

    pub const Site = struct {
        name: []const u8,
        hostname: []const u8,

        pub const PassByRef = true;
        pub const dot = scripty.defaultDot(Site, ExampleValue, false);

        /// This is a convention used by `defaultCall` (see below the definition of `ExampleValue`).
        /// Each definition inside of `Builtins` is a builtin function that users will be able
        /// to call on the original value (e.g. `$site.link()`).
        pub const Builtins = struct {
            pub const link = struct {
                pub fn call(
                    site: *const Site,
                    gpa: Allocator,
                    // Root context is always made available to give you easy access
                    // to resources hidden in private fields.
                    ctx: *const ExampleContext,
                    args: []const ExampleValue,
                ) !ExampleValue {
                    // Make sure to validate your arguments!
                    const bad_arg: ExampleValue = .{ .err = "expected 0 arguments" };
                    if (args.len != 0) return bad_arg;

                    return .{
                        .string = try std.fmt.allocPrint(gpa, "http{s}://{s}", .{
                            if (ctx._force_https) "s" else "",
                            site.hostname,
                        }),
                    };
                }
            };
        };
    };

    pub const Page = struct {
        title: []const u8,
        content: []const u8,

        pub const PassByRef = true;
        pub const dot = scripty.defaultDot(Page, ExampleValue, false);
        pub const Builtins = struct {};
    };
};

/// This union defines the various value types that can be returned by a Scripty
/// expression.
/// In Scripty basic types (string, int, float, bool, err) are expected to be present,
/// but everything else is for you to define.
///
/// Although this type is listed below `ExampleContext`, Scripty evaluation
/// starts from this definition. For example field navigation ('$foo.bar')
/// starts by evaluating `ExampleValue.dot()`, which for non-primitive types
/// will delegate to the `dot` definition in each type (which in the current
/// example will always result into calling `defaultDot` with the semantics
/// explained above).
///
/// Note that field navigation ('$foo.bar') and builtin function calling ('$foo.baz()')
/// are handled separately (see `ExampleValue.call`).
pub const ExampleValue = union(Tag) {
    global: *const ExampleContext,
    site: *const ExampleContext.Site,
    page: *const ExampleContext.Page,
    string: []const u8,
    bool: bool,
    int: usize,
    float: f64,
    err: []const u8, // error message
    nil,

    pub const Tag = enum {
        global,
        site,
        page,
        string,
        bool,
        int,
        float,
        err,
        nil,
    };

    pub fn dot(
        self: ExampleValue,
        gpa: std.mem.Allocator,
        path: []const u8,
    ) error{OutOfMemory}!ExampleValue {
        switch (self) {
            .string,
            .bool,
            .int,
            .float,
            .err,
            .nil,
            => return .{ .err = "primitive value" },
            inline else => |v| return v.dot(gpa, path),
        }
    }

    pub const call = scripty.defaultCall(ExampleValue, ExampleContext);

    // This function is used to provide builtins to primitive types.
    // In this case we're giving a builtin function named `len` to strings
    // which will allow users to do '$page.title.len()' for example.
    pub fn builtinsFor(comptime tag: Tag) type {
        const StringBuiltins = struct {
            pub const len = struct {
                pub fn call(
                    str: []const u8,
                    gpa: std.mem.Allocator,
                    _: *const ExampleContext,
                    args: []const ExampleValue,
                ) !ExampleValue {
                    if (args.len != 0) return .{
                        .err = "'len' wants no arguments",
                    };
                    return ExampleValue.from(gpa, str.len);
                }
            };
        };
        return switch (tag) {
            .string => StringBuiltins,
            .bool, .int, .float, .err, .nil => struct {},
            else => |t| @typeInfo(@FieldType(ExampleValue, @tagName(t))).pointer.child.Builtins,
        };
    }

    // This and the subsequent functions define which value to map each literal.
    pub fn fromStringLiteral(bytes: []const u8) ExampleValue {
        return .{ .string = bytes };
    }

    pub fn fromNumberLiteral(bytes: []const u8) ExampleValue {
        _ = bytes;
        return .{ .int = 0 };
    }

    pub fn fromBooleanLiteral(b: bool) ExampleValue {
        return .{ .bool = b };
    }

    // This is a general-purpose type-mapping function, you generally want
    // to add an entry whenever you see a compile error about value mapping.
    pub fn from(gpa: std.mem.Allocator, value: anytype) !ExampleValue {
        _ = gpa;
        const T = @TypeOf(value);
        switch (T) {
            *ExampleContext, *const ExampleContext => return .{ .global = value },
            *const ExampleContext.Site => return .{ .site = value },
            *const ExampleContext.Page => return .{ .page = value },
            []const u8 => return .{ .string = value },
            usize => return .{ .int = value },
            else => @compileError("TODO: add support for " ++ @typeName(T)),
        }
    }
};
