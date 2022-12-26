//todo: rewrite to be less convoluted

const std = @import("std");
const common = @import("common.zig");

const fatal = common.fatal;
const oom = common.oom;

var tree: std.ArrayListUnmanaged(u8) = .{};
var file_data: std.ArrayListUnmanaged(u8) = .{};

var files: [][]const u8 = undefined;

var seen_extensions: std.ArrayListUnmanaged([]const u8) = .{};
var seen_blank_extension: bool = false;

var seen_paths: std.ArrayListUnmanaged([]const u8) = .{};
var seen_blank_path: bool = false;
const print = std.debug.print;
pub fn pack(directory_path: [:0]const u8) void {

    const start_cwd = std.fs.cwd().openDir(".", .{})
        catch |err| fatal("openDir: {}", .{err});

    const dir_fd = std.fs.cwd().openDirZ(
        directory_path,
        .{},
        true, // iterable (why is this here and not in options struct)
    ) catch |err| fatal("openDir: {}", .{err});
    _ = dir_fd;

    // Resolve full path.
    // Removes problematic bytes like slashes and dots
    var realpath_buf: [std.os.PATH_MAX]u8 = undefined;
    const realpath = std.fs.realpathZ(directory_path, &realpath_buf)
        catch |err| fatal("{}", .{err});

    const top_dir = trimParentDirs(realpath);


    std.os.chdirZ(directory_path)
        catch |err| fatal("chdir: {}", .{err});
    std.os.chdirZ("..") catch unreachable;
    files = allFilesInDirectoryRecursive(top_dir);

    for (files) |file| {
        const ext = getExtFromPath(file);
        if (hasSeenExt(ext))
            continue;
        markExtAsSeen(ext);

        //print("ext: {s}\n", .{ext orelse "(blank)"});

        if (ext != null)
            addSliceToTree(ext.?)
        else
            // blank extension
            addByteToTree(' ');

        // string terminator
        addByteToTree(0);

        paths(ext);
    }

    // end of tree
    addByteToTree(0);

    const archive_name = std.fmt.allocPrintZ(common.allocator, "{s}.vpk", .{top_dir})
        catch oom();
    const archive_file = start_cwd.createFileZ(archive_name, .{.exclusive=true})
        catch |err| fatal("createFile: {}", .{err});

    
    var header_buf: [28]u8 = undefined;
    var header_stream = std.io.fixedBufferStream(&header_buf);
    const writer = header_stream.writer();

    // Identifier
    writer.writeIntLittle(u32, common.magic) catch unreachable;
    // Version (2)
    writer.writeIntLittle(u32, 2) catch unreachable;
    // Tree size
    writer.writeIntLittle(u32, @intCast(u32, tree.items.len)) catch unreachable;
    // File data size
    writer.writeIntLittle(u32, @intCast(u32, file_data.items.len)) catch unreachable;
    
    // Some bullshit
    writer.writeIntLittle(u32, 0) catch unreachable;
    writer.writeIntLittle(u32, 0) catch unreachable;
    writer.writeIntLittle(u32, 0) catch unreachable;

    archive_file.writeAll(&header_buf)
        catch |err| fatal("File.writeAll: {}", .{err});

    archive_file.writeAll(tree.items)
        catch |err| fatal("File.writeAll: {}", .{err});

    archive_file.writeAll(file_data.items)
        catch |err| fatal("File.writeAll: {}", .{err});

    archive_file.close();
}

fn paths(ext: ?[]const u8) void {
    resetSeenPaths();
    for (files) |file| {
        // only files with this extension
        if (!optionalStringMatch(ext, getExtFromPath(file)))
            continue;

        //std.debug.print(">{s}\n<{s}\n", .{getParentPath(file).?, getRelativeParentPath(file).?});

        const path = getRelativeParentPath(file);
        if (hasSeenPath(path))
            continue;
        markPathAsSeen(path);

        //print("path: {s}\n", .{path orelse "(blank)"});

        if (path != null)
            addSliceToTree(path.?)
        else
            addByteToTree(' ');

        addByteToTree(0);

        items(path, ext);
    }

    // End of this extension
    addByteToTree(0);
}
const max_single_file_size = 100_000_000;
// Remove the vpkname/ top directory
// Ex: with `vpacker pack stuff`:
//  stuff/materials/thing.vtf
//  stuff/models/thing.vvd
// Removes 'stuff/'
//  materials/thing.vtf
//  models/thing.vvd
fn getRelativeParentPath(full: []const u8) ?[]const u8 {
    const cut = full[std.mem.indexOfScalar(u8, full, '/').?+1..];
    return getParentPath(cut);
}

