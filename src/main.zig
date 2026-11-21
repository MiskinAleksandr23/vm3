const std = @import("std");
const c = @import("lama_disassembler");

const assert = std.debug.assert;

const bytecode_header_size = 3 * @sizeOf(i32);
const public_symbol_size = 2 * @sizeOf(i32) + @sizeOf(u8);

fn readI32(data: []const u8, offset: usize) i32 {
    return std.mem.readInt(i32, data[offset..][0..4], .little);
}

const Bytecode = struct {
    strings_size: usize,
    terminated_strings_size: usize,
    publics: []const u8,
    code: []const u8,
};

fn parseBytecode(bytes: []const u8) !Bytecode {
    if (bytes.len < bytecode_header_size) return error.TruncatedHeader;
    const string_size = readI32(bytes, 0);
    const globals_count = readI32(bytes, 4);
    const public_count = readI32(bytes, 8);
    if (string_size < 0 or globals_count < 0 or public_count < 0) return error.NegativeHeaderField;

    const count: usize = @intCast(public_count);
    if (count > (bytes.len - bytecode_header_size) / public_symbol_size) return error.TruncatedPublicTable;
    const string_start = bytecode_header_size + count * public_symbol_size;
    const size: usize = @intCast(string_size);
    if (size > bytes.len - string_start) return error.TruncatedStringTable;
    const strings = bytes[string_start..][0..size];
    const terminated_size = if (std.mem.findScalarLast(u8, strings, 0)) |last| last + 1 else 0;
    const publics = bytes[bytecode_header_size..string_start];

    for (0..count) |index| {
        const symbol = publics[index * public_symbol_size ..][0..public_symbol_size];
        const name = readI32(symbol, 0);
        if (name < 0 or name >= size) return error.StringOffsetOutOfBounds;
        if (name >= terminated_size) return error.UnterminatedString;
        const value = readI32(symbol, 4);
        if (value < 0) return error.NegativePublicSymbolOffset;
        switch (symbol[8]) {
            0 => {},
            1 => if (value >= globals_count) return error.GlobalIndexOutOfBounds,
            else => return error.InvalidPublicSymbolType,
        }
    }
    return .{
        .strings_size = size,
        .terminated_strings_size = terminated_size,
        .publics = publics,
        .code = bytes[string_start + size ..],
    };
}

fn disassemblyContext(bytecode: Bytecode) c.LamaBytecode {
    return .{
        .code = bytecode.code.ptr,
        .code_size = bytecode.code.len,
        .strings_size = bytecode.strings_size,
        .terminated_strings_size = bytecode.terminated_strings_size,
    };
}

fn disassembleInstruction(
    bytecode: *const c.LamaBytecode,
    offset: usize,
    output: ?*c.FILE,
    written: [*c]usize,
) !c.LamaInstructionInfo {
    var info: c.LamaInstructionInfo = undefined;
    switch (c.lama_disassemble_instruction(output, bytecode, offset, &info, written)) {
        c.LAMA_DISASM_OK => return info,
        c.LAMA_DISASM_TRUNCATED_INSTRUCTION => return error.TruncatedInstruction,
        c.LAMA_DISASM_INVALID_OPCODE => return error.InvalidOpcode,
        c.LAMA_DISASM_STRING_OFFSET_OUT_OF_BOUNDS => return error.StringOffsetOutOfBounds,
        c.LAMA_DISASM_UNTERMINATED_STRING => return error.UnterminatedString,
        c.LAMA_DISASM_NEGATIVE_CAPTURE_COUNT => return error.NegativeCaptureCount,
        c.LAMA_DISASM_INVALID_CAPTURE_SCOPE => return error.InvalidCaptureScope,
        c.LAMA_DISASM_INCORRECT_OFFSET => return error.IncorrectOffset,
        c.LAMA_DISASM_WRITE_FAILED => return error.WriteFailed,
        else => unreachable,
    }
}

const Idiom = struct {
    offset: u32,
    len: u32,

    fn bytes(self: Idiom, code: []const u8) []const u8 {
        return code[self.offset..][0..self.len];
    }
};

