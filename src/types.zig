const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn defaultCall(Value: type, Context: type) fn (
    Value,
    Allocator,
    *const Context,
    []const u8,
    []const Value,
) error{OutOfMemory}!Value {
    return struct {
        pub fn call(
            value: Value,
            gpa: Allocator,
            ctx: *const Context,
            fn_name: []const u8,
            args: []const Value,
        ) error{OutOfMemory}!Value {
            switch (value) {
                inline else => |v, tag| {
                    const Builtin = if (@hasDecl(Value, "builtinsFor"))
                        Value.builtinsFor(tag)
                    else
                        defaultBuiltinsFor(Value, @TypeOf(v));

                    inline for (@typeInfo(Builtin).@"struct".decls) |decl| {
                        if (decl.name[0] == '_') continue;
                        if (std.mem.eql(u8, decl.name, fn_name)) {
                            return @field(Builtin, decl.name).call(
                                v,
                                gpa,
                                ctx,
                                args,
                            );
                        }
                    }

                    if (hasDecl(@TypeOf(v), "fallbackCall")) {
                        return v.fallbackCall(
                            gpa,
                            ctx,
                            fn_name,
                            args,
                        );
                    }

                    return .{ .err = "builtin not found" };
                },
            }
        }
    }.call;
}

inline fn hasDecl(T: type, comptime decl: []const u8) bool {
    return switch (@typeInfo(T)) {
        else => false,
        .pointer => |p| return hasDecl(p.child, decl),
        .@"struct", .@"union", .@"enum", .@"opaque" => return @hasDecl(T, decl),
    };
}

inline fn constify(comptime T: type, comptime mut: bool) type {
    return switch (mut) {
        true => *T,
        false => *const T,
    };
}

pub fn defaultBuiltinsFor(comptime Value: type, comptime Field: type) type {
    inline for (std.meta.fields(Value)) |f| {
        if (f.type == Field) {
            switch (@typeInfo(f.type)) {
                .pointer => |ptr| {
                    if (@typeInfo(ptr.child) == .@"struct") {
                        return @field(ptr.child, "Builtins");
                    }
                },
                .@"struct" => {
                    return @field(f.type, "Builtins");
                },
                else => {},
            }

            return struct {};
        }
    }
    @compileError("Value has no field of value " ++ @typeName(Field));
}
