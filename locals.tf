locals {
  full_domain_name    = format("%s%s.%s", var.resource_prefix, var.domain_name_prefix, var.hosted_zone)
  configs_bucket_name = format("%s%s-configs-bucket", var.resource_prefix, var.s3_bucket_name_prefix)
  backups_bucket_name = format("%s%s-backups-bucket", var.resource_prefix, var.s3_bucket_name_prefix)

  # Update each version and its hash together.
  software = {
    versions = {
      docker_buildx_cli     = "v0.36.0"
      docker_compose_cli    = "v5.1.3"
      fail2ban              = "1.1.0"
      vaultwarden_image_tag = "1.36.0"
      nginx_image_tag       = "1.31.1"
    }

    hashes = {
      # Buildx v0.36.0, linux-amd64 (SHA-256).
      docker_buildx_checksum = "07823fdfcd82a41be90155a8b16876c1a780a6462de805a9f3f63b3119ccfb99"
      # Docker Compose v5.1.3, linux-x86_64 (SHA-256).
      docker_compose_checksum = "a0298760c9772d2c06888fc8703a487c94c3c3b0134adeef830742a2fc7647b4"
      # Fail2Ban 1.1.0 (Git commit ID).
      fail2ban_commit = "61799e15e1dd4389dea0cc7595da0a287835a177"
      # Vaultwarden 1.36.0 and Nginx 1.31.1 (image digests).
      vaultwarden_image_digest = "sha256:d626d04934cd1192ad8ced1adb975099fca78cec33ab467d2d3c923cde7f3b0c"
      nginx_image_digest       = "sha256:608a100c71651bf5b773c89083b4a1ad7ef4b2bd05d7a7e552271e03123692ad"
    }
  }
}