const IdiomCtx = struct {
    code: []const u8,

    pub fn hash(self: IdiomCtx, idiom: Idiom) u64 {
        return std.hash.Wyhash.hash(0, idiom.bytes(self.code));
    }

    pub fn eql(self: IdiomCtx, lhs: Idiom, rhs: Idiom) bool {
        return std.mem.eql(u8, lhs.bytes(self.code), rhs.bytes(self.code));
    }
};

const Frequency = struct {
    idiom: Idiom,
    count: u32,

    pub fn lessThan(code: []const u8, lhs: Frequency, rhs: Frequency) bool {
        if (lhs.count != rhs.count) return lhs.count > rhs.count;
        return std.mem.order(u8, lhs.idiom.bytes(code), rhs.idiom.bytes(code)) == .lt;
    }
};

const Reachable = struct {
    starts: std.bit_set.Dynamic,
    block_starts: std.bit_set.Dynamic,

    fn deinit(self: *Reachable, alloc: std.mem.Allocator) void {
        self.starts.deinit(alloc);
        self.block_starts.deinit(alloc);
    }

    fn addTarget(self: *Reachable, alloc: std.mem.Allocator, pending: *std.ArrayList(u32), target: i32) !void {
        if (target < 0) return error.IncorrectOffset;
        if (target >= self.starts.bit_length) return error.IncorrectOffset;

        const offset: u32 = @intCast(target);
        if (self.block_starts.isSet(offset)) {
            return;
        }
        self.block_starts.set(offset);
        if (!self.starts.isSet(offset)) {
            try pending.append(alloc, offset);
        }
    }
};

fn analyze(alloc: std.mem.Allocator, bytecode: Bytecode) !Reachable {
    const decoder = disassemblyContext(bytecode);
    var starts = try std.bit_set.Dynamic.initEmpty(alloc, bytecode.code.len);
    errdefer starts.deinit(alloc);
    var block_starts = try std.bit_set.Dynamic.initEmpty(alloc, bytecode.code.len);
    errdefer block_starts.deinit(alloc);
    var reachable = Reachable{ .starts = starts, .block_starts = block_starts };
    var pending: std.ArrayList(u32) = .empty;
    defer pending.deinit(alloc);

    const pbs = bytecode.publics.len / public_symbol_size;
    for (0..pbs) |index| {
        const symbol = bytecode.publics[index * public_symbol_size ..][0..public_symbol_size];
        if (symbol[8] == 0) try reachable.addTarget(alloc, &pending, readI32(symbol, 4));
    }
    while (pending.pop()) |root| {
        var offset: usize = root;
        while (true) {
            if (offset >= bytecode.code.len) return error.TruncatedInstruction;
            if (reachable.starts.isSet(offset)) break;
            const info = try disassembleInstruction(&decoder, offset, null, null);
            reachable.starts.set(offset);
            if (info.target >= 0) {
                try reachable.addTarget(alloc, &pending, info.target);
            }
            if (!info.continues) break;
            offset += info.size;
        }
    }

    var it = reachable.starts.iterator(.{});
    var end: usize = 0;
    while (it.next()) |offset| {
        if (offset < end) return error.IncorrectOffset;
        end = offset + (try disassembleInstruction(&decoder, offset, null, null)).size;
    }
    return reachable;
}

