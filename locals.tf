locals {
  full_domain_name    = format("%s%s.%s", var.resource_prefix, var.domain_name_prefix, var.hosted_zone)
  configs_bucket_name = format("%s%s-configs-bucket", var.resource_prefix, var.s3_bucket_name_prefix)
  backups_bucket_name = format("%s%s-backups-bucket", var.resource_prefix, var.s3_bucket_name_prefix)

  # Update each version and its hash together.
  software = {
    base = {
      ami_id             = "ami-096ef200a877f36af"
      ami_name           = "al2023-ami-2023.12.20261112.0-kernel-6.18-x86_64"
      ami_region         = "us-east-1"
      repository_release = "2023.12.20261112"
      kernel             = "6.18.62-127.179.amzn2023"
      awscli             = "2.36.47-4.amzn2023.0.1"
      sqlite             = "3.40.0-1.amzn2023.0.9"
    }
    versions = {
      docker_rpm            = "25.0.16-1.amzn2023.0.5"
      containerd_rpm        = "2.3.5-1.amzn2023.0.1"
      python_rpm            = "3.14.7-1.amzn2023.0.1"
      python_pip_rpm        = "26.1.1-1.amzn2023.0.4"
      python_setuptools_rpm = "78.1.1-1.amzn2023.0.2"
      certbot               = "5.10.0"
      certbot_dns_route53   = "5.10.0"
      docker_buildx_cli     = "v0.39.0"
      docker_compose_cli    = "v5.7.1"
      fail2ban              = "1.1.1"
      vaultwarden_image_tag = "1.37.5"
      nginx_image_tag       = "1.30.6"
    }

    hashes = {
      # Buildx v0.39.0, linux-amd64 (SHA-256).
      docker_buildx_checksum = "5fb31a097304fbf6dd4038649a0decf32c2b9510e4047acd7d68b9d700c46194"
      # Docker Compose v5.7.1, linux-x86_64 (SHA-256).
      docker_compose_checksum = "af426722a8af5de812fcee30cc1c39f0639f5f723cbadefb25e5d4db054064cf"
      # Fail2Ban 1.1.1 (Git commit ID).
      fail2ban_commit = "f60978618a101427b06924fc932b44350fec2b63"
      # Vaultwarden 1.37.5 and Nginx 1.30.6 (image digests).
      vaultwarden_image_digest = "sha256:4fe17f415f90087377d37c755e0ea3cf189dcc6794e49cdd2a9adbb4937d9e1f"
      nginx_image_digest       = "sha256:42c68eab6f7e22611786a9fe1d1c019e275c50185bd54b8f75dc2b9184322703"
    }
  }
}
