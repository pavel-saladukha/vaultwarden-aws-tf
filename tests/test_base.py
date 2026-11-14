#!/usr/bin/env python3
"""Run host startup checks with dummy data and mocked AWS commands."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from startup_helpers import write_startup

ROOT = Path(__file__).resolve().parents[1]

class BaseTests(unittest.TestCase):
    def test_dns_and_failure(self):
        with tempfile.TemporaryDirectory() as name:
            temp = Path(name)
            startup = write_startup(temp)
            (temp / "curl").write_text("#!/bin/bash\ncase \"$*\" in *api/token*) echo test-token;; *) echo 192.0.2.7;; esac\n".replace('\"', '"'))
            (temp / "aws").write_text("#!/bin/bash\n[[ $FAIL_AWS == 1 ]] && exit 42\nif [[ $2 == change-resource-record-sets ]]; then\nfor arg in \"$@\"; do [[ $arg == file://* ]] && cp \"${arg#file://}\" \"$CAPTURE\"; done\necho /change/TESTONLY\nelse [[ $* == *TESTONLY* ]]; fi\n".replace('\"', '"'))
            for script in (temp / "curl", temp / "aws"):
                script.chmod(0o755)
            env = dict(os.environ, PATH=str(temp)+":"+os.environ["PATH"], CAPTURE=str(temp / "batch.json"), FAIL_AWS="0")
            command = ["bash", "-c", 'source "$1"; register_dns', "--", str(startup)]
            result = subprocess.run(command, env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            record = json.loads((temp / "batch.json").read_text())["Changes"][0]["ResourceRecordSet"]
            self.assertEqual(record["ResourceRecords"], [{"Value": "192.0.2.7"}])
            self.assertEqual(record["Name"], "test-unique.example.invalid")
            env["FAIL_AWS"] = "1"
            self.assertNotEqual(subprocess.run(command, env=env, capture_output=True).returncode, 0)

    def test_spot_ignores_errors(self):
        source = (ROOT / "data/AWS_SpotTerminationNotifier.sh").read_text()
        with tempfile.TemporaryDirectory() as name:
            temp = Path(name)
            (temp / "curl").write_text("#!/bin/bash\ncase \"$*\" in *api/token*) echo token;; *) echo \"$STATUS\";; esac\n".replace('\"', '"'))
            (temp / "sleep").write_text("#!/bin/bash\nexit 77\n")
            (temp / "docker-compose").write_text("#!/bin/bash\ntouch \"$CALLED\"\nexit 88\n".replace('\"', '"'))
            for script in temp.iterdir():
                script.chmod(0o755)
            env = dict(os.environ, PATH=str(temp)+":"+os.environ["PATH"], CALLED=str(temp / "called"))
            for status in ("401", "404", "500"):
                env["STATUS"] = status
                self.assertEqual(subprocess.run(["bash", "-c", source], env=env).returncode, 77)
                self.assertFalse((temp / "called").exists())
            env["STATUS"] = "200"
            self.assertEqual(subprocess.run(["bash", "-c", source], env=env).returncode, 88)
            self.assertTrue((temp / "called").exists())

if __name__ == "__main__":
    unittest.main()
