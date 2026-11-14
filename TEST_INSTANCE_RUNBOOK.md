# Test system updates in a separate Terraform workspace

Use this runbook for AMI updates, OS migrations, and software updates.
It applies to updates within Amazon Linux 2023 and to changes between major OS releases.
It also applies to Terraform, providers, Docker, application images, and setup scripts.

All deployments, replacements, failure tests, and recovery tests use test resources.
Do not apply a plan to production during this procedure.
This document does not deploy resources.
Run command groups in order. Stop if a command or required check fails.

## Implementation status

The upgrade branches start at `main` commit `82bbefb`.
See `UPGRADE_VERIFICATION.md` for local checks and the selected version records.
No Terraform command or deployment was run for this implementation.
The commands in this runbook are instructions for a later test run.

| Required instance check | Status |
|---|---|
| Separate test workspace and resource creation | Pending |
| AMI boot, package installation, and reboot | Pending |
| Image build and Docker services | Pending |
| Fail2ban filters and actual bans | Pending |
| Staging certificate issuance, renewal, and Nginx reload | Pending |
| Vaultwarden login, sync, attachments, and migration | Pending |
| Replacement, baseline restore, and recovery | Pending |

Keep the preserved baseline backup separate from all target-version backups.
Recover with the baseline software and baseline database together.
Do not open a migrated database with an older application version.

| Component | Selected target |
|---|---|
| AMI (us-east-1) | `ami-096ef200a877f36af` |
| Repository | `2023.12.20261112` |
| Kernel | `6.18.62-127.179.amzn2023` |
| AWS CLI RPM | `2.36.47-4.amzn2023.0.1` |
| SQLite RPM | `3.40.0-1.amzn2023.0.9` |
| Docker RPM | `25.0.16-1.amzn2023.0.5` |
| containerd RPM | `2.3.5-1.amzn2023.0.1` |
| Python RPM | `3.14.7-1.amzn2023.0.1` |
| Compose | `v5.7.1` |
| Buildx | `v0.39.0` |
| Fail2ban | `1.1.1` |
| Certbot | `5.10.0` |
| Route 53 plugin | `5.10.0` |
| Vaultwarden image | `1.37.5` |
| Nginx stable image | `1.30.6` |

## 1. Define one test run

Select a new test ID for each independent test run.
Use lowercase letters, numbers, and hyphens. Start the ID with `upgrade-test-`.
Keep the ID short enough for IAM names, S3 bucket names, and a DNS label.
Do not reuse an ID while its resources or state still exist.

Generate a new ID for each test. The table below uses `upgrade-test-001` only as an example:

```bash
export VW_TEST_ID="upgrade-test-$(date -u +%y%m%d%H%M%S)-$(openssl rand -hex 2)"
export VW_TEST_BRANCH="test/$VW_TEST_ID"
export VW_TEST_DIR="$HOME/Projects/vaultwarden-$VW_TEST_ID"
export VW_TEST_DOMAIN="$VW_TEST_ID-warden.psalad.link"
export VW_TEST_ASG="$VW_TEST_ID-vaultwarden"
export AWS_REGION=us-east-1
```

For this example:

| Item | Value |
|---|---|
| Git branch | `test/upgrade-test-001` |
| Git worktree | `~/Projects/vaultwarden-upgrade-test-001` |
| Terraform workspace | `upgrade-test-001` |
| Resource prefix | `upgrade-test-001-` |
| Test URL | `https://upgrade-test-001-warden.psalad.link` |
| Certificate service | Let's Encrypt staging |

Record the test purpose, current versions, target versions, and expected results.
Include every component that will change.

| Component | Record and test |
|---|---|
| AMI and OS | AMI ID, publisher, architecture, OS release, kernel, repository release, boot and reboot |
| Terraform CLI | Exact version, configuration compatibility, plan and state compatibility |
| Terraform providers | Source, version constraints, lock file, schema and resource changes |
| Docker Engine and containerd | Package versions, service startup, networking, storage, image builds |
| Buildx and Compose | Exact versions, checksums, user access, build and service operations |
| Python and Fail2ban | Interpreter, dependencies, source commit, service startup, filters and actual bans |
| Certbot and Route 53 plugin | Versions, DNS challenge, staging issuance, renewal and Nginx reload |
| Nginx | Image tag and digest, configuration syntax, proxy behavior and TLS |
| Vaultwarden and SQLite | Image tag and digest, database migrations, login, sync, attachments, backup and restore |
| AWS CLI and OS utilities | Package versions, metadata access, AWS access, scheduled tasks and logs |
| IAM, networking and setup code | Test resource names, permissions, routes, DNS, startup order and failure behavior |

