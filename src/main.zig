const std = @import("std");
const multiboot = @import("multiboot.zig");
const Console = @import("console.zig").Console;
const VgaChar = @import("console.zig").VgaChar;

const Idt = @import("idt.zig");
const InterruptDescriptorTable = Idt.InterruptDescriptorTable;
const InterruptStackFrame = Idt.InterruptStackFrame;
const Gdt = @import("gdt.zig");
const GlobalDescriptorTable = Gdt.GlobalDescriptorTable;
const SegmentSelector = Gdt.SegmentSelector;
const Descriptor = Gdt.Descriptor;
const TaskStateSegment = Gdt.TaskStateSegment;

const BootInfo = multiboot.BootInfo;
const MmapIter = multiboot.MmapIter;
const Mmap = multiboot.Mmap;

export const multiboot_header align(16) linksection(".multiboot") = multiboot.MultiBoot{
    .mode_type = 0,
    .width = 640,
    .height = 480,
    .depth = 16,
};

// Initialized in boot.S
export var boot_info_addr: u32 = undefined;

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

    fn new(boot_info: BootInfo) FrameBuffer {
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

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = trace;

    //var buffer: [8192]u8 = undefined;
    //var fba = std.heap.FixedBufferAllocator.init(&buffer);
    //var list = std.ArrayList(u8).initCapacity(fba.allocator(), 8192) catch {
    //    Console.bsod("Couldnt make list");
    //    while (true) {}
    //};
    //const writer = list.writer();

    var buf: [4096]u8 = undefined;
    const str = std.fmt.bufPrint(&buf, "{s}\nret_addr: 0x{?x}\n", .{msg, ret_addr}) catch @panic("Failed Bufprint");
    Console.bsod(str);
    while (true) {}
}

const Frame = struct {
    id: usize,

    fn newContaining(addr: usize) Frame {
        return .{ .id = addr / std.mem.page_size };
    }
};

const FrameAllocator = struct {
    next_free: Frame,
    current_mmap: ?Mmap,
    mmaps: MmapIter,
    k_start: Frame,
    m_start: Frame,
    k_end: Frame,
    m_end: Frame,

    fn new(info: *const BootInfo) FrameAllocator {
        var k_start: usize = std.math.maxInt(usize);
        var k_end: usize = 0;
        const m_start = boot_info_addr;
        const m_end = boot_info_addr+@sizeOf(BootInfo);

        const sections = info.kernel_sections().?;
        for (sections) |section| {
            if (section.@"type" == 0) continue;
            if (section.addr < k_start)
                k_start = section.addr;
            if (section.addr+section.size > k_end)
                k_end = section.addr+section.size;
        }

        var frame_allocator = FrameAllocator{
            .next_free = Frame.newContaining(0x100000),
            .current_mmap = null,
            .mmaps = info.mmap_iter(),
            .k_start = Frame.newContaining(k_start),
            .m_start = Frame.newContaining(m_start),
            .k_end = Frame.newContaining(k_end),
            .m_end = Frame.newContaining(m_end),
        };

        frame_allocator.choose_next_mmap();
        return frame_allocator;
    }

    fn alloc(self: *FrameAllocator) ?Frame {
        const mmap = self.current_mmap orelse return null;
        const frame = self.next_free;

        const last_mmap = b: {
            const addr = mmap.base_addr+mmap.length-1;
            break :b Frame.newContaining(addr);
        };

        if (frame.id > last_mmap.id) {
            self.choose_next_mmap();
        } else if (frame.id >= self.k_start.id and frame.id <= self.k_end.id) {
            self.next_free = Frame{ .id = self.k_end.id+1 };
        } else if (frame.id >= self.m_start.id and frame.id <= self.m_end.id) {
            self.next_free = Frame{ .id = self.m_end.id+1 };
        } else {
            self.next_free.id += 1;
            return frame;
        }

        return self.alloc();
    }

    fn choose_next_mmap(self: *FrameAllocator) void {
        var mmaps = self.mmaps;
        var min: usize = std.math.maxInt(usize);

        while (mmaps.next()) |mmap| {
            const addr = mmap.base_addr+mmap.length-1;
            if ((addr / std.mem.page_size) < self.next_free.id) continue;
            if (mmap.base_addr < min) {
                min = mmap.base_addr;
                self.current_mmap = mmap;
            }
        }
        
        const mmap = self.current_mmap orelse return;
        const start = Frame.newContaining(mmap.base_addr);
        if (self.next_free.id < start.id)
            self.next_free = start;
    }

            fn _alloc(self: *FrameAllocator, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
                _ = ptr_align;
                _ = ret_addr;

                if (len > std.mem.page_size) {
                    Console.bsod("Len too long");
                    while (true) {}
                }

                const frame = self.alloc() orelse {
                    Console.bsod("Pages are all used");
                    while (true) {}
                };
                //var allocated: usize = PAGE_SIZE;

                //while (allocated < len) : (allocated += PAGE_SIZE) {
                //    _ = frame_allocator.alloc() orelse {
                //        Console.bsod("Pages are all used");
                //        while (true) {}
                //    };
                //}

                return @ptrFromInt(frame.id*4096);
            }


    fn allocator(self: *FrameAllocator, vtable: *std.mem.Allocator.VTable) std.mem.Allocator {
        const gen = struct {
            fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
                const fallocator: *FrameAllocator = @alignCast(@ptrCast(ctx));
                return fallocator._alloc(len, ptr_align, ret_addr);
            }

            fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
                _ = ctx;
                _ = buf;
                _ = buf_align;
                _ = new_len;
                _ = ret_addr;
                Console.bsod("Cant resize yet");
                while (true) {}
            }

            fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
                _ = ctx;
                _ = buf;
                _ = buf_align;
                _ = ret_addr;
                Console.bsod("Cant free yet");
                while (true) {}
            }
        };

        vtable.* = .{
            .alloc = gen.alloc,
            .resize = gen.resize,
            .free = gen.free,
        };

        return .{
            .ptr = self,
            .vtable = vtable,
        };
    }
};

