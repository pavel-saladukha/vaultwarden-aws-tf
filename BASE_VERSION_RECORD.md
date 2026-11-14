# Base system version record

Base commit: `82bbefb`. Selection date: 2026-11-14.

| Component | Selected value |
| --- | --- |
| Region | `us-east-1` |
| AMI ID | `ami-096ef200a877f36af` |
| AMI name | `al2023-ami-2023.12.20261112.0-kernel-6.18-x86_64` |
| AMI creation time | `2026-11-12T13:01:15.000Z` |
| Repository | `2023.12.20261112` |
| Kernel | `6.18.62-127.179.amzn2023` |
| AWS CLI RPM | `awscli-2-2.36.47-4.amzn2023.0.1` |
| SQLite RPM | `sqlite-3.40.0-1.amzn2023.0.9` |
| Git RPM | `git-2.50.1-1.amzn2023.0.2` |
| jq RPM | `jq-1.8.1-60.amzn2023` |
| Cron RPM | `cronie-1.5.7-1.amzn2023.0.2` |

The shared values are in `local.software.base`. Other host packages come from the recorded repository snapshot. The package manager checks RPM signatures. `image_id` and `repository_release` remain explicit override inputs. For another AWS Region, supply a matching AMI ID.

## Source checks

- [2023.12.20261112 release notes](https://docs.aws.amazon.com/linux/al2023/release-notes/relnotes-2023.12.20261112.html): stable AL2023 release, kernel, Git, and SQLite versions.
- [AL2023.12 package list](https://docs.aws.amazon.com/linux/al2023/release-notes/all-packages-AL2023.12.html): AWS CLI, jq, and Cron versions. The full list is dated 2026-10-21. Later release notes list the changed packages.
- [Versioned repositories](https://docs.aws.amazon.com/linux/al2023/ug/deterministic-upgrades.html): fixed repository selection and update procedure.
- Read-only EC2 `describe-images` query with Amazon owner and the exact release name: AMI ID and creation time.

AL2023 has support through 2029-06-30 for these core packages. This change uses a new instance. It does not do an in-place operating system migration.

## Checks

- PASS: Bash syntax checks for the changed scripts.
- PASS: DNS JSON test with dummy data and mocked AWS commands, including AWS failure.
- PASS: Spot notice tests: HTTP 401, 404, and 500 do not stop the application. Only HTTP 200 starts the stop procedure.
- PENDING: Boot the recorded AMI in a new isolated test workspace. Confirm the installed RPM versions, kernel, routes, DNS registration, and service startup.
- PENDING: Confirm Spot notice backup completion on a test instance.

No Terraform command was run. No resource was deployed.
