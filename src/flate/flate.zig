const std = @import("std");
const math_bits = @import("../bits/index.zig");

pub const HuffmanEncoder = struct {
    condes: CodeList,
    freq_cache: ?LiteralNodeList,
    bit_cache: []i32,
    lns: ?LiteralNodeList,
    lfs: ?LiteralNodeList,
    allocator: *std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    // 2 bits:   type   0 = literal  1=EOF  2=Match   3=Unused
    // 8 bits:   xlength = length - MIN_MATCH_LENGTH
    // 22 bits   xoffset = offset - MIN_OFFSET_SIZE, or literal
    const length_shift = 22;
    const offset_mask = 1 << length_shift - 1;
    const type_mask = 3 << 30;
    const literal_type = 0 << 30;
    const match_type = 1 << 30;

    const max_bits_limit: i32 = 16;

    const max_code_len: usize = 16; // max length of Huffman code
    // The next three numbers come from the RFC section 3.2.7, with the
    // additional proviso in section 3.2.5 which implies that distance codes
    // 30 and 31 should never occur in compressed data.
    const max_num_lit: usize = 286;
    const max_num_dist: usize = 30;
    const num_codes: usize = 19; // number of codes in Huffman meta-code

    // The length code for length X (MIN_MATCH_LENGTH <= X <= MAX_MATCH_LENGTH)
    // is lengthCodes[length - MIN_MATCH_LENGTH]
    const length_codes = []u32{
        0, 1, 2, 3, 4, 5, 6, 7, 8, 8,
        9, 9, 10, 10, 11, 11, 12, 12, 12, 12,
        13, 13, 13, 13, 14, 14, 14, 14, 15, 15,
        15, 15, 16, 16, 16, 16, 16, 16, 16, 16,
        17, 17, 17, 17, 17, 17, 17, 17, 18, 18,
        18, 18, 18, 18, 18, 18, 19, 19, 19, 19,
        19, 19, 19, 19, 20, 20, 20, 20, 20, 20,
        20, 20, 20, 20, 20, 20, 20, 20, 20, 20,
        21, 21, 21, 21, 21, 21, 21, 21, 21, 21,
        21, 21, 21, 21, 21, 21, 22, 22, 22, 22,
        22, 22, 22, 22, 22, 22, 22, 22, 22, 22,
        22, 22, 23, 23, 23, 23, 23, 23, 23, 23,
        23, 23, 23, 23, 23, 23, 23, 23, 24, 24,
        24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
        24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
        24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
        25, 25, 25, 25, 25, 25, 25, 25, 25, 25,
        25, 25, 25, 25, 25, 25, 25, 25, 25, 25,
        25, 25, 25, 25, 25, 25, 25, 25, 25, 25,
        25, 25, 26, 26, 26, 26, 26, 26, 26, 26,
        26, 26, 26, 26, 26, 26, 26, 26, 26, 26,
        26, 26, 26, 26, 26, 26, 26, 26, 26, 26,
        26, 26, 26, 26, 27, 27, 27, 27, 27, 27,
        27, 27, 27, 27, 27, 27, 27, 27, 27, 27,
        27, 27, 27, 27, 27, 27, 27, 27, 27, 27,
        27, 27, 27, 27, 27, 28,
    };

    const offset_codes = []u32{
        0, 1, 2, 3, 4, 4, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7,
        8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9,
        10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
        11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11,
        12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
        12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
        13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
        13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
        14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
        14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
        14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
        14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
    };

    fn lengthCode(v: u32) u32 {
        return length_codes[@intCast(usize, v)];
    }

    fn offsetCode(off: u32) u32 {
        if (@intCast(usize, off) < offset_codes.len) {
            return offset_codes[@intCast(usize, off)];
        }
        if (@intCast(usize, off >> 7) < offset_codes.len) {
            return offset_codes[@intCast(usize, off >> 7)];
        }
        return offset_codes[@intCast(usize, off >> 14)] + 28;
    }

    const Token = struct {
        value: u32,
        fn literalToken(value: u32) token {
            return Token{ .value = literal_type + value };
        }
        fn matchToken(xlength: u32, xoffset: u32) token {
            return Token{ .value = match_type + xlength << length_shift + xoffset };
        }

        fn literal(self: Token) u32 {
            return self.value - literal_type;
        }

        fn offset(self: Token) u32 {
            return self.value & offset_mask;
        }

        fn length(self: Token) u32 {
            return (self.value - match_type) >> length_shift;
        }
    };

    /// A levelInfo describes the state of the constructed tree for a given depth.
    const LevelInfo = struct {
        /// Our level.  for better printing
        level: i32,

        /// The frequency of the last node at this level
        last_freq: i32,

        /// The frequency of the next character to add to this level
        next_char_freq: i32,

        /// The frequency of the next pair (from level below) to add to this level.
        /// Only valid if the "needed" value of the next lower level is 0.
        next_pair_freq: i32,

        /// The number of chains remaining to generate for this level before moving
        /// up to the next level
        needed: i32,
    };

    const Hcode = struct {
        code: u16,
        length: u16,
    };

    fn generateFixedLiteralEncoding(h: []Hcode) void {
        std.debug.assert(h.len >= max_num_lit);
        var ch: u16 = 0;
        while (ch < max_num_lit) : (ch += 1) {
            var bits: u16 = 0;
            var size: u16 = 0;
            if (ch < 144) {
                // size 8, 000110000  .. 10111111
                bits = ch + 48;
                size = 8;
            } else if (ch < 256) {
                // size 9, 110010000 .. 111111111
                bits = ch + 400 - 144;
                size = 9;
            } else if (ch < 280) {
                // size 7, 0000000 .. 0010111
                bits = ch - 256;
                size = 7;
            } else {
                // size 8, 11000000 .. 11000111
                bits = ch + 192 - 280;
                size = 8;
            }
            h[ch] = Hcode{
                .code = reverseBits(bits, size),
                .length = size,
            };
        }
    }

    fn reverseBits(n: u16, bit_length: u16) u16 {
        return math_bits.reverseU16(n << (16 - bit_length));
    }

    const LiteralNode = struct {
        literal: u16,
        freq: u16,
    };

    fn generateFixedOffsetEncoding(h: []hcode) void {
        for (h) |_, idx| {
            h[idx] = hcode{
                .code = reverseBits(u16(idx), 5),
                .length = 5,
            };
        }
    }

    const max_u16 = std.math.maxInt(u16);

    fn maxNode() LiteralNode {
        return LiteralNode{
            .literal = u16(max_u16),
            .freq = u16(max_u16),
        };
    }

    const CodeList = std.ArrayList(Hcode);

    const LiteralNodeList = std.ArrayList(LiteralNode);

    fn sortLiteralNodeList(list: []LiteralNode) void {
        std.sort.insertionSort(LiteralNode, list, lessLiteralNodeListFn);
    }

    fn lessLiteralNodeListFn(x: LiteralNode, y: LiteralNode) bool {
        return x.literal < y.literal;
    }

    fn fixed_literal_encoding() []Hcode {
        var h: [max_num_lit]Hcode = undefined;
        generateFixedLiteralEncoding(h[0..]);
        return h[0..];
    }

    const fixed_offset_encoding = blk: {
        var h: [30]hcode = undefined;
        generateFixedOffsetEncoding(h[0..]);
        break :blk h[0..];
    };

    // initalizes a new HuffmanEncoder instance.
    // call deinit when done to free resources.
    fn init(a: *std.mem.Allocator, size: usize) !HuffmanEncoder {
        var hu: HuffmanEncoder = undefined;
        hu.arena = std.heap.ArenaAllocator.init(a);
        hu.allocator = &hu.arena.allocator;
        hu.bit_cache = try hu.allocator.alloc(i32, 17);
        const bit_cache: [17]i32 = undefined;
        hu.codes = CodeList.init(hu.allocator);
        try codes.ensureCapacity(size);
        return hu;
    }

    fn deinit(h: *HuffmanEncoder) void {
        h.arena.deinit();
    }

    fn bitLength(h: []hcode, freq: []i32) isize {
        var total: isize = 0;
        for (freq) |f, i| {
            if (f != 0) {
                const x = @intCast(isize, h[i].length);
                const y = @intCast(isize, f);
                total += (y * x);
            }
        }
        return total;
    }

    // Return the number of literals assigned to each bit size in the Huffman encoding
    //
    // This method is only called when list.length >= 3
    // The cases of 0, 1, and 2 literals are handled by special case code.
    //
    // list  An array of the literals with non-zero frequencies
    //             and their associated frequencies. The array is in order of increasing
    //             frequency, and has as its last element a special element with frequency
    //             MaxInt32
    // max_bits     The maximum number of bits that should be used to encode any literal.
    //             Must be less than 16.
    // return      An integer array in which array[i] indicates the number of literals
    //             that should be encoded in i bits.
    fn bitCounts(h: *HuffmanEncoder, list: LiteralNodeList, max_bits: i32) []i32 {
        std.debug.assert(max_bits < max_bits_limit);
        const n = list.len;
    }
};

test "sort LiteralNodeList" {
    var ls = &HuffmanEncoder.LiteralNodeList.init(std.debug.global_allocator);
    defer ls.deinit();
    var n: usize = 5;
    while (n > 0) : (n -= 1) {
        try ls.append(HuffmanEncoder.LiteralNode{
            .literal = @intCast(u16, n),
            .freq = 0,
        });
    }

    HuffmanEncoder.sortLiteralNodeList(ls.toSlice());
    for (ls.toSlice()) |value, idx| {
        if (idx + 1 != @intCast(usize, value.literal)) {
            std.debug.warn("expected {} got {}\n", idx + 1, value.literal);
        }
    }

    // std.debug.warn("{}\n", HuffmanEncoder.fixed_literal_encoding().len);
}
