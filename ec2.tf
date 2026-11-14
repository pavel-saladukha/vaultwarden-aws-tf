resource "aws_launch_template" "this" {
  # Existing ASGs use $Latest. Upload the IMDSv2 notifier before publishing it.
  depends_on = [aws_s3_object.notifier]

  image_id               = coalesce(var.image_id, local.software.base.ami_id)
  instance_type          = var.instance_type
  key_name               = data.aws_key_pair.this.key_name
  name                   = "${var.resource_prefix}vaultwarden"
  update_default_version = true

  credit_specification {
    cpu_credits = "standard"
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }

  placement {
    availability_zone = var.aval_zone
  }

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    subnet_id                   = aws_subnet.this.id
    security_groups = [
      aws_security_group.public_ssh.id,
      aws_security_group.public_https.id,
      aws_security_group.public_http.id,
      aws_security_group.vpc_traffic.id
    ]
  }

  metadata_options {
    http_endpoint      = "enabled"
    http_tokens        = "required"
    http_protocol_ipv6 = "enabled"
  }

  user_data = base64encode(
    templatefile("data/init.sh", {
      full_domain_name        = local.full_domain_name
      email_for_cert          = var.email_for_cert
      s3_configs              = aws_s3_bucket.config.bucket
      s3_backups              = aws_s3_bucket.backup.bucket
      enable_test_cert        = var.test_cert ? "--test-cert" : ""
      hosted_zone_id          = data.aws_route53_zone.this.zone_id
      aws_region              = var.region
      repository_release      = coalesce(var.repository_release, local.software.base.repository_release)
      awscli_version          = local.software.base.awscli
      sqlite_version          = local.software.base.sqlite
      docker_buildx_version   = local.software.versions.docker_buildx_cli
      docker_buildx_checksum  = local.software.hashes.docker_buildx_checksum
      docker_compose_version  = local.software.versions.docker_compose_cli
      docker_compose_checksum = local.software.hashes.docker_compose_checksum
      docker_rpm              = local.software.versions.docker_rpm
      containerd_rpm          = local.software.versions.containerd_rpm
      python_rpm              = local.software.versions.python_rpm
      python_pip_rpm          = local.software.versions.python_pip_rpm
      python_setuptools_rpm   = local.software.versions.python_setuptools_rpm
      certbot_version         = local.software.versions.certbot
      certbot_route53_version = local.software.versions.certbot_dns_route53
      fail2ban_commit         = local.software.hashes.fail2ban_commit
    })
  )

  lifecycle {
    precondition {
      condition     = var.image_id != null || var.region == local.software.base.ami_region
      error_message = "Supply image_id for Regions other than the recorded AMI Region."
    }
  }

  description = "Launch template for EC2 instance vaultwarden"

  tags = merge(
    var.default_tags, {
      Name = "${var.resource_prefix}vw-template"
    }
  )
}

resource "aws_autoscaling_group" "this" {
  # Complete startup prerequisites before the first instance can launch.
  depends_on = [
    aws_iam_role_policy_attachment.ec2_route53_dns,
    aws_iam_role_policy_attachment.ec2_s3,
    aws_default_route_table.this,
    aws_s3_object.backup_script,
    aws_s3_object.restore_script,
    aws_s3_object.notifier,
    aws_s3_object.maint-script,
    aws_s3_object.docker_compose,
    aws_s3_object.nginx_dockerfile,
    aws_s3_object.nginx_conf,
    aws_s3_object.update_script,
    aws_s3_object.warden_jail,
    aws_s3_object.warden_filter,
    aws_s3_object.warden_admin_jail,
    aws_s3_object.warden_admin_filter,
    aws_s3_object.nginx_bot_jail,
    aws_s3_object.nginx_http_auth_jail,
    aws_s3_object.nginx_301_jail,
    aws_s3_object.nginx_301_filter,
    aws_s3_object.nginx_400_jail,
    aws_s3_object.nginx_400_filter,
    aws_s3_object.nginx_404_jail,
    aws_s3_object.nginx_404_filter,
  ]

  name                = "${var.resource_prefix}vaultwarden"
  min_size            = 1
  max_size            = 1
  vpc_zone_identifier = [aws_subnet.this.id]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = var.default_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  tag {
    key                 = "Name"
    value               = "vw-asg"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
