const std = @import("std");
const Io = std.Io;

const assert = std.debug.assert;

const buffer_size: usize = 64 * 1024 * 1024;
const bytecode_header_size = 3 * @sizeOf(i32);
const public_symbol_size = 2 * @sizeOf(i32) + @sizeOf(u8);
var file_buffer: [buffer_size]u8 = undefined;

fn readI32(data: []const u8, offset: usize) i32 {
    return std.mem.readInt(i32, data[offset..][0..4], .little);
}

const Bytecode = struct {
    strings: []const u8,
    publics: []const u8,
    code: []const u8,
};

const Op = enum(u8) {
    Add = 0x01,
    Sub = 0x02,
    Mul = 0x03,
    Div = 0x04,
    Rem = 0x05,
    Less = 0x06,
    LessEqual = 0x07,
    Greater = 0x08,
    GreaterEqual = 0x09,
    Equal = 0x0A,
    NotEqual = 0x0B,
    And = 0x0C,
    Or = 0x0D,

    Const = 0x10,
    String = 0x11,
    Sexp = 0x12,
    StoreIndirect = 0x13,
    StoreElement = 0x14,
    Jump = 0x15,
    End = 0x16,
    Ret = 0x17,
    Drop = 0x18,
    Dup = 0x19,
    Swap = 0x1A,
    Elem = 0x1B,

    LoadGlobal = 0x20,
    LoadLocal = 0x21,
    LoadArg = 0x22,
    LoadClosure = 0x23,

    LoadAddressGlobal = 0x30,
    LoadAddressLocal = 0x31,
    LoadAddressArg = 0x32,
    LoadAddressClosure = 0x33,

    StoreGlobal = 0x40,
    StoreLocal = 0x41,
    StoreArg = 0x42,
    StoreClosure = 0x43,

    JumpZero = 0x50,
    JumpNonZero = 0x51,
    Begin = 0x52,
    CBegin = 0x53,
    Closure = 0x54,
    CallClosure = 0x55,
    Call = 0x56,
    Tag = 0x57,
    ArrayPattern = 0x58,
    Fail = 0x59,
    Line = 0x5A,

    StringEqual = 0x60,
    IsString = 0x61,
    IsArray = 0x62,
    IsSexp = 0x63,
    IsBoxed = 0x64,
    IsUnboxed = 0x65,
    IsClosure = 0x66,

    Read = 0x70,
    Write = 0x71,
    Length = 0x72,
    ToString = 0x73,
    Array = 0x74,

    Terminator = 0xFF,
    _,
};

fn readBounded(reader: *std.Io.File.Reader, buffer: []u8, comptime too_large: anyerror) ![]const u8 {
    const size = reader.interface.readSliceShort(buffer) catch return reader.err.?;
    if (size == buffer.len) {
        var extra: [1]u8 = undefined;
        const remaining = reader.interface.readSliceShort(&extra) catch return reader.err.?;
        if (remaining != 0) return too_large;
    }
    return buffer[0..size];
}

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
    const publics = bytes[bytecode_header_size..string_start];

    for (0..count) |index| {
        const symbol = publics[index * public_symbol_size ..][0..public_symbol_size];
        _ = try stringAt(strings, readI32(symbol, 0));
        const value = readI32(symbol, 4);
        if (value < 0) return error.NegativePublicSymbolOffset;
        switch (symbol[8]) {
            0 => {},
            1 => if (value >= globals_count) return error.GlobalIndexOutOfBounds,
            else => return error.InvalidPublicSymbolType,
        }
    }
    return .{ .strings = strings, .publics = publics, .code = bytes[string_start + size ..] };
}

fn stringAt(strings: []const u8, offset: i32) ![]const u8 {
    if (offset < 0 or offset >= strings.len) return error.StringOffsetOutOfBounds;
    const tail = strings[@intCast(offset)..];
    const end = std.mem.findScalar(u8, tail, 0) orelse return error.UnterminatedString;
    return tail[0..end];
}