fn items(path: ?[]const u8, ext: ?[]const u8) void {
    for (files) |file| {
        if (!optionalStringMatch(ext, getExtFromPath(file)))
            continue;
        if (!optionalStringMatch(path, getRelativeParentPath(file)))
            continue;

        const fname = getFileName(file);
        //print("file: {s}\n", .{fname});

        addSliceToTree(fname);
        addByteToTree(0);

        const data = std.fs.cwd().readFileAlloc(
            common.allocator,
            file,
            max_single_file_size,
        ) catch |err| switch (err) {
            error.FileNotFound => @panic("shouldnt happen???"),
            error.FileTooBig => fatal("File exceeds size limit of {} bytes", .{max_single_file_size}),
            error.OutOfMemory => oom(),
            else => fatal("Something happened: {}", .{err}),
        };

        // My first time ever using std.hash
        const crc: u32 = std.hash.Crc32.hash(data);

        // CRC
        addIntToTree(u32, crc);

        // # Preload Bytes
        // None of that tomfoolery here
        addIntToTree(u16, 0);

        // Archive Index
        addIntToTree(u16, 0x7fff);

        // Data Offset
        addIntToTree(u32, @intCast(u32, file_data.items.len));
        // Data Length
        addIntToTree(u32, @intCast(u32, data.len));

        // Terminator (always 0xFFFF)
        addIntToTree(u16, 0xFFFF);

        file_data.appendSlice(common.allocator, data) catch oom();

        common.allocator.free(data);
    }

    addByteToTree(0);
}

fn addByteToTree(byte: u8) void {
    tree.append(common.allocator, byte) catch oom();
}

fn addSliceToTree(data: []const u8) void {
    tree.appendSlice(common.allocator, data) catch oom();
}

fn addIntToTree(comptime T: type, int: T) void {
    addSliceToTree(std.mem.asBytes(&int));
}

fn markExtAsSeen(ext: ?[]const u8) void {
    if (ext == null)
        seen_blank_extension = true;

    seen_extensions.append(common.allocator, ext.?)
        catch oom();
}

fn markPathAsSeen(path: ?[]const u8) void {
    if (path == null)
        seen_blank_path = true
    else
        seen_paths.append(common.allocator, path.?)
            catch oom();
}

fn getFileName(path: []const u8) []const u8 {
    const last_slash = std.mem.lastIndexOfScalar(u8, path, '/');
    if (last_slash == null)
        return path;

    const last_dot = std.mem.lastIndexOfScalar(u8, path, '.');
    if (last_dot == null)
        return path[last_slash.?+1..]
    else
        return path[last_slash.?+1..last_dot.?];
}

fn resetSeenPaths() void {
    seen_paths.deinit(common.allocator);
    seen_paths = .{};
    seen_blank_extension = false;
}

fn hasSeenPath(path: ?[]const u8) bool {
    if (path == null and seen_blank_path)
        return true;
    
    for (seen_paths.items) |seen_path|
        if (std.mem.eql(u8, path.?, seen_path))
            return true;

    return false;
}

fn hasSeenExt(ext: ?[]const u8) bool {
    if (ext == null and seen_blank_extension)
        return true;

    for (seen_extensions.items) |seen_ext|
        if (std.mem.eql(u8, ext.?, seen_ext))
            return true;

    return false;
}

fn optionalStringMatch(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null and b == null)
        return true;
    if (a != null and b != null)
        return std.mem.eql(u8, a.?, b.?);

    return false;
}

fn getExtFromPath(path: []const u8) ?[]const u8 {
    const last_dot = std.mem.lastIndexOfScalar(u8, path, '.')
        orelse return null;
    
    const slice = path[last_dot+1..];

    return slice;
}

//TODO: Does Windows need special behaviour?
fn getParentPath(full: []const u8) ?[]const u8 {
    const last_slash = std.mem.lastIndexOfScalar(u8, full, '/')
        orelse return null;
    
    const slice = full[0..last_slash];

    return slice;
}

fn trimParentDirs(name: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, name, '/')) |index| {
        return name[index+1..];
    }
    return name;
}

fn allFilesInDirectoryRecursive(
    dir_path: []const u8,
) [][]u8 {
    const S = struct {
        result: std.ArrayListUnmanaged([]u8),

        fn descend(self: *@This(), path: []const u8) void {
            const dir = std.fs.cwd().openIterableDir(path, .{})
                    catch |err| fatal("Error opening '{s}': {}", .{path, err});
    
            var iter = dir.iterate();
            while (true) {
                const entry = iter.next()
                    catch |err| fatal("what? {}", .{err})
                    orelse break;

                const fullname =
                        std.fmt.allocPrintZ(common.allocator, "{s}/{s}", .{path, entry.name}) catch oom();

                
                switch (entry.kind) {
                    .File => {
                        self.result.append(common.allocator, fullname) catch oom();
                    },
                    .Directory => {
                        self.descend(fullname);
                    },
                    else => std.debug.print("[!!!] ignoring {s}: is a {}", .{fullname, entry.kind}),
                }
            }
        }
    };

    var s = S {.result = .{}};
    s.descend(dir_path);
    return s.result.items;
}
