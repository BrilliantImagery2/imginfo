//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");
const print = std.debug.print;
const allocator = std.heap.page_allocator;

const JpgError = @import("errors.zig").JpgError;
const Marker = @import("constants.zig").Marker;

pub const JpgReader = struct {
    data: []const u8,
    position: usize = 0,

    pub fn init(data: []const u8) JpgReader {
        return .{ .data = data };
    }

    pub inline fn readInt(self: *JpgReader, comptime T: type) T {
        const value = self.peekInt(T);
        self.position += @sizeOf(T);
        return value;
    }

    pub inline fn peekInt(self: *JpgReader, comptime T: type) T {
        if (T == u8) return self.data[self.position];
        const size = @sizeOf(T);
        var value: T = 0;
        if (!(self.position + size < self.data.len)) {
            return 0;
        }
        for (self.data[self.position .. self.position + size][0..size]) |b| {
            value = value << 8 | b;
        }
        return value;
    }

    pub inline fn hasNext(self: JpgReader) bool {
        return self.position - 1 < self.data.len;
    }

    pub inline fn has2Next(self: JpgReader) bool {
        if (self.position > 10) {
            return self.position - 10 < self.data.len;
        }
        return true;
    }

    pub inline fn skip(self: *JpgReader) void {
        self.position += 1;
    }
};

pub fn main() !void {
    if (std.os.argv.len == 1) {
        std.debug.print("{s}\n", .{"don't forget to include a path."});
        return;
    }
    const file_path = std.mem.span(std.os.argv[1]);
    const file = open_file(file_path);

    var reader = JpgReader.init(file);
    try is_jpg(&reader);

    while (reader.hasNext()) {
        switch (reader.peekInt(u16)) {
            0...0xFF01, 0xFFFF => {
                reader.skip();
            },
            @intFromEnum(Marker.SOF0), @intFromEnum(Marker.SOF3) => {
                parseFrameHeader(&reader);
            },
            @intFromEnum(Marker.DHT) => {
                parseHuffmanTable(&reader);
            },
            @intFromEnum(Marker.SOS) => {
                parseScanHeader(&reader);
            },
            else => {
                reader.skip();
            },
        }
    }
}

fn parseScanHeader(reader: *JpgReader) void {
    print("Scan Header, B.2.3, p.37{s}\n", .{""});
    const marker = reader.readInt(u16);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X},  {d: >5}\n", .{ "Marker:", "SOS", "u16", marker, marker });
    const l_s = reader.readInt(u16);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Scan header length:", "Ls", "u16", l_s, l_s });
    const n_s = reader.readInt(u8);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Number of image comps in scan:", "Ns", "u8", n_s, n_s });
    //print(" {}", .{" \n"});

    for (0..n_s) |_| {
        const c_sj = reader.readInt(u8);
        const t_dj_t_aj = reader.readInt(u8);
        const t_dj = t_dj_t_aj >> 4;
        const t_aj = t_dj_t_aj & 0xF;
        print("    {s: <30}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Scan comp selector:", "Csj", "u8", c_sj, c_sj });
        print("    {s: <30}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Entropy coding table dest:", "Tdj", "u4", t_dj, t_dj });
        print("    {s: <30}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Zero for lossless:", "Taj", "u4", t_aj, t_aj });
        //print("{}", "\n");
    }

    const s_s = reader.readInt(u8);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Predictor selector:", "Ss", "u8", s_s, s_s });
    const s_e = reader.readInt(u8);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Zero for lossless:", "Se", "u8", s_e, s_e });
    const a_h_a_l = reader.readInt(u8);
    const a_h = a_h_a_l >> 4;
    const a_l = a_h_a_l & 0xF;
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Zero for lossless:", "Ah", "u4", a_h, a_h });
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Point Transform, Pt:", "Al", "u4", a_l, a_l });
}

