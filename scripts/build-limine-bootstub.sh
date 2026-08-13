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
clang="${CLANG:-${llvm_prefix:+$llvm_prefix/bin/clang}}"

if [ -z "$clang" ] || [ ! -x "$clang" ]; then
    clang="${CLANG:-clang}"
fi

command -v "$clang" >/dev/null 2>&1

mkdir -p "$work" "$(dirname "$output")"

kernel_c="$work/bootstub.c"
linker="$work/bootstub.ld"
object="$work/bootstub.o"

cat > "$kernel_c" <<'SOURCE'
#include <stdint.h>
#include <stddef.h>

#define LIMINE_COMMON_MAGIC 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b
#define LIMINE_FRAMEBUFFER_REQUEST { LIMINE_COMMON_MAGIC, 0x9d5827dcd881dd75, 0xa3148604f6fab11b }
#define LIMINE_BASE_REVISION(N) uint64_t limine_base_revision[3] = { 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, (N) }

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
static volatile LIMINE_BASE_REVISION(1);

__attribute__((used, section(".limine_requests")))
static volatile struct limine_framebuffer_request framebuffer_request = {
    .id = LIMINE_FRAMEBUFFER_REQUEST,
    .revision = 0,
    .response = 0
};

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
        uint32_t background = make_pixel(fb, 0, 64, 32);
        uint32_t marker = make_pixel(fb, 0, 255, 96);
        uint32_t stripe = make_pixel(fb, 255, 0, 255);

        fill_rect(fb, 0, 0, fb->width, fb->height, background);
        fill_rect(fb, fb->width / 8, fb->height / 3, fb->width * 3 / 4, fb->height / 5, marker);
        fill_rect(fb, fb->width / 8, fb->height / 3 + fb->height / 5 + 12, fb->width * 3 / 4, 18, stripe);
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
        KEEP(*(.limine_requests))
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
        cflags="-mno-red-zone -mcmodel=kernel"
        ;;
    arm64)
        target=aarch64-unknown-elf
        cflags=""
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

"$clang" \
    -target "$target" \
    -nostdlib \
    -fuse-ld=lld \
    -Wl,-no-pie \
    -Wl,-T,"$linker" \
    -Wl,--build-id=none \
    "$object" \
    -o "$output"

file "$output"
