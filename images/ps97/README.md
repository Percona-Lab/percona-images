# Percona Server for MySQL 9.7 AMI — build guide

Builds AWS AMIs for Percona Server for MySQL 9.7 on Amazon Linux 2023, for
x86_64 and arm64. The design rationale for every decision below lives in
`docs/specs/2026-09-15-ps97-ami-design.md` at the root of this repository;
this document only covers how to run the pipeline.

## Prerequisites

Install on the workstation or CI agent that runs the `Makefile` targets:

- `shellcheck`
- `ansible-lint`
- `bats` (the `bats-core` package or an equivalent on `PATH`)
- `docker`

Then run:

```bash
make deps
```

This downloads the pinned Packer 1.11.2 binary into `~/bin` and runs
`packer init packer/`, which installs the `amazon` and `ansible` plugin
versions declared in `packer/ps97-ami.pkr.hcl`. The `PACKER` variable
(default `~/bin/packer`) and `PACKER_VERSION` variable can be overridden if a
different location or version is required.

Building and verifying an image (`make validate`, `make build`,
`test/smoke/smoke.sh`) additionally requires AWS credentials. The default
build subnet and security group are the shared Percona build network
declared in `packer/variables.pkr.hcl`; override them with `-var` or
`-var-file` to build in a different account.

## Local checks that need no AWS

These run entirely on the local workstation or CI agent, without AWS
credentials or a launched instance:

```bash
make lint       # shellcheck, packer fmt -check, ansible-lint
make unit       # bats test/unit/ — offline tests for the first-boot script
make container  # applies the playbook inside a systemd-enabled Amazon
                # Linux 2023 container, with the storage role in directory
                # mode since the container has no second disk
```

`make lint` and `make unit` run in well under a minute. `make container`
pulls and prepares a base image on first run and is slower; subsequent runs
reuse the prepared image.

## Building

Validate the template against both source blocks:

```bash
make validate
```

Build both architectures:

```bash
make build
```

Both targets pass `-var-file=packer/release.pkvars.hcl`, which sets the
requested Percona Server version and repository channel and the AMI region
list. Override any of those with additional `-var` or `-var-file` arguments.

To build a single architecture — for example while iterating on a role
change — pass `-only` with the build name and source name:

```bash
~/bin/packer build -only='ps97.amazon-ebs.ps97_x86_64' \
  -var-file=packer/release.pkvars.hcl packer/
```

Substitute `ps97.amazon-ebs.ps97_arm64` for the arm64 source.

A build provisions a throwaway EC2 instance, runs the Ansible roles against
it via `ansible-local`, runs the in-image bats suites, and only then creates
the AMI. A bats failure stops the build before any AMI is created; a
provisioning error terminates the instance without creating one either.

## Verifying a built image

`test/smoke/smoke.sh` launches an instance of a built AMI, exercises it, and
terminates it on exit regardless of outcome:

```bash
test/smoke/smoke.sh <ami-id> <region> [instance-type]
```

`instance-type` defaults to `t3.medium` if omitted. Four environment
variables are required:

| Variable | Purpose |
|---|---|
| `SMOKE_SUBNET_ID` | Subnet to launch the test instance into |
| `SMOKE_SECURITY_GROUP_ID` | Security group allowing SSH from the host running the script |
| `SMOKE_KEY_NAME` | EC2 key pair name to launch with |
| `SMOKE_KEY_FILE` | Path to the matching private key file |

The script requires the `aws`, `ssh`, and `timeout` commands. It waits for
the credential banner to appear in the console log, connects over SSH,
authenticates with the recovered password, exercises a write/read
round-trip, confirms the datadir and buffer pool sizing, confirms port 3306
is not reachable from outside the instance, runs an `xtrabackup` backup and
prepare cycle, reboots the instance, and confirms the password and data
survive the reboot. Any failed check is reported and the script exits
non-zero; the launched instance is terminated either way.

## What happens on first boot

`ps97-firstboot.service` runs once, before `mysqld.service` starts, on an
instance whose data volume has not already been initialized:

- A 32-character alphanumeric password is generated for this instance only.
  It is never baked into the AMI and is not shared between instances.
- The password is written to `/dev/console`, which appears in the EC2
  system log (`aws ec2 get-console-output`) and is retrievable without SSH
  access, and to `/etc/motd.d/30-ps97`, which is shown at login.
- MySQL listens on `127.0.0.1` only (`bind-address` in
  `/etc/my.cnf.d/99-percona-ami.cnf`). Nothing is reachable off-instance in
  the default configuration; security groups plus this setting are the
  boundary, since the image ships no host firewall.
- The datadir is `/data/mysql`, on the data volume mounted by
  `LABEL=PS97DATA` rather than the OS volume, so its lifecycle is
  independent of the root volume.

Rerunning first boot is a no-op once its marker file
(`/data/.ps97-firstboot-done`) exists or the datadir is already populated,
so a reboot does not regenerate the password. A data volume detached from
one instance and attached to a fresh one is treated as unpopulated and gets
its own password on that instance's first boot.
