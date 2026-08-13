#!/usr/bin/env sh
set -eu

dst="${1:?usage: install-xnu-build-deps.sh <deps-dir>}"
xnu_src="${2:-${XNU_SOURCE_DIR:-build/xnu-source}}"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Apple XNU build dependencies are only installed on macOS runners." >&2
    exit 1
fi

. ./xnu-upstream.env

sdkroot="$(xcrun -sdk macosx --show-sdk-path)"
availability_tool="$sdkroot/usr/local/libexec/availability.pl"

mkdir -p "$dst"

if [ -x "$availability_tool" ]; then
    echo "Found availability.pl in SDK: $availability_tool"
else
    src="$dst/AvailabilityVersions"
    obj="$dst/AvailabilityVersions-obj"
    sym="$dst/AvailabilityVersions-sym"
    install_root="$dst/AvailabilityVersions-dst"

    rm -rf "$src" "$obj" "$sym" "$install_root"
    git init "$src"
    git -C "$src" remote add origin "$AVAILABILITY_VERSIONS_REPO_URL"
    git -C "$src" fetch --depth 1 origin "$AVAILABILITY_VERSIONS_COMMIT"
    git -C "$src" checkout --detach FETCH_HEAD

    actual_commit="$(git -C "$src" rev-parse HEAD)"
    if [ "$actual_commit" != "$AVAILABILITY_VERSIONS_COMMIT" ]; then
        echo "Expected AvailabilityVersions $AVAILABILITY_VERSIONS_COMMIT, got $actual_commit" >&2
        exit 1
    fi

    cmake_bin="$(command -v cmake)"
    ninja_bin="$(command -v ninja)"

    make -C "$src" \
        CMAKE="$cmake_bin" \
        NINJA="$ninja_bin" \
        SRCROOT="$(pwd)/$src" \
        OBJROOT="$(pwd)/$obj" \
        SYMROOT="$(pwd)/$sym" \
        DSTROOT="$(pwd)/$install_root" \
        install

    if [ ! -x "$install_root/usr/local/libexec/availability.pl" ]; then
        echo "AvailabilityVersions did not produce usr/local/libexec/availability.pl" >&2
        exit 1
    fi

    sudo mkdir -p "$sdkroot/usr/local"
    sudo rsync -a "$install_root/usr/local/" "$sdkroot/usr/local/"

    if [ ! -x "$availability_tool" ]; then
        echo "Failed to install availability.pl into $availability_tool" >&2
        exit 1
    fi
fi

kernel_private_headers="$sdkroot/System/Library/Frameworks/Kernel.framework/Versions/A/PrivateHeaders"
sudo mkdir -p \
    "$sdkroot/usr/local/include/kernel" \
    "$sdkroot/usr/local/lib/kernel" \
    "$sdkroot/usr/local/lib/kernel/platform" \
    "$sdkroot/usr/local/include/CodeSignature" \
    "$sdkroot/usr/local/include/CoreEntitlements/V2" \
    "$sdkroot/usr/local/include/os" \
    "$sdkroot/usr/local/include/TrustCache" \
    "$sdkroot/usr/local/include/arm64/ppl" \
    "$sdkroot/usr/local/include/iBoot" \
    "$kernel_private_headers/AppleFeatures" \
    "$kernel_private_headers/platform"

if [ ! -f "$kernel_private_headers/AppleFeatures/AppleFeatures.h" ]; then
    cat > "$dst/AppleFeatures.h" <<'HEADER'
#ifndef APPLEFEATURES_H
#define APPLEFEATURES_H
#endif
HEADER
    sudo cp "$dst/AppleFeatures.h" "$kernel_private_headers/AppleFeatures/AppleFeatures.h"
fi

if [ ! -f "$sdkroot/usr/local/include/iBoot/boot_args_abi.h" ]; then
    cat > "$dst/boot_args_abi.h" <<'HEADER'
#ifndef IBOOT_BOOT_ARGS_ABI_H
#define IBOOT_BOOT_ARGS_ABI_H
#define IBOOT_MAX_ENV_VAR_DATA_SIZE 1024
#endif
HEADER
    sudo cp "$dst/boot_args_abi.h" "$sdkroot/usr/local/include/iBoot/boot_args_abi.h"
