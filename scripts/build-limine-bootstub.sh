#!/usr/bin/env sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <amd64|arm64> <work-dir> <output-elf>" >&2
    exit 2
fi

arch=$1
work=$2
output=$3

llvm_prefix=$(brew --prefix llvm 2>/dev/null || true)
lld_prefix=$(brew --prefix lld 2>/dev/null || true)
clang="${CLANG:-${llvm_prefix:+$llvm_prefix/bin/clang}}"
ld_lld="${LD_LLD:-${lld_prefix:+$lld_prefix/bin/ld.lld}}"

if [ -z "$clang" ] || [ ! -x "$clang" ]; then
    clang="${CLANG:-clang}"
fi
if [ -z "$ld_lld" ] || [ ! -x "$ld_lld" ]; then
    ld_lld="${LD_LLD:-ld.lld}"
fi

command -v "$clang" >/dev/null 2>&1
command -v "$ld_lld" >/dev/null 2>&1

mkdir -p "$work" "$(dirname "$output")"

kernel_c="$work/bootstub.c"
linker="$work/bootstub.ld"
object="$work/bootstub.o"

cat > "$kernel_c" <<'SOURCE'
#include <stdint.h>
#include <stddef.h>

#define LIMINE_COMMON_MAGIC 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b
#define LIMINE_FRAMEBUFFER_REQUEST { LIMINE_COMMON_MAGIC, 0x9d5827dcd881dd75, 0xa3148604f6fab11b }
#define LIMINE_REQUESTS_START_MARKER { 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9 }
#define LIMINE_REQUESTS_END_MARKER { 0xadc0e0531bb10d03, 0x9572709f31764c62 }
#define LIMINE_BASE_REVISION(N) { 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, (N) }

__attribute__((used, section(".limine_requests_start")))
static volatile uint64_t limine_requests_start_marker[4] = LIMINE_REQUESTS_START_MARKER;

struct limine_framebuffer {
    void *address;
    uint64_t width;
    uint64_t height;
    uint64_t pitch;
    uint16_t bpp;
    uint8_t memory_model;
    uint8_t red_mask_size;
    uint8_t red_mask_shift;
    uint8_t green_mask_size;
    uint8_t green_mask_shift;
    uint8_t blue_mask_size;
    uint8_t blue_mask_shift;
    uint8_t unused[7];
    uint64_t edid_size;
    void *edid;
};

struct limine_framebuffer_response {
    uint64_t revision;
    uint64_t framebuffer_count;
    struct limine_framebuffer **framebuffers;
};

struct limine_framebuffer_request {
    uint64_t id[4];
    uint64_t revision;
    struct limine_framebuffer_response *response;
};

__attribute__((used, section(".limine_requests")))
static volatile uint64_t limine_base_revision[3] = LIMINE_BASE_REVISION(4);

__attribute__((used, section(".limine_requests")))
static volatile struct limine_framebuffer_request framebuffer_request = {
    .id = LIMINE_FRAMEBUFFER_REQUEST,
    .revision = 0,
    .response = 0
};

__attribute__((used, section(".limine_requests_end")))
static volatile uint64_t limine_requests_end_marker[2] = LIMINE_REQUESTS_END_MARKER;

static uint32_t make_pixel(const struct limine_framebuffer *fb,
                           uint8_t r, uint8_t g, uint8_t b) {
    if (fb->bpp < 24) {
        return 0;
    }
    return ((uint32_t)r << fb->red_mask_shift)
         | ((uint32_t)g << fb->green_mask_shift)
         | ((uint32_t)b << fb->blue_mask_shift);
}

static void fill_rect(struct limine_framebuffer *fb,
                      uint64_t x0, uint64_t y0,
                      uint64_t w, uint64_t h,
                      uint32_t colour) {
    if (fb->bpp != 32) {
        return;
    }

    if (x0 + w > fb->width) {
        w = fb->width - x0;
    }
    if (y0 + h > fb->height) {
        h = fb->height - y0;
    }

    for (uint64_t y = y0; y < y0 + h; y++) {
        volatile uint32_t *row = (volatile uint32_t *)((uint8_t *)fb->address + y * fb->pitch);
        for (uint64_t x = x0; x < x0 + w; x++) {
            row[x] = colour;
        }
    }
}

