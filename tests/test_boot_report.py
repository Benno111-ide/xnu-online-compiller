import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "boot_report", Path(__file__).resolve().parents[1] / "scripts/check-boot-report.py")
boot_report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot_report)


class BootReportTests(unittest.TestCase):
    def test_firmware_shell_is_not_loader_success(self):
        self.assertTrue(boot_report.assess("", "UEFI Interactive Shell", "", "")[2])

    def test_fallback_is_not_kernel_boot(self):
        self.assertEqual(boot_report.assess("", "XNU EFI fallback loader", "", ""),
                         (True, False, []))

    def test_kernel_output(self):
        self.assertEqual(boot_report.assess("Darwin Kernel Version 25.0.0", "", "", ""),
                         (True, True, []))

    def test_exception_overrides_loader_progress(self):
        self.assertTrue(boot_report.assess("OC: Starting\n!!!! X64 Exception Type - 0D", "", "", "")[2])

    def test_panic_overrides_kernel_output(self):
        self.assertTrue(boot_report.assess("Darwin Kernel Version\npanic(cpu 0 caller 0x123)", "", "", "")[2])

    def test_normal_initial_cpu_reset_is_allowed(self):
        self.assertFalse(boot_report.assess("OC: Starting", "", "", "CPU Reset (CPU 0)")[2])

    def test_triple_fault_fails(self):
        self.assertTrue(boot_report.assess("OC: Starting", "", "", "Triple fault")[2])

    def test_qemu_error_fails(self):
        self.assertTrue(boot_report.assess("OC: Starting", "", "qemu-system-x86_64: Could not open disk", "")[2])

    def test_report_is_saved_on_success_and_failure(self):
        for serial, expected in [("OC: Starting", 0),
                                 ("OC: Starting\nX64 Exception Type - 0D", 1)]:
            with self.subTest(expected=expected), tempfile.TemporaryDirectory() as temp:
                out = Path(temp)
                (out / "serial.log").write_text(serial, encoding="utf-8")
                with patch.object(sys, "argv", ["check-boot-report.py", temp]), patch("builtins.print"):
                    self.assertEqual(boot_report.main(), expected)
                self.assertIn(f"result={'FAIL' if expected else 'PASS'}",
                              (out / "boot-test.txt").read_text(encoding="utf-8"))
                self.assertEqual((out / "serial.log").read_text(encoding="utf-8"), serial)

    def test_screenshot_exception_fails_even_with_good_serial(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            (out / "serial.log").write_text("OC: Starting", encoding="utf-8")
            (out / "screen-01.ppm").touch()
            ocr = subprocess.CompletedProcess([], 0, stdout="General Protection", stderr="")
            with patch.object(sys, "argv", ["check-boot-report.py", temp]), \
                    patch.object(boot_report.subprocess, "run", return_value=ocr), patch("builtins.print"):
                self.assertEqual(boot_report.main(), 1)
            self.assertIn("General Protection", (out / "screen-text.txt").read_text(encoding="utf-8"))