fi

if [ ! -f "$sdkroot/usr/local/include/CodeSignature/Entitlements.h" ]; then
    cat > "$dst/CodeSignature-Entitlements.h" <<'HEADER'
#ifndef CODESIGNATURE_ENTITLEMENTS_H
#define CODESIGNATURE_ENTITLEMENTS_H

#define kCSWebBrowserHostEntitlement "com.apple.private.web-browser-engine.host"
#define kCSWebBrowserGPUEntitlement "com.apple.private.web-browser-engine.gpu"
#define kCSWebBrowserNetworkEntitlement "com.apple.private.web-browser-engine.network"
#define kCSWebBrowserWebContentEntitlement "com.apple.private.web-browser-engine.webcontent"

#endif
HEADER
    sudo cp "$dst/CodeSignature-Entitlements.h" "$sdkroot/usr/local/include/CodeSignature/Entitlements.h"
fi

if [ ! -f "$sdkroot/usr/local/include/CoreEntitlements/V2/API.h" ]; then
    cat > "$dst/CoreEntitlements-V2-API.h" <<'HEADER'
#ifndef CORE_ENTITLEMENTS_V2_API_H
#define CORE_ENTITLEMENTS_V2_API_H

#include <CoreEntitlements/CoreEntitlements.h>

#endif
HEADER
    sudo cp "$dst/CoreEntitlements-V2-API.h" "$sdkroot/usr/local/include/CoreEntitlements/V2/API.h"
fi

if [ ! -f "$sdkroot/usr/local/include/CoreEntitlements/V2/Kernel.h" ]; then
    cat > "$dst/CoreEntitlements-V2-Kernel.h" <<'HEADER'
#ifndef CORE_ENTITLEMENTS_V2_KERNEL_H
#define CORE_ENTITLEMENTS_V2_KERNEL_H

#include <stdint.h>

typedef struct CEKernelAPI {
    uint64_t version;
} CEKernelAPI_t;

#endif
HEADER
    sudo cp "$dst/CoreEntitlements-V2-Kernel.h" "$sdkroot/usr/local/include/CoreEntitlements/V2/Kernel.h"
fi

if [ ! -f "$sdkroot/usr/local/include/os/firehose_buffer_private.h" ]; then
    cat > "$dst/os-firehose_buffer_private.h" <<'HEADER'
#ifndef OS_FIREHOSE_BUFFER_PRIVATE_H
#define OS_FIREHOSE_BUFFER_PRIVATE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <firehose/firehose_types_private.h>
#include <firehose/tracepoint_private.h>

#ifndef FIREHOSE_BUFFER_KERNEL_DEFAULT_CHUNK_COUNT
#define FIREHOSE_BUFFER_KERNEL_DEFAULT_CHUNK_COUNT 128
#endif

#ifndef FIREHOSE_BUFFER_KERNEL_DEFAULT_IO_PAGES
#define FIREHOSE_BUFFER_KERNEL_DEFAULT_IO_PAGES 8
#endif

#ifndef FIREHOSE_BUFFER_KERNEL_CHUNK_COUNT
#define FIREHOSE_BUFFER_KERNEL_CHUNK_COUNT FIREHOSE_BUFFER_KERNEL_DEFAULT_CHUNK_COUNT
#endif

struct firehose_buffer_range_s {
    uint16_t fbr_offset;
    uint16_t fbr_length;
};

#ifdef __cplusplus
extern "C" {
#endif

firehose_buffer_t __firehose_buffer_create(size_t *size);
bool __firehose_kernel_configuration_valid(uint8_t chunk_count, uint8_t io_pages);
bool __firehose_merge_updates(firehose_push_reply_t update);
firehose_tracepoint_t __firehose_buffer_tracepoint_reserve(uint64_t stamp,
    firehose_stream_t stream, uint16_t pubsize, uint16_t privsize, uint8_t **privdata);
void __firehose_buffer_tracepoint_flush(firehose_tracepoint_t tracepoint,
    firehose_tracepoint_id_u tracepoint_id);

#ifdef __cplusplus
}
#endif

