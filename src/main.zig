const std = @import("std");
const common = @import("common.zig");

comptime {
    if (@import("builtin").cpu.arch.endian() == .Big) {
        @compileError("Not Big-Endian compatible");
    }
}

pub const std_options = struct {
    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = scope;
        _ = level;

        const prefix = "vpacker: ";

        std.debug.getStderrMutex().lock();
        defer std.debug.getStderrMutex().unlock();
        const stderr = std.io.getStdErr().writer();
        nosuspend stderr.print(prefix ++ format ++ "\n", args)
            catch return;
    }
};



fn usage() noreturn {
    std.io.getStdErr().writeAll(
\\Usage:
\\  vpacker list <file.vpk>
\\  vpacker extract <file.vpk> <file(s) to extract>
\\  vpacker pack <directory>
\\  vpacker unpack <file.vpk>
\\  vpacker check <file.vpk>
\\
    ) catch {};
    std.process.exit(1);
}

const oom = common.oom;
const fatal = common.fatal;

pub fn main() void {
    const args = std.process.argsAlloc(common.allocator)
        catch oom();

    if (args.len < 3) {
        usage();
    }

    const command_str = args[1];
    const filenames = args[2..];

    const eql = std.mem.eql;
    
    if (eql(u8, command_str, "list"))
        list(filenames)
    else if (eql(u8, command_str, "extract"))
        extract(filenames)
    else if (eql(u8, command_str, "pack"))
        pack(filenames)
    else if (eql(u8, command_str, "unpack"))
        unpack(filenames)
    else if (eql(u8, command_str, "check"))
        check(filenames)
    else
        usage();
}



fn check(filenames: [][:0]const u8) void {
    if (filenames.len != 1) {
        fatal("Expected only one argument: archive to check", .{});
    }

    if (!std.ascii.endsWithIgnoreCase(filenames[0], ".vpk")) {
        fatal("archive should have .vpk extension", .{});
    }

    @import("check.zig").check(filenames[0]);
}

fn pack(filenames: [][:0]const u8) void {
    if (filenames.len != 1) {
        fatal("Expected only one argument: directory to be packed", .{});
    }

    @import("pack.zig").pack(filenames[0]);
}

fn unpack(filenames: [][:0]const u8) void {
    if (filenames.len != 1) {
        fatal("Expected only one file", .{});
    }

    @import("unpack.zig").unpack(filenames[0]);
}

fn list(filenames: [][:0]const u8) void {
    if (filenames.len != 1) {
        fatal("Expected only one file", .{});
    }

    if (!std.ascii.endsWithIgnoreCase(filenames[0], ".vpk")) {
        fatal("archive should have .vpk extension", .{});
    }

    @import("list.zig").list(filenames[0]);
}

fn extract(filenames: [][:0]const u8) void {
    if (filenames.len < 2) {
        fatal("Need at least two names: path to the VPK, and one or more files to extract from it", .{});
    }
    if (!std.ascii.endsWithIgnoreCase(filenames[0], ".vpk")) {
        fatal("archive should have .vpk extension", .{});
    }

    @import("extract.zig").extract(filenames);
}

fn pause() void {
    std.io.getStdIn().reader().skipUntilDelimiterOrEof('\n')
        catch @panic("error reading stdin");
}