fn parseHuffmanTable(reader: *JpgReader) void {
    print("Huffman table, B.2.4.2, p.40{s}\n", .{""});
    const marker = reader.readInt(u16);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X},  {d: >5}\n", .{ "Marker:", "DHT", "u16", marker, marker });
    const l_h = reader.readInt(u16);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Huffman table def len:", "Lh", "u16", l_h, l_h });
    const t_c_t_h = reader.readInt(u8);
    const t_c = t_c_t_h >> 4;
    const t_h = t_c_t_h & 0x0F;
    print("  {s: <32}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Table class (not used):", "Tc", "u4", t_c, t_c });
    print("  {s: <32}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Huffman table destination ID:", "Th", "u4", t_h, t_h });

    var code_lengths: [16][17]?u8 = .{.{null} ** 17} ** 16;
    var lengths = std.AutoArrayHashMap(u8, u8).init(allocator);
    defer lengths.deinit();
    for (0..16) |code_length_index| {
        const l_i = reader.readInt(u8);
        if (l_i > 0) {
            lengths.put(@intCast(code_length_index), l_i) catch unreachable;
        }
    }
    for (lengths.keys(), lengths.values()) |code_length_index, l_i| {
        for (0..l_i) |i| {
            code_lengths[code_length_index][i] = reader.readInt(u8);
        }
    }

    var code: usize = 1;
    var table = std.AutoHashMap(u8, usize).init(allocator);
    for (code_lengths, 0..) |row, index| {
        var values = std.ArrayList(u8).init(allocator);
        defer values.deinit();
        for (row) |item| {
            if (item) |value| {
                values.append(value) catch unreachable;
            }
        }
        if (values.items.len > 0) {
            var current_value_index: usize = 0;
            while (current_value_index <= values.items.len) {
                code = code << @intCast(index + 1 - (numberOfUsedBits(code) - 1));
                if (current_value_index > 0) {
                    while (true) {
                        const removed = code & 1;
                        code >>= 1;
                        if (removed == 0 or numberOfUsedBits(code) <= 1) {
                            break;
                        }
                    }
                    code = (code << 1) + 1;
                    code = code << @intCast((index + 1) - (numberOfUsedBits(code) - 1));
                }
                if (values.items.len > current_value_index) {
                    //table.put(code, values.items[current_value_index]) catch unreachable;
                    table.put(values.items[current_value_index], code) catch unreachable;
                }
                current_value_index += 1;
            }
        }
    }

    for (code_lengths, 1..) |cl, i| {
        if (cl[0] != null) {
            var l_i: usize = 0;
            for (cl) |c| {
                if (c != null) {
                    l_i += 1;
                }
            }
            print("    Numb of codes of len {d: <9}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ i, "Li", "u8", l_i, l_i });
            for (cl) |c| {
                if (c) |v| {
                    //print("      {s: <28}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Value assoc w Huff code:", "Vij", "u8", v, v });
                    const cd = table.get(v).?;
                    const numb_bits = numberOfUsedBits(cd);
                    var code_str = std.ArrayList(u8).init(allocator);
                    for (1..numb_bits) |j| {
                        const offset = numb_bits - j - 1;
                        const b = (cd >> @intCast(offset)) & 1;
                        if (b == 0) {
                            code_str.append('0') catch unreachable;
                        } else {
                            code_str.append('1') catch unreachable;
                        }
                    }
                    print("        {s: <10}  {d: >2},  {s},    {d: >2}, {s}: {s}\n", .{
                        "SSSS: (Vij)",
                        v,
                        "Code:",
                        cd,
                        "Code:",
                        code_str.items,
                    });
                }
            }
        } else {
            const l_i = 0;
            print("    Numb of codes of len {d: <9}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ i, "Li", "u8", l_i, l_i });
        }
    }
}

fn parseFrameHeader(reader: *JpgReader) void {
    print("Frame Header, B.2.2, p.35{s}\n", .{""});
    const marker = reader.readInt(u16);
    switch (marker) {
        @intFromEnum(Marker.SOF0) => {
            print("  {s: <32}  {s: >4},  {s: >3},  0x{X},  {d: >5}\n", .{ "Marker:", "SOF0", "u16", marker, marker });
            print("    Lossy Jpg encoding{s}\n", .{""});
        },
        @intFromEnum(Marker.SOF3) => {
            print("  {s: <32}  {s: >4},  {s: >3},  0x{X},  {d: >5}\n", .{ "Marker:", "SOF3", "u16", marker, marker });
            print("    Lossless Jpg encoding{s}\n", .{""});
        },
        else => {
            print("  Marker not implimented\n{s}", .{""});
        },
    }
    const l_f = reader.readInt(u16);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Frame header length:", "Lf", "u16", l_f, l_f });
    const p_ = reader.readInt(u8);
    print("  {s: <32}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Sample precision:", "P", "u8", p_, p_ });
    const y_ = reader.readInt(u16);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Number of lines:", "Y", "u16", y_, y_ });
    const x_ = reader.readInt(u16);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Numb of samples per line:", "X", "u16", x_, x_ });
    const n_f = reader.readInt(u8);
    print("  {s: <32}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Numb of image comps in frame:", "Nf", "u8", n_f, n_f });
    print("\n{s}", .{""});
    for (0..n_f) |_| {
        const c_i = reader.readInt(u8);
        print("    {s: <30}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Component identifier:", "Ci", "u8", c_i, c_i });
        const h_i_v_i = reader.readInt(u8);
        const h_i = h_i_v_i >> 4;
        const v_i = h_i_v_i & 0x0F;
        print("    {s: <30}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Horizontal sample factor:", "Hi", "u4", h_i, h_i });
        print("    {s: <30}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Vertical sample factor:", "Vi", "u4", v_i, v_i });
        const t_qi = reader.readInt(u8);
        print("    {s: <30}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Quant table dest selector:", "Tqi", "u4", t_qi, t_qi });
        print("\n{s}", .{""});
    }
}

fn is_jpg(reader: *JpgReader) JpgError!void {
    if (reader.readInt(u16) != @intFromEnum(Marker.SOI)) {
        return JpgError.InvalidSOI;
    }
}

fn open_file(file_path: []const u8) []u8 {
    //const allocator = std.heap.page_allocator;

    // Change the file path to the binary file you want to read.
    //const file_path = "tests/F-18.ljpg";

    // Open the file.
    var file = std.fs.cwd().openFile(file_path, .{}) catch unreachable;
    defer file.close();

    // Get the file size.
    const file_size = file.getEndPos() catch unreachable;

    // Allocate a buffer for the file contents.
    const buffer = allocator.alloc(u8, file_size) catch unreachable;
    // defer allocator.free(buffer);

    // Read the entire file into the buffer.
    const read_bytes = file.readAll(buffer) catch unreachable;
    if (read_bytes != file_size) {
        //return error.ReadError; // Custom error for incomplete read.
        unreachable;
    }

    return buffer[0..read_bytes];
}

pub fn numberOfUsedBits(value: usize) usize {
    return if (value == 0) 0 else std.math.log2(value) + 1;
}