pub const TablePointer = extern struct {
    size: u16,
    offset: u64 align(2),
};

const DOUBLE_FAULT_IST_INDEX = 0;
var STACK: [16*std.mem.page_size]u8 align(16) = undefined;

pub var console = Console{};
var idt = InterruptDescriptorTable{};
var gdt = GlobalDescriptorTable{};
var tss = TaskStateSegment.new();

const fmtHandler =
    \\[EXCEPTION]: {s} - 0x{x}
    \\    instr_pointer: 0x{x}
    \\    code_segment:  0x{x}
    \\    cpu_flags:     0x{x}
    \\    stack_pointer: 0x{x}
    \\    stack_segment: 0x{x}
    \\
;

fn debugException(name: []const u8, frame: *InterruptStackFrame, code: u64) void {
    var buf: [4096]u8 = undefined;
    const str = std.fmt.bufPrint(&buf, fmtHandler, .{
        name, code,
        frame.instruction_pointer,
        frame.code_segment,
        frame.cpu_flags,
        frame.stack_pointer,
        frame.stack_segment,
    }) catch @panic("Failed bufPrint");
    console.puts(str);
}

fn breakpointHandler(frame: *InterruptStackFrame) callconv(.Interrupt) void {
    const old_colors = .{console.foreground, console.background};
    console.set_color(.Red, .Black);
    debugException("breakpoint", frame, 0);
    console.set_color(old_colors[0], old_colors[1]);
}

fn doubleFaultHandler(frame: *InterruptStackFrame, code: u64) callconv(.Interrupt) noreturn {
    const old_colors = .{console.foreground, console.background};
    console.set_color(.Red, .Black);
    debugException("doubleFault", frame, code);
    console.set_color(old_colors[0], old_colors[1]);
    while (true) {}
}

fn pageFaultHandler(frame: *InterruptStackFrame, code: u64) callconv(.Interrupt) void {
    const old_colors = .{console.foreground, console.background};
    console.set_color(.Red, .Black);
    debugException("pageFault", frame, code);
    console.set_color(old_colors[0], old_colors[1]);
}

pub fn getBits(comptime T: type, comptime low: u8, comptime high: u8, src: T) T {
    if (!(low < @bitSizeOf(T)))
        @panic("getBits fault 0");
    if (!(high <= @bitSizeOf(T)))
        @panic("getBits fault 1");
    if (!(low < high))
        @panic("getBits fault 2");

    const bits: T = src << (@bitSizeOf(T) - high) >> (@bitSizeOf(T) - high);
    return bits >> low;
}

pub fn setBits(comptime T: type, comptime low: u8, comptime high: u8, dst: T, src: T) T {
    if (!(low < @bitSizeOf(T)))
        @panic("setBits fault 0");
    if (!(high <= @bitSizeOf(T)))
        @panic("setBits fault 1");
    if (!(low < high))
        @panic("setBits fault 2");
    if (!(src << (@bitSizeOf(T) - (high - low)) >> (@bitSizeOf(T) - (high - low)) == src))
        @panic("setBits fault 3");

    const bitmask: T = ~(~@as(T, 0) << (@bitSizeOf(T) - high) >> (@bitSizeOf(T) - high) >> low << low);
    return (dst & bitmask) | (src << low);
}

fn rec() void {
    rec();
}

fn load_tss(segment: SegmentSelector) void {
    asm volatile("ltr %[p]" : : [p] "r" (segment.selector));
}

export fn main() void {
    //const boot_info: *const multiboot.BootInfo = @ptrFromInt(boot_info_addr);
    console.clear();
    console.puts("Still works\n");

    console.puts("Here1\n");

    tss.interrupt_stack_table[DOUBLE_FAULT_IST_INDEX] = @intFromPtr(&STACK) + @sizeOf(@TypeOf(STACK));

    const code_selector = gdt.append(Descriptor.kernel_code_segment());
    const tss_selector = gdt.append(Descriptor.tss_segment(&tss));
    gdt.load();

    asm volatile(
        \\pushq %[sel]
        \\leaq 1f(%rip), %rcx
        \\pushq %rcx
        \\lretq
        \\1:
        : : [sel] "r" (@as(u64, code_selector.selector))
        : "rcx"
    );
    load_tss(tss_selector);

    _ = idt.breakpoint.setHandler(breakpointHandler);
    _ = idt.double_fault
        .setHandler(doubleFaultHandler)
        .setStackIndex(DOUBLE_FAULT_IST_INDEX);
    idt.load();
    console.puts("Here2\n");

    // TESTING EXCEPTIONS
    //asm volatile ("int3");
    //@as(*u8, @ptrFromInt(0xfdeadbeef)).* = 0;

    // THIS IS THE OFFENDING CODE
    rec();

    console.puts("Here3\n");
}