fn decode(alloc: std.mem.Allocator, bytecode: Bytecode) ![]Instruction {
    const code = bytecode.code;
    var instructions: std.ArrayList(Instruction) = .empty;
    var offset: usize = 0;
    while (offset < code.len) {
        const opcode: Op = @fromBackingInt(code[offset]);
        if (opcode == Op.Terminator) {
            if (offset != code.len - 1) return error.TrailingBytesAfterTerminator;
            return instructions.toOwnedSlice(alloc);
        }

        const size: usize = switch (opcode) {
            Op.Add,
            Op.Sub,
            Op.Mul,
            Op.Div,
            Op.Rem,
            Op.Less,
            Op.LessEqual,
            Op.Greater,
            Op.GreaterEqual,
            Op.Equal,
            Op.NotEqual,
            Op.And,
            Op.Or,
            Op.StoreIndirect,
            Op.StoreElement,
            Op.End,
            Op.Ret,
            Op.Drop,
            Op.Dup,
            Op.Swap,
            Op.Elem,
            Op.StringEqual,
            Op.IsString,
            Op.IsArray,
            Op.IsSexp,
            Op.IsBoxed,
            Op.IsUnboxed,
            Op.IsClosure,
            Op.Read,
            Op.Write,
            Op.Length,
            Op.ToString,
            => 1,
            Op.Const,
            Op.String,
            Op.Jump,
            Op.LoadGlobal,
            Op.LoadLocal,
            Op.LoadArg,
            Op.LoadClosure,
            Op.LoadAddressGlobal,
            Op.LoadAddressLocal,
            Op.LoadAddressArg,
            Op.LoadAddressClosure,
            Op.StoreGlobal,
            Op.StoreLocal,
            Op.StoreArg,
            Op.StoreClosure,
            Op.JumpZero,
            Op.JumpNonZero,
            Op.CallClosure,
            Op.ArrayPattern,
            Op.Line,
            Op.Array,
            => 5,
            Op.Sexp, Op.Begin, Op.CBegin, Op.Call, Op.Tag, Op.Fail => 9,
            Op.Closure => blk: {
                if (code.len - offset < 9) return error.TruncatedInstruction;
                const count = readI32(code, offset + 5);
                if (count < 0) return error.NegativeCaptureCount;
                const captures: usize = @intCast(count);
                if (captures > (code.len - offset - 9) / 5) return error.TruncatedInstruction;
                break :blk 9 + captures * 5;
            },
            else => {
                return error.InvalidOpcode;
            },
        };
        if (size > code.len - offset) return error.TruncatedInstruction;
        const instruction = Instruction{ .offset = offset, .bytes = code[offset..][0..size] };
        switch (opcode) {
            Op.String, Op.Sexp, Op.Tag => _ = try stringAt(bytecode.strings, instruction.operand(0)),
            Op.Closure => {
                var descriptor: usize = 9;
                while (descriptor < size) : (descriptor += 5) {
                    if (instruction.bytes[descriptor] > 3) return error.InvalidCaptureScope;
                }
            },
            else => {},
        }
        try instructions.append(alloc, instruction);
        offset += size;
    }
    return error.MissingTerminator;
}

const Instruction = struct {
    const Self = @This();

    offset: usize,
    bytes: []const u8,

    pub fn opcode(self: *const Self) Op {
        return @fromBackingInt(@intCast(self.bytes[0]));
    }
    pub fn operand(self: *const Self, index: usize) i32 {
        return std.mem.readInt(i32, self.bytes[1 + 4 * index ..][0..4], .little);
    }
};

const Frequency = struct {
    const Self = @This();

    text: []const u8,
    count: usize,

    pub fn lessThan(_: void, lhs: Self, rhs: Self) bool {
        if (lhs.count != rhs.count) return lhs.count < rhs.count;
        return std.mem.order(u8, lhs.text, rhs.text) == .lt;
    }
};

