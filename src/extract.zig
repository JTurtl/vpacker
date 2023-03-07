const std = @import("std");
const common = @import("common.zig");

const oom = common.oom;
const fatal = common.fatal;

var archive: common.VpkFile = undefined;

const max_archive_size = std.math.maxInt(i32);
const print = std.debug.print;

pub fn extract(paths: [][:0]const u8) void {
    archive = common.readDirectoryFile(paths[0]);

    const search_paths = paths[1..];

    const found_flags = common.allocator.alloc(bool, search_paths.len)
        catch oom();

    std.mem.set(bool, found_flags, false);

    const found_entries = common.allocator.alloc(common.FullEntry, search_paths.len)
        catch oom();

    const is_multifile = std.mem.endsWith(u8, paths[0], "_dir.vpk");
    
    const entries = common.getAllEntries(archive.tree_data);

    for (entries) |entry| {
        var name_buf: [std.os.PATH_MAX]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "{}", .{entry})
            catch oom();
        
        for (search_paths, 0..) |fname, i| {
            if (std.mem.eql(u8, name, fname)) {
                found_flags[i] = true;
                found_entries[i] = entry;
            }
        }
    }

    for (found_flags, 0..) |f, i| {
        if (!f) {
            fatal("file \"{s}\" not found", .{search_paths[i]});
        }
    }

    // Local files first
    // Also start looking for external archive indices
    var max_archive_index: ?u16 = null;
    for (found_entries) |entry| {
        if (entry.data.archive != 0x7fff) {
            if (!is_multifile) {
                fatal("didnt expect an external entry, index file does not end with _dir", .{});
            }

            if (
                max_archive_index == null
                or entry.data.archive > max_archive_index.?
            ) {
                max_archive_index = entry.data.archive;
            }
            continue;
        }
        extractEntry(
            entry,
            entryPreloadData(entry),
            entryMainData(entry, archive.file_data)
        );
    }

    if (!is_multifile)
        return;

    var archive_i: u16 = 0;
    while (archive_i <= max_archive_index.?) : (archive_i += 1) {
        var any_match = false;
        for (found_entries) |entry| {
            if (entry.data.archive == archive_i) {
                any_match = true;
                break;
            }
        }
        if (!any_match) {
            continue;
        }

        // Open file_[archive_idx].vpk
        var ex_name_buf: [std.os.PATH_MAX]u8 = undefined;
        const ex_name =
            std.fmt.bufPrintZ(
                &ex_name_buf,
                "{s}_{:0>3}.vpk", // {:0>3} = three digit 0-padded
                .{trimArchiveExtension(paths[0]), archive_i}
            ) catch oom();
            

        // Since the user probably asked for very few files,
        // don't read the entire file into memory.
        // We can spare a few more syscalls.
        const ex_file = std.fs.cwd().openFile(ex_name, .{})
            catch |err| fatal("Error opening '{s}': {}", .{ex_name, err});
        defer ex_file.close();

        for (found_entries) |entry| {
            if (entry.data.archive == archive_i) {
                const data = common.allocator.alloc(u8, entry.data.length)
                    catch oom();

                ex_file.seekTo(entry.data.offset)
                    catch |err| fatal("{}", .{err});

                const len = ex_file.readAll(data)
                    catch |err| fatal("{}", .{err});

                if (entry.data.length != len) {
                    fatal("Where's the data?", .{});
                }
                extractEntry(entry, entryPreloadData(entry), data);
            }
        }
    }

}

//TODO: make extract and unpack directly share some functions.

fn extractEntry(entry: common.FullEntry, preload_data: []const u8, main_data: []const u8) void {
    //if (!common.isBlank(entry.directory))
    //    std.fs.cwd().makePath(entry.directory)
    //        catch |err| fatal("Error creating path: {}", .{err});

    var file_name_buf: [std.os.PATH_MAX]u8 = undefined;
    const file_name =
        if (common.isBlank(entry.extension))
            entry.filename
        else
            std.fmt.bufPrint(&file_name_buf, "{s}.{s}", .{entry.filename, entry.extension})
                catch oom();

    const output_file = std.fs.cwd().createFile(file_name, .{})
        catch |err| fatal("Error creating file: {}", .{err});
    defer output_file.close();
    
    if (entry.data.preload != 0)
        output_file.writeAll(preload_data)
            catch |err| fatal("error writing to file: {}", .{err});

    output_file.writeAll(main_data)
        catch |err| fatal("error writing to file: {}", .{err});

}

fn entryMainData(entry: common.FullEntry, src: []const u8) []const u8 {
    return src[
        entry.data.offset..entry.data.offset+entry.data.length
    ];
}

fn entryPreloadData(entry: common.FullEntry) []const u8 {
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
