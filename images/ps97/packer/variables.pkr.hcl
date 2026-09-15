variable "ps97_version" {
  type    = string
  default = "9.7.1"
}

variable "repo_channel" {
  type    = string
  default = "release"

  validation {
    condition     = contains(["release", "testing", "experimental"], var.repo_channel)
    error_message = "The repo_channel must be release, testing, or experimental."
  }
}

variable "build_region" {
  type    = string
  default = "us-east-1"
}

variable "ami_regions" {
  type    = list(string)
  default = []
}

# Build network shared with the other Percona AMI builds in this repository. The
# VPC is derived from the subnet, matching how those builds are configured.
# Override both with -var or -var-file to build in a different account.
variable "subnet_id" {
  type    = string
  default = "subnet-ee06e8e1"
}

variable "security_group_id" {
  type    = string
  default = "sg-688c2b1c"
}

variable "root_volume_size" {
  type    = number
  default = 30
}

variable "data_volume_size" {
  type    = number
  default = 50
}

variable "instance_type_x86_64" {
  type    = string
  default = "t3.medium"
}

variable "instance_type_arm64" {
  type    = string
  default = "t4g.medium"
}

variable "bats_version" {
  type    = string
  default = "1.11.0"
}

# Cost allocation tag used across Percona image builds.
variable "billing_tag" {
  type    = string
  default = "ps97-ami"
}
