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
handoff_debug="${XNU_HANDOFF_DEBUG:-0}"

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
#define LIMINE_MODULE_REQUEST { LIMINE_COMMON_MAGIC, 0x3e7e279702be32af, 0xca1c4f3bd1280cee }
#define LIMINE_HHDM_REQUEST { LIMINE_COMMON_MAGIC, 0x48dcf1cb8ad2b852, 0x63984e959a98244b }
#define LIMINE_MEMMAP_REQUEST { LIMINE_COMMON_MAGIC, 0x67cf3d9d378a806f, 0xe304acdfc50c3c62 }
#define LIMINE_EFI_SYSTEM_TABLE_REQUEST { LIMINE_COMMON_MAGIC, 0x5ceba5163eaaf6d6, 0x0a6981610cf65fcc }
#define LIMINE_EFI_MEMMAP_REQUEST { LIMINE_COMMON_MAGIC, 0x7df62a431d6872d5, 0xa4fcdfb3e57306c8 }
#define LIMINE_RSDP_REQUEST { LIMINE_COMMON_MAGIC, 0xc5e77b6b397e7b43, 0x27637845accdcf3c }
#define LIMINE_EXECUTABLE_ADDRESS_REQUEST { LIMINE_COMMON_MAGIC, 0x71ba76863cc55f63, 0xb2644a48c516a487 }
#define LIMINE_INTERNAL_MODULE_REQUIRED (1 << 0)
#define LIMINE_REQUESTS_START_MARKER { 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9 }
#define LIMINE_REQUESTS_END_MARKER { 0xadc0e0531bb10d03, 0x9572709f31764c62 }
#define LIMINE_BASE_REVISION(N) { 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, (N) }
#define LIMINE_MEMMAP_USABLE 0
#define LIMINE_MEMMAP_RESERVED 1
#define LIMINE_MEMMAP_ACPI_RECLAIMABLE 2
#define LIMINE_MEMMAP_ACPI_NVS 3
#define LIMINE_MEMMAP_BAD_MEMORY 4
#define LIMINE_MEMMAP_BOOTLOADER_RECLAIMABLE 5
#define LIMINE_MEMMAP_KERNEL_AND_MODULES 6
#define LIMINE_MEMMAP_FRAMEBUFFER 7

__attribute__((used, section(".limine_requests_start")))
static volatile uint64_t limine_requests_start_marker[4] = LIMINE_REQUESTS_START_MARKER;

struct limine_uuid {
    uint32_t a;
    uint16_t b;
    uint16_t c;
    uint8_t d[8];
};

struct limine_file {
    uint64_t revision;
    void *address;
    uint64_t size;
    char *path;
    char *cmdline;
    uint32_t media_type;
    uint32_t unused;
    uint32_t tftp_ip;
    uint32_t tftp_port;
    uint32_t partition_index;
    uint32_t mbr_disk_id;
    struct limine_uuid gpt_disk_uuid;
    struct limine_uuid gpt_part_uuid;
    struct limine_uuid part_uuid;
};

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

struct limine_internal_module {
    const char *path;
    const char *cmdline;
    uint64_t flags;
};

struct limine_module_response {
    uint64_t revision;
    uint64_t module_count;
    struct limine_file **modules;
};

struct limine_module_request {
    uint64_t id[4];
    uint64_t revision;
    struct limine_module_response *response;
    uint64_t internal_module_count;
    struct limine_internal_module **internal_modules;
};

struct limine_hhdm_response {
    uint64_t revision;
    uint64_t offset;
};

struct limine_hhdm_request {
    uint64_t id[4];
    uint64_t revision;
    struct limine_hhdm_response *response;
};

struct limine_memmap_entry {
    uint64_t base;
    uint64_t length;
    uint64_t type;
};

struct limine_memmap_response {
    uint64_t revision;
    uint64_t entry_count;
    struct limine_memmap_entry **entries;
};

struct limine_memmap_request {
    uint64_t id[4];
    uint64_t revision;
    struct limine_memmap_response *response;
};

struct limine_efi_system_table_response {
    uint64_t revision;
    void *address;
};

struct limine_efi_system_table_request {
    uint64_t id[4];
    uint64_t revision;
    struct limine_efi_system_table_response *response;
};

struct limine_efi_memmap_response {
    uint64_t revision;
    void *memmap;
    uint64_t memmap_size;
    uint64_t desc_size;
    uint64_t desc_version;
};

struct limine_efi_memmap_request {
    uint64_t id[4];
    uint64_t revision;
    struct limine_efi_memmap_response *response;
};

struct limine_rsdp_response {
    uint64_t revision;
    void *address;
};

struct limine_rsdp_request {
    uint64_t id[4];
    uint64_t revision;
    struct limine_rsdp_response *response;
};

struct limine_executable_address_response {
    uint64_t revision;
    uint64_t physical_base;
    uint64_t virtual_base;
};

struct limine_executable_address_request {
    uint64_t id[4];
    uint64_t revision;
    struct limine_executable_address_response *response;
};

__attribute__((used, section(".limine_requests")))
static volatile uint64_t limine_base_revision[3] = LIMINE_BASE_REVISION(6);

__attribute__((used, section(".limine_requests")))
static volatile struct limine_framebuffer_request framebuffer_request = {
    .id = LIMINE_FRAMEBUFFER_REQUEST,
    .revision = 0,
    .response = 0
};

static const char xnu_module_path[] = "boot():/boot/xnu-kernel.macho";
static const char xnu_module_cmdline[] = "xnu-kernel";

__attribute__((used, section(".limine_requests")))
static volatile struct limine_module_request module_request = {
    .id = LIMINE_MODULE_REQUEST,
    .revision = 0,
    .response = 0,
    .internal_module_count = 0,
    .internal_modules = 0
};

__attribute__((used, section(".limine_requests")))
static volatile struct limine_hhdm_request hhdm_request = {
    .id = LIMINE_HHDM_REQUEST,
    .revision = 0,
    .response = 0
};

__attribute__((used, section(".limine_requests")))
static volatile struct limine_memmap_request memmap_request = {
    .id = LIMINE_MEMMAP_REQUEST,
    .revision = 0,
    .response = 0
};

__attribute__((used, section(".limine_requests")))
static volatile struct limine_efi_system_table_request efi_system_table_request = {
    .id = LIMINE_EFI_SYSTEM_TABLE_REQUEST,
    .revision = 0,
    .response = 0
};

__attribute__((used, section(".limine_requests")))
static volatile struct limine_efi_memmap_request efi_memmap_request = {
    .id = LIMINE_EFI_MEMMAP_REQUEST,
    .revision = 0,
    .response = 0
};

__attribute__((used, section(".limine_requests")))
static volatile struct limine_rsdp_request rsdp_request = {
    .id = LIMINE_RSDP_REQUEST,
    .revision = 0,
    .response = 0
};