#endif
HEADER
    sudo cp "$dst/os-firehose_buffer_private.h" "$sdkroot/usr/local/include/os/firehose_buffer_private.h"
fi

if [ ! -f "$sdkroot/usr/local/include/arm64/ppl/sart.h" ]; then
    cat > "$dst/arm64-ppl-sart.h" <<'HEADER'
#ifndef ARM64_PPL_SART_H
#define ARM64_PPL_SART_H

static inline void
sart_bootstrap(void)
{
}

#endif
HEADER
    sudo cp "$dst/arm64-ppl-sart.h" "$sdkroot/usr/local/include/arm64/ppl/sart.h"
fi

if [ ! -f "$sdkroot/usr/local/include/arm64/ppl/uat.h" ]; then
    cat > "$dst/arm64-ppl-uat.h" <<'HEADER'
#ifndef ARM64_PPL_UAT_H
#define ARM64_PPL_UAT_H
#endif
HEADER
    sudo cp "$dst/arm64-ppl-uat.h" "$sdkroot/usr/local/include/arm64/ppl/uat.h"
fi

if [ ! -f "$sdkroot/usr/local/lib/kernel/libfirehose_kernel.a" ]; then
    cat > "$dst/firehose_kernel_common_stub.c" <<'SOURCE'
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef uint8_t firehose_stream_t;
typedef union firehose_buffer_u *firehose_buffer_t;
typedef struct firehose_tracepoint_s *firehose_tracepoint_t;
typedef union {
    uint64_t ftid_value;
} firehose_tracepoint_id_u;
typedef struct {
    uint64_t fpr_mem_flushed_pos;
    uint64_t fpr_io_flushed_pos;
} firehose_push_reply_t;

firehose_buffer_t
__firehose_buffer_create(size_t *size)
{
    (void)size;
    return (firehose_buffer_t)0;
}

bool
__firehose_kernel_configuration_valid(uint8_t chunk_count, uint8_t io_pages)
{
    return chunk_count != 0 && io_pages != 0;
}

bool
__firehose_merge_updates(firehose_push_reply_t update)
{
    (void)update;
    return false;
}

firehose_tracepoint_t
__firehose_buffer_tracepoint_reserve(uint64_t stamp, firehose_stream_t stream,
    uint16_t pubsize, uint16_t privsize, uint8_t **privdata)
{
    (void)stamp;
    (void)stream;
    (void)pubsize;
    (void)privsize;
    if (privdata != NULL) {
        *privdata = NULL;
    }
    return (firehose_tracepoint_t)0;
}

void
__firehose_buffer_tracepoint_flush(firehose_tracepoint_t tracepoint,
    firehose_tracepoint_id_u tracepoint_id)
{
    (void)tracepoint;
    (void)tracepoint_id;
}
SOURCE

    if [ -f "$xnu_src/config/libTightbeam.exports" ]; then
        while IFS= read -r symbol; do
            case "$symbol" in
                _tb_*)
                    printf 'uintptr_t %s(void) { return 0; }\n' "${symbol#_}" >> "$dst/firehose_kernel_common_stub.c"
                    ;;
            esac
        done < "$xnu_src/config/libTightbeam.exports"
    fi

    cat > "$dst/arm64_platform_stub.c" <<'SOURCE'
#include <stdint.h>

uintptr_t
uat_get_desc(void)
{
    return 0;
}

uintptr_t
sart_get_desc(void)
{
    return 0;
}

uintptr_t
t6000dart_get_desc(void)
{
    return 0;
}

uintptr_t
t6000dart_vo_tte(void)
{
    return 0;
}

uintptr_t
t8020dart_get_desc(void)
{
    return 0;
}

uintptr_t
t8020dart_vo_tte(void)
{
    return 0;
}

uintptr_t
t8110dart_get_desc(void)
{
    return 0;
}

uintptr_t
t8110dart_max_translation_levels(void)
{
    return 0;
}

uintptr_t
t8110dart_vo_tt_index(void)
{
    return 0;
}

