#!/usr/bin/env python3
"""Exercise the real supervisor without replacing the host's PID 1."""
import os
from pathlib import Path
import shlex
import signal
import subprocess
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


class InitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="xnu-init-build-")
        cls.binary = Path(cls.build.name) / "xnu-init"
        subprocess.run(
            shlex.split(os.environ.get("CC", "cc"))
            + ["-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
               str(REPO / "init/xnu-init.c"), "-o", str(cls.binary)],
            check=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="xnu-init-test-")
        self.root = Path(self.temp.name)
        self.config = self.root / "services.conf"
        self.process = None
        self.log = open(self.root / "log", "w+")

    def tearDown(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        self.log.close()
        self.temp.cleanup()

    def start(self, config):
        self.config.write_text(config)
        self.process = subprocess.Popen(
            [str(self.binary), "--user", "--config", str(self.config)],
            cwd=self.root, stdout=self.log, stderr=self.log,
        )

    def wait_for(self, condition, timeout=8, supervisor=True):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if condition():
                return
            if supervisor and self.process and self.process.poll() is not None:
                self.fail("supervisor exited unexpectedly: " + self.logs())
            time.sleep(0.05)
        self.fail("timed out: " + self.logs())

    def logs(self):
        return (self.root / "log").read_text()

    def check(self, config):
        self.config.write_text(config)
        return subprocess.run(
            [str(self.binary), "--check", "--config", str(self.config)],
            cwd=self.root, text=True, capture_output=True, timeout=5,
        )

    def test_config_validation_and_no_execution(self):
        self.assertEqual(self.check("a | once | touch forbidden\n").returncode, 0)
        self.assertFalse((self.root / "forbidden").exists())
        for config in ["", "# comment\n", "a | unknown | true\n",
                       "a | once |\n", "a | once | true\na | once | true\n",
                       "bad name | once | true\n", "x" * 5000,
                       "".join(f"s{i}|once|true\n" for i in range(65))]:
            with self.subTest(config=config[:40]):
                self.assertNotEqual(self.check(config).returncode, 0)
        self.assertEqual(self.check("a|once|printf hi | cat\n").returncode, 0)

    def test_default_config(self):
        result = subprocess.run(
            [str(self.binary), "--check", "--config", str(REPO / "init/services.conf")],
            capture_output=True, timeout=5,
        )
        self.assertEqual(result.returncode, 0)

    def test_requires_pid_one_or_explicit_user_mode(self):
        result = subprocess.run([str(self.binary)], capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"requires PID 1", result.stderr)

    def test_ordered_startup(self):
        self.start("first|once|sleep 0.3; echo first >> order\n"
                   "second|once|echo second >> order\n"
                   "daemon|respawn|echo daemon >> order; exec sleep 60\n")
        path = self.root / "order"
        self.wait_for(lambda: path.exists() and len(path.read_text().splitlines()) == 3)
        self.assertEqual(path.read_text().splitlines(), ["first", "second", "daemon"])
        self.process.terminate()
        self.assertEqual(self.process.wait(timeout=10), 0)

    def test_failed_boot_job_stops_later_services(self):
        self.start("fail|once|exit 7\nnever|respawn|touch forbidden\n")
        self.assertEqual(self.process.wait(timeout=10), 1)
        self.assertFalse((self.root / "forbidden").exists())
        self.assertIn("status=7", self.logs())

    def test_restart_backoff(self):
        self.start("crash|respawn|echo attempt >> attempts; exit 9\n")
        path = self.root / "attempts"
        self.wait_for(lambda: path.exists() and len(path.read_text().splitlines()) >= 3)
        self.assertIn("retry crash in 1 seconds", self.logs())
        self.assertIn("retry crash in 2 seconds", self.logs())
        self.process.terminate()
        self.assertEqual(self.process.wait(timeout=10), 0)
        self.assertEqual(len(path.read_text().splitlines()), 3)

    def test_shutdown_kills_descendants_ignoring_term(self):
        script = self.root / "stubborn.sh"
        script.write_text("#!/bin/sh\ntrap '' TERM\necho $$ > descendant.pid\n"
                          "while :; do sleep 1; done\n")
        self.start("tree|respawn|/bin/sh stubborn.sh & wait\n")
        path = self.root / "descendant.pid"
        self.wait_for(path.exists)
        child = int(path.read_text())
        self.process.send_signal(signal.SIGTERM)
        self.assertEqual(self.process.wait(timeout=10), 0)
        # An orphan may briefly be a zombie until the host init reaps it.
        def gone():
            try:
                os.kill(child, 0)
            except ProcessLookupError:
                return True
            stat = Path(f"/proc/{child}/stat")
            return stat.exists() and stat.read_text().split(") ", 1)[1].startswith("Z")
        self.wait_for(gone, supervisor=False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