__attribute__((used, section(".limine_requests")))
static volatile struct limine_executable_address_request executable_address_request = {
    .id = LIMINE_EXECUTABLE_ADDRESS_REQUEST,
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

static struct limine_framebuffer *debug_fb;

#if XNU_HANDOFF_DEBUG
static void debug_stage(uint64_t stage, uint8_t r, uint8_t g, uint8_t b) {
    if (debug_fb == 0) {
        return;
    }
    fill_rect(debug_fb, 24 + stage * 24, 136, 18, 18, make_pixel(debug_fb, r, g, b));
    flush_framebuffer(debug_fb);
}
#else
static void debug_stage(uint64_t stage, uint8_t r, uint8_t g, uint8_t b) {
    (void)stage;
    (void)r;
    (void)g;
    (void)b;
}
#endif

static char boot_log_buffer[8192];
static uint64_t boot_log_len;

static void boot_log_append(const char *s) {
    while (*s != '\0' && boot_log_len + 1 < sizeof(boot_log_buffer)) {
        boot_log_buffer[boot_log_len++] = *s;
        s++;
    }
    boot_log_buffer[boot_log_len] = '\0';
}

static void boot_log_append_char(char c) {
    if (boot_log_len + 1 < sizeof(boot_log_buffer)) {
        boot_log_buffer[boot_log_len++] = c;
        boot_log_buffer[boot_log_len] = '\0';
    }
}

static void serial_putc(char c) {
#if defined(__x86_64__)
    __asm__ volatile ("outb %0, %1" :: "a"((uint8_t)c), "Nd"((uint16_t)0x3f8));
#else
    (void)c;
#endif
}

static void serial_write(const char *s) {
    while (*s != '\0') {
        if (*s == '\n') {
            serial_putc('\r');
            boot_log_append_char('\n');
        }
        serial_putc(*s);
        boot_log_append_char(*s);
        s++;
    }
}

static void serial_hex64(uint64_t value) {
    static const char hexdigits[] = "0123456789abcdef";
    serial_write("0x");
    for (int i = 0; i < 16; i++) {
        serial_putc(hexdigits[(value >> ((15 - i) * 4)) & 0xf]);
    }
}

static void serial_key_hex(const char *key, uint64_t value) {
    serial_write("os8-handoff: ");
    serial_write(key);
    serial_write("=");
    serial_hex64(value);
    serial_write("\n");
}

static void configure_framebuffer_handoff(struct limine_framebuffer *fb,
                                         uint64_t *fb_phys_out,
                                         uint64_t *fb_pitch_out,
                                         uint64_t *fb_width_out,
                                         uint64_t *fb_height_out,
                                         uint32_t *fb_bpp_out);

#if defined(__aarch64__)
static void flush_range_to_poc(const void *address, uint64_t size) {
    uint64_t ctr_el0;
    __asm__ volatile ("mrs %0, ctr_el0" : "=r"(ctr_el0));
    uint64_t line_size = 4ull << ((ctr_el0 >> 16) & 0xf);
    uintptr_t start = (uintptr_t)address;
    uintptr_t end = start + size;
    start &= ~(uintptr_t)(line_size - 1);

    for (uintptr_t p = start; p < end; p += line_size) {
        __asm__ volatile ("dc cvac, %0" :: "r"(p) : "memory");
        __asm__ volatile ("ic ivau, %0" :: "r"(p) : "memory");
    }
    __asm__ volatile ("dsb sy; isb" ::: "memory");
}
#endif

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

static void draw_boot_log(struct limine_framebuffer *fb,
                         uint64_t x, uint64_t y,
                         uint32_t colour) {
    if (boot_log_len == 0) {
        return;
    }

    char line[96];
    uint64_t line_y = y;
    const char *cursor = boot_log_buffer;
    uint64_t line_index = 0;

    while (*cursor != '\0' && line_index < 10) {
        uint64_t i = 0;
        while (*cursor != '\0' && *cursor != '\n' && i + 1 < sizeof(line)) {
            line[i++] = *cursor++;
        }
        line[i] = '\0';
        if (i == 0 && *cursor == '\n') {
            cursor++;
            continue;
        }
        draw_text(fb, x, line_y, line, 2, colour);
        line_y += 20;
        line_index++;
        if (*cursor == '\n') {
            cursor++;
        }
    }
}

static int streq(const char *a, const char *b) {
    if (a == 0 || b == 0) {
        return 0;
    }
    while (*a != '\0' && *b != '\0') {
        if (*a != *b) {
            return 0;
        }
        a++;
        b++;
    }
    return *a == *b;
}

static void memzero(void *dst, uint64_t size) {
    uint8_t *p = (uint8_t *)dst;
    for (uint64_t i = 0; i < size; i++) {
        p[i] = 0;
    }
}

static void memcopy(void *dst, const void *src, uint64_t size) {
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    for (uint64_t i = 0; i < size; i++) {
        d[i] = s[i];
    }
}

static void strcopy_bounded(char *dst, uint64_t dst_size, const char *src) {
    if (dst_size == 0) {
        return;
    }
    uint64_t i = 0;
    while (i + 1 < dst_size && src[i] != '\0') {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

static uint64_t align_up(uint64_t value, uint64_t alignment) {
    return (value + alignment - 1) & ~(alignment - 1);
}

static uint64_t align_down(uint64_t value, uint64_t alignment) {
    return value & ~(alignment - 1);
}

static uint64_t virt_to_phys(void *ptr) {
    struct limine_hhdm_response *hhdm = hhdm_request.response;
    uint64_t addr = (uint64_t)(uintptr_t)ptr;
    if (hhdm != 0 && addr >= hhdm->offset) {
        return addr - hhdm->offset;
    }
    return addr;
}

struct boot_allocator {
    uint64_t cursor;
    uint64_t base;
    uint64_t size;
};

static int init_boot_allocator(struct boot_allocator *allocator, uint64_t reserve_size) {
    struct limine_memmap_response *memmap = memmap_request.response;
    struct limine_hhdm_response *hhdm = hhdm_request.response;
    if (memmap == 0 || hhdm == 0) {
        return 0;
    }

    uint64_t best_base = 0;
    uint64_t best_size = 0;
    for (uint64_t i = 0; i < memmap->entry_count; i++) {
        struct limine_memmap_entry *entry = memmap->entries[i];
        if (entry == 0 || entry->type != LIMINE_MEMMAP_USABLE) {
            continue;
        }
        uint64_t base = align_up(entry->base, 0x1000);
        uint64_t end = align_down(entry->base + entry->length, 0x1000);
#if defined(__x86_64__)
        if (end > 0xffffffffULL) {
            end = 0xffffffffULL & ~0xfffULL;
        }
#endif
        if (end <= base || end - base < reserve_size) {
            continue;
        }
        if (end - base > best_size) {
            best_base = base;
            best_size = end - base;
        }
    }

    if (best_size == 0) {
        return 0;
    }

    allocator->base = align_up(best_base, 0x1000);
    allocator->size = reserve_size;
    allocator->cursor = allocator->base;
    memzero((void *)(uintptr_t)(hhdm->offset + allocator->base), reserve_size);
    return 1;
}

static void *boot_alloc(struct boot_allocator *allocator,
                        uint64_t size,
                        uint64_t alignment,
                        uint64_t *phys_out) {
    struct limine_hhdm_response *hhdm = hhdm_request.response;
    if (hhdm == 0) {
        return 0;
    }
    uint64_t phys = align_up(allocator->cursor, alignment);
    if (phys < allocator->base || phys + size > allocator->base + allocator->size) {
        return 0;
    }
    allocator->cursor = phys + size;
    if (phys_out != 0) {
        *phys_out = phys;
    }
    return (void *)(uintptr_t)(hhdm->offset + phys);
}

static struct limine_file *find_xnu_module(void) {
    struct limine_module_response *response = module_request.response;
    if (response == 0) {
        return 0;
    }
    for (uint64_t i = 0; i < response->module_count; i++) {
        struct limine_file *module = response->modules[i];
        if (module == 0) {
            continue;
        }
        if (streq(module->cmdline, xnu_module_cmdline) || streq(module->path, xnu_module_path)) {
            return module;
        }
    }
    return 0;
}

static const uint8_t *module_data(const struct limine_file *file) {
    if (file == 0 || file->address == 0) {
        return 0;
    }
    struct limine_hhdm_response *hhdm = hhdm_request.response;
    uintptr_t address = (uintptr_t)file->address;
    if (hhdm != 0) {
        if (address < hhdm->offset) {
            address += hhdm->offset;
        }
    } else if (address < 0xffff800000000000ULL) {
        return 0;
    }
    return (const uint8_t *)address;
}

#define MH_MAGIC_64 0xfeedfacfU
#define MH_CIGAM_64 0xcffaedfeU
#define FAT_MAGIC 0xcafebabeU
#define FAT_CIGAM 0xbebafecaU
#define FAT_MAGIC_64 0xcafebabfU
#define FAT_CIGAM_64 0xbfbafecaU
#define CPU_TYPE_X86_64 0x01000007U
#define CPU_TYPE_ARM64 0x0100000cU
#define LC_SEGMENT_64 0x19U
#define LC_UNIXTHREAD 0x5U
#define LC_MAIN 0x80000028U
#define X86_THREAD_STATE64 4U
#define ARM_THREAD_STATE64 6U

#if defined(__x86_64__)
#define XNU_CPU_TYPE CPU_TYPE_X86_64
#elif defined(__aarch64__)
#define XNU_CPU_TYPE CPU_TYPE_ARM64
#else
#define XNU_CPU_TYPE 0
#endif

struct macho_preflight {
    const uint8_t *image;
    uint64_t size;
    uint64_t slice_offset;
    uint64_t slice_size;
    uint64_t vm_min;
    uint64_t vm_max;
    uint64_t file_highest;
    uint64_t entry;
    uint32_t cpu_type;
    uint32_t ncmds;
    uint32_t status;
};

#define XNU_BOOT_LINE_LENGTH 1024
#define XNU_GRAPHICS_MODE 1
#define XNU_BOOT_ARGS_VERSION 2
#define XNU_BOOT_ARGS_REVISION_X86 0
#define XNU_BOOT_ARGS_REVISION_ARM64 2
#define XNU_EFI_MODE_64 64
#define XNU_BOOT_ARG_RESERVE (128 * 1024)

struct xnu_boot_video_x86_v1 {
    uint32_t base_addr;
    uint32_t display;
    uint32_t row_bytes;
    uint32_t width;
    uint32_t height;
    uint32_t depth;
};

struct xnu_boot_video_x86 {
    uint32_t display;
    uint32_t row_bytes;
    uint32_t width;
    uint32_t height;
    uint32_t depth;
    uint8_t rotate;
    uint8_t reserved_byte[3];
    uint32_t reserved[6];
    uint64_t base_addr;
};

struct xnu_efi_memory_range {
    uint32_t type;
    uint32_t pad;
    uint64_t physical_start;
    uint64_t virtual_start;
    uint64_t number_of_pages;
    uint64_t attribute;
};

struct xnu_boot_args_x86 {
    uint16_t revision;
    uint16_t version;
    uint8_t efi_mode;
    uint8_t debug_mode;
    uint16_t flags;
    char command_line[XNU_BOOT_LINE_LENGTH];
    uint32_t memory_map;
    uint32_t memory_map_size;
    uint32_t memory_map_descriptor_size;
    uint32_t memory_map_descriptor_version;
    struct xnu_boot_video_x86_v1 video_v1;
    uint32_t device_tree_p;
    uint32_t device_tree_length;
    uint32_t kaddr;
    uint32_t ksize;
    uint32_t efi_runtime_services_page_start;
    uint32_t efi_runtime_services_page_count;
    uint64_t efi_runtime_services_virtual_page_start;
    uint32_t efi_system_table;
    uint32_t kslide;
    uint32_t performance_data_start;
    uint32_t performance_data_size;
    uint32_t key_store_data_start;
    uint32_t key_store_data_size;
    uint64_t boot_mem_start;
    uint64_t boot_mem_size;
    uint64_t physical_memory_size;
    uint64_t fsb_frequency;
    uint64_t pci_config_space_base_address;
    uint32_t pci_config_space_start_bus_number;
    uint32_t pci_config_space_end_bus_number;
    uint32_t csr_active_config;
    uint32_t csr_capabilities;
    uint32_t boot_smc_plimit;
    uint16_t boot_progress_meter_start;
    uint16_t boot_progress_meter_end;
    struct xnu_boot_video_x86 video;
    uint32_t apfs_data_start;
    uint32_t apfs_data_size;
    uint64_t kc_hdrs_vaddr;
    uint64_t arv_root_hash_start;
    uint64_t arv_root_hash_size;
    uint64_t arv_manifest_start;
    uint64_t arv_manifest_size;
    uint64_t bs_arv_root_hash_start;
    uint64_t bs_arv_root_hash_size;
    uint64_t bs_arv_manifest_start;
    uint64_t bs_arv_manifest_size;
    uint32_t reserved4[692];
};

struct xnu_boot_video_arm64 {
    uint64_t base_addr;
    uint64_t display;
    uint64_t row_bytes;
    uint64_t width;
    uint64_t height;
    uint64_t depth;
};

struct xnu_boot_args_arm64 {
    uint16_t revision;
    uint16_t version;
    uint64_t virt_base;
    uint64_t phys_base;
    uint64_t mem_size;
    uint64_t top_of_kernel_data;
    struct xnu_boot_video_arm64 video;
    uint32_t machine_type;
    void *device_tree_p;
    uint32_t device_tree_length;
    char command_line[XNU_BOOT_LINE_LENGTH];
    uint64_t boot_flags;
    uint64_t mem_size_actual;
};

#define STATIC_ASSERT(name, condition) typedef char static_assert_##name[(condition) ? 1 : -1]
#define OFFSET_OF(type, member) ((uint64_t)__builtin_offsetof(type, member))

STATIC_ASSERT(x86_boot_args_size, sizeof(struct xnu_boot_args_x86) == 4096);
STATIC_ASSERT(x86_command_line_offset, OFFSET_OF(struct xnu_boot_args_x86, command_line) == 8);
STATIC_ASSERT(x86_device_tree_offset, OFFSET_OF(struct xnu_boot_args_x86, device_tree_p) == 1072);
STATIC_ASSERT(x86_physical_memory_size_offset, OFFSET_OF(struct xnu_boot_args_x86, physical_memory_size) == 1144);
STATIC_ASSERT(arm64_boot_args_size, sizeof(struct xnu_boot_args_arm64) == 1152);
STATIC_ASSERT(arm64_virt_base_offset, OFFSET_OF(struct xnu_boot_args_arm64, virt_base) == 8);
STATIC_ASSERT(arm64_device_tree_offset, OFFSET_OF(struct xnu_boot_args_arm64, device_tree_p) == 96);
STATIC_ASSERT(arm64_device_tree_length_offset, OFFSET_OF(struct xnu_boot_args_arm64, device_tree_length) == 104);
STATIC_ASSERT(arm64_boot_flags_offset, OFFSET_OF(struct xnu_boot_args_arm64, boot_flags) == 1136);
STATIC_ASSERT(arm64_mem_size_actual_offset, OFFSET_OF(struct xnu_boot_args_arm64, mem_size_actual) == 1144);

struct xnu_handoff {
    void *boot_args;
    uint64_t boot_args_phys;
    uint64_t identity_pagetable_phys;
    uint64_t memory_map_phys;
    uint64_t memory_map_size;
    uint64_t allocator_base;
    uint64_t allocator_used;
    uint64_t physical_memory_size;
    uint64_t memory_map_descriptor_size;
    uint64_t efi_runtime_services_page_start;
    uint64_t efi_runtime_services_page_count;
    uint64_t efi_runtime_services_virtual_page_start;
    uint64_t efi_system_table_phys;
    uint64_t kernel_phys;
    uint64_t kernel_size;
    uint64_t kernel_entry_phys;
    uint64_t kernel_entry_virt;
    uint64_t top_of_kernel_data;
    uint64_t jump_stack_phys;
    uint64_t jump_stack_size;
    uint32_t status;
};

static int try_jump_xnu(const struct xnu_handoff *handoff);

struct apple_dt_node {
    uint32_t n_properties;
    uint32_t n_children;
};

struct apple_dt_property {
    char name[32];
    uint32_t length;
};

struct mach_header_64 {
    uint32_t magic;
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t filetype;
    uint32_t ncmds;
    uint32_t sizeofcmds;
    uint32_t flags;
    uint32_t reserved;
};

struct load_command {
    uint32_t cmd;
    uint32_t cmdsize;
};

struct segment_command_64 {
    uint32_t cmd;
    uint32_t cmdsize;
    char segname[16];
    uint64_t vmaddr;
    uint64_t vmsize;
    uint64_t fileoff;
    uint64_t filesize;
    uint32_t maxprot;
    uint32_t initprot;
    uint32_t nsects;
    uint32_t flags;
};

struct entry_point_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint64_t entryoff;
    uint64_t stacksize;
};

struct thread_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t flavor;
    uint32_t count;
};

struct fat_header {
    uint32_t magic;
    uint32_t nfat_arch;
};

struct fat_arch {
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t offset;
    uint32_t size;
    uint32_t align;
};

struct fat_arch_64 {
    uint32_t cputype;
    uint32_t cpusubtype;
    uint64_t offset;
    uint64_t size;
    uint32_t align;
    uint32_t reserved;
};

static uint32_t bswap32(uint32_t value) {
    return ((value & 0x000000ffU) << 24)
         | ((value & 0x0000ff00U) << 8)
         | ((value & 0x00ff0000U) >> 8)
         | ((value & 0xff000000U) >> 24);
}

static uint64_t bswap64(uint64_t value) {
    return ((uint64_t)bswap32((uint32_t)value) << 32)
         | (uint64_t)bswap32((uint32_t)(value >> 32));
}

#if defined(__aarch64__)
#define ARM64_TABLE_DESC 0x3ULL
#define ARM64_BLOCK_DESC 0x701ULL
#define ARM64_L1_BLOCK_SIZE 0x40000000ULL

static int build_arm64_identity_map(struct boot_allocator *allocator, uint64_t *table_phys_out) {
    uint64_t l0_phys = 0;
    uint64_t l1_phys = 0;
    uint64_t *l0 = (uint64_t *)boot_alloc(allocator, 0x1000, 0x1000, &l0_phys);
    uint64_t *l1 = (uint64_t *)boot_alloc(allocator, 0x1000, 0x1000, &l1_phys);
    if (l0 == 0 || l1 == 0) {
        return 0;
    }

    memzero(l0, 0x1000);
    memzero(l1, 0x1000);
    l0[0] = (l1_phys & 0x0000fffffffff000ULL) | ARM64_TABLE_DESC;
    for (uint64_t i = 0; i < 512; i++) {
        uint64_t phys = i * ARM64_L1_BLOCK_SIZE;
        l1[i] = (phys & 0x0000ffffc0000000ULL) | ARM64_BLOCK_DESC;
    }

    *table_phys_out = l0_phys;
    return 1;
}
#endif

#if defined(__x86_64__)

#define X86_PAGE_PRESENT 0x001ULL
#define X86_PAGE_WRITE   0x002ULL
#define X86_PAGE_PS      0x080ULL
#define X86_PAGE_NX      0x8000000000000000ULL
#define X86_PAGE_TABLE_FLAGS (X86_PAGE_PRESENT | X86_PAGE_WRITE)
#define X86_LARGE_PAGE_FLAGS (X86_PAGE_PRESENT | X86_PAGE_WRITE | X86_PAGE_PS)
#define X86_PAGE_FLAGS (X86_PAGE_PRESENT | X86_PAGE_WRITE)
#define X86_PT_MASK 0x000ffffffffff000ULL
#define X86_2M   0x00200000ULL
#define X86_1G   0x40000000ULL
#define X86_512G 0x8000000000ULL
#define X86_XNU_STATIC_BASE 0xffffff8000000000ULL
#define X86_EFI_MEMORY_RUNTIME 0x8000000000000000ULL

static int map_x86_2m_page(struct boot_allocator *allocator,
                           uint64_t *pml4,
                           uint64_t hhdm_offset,
                           uint64_t virtual_address,
                           uint64_t physical_address) {
    uint64_t pml4_index = (virtual_address >> 39) & 0x1ff;
    uint64_t pdpt_index = (virtual_address >> 30) & 0x1ff;
    uint64_t pd_index = (virtual_address >> 21) & 0x1ff;

    uint64_t pdpt_phys = pml4[pml4_index] & 0x000ffffffffff000ULL;
    uint64_t *pdpt = 0;
    if (pdpt_phys == 0) {
        pdpt = (uint64_t *)boot_alloc(allocator, 0x1000, 0x1000, &pdpt_phys);
        if (pdpt == 0) {
            return 0;
        }
        memzero(pdpt, 0x1000);
        pml4[pml4_index] = pdpt_phys | X86_PAGE_TABLE_FLAGS;
    } else {
        pdpt = (uint64_t *)(uintptr_t)(hhdm_offset + pdpt_phys);
    }

    uint64_t pd_phys = pdpt[pdpt_index] & 0x000ffffffffff000ULL;
    uint64_t *pd = 0;
    if (pd_phys == 0) {
        pd = (uint64_t *)boot_alloc(allocator, 0x1000, 0x1000, &pd_phys);
        if (pd == 0) {
            return 0;
        }
        memzero(pd, 0x1000);
        pdpt[pdpt_index] = pd_phys | X86_PAGE_TABLE_FLAGS;
    } else {
        pd = (uint64_t *)(uintptr_t)(hhdm_offset + pd_phys);
    }

    pd[pd_index] =
        (physical_address & 0x000fffffffe00000ULL) | X86_LARGE_PAGE_FLAGS;
    return 1;
}

static int map_x86_4k_page(struct boot_allocator *allocator,
                           uint64_t *pml4,
                           uint64_t hhdm_offset,
                           uint64_t virtual_address,
                           uint64_t physical_address) {
    uint64_t pml4_index = (virtual_address >> 39) & 0x1ff;
    uint64_t pdpt_index = (virtual_address >> 30) & 0x1ff;
    uint64_t pd_index = (virtual_address >> 21) & 0x1ff;
    uint64_t pt_index = (virtual_address >> 12) & 0x1ff;

    uint64_t pdpt_phys = pml4[pml4_index] & X86_PT_MASK;
    uint64_t *pdpt = 0;
    if (pdpt_phys == 0) {
        pdpt = (uint64_t *)boot_alloc(allocator, 0x1000, 0x1000, &pdpt_phys);
        if (pdpt == 0) {
            return 0;
        }
        memzero(pdpt, 0x1000);
        pml4[pml4_index] = pdpt_phys | X86_PAGE_TABLE_FLAGS;
    } else {
        pdpt = (uint64_t *)(uintptr_t)(hhdm_offset + pdpt_phys);
    }

    uint64_t pd_phys = pdpt[pdpt_index] & X86_PT_MASK;
    uint64_t *pd = 0;
    if (pd_phys == 0) {
        pd = (uint64_t *)boot_alloc(allocator, 0x1000, 0x1000, &pd_phys);
        if (pd == 0) {
            return 0;
        }
        memzero(pd, 0x1000);
        pdpt[pdpt_index] = pd_phys | X86_PAGE_TABLE_FLAGS;
    } else {
        pd = (uint64_t *)(uintptr_t)(hhdm_offset + pd_phys);
    }

    if ((pd[pd_index] & X86_PAGE_PS) != 0) {
        serial_write("os8-handoff: x86 4k map hit large page\n");
        return 0;
    }

    uint64_t pt_phys = pd[pd_index] & X86_PT_MASK;
    uint64_t *pt = 0;
    if (pt_phys == 0) {
        pt = (uint64_t *)boot_alloc(allocator, 0x1000, 0x1000, &pt_phys);
        if (pt == 0) {
            return 0;
        }
        memzero(pt, 0x1000);
        pd[pd_index] = pt_phys | X86_PAGE_TABLE_FLAGS;
    } else {
        pt = (uint64_t *)(uintptr_t)(hhdm_offset + pt_phys);
    }

    pt[pt_index] = (physical_address & X86_PT_MASK) | X86_PAGE_FLAGS;
    return 1;
}

static int map_x86_4k_range(struct boot_allocator *allocator,
                            uint64_t *pml4,
                            uint64_t hhdm_offset,
                            uint64_t virtual_base,
                            uint64_t physical_base,
                            uint64_t size) {
    uint64_t virtual_start = align_down(virtual_base, 0x1000);
    uint64_t virtual_delta = virtual_base - virtual_start;
    uint64_t physical_start = physical_base - virtual_delta;
    uint64_t mapped_size = align_up(size + virtual_delta, 0x1000);

    for (uint64_t offset = 0; offset < mapped_size; offset += 0x1000) {
        if (!map_x86_4k_page(allocator,
                             pml4,
                             hhdm_offset,
                             virtual_start + offset,
                             physical_start + offset)) {
            return 0;
        }
    }
    return 1;
}

static int map_x86_2m_range(struct boot_allocator *allocator,
                            uint64_t *pml4,
                            uint64_t hhdm_offset,
                            uint64_t virtual_base,
                            uint64_t physical_base,
                            uint64_t size) {
    uint64_t virtual_start = align_down(virtual_base, X86_2M);
    uint64_t physical_start = align_down(physical_base, X86_2M);
    uint64_t virtual_delta = virtual_base - virtual_start;
    uint64_t mapped_size = align_up(size + virtual_delta, X86_2M);

    for (uint64_t offset = 0; offset < mapped_size; offset += X86_2M) {
        if (!map_x86_2m_page(allocator,
                             pml4,
                             hhdm_offset,
                             virtual_start + offset,
                             physical_start + offset)) {
            return 0;
        }
    }
    return 1;
}

static int build_x86_bootstrap_map(
    struct boot_allocator *allocator,
    uint64_t hhdm_offset,
    uint64_t executable_virtual_base,
    uint64_t executable_physical_base,
    uint64_t transition_virtual_address,
    uint64_t transition_physical_address,
    uint64_t kernel_virtual_base,
    uint64_t kernel_physical_base,
    uint64_t kernel_size,
    uint64_t static_map_size,
    uint64_t max_phys,
    uint64_t *pml4_phys_out
) {
    uint64_t pml4_phys = 0;
    uint64_t pdpt_phys = 0;

    uint64_t *pml4 = (uint64_t *)boot_alloc(
        allocator, 0x1000, 0x1000, &pml4_phys);
    uint64_t *pdpt = (uint64_t *)boot_alloc(
        allocator, 0x1000, 0x1000, &pdpt_phys);

    if (pml4 == 0 || pdpt == 0) {
        return 0;
    }

    memzero(pml4, 0x1000);
    memzero(pdpt, 0x1000);

    pml4[0] =
        (pdpt_phys & 0x000ffffffffff000ULL) | X86_PAGE_TABLE_FLAGS;
    pml4[511] =
        (pdpt_phys & 0x000ffffffffff000ULL) | X86_PAGE_TABLE_FLAGS;

    if (max_phys < X86_1G) {
        max_phys = X86_1G;
    }

    uint64_t gigabyte_count =
        align_up(max_phys, X86_1G) / X86_1G;

    if (gigabyte_count > 512) {
        gigabyte_count = 512;
    }

    serial_key_hex("x86-map-max-phys", max_phys);
    serial_key_hex("x86-map-gigabytes", gigabyte_count);

    for (uint64_t gigabyte = 0;
         gigabyte < gigabyte_count;
         gigabyte++) {
        uint64_t pd_phys = 0;
        uint64_t *pd = (uint64_t *)boot_alloc(
            allocator, 0x1000, 0x1000, &pd_phys);

        if (pd == 0) {
            return 0;
        }

        memzero(pd, 0x1000);
        pdpt[gigabyte] =
            (pd_phys & 0x000ffffffffff000ULL) | X86_PAGE_TABLE_FLAGS;

        for (uint64_t page = 0; page < 512; page++) {
            uint64_t physical = gigabyte * X86_1G + page * X86_2M;
            pd[page] =
                (physical & 0x000fffffffe00000ULL) | X86_LARGE_PAGE_FLAGS;
        }
    }

    if ((hhdm_offset & (X86_512G - 1)) != 0) {
        serial_write("os8-handoff: x86 hhdm is not PML4 aligned\n");
        return 0;
    }

    uint64_t hhdm_slot = (hhdm_offset >> 39) & 0x1ff;
    pml4[hhdm_slot] =
        (pdpt_phys & 0x000ffffffffff000ULL) | X86_PAGE_TABLE_FLAGS;

    serial_key_hex("x86-exec-virt", executable_virtual_base);
    serial_key_hex("x86-exec-phys", executable_physical_base);
    serial_key_hex("x86-transition-virt", transition_virtual_address);
    serial_key_hex("x86-transition-phys", transition_physical_address);

    if (executable_virtual_base != 0 &&
        executable_physical_base != 0 &&
        !map_x86_4k_range(allocator,
                           pml4,
                           hhdm_offset,
                           executable_virtual_base,
                           executable_physical_base,
                           X86_2M)) {
        return 0;
    }

    if (transition_virtual_address != 0 &&
        transition_physical_address != 0 &&
        !map_x86_4k_range(allocator,
                           pml4,
                           hhdm_offset,
                           transition_virtual_address,
                           transition_physical_address,
                           X86_2M)) {
        return 0;
    }

    if (kernel_virtual_base != 0 &&
        kernel_physical_base != 0 &&
        kernel_size != 0 &&
        !map_x86_2m_range(allocator,
                          pml4,
                          hhdm_offset,
                          kernel_virtual_base,
                          kernel_physical_base,
                          kernel_size)) {
        return 0;
    }

    if (static_map_size != 0 &&
        !map_x86_2m_range(allocator,
                          pml4,
                          hhdm_offset,
                          X86_XNU_STATIC_BASE,
                          0,
                          static_map_size)) {
        return 0;
    }

    *pml4_phys_out = pml4_phys;
    serial_key_hex("x86-bootstrap-pml4", pml4_phys);
    serial_key_hex("x86-hhdm-slot", hhdm_slot);
    return 1;
}

#endif

static int range_ok(uint64_t base, uint64_t size, uint64_t need) {
    return base <= size && need <= size - base;
}

static int parse_macho_slice(struct macho_preflight *out,
                             const uint8_t *image,
                             uint64_t size,
                             uint64_t slice_offset,
                             uint64_t slice_size) {
    if (!range_ok(slice_offset, size, sizeof(struct mach_header_64))) {
        out->status = 2;
        return 0;
    }
    if (!range_ok(slice_offset, size, slice_size)) {
        out->status = 3;
        return 0;
    }

    const struct mach_header_64 *header = (const struct mach_header_64 *)(image + slice_offset);
    if (header->magic != MH_MAGIC_64) {
        out->status = header->magic == MH_CIGAM_64 ? 4 : 5;
        return 0;
    }
    if (header->cputype != XNU_CPU_TYPE) {
        out->status = 6;
        return 0;
    }
    if (!range_ok(sizeof(*header), slice_size, header->sizeofcmds)) {
        out->status = 7;
        return 0;
    }

    out->slice_offset = slice_offset;
    out->slice_size = slice_size;
    out->cpu_type = header->cputype;
    out->ncmds = header->ncmds;
    out->vm_min = UINT64_MAX;
    out->vm_max = 0;
    out->file_highest = 0;
    out->entry = 0;

    uint64_t cursor = slice_offset + sizeof(*header);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (!range_ok(cursor, size, sizeof(struct load_command))) {
            out->status = 8;
            return 0;
        }
        const struct load_command *lc = (const struct load_command *)(image + cursor);
        if (lc->cmdsize < sizeof(*lc) || !range_ok(cursor - slice_offset, slice_size, lc->cmdsize)) {
            out->status = 9;
            return 0;
        }
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (seg->vmsize != 0) {
                if (seg->vmaddr < out->vm_min) {
                    out->vm_min = seg->vmaddr;
                }
                if (seg->vmaddr + seg->vmsize > out->vm_max) {
                    out->vm_max = seg->vmaddr + seg->vmsize;
                }
            }
            if (seg->filesize != 0) {
                uint64_t high = seg->fileoff + seg->filesize;
                if (high > out->file_highest) {
                    out->file_highest = high;
                }
            }
        } else if (lc->cmd == LC_MAIN && lc->cmdsize >= sizeof(struct entry_point_command)) {
            const struct entry_point_command *entry = (const struct entry_point_command *)lc;
            out->entry = entry->entryoff;
        } else if (lc->cmd == LC_UNIXTHREAD && lc->cmdsize >= sizeof(struct thread_command)) {
            const struct thread_command *thread = (const struct thread_command *)lc;
#if defined(__x86_64__)
            if (thread->flavor == X86_THREAD_STATE64 && thread->count >= 21) {
                const uint64_t *state = (const uint64_t *)(image + cursor + sizeof(*thread));
                out->entry = state[16];
            }
#elif defined(__aarch64__)
            if (thread->flavor == ARM_THREAD_STATE64 && thread->count >= 68) {
                const uint64_t *state = (const uint64_t *)(image + cursor + sizeof(*thread));
                out->entry = state[32];
            }
#endif
        }
        cursor += lc->cmdsize;
    }

    out->status = out->entry == 0 ? 10 : 0;
    return out->status == 0;
}

