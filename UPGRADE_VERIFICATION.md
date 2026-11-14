# System upgrade checks

Date: 2026-11-14. All branches start at `main` commit `82bbefb`.
The integration branch is `upgrade/integration`.

| Group | Preserved commit | Version record |
|---|---|---|
| Base | `9251656` | [Base](BASE_VERSION_RECORD.md) |
| Supporting software | `0958496` | [Supporting software](docs/supporting-software-versions.md) |
| Application | `ff17403` | [Application](docs/application-versions.md) |

The groups were merged in the required order: base, supporting software, application.
The existing `docs/tooling-ami-upgrade-plan` branch is retained.
The shared version record is `local.software`. The test runbook lists the selected targets.

## Local results

| Check | Result |
|---|---|
| HCL syntax with python-hcl2 8.2.0 | Passed |
| Template input names and software references | Passed |
| Rendered shell syntax and ShellCheck 0.11.0 warnings | Passed |
| Compose YAML with PyYAML 6.0.3 | Passed |
| Image version and SHA-256 reference format | Passed |
| Certificate mount and renewal executable paths | Passed review |
| Configuration uploads before instance startup | Passed |
| Content-change detection for all 16 file-backed S3 objects | Passed static check |
| Notifier upload before launch template publication | Passed static check |
| Removing the notifier source hash in a temporary copy | Rejected by regression check |
| Rendered user-data size | 11,462 bytes; limit 16,384 |
| Host, application, and download dummy-data tests | 12 passed |
| Compose and Buildx download checksums and version commands | Passed in supporting software group |
| Fail2ban source commit and build with Python 3.14.10 | Passed in supporting software group |
| Selected Fail2ban action and regex tests | 28 passed in supporting software group |
| Certbot and Route 53 environment, plugin discovery, and pip check | Passed in supporting software group |
| Application image index digests | Verified against registry response SHA-256 in application group |
| Whitespace check | Passed |

Reproduce the integration checks from this worktree with Python 3.14 and Bash.
Use a temporary Python environment with `python-hcl2==8.2.0`, `PyYAML==6.0.3`,
and `shellcheck-py==0.11.0.1`. Put its `bin` directory on `PATH`:

```bash
python -B tests/check_integration.py
python3 -B -m unittest discover -s tests -p 'test_*.py' -v
git diff --check
```

The tests use temporary data and mocked AWS and Compose commands.
The SQLite command is replaced by a Python SQLite wrapper in the dummy tests.
This verifies backup and restore control flow. It does not verify the target host RPM.
The host system Python remains available. Python 3.14 is used for Fail2ban and Certbot.
The Python environment checks used local Python 3.14.10. The target AWS RPM is 3.14.7.
Certbot top-level packages are fixed. Its transitive dependency versions are not locked.

Integration adds the restore upload dependency, creates the log before Fail2ban starts,
and starts the Spot handler after application setup. Backup cron runs as root.
Restore completes before the first application start. It preserves an unchanged baseline
archive and checksum. Failed backup uploads keep local files and return an error.
Recovery uses the preserved baseline with the previous application images.
An older application must not open the migrated database.

## Script maintenance

The startup, backup, and restore scripts use named functions and an explicit `main`
sequence. See [the maintenance guide](docs/script-maintenance.md) for inputs,
operation order, error handling, and edit locations. Startup writes cron files
directly, without temporary templates or `envsubst`. Repeated setup replaces
cron files. Binary downloads share one checksum check with local cleanup.
Restore also accepts an archive path relative to the caller's directory.

The tests call the rendered startup functions with mocked commands. They no longer
extract source blocks by comment or line position. Additional checks cover failed
backup discovery, damaged archives and snapshots, old archive format, and failed binary
checksum verification without replacing an installed file.

Restore now uses `tar` directly and trusts the backup script and bucket. It no
longer contains Python archive validation or a second database copy and integrity
check. The checked snapshot becomes `db.sqlite3` directly. Runtime command lookup, version, import, plugin,
dependency, and Compose configuration checks were removed. The commands themselves
report failures; installation verification remains in the test runbook. Locks,
backup restart handling, baseline retention, checksums, and database checks remain.

File-backed S3 configuration objects use `source_hash = filesha256(...)` so an
edit at the same source path schedules an upload. The ASG depends on these objects,
including the Spot notifier. The launch template also depends on the notifier
upload because existing ASGs use `$Latest`. The IMDSv2 template is published only
after the new notifier is uploaded.
Objects that use `content` already track their rendered content. No ETag comparison
or runtime validation was added. This uses the AWS provider's documented
[`source_hash` update trigger](https://registry.terraform.io/providers/hashicorp/aws/6.40.0/docs/resources/s3_object).
The actual upgrade plan and S3 update sequence remain pending in the isolated test deployment.

## Pending instance checks

No Terraform command was run. No resource was deployed. Production and its state were not changed.
Terraform syntax evaluation, provider checks, and plans remain pending for later test execution.
No Terragrunt or backend change is included.

AMI boot and RPM installation, Docker builds and services, Fail2ban bans, staging certificate
issuance and renewal, Nginx reload, real database migration, login, sync, attachments,
replacement, and recovery remain pending. Local tests do not establish these results.
Use a new test workspace and unique resource names, URLs, and S3 buckets.
The runbook generates a time-based ID with a random suffix. Check AWS for name conflicts.
Retain the baseline under a separate test backup key before target backups replace the latest key.
See [the test runbook](TEST_INSTANCE_RUNBOOK.md). Test execution does not authorize production changes.
