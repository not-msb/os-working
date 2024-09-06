const std = @import("std");
const multiboot = @import("multiboot.zig");
const Console = @import("console.zig").Console;

export const multiboot_header align(16) linksection(".multiboot") = multiboot.MultiBoot{
    .mode_type = 0,
    .width = 640,
    .height = 480,
    .depth = 16,
};

// Initialized in boot.S
export var boot_info: *const multiboot.BootInfo = undefined;

// We only handle 16 bpp bgr, for now
const Pixel = packed struct {
    _rvsd: u1 = 0,
    b: u5,
    g: u5,
    r: u5,
};
    
const FrameBuffer = struct {
    pitch: u32,
    width: u32,
    height: u32,
    buffer: []Pixel,

    fn new() FrameBuffer {
        const fb_addr: usize = @intCast(boot_info.framebuffer_addr);
        const fb_bpp = boot_info.framebuffer_bpp;
        const fb_pitch = boot_info.framebuffer_pitch;
        const fb_width = boot_info.framebuffer_width;
        const fb_height = boot_info.framebuffer_height;

        const scale = fb_bpp/8;
        const pitch = fb_pitch / scale; 
        const _rest = fb_pitch % scale;
        std.debug.assert(_rest == 0);

        const raw: [*]Pixel = @ptrFromInt(fb_addr);
        const buffer = raw[0..pitch*fb_height];

        return .{
            .pitch = pitch,
            .width = fb_width,
            .height = fb_height,
            .buffer = buffer,
        };
    }

    fn clear(self: FrameBuffer) void {
        self.draw_square(.{ .b = 0, .g = 0, .r = 0 }, 0, 0, self.width, self.height);
    }

    fn fill(self: FrameBuffer, pixel: Pixel) void {
        self.draw_square(pixel, 0, 0, self.width, self.height);
    }

    fn draw_square(self: FrameBuffer, pixel: Pixel, x: u32, y: u32, w: u32, h: u32) void {
        for (y..y+h) |yi|
        for (x..x+w) |xi| {
            self.buffer[xi+yi*self.pitch] = pixel;
        };
    }
};

export fn main64() void {
    var console = Console{};
    console.puts("See that, lil bitch");
}

export fn main() void {
    const fb = FrameBuffer.new();
    const dim = 20;
    var x: i32 = 0;
    var y: i32 = 0;
    var vx: i32 = 1;
    var vy: i32 = 1;

    while (true) {
        fb.clear();
    //#fb.draw_square(.{ .b = 0, .g = 0, .r = 0 }, @intCast(x), @intCast(y), dim, dim);
        x += vx;
        y += vy;

        if (x == 0 or x >= fb.width-dim)
            vx *= -1;
        if (y == 0 or y >= fb.height-dim)
            vy *= -1;

        fb.draw_square(.{ .b = 0, .g = 31, .r = 0 }, @intCast(x), @intCast(y), dim, dim);
    }
}