static int parse_macho(struct limine_file *file, struct macho_preflight *out) {
    debug_stage(10, 255, 255, 255);
    out->image = module_data(file);
    debug_stage(11, out->image != 0 ? 0 : 255, out->image != 0 ? 255 : 80, 255);
    out->size = file->size;
    out->slice_offset = 0;
    out->slice_size = file->size;
    out->status = 1;

    if (out->image == 0 || file->size < sizeof(uint32_t)) {
        return 0;
    }

    const uint8_t *image = out->image;
    uint32_t magic = *(const uint32_t *)image;
    debug_stage(12, 0, 255, 255);
    if (magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
        return parse_macho_slice(out, image, file->size, 0, file->size);
    }
    if (magic != FAT_MAGIC && magic != FAT_CIGAM && magic != FAT_MAGIC_64 && magic != FAT_CIGAM_64) {
        out->status = 11;
        return 0;
    }

    const struct fat_header *fat = (const struct fat_header *)image;
    int fat_big_endian = magic == FAT_CIGAM || magic == FAT_CIGAM_64;
    int fat64 = magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64;
    uint32_t nfat_arch = fat_big_endian ? bswap32(fat->nfat_arch) : fat->nfat_arch;
    uint64_t arch_entry_size = fat64 ? sizeof(struct fat_arch_64) : sizeof(struct fat_arch);
    uint64_t arch_table_size = sizeof(*fat) + (uint64_t)nfat_arch * arch_entry_size;
    if (!range_ok(0, file->size, arch_table_size)) {
        out->status = 12;
        return 0;
    }

    for (uint32_t i = 0; i < nfat_arch; i++) {
        uint64_t entry = sizeof(*fat) + (uint64_t)i * arch_entry_size;
        uint32_t cputype = 0;
        uint64_t offset = 0;
        uint64_t size = 0;
        if (fat64) {
            const struct fat_arch_64 *arch = (const struct fat_arch_64 *)(image + entry);
            cputype = fat_big_endian ? bswap32(arch->cputype) : arch->cputype;
            offset = fat_big_endian ? bswap64(arch->offset) : arch->offset;
            size = fat_big_endian ? bswap64(arch->size) : arch->size;
        } else {
            const struct fat_arch *arch = (const struct fat_arch *)(image + entry);
            cputype = fat_big_endian ? bswap32(arch->cputype) : arch->cputype;
            offset = fat_big_endian ? bswap32(arch->offset) : arch->offset;
            size = fat_big_endian ? bswap32(arch->size) : arch->size;
        }
        if (cputype == XNU_CPU_TYPE) {
            return parse_macho_slice(out, image, file->size, offset, size);
        }
    }

    out->status = 13;
    return 0;
}

