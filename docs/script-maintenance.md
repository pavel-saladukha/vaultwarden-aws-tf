# Maintain the startup, backup, and restore scripts

Start with the `main` function at the end of each script. It lists the operations
in order. Each function has one task. Error messages identify the failed check.
The scripts use Bash and standard host commands.
No code generation tool is required to maintain them.

## Files and inputs

| File | Task | Inputs |
|---|---|---|
| `data/init.sh` | Prepare a new host and start services | Terraform template inputs from `ec2.tf` |
| `data/scripts/backup.sh` | Save a checked database snapshot and application files | Bucket template input from `s3.tf`; optional `VW_HOME` |
| `data/scripts/restore.sh` | Preserve an archive, check it, and install restored data | One archive path; optional `VW_HOME` |

`init.sh` and `backup.sh` are Terraform templates. Do not run their source files
directly. `${name}` is a Terraform input. `$${name}` becomes a Bash variable
expression in the rendered file. Use `$name` for ordinary Bash variables where
braces are not needed. `restore.sh` is copied as a file; it does not use template escaping.

The template inputs and version values are grouped at the top of `init.sh`.
The normal paths are `/home/ec2-user`, `/home/ec2-user/scripts`, `/opt/fail2ban`,
and `/opt/certbot`. `VW_HOME` lets backup and restore tests use temporary data.
It does not select the S3 bucket.

## Startup order

`main` installs host packages before AWS commands, then configures DNS, Docker,
Fail2ban, certificates, scripts, scheduled jobs, and the application.
Data restore completes before the first application start. Vaultwarden runs
database migrations at startup. Fail2ban starts after its configuration and logs exist.
The Spot handler starts after application setup. The final reboot is retained.

To change a package version, edit `local.software` and its matching hash or source ID.
To add a required host tool, edit `install_host_packages`.
To change a Fail2ban file mapping, edit `install_fail2ban_config`.
To change a schedule, edit `configure_scheduled_jobs`. `write_cron_file` supplies
the common shell and command path. It replaces each file to prevent duplicate jobs.

`install_verified_binary` checks the downloaded file before replacing an executable.
Its temporary file and the DNS request file have separate subshell cleanup handlers.
These handlers cannot replace the backup or restore cleanup handler.
The `name() ( ... )` form runs a function in a subshell. Directory changes and
cleanup handlers in that function do not change its caller.

The scripts use `set -euo pipefail` to stop on command errors, unset variables,
and failed pipelines. Call setup steps directly from `main`. Bash can suppress
automatic error exit inside a function used as an `if`, `&&`, or `||` condition.
Check expected failures inside the function and print a specific error message.

## Backup and restore rules

Both scripts hold file descriptor 9 as an exclusive lock on `.vaultwarden-data.lock`.
Do not remove the lock file while an operation is active.

Backup stops only Vaultwarden. Its exit handler always attempts to start Vaultwarden
again, including after a database or upload error. A failed operation returns a
nonzero status and keeps its temporary files. Upload the dated archive before
replacing `backup-latest.tar.gz`. Do not delete failed local archives until their
contents have been checked and a usable backup is available.

Restore requires the caller to stop Vaultwarden and move the current `vw-data`.
It preserves the source under `recovery/baseline.*` with a checksum. It uses `tar`
to extract the archive in a temporary directory, then checks the SQLite snapshot.
The checked snapshot becomes `db.sqlite3` without another database copy.
It installs `vw-data` only after extraction and the database check succeed. A failure removes the extraction
directory but keeps the baseline. Restore does not start services.

Restore trusts archives made by our backup script and stored in our backup bucket.
It does not perform a separate check of archive paths or file types. Do not use it
to inspect archives from other sources. Both gzip and the old uncompressed tar
format remain supported. Recovery must use the preserved baseline and the previous
application version together.

Do not add checks that repeat a command's own error handling. Package installation,
downloads, extraction, and service commands return errors themselves. Startup does
not repeat command lookup, version, import, plugin, or Compose configuration checks.
Use the test runbook for installation verification.

Keep checks for external data and runtime conditions: binary download checksums,
one SQLite integrity check when making a backup and one before restoring it,
the shared lock, and refusal to restore over existing data. Keep the snapshot
existence check because SQLite can create an empty database if the file is missing.
Command failures still stop the scripts through `set -euo pipefail`.

## Checks before a commit

Use Python 3.14 and the temporary test environment described in
[`UPGRADE_VERIFICATION.md`](../UPGRADE_VERIFICATION.md). Put ShellCheck on `PATH`.
Run from the repository root:

```bash
python -B tests/check_integration.py
python3 -B -m unittest discover -s tests -p 'test_*.py' -v
git diff --check
```

The integration check renders dummy template inputs and checks shell syntax,
ShellCheck warnings, input names, and the EC2 user-data size limit.
The tests use temporary databases and mocked AWS, Docker, and download commands.
They source the rendered startup file to call individual functions. Sourcing does
not call `main`. The tests do not install host packages or contact AWS.
Keep tests focused on results and failure handling rather than function layout.

Instance checks remain pending. Use the separate test resources in
[`TEST_INSTANCE_RUNBOOK.md`](../TEST_INSTANCE_RUNBOOK.md). Do not run Terraform or
deploy resources as part of this local script review.
