const std = @import("std");

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

pub const magic: u32 = 0x55aa1234;

pub const VpkFile = struct {
    header: HeaderV2,
    tree_data: []const u8,
    file_data: []const u8,
};

pub const HeaderV2 = packed struct {
    pub const size = 28;

    magic: u32,
    version: u32,
    tree_size: u32,
    file_data_size: u32,
    archive_md5_size: u32,
    other_md5_size: u32,
    signature_size: u32,
};

pub const Entry = packed struct {
    pub const size: u32 = 18;

    crc: u32,
    preload: u16,
    archive: u16,
    offset: u32,
    length: u32,
    terminator: u16,
};

pub const FullEntry = struct {
    filename: []const u8,
    directory: []const u8,
    extension: []const u8,

    file_pos: u32,

    data: *align(1) const Entry,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype
    ) !void {
        _ = fmt;
        _ = options;
        if (
            !isBlank(self.directory)
            and !isBlank(self.extension)
            and !isBlank(self.filename)
        ) {
            try writer.print("{s}/{s}.{s}", .{
                self.directory, self.filename, self.extension
            });
        }
        else if (
            isBlank(self.directory)
            and !isBlank(self.extension)
            and !isBlank(self.filename)
        ) {
            try writer.print("{s}.{s}", .{self.filename, self.extension});
        }
        else {
            @panic("bad combo of blank path parts");
        }
    }
};

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.process.exit(1);
}

pub fn oom() noreturn {
    fatal("Out of memory", .{});
}

pub fn isBlank(str: []const u8) bool {
    return str.len == 1 and str[0] == ' ';
}

pub const Reader = struct {
    index: u32 = 0,
    src: []const u8,

    pub fn string(self: *@This()) []const u8 {
        const start = self.index;
        while (self.src[self.index] != 0) {
            //std.debug.print("% {}: {X:0>2}", .{self.index, self.src[self.index]});
            //pause();
            self.index += 1;
        }
        const str = self.src[start..self.index];
        self.index += 1;
        return str;
    }

    pub fn int(self: *@This()) u32 {
        defer self.index += 4;
        return std.mem.readIntLittle(u32, self.src[self.index..][0..4]);
    }

    pub fn short(self: *@This()) u16 {
        defer self.index += 2;
        return std.mem.readIntLittle(u16, self.src[self.index..][0..4]);
    }
};

pub fn getAllEntries(tree_data: []const u8) []FullEntry {
    var result = std.ArrayList(FullEntry).init(allocator);
    var reader = Reader{.src = tree_data};
    while (true) {
        const ext = reader.string();
        if (ext.len == 0)
            break;

        while (true) {
            const path = reader.string();
            if (path.len == 0)
                break;

            while (true) {
                const fname = reader.string();
                if (fname.len == 0)
                    break;

                //std.debug.print("poop: {s}\n", .{fname});

                // big endian cpus get fucked i guess
                const entry = @ptrCast(*const align(1) Entry, reader.src.ptr + reader.index);
                result.append(FullEntry {
                    .filename = fname,
                    .directory = path,
                    .extension = ext,
                    .file_pos = reader.index,
                    .data = entry,
                }) catch oom();
                reader.index += Entry.size + entry.preload;
            }
        }
    }

    return result.toOwnedSlice() catch oom();
}

pub fn readDirectoryFile(path: [:0]const u8) VpkFile {
    const fp = std.fs.cwd().openFile(path, .{})
        catch |err| fatal("File open failure ({s}): {}", .{path, err});

    // We may be working with rather chonky files here.
    // Dont read everything at once.
    //TODO: worry about big endianness... eventually. maybe.
    var header: HeaderV2 = undefined;
    const bytes_read = fp.readAll(
        // can't use std.mem.asBytes()
        // because @sizeOf(HeaderV2) != HeaderV2.size.
        // manually convert &header to a slice of bytes
        @ptrCast([*]u8, &header)[0..HeaderV2.size],
    ) catch |err| fatal("File read failure: {}", .{err});

    if (bytes_read != HeaderV2.size) {
        fatal("Not a VPK (too small)", .{});
    }

    if (header.magic != magic) {
        fatal("Not a VPK (bad signature)", .{});
    }

    //TODO: Version 1 vpks. they're out there, somewhere...
    if (header.version != 2) {
        fatal("Invalid VPK version: {} (expected 2)", .{header.version});
    }

    // Confident that this is a real VPK dir file.
    // Now we may do the big read.
    const all_data_after_header = fp.readToEndAllocOptions(
        allocator,
        std.math.maxInt(i32), // max length
        null,
        8, // alignment
        null,
    ) catch |err| fatal("File read failure: {}", .{err});

    // done with this
    fp.close();

    const expected_data_len =
        header.tree_size
        + header.file_data_size
        + header.archive_md5_size
        + header.other_md5_size
        + header.signature_size;

    if (all_data_after_header.len != expected_data_len) {
        fatal(
            "file size not expected based on header ({} != {})\n",
            .{all_data_after_header.len, expected_data_len}
        );
    }

    const tree_data = all_data_after_header[0..header.tree_size];
    const file_data = all_data_after_header[header.tree_size..header.tree_size+header.file_data_size];
    //print("tree size: {}, file data size: {}\n", .{tree_data.len, file_data.len});
    return .{
        .header = header,
        .tree_data = tree_data,
        .file_data = file_data,
    };
}
