//todo: unpack options:
//  verify checksum: make sure MD5 sections are valid

const std = @import("std");
const common = @import("common.zig");

const fatal = common.fatal;

fn filenamelen() noreturn {
    fatal("File name too long", .{});
}

const max_archive_size = std.math.maxInt(i32);

var is_multifile: bool = undefined;
var basename: []const u8 = undefined;
var archive: common.VpkFile = undefined;
var entries: []common.FullEntry = undefined;

pub fn unpack(archive_path: [:0]const u8) void {
    if (!std.ascii.endsWithIgnoreCase(archive_path, ".vpk")) {
        fatal("Archive needs .vpk extension.", .{});
    }

    is_multifile = std.mem.endsWith(u8, archive_path, "_dir.vpk");
    basename = trimArchivePath(archive_path);

    archive = common.readDirectoryFile(archive_path);
    entries = common.getAllEntries(archive.tree_data);

    makeDir(basename);
    chdir(basename);

    // All local files first
    var max_archive_index: ?u16 = null;
    for (entries) |entry| {
        if (entry.data.archive != 0x7fff) {
            if (
                max_archive_index == null
                or entry.data.archive > max_archive_index.?
            )
                max_archive_index = entry.data.archive;
            continue;
        }

        extractEntry(entry, archive.file_data);
    }

    if (!is_multifile) {
        if (max_archive_index != null)
            fatal("Found files with external data, but this archive's name does not end with _dir.vpk", .{});
    
        return;
    }

    // Grab all files from each archive file (file_NNN.vpk) sequentially
    // Opening and closing each file as needed would be very, very slow.
    var archive_idx: u16 = 0;
    while (archive_idx <= max_archive_index.?) : (archive_idx += 1) {

        // Open file_[archive_idx].vpk
        var ex_name_buf: [std.os.PATH_MAX]u8 = undefined;
        const ex_name =
            std.fmt.bufPrintZ(
                &ex_name_buf,
                "{s}_{:0>3}.vpk", // {:0>3} = three digit 0-padded
                .{trimArchiveExtension(archive_path), archive_idx}
            ) catch filenamelen();

        // Load entire file into memory, why not
        const ex_data = std.fs.cwd().readFileAlloc(common.allocator, ex_name, max_archive_size)
            catch |err| fatal("Couldn't read '{s}': {}", .{ex_name, err});
        defer common.allocator.free(ex_data);

        for (entries) |entry| {
            if (entry.data.archive == archive_idx) {
                extractEntry(entry, ex_data);
            }
        }
    }
}

// Function wrappers that handle failure
fn makeDir(name: []const u8) void {
    std.fs.cwd().makeDir(name)
        catch |err| fatal("Error creating directory '{s}': {}", .{name, err});
}
fn chdir(name: []const u8) void {
    std.os.chdir(name) catch |err| fatal("Error moving to directory '{s}': {}", .{name, err});
}

fn extractEntry(entry: FullEntry, main_data_src: []const u8) void {
    const preload_data = entryPreloadData(entry);
    const main_data = entryMainData(entry, main_data_src);

    if (!common.isBlank(entry.directory))
        std.fs.cwd().makePath(entry.directory)
            catch |err| fatal("Error creating path: {}", .{err});

    var file_name_buf: [std.os.PATH_MAX]u8 = undefined;
    const file_name = std.fmt.bufPrintZ(&file_name_buf, "{}", .{entry}) catch filenamelen();

    const output_file = std.fs.cwd().createFileZ(file_name, .{})
        catch |err| fatal("Error creating file: {}", .{err});
    defer output_file.close();
    
    if (entry.data.preload != 0)
        output_file.writeAll(preload_data)
            catch |err| fatal("error writing to file: {}", .{err});

    output_file.writeAll(main_data)
        catch |err| fatal("error writing to file: {}", .{err});

}

fn entryMainData(entry: FullEntry, src: []const u8) []const u8 {
    return src[
        entry.data.offset..entry.data.offset+entry.data.length
    ];
}

const FullEntry = common.FullEntry;
fn entryPreloadData(entry: FullEntry) []const u8 {
    if (entry.data.preload == 0)
        return undefined;
    const start = entry.file_pos + common.Entry.size;
    return archive.tree_data[start .. start + entry.data.preload];
}


fn trimArchivePath(path: []const u8) []const u8 {
    const no_ext = trimArchiveExtension(path);
    const result = trimParentDirs(no_ext);
    return result;
}

fn trimParentDirs(name: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, name, '/')) |index| {
        return name[index+1..];
    }
    return name;
}

fn trimArchiveExtension(name: []const u8) []const u8 {
    const indexOf = std.ascii.indexOfIgnoreCase;
    if (indexOf(name, "_dir.vpk")) |idx| {
        // trim "_dir.vpk"
        return name[0..idx];
    }

    // trim ".vpk"
    return name[0..name.len-4];
}
