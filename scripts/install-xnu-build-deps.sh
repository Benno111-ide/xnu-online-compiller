#!/usr/bin/env sh
set -eu

dst="${1:?usage: install-xnu-build-deps.sh <deps-dir>}"

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
    "$sdkroot/usr/local/include/CodeSignature" \
    "$sdkroot/usr/local/include/CoreEntitlements/V2" \
    "$sdkroot/usr/local/include/TrustCache" \
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
    uint32_t img4Runtime;
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
    uint32_t img4Runtime)
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
