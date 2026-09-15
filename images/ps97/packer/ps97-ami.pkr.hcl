packer {
  required_version = ">= 1.8.0"

  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

locals {
  build_date = formatdate("YYYYMMDD-hhmm", timestamp())

  common_tags = {
    Product           = "Percona Server for MySQL"
    ServerVersion     = var.ps97_version
    RepoChannel       = var.repo_channel
    BuildDate         = local.build_date
    "iit-billing-tag" = var.billing_tag
  }

  billing_run_tags = {
    "iit-billing-tag" = var.billing_tag
  }
}

source "amazon-ebs" "ps97_x86_64" {
  region                      = var.build_region
  instance_type               = var.instance_type_x86_64
  ssh_username                = "ec2-user"
  ssh_clear_authorized_keys   = true
  ami_name                    = "percona-server-mysql-${var.ps97_version}-x86_64-${local.build_date}"
  ami_description             = "Percona Server for MySQL ${var.ps97_version} on Amazon Linux 2023"
  ami_regions                 = var.ami_regions
  encrypt_boot                = false
  subnet_id                   = var.subnet_id
  security_group_id           = var.security_group_id
  associate_public_ip_address = true

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-kernel-6.1-x86_64"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  launch_block_device_mappings {
    device_name = "/dev/sdb"
    volume_size = var.data_volume_size
    volume_type = "gp3"
    # The Percona Server 8.0 template leaves this false, which orphans an EBS
    # volume every time an instance from that image is terminated.
    delete_on_termination = true
  }

  tags            = merge(local.common_tags, { Architecture = "x86_64" })
  run_tags        = merge(local.billing_run_tags, { Name = "packer-ps97-x86_64" })
  run_volume_tags = local.billing_run_tags
  snapshot_tags   = merge(local.common_tags, { Architecture = "x86_64" })
}

source "amazon-ebs" "ps97_arm64" {
  region                      = var.build_region
  instance_type               = var.instance_type_arm64
  ssh_username                = "ec2-user"
  ssh_clear_authorized_keys   = true
  ami_name                    = "percona-server-mysql-${var.ps97_version}-arm64-${local.build_date}"
  ami_description             = "Percona Server for MySQL ${var.ps97_version} on Amazon Linux 2023"
  ami_regions                 = var.ami_regions
  encrypt_boot                = false
  subnet_id                   = var.subnet_id
  security_group_id           = var.security_group_id
  associate_public_ip_address = true

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-kernel-6.1-arm64"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/sdb"
    volume_size           = var.data_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags            = merge(local.common_tags, { Architecture = "arm64" })
  run_tags        = merge(local.billing_run_tags, { Name = "packer-ps97-arm64" })
  run_volume_tags = local.billing_run_tags
  snapshot_tags   = merge(local.common_tags, { Architecture = "arm64" })
}

build {
  name    = "ps97"
  sources = ["source.amazon-ebs.ps97_x86_64", "source.amazon-ebs.ps97_arm64"]

  provisioner "shell" {
    inline = [
      "sudo dnf -y install ansible-core tar gzip xfsprogs",
      # The roles use modules from these collections; ansible-core bundles
      # neither, and ansible-local runs whatever is on the build instance.
      "sudo ansible-galaxy collection install community.general ansible.posix",
      # Amazon Linux 2023 ships no bats package. Install the pinned upstream
      # release under /opt so the whole tree can be removed before the snapshot.
      "curl -fsSL https://github.com/bats-core/bats-core/archive/refs/tags/v${var.bats_version}.tar.gz -o /tmp/bats.tar.gz",
      "tar -xzf /tmp/bats.tar.gz -C /tmp",
      "sudo /tmp/bats-core-${var.bats_version}/install.sh /opt/bats",
      "rm -rf /tmp/bats.tar.gz /tmp/bats-core-${var.bats_version}",
    ]
  }

  provisioner "ansible-local" {
    playbook_file = "${path.root}/../ansible/ps97-ami.yml"
    playbook_dir  = "${path.root}/../ansible"
    extra_arguments = [
      "-e", "ps97_version=${var.ps97_version}",
      "-e", "ps97_repo_channel=${var.repo_channel}",
    ]
  }

  provisioner "file" {
    source      = "${path.root}/../test/bats"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      # Build tooling is removed before the suites run, because one of the
      # hardening assertions is that it is gone.
      "sudo dnf -y remove ansible-core",
      "sudo dnf clean all",
      "sudo PS97_VERSION=${var.ps97_version} PS97_REPO_CHANNEL=${var.repo_channel} /opt/bats/bin/bats /tmp/bats/*.bats",
      "rm -rf /tmp/bats",
      "sudo rm -rf /opt/bats",
      "sudo rm -rf /var/log/dnf.* /root/.ansible /home/ec2-user/.ansible",
    ]
  }
}
