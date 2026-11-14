# Supporting software upgrade record

Base commit: `82bbefb`. Source check date: 2026-11-14.

`local.software` contains the install versions and source identifiers.

| Component | Selected version | Reason |
|---|---|---|
| Docker | 25.0.16-1.amzn2023.0.5 | Latest supported package in AL2023.12 inventory |
| containerd | 2.3.5-1.amzn2023.0.1 | Package supplied with the selected AL2023 repository |
| Python | 3.14.7-1.amzn2023.0.1 | Latest supported Python series in AL2023.12 |
| Python pip | 26.1.1-1.amzn2023.0.4 | AL2023 package for Python 3.14 |
| Python setuptools | 78.1.1-1.amzn2023.0.2 | AL2023 package for Python 3.14 |
| Compose | v5.7.1 | Latest stable release |
| Buildx | v0.39.0 | Latest stable release |
| Fail2ban | 1.1.1 | Latest stable release; commit f60978618a101427b06924fc932b44350fec2b63 |
| Certbot and Route 53 plugin | 5.10.0 | Matching latest stable releases; require Python 3.10 or later |

The AWS package inventory states full support for Docker and containerd until 2029-06-30. Use these supported packages rather than a Docker repository for a different operating system. The 2026-11-12 release notes have no later change for these packages. Python 3.14 has AWS support until the end of AL2023 support. The system Python remains available for AWS tools.

Compose 5.7.1 source retains Docker Engine API 1.44 (Docker 25). It requires Buildx 0.17 or later; parallel build jobs require 0.38 or later. Buildx 0.39 requires Docker Engine 19.03 or later. Build, service, and API checks on the selected AMI are pending.

Fail2ban 1.1.1 changes the internal iptables action format. The repository jails use the stock `iptables-allports` action and pass `chain=FORWARD`. They have no custom action templates. Fail2ban starts after application log files exist. Its unit and scripts use the same Python environment. No Python library path is fixed in the unit.

Certbot uses a separate Python environment at `/opt/certbot`. Certificate issuance uses the Route 53 plugin directly. Separate environment and plugin checks are part of test verification. Renewal uses the same executable. The deploy hook reloads Nginx only after successful renewal. Certificate paths remain under `/etc/letsencrypt`. Transitive Python dependencies use the versions selected by pip; the selected top-level versions are fixed. A complete dependency lock is not provided.

## Sources

- [AL2023.12 package inventory](https://docs.aws.amazon.com/linux/al2023/release-notes/all-packages-AL2023.12.html)
- [AL2023 2023.12.20261112 release notes](https://docs.aws.amazon.com/linux/al2023/release-notes/relnotes-2023.12.20261112.html)
- [Python in AL2023](https://docs.aws.amazon.com/linux/al2023/ug/python.html)
- [Compose v5.7.1 release](https://github.com/docker/compose/releases/tag/v5.7.1)
- [Compose API and Buildx requirements](https://github.com/docker/compose/blob/v5.7.1/pkg/compose/api_versions.go)
- [Buildx v0.39.0 release](https://github.com/docker/buildx/releases/tag/v0.39.0)
- [Buildx requirements](https://github.com/docker/buildx/blob/v0.39.0/README.md)
- [Fail2ban 1.1.1 release](https://github.com/fail2ban/fail2ban/releases/tag/1.1.1)
- [Fail2ban migration changes](https://github.com/fail2ban/fail2ban/blob/1.1.1/ChangeLog)
- [Certbot 5.10.0](https://pypi.org/project/certbot/5.10.0/)
- [Route 53 plugin 5.10.0](https://pypi.org/project/certbot-dns-route53/5.10.0/)
- [Certbot pip installation](https://certbot.eff.org/instructions?ws=other&os=pip)

## Verification

- `bash -n data/init.sh`: passed.
- `git diff --check`: passed.
- Downloaded Compose and Buildx binary SHA-256 values match the GitHub release API values in `local.software`.
- Downloaded Compose and Buildx version commands: passed.
- Fail2ban tag dereference matches the selected commit.
- Fail2ban build and install under a temporary root with Python 3.14.10 and setuptools 78.1.1: passed. Its 28 selected action and regex tests passed. The unit calls Python directly because the source install retains a `#!python` script header.
- Certbot 5.10.0 and Route 53 plugin installed in a temporary Python 3.14.10 environment. `pip check`, version, and plugin discovery checks passed. The exact AWS Python RPM remains an instance test.
- AMI package installation, Docker builds, Fail2ban service and bans, certificate issuance, renewal, and Nginx reload: pending on a separate test instance.

No Terraform command or deployment was run.
