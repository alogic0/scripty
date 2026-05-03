const std = @import("std");
const Allocator = std.mem.Allocator;
const scripty = @import("root.zig"); // In your case this would be @import("scripty")

/// A Scripty VM is created by providing a Context and a Value type which
/// make up the Scripty evaluation context.
const ExampleVM = scripty.VM(ExampleRoot, ExampleValueUnion);

test ExampleVM {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    const arena = arena_state.allocator();

    const src = "$site.link()";
    var ctx: ExampleRoot = .{
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

    var vm: ExampleVM = .{};
    const result = while (true) break vm.run(arena, &ctx, src, .{}) catch |err| switch (err) {
        error.OutOfMemory => std.process.fatal("oom", .{}),
        error.Quota => unreachable, // we are running with infinite quota, see RunOptions
    };

    const value: ExampleValueUnion = result.value;
    try std.testing.expectEqualStrings("https://example.com", value.string);
}

/// This is the type definition for the root of your evaluation context.
/// Every Scripty expression will start by accessing a field of this struct
/// (e.g. `$version`, `$page`, `$site`).
///
/// Field navigation (eg '$page.title') maps 1:1 to struct field navigation
/// when the corresponding struct definition contains a `Dot` decl set to
/// true (all fields will be private otherwise). If you want a field to NOT
/// be accessible by users via Scripty, when `Dot = true`, prefix it with
/// '_'. This is useful to make available resources such as allocators to
/// builtin function implementations.
///
/// See below the definition of `ExampleValue` to learn the possible values
/// that a Scripty expression can evaluate to.
const ExampleRoot = struct {
    version: []const u8,
    page: Page,
    site: Site,

    // Private, won't be accessible to users.
    _force_https: bool,

    // Whether the value should be passed by copy or by pointer to
    // builtin functions (the builtin function signature must match).
    pub const PassByRef = true;

    // Marks this type as being navigable via dot syntax (eg '$version').
    // Note that this is unrelated to being able to call builtin functions
    // on this type (eg '$foo.baz()').
    // Fields prefixed by an underscore will remain private (ie not
    // navigable by users).
    pub const Dot = true;

    pub const Builtins = struct {};

    pub const Site = struct {
        name: []const u8,
        hostname: []const u8,

        pub const Dot = true;
        pub const PassByRef = true;

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
                    ctx: *const ExampleRoot,
                    args: []const ExampleValueUnion,
                ) !ExampleValueUnion {
                    // Make sure to validate your arguments!
                    const bad_arg: ExampleValueUnion = .{ .err = "expected 0 arguments" };
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

        pub const Dot = true;
        pub const PassByRef = true;
        pub const Builtins = struct {};
    };
};

/// This union defines the various value types that can be returned by a Scripty
/// expression.
///
/// It's your job to map literals to their corresponding union case (see
/// `fromStringLiteral()` for example), including mapping them to an
/// evaluation error, if so desired.
///
/// What values should exist in your evaluation context is entirely up to you
/// except for one case: errors. The `err: []const u8` union case is required
/// by Scripty as it is used to report all kinds of runtime evaluation errors.
///
/// When a Scripty VM is embedded in a host language it's also possible that
/// the host language also places ulterior requirements on the structure of
/// the evaluation context. For example SuperHTML requires the existence
/// of Optionals, Iterators, and a few other things.
pub const ExampleValueUnion = union(Tag) {
    global: *const ExampleRoot,
    site: *const ExampleRoot.Site,
    page: *const ExampleRoot.Page,
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

    pub const call = scripty.defaultCall(ExampleValueUnion, ExampleRoot);

    // This function is used to provide builtins to primitive types.
    // In this case we're giving a builtin function named `len` to strings
    // which will allow users to do '$page.title.len()' for example.
    pub fn builtinsFor(comptime tag: Tag) type {
        const StringBuiltins = struct {
            pub const len = struct {
                pub fn call(
                    str: []const u8,
                    gpa: std.mem.Allocator,
                    _: *const ExampleRoot,
                    args: []const ExampleValueUnion,
                ) !ExampleValueUnion {
                    if (args.len != 0) return .{
                        .err = "'len' wants no arguments",
                    };
                    return ExampleValueUnion.from(gpa, str.len);
                }
            };
        };
        return switch (tag) {
            .string => StringBuiltins,
            .bool, .int, .float, .err, .nil => struct {},
            else => |t| @typeInfo(@FieldType(ExampleValueUnion, @tagName(t))).pointer.child.Builtins,
        };
    }

    // This and the subsequent functions define which value to map each literal.
    pub fn fromStringLiteral(bytes: []const u8) ExampleValueUnion {
        return .{ .string = bytes };
    }

    pub fn fromNumberLiteral(bytes: []const u8) ExampleValueUnion {
        _ = bytes;
        return .{ .int = 0 }; // TODO: perform proper parsing
    }

    pub fn fromBooleanLiteral(b: bool) ExampleValueUnion {
        return .{ .bool = b };
    }

    // This is a general-purpose type-mapping function, you generally want
    // to add an entry whenever you see a compile error about value mapping.
    pub fn from(gpa: std.mem.Allocator, value: anytype) !ExampleValueUnion {
        _ = gpa;
        const T = @TypeOf(value);
        switch (T) {
            *ExampleRoot, *const ExampleRoot => return .{ .global = value },
            *const ExampleRoot.Site => return .{ .site = value },
            *const ExampleRoot.Page => return .{ .page = value },
            []const u8 => return .{ .string = value },
            usize => return .{ .int = value },
            else => @compileError("TODO: add support for " ++ @typeName(T)),
        }
    }
};
