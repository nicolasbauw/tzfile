const std = @import("std");
const testing = std.testing;

const MAGIC: u32 = 0x545A6966;

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