static int load_macho_segments(struct boot_allocator *allocator,
                               const struct macho_preflight *macho,
                               uint64_t *kernel_phys,
                               uint64_t *kernel_size,
                               uint64_t *entry_phys) {
    if (macho->vm_min == UINT64_MAX || macho->vm_max <= macho->vm_min) {
        return 0;
    }

    uint64_t load_size = align_up(macho->vm_max - macho->vm_min, 0x1000);
    if (load_size == 0 || load_size > 512ULL * 1024ULL * 1024ULL) {
        return 0;
    }

    uint64_t load_phys = 0;
    uint8_t *load_base = (uint8_t *)boot_alloc(allocator, load_size, 0x1000, &load_phys);
    if (load_base == 0) {
        return 0;
    }

    memzero(load_base, load_size);

    const uint8_t *image = macho->image;
    const struct mach_header_64 *header =
        (const struct mach_header_64 *)(image + macho->slice_offset);
    uint64_t cursor = macho->slice_offset + sizeof(*header);
    uint64_t translated_entry = 0;

    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)(image + cursor);
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (seg->filesize != 0) {
                if (seg->vmaddr < macho->vm_min || seg->vmaddr + seg->filesize > macho->vm_max) {
                    return 0;
                }
                if (!range_ok(macho->slice_offset + seg->fileoff, macho->size, seg->filesize)) {
                    return 0;
                }
                uint64_t dest_off = seg->vmaddr - macho->vm_min;
                memcopy(load_base + dest_off, image + macho->slice_offset + seg->fileoff, seg->filesize);
            }

            if (macho->entry >= seg->vmaddr && macho->entry < seg->vmaddr + seg->vmsize) {
                translated_entry = load_phys + (macho->entry - macho->vm_min);
            } else if (macho->entry >= seg->fileoff && macho->entry < seg->fileoff + seg->filesize) {
                translated_entry = load_phys + (seg->vmaddr - macho->vm_min) + (macho->entry - seg->fileoff);
            }
        }
        cursor += lc->cmdsize;
    }

    if (translated_entry == 0) {
        return 0;
    }

    *kernel_phys = load_phys;
    *kernel_size = load_size;
    *entry_phys = translated_entry;
    return 1;
}

