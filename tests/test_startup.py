#!/usr/bin/env python3
"""Check downloaded-file validation without network access or host changes."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from startup_helpers import write_startup


class DownloadTests(unittest.TestCase):
    def test_binary_checksum_and_existing_file(self):
        with tempfile.TemporaryDirectory(prefix="vw-download-test-") as name:
            directory = Path(name)
            startup = write_startup(directory)
            payload = b"dummy executable\n"
            checksum = hashlib.sha256(payload).hexdigest()
            (directory / "payload").write_bytes(payload)
            curl = directory / "curl"
            curl.write_text('''#!/bin/bash
while (( $# )); do
    if [[ "$1" == -o ]]; then
        cp "$TEST_PAYLOAD" "$2"
        exit
    fi
    shift
done
exit 1
''')
            curl.chmod(0o755)
            env = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ["PATH"],
                       TEST_PAYLOAD=str(directory / "payload"))
            destination = directory / "installed"
            command = ["bash", "-c",
                       'source "$1"; install_verified_binary https://example.invalid/tool "$2" "$3"',
                       "--", str(startup), checksum, str(destination)]
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(destination.read_bytes(), payload)
            self.assertEqual(destination.stat().st_mode & 0o777, 0o755)

            # A bad download must not replace an installed file.
            command[-2] = "0" * 64
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("checksum does not match", result.stderr)
            self.assertEqual(destination.read_bytes(), payload)


if __name__ == "__main__":
    unittest.main()