The approved upgrade permits a Buildx update.
Select explicit target versions for all tools. Update their hashes or digests at the same time.
Use `local.software` and the group version records for the selected versions.
A new OS can require several related components to change together.
Record that dependency instead of assuming every component can change independently.

Use dummy accounts and dummy vault data.
Disable external email, webhooks, or other integrations that could contact production users.
Do not configure the test instance to read or write production backup buckets.

## 2. Create the branch and worktree

Run on the local computer:

```bash
cd ~/Projects/vaultwarden-aws-tf
git status --short
git worktree add -b "$VW_TEST_BRANCH" "$VW_TEST_DIR" main
cd "$VW_TEST_DIR"
export TF_DATA_DIR="$PWD/.terraform"
umask 077
mkdir -p .test-results
cat >> .gitignore <<'IGNORE'

# Local test records and saved plans.
.test-results/
*.tfplan
IGNORE
```

Start from the reviewed commit that represents the current production configuration.
If `main` does not represent production, use the recorded production commit instead.
Keep uncommitted production work in its original worktree.

Do not copy production state, `.terraform`, or variable files into the test worktree.
Use a new local Terraform data directory.
Keep this directory and the test state until all test resources are removed.
If a worktree or branch already exists, inspect it before use.
Do not overwrite an existing test run.

In each later local shell, restore the `VW_TEST_*`, `AWS_REGION`, and `TF_DATA_DIR` variables.
After workspace creation, also set `TF_WORKSPACE` to the test ID.
Review inherited `TF_CLI_ARGS*` and `TF_VAR_*` settings.
Remove settings that select production inputs or a production backend.
Select the intended AWS profile if named profiles are used.

## 3. Select the AMI and check shared resources

```bash
aws sts get-caller-identity
aws ec2 describe-key-pairs --key-names aws-north-virginia \
  --query 'KeyPairs[].{Name:KeyName,Tags:Tags}'
aws route53 list-hosted-zones-by-name --dns-name psalad.link \
  --query "HostedZones[?Name=='psalad.link.']"
```

Confirm the account ID, region, and public hosted zone.
The current key pair lookup requires `Project=warden`.
The configuration selects a public zone. Startup uses its exact hosted zone ID.

The target code is on `upgrade/integration`. Use its reviewed commit for the target stage.
For an application-only update, keep the recorded baseline AMI.
For an AMI update, select an explicit candidate ID in the intended region.
This can be a newer AL2023 image or a different supported OS release.
Check publisher, CPU architecture, kernel, instance compatibility, and support status.
Preview images are suitable for evaluation only unless a separate decision permits their use.

Example AMI discovery for an AL2023 x86_64 update:

```bash
aws ec2 describe-images --owners amazon \
  --filters 'Name=name,Values=al2023-ami-2023*' \
            'Name=architecture,Values=x86_64' \
            'Name=state,Values=available' \
  --query 'sort_by(Images,&CreationDate)[].{ID:ImageId,Name:Name,Date:CreationDate}'
```

Use the target OS publisher's current discovery instructions for another release.
Do not use a changing latest-image lookup during the test.
Record exact AMI and package repository releases for both baseline and target.

Check Route 53 to confirm that `$VW_TEST_DOMAIN` is unused.
Do not check DNS resolution alone; an existing record can point to an unavailable server.
The setup script will replace an existing A record with the same name.
Use a different test ID if another deployment owns the record.

## 4. Create explicit test inputs

Set the following values for the intended test account and target image:

```bash
export VW_TEST_ACCOUNT_ID=REPLACE_WITH_EXPECTED_ACCOUNT_ID
export VW_TEST_AMI=REPLACE_WITH_SELECTED_AMI_ID
export VW_TEST_EMAIL=REPLACE_WITH_YOUR_EMAIL
export VW_TEST_CONFIG_BUCKET="$VW_TEST_ID-vw-$VW_TEST_ACCOUNT_ID-configs-bucket"
export VW_TEST_BACKUP_BUCKET="$VW_TEST_ID-vw-$VW_TEST_ACCOUNT_ID-backups-bucket"
```

Check the account ID against `aws sts get-caller-identity`.
Keep the complete test bucket names below 64 characters.
Bucket names must be globally unique.

Generate `test.tfvars` in the test worktree:

