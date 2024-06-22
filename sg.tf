resource "aws_security_group" "public_ssh" {

  name        = "${var.resource_prefix}ssh"
  description = "Allow ssh connectivity to host"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Public SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.default_tags, {
      Name = "public-ssh"
    }
  )
}

resource "aws_security_group" "public_https" {

  name        = "${var.resource_prefix}https"
  description = "Allow https connectivity to host"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Public HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.default_tags, {
      Name = "${var.resource_prefix}public-https",
    }
  )
}

resource "aws_security_group" "public_http" {

  name        = "${var.resource_prefix}http"
  description = "Allow http connectivity to host"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Public HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.default_tags, {
      Name = "${var.resource_prefix}public-http",
    }
  )
}

resource "aws_security_group" "vpc_traffic" {
  name        = "${var.resource_prefix}vpc-traffic"
  description = "Allow all VPC traffic"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    cidr_blocks = [
    var.cidr]
  }
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "udp"
    cidr_blocks = [
    var.cidr]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
    "0.0.0.0/0"]
  }

  tags = merge(
    var.default_tags, {
      Name = "${var.resource_prefix}private-vpc-traffic",
    }
  )
}