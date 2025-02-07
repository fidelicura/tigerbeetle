const std = @import("std");
const vsr = @import("vsr");
const tb = vsr.tigerbeetle;
const tb_client = vsr.tb_client;

const type_mappings = .{
    .{ tb.AccountFlags, "TB_ACCOUNT_FLAGS" },
    .{ tb.Account, "tb_account_t" },
    .{ tb.TransferFlags, "TB_TRANSFER_FLAGS" },
    .{ tb.Transfer, "tb_transfer_t" },
    .{ tb.CreateAccountResult, "TB_CREATE_ACCOUNT_RESULT" },
    .{ tb.CreateTransferResult, "TB_CREATE_TRANSFER_RESULT" },
    .{ tb.CreateAccountsResult, "tb_create_accounts_result_t" },
    .{ tb.CreateTransfersResult, "tb_create_transfers_result_t" },
    .{ tb.AccountFilter, "tb_account_filter_t" },
    .{ tb.AccountFilterFlags, "TB_ACCOUNT_FILTER_FLAGS" },
    .{ tb.AccountBalance, "tb_account_balance_t" },
    .{ tb.QueryFilter, "tb_query_filter_t" },
    .{ tb.QueryFilterFlags, "TB_QUERY_FILTER_FLAGS" },

    .{ tb_client.tb_operation_t, "TB_OPERATION" },
    .{ tb_client.tb_packet_status_t, "TB_PACKET_STATUS" },
    .{ tb_client.tb_packet_t, "tb_packet_t" },
    .{ tb_client.tb_client_t, "tb_client_t" },
    .{ tb_client.tb_status_t, "TB_STATUS" },
};

fn resolve_c_type(comptime Type: type) []const u8 {
    switch (@typeInfo(Type)) {
        .Array => |info| return resolve_c_type(info.child),
        .Enum => |info| return resolve_c_type(info.tag_type),
        .Struct => return resolve_c_type(std.meta.Int(.unsigned, @bitSizeOf(Type))),
        .Bool => return "uint8_t",
        .Int => |info| {
            std.debug.assert(info.signedness == .unsigned);
            return switch (info.bits) {
                8 => "uint8_t",
                16 => "uint16_t",
                32 => "uint32_t",
                64 => "uint64_t",
                128 => "tb_uint128_t",
                else => @compileError("invalid int type"),
            };
        },
        .Optional => |info| switch (@typeInfo(info.child)) {
            .Pointer => return resolve_c_type(info.child),
            else => @compileError("Unsupported optional type: " ++ @typeName(Type)),
        },
        .Pointer => |info| {
            std.debug.assert(info.size != .Slice);
            std.debug.assert(!info.is_allowzero);

            inline for (type_mappings) |type_mapping| {
                const ZigType = type_mapping[0];
                const c_name = type_mapping[1];

                if (info.child == ZigType) {
                    const prefix = if (@typeInfo(ZigType) == .Struct) "struct " else "";
                    return prefix ++ c_name ++ "*";
                }
            }

            return comptime resolve_c_type(info.child) ++ "*";
        },
        .Void, .Opaque => return "void",
        else => @compileError("Unhandled type: " ++ @typeName(Type)),
    }
}

fn to_uppercase(comptime input: []const u8) [input.len]u8 {
    comptime var output: [input.len]u8 = undefined;
    inline for (&output, 0..) |*char, i| {
        char.* = input[i];
        char.* -= 32 * @as(u8, @intFromBool(char.* >= 'a' and char.* <= 'z'));
    }
    return output;
}

fn emit_enum(
    buffer: *std.ArrayList(u8),
    comptime Type: type,
    comptime type_info: anytype,
    comptime c_name: []const u8,
    comptime skip_fields: []const []const u8,
) !void {
    var suffix_pos = std.mem.lastIndexOf(u8, c_name, "_").?;
    if (std.mem.count(u8, c_name, "_") == 1) suffix_pos = c_name.len;

    try buffer.writer().print("typedef enum {s} {{\n", .{c_name});

    inline for (type_info.fields, 0..) |field, i| {
        comptime var skip = false;
        inline for (skip_fields) |sf| {
            skip = skip or comptime std.mem.eql(u8, sf, field.name);
        }

        if (!skip) {
            const field_name = to_uppercase(field.name);
            if (@typeInfo(Type) == .Enum) {
                try buffer.writer().print("    {s}_{s} = {},\n", .{
                    c_name[0..suffix_pos],
                    @as([]const u8, &field_name),
                    @intFromEnum(@field(Type, field.name)),
                });
            } else {
                // Packed structs.
                try buffer.writer().print("    {s}_{s} = 1 << {},\n", .{
                    c_name[0..suffix_pos],
                    @as([]const u8, &field_name),
                    i,
                });
            }
        }
    }

    try buffer.writer().print("}} {s};\n\n", .{c_name});
}

