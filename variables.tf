variable "image_id" {
  type        = string
  default     = null
  description = "Optional AMI ID. The default uses the recorded Amazon Linux 2023 image in us-east-1."
}

variable "instance_type" {
  type    = string
  default = "t3a.micro"
}

variable "cidr" {
  type    = string
  default = "10.0.0.0/28"
}

variable "default_tags" {
  type        = map(any)
  description = "Map of Default Tags"
  default = {
    Project            = "vaultwarden"
    ManagedByTerraform = "true"
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "aval_zone" {
  type    = string
  default = "us-east-1a"
}

variable "domain_name_prefix" {
  type    = string
  default = "warden"
}

variable "hosted_zone" {
  type = string
}

variable "email_for_cert" {
  type = string
}

variable "test_cert" {
  type    = bool
  default = true
}

variable "s3_bucket_name_prefix" {
  type = string
}

variable "access_key_name" {
  type = string
}

variable "resource_prefix" {
  type    = string
  default = ""
}

variable "repository_release" {
  type        = string
  default     = null
  description = "Optional Amazon Linux 2023 repository release. Match it to the selected AMI."
}
