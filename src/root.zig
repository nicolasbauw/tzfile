const std = @import("std");
const testing = std.testing;

// TZif magic four bytes
const MAGIC: u32 = 0x545A6966;
// Header length
const HEADER_LEN: u32 = 0x2C;

const TimezoneError = error{
    InvalidMagic,
    UnsupportedFormat,
};

// Tzfile header values
const Header = struct {
    tzh_ttisutcnt: u32,
    tzh_ttisstdcnt: u32,
    tzh_leapcnt: u32,
    tzh_timecnt: u32,
    tzh_typecnt: u32,
    tzh_charcnt: u32,
    v2_header_start: u32,
};

/// This is the library's primary structure, which contains the TZfile fields.
const Tz = struct {
    /// Allocator
    allocator: std.mem.Allocator,
    /// transition times timestamps table
    tzh_timecnt_data: []const i64,
    // indices for the next field
    tzh_timecnt_indices: []const u8,
    // a struct containing UTC offset, daylight saving time, abbreviation index
    tzh_typecnt: []const Ttinfo,
    // abbreviations table
    tz_abbr: []const u8,

    pub fn deinit(self: *const Tz) void {
        self.allocator.free(self.tzh_timecnt_data);
        self.allocator.free(self.tzh_timecnt_indices);
        self.allocator.free(self.tz_abbr);
        self.allocator.free(self.tzh_typecnt);
    }
};

/// This sub-structure of the Tz struct is part of the TZfile format specifications, and contains UTC offset, daylight saving time, abbreviation index.
const Ttinfo = struct {
    tt_utoff: i32, // number of seconds to be added to UT
    tt_isdst: u8, // DST ?
    tt_desigidx: u8, // index into the array of time zone abbreviation bytes
};

fn parse_header(buffer: *[8192]u8) !Header {
    const magic = to_u32(buffer[0x00..0x04].*);
    if (magic != MAGIC) return error.InvalidMagic;
    if (buffer[4] != 50) return error.UnsupportedFormat;

    const tzh_ttisutcnt = to_u32(buffer[0x14..0x18].*);
    const tzh_ttisstdcnt = to_u32(buffer[0x18..0x1C].*);
    const tzh_leapcnt = to_u32(buffer[0x1C..0x20].*);
    const tzh_timecnt = to_u32(buffer[0x20..0x24].*);
    const tzh_typecnt = to_u32(buffer[0x24..0x28].*);
    const tzh_charcnt = to_u32(buffer[0x28..0x2C].*);
    const v2_header_start = tzh_timecnt * 5 + tzh_typecnt * 6 + tzh_leapcnt * 8 + tzh_charcnt + tzh_ttisstdcnt + tzh_ttisutcnt + 44;

    return Header{ .tzh_ttisutcnt = tzh_ttisutcnt, .tzh_ttisstdcnt = tzh_ttisstdcnt, .tzh_leapcnt = tzh_leapcnt, .tzh_timecnt = tzh_timecnt, .tzh_typecnt = tzh_typecnt, .tzh_charcnt = tzh_charcnt, .v2_header_start = v2_header_start };
}

