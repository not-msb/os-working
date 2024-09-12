const main = @import("main.zig");
const setBits = main.setBits;
const TablePointer = main.TablePointer;

const Entry = extern struct {
    offset_1: u16,
    selector: u16,
    bits: u16,
    offset_2: u16,
    offset_3: u32,
    _reserved: u32 = 0,

    fn missing() Entry {
        return .{
            .offset_1 = 0,
            .offset_2 = 0,
            .offset_3 = 0,
            .selector = 0,
            .bits = 0,
            //.bits = 0b1110_0000_0000,
        };
    }

    pub fn setHandler(self: *Entry, handler: *const anyopaque) *Entry {
        const addr: u64 = @intFromPtr(handler);
        self.offset_1 = @truncate(addr);
        self.offset_2 = @truncate(addr>>16);
        self.offset_3 = @truncate(addr>>32);

        asm volatile ("movw %cs, (%[sel])" : : [sel] "r" (&self.selector));
        self.bits = 0b1110_0000_0000;
        self.bits |= 1 << 15;
        return self;
    }

    pub fn setStackIndex(self: *Entry, index: u16) *Entry {
        self.bits = setBits(u16, 0, 3, self.bits, index+1);
        return self;
    }
};

pub const InterruptStackFrame = extern struct {
    instruction_pointer: u64,
    code_segment: u16,
    _reserved0: [6]u8,
    cpu_flags: u64,
    stack_pointer: u64,
    stack_segment: u16,
    _reserved1: [6]u8,
};

pub const InterruptDescriptorTable align(16) = extern struct {
    divide_error: Entry = Entry.missing(),
    debug: Entry = Entry.missing(),
    non_maskable_interrupt: Entry = Entry.missing(),
    breakpoint: Entry = Entry.missing(),
    overflow: Entry = Entry.missing(),
    bound_range_exceeded: Entry = Entry.missing(),
    invalid_opcode: Entry = Entry.missing(),
    device_not_available: Entry = Entry.missing(),
    double_fault: Entry = Entry.missing(),
    coprocessor_segment_overrun: Entry = Entry.missing(),
    invalid_tss: Entry = Entry.missing(),
    segment_not_present: Entry = Entry.missing(),
    stack_segment_fault: Entry = Entry.missing(),
    general_protection_fault: Entry = Entry.missing(),
    page_fault: Entry = Entry.missing(),
    _reserved0: Entry = Entry.missing(),
    x87_floating_point: Entry = Entry.missing(),
    alignment_check: Entry = Entry.missing(),
    machine_check: Entry = Entry.missing(),
    simd_floating_point: Entry = Entry.missing(),
    virtualization: Entry = Entry.missing(),
    cp_protection_exception: Entry = Entry.missing(),
    _reserved1: [6]Entry = .{ Entry.missing() } ** 6,
    hv_injection_exception: Entry = Entry.missing(),
    vmm_communication_exception: Entry = Entry.missing(),
    security_exception: Entry = Entry.missing(),
    _reserved2: Entry = Entry.missing(),
    interrupts: [256-32]Entry = .{Entry.missing()} ** (256-32),

    fn pointer(self: *const InterruptDescriptorTable) TablePointer {
        return .{
            .size = @sizeOf(InterruptDescriptorTable)-1,
            .offset = @intFromPtr(self),
        };
    }

    pub fn load(self: *const InterruptDescriptorTable) void {
        const ptr = &self.pointer();
        asm volatile (
            "lidtq (%[p])" : : [p] "r" (ptr)
        );
    }
};