uintptr_t
t8110dart_vo_tte(void)
{
    return 0;
}
SOURCE

    cat > "$dst/arm64_link_stub.s" <<'SOURCE'
.text
.align 2

.macro ret_zero symbol
.globl \symbol
\symbol:
	mov	x0, #0
	ret
.endmacro

.macro ret_void symbol
.globl \symbol
\symbol:
	ret
.endmacro

ret_void _CleanPoC_DcacheRegion_Force_nopreempt
ret_void _CleanPoC_DcacheRegion_Force_nopreempt_nohid
ret_void _ml_enable_monitor
ret_zero _nvme_ppl_get_desc
ret_zero _pmap_cs_configuration
ret_zero _pmap_has_iofilter_protected_write
ret_zero _pmap_iommu_alloc_contiguous_pages
ret_zero _pmap_iommu_init
ret_zero _pmap_iommu_ioctl
ret_zero _pmap_iommu_iovmalloc
ret_zero _pmap_iommu_iovmfree
ret_zero _pmap_iommu_map
ret_zero _pmap_iommu_unmap
ret_zero __ZN26IOUnifiedAddressTranslator12commitUnmapsEv
ret_zero __ZN26IOUnifiedAddressTranslator14prepareFWUnmapEyy
ret_zero __ZN26IOUnifiedAddressTranslator17getPageTableEntryEy
ret_zero __ZN26IOUnifiedAddressTranslator18setClientContextIDEjb
ret_zero __ZN26IOUnifiedAddressTranslator19isPageFaultExpectedEyj
ret_zero __ZN26IOUnifiedAddressTranslator21removeClientContextIDEv
ret_zero __ZN26IOUnifiedAddressTranslator22registerTaskForServiceEP4taskP9IOService
ret_zero __ZN26IOUnifiedAddressTranslator23createMappingInApertureEjP18IOMemoryDescriptorjym
ret_zero __ZN26IOUnifiedAddressTranslator23getTotalPageTableMemoryEv
ret_zero __ZN26IOUnifiedAddressTranslator29getFirmwareAddressSpaceHandleEv
ret_zero __ZN26IOUnifiedAddressTranslator3mapEP11IOMemoryMapj
ret_zero __ZN26IOUnifiedAddressTranslator5doMapEP18IOMemoryDescriptoryyj
ret_zero __ZN26IOUnifiedAddressTranslator5unmapEP11IOMemoryMap
ret_zero __ZN26IOUnifiedAddressTranslator7doUnmapEP18IOMemoryDescriptoryy
ret_zero __ZN26IOUnifiedAddressTranslator7getModeEv
ret_zero __ZN26IOUnifiedAddressTranslator8taskDiedEv

.data
.align 3
.globl _rorgn_begin
_rorgn_begin:
	.quad 0
.globl _rorgn_end
_rorgn_end:
	.quad 0
.globl __ZN26IOUnifiedAddressTranslator10gMetaClassE
__ZN26IOUnifiedAddressTranslator10gMetaClassE:
	.quad 0
.globl __ZN26IOUnifiedAddressTranslator10superClassE
__ZN26IOUnifiedAddressTranslator10superClassE:
	.quad 0
.globl __ZTV26IOUnifiedAddressTranslator
__ZTV26IOUnifiedAddressTranslator:
	.quad 0
	.quad 0
SOURCE

    clang -c -arch x86_64 -mmacosx-version-min=15.5 \
        "$dst/firehose_kernel_common_stub.c" -o "$dst/firehose_kernel_common_stub.x86_64.o"
    clang -c -arch arm64e -mmacosx-version-min=15.5 \
        "$dst/firehose_kernel_common_stub.c" -o "$dst/firehose_kernel_common_stub.arm64e.o"
    clang -c -arch arm64e -mmacosx-version-min=15.5 \
        "$dst/arm64_platform_stub.c" -o "$dst/arm64_platform_stub.arm64e.o"
    clang -c -arch arm64e -mmacosx-version-min=15.5 \
        "$dst/arm64_link_stub.s" -o "$dst/arm64_link_stub.arm64e.o"
    libtool -static -o "$dst/libfirehose_kernel.x86_64.a" \
        "$dst/firehose_kernel_common_stub.x86_64.o"
    libtool -static -o "$dst/libfirehose_kernel.arm64e.a" \
        "$dst/firehose_kernel_common_stub.arm64e.o" "$dst/arm64_platform_stub.arm64e.o" \
        "$dst/arm64_link_stub.arm64e.o"
    lipo -create -output "$dst/libfirehose_kernel.a" \
        "$dst/libfirehose_kernel.x86_64.a" "$dst/libfirehose_kernel.arm64e.a"
    sudo cp "$dst/libfirehose_kernel.a" "$sdkroot/usr/local/lib/kernel/libfirehose_kernel.a"
