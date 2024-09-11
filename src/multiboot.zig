const ALIGN = 1 << 0;
const MEMINFO = 1 << 1;
const VIDEO = 0 << 2;
const MAGIC: u32 = 0x1BADB002;
const FLAGS: u32 = ALIGN | MEMINFO | VIDEO;

//not sure about extern, packed always complains tho
pub const MultiBoot = extern struct {
    magic: u32 align(1) = MAGIC,
    flags: u32 align (1) = FLAGS,
    cksum: u32 align (1) = -%(MAGIC + FLAGS),
    _rvsd1: u32 align (1) = 0,
    _rvsd2: u32 align (1) = 0,
    _rvsd3: u32 align (1) = 0,
    _rvsd4: u32 align (1) = 0,
    _rvsd5: u32 align (1) = 0,
    mode_type: u32 align (1),
    width: u32 align (1),
    height: u32 align (1),
    depth: u32 align (1),
};

pub const BootInfo = extern struct {
    flags: u32,
    mem_lower: u32,
    mem_upper: u32,
    boot_devie: u32,
    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,
    _syms0: u32,
    _syms1: u32,
    _syms2: u32,
    _syms3: u32,
    mmap_length: u32,
    mmap_addr: u32,
    drives_length: u32,
    drives_addr: u32,
    config_table: u32,
    bootloader_name: u32,
    apm_table: u32,
    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,
    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8 align(1),
    framebuffer_type: u8 align(1),
    framebuffer_palette_addr: u32 align(1),
    framebuffer_palette_num_colors: u16,

    pub fn flagIsSet(self: *const BootInfo, index: u5) bool {
        const mask: u32 = @as(u32, 1) << index;
        const flag = self.flags & mask;
        return flag != 0;
    }

    pub fn mmap_iter(self: *const BootInfo) MmapIter {
        return .{
            .end = self.mmap_addr+self.mmap_length,
            .current = self.mmap_addr,
        };
    }

    pub fn kernel_symbols(self: *const BootInfo) ?KernelSymbolTable {
        if (!self.flagIsSet(5))
            return null;

        return .{
            .num = self._syms0,
            .size = self._syms1,
            .addr = self._syms2,
            .shndx = self._syms3,
        };
    }

    pub fn kernel_sections(self: *const BootInfo) ?[]const align(1) Section {
        const symbols = self.kernel_symbols() orelse return null;
        //if (table.size != 64)
        //1    return Console.bsod("KernelSymbolTable.size isn't 64");

        const sections: [*]const align(1) Section = @ptrFromInt(symbols.addr);
        return sections[0..symbols.num];
    }
};

pub const Mmap = extern struct {
    size: u32 align(4),
    base_addr: u64 align(4),
    length: u64 align(4),
    @"type": u32 align(4),
};

pub const MmapIter = struct {
    end: u32,
    current: u32,

    pub fn next(self: *MmapIter) ?Mmap {
        if (self.current >= self.end) return null;

        const mmap: *const Mmap = @ptrFromInt(self.current);
        self.current += mmap.size + 4;
        return mmap.*;
    }
};

const KernelSymbolTable = struct {
    num: u32,
    size: u32,
    addr: u32,
    shndx: u32,
};

const Section = extern struct {
    name: u32,
    @"type": u32,
    flags: u64,
    addr: u64,
    offset: u64,
    size: u64,
    link: u32,
    info: u32,
    addr_align: u64,
    ent_size: u64,
};