fn formatInstruction(alloc: std.mem.Allocator, instruction: Instruction) ![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(alloc);
    defer buffer.deinit();
    const writer = &buffer.writer;
    const opcode = instruction.opcode();
    const opcode_byte = @backingInt(opcode);
    const binary = [_][]const u8{ "ADD", "SUB", "MUL", "DIV", "MOD", "LT", "LE", "GT", "GE", "EQ", "NE", "AND", "OR" };
    const scopes = [_][]const u8{ "GLOBAL", "LOCAL", "ARG", "CLOSURE" };

    switch (opcode) {
        Op.Add,
        Op.Sub,
        Op.Mul,
        Op.Div,
        Op.Rem,
        Op.Less,
        Op.LessEqual,
        Op.Greater,
        Op.GreaterEqual,
        Op.Equal,
        Op.NotEqual,
        Op.And,
        Op.Or,
        => try writer.writeAll(binary[opcode_byte - @backingInt(Op.Add)]),
        Op.Const => try writer.print("CONST {d}", .{instruction.operand(0)}),
        Op.String => try writer.print("STRING {d}", .{instruction.operand(0)}),
        Op.Sexp => try writer.print("SEXP {d} {d}", .{ instruction.operand(0), instruction.operand(1) }),
        Op.StoreIndirect => try writer.writeAll("STI"),
        Op.StoreElement => try writer.writeAll("STA"),
        Op.Jump => try writer.print("JMP L{d}", .{instruction.operand(0)}),
        Op.End => try writer.writeAll("END"),
        Op.Ret => try writer.writeAll("RET"),
        Op.Drop => try writer.writeAll("DROP"),
        Op.Dup => try writer.writeAll("DUP"),
        Op.Swap => try writer.writeAll("SWAP"),
        Op.Elem => try writer.writeAll("ELEM"),
        Op.LoadGlobal,
        Op.LoadLocal,
        Op.LoadArg,
        Op.LoadClosure,
        Op.LoadAddressGlobal,
        Op.LoadAddressLocal,
        Op.LoadAddressArg,
        Op.LoadAddressClosure,
        Op.StoreGlobal,
        Op.StoreLocal,
        Op.StoreArg,
        Op.StoreClosure,
        => {
            const names = [_][]const u8{ "LD", "LDA", "ST" };
            try writer.print("{s} {s} {d}", .{ names[(opcode_byte - @backingInt(Op.LoadGlobal)) >> 4], scopes[opcode_byte & 3], instruction.operand(0) });
        },
        Op.JumpZero, Op.JumpNonZero => try writer.print("{s} L{d}", .{ if (opcode == Op.JumpZero) @as([]const u8, "CJMPZ") else "CJMPNZ", instruction.operand(0) }),
        Op.Begin, Op.CBegin => try writer.print("{s} {d} {d}", .{ if (opcode == Op.Begin) @as([]const u8, "BEGIN") else "CBEGIN", instruction.operand(0), instruction.operand(1) }),
        Op.Closure => {
            try writer.print("CLOSURE L{d} {d}", .{ instruction.operand(0), instruction.operand(1) });
            var offset: usize = 9;
            while (offset < instruction.bytes.len) : (offset += 5) {
                try writer.print(" {s} {d}", .{ scopes[instruction.bytes[offset]], readI32(instruction.bytes, offset + 1) });
            }
        },
        Op.CallClosure => try writer.print("CALLC {d}", .{instruction.operand(0)}),
        Op.Call => try writer.print("CALL L{d} {d}", .{ instruction.operand(0), instruction.operand(1) }),
        Op.Tag => try writer.print("TAG {d} {d}", .{ instruction.operand(0), instruction.operand(1) }),
        Op.ArrayPattern => try writer.print("ARRAY {d}", .{instruction.operand(0)}),
        Op.Fail => try writer.print("FAIL {d} {d}", .{ instruction.operand(0), instruction.operand(1) }),
        Op.Line => try writer.print("LINE {d}", .{instruction.operand(0)}),
        Op.StringEqual, Op.IsString, Op.IsArray, Op.IsSexp, Op.IsBoxed, Op.IsUnboxed, Op.IsClosure => {
            const patterns = [_][]const u8{ "STRCMP", "STRING", "ARRAY", "SEXP", "BOXED", "UNBOXED", "CLOSURE" };
            try writer.print("PATT {s}", .{patterns[opcode_byte - @backingInt(Op.StringEqual)]});
        },
        Op.Read => try writer.writeAll("READ"),
        Op.Write => try writer.writeAll("WRITE"),
        Op.Length => try writer.writeAll("LENGTH"),
        Op.ToString => try writer.writeAll("TO_STRING"),
        Op.Array => try writer.print("MAKE_ARRAY {d}", .{instruction.operand(0)}),
        else => unreachable,
    }
    return buffer.toOwnedSlice();
}