#if defined(__x86_64__)
static int load_macho_segments_x86_fixed(const struct macho_preflight *macho,
                                         uint64_t *kernel_phys,
                                         uint64_t *kernel_size,
                                         uint64_t *entry_phys) {
    if (macho->vm_min == UINT64_MAX || macho->vm_max <= macho->vm_min ||
        macho->vm_min < X86_XNU_STATIC_BASE) {
        return 0;
    }

    struct limine_hhdm_response *hhdm = hhdm_request.response;
    if (hhdm == 0) {
        return 0;
    }

    uint64_t load_phys = macho->vm_min - X86_XNU_STATIC_BASE;
    uint64_t load_size = align_up(macho->vm_max - macho->vm_min, 0x1000);
    if (load_size == 0 || load_size > 512ULL * 1024ULL * 1024ULL ||
        load_phys < 0x100000 || load_phys + load_size > 0xffffffffULL) {
        return 0;
    }

    uint8_t *load_base = (uint8_t *)(uintptr_t)(hhdm->offset + load_phys);
    memzero(load_base, load_size);

    const uint8_t *image = macho->image;
    const struct mach_header_64 *header =
        (const struct mach_header_64 *)(image + macho->slice_offset);
    uint64_t cursor = macho->slice_offset + sizeof(*header);
    uint64_t translated_entry = 0;

    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)(image + cursor);
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (seg->filesize != 0) {
                if (seg->vmaddr < macho->vm_min || seg->vmaddr + seg->filesize > macho->vm_max) {
                    return 0;
                }
                if (!range_ok(macho->slice_offset + seg->fileoff, macho->size, seg->filesize)) {
                    return 0;
                }
                uint64_t dest_off = seg->vmaddr - macho->vm_min;
                memcopy(load_base + dest_off, image + macho->slice_offset + seg->fileoff, seg->filesize);
            }

            if (macho->entry >= seg->vmaddr && macho->entry < seg->vmaddr + seg->vmsize) {
                translated_entry = load_phys + (macho->entry - macho->vm_min);
            }
        }
        cursor += lc->cmdsize;
    }

    if (translated_entry == 0) {
        return 0;
    }

    *kernel_phys = load_phys;
    *kernel_size = load_size;
    *entry_phys = translated_entry;
    return 1;
}
#endif

static uint32_t xnu_efi_type_from_limine(uint64_t type) {
    switch (type) {
        case LIMINE_MEMMAP_USABLE:
            return 7;
        case LIMINE_MEMMAP_ACPI_RECLAIMABLE:
            return 9;
        case LIMINE_MEMMAP_ACPI_NVS:
            return 10;
        case LIMINE_MEMMAP_BAD_MEMORY:
            return 8;
        case LIMINE_MEMMAP_BOOTLOADER_RECLAIMABLE:
            return 4;
        case LIMINE_MEMMAP_KERNEL_AND_MODULES:
            return 2;
        case LIMINE_MEMMAP_FRAMEBUFFER:
            return 11;
        case LIMINE_MEMMAP_RESERVED:
        default:
            return 0;
    }
}

#if defined(__x86_64__)
static void normalize_x86_runtime_descriptors(void *memory_map,
                                              uint64_t memory_map_size,
                                              uint64_t descriptor_size) {
    if (memory_map == 0 || descriptor_size < sizeof(struct xnu_efi_memory_range)) {
        return;
    }

    uint8_t *cursor = (uint8_t *)memory_map;
    uint64_t count = memory_map_size / descriptor_size;
    for (uint64_t i = 0; i < count; i++) {
        struct xnu_efi_memory_range *range =
            (struct xnu_efi_memory_range *)(cursor + i * descriptor_size);
        if ((range->attribute & X86_EFI_MEMORY_RUNTIME) != 0 &&
            range->virtual_start == 0) {
            range->virtual_start = X86_XNU_STATIC_BASE | range->physical_start;
        }
    }
}

static void compute_x86_runtime_range(const void *memory_map,
                                      uint64_t memory_map_size,
                                      uint64_t descriptor_size,
                                      uint32_t *page_start_out,
                                      uint32_t *page_count_out,
                                      uint64_t *virtual_start_out) {
    uint64_t first_page = UINT64_MAX;
    uint64_t end_page = 0;
    uint64_t first_virtual = 0;

    if (memory_map != 0 && descriptor_size >= sizeof(struct xnu_efi_memory_range)) {
        const uint8_t *cursor = (const uint8_t *)memory_map;
        uint64_t count = memory_map_size / descriptor_size;
        for (uint64_t i = 0; i < count; i++) {
            const struct xnu_efi_memory_range *range =
                (const struct xnu_efi_memory_range *)(cursor + i * descriptor_size);
            if ((range->attribute & X86_EFI_MEMORY_RUNTIME) == 0 ||
                range->number_of_pages == 0) {
                continue;
            }

            uint64_t page_start = range->physical_start >> 12;
            uint64_t page_end = page_start + range->number_of_pages;
            if (page_start < first_page) {
                first_page = page_start;
                first_virtual = range->virtual_start;
            }
            if (page_end > end_page) {
                end_page = page_end;
            }
        }
    }

    if (first_page == UINT64_MAX || end_page <= first_page ||
        first_page > UINT32_MAX || end_page - first_page > UINT32_MAX) {
        *page_start_out = 0;
        *page_count_out = 0;
        *virtual_start_out = 0;
        return;
    }

    *page_start_out = (uint32_t)first_page;
    *page_count_out = (uint32_t)(end_page - first_page);
    *virtual_start_out = first_virtual;
}
#endif

static uint64_t physical_memory_size_from_memmap(void) {
    struct limine_memmap_response *memmap = memmap_request.response;
    if (memmap == 0) {
        return 0;
    }

    uint64_t total = 0;
    uint64_t fallback_total = 0;
    for (uint64_t i = 0; i < memmap->entry_count; i++) {
        struct limine_memmap_entry *entry = memmap->entries[i];
        if (entry == 0) {
            continue;
        }
        if (entry->type == LIMINE_MEMMAP_USABLE ||
            entry->type == LIMINE_MEMMAP_BOOTLOADER_RECLAIMABLE ||
            entry->type == LIMINE_MEMMAP_KERNEL_AND_MODULES) {
            if (entry->base < 0x100000000ULL) {
                uint64_t length = entry->length;
                if (entry->base + length > 0x100000000ULL) {
                    length = 0x100000000ULL - entry->base;
                }
                total += length;
            }
        }
        if (entry->type != LIMINE_MEMMAP_BAD_MEMORY && entry->base < 0x100000000ULL) {
            uint64_t length = entry->length;
            if (entry->base + length > 0x100000000ULL) {
                length = 0x100000000ULL - entry->base;
            }
            fallback_total += length;
        }
    }
    return total != 0 ? total : fallback_total;
}

static void write_dt_prop_name(char dst[32], const char *name) {
    uint64_t i = 0;
    for (; i < 31 && name[i] != '\0'; i++) {
        dst[i] = name[i];
    }
    for (; i < 32; i++) {
        dst[i] = 0;
    }
}

static uint8_t *dt_write_prop(uint8_t *p, const char *name, const void *value, uint32_t length) {
    struct apple_dt_property *prop = (struct apple_dt_property *)p;
    write_dt_prop_name(prop->name, name);
    prop->length = length;
    p += sizeof(*prop);
    memcopy(p, value, length);
    p += align_up(length, 4);
    return p;
}

static uint8_t *dt_write_string_prop(uint8_t *p, const char *name, const char *value) {
    uint32_t length = 0;
    while (value[length] != '\0') {
        length++;
    }
    length++;
    return dt_write_prop(p, name, value, length);
}

