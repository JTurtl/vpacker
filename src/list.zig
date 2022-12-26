const std = @import("std");
const common = @import("common.zig");

pub fn list(archive_path: [:0]const u8) void {
    const file = common.readDirectoryFile(archive_path);
    const entries = common.getAllEntries(file.tree_data);

    var buffered_writer = std.io.bufferedWriter(std.io.getStdOut().writer());
    const writer = buffered_writer.writer();

    for (entries) |entry| {
        // see FullEntry.format
        writer.print("{s}\n", .{entry})
            catch unreachable;

        // failing to write to stdout is weird enough that
        // i dont care to handle it.
    }
    buffered_writer.flush() catch unreachable;
}