fn countFrequencies(alloc: std.mem.Allocator, instructions: []const Instruction, can_start_pair: []const u8, up_to: usize) !std.ArrayList(Frequency) {
    assert(up_to > 0);
    var freqs: std.StringHashMap(usize) = .init(alloc);
    errdefer freqs.deinit();

    for (instructions) |instr| {
        const entry = try freqs.getOrPut(try formatInstruction(alloc, instr));
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
        }
        entry.value_ptr.* += 1;
    }
    for (2..up_to + 1) |batch_count| {
        for (0..instructions.len) |start| {
            if (can_start_pair[start] == 1 and start + batch_count <= instructions.len) {
                if (!std.mem.allEqual(u8, can_start_pair[start .. start + batch_count - 1], 1)) {
                    continue;
                }
                var text: std.ArrayList(u8) = .empty;
                for (start..start + batch_count) |idx| {
                    try text.appendSlice(alloc, try formatInstruction(alloc, instructions[idx]));
                    if (idx != start + batch_count - 1) try text.appendSlice(alloc, "; ");
                }
                const combined = try text.toOwnedSlice(alloc);
                const entry = try freqs.getOrPut(combined);
                if (!entry.found_existing) {
                    entry.value_ptr.* = 0;
                }
                entry.value_ptr.* += 1;
            }
        }
    }
    var result: std.ArrayList(Frequency) = try .initCapacity(alloc, 0);
    var it = freqs.iterator();
    while (it.next()) |entry| {
        const bytes = entry.key_ptr.*;
        const count = entry.value_ptr.*;
        try result.append(alloc, Frequency{ .text = bytes, .count = count });
    }
    return result;
}

fn analyze(alloc: std.mem.Allocator, instructions: []const Instruction, publics: []const u8) ![]u8 {
    assert(publics.len % public_symbol_size == 0);

    var instruction_starts: std.AutoHashMap(usize, usize) = .init(alloc);
    errdefer instruction_starts.deinit();

    var index: usize = 0;
    for (instructions) |instr| {
        try instruction_starts.put(instr.offset, index);
        index += 1;
    }

    const instr_count = instructions.len;
    const can_start_pair = try alloc.alloc(u8, instr_count);
    errdefer alloc.free(can_start_pair);
    @memset(can_start_pair, 1);

    for (0..publics.len / public_symbol_size) |idx| {
        const symbol = publics[idx * public_symbol_size ..][0..public_symbol_size];
        if (symbol[public_symbol_size - 1] == 0) {
            const offset: usize = @intCast(readI32(symbol, @sizeOf(i32)));
            if (instruction_starts.get(offset)) |to| {
                if (to != 0) {
                    can_start_pair[to - 1] = 0;
                }
            } else {
                return error.IncorrectOffset;
            }
        }
    }
    if (instr_count == 0) {
        return &.{};
    }

    for (0..instr_count) |idx| {
        switch (instructions[idx].opcode()) {
            .Jump, .JumpZero, .JumpNonZero, .Call, .Closure => {
                const to: usize = @intCast(instructions[idx].operand(0));
                if (instruction_starts.get(to)) |jmp_to| {
                    if (jmp_to != 0) {
                        can_start_pair[jmp_to - 1] = 0;
                    }
                } else {
                    return error.IncorrectOffset;
                }
                if (instructions[idx].opcode() == .Call) {
                    can_start_pair[idx] = 0;
                }
            },
            .CallClosure => {
                can_start_pair[idx] = 0;
            },
            else => continue,
        }
    }
    can_start_pair[instr_count - 1] = 0;
    return can_start_pair;
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
        assert(up_to >= 1);
    }
    const file = try std.Io.Dir.cwd().openFile(init.io, filename, .{});
    defer file.close(init.io);
    var reader = file.readerStreaming(init.io, &.{});
    const bytes = try readBounded(&reader, &file_buffer, error.BytecodeFileTooLarge);
    const bytecode = try parseBytecode(bytes);
    const instructions = try decode(init.arena.allocator(), bytecode);
    const can_start_pair = try analyze(init.arena.allocator(), instructions, bytecode.publics);
    const freqs = try countFrequencies(
        init.arena.allocator(),
        instructions,
        can_start_pair,
        up_to,
    );
    std.mem.sort(Frequency, freqs.items, {}, Frequency.lessThan);
    std.mem.reverse(Frequency, freqs.items);
    for (freqs.items) |entry| {
        std.debug.print("{s: <50} {d: >5} times\n", .{ entry.text, entry.count });
    }
}