```bash
cat > test.tfvars <<VARS
region                = "us-east-1"
aval_zone             = "us-east-1a"
hosted_zone           = "psalad.link"
domain_name_prefix    = "warden"
resource_prefix       = "$VW_TEST_ID-"
email_for_cert        = "$VW_TEST_EMAIL"
test_cert             = true
s3_bucket_name_prefix = "vw-$VW_TEST_ACCOUNT_ID"
access_key_name       = "aws-north-virginia"
image_id              = "$VW_TEST_AMI"
instance_type         = "t3a.micro"

default_tags = {
  Project            = "vaultwarden"
  ManagedByTerraform = "true"
  Environment        = "$VW_TEST_ID"
}
VARS
```

For another region, change both region and availability zone consistently.
For another CPU architecture, update the instance type, tool downloads, and checksums together.
The current download configuration targets x86_64. An AMI change alone does not add ARM support.

`test.tfvars` is excluded by the repository's `*.tfvars` rule.
Do not add `terraform.tfvars` or automatic variable files to this worktree.
Pass `-var-file=test.tfvars` for every plan.
The workspace name does not set resource names; `resource_prefix` does that.

## 5. Prepare a baseline and target

Use two test stages where applicable:

1. Start with the production software versions on separate test resources. Create dummy data and verify a backup.
2. Apply the selected updates to those test resources. Test a fresh start and restore of the baseline data.

For large changes, add intermediate versions if the publisher requires them.
Test each intermediate step in the test workspace.
Also test the complete required sequence from a fresh baseline.
If a baseline cannot run on the target OS, create it first with its original AMI in the test workspace.
Keep the baseline archive under a separate test S3 key before later backups overwrite the latest key.

Make code changes only on the test branch:

- Update versions and matching checksums, source commits, or image digests in `local.software`.
- Check package names, package manager commands, Python paths, and service settings for the target OS.
- Check `sqlite3`, Certbot, the Route 53 plugin, cron, and AWS CLI availability.
- Check SELinux labels and file permissions without disabling the target security policy to hide a failure.
- Check metadata access, routes, IAM policy readiness, and configuration download order.
- Keep test URLs, test buckets, and `test_cert=true` for every stage.

For Terraform CLI updates, record the exact old and new executables.
For provider updates, change constraints deliberately and review the regenerated lock file.
Use `terraform init -upgrade` only for an intended provider update in this test worktree.
Keep a state copy before tool or provider changes.
Do not assume that older Terraform or provider versions can read state written by newer versions.
Test downgrade or recovery with test state copies in another temporary directory.

Do not copy production state for these tests.
This procedure tests the configuration and test resource transitions.
It does not prove that an upgrade can read every historical production state format.
Record any additional state compatibility assessment required before a future production change.

Commit each selected code version before deploying it.
Do not commit test inputs, plans, state, certificates, or logs.

## 6. Create a new Terraform workspace

