const std = @import("std");
const testing = std.testing;

const Header = struct {
    tzh_ttisutcnt: u32,
    tzh_ttisstdcnt: u32,
    tzh_leapcnt: u32,
    tzh_timecnt: u32,
    tzh_typecnt: u32,
    tzh_charcnt: u32,
    v2_header_start: u32,
};

pub fn parse_header(tzfilename: []const u8) !Header {
    const tzfile = try std.fs.openFileAbsolute(tzfilename, .{});
    defer tzfile.close();
    var buffer: [4096]u8 = undefined;
    _ = try tzfile.readAll(&buffer);

    const tzh_ttisutcnt = buffer[0x14] << 3 | buffer[0x15] << 2 | buffer[0x16] << 1 | buffer[0x17];
    const tzh_ttisstdcnt = buffer[0x18] << 3 | buffer[0x19] << 2 | buffer[0x1A] << 1 | buffer[0x1B];
    const tzh_leapcnt = buffer[0x1C] << 3 | buffer[0x1D] << 2 | buffer[0x1E] << 1 | buffer[0x1F];
    const tzh_timecnt = buffer[0x20] << 3 | buffer[0x21] << 2 | buffer[0x22] << 1 | buffer[0x23];
    const tzh_typecnt = buffer[0x24] << 3 | buffer[0x25] << 2 | buffer[0x26] << 1 | buffer[0x27];
    const tzh_charcnt = buffer[0x28] << 3 | buffer[0x29] << 2 | buffer[0x2A] << 1 | buffer[0x2B];
    const v2_header_start = tzh_timecnt * 5 + tzh_typecnt * 6 + tzh_leapcnt * 8 + tzh_charcnt + tzh_ttisstdcnt + tzh_ttisutcnt + 44;

    return Header{ .tzh_ttisutcnt = tzh_ttisutcnt, .tzh_ttisstdcnt = tzh_ttisstdcnt, .tzh_leapcnt = tzh_leapcnt, .tzh_timecnt = tzh_timecnt, .tzh_typecnt = tzh_typecnt, .tzh_charcnt = tzh_charcnt, .v2_header_start = v2_header_start };
}

test "header parse" {
    const amph = Header{
        .tzh_ttisutcnt = 5,
        .tzh_ttisstdcnt = 5,
        .tzh_leapcnt = 0,
        .tzh_timecnt = 11,
        .tzh_typecnt = 5,
        .tzh_charcnt = 16,
        .v2_header_start = 155,
    };
    const result = try parse_header("/usr/share/zoneinfo/America/Phoenix");
    try testing.expect(result.tzh_ttisutcnt == amph.tzh_ttisutcnt);
    try testing.expect(result.tzh_ttisstdcnt == amph.tzh_ttisstdcnt);
    try testing.expect(result.tzh_leapcnt == amph.tzh_leapcnt);
    try testing.expect(result.tzh_timecnt == amph.tzh_timecnt);
    try testing.expect(result.tzh_typecnt == amph.tzh_typecnt);
    try testing.expect(result.tzh_charcnt == amph.tzh_charcnt);
    try testing.expect(result.v2_header_start == amph.v2_header_start);
}