static int build_minimal_device_tree(struct boot_allocator *allocator,
                                     void **dt_virt,
                                     uint64_t *dt_phys,
                                     uint32_t *dt_size,
                                     uint64_t physical_memory_size) {
    uint64_t phys = 0;
    uint8_t *dt = (uint8_t *)boot_alloc(allocator, 4096, 16, &phys);
    if (dt == 0) {
        return 0;
    }
    memzero(dt, 4096);

    uint8_t *p = dt;
    struct apple_dt_node *root = (struct apple_dt_node *)p;
    root->n_properties = 4;
    root->n_children = 3;
    p += sizeof(*root);
    p = dt_write_string_prop(p, "name", "device-tree");
    p = dt_write_string_prop(p, "compatible", "openai,os8-limine");
    p = dt_write_string_prop(p, "model", "OS8 Limine Virtual Machine");
    p = dt_write_string_prop(p, "target-type", "OS8-Limine");

    struct apple_dt_node *cpus = (struct apple_dt_node *)p;
    cpus->n_properties = 2;
    cpus->n_children = 1;
    p += sizeof(*cpus);
    p = dt_write_string_prop(p, "name", "cpus");
    uint32_t address_cells = 1;
    p = dt_write_prop(p, "#address-cells", &address_cells, sizeof(address_cells));

    struct apple_dt_node *cpu0 = (struct apple_dt_node *)p;
    cpu0->n_properties = 6;
    cpu0->n_children = 0;
    p += sizeof(*cpu0);
    p = dt_write_string_prop(p, "name", "cpu0");
    p = dt_write_string_prop(p, "device_type", "cpu");
    p = dt_write_string_prop(p, "state", "running");
    uint32_t cpu_reg = 0;
    uint32_t timebase = 24000000;
    uint32_t bus_frequency = 100000000;
    p = dt_write_prop(p, "reg", &cpu_reg, sizeof(cpu_reg));
    p = dt_write_prop(p, "timebase-frequency", &timebase, sizeof(timebase));
    p = dt_write_prop(p, "bus-frequency", &bus_frequency, sizeof(bus_frequency));

    struct apple_dt_node *chosen = (struct apple_dt_node *)p;
    chosen->n_properties = 8;
    chosen->n_children = 1;
    p += sizeof(*chosen);
    p = dt_write_string_prop(p, "name", "chosen");
    uint32_t debug_enabled = 1;
    uint32_t dram_vendor_id = 0;
    uint64_t dram_base = 0;
    uint64_t unique_chip_id = 0;
    p = dt_write_prop(p, "debug-enabled", &debug_enabled, sizeof(debug_enabled));
    p = dt_write_string_prop(p, "firmware-version", "limine-os8");
    p = dt_write_string_prop(p, "system-firmware-version", "limine-os8");
    p = dt_write_prop(p, "unique-chip-id", &unique_chip_id, sizeof(unique_chip_id));
    p = dt_write_prop(p, "dram-vendor-id", &dram_vendor_id, sizeof(dram_vendor_id));
    p = dt_write_prop(p, "dram-base", &dram_base, sizeof(dram_base));
    p = dt_write_prop(p, "dram-size", &physical_memory_size, sizeof(physical_memory_size));

    struct apple_dt_node *chosen_memory_map = (struct apple_dt_node *)p;
    chosen_memory_map->n_properties = 1;
    chosen_memory_map->n_children = 0;
    p += sizeof(*chosen_memory_map);
    p = dt_write_string_prop(p, "name", "memory-map");

    struct apple_dt_node *product = (struct apple_dt_node *)p;
    product->n_properties = 2;
    product->n_children = 0;
    p += sizeof(*product);
    p = dt_write_string_prop(p, "name", "product");
    uint32_t chip_role = 0;
    p = dt_write_prop(p, "chip-role", &chip_role, sizeof(chip_role));

    *dt_virt = dt;
    *dt_phys = phys;
    *dt_size = (uint32_t)(p - dt);
    return 1;
}

static int build_xnu_handoff(struct xnu_handoff *handoff,
                             struct limine_file *xnu,
                             const struct macho_preflight *macho,
                             struct limine_framebuffer *fb) {
    struct limine_memmap_response *memmap = memmap_request.response;
    debug_stage(0, 255, 255, 255);
    if (xnu == 0 || macho->status != 0) {
        handoff->status = 1;
        return 0;
    }
    if (memmap == 0 || hhdm_request.response == 0) {
        handoff->status = 2;
        return 0;
    }

    struct limine_efi_memmap_response *efi_memmap = efi_memmap_request.response;
    uint64_t memory_map_size = memmap->entry_count * sizeof(struct xnu_efi_memory_range);
    uint64_t memory_map_descriptor_size = sizeof(struct xnu_efi_memory_range);
    int use_efi_memory_map = 0;
#if defined(__x86_64__)
    if (efi_memmap != 0 &&
        efi_memmap->memmap != 0 &&
        efi_memmap->memmap_size != 0 &&
        efi_memmap->desc_size >= sizeof(struct xnu_efi_memory_range)) {
        memory_map_size = efi_memmap->memmap_size;
        memory_map_descriptor_size = efi_memmap->desc_size;
        use_efi_memory_map = 1;
    }
#endif
    uint64_t kernel_load_size = 0;
    if (macho->vm_min != UINT64_MAX && macho->vm_max > macho->vm_min) {
        kernel_load_size = align_up(macho->vm_max - macho->vm_min, 0x1000);
    }
    if (kernel_load_size == 0 || kernel_load_size > 512ULL * 1024ULL * 1024ULL) {
        handoff->status = 3;
        return 0;
    }
    debug_stage(1, 255, 255, 255);

    uint64_t reserve_size = align_up(kernel_load_size + memory_map_size + XNU_BOOT_ARG_RESERVE, 0x1000);
    struct boot_allocator allocator = {0};
    if (!init_boot_allocator(&allocator, reserve_size)) {
        handoff->status = 4;
        return 0;
    }
    handoff->allocator_base = allocator.base;
    debug_stage(2, 255, 255, 255);

    int load_ok = 0;
#if defined(__x86_64__)
    load_ok = load_macho_segments_x86_fixed(macho,
                                            &handoff->kernel_phys,
                                            &handoff->kernel_size,
                                            &handoff->kernel_entry_phys);
#else
    load_ok = load_macho_segments(&allocator, macho,
                                  &handoff->kernel_phys,
                                  &handoff->kernel_size,
                                  &handoff->kernel_entry_phys);
#endif
    if (!load_ok) {
        handoff->status = 5;
        return 0;
    }
#if defined(__x86_64__)
    if (allocator.cursor < handoff->kernel_phys + handoff->kernel_size &&
        allocator.base + allocator.size > handoff->kernel_phys) {
        allocator.cursor = align_up(handoff->kernel_phys + handoff->kernel_size, 0x1000);
        if (allocator.cursor > allocator.base + allocator.size) {
            handoff->status = 5;
            return 0;
        }
    }
#endif
    debug_stage(3, 255, 255, 255);

    uint64_t memory_map_phys = 0;
    struct xnu_efi_memory_range *memory_map = (struct xnu_efi_memory_range *)
        boot_alloc(&allocator, memory_map_size, 16, &memory_map_phys);
    if (memory_map == 0) {
        handoff->status = 6;
        return 0;
    }

    handoff->kernel_entry_virt = macho->entry;
    debug_stage(4, 255, 255, 255);

    if (use_efi_memory_map) {
        memcopy(memory_map, efi_memmap->memmap, memory_map_size);
#if defined(__x86_64__)
        normalize_x86_runtime_descriptors(memory_map, memory_map_size, memory_map_descriptor_size);
#endif
    } else {
        for (uint64_t i = 0; i < memmap->entry_count; i++) {
            struct limine_memmap_entry *entry = memmap->entries[i];
            memory_map[i].type = entry != 0 ? xnu_efi_type_from_limine(entry->type) : 0;
            memory_map[i].physical_start = entry != 0 ? entry->base : 0;
            memory_map[i].virtual_start = 0;
            memory_map[i].number_of_pages = entry != 0 ? entry->length / 0x1000 : 0;
            memory_map[i].attribute = 0;
        }
    }
#if !defined(__x86_64__)
    (void)memory_map_descriptor_size;
#endif
    debug_stage(5, 255, 255, 255);

    uint64_t boot_args_phys = 0;
    handoff->physical_memory_size = physical_memory_size_from_memmap();
    handoff->memory_map_phys = memory_map_phys;
    handoff->memory_map_size = memory_map_size;
    void *device_tree = 0;
    uint64_t device_tree_phys = 0;
    uint32_t device_tree_size = 0;
    if (!build_minimal_device_tree(&allocator, &device_tree, &device_tree_phys, &device_tree_size,
                                   handoff->physical_memory_size)) {
        handoff->status = 7;
        return 0;
    }
    debug_stage(6, 255, 255, 255);

#if defined(__x86_64__)
    struct limine_hhdm_response *hhdm = hhdm_request.response;
    if (hhdm == 0) {
        handoff->status = 10;
        return 0;
    }

    uint64_t executable_virtual_base = 0;
    uint64_t executable_physical_base = 0;
    if (executable_address_request.response != 0) {
        executable_virtual_base =
            executable_address_request.response->virtual_base;
        executable_physical_base =
            executable_address_request.response->physical_base;
    }
    uint64_t transition_virtual_address = (uint64_t)(uintptr_t)&try_jump_xnu;
    uint64_t transition_physical_address = 0;
    if (executable_virtual_base != 0 &&
        executable_physical_base != 0 &&
        transition_virtual_address >= executable_virtual_base) {
        transition_physical_address =
            executable_physical_base +
            (transition_virtual_address - executable_virtual_base);
    }

    uint64_t x86_map_end = handoff->physical_memory_size;

    uint64_t kernel_end =
        handoff->kernel_phys + handoff->kernel_size;
    if (kernel_end > x86_map_end) {
        x86_map_end = kernel_end;
    }

    uint64_t allocator_end =
        allocator.base + allocator.size;
    if (allocator_end > x86_map_end) {
        x86_map_end = allocator_end;
    }

    if (fb != 0) {
        uint64_t fb_phys = virt_to_phys(fb->address);
        uint64_t fb_end =
            fb_phys + fb->pitch * fb->height;
        if (fb_end > x86_map_end) {
            x86_map_end = fb_end;
        }
    }

    if (!build_x86_bootstrap_map(
            &allocator,
            hhdm->offset,
            executable_virtual_base,
            executable_physical_base,
            transition_virtual_address,
            transition_physical_address,
            macho->vm_min,
            handoff->kernel_phys,
            handoff->kernel_size,
            x86_map_end,
            x86_map_end,
            &handoff->identity_pagetable_phys)) {
        handoff->status = 11;
        return 0;
    }

    handoff->jump_stack_size = 0x10000;
    void *jump_stack = boot_alloc(
        &allocator,
        handoff->jump_stack_size,
        0x1000,
        &handoff->jump_stack_phys);
    if (jump_stack == 0) {
        handoff->status = 12;
        return 0;
    }
    memzero(jump_stack, handoff->jump_stack_size);

    struct xnu_boot_args_x86 *args = (struct xnu_boot_args_x86 *)
        boot_alloc(&allocator, sizeof(*args), 0x1000, &boot_args_phys);
    if (args == 0) {
        handoff->status = 8;
        return 0;
    }
    debug_stage(7, 255, 255, 255);
    args->revision = XNU_BOOT_ARGS_REVISION_X86;
    args->version = XNU_BOOT_ARGS_VERSION;
    args->efi_mode = XNU_EFI_MODE_64;
    strcopy_bounded(args->command_line, sizeof(args->command_line), "-v keepsyms=1");
    args->memory_map = (uint32_t)memory_map_phys;
    args->memory_map_size = (uint32_t)memory_map_size;
    args->memory_map_descriptor_size = (uint32_t)memory_map_descriptor_size;
    if (efi_memmap != 0) {
        args->memory_map_descriptor_version = (uint32_t)efi_memmap->desc_version;
    }
    compute_x86_runtime_range(memory_map,
                              memory_map_size,
                              memory_map_descriptor_size,
                              &args->efi_runtime_services_page_start,
                              &args->efi_runtime_services_page_count,
                              &args->efi_runtime_services_virtual_page_start);
    handoff->memory_map_descriptor_size = args->memory_map_descriptor_size;
    handoff->efi_runtime_services_page_start = args->efi_runtime_services_page_start;
    handoff->efi_runtime_services_page_count = args->efi_runtime_services_page_count;
    handoff->efi_runtime_services_virtual_page_start = args->efi_runtime_services_virtual_page_start;
    args->device_tree_p = (uint32_t)device_tree_phys;
    args->device_tree_length = device_tree_size;
    args->kaddr = (uint32_t)handoff->kernel_phys;
    args->ksize = (uint32_t)handoff->kernel_size;
    args->boot_mem_start = allocator.base;
    args->boot_mem_size = allocator.size;
    args->physical_memory_size = handoff->physical_memory_size;
    if (efi_system_table_request.response != 0) {
        args->efi_system_table = (uint32_t)virt_to_phys(efi_system_table_request.response->address);
        handoff->efi_system_table_phys = args->efi_system_table;
    }
    if (fb != 0) {
        uint64_t fb_phys = 0;
        uint64_t fb_pitch = 0;
        uint64_t fb_width = 0;
        uint64_t fb_height = 0;
        uint32_t fb_bpp = 0;
        configure_framebuffer_handoff(fb, &fb_phys, &fb_pitch, &fb_width, &fb_height, &fb_bpp);
        args->video_v1.base_addr = (uint32_t)fb_phys;
        args->video_v1.display = XNU_GRAPHICS_MODE;
        args->video_v1.row_bytes = (uint32_t)fb_pitch;
        args->video_v1.width = (uint32_t)fb_width;
        args->video_v1.height = (uint32_t)fb_height;
        args->video_v1.depth = fb_bpp;
        args->video.display = XNU_GRAPHICS_MODE;
        args->video.row_bytes = (uint32_t)fb_pitch;
        args->video.width = (uint32_t)fb_width;
        args->video.height = (uint32_t)fb_height;
        args->video.depth = fb_bpp;
        args->video.base_addr = fb_phys;
    }
    handoff->boot_args = args;
#elif defined(__aarch64__)
    if (!build_arm64_identity_map(&allocator, &handoff->identity_pagetable_phys)) {
        handoff->status = 10;
        return 0;
    }

    struct xnu_boot_args_arm64 *args = (struct xnu_boot_args_arm64 *)
        boot_alloc(&allocator, sizeof(*args), 0x1000, &boot_args_phys);
    if (args == 0) {
        handoff->status = 8;
        return 0;
    }
    debug_stage(7, 255, 255, 255);
    args->revision = XNU_BOOT_ARGS_REVISION_ARM64;
    args->version = XNU_BOOT_ARGS_VERSION;
    args->virt_base = macho->vm_min == UINT64_MAX ? 0 : macho->vm_min;
    args->phys_base = handoff->kernel_phys;
    args->mem_size = handoff->physical_memory_size;
    args->mem_size_actual = handoff->physical_memory_size;
    args->top_of_kernel_data = align_up(allocator.cursor, 0x4000);
    args->device_tree_p = (void *)(uintptr_t)device_tree_phys;
    args->device_tree_length = device_tree_size;
    strcopy_bounded(args->command_line, sizeof(args->command_line), "-v keepsyms=1");
    if (fb != 0) {
        uint64_t fb_phys = 0;
        uint64_t fb_pitch = 0;
        uint64_t fb_width = 0;
        uint64_t fb_height = 0;
        uint32_t fb_bpp = 0;
        configure_framebuffer_handoff(fb, &fb_phys, &fb_pitch, &fb_width, &fb_height, &fb_bpp);
        args->video.base_addr = fb_phys;
        args->video.display = XNU_GRAPHICS_MODE;
        args->video.row_bytes = fb_pitch;
        args->video.width = fb_width;
        args->video.height = fb_height;
        args->video.depth = fb_bpp;
    }
    handoff->boot_args = args;
#else
    handoff->status = 9;
    return 0;
#endif

    handoff->boot_args_phys = boot_args_phys;
    handoff->allocator_used = allocator.cursor - allocator.base;
#if defined(__aarch64__)
    handoff->top_of_kernel_data = ((struct xnu_boot_args_arm64 *)args)->top_of_kernel_data;
#endif
    handoff->status = 0;
    debug_stage(8, 0, 210, 255);
    return 1;
}

