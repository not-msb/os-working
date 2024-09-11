const std = @import("std");
const main = @import("main.zig");
const console = &main.console;
const setBits = main.setBits;
const getBits = main.getBits;
const TablePointer = main.TablePointer;

pub const SegmentSelector = struct {
    selector: u16,

    fn new(index: u16, rpl: PrivilegeLevel) SegmentSelector {
        return .{ .selector = (index << 3) | @intFromEnum(rpl) };
    }
};

const PrivilegeLevel = enum(u8) {
    ring0 = 0,
    ring1 = 1,
    ring2 = 2,
    ring3 = 3,

    fn new(level: u2) PrivilegeLevel {
        return switch (level) {
            0 => .ring0,
            1 => .ring1,
            2 => .ring2,
            3 => .ring3,
        };
    }
};

pub const TaskStateSegment = extern struct {
    _reserved0: u32 = 0,
    privilege_stack_table: [3]u64 align(1),
    _reserved1: u64 align(1) = 0,
    interrupt_stack_table: [7]u64 align(1),
    _reserved2: u64 align(1) = 0,
    _reserved3: u16 = 0,
    io_map_base_addr: u16,

    pub fn new() TaskStateSegment {
        return .{
            .privilege_stack_table = .{0} ** 3,
            .interrupt_stack_table = .{0} ** 7,
            .io_map_base_addr = @sizeOf(TaskStateSegment),
        };
    }
};

pub const Descriptor = union(enum) {
    UserSegment: u64,
    SystemSegment: struct { u64, u64 },

    const Flags = struct {
        const ACCESSED     = 1 << 40;
        const WRITABLE     = 1 << 41;
        const CONFORMING   = 1 << 42;
        const EXECUTABLE   = 1 << 43;
        const USER_SEGMENT = 1 << 44;
        const DPL_RING_3   = 3 << 45;
        const PRESENT      = 1 << 47;
        const AVAILABLE    = 1 << 52;
        const LONG_MODE    = 1 << 53;
        const DEFAULT_SIZE = 1 << 54;
        const GRANULARITY  = 1 << 55;
        const LIMIT_0_15   = 0xFFFF;
        const LIMIT_16_19  = 0xF << 48;
        const BASE_0_23    = 0xFF_FFFF << 16;
        const BASE_24_31   = 0xFF << 56;

        const COMMON =
            Flags.USER_SEGMENT
            | Flags.PRESENT
            | Flags.WRITABLE
            | Flags.ACCESSED
            | Flags.LIMIT_0_15
            | Flags.LIMIT_16_19
            | Flags.GRANULARITY;

        const KERNEL_CODE64 = Flags.COMMON | Flags.EXECUTABLE | Flags.LONG_MODE;
    };

    fn dpl(self: Descriptor) PrivilegeLevel {
        const v_low = switch (self) {
            .UserSegment => |v| v,
            .SystemSegment => |t| t[0],
        };

        const d = (v_low & Flags.DPL_RING_3) >> 45;
        return PrivilegeLevel.new(@truncate(d));
    }

    pub fn kernel_code_segment() Descriptor {
        return .{ .UserSegment = Flags.KERNEL_CODE64 };
    }

    pub fn tss_segment(tss_ptr: *const TaskStateSegment) Descriptor {
        const addr: u64 = @intFromPtr(tss_ptr);
        var low: u64 = Flags.PRESENT;
        var high: u64 = 0;

        low = setBits(u64, 16, 40, low, getBits(u64, 0, 24, addr));
        low = setBits(u64, 56, 64, low, getBits(u64, 24, 32, addr));
        low = setBits(u64,  0, 16, low, @sizeOf(TaskStateSegment)-1);
        low = setBits(u64, 40, 44, low, 0b1001);
        high = setBits(u64, 0, 32, high, getBits(u64, 32, 64, addr));

    var buf: [4096]u8 = undefined;
    const str = std.fmt.bufPrint(&buf, "TSS\n  addr: 0b{b:0>64}\n  low:  0b{b:0>64}\n  high: 0b{b:0>64}\n", .{addr, low, high}) catch @panic("Failed bufPrint");
    console.puts(str);

        return .{ .SystemSegment = .{ low, high } };
    }
};

pub const GlobalDescriptorTable = extern struct {
    table: [8]u64 = .{0} ** 8,
    len: usize = 1,

    pub fn append(self: *GlobalDescriptorTable, desc: Descriptor) SegmentSelector {
        const index = self.len;

        switch (desc) {
            .UserSegment => |v| {
                if (self.len >= 8)
                    @panic("GDT is filled\n");

                self.table[self.len] = v;
                self.len += 1;
            },
            .SystemSegment => |t| {
                const v_low, const v_high = t;

                if (self.len+1 >= 8)
                    @panic("GDT is filled\n");

                self.table[self.len] = v_low;
                self.table[self.len+1] = v_high;
                self.len += 2;
            },
        }

        return SegmentSelector.new(@truncate(index), desc.dpl());
    }

    fn pointer(self: *const GlobalDescriptorTable) TablePointer {
        return .{
            .size = @truncate(self.len*@sizeOf(u64) - 1),
            .offset = @intFromPtr(&self.table),
        };
    }

    pub fn load(self: *const GlobalDescriptorTable) void {
        const ptr = &self.pointer();
        asm volatile (
            "lgdtq (%[p])" : : [p] "r" (ptr)
        );
    }
};