These commands assume the repository's current local backend.
If the backend changes, verify its workspace support and separate test state location first.
Workspaces separate state. They do not restrict AWS permissions or external script actions.
See [Terraform workspaces](https://developer.hashicorp.com/terraform/cli/workspaces).

```bash
cd "$VW_TEST_DIR"
unset TF_WORKSPACE
terraform init -lockfile=readonly
terraform workspace new "$VW_TEST_ID"
export TF_WORKSPACE="$VW_TEST_ID"
terraform workspace show
terraform state list
```

A new test must have empty state.
If the workspace already exists, stop and inspect its owner and resources.
For a deliberate continuation of the same run, select its existing workspace.
Do not treat an existing workspace as a new test.

Local state is stored under `terraform.tfstate.d/<test-id>/terraform.tfstate` in this worktree.
Keep protected copies after every apply.
State and saved plans contain the administrator token.

## 7. Validate and inspect each plan

```bash
test "$(git branch --show-current)" = "$VW_TEST_BRANCH"
test "$(terraform workspace show)" = "$VW_TEST_ID"
terraform fmt -check -recursive
terraform validate
bash -n data/init.sh data/scripts/backup.sh data/scripts/maintenance.sh data/scripts/update.sh
terraform plan -var-file=test.tfvars -out=.test-results/change.tfplan
terraform show -no-color .test-results/change.tfplan > .test-results/change-plan.txt
```

Check these requirements before every apply:

- The first deployment creates only new resources. Later changes affect only resources from this test run.
- Resource names use the complete test prefix. Both buckets match the expected test bucket names.
- The domain is `$VW_TEST_DOMAIN`. The certificate command includes `--test-cert`.
- The launch template uses the selected baseline or target AMI.
- For an existing test deployment, changed script files schedule S3 object updates, including the IMDSv2 Spot notifier.
  The notifier upload must precede publication of the new launch template.
  The ASG dependencies must complete the other uploads before a replacement instance starts.
- IAM S3 permissions reference only test buckets. No production backup is restored automatically.
- The plan contains the intended version and provider changes only.

The public hosted zone and EC2 key pair are shared data sources.
Some display tags also match production. Identify resources by IDs and prefixed resource names.
The current test IAM policy can change records throughout the shared hosted zone.
Check the rendered domain because Terraform state cannot restrict what cloud-init writes to DNS.
Do not apply a plan that refers to production resources.

Apply the reviewed plan:

```bash
test "$(terraform workspace show)" = "$VW_TEST_ID"
terraform apply .test-results/change.tfplan
terraform output -raw full-domain-name
terraform state pull > .test-results/state-after-apply.json
```

The domain output must match `$VW_TEST_DOMAIN`.
Give each saved state copy a stage-specific name before the next apply.
Terraform completion does not prove successful server setup.
The setup script reboots the instance when it finishes.

## 8. Check the instance and installed versions

Run locally:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$VW_TEST_ASG" \
  --query 'AutoScalingGroups[0].Instances[].{ID:InstanceId,Health:HealthStatus,State:LifecycleState}'
aws ec2 describe-instances --instance-ids REPLACE_WITH_TEST_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].{IP:PublicIpAddress,AMI:ImageId,State:State.Name}'
ssh -i /path/to/private-key ec2-user@REPLACE_WITH_TEST_PUBLIC_IP
```

Then run on the test server:

```bash
sudo cloud-init status --long
sudo tail -n 100 /var/log/cloud-init-output.log
cat /etc/os-release
uname -r
sudo systemctl --failed
sudo systemctl status docker fail2ban crond --no-pager
docker version
docker buildx version
docker-compose version
python3 --version
python3.14 --version
/opt/fail2ban/bin/python --version
sudo /opt/fail2ban/bin/python /opt/fail2ban/bin/fail2ban-client --version
aws --version
sudo /opt/certbot/bin/certbot --version
sqlite3 --version
docker-compose -f /home/ec2-user/docker-compose.yml ps
```

Check the OS, kernel, package repository release, component versions, and image digests against the test record.
If the OS uses SELinux, inspect `getenforce` and denial logs.
Verify that both containers remain running after the setup reboot.
Run an actual image build as the required user. Version output alone is not sufficient.
Check Fail2ban with a controlled failure and a real ban against test traffic.
Check service names and paths if the target version changes them.

## 9. Test DNS, TLS, and application functions

Run locally:

```bash
dig +short "$VW_TEST_DOMAIN" A
curl --insecure --fail --show-error --silent "https://$VW_TEST_DOMAIN/alive"
openssl s_client -connect "$VW_TEST_DOMAIN:443" \
  -servername "$VW_TEST_DOMAIN" </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
terraform output -raw admin-token
```

The address must match the test instance.
The certificate must include the test domain and a staging issuer.
Keep the administrator token out of shared logs.

Staging certificates are not trusted by normal clients.
Limit `--insecure` to these test requests.
For UI tests, use a separate test browser profile with staging trust configured there only.
HSTS can prevent a simple browser exception.
Never add staging certificate authorities to the normal system or browser trust store.
Record client trust limitations separately from application failures.
See [Let's Encrypt staging certificates](https://letsencrypt.org/docs/staging-environment/).

Use dummy invitations and accounts to test registration, login, sync, attachments, and administrator access.
Check scheduled jobs, logs, disk use, memory, CPU use, and CPU credits.
For major application changes, compare results before and after database migration.

## 10. Test certificate renewal

Set the same test domain variable in the remote shell. Local shell variables are not copied through SSH.
Use the actual test ID selected in section 1:

```bash
export VW_TEST_DOMAIN=REPLACE_WITH_THIS_RUN_TEST_DOMAIN
sudo grep '^server' "/etc/letsencrypt/renewal/$VW_TEST_DOMAIN.conf"
sudo cat /etc/cron.d/renew-certs
sudo /opt/certbot/bin/certbot certificates
```

Check that renewal uses the staging service and that the daily cron includes a reload hook.
Record the certificate serial locally before renewal:

```bash
openssl s_client -connect "$VW_TEST_DOMAIN:443" \
  -servername "$VW_TEST_DOMAIN" </dev/null 2>/dev/null \
  | openssl x509 -noout -serial
```

Run one forced staging renewal on the test server:

```bash
sudo /opt/certbot/bin/certbot renew --cert-name "$VW_TEST_DOMAIN" --test-cert --force-renewal \
  --deploy-hook '/usr/bin/docker-compose -f /home/ec2-user/docker-compose.yml exec -T nginx nginx -s reload'
