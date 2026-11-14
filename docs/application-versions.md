# Application upgrade record

Base commit: `82bbefb`. Branch: `upgrade/application`.
Release and registry checks: 2026-11-14.
The shared version values are in `local.software`.

| Component | Selected version | OCI index SHA-256 |
|---|---|---|
| Vaultwarden | 1.37.5 | `4fe17f415f90087377d37c755e0ea3cf189dcc6794e49cdd2a9adbb4937d9e1f` |
| Nginx | 1.30.6 | `42c68eab6f7e22611786a9fe1d1c019e275c50185bd54b8f75dc2b9184322703` |

The registry response body SHA-256 agrees with the `Docker-Content-Digest`
header for both tags. The Linux amd64 manifest digests are:

- Vaultwarden: `sha256:f8863ab2519364bfc657144006682a830784e0bb501606d5e34516ee76b60b5c`.
- Nginx: `sha256:909063468649748c84e0fa2a67869c7b0b2d431c72b73cf654e4052f1e2d2937`.

## Release and support checks

[Vaultwarden 1.37.5 release notes](https://github.com/dani-garcia/vaultwarden/releases/tag/1.37.5)
identify this release as the latest stable release. The release includes
security corrections and web vault 2026.10.1. Invalid configuration values
can stop startup. Check any saved `vw-data/config.json` before the server test.
The release supports the newer client API changes. No separate SQLite
conversion command is specified.

The [Nginx download page](https://nginx.org/en/download.html) lists 1.30.6
as stable and 1.31.8 as mainline. Select the stable series for this upgrade.
The [1.30 changes](https://nginx.org/en/CHANGES-1.30) include the October
security corrections. The existing HTTP/2 and TLS directives are supported.

The [Vaultwarden database code](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/db/mod.rs)
runs the embedded SQLite migrations at startup. Restore the old snapshot
before the first start of the new image. Do not start an old image with
a migrated database.

## Backup and recovery

The backup script stops Vaultwarden, creates and checks a SQLite snapshot,
and stores the complete data set. It uploads a unique dated archive before
it replaces `backup-latest.tar.gz`. An error causes a nonzero exit and a
service start attempt. Failed uploads keep the local archive.

Startup checks S3 for the exact latest key. An AWS error stops startup;
an empty bucket permits a new database. Restore accepts the existing
uncompressed archive format and the new gzip format. It trusts archives from
the backup bucket and uses `tar` for extraction. It checks the database snapshot
before it installs `vw-data`.

Restore stores an unchanged archive and SHA-256 file under
`/home/ec2-user/recovery/baseline.*` before migration. Copy this baseline
to a separate key in the test backup bucket before any upgrade test. Keep the
previous Compose file and image references with it. For recovery:

1. Stop the application with `docker-compose down`.
2. Move the migrated `vw-data` to a separate directory.
3. Run `bash scripts/restore.sh recovery/baseline.REPLACE/backup.tar.gz`.
4. Restore the previous Compose file and image references.
5. Start the previous version. Check login, records, and attachments.

Keep the full `/etc/letsencrypt` read-only mount. The certificate paths
use the `live` links, which refer to files under `archive`. The supporting
software group owns renewal and the Nginx reload command.

## Checks

Passed: `python3 -B tests/test_application.py` (9 tests), shell syntax,
and `git diff --check`. Tests use temporary SQLite databases, dummy bucket
names, and mocked AWS and Compose commands. They cover the full data
restore, recovery after a simulated database change, database failure,
upload failure, restart failure, damaged archives and snapshots, and empty-bucket lookup.
No Terraform command was run.

Pending on a separate test server: image pull, Nginx build and `nginx -t`,
real Vaultwarden migration, startup logs, login and client sync, attachments,
certificate renewal and reload, and recovery with the previous image.
Use a new test workspace and unique resource names, URL, and S3 buckets.
Deployment and production changes are not authorized by these checks.
