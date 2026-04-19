locals {
  full_domain_name    = format("%s%s.%s", var.resource_prefix, var.domain_name_prefix, var.hosted_zone)
  configs_bucket_name = format("%s%s-configs-bucket", var.resource_prefix, var.s3_bucket_name_prefix)
  backups_bucket_name = format("%s%s-backups-bucket", var.resource_prefix, var.s3_bucket_name_prefix)

  # Pin versions for EC2 bootstrap (init.sh) and templated artifacts (docker-compose.yml).
  software_versions = {
    docker_compose_cli    = "v5.1.3"
    fail2ban_git_ref      = "1.1.0"
    vaultwarden_image_tag = "1.32.7"
  }
}