fi

if [ ! -f "$sdkroot/usr/local/include/TrustCache/API.h" ]; then
    cat > "$dst/TrustCache-API.h" <<'HEADER'
#ifndef TRUSTCACHE_API_H
#define TRUSTCACHE_API_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define kTCEntryHashSize 20
#define kUUIDSize 16

typedef struct {
    uint8_t component;
    uint32_t error;
    uint32_t uniqueError;
} TCReturn_t;

enum {
    kTCReturnSuccess = 0,
    kTCReturnError = 1,
    kTCReturnDuplicate = 2,
    kTCReturnNotFound = 3
};

typedef enum {
    kTCTypeInvalid = 0,
    kTCTypeStatic = 1,
    kTCTypeEngineering = 2,
    kTCTypeLegacy = 3,
    kTCTypeLTRS = 4,
    kTCTypeDTRS = 5,
    kTCTypeCryptex1BootOS = 6,
    kTCTypeCryptex1BootApp = 7,
    kTCTypeTotal = 8
} TCType_t;

typedef enum {
    kTCQueryTypeStatic = 0,
    kTCQueryTypeLoadable = 1,
    kTCQueryTypeAll = 2,
    kTCQueryTypeTotal = 3
} TCQueryType_t;

typedef uint64_t TCCapabilities_t;

enum {
    kTCCapabilityNone = 0
};

typedef struct TrustCache {
    uintptr_t opaque[4];
} TrustCache_t;

typedef struct TrustCacheTypeConfig {
    const char *entitlementValue;
} TrustCacheTypeConfig_t;

static const TrustCacheTypeConfig_t TCTypeConfig[kTCTypeTotal] __attribute__((unused)) = {
    [kTCTypeInvalid] = { NULL },
    [kTCTypeStatic] = { NULL },
    [kTCTypeEngineering] = { NULL },
    [kTCTypeLegacy] = { NULL },
    [kTCTypeLTRS] = { "ltrs" },
    [kTCTypeDTRS] = { "dtrs" },
    [kTCTypeCryptex1BootOS] = { "cryptex1.boot.os" },
    [kTCTypeCryptex1BootApp] = { "cryptex1.boot.app" }
};

typedef struct TrustCacheRuntime {
    bool allowSecondStaticTC;
    bool allowEngineeringTC;
    bool allowLegacyTC;
    const void *img4Runtime;
} TrustCacheRuntime_t;

typedef struct TrustCacheMutableRuntime {
    uintptr_t opaque[4];
} TrustCacheMutableRuntime_t;

typedef struct TrustCacheQueryToken {
    const TrustCache_t *trustCache;
    const void *trustCacheEntry;
} TrustCacheQueryToken_t;

static inline void
trustCacheInitializeRuntime(
    TrustCacheRuntime_t *runtime,
    TrustCacheMutableRuntime_t *mutableRuntime,
    bool allowSecondStaticTC,
    bool allowEngineeringTC,
    bool allowLegacyTC,
    const void *img4Runtime)
{
    (void)mutableRuntime;
    runtime->allowSecondStaticTC = allowSecondStaticTC;
    runtime->allowEngineeringTC = allowEngineeringTC;
    runtime->allowLegacyTC = allowLegacyTC;
    runtime->img4Runtime = img4Runtime;
}

#endif
HEADER
    sudo cp "$dst/TrustCache-API.h" "$sdkroot/usr/local/include/TrustCache/API.h"
fi

echo "Installed AvailabilityVersions $actual_commit into $sdkroot"
