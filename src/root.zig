const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayList;

// TZif magic four bytes
const MAGIC: u32 = 0x545A6966;
// Header length
const HEADER_LEN: usize = 0x2C;

const TimezoneError = error{
    InvalidMagic,
    UnsupportedFormat,
};

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
    /// transition times timestamps table
    tzh_timecnt_data: ArrayList(i64),
    /// indices for the next field
    tzh_timecnt_indices: ArrayList(u8),
    /// a struct containing UTC offset, daylight saving time, abbreviation index
    tzh_typecnt: ArrayList(Ttinfo),
    /// abbreviations table
    tz_abbr: ArrayList([]const u8),
};

/// This sub-structure of the Tz struct is part of the TZfile format specifications, and contains UTC offset, daylight saving time, abbreviation index.
const Ttinfo = struct {
    tt_utoff: i32,
    tt_isdst: u8,
    tt_abbrind: u8,
};

pub fn parse_header(buffer: *[8192]u8) !Header {
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

fn parse_data(buffer: *[8192]u8, header: Header) Tz {
    // Calculates fields lengths and indexes (Version 2 format)
    const tzh_timecnt_len: u32 = header.tzh_timecnt * 9;
    const tzh_typecnt_len: u32 = header.tzh_typecnt * 6;
    const tzh_leapcnt_len: u32 = header.tzh_leapcnt * 12;
    const tzh_charcnt_len: u32 = header.tzh_charcnt;
    const tzh_timecnt_end: u32 = HEADER_LEN + header.v2_header_start + tzh_timecnt_len;
    const tzh_typecnt_end: u32 = tzh_timecnt_end + tzh_typecnt_len;
    const tzh_leapcnt_end: u32 = tzh_typecnt_end + tzh_leapcnt_len;
    const tzh_charcnt_end: u32 = tzh_leapcnt_end + tzh_charcnt_len;

    const tzh_timecnt_data: []u8 = buffer[HEADER_LEN + header.v2_header_start .. HEADER_LEN + header.v2_header_start + header.tzh_timecnt * 8];
    const reader = tzh_timecnt_data.reader();
    var i: usize = 0;
    while (i < header.timecnt) : (i += 1) {
        try reader.readInt(i64, .big);
    }
}

fn to_u32(b: [4]u8) u32 {
    return @as(u32, b[0]) << 24 | @as(u32, b[1]) << 16 | @as(u32, b[2]) << 8 | @as(u32, b[3]);
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

test "bytes to u32" {
    const bytes = [4]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    try testing.expect(to_u32(bytes) == 0xDEADBEEF);
}
