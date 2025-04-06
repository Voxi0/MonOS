const builtin = @import("builtin");
const limine = @import("limine");

export var startMarker: limine.RequestsStartMarker linksection(".limine_requests_start") = .{};
export var endMarker: limine.RequestsEndMarker linksection(".limine_requests_end") = .{};

export var baseRevision: limine.BaseRevision linksection(".limine_requests") = .init(3);

// Limine requests
export var framebufferRequest: limine.FramebufferRequest linksection(".limine_requests") = .{};

// Halt the CPU indefinitely
fn halt() noreturn {
    while (true) {
        switch (builtin.cpu.arch) {
            .x86_64 => asm volatile ("hlt"),
            .aarch64 => asm volatile ("wfi"),
            .riscv64 => asm volatile ("wfi"),
            .loongarch64 => asm volatile ("idle 0"),
            else => unreachable,
        }
    }
}

export fn kmain() noreturn {
    if (!baseRevision.isSupported()) @panic("Base revision unsupported");
    if (framebufferRequest.response) |framebufferResponse| {
        const fb = framebufferResponse.getFramebuffers()[0];
        for (0..100) |i| {
            const fbPtr: [*]volatile u32 = @ptrCast(@alignCast(fb.address));
            fbPtr[i * (fb.pitch / 4) + i] = 0xffffff;
        }
    } else @panic("No framebuffer");

    // Halt the CPU indefinitely
    halt();
}