```

Repeat the serial check locally. It must change, and HTTPS must still work.
Check the hook command if an update changes the Compose command or container name.
A normal renewal check can do nothing when renewal is not due.
See [Certbot renewal hooks](https://eff-certbot.readthedocs.io/en/stable/using.html#renewing-certificates).

## 11. Test backup, restore, replacement, and recovery

On the test server:

```bash
sudo bash /home/ec2-user/scripts/backup.sh
sudo test -w /var/log/vaultwarden-backup.log
```

Check the actual scheduled job as well as manual execution.
Verify the latest and dated archives in the test bucket.
Keep a separate baseline archive before a database migration.
Simulate upload and database backup failures with dummy data and controlled test commands.
Check error status, retained archives where applicable, and the application restart attempt.
Do not change production IAM permissions to simulate failures.

After a target configuration is applied, start a replacement of the test instance locally:

```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$VW_TEST_ASG" \
  --preferences '{"MinHealthyPercentage":0,"MaxHealthyPercentage":100}'
aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$VW_TEST_ASG"
```

An S3 upload or launch template change alone does not update the running server.
This refresh permits test downtime and keeps only one server accepting writes.
Wait for completion and repeat all required checks.
Verify that the new instance restores baseline dummy data using the target software.
Allow for DNS caches during the address change.
Also test an ordinary reboot and a clean installation with no backup.
Use a separate fresh test run for clean installation if the current run must be retained.

Test recovery entirely within test resources.
Use the previous code, AMI, and versions with the preserved baseline test backup.
Do not assume that an older application can read a database changed by a newer version.
Do not overwrite the preserved baseline archive with target-version data.
Terraform state compatibility and application data compatibility are separate checks.

## 12. Record results and finish the review

Record each stage with:

- Git commit, Terraform CLI version, provider lock file, and selected workspace.
- Baseline and target AMIs, OS releases, package releases, versions, hashes, and digests.
- Test resource IDs, domain, and backup keys.
- Expected and actual results, logs, failures, and unresolved limits.
- Fresh installation, baseline-data restore, replacement, reboot, and recovery results.

Keep test state copies protected until removal is complete.
Keep useful results outside the worktree before deleting it.
A successful test does not authorize a production deployment.
Prepare a separate production change proposal if required later.
No production apply, refresh, database migration, or recovery belongs in this runbook.

## 13. Remove only this test run

Run locally from the test worktree with the variables from sections 1 and 4:

```bash
cd "$VW_TEST_DIR"
export TF_DATA_DIR="$PWD/.terraform"
export TF_WORKSPACE="$VW_TEST_ID"
aws sts get-caller-identity
test "$(git branch --show-current)" = "$VW_TEST_BRANCH"
test "$(terraform workspace show)" = "$VW_TEST_ID"
terraform state list
aws s3 ls "s3://$VW_TEST_CONFIG_BUCKET"
aws s3 ls "s3://$VW_TEST_BACKUP_BUCKET"
```

Compare account, resource IDs, and complete bucket names with the test inputs and state.
The current buckets do not enable `force_destroy`.
After checking the names, empty only the two test buckets and inspect a destroy plan:

```bash
aws s3 rm "s3://$VW_TEST_CONFIG_BUCKET" --recursive
aws s3 rm "s3://$VW_TEST_BACKUP_BUCKET" --recursive
terraform plan -destroy -var-file=test.tfvars -out=.test-results/destroy.tfplan
terraform show -no-color .test-results/destroy.tfplan
```

The plan must delete only resources from this test run.
Apply it only after review:

```bash
terraform apply .test-results/destroy.tfplan
terraform state list
```

If the test backup job writes more objects during removal, inspect and empty that test bucket again.
Create and review a new destroy plan.
If versioning was added, remove test object versions and delete markers as well.

Cloud-init creates the A record outside Terraform state.
After the test instance is removed, delete only `$VW_TEST_DOMAIN` type A in Route 53.
Check for a leftover `_acme-challenge` TXT record for that test domain after a failed challenge.
Remove it only when no renewal is running.
Keep the hosted zone, EC2 key pair, production DNS records, and production resources.

When state is empty and test DNS records are removed:

```bash
unset TF_WORKSPACE
terraform workspace select default
terraform workspace delete "$VW_TEST_ID"
```

Delete the test worktree only after resource removal and required record retention.
Keep the test branch until useful code changes have been reviewed.
Do not merge test variables, state, plans, or preview-only settings into production.
