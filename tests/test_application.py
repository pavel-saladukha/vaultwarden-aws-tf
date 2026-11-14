#!/usr/bin/env python3
"""Test backup and restore with dummy SQLite data and mocked AWS/Compose."""
import os
from contextlib import closing
from pathlib import Path
import sqlite3
import subprocess
import tarfile
import tempfile
import unittest
from startup_helpers import write_startup

ROOT = Path(__file__).resolve().parents[1]

class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="vw-upgrade-test-")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, VW_HOME=str(self.home),
                        PATH=str(self.bin) + os.pathsep + os.environ["PATH"])
        self.command("docker-compose", 'echo "$*" >> "$VW_HOME/compose.log"; exit "${COMPOSE_FAIL:-0}"')
        self.command("aws", 'echo "$*" >> "$VW_HOME/aws.log"; [ "${AWS_FAIL:-0}" = 0 ] || exit 9; cp "$3" "$VW_HOME/upload.tar.gz"')
        self.command("sqlite3", """exec python3 - "$@" <<'PYTHON'
import sqlite3,sys
from contextlib import closing
with closing(sqlite3.connect(sys.argv[1])) as c, c:
    query=sys.argv[2]
    if query.startswith('.backup '):
        with closing(sqlite3.connect(query[8:].strip("'"))) as dest, dest: c.backup(dest)
    else:
        for row in c.execute(query): print(*row,sep='|')
PYTHON""")
        data = self.home / "vw-data"
        data.mkdir()
        with closing(sqlite3.connect(data / "db.sqlite3")) as c, c:
            c.execute("create table dummy (value text)")
            c.execute("insert into dummy values ('baseline')")
        (data / "attachment.txt").write_text("attachment")
        self.backup = self.home / "backup.sh"
        self.backup.write_text((ROOT / "data/scripts/backup.sh").read_text()
                               .replace("$${", "${")
                               .replace("${s3_bucket_name}", "vw-upgrade-test-dummy"))

    def command(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(0o755)

    def run_script(self, script, *args):
        return subprocess.run(["bash", str(script), *map(str, args)],
                              env=self.env, capture_output=True, text=True)

    def test_round_trip_and_preserved_baseline(self):
        result = self.run_script(self.backup)
        self.assertEqual(result.returncode, 0, result.stderr)
        archive = self.home / "upload.tar.gz"
        with tarfile.open(archive) as t:
            self.assertIn("vw-data/backup.sqlite3", t.getnames())
            self.assertNotIn("vw-data/db.sqlite3", t.getnames())
        (self.home / "vw-data").rename(self.home / "old-data")
        result = self.run_script(ROOT / "data/scripts/restore.sh", archive)
        self.assertEqual(result.returncode, 0, result.stderr)
        with closing(sqlite3.connect(self.home / "vw-data/db.sqlite3")) as c, c:
            self.assertEqual(c.execute("select * from dummy").fetchone(), ("baseline",))
            c.execute("update dummy set value='migrated'")
        baseline = next((self.home / "recovery").glob("baseline.*/backup.tar.gz"))
        self.assertEqual(baseline.read_bytes(), archive.read_bytes())
        self.assertEqual((self.home / "vw-data/attachment.txt").read_text(), "attachment")
        (self.home / "vw-data").rename(self.home / "migrated-data")
        result = self.run_script(ROOT / "data/scripts/restore.sh", baseline)
        self.assertEqual(result.returncode, 0, result.stderr)
        with closing(sqlite3.connect(self.home / "vw-data/db.sqlite3")) as c, c:
            self.assertEqual(c.execute("select * from dummy").fetchone(), ("baseline",))

    def test_upload_failure_restarts_and_keeps_archive(self):
        self.env["AWS_FAIL"] = "1"
        result = self.run_script(self.backup)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("up -d vaultwarden", (self.home / "compose.log").read_text())
        self.assertEqual(len(list(self.home.glob("backup.*/backup.tar.gz"))), 1)
        self.assertNotIn("backup-latest.tar.gz", (self.home / "aws.log").read_text())

    def test_database_failure_restarts_without_upload(self):
        self.command("sqlite3", "exit 8")
        result = self.run_script(self.backup)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("up -d vaultwarden", (self.home / "compose.log").read_text())
        self.assertFalse((self.home / "aws.log").exists())

    def test_backup_discovery_empty_and_populated(self):
        for response, should_restore in [({}, False),
                ({"Contents": [{"Key": "backup-latest.tar.gz"}]}, True),
                ({"Contents": [{"Key": "backup-latest.tar.gz.old"}]}, False)]:
            with self.subTest(response=response):
                marker = self.home / "restore.log"
                marker.unlink(missing_ok=True)
                result = self.run_backup_lookup(response)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(marker.exists(), should_restore)

    def run_backup_lookup(self, response, fail=False):
        import json
        startup = write_startup(self.home)
        (self.home / "lookup.json").write_text(json.dumps(response))
        self.env["AWS_FAIL"] = "1" if fail else "0"
        self.command("aws", '''
            [ "$AWS_FAIL" = 0 ] || exit 9
            case "$1 $2" in
                "s3api list-objects-v2") cat "$VW_HOME/lookup.json" ;;
                "s3 cp") echo dummy-archive > "$4" ;;
                *) exit 10 ;;
            esac
        ''')
        scripts = self.home / "scripts"
        scripts.mkdir(exist_ok=True)
        (scripts / "restore.sh").write_text('#!/bin/bash\necho restored > "$VW_HOME/restore.log"\n')
        return subprocess.run([
            "bash", "-c",
            'source "$1"; APP_HOME="$VW_HOME"; SCRIPTS_DIR="$VW_HOME/scripts"; restore_latest_backup',
            "--", str(startup),
        ], env=self.env, capture_output=True, text=True)

    def test_backup_lookup_failure_does_not_restore(self):
        result = self.run_backup_lookup({}, fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / "restore.log").exists())

    def test_uncompressed_archive_restore(self):
        import gzip
        result = self.run_script(self.backup)
        self.assertEqual(result.returncode, 0, result.stderr)
        old_archive = self.home / "old-format.tar.gz"
        old_archive.write_bytes(gzip.decompress((self.home / "upload.tar.gz").read_bytes()))
        (self.home / "vw-data").rename(self.home / "old-data")
        result = self.run_script(ROOT / "data/scripts/restore.sh", old_archive)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / "vw-data/db.sqlite3").is_file())

    def test_restart_failure_is_reported(self):
        self.env["COMPOSE_FAIL"] = "1"
        result = self.run_script(self.backup)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cannot start Vaultwarden", result.stderr)

    def test_damaged_archive_does_not_install_data(self):
        archive = self.home / "damaged.tar.gz"
        archive.write_bytes(b"not a tar archive")
        (self.home / "vw-data").rename(self.home / "old-data")
        result = self.run_script(ROOT / "data/scripts/restore.sh", archive)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / "vw-data").exists())
        self.assertTrue(list((self.home / "recovery").glob("baseline.*/backup.tar.gz")))

    def test_missing_or_damaged_snapshot_does_not_install_data(self):
        import io
        (self.home / "vw-data").rename(self.home / "old-data")
        for snapshot in (None, b"not a SQLite database"):
            with self.subTest(snapshot=snapshot):
                archive = self.home / "damaged-data.tar"
                with tarfile.open(archive, "w") as tar:
                    attachment = tarfile.TarInfo("vw-data/attachment.txt")
                    attachment.size = 4
                    tar.addfile(attachment, io.BytesIO(b"data"))
                    if snapshot is not None:
                        member = tarfile.TarInfo("vw-data/backup.sqlite3")
                        member.size = len(snapshot)
                        tar.addfile(member, io.BytesIO(snapshot))
                result = self.run_script(ROOT / "data/scripts/restore.sh", archive)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.home / "vw-data").exists())
                self.assertFalse(list(self.home.glob("restore.*")))

if __name__ == "__main__":
    unittest.main()
