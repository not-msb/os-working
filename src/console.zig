const std = @import("std");

const VgaChar = packed struct {
    code_point: u8,
    foreground: VgaColor,
    background: VgaColor,
};

const VgaColor = enum(u4) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    LightMagenta = 13,
    LightBrown = 14,
    White = 15,
};

pub const Console = struct {
    buffer: *volatile [25][80]VgaChar = @ptrFromInt(0xB8000),
    foreground: VgaColor = .White,
    background: VgaColor = .Black,
    index: u16 = 0,

    pub fn set_color(self: *Console, foreground: VgaColor, background: VgaColor) void {
        self.foreground = foreground;
        self.background = background;
    }

    pub fn clear(self: *Console) void {
        const c = .{
            .code_point = 0,
            .foreground = self.foreground,
            .background = self.background,
        };
        self.index = 0;

        @memset(@as(*volatile [25*80]VgaChar, @ptrCast(self.buffer)), c);
    }

    pub fn putc(self: *Console, c: u8) void {
        const row = self.index / 80;
        const col = self.index % 80;

        // More may be added later
        switch (c) {
            '\n' => {
                self.index = (row+1)*80;
                return;
            },
            else => self.index += 1,
        }

        if (self.index >= 25*80) {
            self.index = 0;
            std.mem.copyForwards(
                VgaChar,
                @as(*[24*80]VgaChar, @volatileCast(@ptrCast(self.buffer[0..23]))),
                @as(*[24*80]VgaChar, @volatileCast(@ptrCast(self.buffer[1..]))),
            );
        }

        self.buffer[row][col] = .{
            .code_point = c,
            .foreground = self.foreground,
            .background = self.background,
        };
    }

    pub fn puts(self: *Console, s: []const u8) void {
        for (s) |c|
            self.putc(c);
    }
};
