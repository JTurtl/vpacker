const std = @import("std");
const common = @import("common.zig");

const oom = common.oom;
const fatal = common.fatal;

pub fn check(archive_path: [:0]const u8) void {
    const file_data = readWholeFile(archive_path);

    if (file_data.len < common.HeaderV2.size) {
        fatal("Not a VPK file (too small)", .{});
    }

    var reader = common.Reader {.src = file_data };

    const magic = reader.int();
    if (magic != common.magic) {
        fatal("Not a VPK file (identifier mismatch)", .{});
    }

    const version = reader.int();
    if (version != 2) {
        fatal("Invalid VPK (bad version: {})", .{version});
    }

    const tree_size = reader.int();
    const file_data_size = reader.int();
    const archive_md5_size = reader.int();
    const other_md5_size = reader.int();
    const signature_size = reader.int();

    _ = tree_size;
    _ = file_data_size;
    _ = archive_md5_size;
    _ = other_md5_size;
    _ = signature_size;
}

fn readWholeFile(path: []const u8) []u8 {
    const file = std.fs.cwd().openFile(path, .{})
        catch |err| fatal("Error reading file: {}", .{err});
    defer file.close();

    const data = file.readToEndAlloc(common.allocator, std.math.maxInt(i32))
        catch |err| fatal("Error reading file: {}", .{err});

    return data;
}
