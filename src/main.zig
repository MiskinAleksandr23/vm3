const std = @import("std");
const Io = std.Io;

const assert = std.debug.assert;

const bytecode_header_size = 3 * @sizeOf(i32);
const public_symbol_size = 2 * @sizeOf(i32) + @sizeOf(u8);

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

fn readInstruction(code: []const u8, offset: usize) !Instruction {
    if (offset >= code.len) return error.TruncatedInstruction;
    const opcode: Op = @fromBackingInt(code[offset]);
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
        Op.Terminator,
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
        else => return error.InvalidOpcode,
    };
    if (size > code.len - offset) return error.TruncatedInstruction;
    return .{ .bytes = code[offset..][0..size] };
}

fn decodeInstruction(bytecode: Bytecode, offset: usize) !Instruction {
    const instruction = try readInstruction(bytecode.code, offset);
    try instruction.validate(bytecode);
    return instruction;
}

const FlowInfo = struct {
    continues: bool = true,
    target: ?i32 = null,
    returns_after: bool = false,
    countable: bool = true,
};

const Instruction = struct {
    const Self = @This();

    bytes: []const u8,

    pub fn opcode(self: *const Self) Op {
        return @fromBackingInt(@intCast(self.bytes[0]));
    }
    pub fn operand(self: *const Self, index: usize) i32 {
        return std.mem.readInt(i32, self.bytes[1 + 4 * index ..][0..4], .little);
    }

    fn flowInfo(self: *const Self) FlowInfo {
        return switch (self.opcode()) {
            .Jump => .{ .continues = false, .target = self.operand(0) },
            .JumpZero, .JumpNonZero, .Closure => .{ .target = self.operand(0) },
            .Call => .{ .target = self.operand(0), .returns_after = true },
            .CallClosure => .{ .returns_after = true },
            .End => .{ .continues = false },
            .Terminator => .{ .continues = false, .countable = false },
            else => .{},
        };
    }

    fn validate(self: *const Self, bytecode: Bytecode) !void {
        switch (self.opcode()) {
            .String, .Sexp, .Tag => _ = try stringAt(bytecode.strings, self.operand(0)),
            .Closure => {
                var descriptor: usize = 9;
                while (descriptor < self.bytes.len) : (descriptor += 5) {
                    if (self.bytes[descriptor] > 3) return error.InvalidCaptureScope;
                }
            },
            else => {},
        }
        if (self.flowInfo().target) |target| {
            if (target < 0) return error.IncorrectOffset;
            if (target >= bytecode.code.len) return error.IncorrectOffset;
        }
    }
};

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

fn formatInstruction(writer: *std.Io.Writer, bytecode: Bytecode, instruction_offset: usize) !usize {
    const instruction = try decodeInstruction(bytecode, instruction_offset);
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
        Op.Terminator => try writer.writeAll("STOP"),
        else => unreachable,
    }
    return instruction.bytes.len;
}

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
            const instruction = try decodeInstruction(bytecode, offset);
            reachable.starts.set(offset);
            const flow = instruction.flowInfo();
            if (flow.target) |target| {
                try reachable.addTarget(alloc, &pending, target);
            }
            if (!flow.continues) break;
            offset += instruction.bytes.len;
        }
    }

    var it = reachable.starts.iterator(.{});
    var end: usize = 0;
    while (it.next()) |offset| {
        if (offset < end) return error.IncorrectOffset;
        end = offset + (try readInstruction(bytecode.code, offset)).bytes.len;
    }
    return reachable;
}

fn countFrequencies(alloc: std.mem.Allocator, bytecode: Bytecode, reachable: Reachable, up_to: usize) !std.ArrayList(Frequency) {
    assert(up_to > 0);
    var result: std.ArrayList(Frequency) = .empty;
    errdefer result.deinit(alloc);
    const max_length = @min(up_to, reachable.starts.count());

    for (0..max_length) |length_index| {
        var freqs = std.HashMap(
            Idiom,
            u32,
            IdiomCtx,
            std.hash_map.default_max_load_percentage,
        ).initContext(
            alloc,
            .{ .code = bytecode.code },
        );
        defer freqs.deinit();

        var it = reachable.starts.iterator(.{});
        while (it.next()) |start| {
            var end = start;
            for (0..length_index + 1) |index| {
                if (end >= bytecode.code.len or !reachable.starts.isSet(end)) break;
                if (index != 0 and reachable.block_starts.isSet(end)) break;
                const instruction = try readInstruction(bytecode.code, end);
                const flow = instruction.flowInfo();
                if (!flow.countable) break;
                end += instruction.bytes.len;
                if (index == length_index) {
                    const entry = try freqs.getOrPut(.{ .offset = @intCast(start), .len = @intCast(end - start) });
                    if (!entry.found_existing) entry.value_ptr.* = 0;
                    entry.value_ptr.* += 1;
                }
                if (!flow.continues or flow.returns_after) break;
            }
        }
        if (freqs.count() == 0) break;
        try result.ensureTotalCapacityPrecise(alloc, result.items.len + freqs.count());
        var entries = freqs.iterator();
        while (entries.next()) |entry| {
            result.appendAssumeCapacity(.{ .idiom = entry.key_ptr.*, .count = entry.value_ptr.* });
        }
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
        assert(up_to >= 1);
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
        const end = @min(read_offset + 16 * 1024 * 1024, bytes.len);
        try reader.interface.readSliceAll(bytes[read_offset..end]);
        read_offset = end;
    }
    const bytecode = try parseBytecode(bytes);
    var reachable = try analyze(alloc, bytecode);
    defer reachable.deinit(alloc);
    var freqs = try countFrequencies(alloc, bytecode, reachable, up_to);
    defer freqs.deinit(alloc);
    std.mem.sort(Frequency, freqs.items, bytecode.code, Frequency.lessThan);
    var text: std.Io.Writer.Allocating = .init(alloc);
    defer text.deinit();
    for (freqs.items) |entry| {
        text.clearRetainingCapacity();
        var offset: usize = entry.idiom.offset;
        const end = offset + entry.idiom.len;
        while (offset < end) {
            if (offset != entry.idiom.offset) try text.writer.writeAll("; ");
            offset += try formatInstruction(&text.writer, bytecode, offset);
        }
        std.debug.print("{s: <50} {d: >5} times\n", .{ text.written(), entry.count });
    }
}