static void hex64(char *buf, uint64_t value) {
    static const char hexdigits[] = "0123456789abcdef";
    buf[0] = '0';
    buf[1] = 'x';
    for (int i = 0; i < 16; i++) {
        buf[2 + i] = hexdigits[(value >> ((15 - i) * 4)) & 0xf];
    }
    buf[18] = '\0';
}

static void draw_key_hex(struct limine_framebuffer *fb,
                         uint64_t x, uint64_t y,
                         const char *key, uint64_t value,
                         uint32_t key_colour, uint32_t value_colour) {
    char buf[19];
    hex64(buf, value);
    draw_text(fb, x, y, key, 2, key_colour);
    draw_text(fb, x + 210, y, buf, 2, value_colour);
}

static void configure_framebuffer_handoff(struct limine_framebuffer *fb,
                                         uint64_t *fb_phys_out,
                                         uint64_t *fb_pitch_out,
                                         uint64_t *fb_width_out,
                                         uint64_t *fb_height_out,
                                         uint32_t *fb_bpp_out) {
    if (fb == 0) {
        if (fb_phys_out != 0) {
            *fb_phys_out = 0;
        }
        if (fb_pitch_out != 0) {
            *fb_pitch_out = 0;
        }
        if (fb_width_out != 0) {
            *fb_width_out = 0;
        }
        if (fb_height_out != 0) {
            *fb_height_out = 0;
        }
        if (fb_bpp_out != 0) {
            *fb_bpp_out = 0;
        }
        return;
    }

    uint64_t fb_phys = virt_to_phys(fb->address);
    if (fb_phys_out != 0) {
        *fb_phys_out = fb_phys;
    }
    if (fb_pitch_out != 0) {
        *fb_pitch_out = fb->pitch;
    }
    if (fb_width_out != 0) {
        *fb_width_out = fb->width;
    }
    if (fb_height_out != 0) {
        *fb_height_out = fb->height;
    }
    if (fb_bpp_out != 0) {
        *fb_bpp_out = fb->bpp;
    }

    serial_key_hex("fb-phys", fb_phys);
    serial_key_hex("fb-pitch", fb->pitch);
    serial_key_hex("fb-width", fb->width);
    serial_key_hex("fb-height", fb->height);
    serial_key_hex("fb-bpp", fb->bpp);
}

#if defined(__x86_64__)
struct x86_gdtr {
    uint16_t limit;
    uint64_t base;
} __attribute__((packed));

static uint64_t x86_transition_gdt[] __attribute__((aligned(16))) = {
    0x0000000000000000ULL,
    0x00cf9a000000ffffULL,
    0x00cf92000000ffffULL,
    0x00af9a000000ffffULL,
};
#endif

