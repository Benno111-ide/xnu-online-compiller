#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <opencore-output-dir>" >&2
    exit 2
fi

dst=$1
case "$dst" in
    build/*|./build/*|*/build/*) ;;
    *)
        echo "refusing to replace non-build OpenCore directory: $dst" >&2
        exit 2
        ;;
esac

. ./xnu-upstream.env

normalize_opencore_config() {
    config=$1
    python3 - "$config" <<'PY'
from pathlib import Path
import os
import plistlib
import sys

config = Path(sys.argv[1])
boot_args = os.environ.get("XNU_BOOT_ARGS", "-v keepsyms=1 debug=0x144 serial=3")
with config.open("rb") as f:
    plist = plistlib.load(f)

for key in list(plist):
    if key.startswith("#"):
        del plist[key]

acpi = plist.setdefault("ACPI", {})
acpi["Add"] = []
acpi["Delete"] = []
acpi["Patch"] = []
acpi["Quirks"] = {
    "FadtEnableReset": False,
    "NormalizeHeaders": False,
    "RebaseRegions": False,
    "ResetHwSig": False,
    "ResetLogoStatus": False,
    "SyncTableIds": False,
}

booter = plist.setdefault("Booter", {})
booter["MmioWhitelist"] = []
booter["Patch"] = []
booter["Quirks"] = {
    "AllowRelocationBlock": False,
    "AvoidRuntimeDefrag": True,
    "ClearTaskSwitchBit": False,
    "DevirtualiseMmio": False,
    "DisableSingleUser": False,
    "DisableVariableWrite": False,
    "DiscardHibernateMap": False,
    "EnableSafeModeSlide": True,
    "EnableWriteUnprotector": True,
    "FixupAppleEfiImages": True,
    "ForceBooterSignature": False,
    "ForceExitBootServices": False,
    "ProtectMemoryRegions": False,
    "ProtectSecureBoot": False,
    "ProtectUefiServices": False,
    "ProvideCustomSlide": True,
    "ProvideMaxSlide": 0,
    "RebuildAppleMemoryMap": True,
    "ResizeAppleGpuBars": -1,
    "SetupVirtualMap": True,
    "SignalAppleOS": False,
    "SyncRuntimePermissions": True,
}

device_properties = plist.setdefault("DeviceProperties", {})
device_properties["Add"] = {}
device_properties["Delete"] = {}

kernel = plist.setdefault("Kernel", {})
kernel["Add"] = []
kernel["Block"] = []
kernel["Emulate"] = {
    "Cpuid1Data": b"",
    "Cpuid1Mask": b"",
    "DummyPowerManagement": False,
    "MaxKernel": "",
    "MinKernel": "",
}
kernel["Force"] = []
kernel["Patch"] = []
kernel["Quirks"] = {
    "AppleCpuPmCfgLock": True,
    "AppleXcpmCfgLock": True,
    "AppleXcpmExtraMsrs": False,
    "AppleXcpmForceBoost": False,
    "CustomPciSerialDevice": False,
    "CustomSMBIOSGuid": False,
    "DisableIoMapper": True,
    "DisableIoMapperMapping": True,
    "DisableLinkeditJettison": True,
    "DisableRtcChecksum": False,
    "ExtendBTFeatureFlags": False,
    "ExternalDiskIcons": False,
    "ForceAquantiaEthernet": False,
    "ForceSecureBootScheme": False,
    "IncreasePciBarSize": False,
    "LapicKernelPanic": True,
    "LegacyCommpage": False,
    "PanicNoKextDump": True,
    "PowerTimeoutKernelPanic": True,
    "ProvideCurrentCpuInfo": False,
    "SetApfsTrimTimeout": -1,
    "ThirdPartyDrives": False,
    "XhciPortLimit": False,
}
kernel["Scheme"] = {
    "CustomKernel": False,
    "FuzzyMatch": True,
    "KernelArch": "Auto",
    "KernelCache": "Auto",
}

misc = plist.setdefault("Misc", {})
misc["BlessOverride"] = []
misc["Entries"] = []
misc["Tools"] = []

boot = misc.setdefault("Boot", {})
boot["ConsoleAttributes"] = 0
boot["HibernateMode"] = "None"
boot["HibernateSkipsPicker"] = False
boot["HideAuxiliary"] = False
boot["InstanceIdentifier"] = ""
boot["LauncherOption"] = "Disabled"
boot["LauncherPath"] = "Default"
boot["PickerAttributes"] = 17
boot["PickerAudioAssist"] = False
boot["PickerMode"] = "Builtin"
boot["PickerVariant"] = "Auto"
boot["PollAppleHotKeys"] = False
boot["ShowPicker"] = True
boot["TakeoffDelay"] = 0
boot["Timeout"] = 5

debug = misc.setdefault("Debug", {})
debug["AppleDebug"] = True
debug["ApplePanic"] = True
debug["DisableWatchDog"] = True
debug["DisplayDelay"] = 0
debug["DisplayLevel"] = 0x80000042
debug["LogModules"] = "*"
debug["SysReport"] = False
# Enable serial logging as well as console/file output so CI can retain it.
debug["Target"] = 75

security = misc.setdefault("Security", {})
security["AllowSetDefault"] = False
security["ApECID"] = 0
security["AuthRestart"] = False
security["BlacklistAppleUpdate"] = True
security["DmgLoading"] = "Any"
security["EnablePassword"] = False
security["ExposeSensitiveData"] = 15
security["HaltLevel"] = 0
security["PasswordHash"] = b""
security["PasswordSalt"] = b""
security["ScanPolicy"] = 0
security["SecureBootModel"] = "Disabled"
security["Vault"] = "Optional"

serial = misc.setdefault("Serial", {})
serial["Init"] = True
serial["Override"] = False

platform = plist.setdefault("PlatformInfo", {})
platform["Automatic"] = True
platform["CustomMemory"] = False
platform["UpdateDataHub"] = True
platform["UpdateNVRAM"] = True
platform["UpdateSMBIOS"] = True
platform["UpdateSMBIOSMode"] = "Create"
platform["UseRawUuidEncoding"] = False
generic = platform.setdefault("Generic", {})
generic["AdviseFeatures"] = False
generic["MLB"] = "OS8XNU00000000001"
generic["MaxBIOSVersion"] = False
generic["ProcessorType"] = 0
generic["ROM"] = b"\x02\x00\x00\x00\x00\x01"
generic["SpoofVendor"] = True
generic["SystemMemoryStatus"] = "Auto"
generic["SystemProductName"] = "iMac19,1"
generic["SystemSerialNumber"] = "OS8XNU000001"
generic["SystemUUID"] = "11111111-2222-3333-4444-555555555555"

nvram = plist.setdefault("NVRAM", {})
nvram["Add"] = {
    "4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14": {
        "DefaultBackgroundColor": b"\x00\x00\x00\x00",
    },
    "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102": {},
    "7C436110-AB2A-4BBB-A880-FE41995C9F82": {
        "boot-args": boot_args,
        "csr-active-config": b"\x00\x00\x00\x00",
        "prev-lang:kbd": b"en-US:0",
        "run-efi-updater": "No",
    },
}
nvram["Delete"] = {
    "4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14": [],
    "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102": [],
    "7C436110-AB2A-4BBB-A880-FE41995C9F82": [],
}
nvram["LegacyOverwrite"] = False
nvram["LegacySchema"] = {}
nvram["WriteFlash"] = True

uefi = plist.setdefault("UEFI", {})
uefi["APFS"] = {
    "EnableJumpstart": True,
    "GlobalConnect": False,
    "HideVerbose": False,
    "JumpstartHotPlug": False,
    "MinDate": 0,
    "MinVersion": 0,
}
uefi["AppleInput"] = {
    "AppleEvent": "Builtin",
    "CustomDelays": False,
    "GraphicsInputMirroring": True,
    "KeyInitialDelay": 50,
    "KeySubsequentDelay": 5,
    "PointerDwellClickTimeout": 0,
    "PointerDwellDoubleClickTimeout": 0,
    "PointerDwellRadius": 0,
    "PointerPollMask": -1,
    "PointerPollMax": 80,
    "PointerPollMin": 10,
    "PointerSpeedDiv": 1,
    "PointerSpeedMul": 1,
}
uefi["Audio"] = {
    "AudioCodec": 0,
    "AudioDevice": "PciRoot(0x0)/Pci(0x1b,0x0)",
    "AudioOutMask": 1,
    "AudioSupport": False,
    "DisconnectHda": False,
    "MaximumGain": -15,
    "MinimumAssistGain": -30,
    "MinimumAudibleGain": -55,
    "PlayChime": "Auto",
    "ResetTrafficClass": False,
    "SetupDelay": 0,
}
uefi["ConnectDrivers"] = True
uefi["Drivers"] = [
    {
        "Arguments": "",
        "Comment": "OpenCore runtime services",
        "Enabled": True,
        "LoadEarly": False,
        "Path": "OpenRuntime.efi",
    },
    {
        "Arguments": "",
        "Comment": "HFS+ filesystem support bundled with OpenCore",
        "Enabled": True,
        "LoadEarly": False,
        "Path": "OpenHfsPlus.efi",
    },
]
uefi["Input"] = {
    "KeyFiltering": False,
    "KeyForgetThreshold": 5,
    "KeySupport": True,
    "KeySupportMode": "Auto",
    "KeySwap": False,
    "PointerSupport": False,
    "PointerSupportMode": "",
    "TimerResolution": 50000,
}
uefi["Output"] = {
    "ClearScreenOnModeSwitch": False,
    "ConsoleFont": "",
    "ConsoleMode": "",
    "DirectGopRendering": False,
    "ForceResolution": False,
    "GopBurstMode": False,
    "GopPassThrough": "Disabled",
    "IgnoreTextInGraphics": False,
    "InitialMode": "Text",
    "ProvideConsoleGop": True,
    "ReconnectGraphicsOnConnect": True,
    "ReconnectOnResChange": False,
    "ReplaceTabWithSpace": False,
    "Resolution": "Max",
    "SanitiseClearScreen": False,
    "TextRenderer": "BuiltinGraphics",
    "UIScale": 0,
    "UgaPassThrough": False,
}
uefi["ProtocolOverrides"] = {
    "AppleAudio": False,
    "AppleBootPolicy": False,
    "AppleDebugLog": False,
    "AppleEg2Info": False,
    "AppleFramebufferInfo": False,
    "AppleImageConversion": False,
    "AppleImg4Verification": False,
    "AppleKeyMap": False,
    "AppleRtcRam": False,
    "AppleSecureBoot": False,
    "AppleSmcIo": False,
    "AppleUserInterfaceTheme": False,
    "DataHub": False,
    "DeviceProperties": False,
    "FirmwareVolume": False,
    "HashServices": False,
    "OSInfo": False,
    "PciIo": False,
    "UnicodeCollation": False,
}
uefi["Quirks"] = {
    "ActivateHpetSupport": False,
    "DisableSecurityPolicy": True,
    "EnableVectorAcceleration": True,
    "EnableVmx": True,
    "ExitBootServicesDelay": 0,
    "ForceOcWriteFlash": False,
    "ForgeUefiSupport": False,
    "IgnoreInvalidFlexRatio": False,
    "ReleaseUsbOwnership": False,
    "ReloadOptionRoms": False,
    "RequestBootVarRouting": True,
    "ResizeGpuBars": -1,
    "ResizeUsePciRbIo": False,
    "ShimRetainProtocol": False,
    "TscSyncTimeout": 0,
    "UnblockFsConnect": True,
}
uefi["ReservedMemory"] = []
uefi["Unload"] = []

with config.open("wb") as f:
    plistlib.dump(plist, f, sort_keys=False)
PY
}

validate_opencore_config() {
    root=$1
    config=$2
    if [ -x "$root/Utilities/ocvalidate/ocvalidate" ]; then
        "$root/Utilities/ocvalidate/ocvalidate" "$config"
    elif [ -x "$root/Utilities/ocvalidate/ocvalidate.linux" ]; then
        "$root/Utilities/ocvalidate/ocvalidate.linux" "$config"
    elif [ -x "$root/Utilities/ocvalidate/ocvalidate.exe" ]; then
        "$root/Utilities/ocvalidate/ocvalidate.exe" "$config"
    else
        echo "warning: OpenCore ocvalidate utility not found; skipping config schema validation" >&2
    fi
}

if [ -s "$dst/X64/EFI/BOOT/BOOTx64.efi" ] &&
   [ -s "$dst/X64/EFI/OC/OpenCore.efi" ] &&
   [ -s "$dst/X64/EFI/OC/config.plist" ]; then
    normalize_opencore_config "$dst/X64/EFI/OC/config.plist"
    validate_opencore_config "$dst" "$dst/X64/EFI/OC/config.plist"
    exit 0
fi

tmp="${dst}.tmp"
archive="${tmp}/OpenCore.zip"

rm -rf "$tmp"
mkdir -p "$tmp"

curl -fsSL "$OPENCORE_BINARY_URL" -o "$archive"
printf '%s  %s\n' "$OPENCORE_BINARY_SHA256" "$archive" | shasum -a 256 -c -
python3 - "$archive" "$tmp" <<'PY'
from pathlib import Path
import sys
import zipfile

archive = Path(sys.argv[1])
target = Path(sys.argv[2])
with zipfile.ZipFile(archive) as zf:
    zf.extractall(target)
PY
rm -f "$archive"

test -s "$tmp/X64/EFI/BOOT/BOOTx64.efi"
test -s "$tmp/X64/EFI/OC/OpenCore.efi"
test -s "$tmp/X64/EFI/OC/Drivers/OpenRuntime.efi"
test -s "$tmp/X64/EFI/OC/Drivers/OpenHfsPlus.efi"

if [ ! -s "$tmp/X64/EFI/OC/config.plist" ]; then
    if [ -s "$tmp/Docs/Sample.plist" ]; then
        cp "$tmp/Docs/Sample.plist" "$tmp/X64/EFI/OC/config.plist"
    else
        echo "OpenCore release did not contain X64/EFI/OC/config.plist or Docs/Sample.plist" >&2
        exit 1
    fi
fi

normalize_opencore_config "$tmp/X64/EFI/OC/config.plist"
validate_opencore_config "$tmp" "$tmp/X64/EFI/OC/config.plist"

rm -rf "$dst"
mv "$tmp" "$dst"