static void flush_framebuffer(const struct limine_framebuffer *fb) {
#if defined(__aarch64__)
    uint64_t ctr_el0;
    __asm__ volatile ("mrs %0, ctr_el0" : "=r"(ctr_el0));
    uint64_t line_size = 4ull << ((ctr_el0 >> 16) & 0xf);
    uintptr_t start = (uintptr_t)fb->address;
    uintptr_t end = start + fb->pitch * fb->height;
    start &= ~(uintptr_t)(line_size - 1);

    for (uintptr_t p = start; p < end; p += line_size) {
        __asm__ volatile ("dc cvac, %0" :: "r"(p) : "memory");
    }
    __asm__ volatile ("dsb sy; isb" ::: "memory");
#else
    (void)fb;
#endif
}

static uint8_t glyph5x7(char c, uint8_t row) {
    static const uint8_t digits[10][7] = {
        {0x0e,0x11,0x13,0x15,0x19,0x11,0x0e},
        {0x04,0x0c,0x04,0x04,0x04,0x04,0x0e},
        {0x0e,0x11,0x01,0x02,0x04,0x08,0x1f},
        {0x1e,0x01,0x01,0x0e,0x01,0x01,0x1e},
        {0x02,0x06,0x0a,0x12,0x1f,0x02,0x02},
        {0x1f,0x10,0x10,0x1e,0x01,0x01,0x1e},
        {0x0e,0x10,0x10,0x1e,0x11,0x11,0x0e},
        {0x1f,0x01,0x02,0x04,0x08,0x08,0x08},
        {0x0e,0x11,0x11,0x0e,0x11,0x11,0x0e},
        {0x0e,0x11,0x11,0x0f,0x01,0x01,0x0e},
    };
    static const uint8_t letters[26][7] = {
        {0x0e,0x11,0x11,0x1f,0x11,0x11,0x11},
        {0x1e,0x11,0x11,0x1e,0x11,0x11,0x1e},
        {0x0e,0x11,0x10,0x10,0x10,0x11,0x0e},
        {0x1e,0x11,0x11,0x11,0x11,0x11,0x1e},
        {0x1f,0x10,0x10,0x1e,0x10,0x10,0x1f},
        {0x1f,0x10,0x10,0x1e,0x10,0x10,0x10},
        {0x0e,0x11,0x10,0x17,0x11,0x11,0x0f},
        {0x11,0x11,0x11,0x1f,0x11,0x11,0x11},
        {0x0e,0x04,0x04,0x04,0x04,0x04,0x0e},
        {0x07,0x02,0x02,0x02,0x12,0x12,0x0c},
        {0x11,0x12,0x14,0x18,0x14,0x12,0x11},
        {0x10,0x10,0x10,0x10,0x10,0x10,0x1f},
        {0x11,0x1b,0x15,0x15,0x11,0x11,0x11},
        {0x11,0x19,0x15,0x13,0x11,0x11,0x11},
        {0x0e,0x11,0x11,0x11,0x11,0x11,0x0e},
        {0x1e,0x11,0x11,0x1e,0x10,0x10,0x10},
        {0x0e,0x11,0x11,0x11,0x15,0x12,0x0d},
        {0x1e,0x11,0x11,0x1e,0x14,0x12,0x11},
        {0x0f,0x10,0x10,0x0e,0x01,0x01,0x1e},
        {0x1f,0x04,0x04,0x04,0x04,0x04,0x04},
        {0x11,0x11,0x11,0x11,0x11,0x11,0x0e},
        {0x11,0x11,0x11,0x11,0x11,0x0a,0x04},
        {0x11,0x11,0x11,0x15,0x15,0x15,0x0a},
        {0x11,0x11,0x0a,0x04,0x0a,0x11,0x11},
        {0x11,0x11,0x0a,0x04,0x04,0x04,0x04},
        {0x1f,0x01,0x02,0x04,0x08,0x10,0x1f},
    };

    if (row >= 7) {
        return 0;
    }
    if (c >= 'a' && c <= 'z') {
        c = (char)(c - 'a' + 'A');
    }
    if (c >= '0' && c <= '9') {
        return digits[c - '0'][row];
    }
    if (c >= 'A' && c <= 'Z') {
        return letters[c - 'A'][row];
    }
    switch (c) {
        case '.': return row == 6 ? 0x04 : 0x00;
        case ':': return row == 1 || row == 5 ? 0x04 : 0x00;
        case '-': return row == 3 ? 0x1f : 0x00;
        case '/': return (uint8_t)(0x01 << (6 - row > 4 ? 4 : 6 - row));
        default: return 0x00;
    }
}

static void draw_char(struct limine_framebuffer *fb,
                      uint64_t x, uint64_t y,
                      char c, uint64_t scale,
                      uint32_t colour) {
    for (uint8_t row = 0; row < 7; row++) {
        uint8_t bits = glyph5x7(c, row);
        for (uint8_t col = 0; col < 5; col++) {
            if ((bits & (uint8_t)(1u << (4 - col))) != 0) {
                fill_rect(fb, x + col * scale, y + row * scale, scale, scale, colour);
            }
        }
    }
}