fn emit_struct(
    buffer: *std.ArrayList(u8),
    comptime type_info: anytype,
    comptime c_name: []const u8,
) !void {
    try buffer.writer().print("typedef struct {s} {{\n", .{c_name});

    inline for (type_info.fields) |field| {
        try buffer.writer().print("    {s} {s}", .{
            resolve_c_type(field.type),
            field.name,
        });

        switch (@typeInfo(field.type)) {
            .Array => |array| try buffer.writer().print("[{d}]", .{array.len}),
            else => {},
        }

        try buffer.writer().print(";\n", .{});
    }

    try buffer.writer().print("}} {s};\n\n", .{c_name});
}

pub fn main() !void {
    @setEvalBranchQuota(100_000);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buffer = std.ArrayList(u8).init(allocator);
    try buffer.writer().print(
        \\ //////////////////////////////////////////////////////////
        \\ // This file was auto-generated by tb_client_header.zig //
        \\ //              Do not manually modify.                 //
        \\ //////////////////////////////////////////////////////////
        \\
        \\#ifndef TB_CLIENT_H
        \\#define TB_CLIENT_H
        \\
        \\#ifdef __cplusplus
        \\extern "C" {{
        \\#endif
        \\
        \\#include <stddef.h>
        \\#include <stdint.h>
        \\#include <stdbool.h>
        \\
        \\typedef __uint128_t tb_uint128_t;
        \\
        \\
    , .{});

    // Emit C type declarations.
    inline for (type_mappings) |type_mapping| {
        const ZigType = type_mapping[0];
        const c_name = type_mapping[1];

        switch (@typeInfo(ZigType)) {
            .Struct => |info| switch (info.layout) {
                .auto => @compileError("Invalid C struct type: " ++ @typeName(ZigType)),
                .@"packed" => try emit_enum(&buffer, ZigType, info, c_name, &.{"padding"}),
                .@"extern" => try emit_struct(&buffer, info, c_name),
            },
            .Enum => |info| {
                comptime var skip: []const []const u8 = &.{};
                if (ZigType == tb_client.tb_operation_t) {
                    skip = &.{ "reserved", "root", "register" };
                }

                try emit_enum(&buffer, ZigType, info, c_name, skip);
            },
            else => try buffer.writer().print("typedef {s} {s}; \n\n", .{
                resolve_c_type(ZigType),
                c_name,
            }),
        }
    }

    // Emit C function declarations.
    // TODO: use `std.meta.declaractions` and generate with pub + export functions.
    // Zig 0.9.1 has `decl.data.Fn.arg_names` but it's currently/incorrectly a zero-sized slice.
    try buffer.writer().print(
        \\// Initialize a new TigerBeetle client which connects to the addresses provided and
        \\// completes submitted packets by invoking the callback with the given context.
        \\TB_STATUS tb_client_init(
        \\    tb_client_t* out_client,
        \\    const uint8_t cluster_id[16],
        \\    const char* address_ptr,
        \\    uint32_t address_len,
        \\    uintptr_t on_completion_ctx,
        \\    void (*on_completion)(uintptr_t, tb_client_t, tb_packet_t*, uint64_t, const uint8_t*, uint32_t)
        \\);
        \\
        \\// Initialize a new TigerBeetle client which echos back any data submitted.
        \\TB_STATUS tb_client_init_echo(
        \\    tb_client_t* out_client,
        \\    const uint8_t cluster_id[16],
        \\    const char* address_ptr,
        \\    uint32_t address_len,
        \\    uintptr_t on_completion_ctx,
        \\    void (*on_completion)(uintptr_t, tb_client_t, tb_packet_t*, uint64_t, const uint8_t*, uint32_t)
        \\);
        \\
        \\// Retrieve the callback context initially passed into `tb_client_init` or
        \\// `tb_client_init_echo`.
        \\uintptr_t tb_client_completion_context(
        \\    tb_client_t client
        \\);
        \\
        \\// Submit a packet with its operation, data, and data_size fields set.
        \\// Once completed, `on_completion` will be invoked with `on_completion_ctx` and the given
        \\// packet on the `tb_client` thread (separate from caller's thread).
        \\void tb_client_submit(
        \\    tb_client_t client,
        \\    tb_packet_t* packet
        \\);
        \\
        \\// Closes the client, causing any previously submitted packets to be completed with
        \\// `TB_PACKET_CLIENT_SHUTDOWN` before freeing any allocated client resources from init.
        \\// It is undefined behavior to use any functions on the client once deinit is called.
        \\void tb_client_deinit(
        \\    tb_client_t client
        \\);
        \\
        \\
    , .{});

    try buffer.writer().print(
        \\#ifdef __cplusplus
        \\}} // extern "C"
        \\#endif
        \\
        \\#endif // TB_CLIENT_H
        \\
    , .{});

    try std.io.getStdOut().writeAll(buffer.items);
}