static int try_jump_xnu(const struct xnu_handoff *handoff) {
#if defined(__x86_64__)
    if (handoff->status != 0) {
        serial_write("os8-handoff: x86 jump skipped bad handoff\n");
        return 0;
    }
    if (handoff->kernel_entry_virt == 0 ||
        handoff->kernel_entry_phys == 0) {
        serial_write("os8-handoff: x86 jump skipped no entry\n");
        return 0;
    }
    if (handoff->boot_args_phys == 0) {
        serial_write("os8-handoff: x86 jump skipped no boot args\n");
        return 0;
    }
    if (handoff->identity_pagetable_phys == 0) {
        serial_write("os8-handoff: x86 jump skipped no pml4\n");
        return 0;
    }
    if (handoff->jump_stack_phys == 0 ||
        handoff->jump_stack_size == 0) {
        serial_write("os8-handoff: x86 jump skipped no stack\n");
        return 0;
    }

    struct limine_hhdm_response *hhdm = hhdm_request.response;
    if (hhdm == 0) {
        serial_write("os8-handoff: x86 jump skipped no hhdm\n");
        return 0;
    }

    uint64_t new_cr3 = handoff->identity_pagetable_phys;
    uint64_t entry = handoff->kernel_entry_virt;
    uint64_t boot_args = handoff->boot_args_phys;
    uint32_t boot_args32 = (uint32_t)boot_args;
    uint64_t stack_top =
        hhdm->offset + handoff->jump_stack_phys +
        handoff->jump_stack_size - 16;
    uint32_t entry32 = (uint32_t)handoff->kernel_entry_phys;
    uint32_t stack_top32 =
        (uint32_t)(handoff->jump_stack_phys + handoff->jump_stack_size - 16);
    uint32_t compat_trampoline32 = (uint32_t)handoff->jump_stack_phys;
    struct x86_gdtr transition_gdtr = {
        (uint16_t)(sizeof(x86_transition_gdt) - 1),
        (uint64_t)(uintptr_t)x86_transition_gdt
    };
    static const uint8_t compat_trampoline[] = {
        0x66, 0xba, 0x10, 0x00,
        0x8e, 0xda,
        0x8e, 0xc2,
        0x8e, 0xd2,
        0x89, 0xcc,
        0x31, 0xed,
        0x31, 0xc9,
        0x31, 0xd2,
        0xff, 0xe3
    };
    memcopy((void *)(uintptr_t)(hhdm->offset + handoff->jump_stack_phys),
            compat_trampoline,
            sizeof(compat_trampoline));

    serial_key_hex("jump-entry-phys", handoff->kernel_entry_phys);
    serial_key_hex("jump-entry-virt", entry);
    serial_key_hex("jump-boot-args", boot_args);
    serial_key_hex("jump-cr3", new_cr3);
    serial_key_hex("jump-stack", stack_top);

    uint64_t old_cr3;
    __asm__ volatile ("mov %%cr3, %0" : "=r"(old_cr3));
    serial_key_hex("old-cr3", old_cr3);
    serial_write("os8-handoff: x86 jumping\n");

    /*
     * Diagnostic transition:
     * X = survived CR3 switch
     * Z = new stack installed
     */
    __asm__ volatile (
    "cli\n"
    "cld\n"

    /*
     * COM1 serial port.
     */
    "mov $0x3f8, %%dx\n"

    /*
     * Switch to our XNU bootstrap page tables.
     */
    "mov %0, %%cr3\n"

    /*
     * X = survived CR3 switch.
     */
    "mov $0x58, %%al\n"
    "outb %%al, %%dx\n"

    /*
     * Install a known GDT before changing the C stack/base pointer.
     */
    "lgdt %5\n"

    /*
     * Switch to our transition stack.
     */
    "mov %1, %%rsp\n"
    "xor %%rbp, %%rbp\n"

    /*
     * Z = stack transition worked.
     */
    "mov $0x5a, %%al\n"
    "outb %%al, %%dx\n"

    /*
     * Enter XNU through the 32-bit protected-mode trampoline it expects.
     */
    "pushq $0x18\n"
    "leaq 1f(%%rip), %%rax\n"
    "pushq %%rax\n"
    "lretq\n"
    "1:\n"
    "mov $0x10, %%ax\n"
    "mov %%ax, %%ds\n"
    "mov %%ax, %%es\n"
    "mov %%ax, %%ss\n"
    "mov %2, %%eax\n"
    "mov %3, %%ebx\n"
    "mov %4, %%ecx\n"
    "mov %6, %%esi\n"
    "pushq $0x08\n"
    "pushq %%rsi\n"
    "lretq\n"
    :
    : "r"(new_cr3),
      "r"(stack_top),
      "r"(boot_args32),
      "r"(entry32),
      "r"(stack_top32),
      "m"(transition_gdtr),
      "r"(compat_trampoline32)
    : "rax",
      "rbx",
      "rdx",
      "rsi",
      "rcx",
      "memory"
    );

    __builtin_unreachable();

#elif defined(__aarch64__)
    if (handoff->status != 0 || handoff->kernel_entry_phys == 0 ||
        handoff->boot_args == 0 || handoff->identity_pagetable_phys == 0) {
        serial_write("os8-handoff: jump skipped\n");
        return 0;
    }

    struct limine_hhdm_response *hhdm = hhdm_request.response;
    if (hhdm == 0) {
        serial_write("os8-handoff: jump skipped no-hhdm\n");
        return 0;
    }

    uint64_t entry_phys = handoff->kernel_entry_phys;
    uint64_t boot_args_phys = handoff->boot_args_phys;
    uint64_t identity_ttbr0 = handoff->identity_pagetable_phys;
    serial_key_hex("jump-entry-phys", handoff->kernel_entry_phys);
    serial_key_hex("jump-boot-args", boot_args_phys);
    serial_key_hex("jump-ttbr0", identity_ttbr0);
    serial_write("os8-handoff: jumping\n");
    flush_range_to_poc((void *)(uintptr_t)(hhdm->offset + handoff->kernel_phys), handoff->kernel_size);
    flush_range_to_poc((void *)(uintptr_t)(hhdm->offset + handoff->allocator_base),
                       handoff->allocator_used);

    __asm__ volatile (
        "dsb ish\n"
        "msr ttbr0_el1, %2\n"
        "isb\n"
        "tlbi vmalle1\n"
        "dsb ish\n"
        "isb\n"
        "mov x0, %0\n"
        "mov x20, %0\n"
        "mov x21, xzr\n"
        "mov x1, xzr\n"
        "mov x2, xzr\n"
        "mov x3, xzr\n"
        "br %1\n"
        :
        : "r"(boot_args_phys), "r"(entry_phys), "r"(identity_ttbr0)
        : "x0", "x1", "x2", "x3", "x20", "x21", "memory");
    __builtin_unreachable();
#else
    (void)handoff;
    return 0;
#endif
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
    serial_write("os8-handoff: start\n");
    struct limine_framebuffer_response *response = framebuffer_request.response;
    if (response != 0 && response->framebuffer_count > 0) {
        struct limine_framebuffer *fb = response->framebuffers[0];
        debug_fb = fb;
        serial_key_hex("framebuffer-width", fb->width);
        serial_key_hex("framebuffer-height", fb->height);
        uint32_t early_background = make_pixel(fb, 4, 16, 28);
        uint32_t early_marker = make_pixel(fb, 0, 210, 255);
        fill_rect(fb, 0, 0, fb->width, fb->height, early_background);
        fill_rect(fb, 24, 24, 96, 96, early_marker);
        flush_framebuffer(fb);

        debug_stage(0, 255, 0, 255);
        struct limine_file *xnu = find_xnu_module();
        serial_write(xnu != 0 ? "os8-handoff: module found\n" : "os8-handoff: module missing\n");
        if (xnu != 0) {
            serial_key_hex("module-size", xnu->size);
        }
        debug_stage(1, xnu != 0 ? 0 : 255, xnu != 0 ? 255 : 80, 255);
        debug_stage(2, 255, 0, 255);
        struct macho_preflight macho;
        memzero(&macho, sizeof(macho));
        debug_stage(3, 255, 0, 255);
        int macho_ok = xnu != 0 && parse_macho(xnu, &macho);
        serial_key_hex("macho-status", macho.status);
        serial_key_hex("macho-slice-offset", macho.slice_offset);
        serial_key_hex("macho-slice-size", macho.slice_size);
        serial_key_hex("macho-entry", macho.entry);
        serial_key_hex("macho-vm-min", macho.vm_min == UINT64_MAX ? 0 : macho.vm_min);
        serial_key_hex("macho-vm-max", macho.vm_max);
        debug_stage(4, macho_ok ? 0 : 255, macho_ok ? 255 : 80, 255);
        struct xnu_handoff handoff;
        memzero(&handoff, sizeof(handoff));
        int handoff_ok = build_xnu_handoff(&handoff, xnu, &macho, fb);
        serial_key_hex("handoff-status", handoff.status);
        serial_key_hex("kernel-load", handoff.kernel_phys);
        serial_key_hex("kernel-size", handoff.kernel_size);
        serial_key_hex("kernel-entry-phys", handoff.kernel_entry_phys);
        serial_key_hex("kernel-entry-virt", handoff.kernel_entry_virt);
        serial_key_hex("boot-args", handoff.boot_args_phys);
        serial_key_hex("memory-map", handoff.memory_map_phys);
        serial_key_hex("physical-memory-size", handoff.physical_memory_size);
#if defined(__x86_64__)
        serial_key_hex("memory-map-desc-size", handoff.memory_map_descriptor_size);
        serial_key_hex("efi-runtime-page-start", handoff.efi_runtime_services_page_start);
        serial_key_hex("efi-runtime-page-count", handoff.efi_runtime_services_page_count);
        serial_key_hex("efi-runtime-virt-start", handoff.efi_runtime_services_virtual_page_start);
        serial_key_hex("efi-system-table", handoff.efi_system_table_phys);
        serial_key_hex("bootstrap-pml4", handoff.identity_pagetable_phys);
        serial_key_hex("jump-stack-phys", handoff.jump_stack_phys);
#elif defined(__aarch64__)
        serial_key_hex("top-kernel-data", handoff.top_of_kernel_data);
        serial_key_hex("identity-pagetable", handoff.identity_pagetable_phys);
#endif
        if (handoff_ok) {
            int jumped = try_jump_xnu(&handoff);
            int retry = 0;
            while (!jumped && retry < 5) {
                serial_write("os8-handoff: retrying jump\n");
                for (volatile uint64_t d = 0; d < 2000000; d++) {
                    __asm__ volatile ("nop");
                }
                jumped = try_jump_xnu(&handoff);
                retry++;
            }
            if (!jumped) {
                serial_write("os8-handoff: jump failed, falling back to on-screen state\n");
            }
        }

        uint32_t background = make_pixel(fb, 8, 18, 28);
        uint32_t panel = make_pixel(fb, 14, 38, 48);
        uint32_t marker = make_pixel(fb, 0, 255, 96);
        uint32_t stripe = make_pixel(fb, 255, 0, 255);
        uint32_t text = make_pixel(fb, 230, 246, 238);
        uint32_t muted = make_pixel(fb, 156, 184, 176);
        uint32_t warn = make_pixel(fb, 255, 190, 80);
        uint32_t success = make_pixel(fb, 0, 210, 255);

        fill_rect(fb, 0, 0, fb->width, fb->height, background);
        fill_rect(fb, fb->width / 10, fb->height / 5, fb->width * 4 / 5, fb->height * 3 / 5, panel);
        fill_rect(fb, fb->width / 10, fb->height / 5, fb->width * 4 / 5, 14, marker);
        fill_rect(fb, fb->width / 10, fb->height / 5 + 22, fb->width * 4 / 5, 6, stripe);
        fill_rect(fb, fb->width / 10 + fb->width * 4 / 5 - 96, fb->height / 5 + 42, 64, 64,
                  handoff_ok ? success : warn);

        uint64_t x = fb->width / 10 + 32;
        uint64_t y = fb->height / 5 + 48;

        draw_text(fb, x, y, "OS8 XNU HANDOFF", 4, text);
        y += 60;
        draw_text(fb, x, y, xnu != 0 ? "XNU MODULE LOADED" : "XNU MODULE MISSING", 3, xnu != 0 ? marker : warn);
        y += 44;
        draw_text(fb, x, y, macho_ok ? "MACH-O PREFLIGHT OK" : "MACH-O PREFLIGHT FAILED", 2, macho_ok ? marker : warn);
        y += 34;
        draw_text(fb, x, y, handoff_ok ? "XNU BOOT-ARGS BUILT" : "XNU BOOT-ARGS FAILED", 2, handoff_ok ? marker : warn);
        y += 34;

        if (xnu != 0) {
            draw_key_hex(fb, x, y, "MODULE SIZE", xnu->size, muted, text);
            y += 28;
        }
        draw_key_hex(fb, x, y, "STATUS", macho.status, muted, macho_ok ? marker : warn);
        y += 28;
        draw_key_hex(fb, x, y, "SLICE OFFSET", macho.slice_offset, muted, text);
        y += 28;
        draw_key_hex(fb, x, y, "ENTRY", macho.entry, muted, text);
        y += 28;
        draw_key_hex(fb, x, y, "VM MIN", macho.vm_min == UINT64_MAX ? 0 : macho.vm_min, muted, text);
        y += 28;
        draw_key_hex(fb, x, y, "VM MAX", macho.vm_max, muted, text);
        y += 38;
        draw_key_hex(fb, x, y, "BOOT ARGS", handoff.boot_args_phys, muted, handoff_ok ? marker : warn);
        y += 28;
        draw_key_hex(fb, x, y, "MEM MAP", handoff.memory_map_phys, muted, handoff_ok ? marker : warn);
        y += 28;
        draw_key_hex(fb, x, y, "KERNEL LOAD", handoff.kernel_phys, muted, handoff_ok ? marker : warn);
        y += 28;
        draw_key_hex(fb, x, y, "ENTRY PHYS", handoff.kernel_entry_phys, muted, handoff_ok ? marker : warn);
        y += 28;
#if defined(__aarch64__)
        draw_key_hex(fb, x, y, "TOP KDATA", handoff.top_of_kernel_data, muted, handoff_ok ? marker : warn);
        y += 28;
        draw_key_hex(fb, x, y, "TTBR0 IDMAP", handoff.identity_pagetable_phys, muted, handoff_ok ? marker : warn);
        y += 28;
#endif
        draw_key_hex(fb, x, y, "HANDOFF STAT", handoff.status, muted, handoff_ok ? marker : warn);
        y += 38;

#if defined(__x86_64__)
        draw_text(fb, x, y, "X86-64 XNU JUMP ENABLED: CHECK SERIAL X/Y/Z", 2, warn);
#elif defined(__aarch64__)
        draw_text(fb, x, y, "ARM64 JUMP READY: PHYS BOOTARGS + TTBR0 IDMAP", 2, marker);
#else
        draw_text(fb, x, y, "UNSUPPORTED ARCH BRIDGE", 2, warn);
#endif
        y += 28;
        draw_text(fb, x, y, "LOG", 2, text);
        y += 24;
        draw_boot_log(fb, x, y, muted);
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
        cflags="-mno-red-zone -mcmodel=kernel -mno-sse -mno-sse2 -mno-mmx -msoft-float"
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
    "-DXNU_HANDOFF_DEBUG=$handoff_debug" \
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
