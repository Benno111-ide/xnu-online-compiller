#!/usr/bin/env sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <amd64|arm64> <work-dir> <output-efi>" >&2
    exit 2
fi

arch=$1
work=$2
output=$3
boot_args=${XNU_BOOT_ARGS:-"-v keepsyms=1 debug=0x144 serial=3"}

llvm_prefix=$(brew --prefix llvm 2>/dev/null || true)
clang="${CLANG:-${llvm_prefix:+$llvm_prefix/bin/clang}}"

if [ -z "$clang" ] || [ ! -x "$clang" ]; then
    clang="${CLANG:-clang}"
fi

command -v "$clang" >/dev/null 2>&1

mkdir -p "$work" "$(dirname "$output")"

loader_c="$work/xnu-efi-loader.c"
boot_args_header="$work/xnu-efi-loader-boot-args.h"

python3 - "$boot_args" "$boot_args_header" <<'PY'
import sys

boot_args, output = sys.argv[1], sys.argv[2]
escaped = (
    boot_args
    .replace("\\", "\\\\")
    .replace('"', '\\"')
    .replace("\r", "\\r")
    .replace("\n", "\\n")
)
with open(output, "w", encoding="ascii") as f:
    f.write(f'#define XNU_BOOT_ARGS_TEXT u"  {escaped}\\r\\n"\n')
PY

cat > "$loader_c" <<'SOURCE'
#include <stdint.h>
#include <stddef.h>
#include "xnu-efi-loader-boot-args.h"

typedef uint64_t UINT64;
typedef int64_t INT64;
typedef uint32_t UINT32;
typedef uint16_t CHAR16;
typedef uint16_t UINT16;
typedef uint8_t UINT8;
typedef uintptr_t UINTN;
typedef void VOID;
typedef UINTN EFI_STATUS;
typedef VOID *EFI_HANDLE;

#define EFI_SUCCESS 0
#define EFIAPI

struct efi_simple_text_output_protocol;

typedef EFI_STATUS (EFIAPI *efi_text_string)(
    struct efi_simple_text_output_protocol *self,
    const CHAR16 *string);

typedef struct efi_simple_text_output_protocol {
    VOID *reset;
    efi_text_string output_string;
    VOID *test_string;
    VOID *query_mode;
    VOID *set_mode;
    VOID *set_attribute;
    VOID *clear_screen;
    VOID *set_cursor_position;
    VOID *enable_cursor;
    VOID *mode;
} EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;

typedef struct efi_table_header {
    UINT64 signature;
    UINT32 revision;
    UINT32 header_size;
    UINT32 crc32;
    UINT32 reserved;
} EFI_TABLE_HEADER;

typedef struct efi_system_table {
    EFI_TABLE_HEADER hdr;
    CHAR16 *firmware_vendor;
    UINT32 firmware_revision;
    EFI_HANDLE console_in_handle;
    VOID *con_in;
    EFI_HANDLE console_out_handle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *con_out;
    EFI_HANDLE standard_error_handle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *std_err;
    VOID *runtime_services;
    VOID *boot_services;
    UINTN number_of_table_entries;
    VOID *configuration_table;
} EFI_SYSTEM_TABLE;

static void puts16(EFI_SYSTEM_TABLE *system_table, const CHAR16 *message) {
    if (system_table != 0 &&
        system_table->con_out != 0 &&
        system_table->con_out->output_string != 0) {
        system_table->con_out->output_string(system_table->con_out, message);
    }
}

EFI_STATUS EFIAPI efi_main(EFI_HANDLE image_handle, EFI_SYSTEM_TABLE *system_table) {
    (void)image_handle;

    puts16(system_table, u"\r\n");
    puts16(system_table, u"XNU EFI fallback loader\r\n");
    puts16(system_table, u"\r\n");
    puts16(system_table, u"This ISO is UEFI bootable and bundles:\r\n");
    puts16(system_table, u"  /boot/xnu-kernel.macho\r\n");
    puts16(system_table, u"Default boot-args:\r\n");
    puts16(system_table, XNU_BOOT_ARGS_TEXT);
    puts16(system_table, u"\r\n");
    puts16(system_table, u"Apple boot.efi/iBoot is not part of the open XNU source tree.\r\n");
    puts16(system_table, u"Provide XNU_EFI_LOADER=/path/to/BOOT*.EFI to replace this fallback\r\n");
    puts16(system_table, u"with a loader that performs the real XNU platform handoff.\r\n");

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
SOURCE

case "$arch" in
    amd64)
        target=x86_64-unknown-windows
        ;;
    arm64)
        target=aarch64-unknown-windows
        ;;
    *)
        echo "unsupported architecture: $arch" >&2
        exit 2
        ;;
esac

"$clang" \
    -target "$target" \
    -ffreestanding \
    -fshort-wchar \
    -fno-stack-protector \
    -fno-builtin \
    -fuse-ld=lld-link \
    -nostdlib \
    -Wl,/subsystem:efi_application \
    -Wl,/entry:efi_main \
    "$loader_c" \
    -o "$output"

file "$output"