fn parse_data(allocator: std.mem.Allocator, buffer: *[8192]u8, header: Header) !Tz {
    // Calculates fields lengths and indexes (Version 2 format)
    const tzh_timecnt_len: u32 = header.tzh_timecnt * 9;
    const tzh_typecnt_len: u32 = header.tzh_typecnt * 6;
    const tzh_leapcnt_len: u32 = header.tzh_leapcnt * 12;
    const tzh_charcnt_len: u32 = header.tzh_charcnt;
    const tzh_timecnt_end: u32 = HEADER_LEN + header.v2_header_start + tzh_timecnt_len;
    const tzh_typecnt_end: u32 = tzh_timecnt_end + tzh_typecnt_len;
    const tzh_leapcnt_end: u32 = tzh_typecnt_end + tzh_leapcnt_len;
    const tzh_charcnt_end: u32 = tzh_leapcnt_end + tzh_charcnt_len;

    // Transition times
    const tzh_timecnt_data = try allocator.alloc(i64, header.tzh_timecnt);
    errdefer allocator.free(tzh_timecnt_data);

    const cnt = buffer[HEADER_LEN + header.v2_header_start .. HEADER_LEN + header.v2_header_start + header.tzh_timecnt * 8];
    var i: usize = 0;
    while (i < cnt.len) : (i += 8) {
        tzh_timecnt_data[i / 8] = to_i64(cnt[i..(i + 8)][0..8].*);
    }

    // indices for the next field
    const tzh_timecnt_indices = try allocator.alloc(u8, header.tzh_timecnt);
    errdefer allocator.free(tzh_timecnt_indices);

    @memcpy(tzh_timecnt_indices[0..header.tzh_timecnt], buffer[HEADER_LEN + header.v2_header_start + header.tzh_timecnt * 8 .. tzh_timecnt_end]);

    // Abbreviations
    const abbrs = buffer[tzh_leapcnt_end..tzh_charcnt_end];
    const tz_abbr = try allocator.alloc(u8, header.tzh_charcnt);
    errdefer allocator.free(tzh_timecnt_indices);

    @memcpy(tz_abbr[0..abbrs.len], abbrs[0..abbrs.len]);

    // ttinfo
    const tcnt = buffer[tzh_timecnt_end..tzh_typecnt_end];
    const tzh_typecnt = try allocator.alloc(Ttinfo, header.tzh_typecnt);
    errdefer allocator.free(tzh_typecnt);

    i = 0;
    while (i < header.tzh_typecnt) : (i += 1) {
        tzh_typecnt[i] = .{ .tt_utoff = to_i32(tcnt[i * 6 .. i * 6 + 4][0..4].*), .tt_isdst = tcnt[i * 6 + 4], .tt_desigidx = tcnt[i * 6 + 5] };
    }

    // Returning the Tz struct
    return Tz{ .allocator = allocator, .tzh_timecnt_data = tzh_timecnt_data, .tzh_timecnt_indices = tzh_timecnt_indices, .tzh_typecnt = tzh_typecnt, .tz_abbr = tz_abbr };
}

fn to_u32(b: [4]u8) u32 {
    return @as(u32, b[0]) << 24 | @as(u32, b[1]) << 16 | @as(u32, b[2]) << 8 | @as(u32, b[3]);
}

fn to_i32(b: [4]u8) i32 {
    return @as(i32, b[0]) << 24 | @as(i32, b[1]) << 16 | @as(i32, b[2]) << 8 | @as(i32, b[3]);
}

fn to_i64(b: [8]u8) i64 {
    return @as(i64, b[0]) << 56 | @as(i64, b[1]) << 48 | @as(i64, b[2]) << 40 | @as(i64, b[3]) << 32 | @as(i64, b[4]) << 24 | @as(i64, b[5]) << 16 | @as(i64, b[6]) << 8 | @as(i64, b[7]);
}

test "header parse" {
    const tzfile = try std.fs.openFileAbsolute("/usr/share/zoneinfo/America/Phoenix", .{});
    defer tzfile.close();
    var buffer: [8192]u8 = undefined;
    _ = try tzfile.readAll(&buffer);

    const amph = Header{
        .tzh_ttisutcnt = 5,
        .tzh_ttisstdcnt = 5,
        .tzh_leapcnt = 0,
        .tzh_timecnt = 11,
        .tzh_typecnt = 5,
        .tzh_charcnt = 16,
        .v2_header_start = 155,
    };
    const result = try parse_header(&buffer);
    try testing.expect(std.meta.eql(amph, result));
}