fn frequenciesOfLength(alloc: std.mem.Allocator, bytecode: Bytecode, reachable: Reachable, length: usize) ![]Frequency {
    const decoder = disassemblyContext(bytecode);
    var freqs = std.HashMap(
        Idiom,
        u32,
        IdiomCtx,
        std.hash_map.default_max_load_percentage,
    ).initContext(alloc, .{ .code = bytecode.code });
    defer freqs.deinit();

    var it = reachable.starts.iterator(.{});
    while (it.next()) |start| {
        var end = start;
        for (0..length) |index| {
            if (end >= bytecode.code.len or !reachable.starts.isSet(end)) break;
            if (index != 0 and reachable.block_starts.isSet(end)) break;
            const info = try disassembleInstruction(&decoder, end, null, null);
            end += info.size;
            if (index + 1 == length) {
                const entry = try freqs.getOrPut(.{ .offset = @intCast(start), .len = @intCast(end - start) });
                if (!entry.found_existing) entry.value_ptr.* = 0;
                entry.value_ptr.* += 1;
            }
            if (!info.continues or info.returns_after) break;
        }
    }
    const rows = try alloc.alloc(Frequency, freqs.count());
    var entries = freqs.iterator();
    for (rows) |*row| {
        const entry = entries.next().?;
        row.* = .{ .idiom = entry.key_ptr.*, .count = entry.value_ptr.* };
    }
    return rows;
}

fn countFrequencies(alloc: std.mem.Allocator, bytecode: Bytecode, reachable: Reachable, up_to: usize) !std.ArrayList(Frequency) {
    assert(up_to > 0);
    var result: std.ArrayList(Frequency) = .empty;
    errdefer result.deinit(alloc);
    const max_length = @min(up_to, reachable.starts.count());

    for (0..max_length) |length_index| {
        const rows = try frequenciesOfLength(alloc, bytecode, reachable, length_index + 1);
        if (rows.len == 0) break;
        if (length_index == 0) {
            result = .fromOwnedSlice(rows);
            continue;
        }
        defer alloc.free(rows);
        try result.ensureTotalCapacityPrecise(alloc, result.items.len + rows.len);
        result.appendSliceAssumeCapacity(rows);
    }
    return result;
}

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const filename = args.next() orelse {
        std.debug.print("Usage: ./zig-out/bin/vm3 <file.bc> [n]\n", .{});
        return error.InvalidCommandLineArguments;
    };
    var up_to: usize = 2;
    if (args.next()) |up| {
        up_to = try std.fmt.parseInt(usize, up, 10);
        if (up_to == 0 or args.next() != null) return error.InvalidCommandLineArguments;
    }
    const file = try std.Io.Dir.cwd().openFile(init.io, filename, .{});
    defer file.close(init.io);
    const alloc = init.gpa;
    const stat = try file.stat(init.io);
    if (stat.size > std.math.maxInt(u32)) return error.BytecodeFileTooLarge;
    const bytes = try alloc.alloc(u8, @intCast(stat.size));
    defer alloc.free(bytes);
    var reader = file.readerStreaming(init.io, &.{});
    var read_offset: usize = 0;
    while (read_offset < bytes.len) {
        const end = read_offset + @min(bytes.len - read_offset, 16 * 1024 * 1024);
        try reader.interface.readSliceAll(bytes[read_offset..end]);
        read_offset = end;
    }
    const bytecode = try parseBytecode(bytes);
    var reachable = try analyze(alloc, bytecode);
    defer reachable.deinit(alloc);
    var freqs = try countFrequencies(alloc, bytecode, reachable, up_to);
    defer freqs.deinit(alloc);
    std.mem.sort(Frequency, freqs.items, bytecode.code, Frequency.lessThan);
    const decoder = disassemblyContext(bytecode);
    const output = if (@typeInfo(@TypeOf(c.stderr)) == .@"fn") c.stderr() else c.stderr;
    for (freqs.items) |entry| {
        var written: usize = 0;
        var offset: usize = entry.idiom.offset;
        const end = offset + entry.idiom.len;
        while (offset < end) {
            if (offset != entry.idiom.offset) {
                if (c.fputs("; ", output) < 0) return error.WriteFailed;
                written += 2;
            }
            var instruction_written: usize = 0;
            const info = try disassembleInstruction(&decoder, offset, output, &instruction_written);
            written += instruction_written;
            offset += info.size;
        }
        const padding: c_int = @intCast(50 - @min(written, 50));
        if (c.fprintf(output, "%*s %5u times\n", padding, @as([*c]const u8, ""), @as(c_uint, entry.count)) < 0) {
            return error.WriteFailed;
        }
    }
    if (c.fflush(output) != 0) return error.WriteFailed;
}