static void draw_text(struct limine_framebuffer *fb,
                      uint64_t x, uint64_t y,
                      const char *text, uint64_t scale,
                      uint32_t colour) {
    while (*text != '\0') {
        draw_char(fb, x, y, *text, scale, colour);
        x += 6 * scale;
        text++;
    }
}

__attribute__((noreturn))
static void halt_forever(void) {
    for (;;) {
#if defined(__x86_64__)
        __asm__ volatile ("hlt");
#elif defined(__aarch64__)
        __asm__ volatile ("wfe");
#else
        __asm__ volatile ("");
#endif
    }
}

void _start(void) {
    struct limine_framebuffer_response *response = framebuffer_request.response;
    if (response != 0 && response->framebuffer_count > 0) {
        struct limine_framebuffer *fb = response->framebuffers[0];
        uint32_t background = make_pixel(fb, 8, 18, 28);
        uint32_t panel = make_pixel(fb, 14, 38, 48);
        uint32_t marker = make_pixel(fb, 0, 255, 96);
        uint32_t stripe = make_pixel(fb, 255, 0, 255);
        uint32_t text = make_pixel(fb, 230, 246, 238);
        uint32_t muted = make_pixel(fb, 156, 184, 176);

        fill_rect(fb, 0, 0, fb->width, fb->height, background);
        fill_rect(fb, fb->width / 10, fb->height / 5, fb->width * 4 / 5, fb->height * 3 / 5, panel);
        fill_rect(fb, fb->width / 10, fb->height / 5, fb->width * 4 / 5, 14, marker);
        fill_rect(fb, fb->width / 10, fb->height / 5 + 22, fb->width * 4 / 5, 6, stripe);

        draw_text(fb, fb->width / 10 + 32, fb->height / 5 + 56, "OS8 BOOT STUB", 4, text);
        draw_text(fb, fb->width / 10 + 32, fb->height / 5 + 118, "LIMINE HANDOFF OK", 3, marker);
        draw_text(fb, fb->width / 10 + 32, fb->height / 5 + 164, "XNU MACH-O STARTUP IS NOT IMPLEMENTED", 2, text);
        draw_text(fb, fb->width / 10 + 32, fb->height / 5 + 200, "THIS IMAGE CANNOT BOOT XNU YET", 2, muted);
        draw_text(fb, fb->width / 10 + 32, fb->height / 5 + 236, "BOOT STOPPED INTENTIONALLY", 2, muted);
        flush_framebuffer(fb);
    }

    halt_forever();
}
SOURCE

cat > "$linker" <<'SOURCE'
ENTRY(_start)

PHDRS
{
    requests PT_LOAD FLAGS(4);
    text PT_LOAD FLAGS(5);
    rodata PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = 0xffffffff80000000;

    .limine_requests : {
        KEEP(*(.limine_requests_start))
        KEEP(*(.limine_requests))
        KEEP(*(.limine_requests_end))
    } :requests

    . = ALIGN(0x1000);
    .text : {
        *(.text .text.*)
    } :text

    . = ALIGN(0x1000);
    .rodata : {
        *(.rodata .rodata.*)
    } :rodata

    . = ALIGN(0x1000);
    .data : {
        *(.data .data.*)
    } :data

    .bss : {
        *(COMMON)
        *(.bss .bss.*)
    } :data
}
SOURCE

case "$arch" in
    amd64)
        target=x86_64-unknown-elf
        linker_machine=elf_x86_64
        cflags="-mno-red-zone -mcmodel=kernel"
        ;;
    arm64)
        target=aarch64-unknown-elf
        linker_machine=aarch64elf
        cflags="-mcpu=generic -march=armv8-a+nofp+nosimd -mgeneral-regs-only"
        ;;
    *)
        echo "unsupported architecture: $arch" >&2
        exit 2
        ;;
esac

"$clang" \
    -target "$target" \
    -ffreestanding \
    -fno-stack-protector \
    -fno-pic \
    -fno-pie \
    -fno-builtin \
    -O2 \
    $cflags \
    -Wall \
    -Wextra \
    -c "$kernel_c" \
    -o "$object"

"$ld_lld" \
    -m "$linker_machine" \
    -no-pie \
    -z max-page-size=0x1000 \
    -T "$linker" \
    --build-id=none \
    "$object" \
    -o "$output"

file "$output"