test "data parse America/Phoenix" {
    std.debug.print("Testing timezone America/Phoenix\n", .{});
    const tzfile = try std.fs.openFileAbsolute("/usr/share/zoneinfo/America/Phoenix", .{});
    defer tzfile.close();
    var buffer: [8192]u8 = undefined;
    _ = try tzfile.readAll(&buffer);

    const header = try parse_header(&buffer);
    std.debug.print("parsed header values: {any}\n\n", .{header});

    // Reference values
    const amph_timecnt_d: []const i64 = &.{ -2717643600, -1633273200, -1615132800, -1601823600, -1583683200, -880210800, -820519140, -812653140, -796845540, -84380400, -68659200 };
    const amph_timecnt_t: []const u8 = &.{ 4, 1, 2, 1, 2, 3, 2, 3, 2, 1, 2 };
    const amph_tz_abbrs: []const u8 = &.{ 0x4c, 0x4d, 0x54, 0x00, 0x4d, 0x44, 0x54, 0x00, 0x4d, 0x53, 0x54, 0x00, 0x4d, 0x57, 0x54, 0x00 };

    std.debug.print("reference values    : {any},{any}\n", .{ amph_timecnt_d.len, amph_timecnt_d });
    const result = try parse_data(std.testing.allocator, &buffer, header);
    std.debug.print("tzh_timecnt_data    : {any},{any}\n\n", .{ result.tzh_timecnt_data.len, result.tzh_timecnt_data });

    std.debug.print("reference values    : {any},{any}\n", .{ amph_timecnt_t.len, amph_timecnt_t });
    std.debug.print("tzh_timecnt_indices : {any},{any}\n\n", .{ result.tzh_timecnt_indices.len, result.tzh_timecnt_indices });

    std.debug.print("reference values    : {any},{c}\n", .{ amph_tz_abbrs.len, amph_tz_abbrs });
    std.debug.print("tz_abbrs            : {any},{c}\n\n", .{ result.tz_abbr.len, result.tz_abbr });

    std.debug.print("tzh_typecnt         : {any},{any}\n\n", .{ result.tzh_typecnt.len, result.tzh_typecnt });

    try testing.expectEqualSlices(i64, amph_timecnt_d, result.tzh_timecnt_data);
    try testing.expectEqualSlices(u8, amph_timecnt_t, result.tzh_timecnt_indices);
    try testing.expectEqualSlices(u8, amph_tz_abbrs, result.tz_abbr);

    std.debug.print("Tz struct           : {any}\n", .{result});
    result.deinit();
}

test "data parse America/Virgin" {
    std.debug.print("\n\nTesting timezone America/Virgin\n", .{});
    const tzfile = try std.fs.openFileAbsolute("/usr/share/zoneinfo/America/Virgin", .{});
    defer tzfile.close();
    var buffer: [8192]u8 = undefined;
    _ = try tzfile.readAll(&buffer);

    const header = try parse_header(&buffer);
    std.debug.print("parsed header values: {any}\n\n", .{header});

    // Reference values
    const amvi_timecnt_d: []const i64 = &.{ -2233035335, -873057600, -769395600, -765399600 };
    const amvi_timecnt_t: []const u8 = &.{ 1, 3, 2, 1 };
    const amvi_tz_abbrs: []const u8 = &.{ 0x4c, 0x4d, 0x54, 0x00, 0x41, 0x53, 0x54, 0x00, 0x41, 0x50, 0x54, 0x00, 0x41, 0x57, 0x54, 0x00 };

    std.debug.print("reference values    : {any},{any}\n", .{ amvi_timecnt_d.len, amvi_timecnt_d });
    const result = try parse_data(std.testing.allocator, &buffer, header);
    std.debug.print("tzh_timecnt_data    : {any},{any}\n\n", .{ result.tzh_timecnt_data.len, result.tzh_timecnt_data });

    std.debug.print("reference values    : {any},{any}\n", .{ amvi_timecnt_t.len, amvi_timecnt_t });
    std.debug.print("tzh_timecnt_indices : {any},{any}\n\n", .{ result.tzh_timecnt_indices.len, result.tzh_timecnt_indices });

    std.debug.print("reference values    : {any},{c}\n", .{ amvi_tz_abbrs.len, amvi_tz_abbrs });
    std.debug.print("tz_abbrs            : {any},{c}\n\n", .{ result.tz_abbr.len, result.tz_abbr });

    std.debug.print("tzh_typecnt         : {any},{any}\n\n", .{ result.tzh_typecnt.len, result.tzh_typecnt });

    try testing.expectEqualSlices(i64, amvi_timecnt_d, result.tzh_timecnt_data);
    try testing.expectEqualSlices(u8, amvi_timecnt_t, result.tzh_timecnt_indices);
    try testing.expectEqualSlices(u8, amvi_tz_abbrs, result.tz_abbr);

    std.debug.print("Tz struct           : {any}\n", .{result});
    result.deinit();
}

test "bytes to u32" {
    const bytes = [4]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    try testing.expect(to_u32(bytes) == 0xDEADBEEF);
}

test "bytes to i32" {
    const bytes = [4]u8{ 0xff, 0xff, 0xc2, 0x07 };
    try testing.expect(to_i32(bytes) == -15865);
}

test "bytes to i64" {
    const bytes = [8]u8{ 0xff, 0xff, 0xff, 0xff, 0x5e, 0x04, 0x0c, 0xb0 };
    try testing.expect(to_i64(bytes) == -2717643600);
}
