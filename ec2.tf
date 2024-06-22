resource "aws_launch_template" "this" {
  image_id               = var.image_id
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

  user_data = base64encode(
    templatefile("data/init.sh", {
      full_domain_name = local.full_domain_name
      email_for_cert   = var.email_for_cert
      s3_configs       = aws_s3_bucket.config.bucket
      s3_backups       = aws_s3_bucket.backup.bucket
      enable_test_cert = var.test_cert ? "--test-cert" : ""
    })
  )

  description = "Launch template for EC2 instance vaultwarden"

  tags = merge(
    var.default_tags, {
      Name = "${var.resource_prefix}vw-template"
    }
  )
}

resource "aws_autoscaling_group" "this" {
  name                = "${var.resource_prefix}vaultwarden"
  min_size            = 1
  max_size            = 1
  vpc_zone_identifier = [aws_subnet.this.id]
  target_group_arns   = [aws_lb_target_group.this.arn]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tags = local.asg_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "this" {
  name               = "${var.resource_prefix}vw-nlb"
  internal           = false
  load_balancer_type = "network"

  subnets = [aws_subnet.this.id]

  tags = merge(
    var.default_tags, {
      Name = "${var.resource_prefix}vw-nlb"
    }
  )
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = merge(
    var.default_tags, {
      Name = "${var.resource_prefix}vw-nlb-listener"
    }
  )
}

resource "aws_lb_target_group" "this" {
  name     = "${var.resource_prefix}vw-nlb-target-group"
  port     = 443
  protocol = "TCP"
  vpc_id   = aws_vpc.this.id

  tags = merge(
    var.default_tags, {
      Name = "${var.resource_prefix}vw-nlb-target-group"
    }
  )
}
