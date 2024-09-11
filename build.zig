const std = @import("std");
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;
const Feature = Target.Cpu.Feature;

pub fn build(b: *std.Build) void {
    const features = Target.x86.Feature;
    var dib_features = Feature.Set.empty;
    var enb_features = Feature.Set.empty;

    dib_features.addFeature(@intFromEnum(features.mmx));
    dib_features.addFeature(@intFromEnum(features.sse));
    dib_features.addFeature(@intFromEnum(features.sse2));
    dib_features.addFeature(@intFromEnum(features.avx));
    dib_features.addFeature(@intFromEnum(features.avx2));
    enb_features.addFeature(@intFromEnum(features.soft_float));

    const query = CrossTarget{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_sub = dib_features,
        .cpu_features_add = enb_features,
    };

    const target = b.standardTargetOptions(.{ .default_target = query });
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "coffin_os",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
    });

    const boot_path = b.fmt("{s}/boot.o", .{b.cache_root.path.?});
    const asm_cmd = b.addSystemCommand(&[_][]const u8{
        "nasm",
        "-felf64",
        "src/boot.asm",
        "-o",
        boot_path,
    });
    b.getInstallStep().dependOn(&asm_cmd.step);

    exe.setLinkerScript(.{ .cwd_relative = "src/linker.ld" });
    exe.addObjectFile(.{ .cwd_relative = boot_path });
    b.installArtifact(exe);

    const iso_dir = b.fmt("{s}/isofiles", .{b.cache_root.path.?});
    const kernel_path = b.fmt("{s}/coffin_os", .{b.exe_dir});
    const iso_path = b.fmt("{s}/disk.iso", .{b.exe_dir});

    const iso_cmd_str = &[_][]const u8{ 
        "/bin/sh", "-c",
        b.fmt(
            \\ mkdir -p {s}/boot/grub &&
            \\ cp {s} {s}/boot &&
            \\ cp src/grub.cfg {s}/boot/grub &&
            \\ grub-mkrescue -o {s} {s} -d /usr/lib/grub/i386-pc
        , .{iso_dir, kernel_path, iso_dir, iso_dir, iso_path, iso_dir})
    };

    const iso_cmd = b.addSystemCommand(iso_cmd_str);
    iso_cmd.step.dependOn(b.getInstallStep());

    const iso_step = b.step("iso", "Build an ISO image");
    iso_step.dependOn(&iso_cmd.step);

    const run_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-x86_64",
        "-cdrom",
        "zig-out/bin/disk.iso",
        "-m", "4G",
    });
    run_cmd.step.dependOn(iso_step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
