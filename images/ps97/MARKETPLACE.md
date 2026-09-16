# AWS Marketplace submission

Everything needed to submit the Percona Server for MySQL 9.7 AMIs to AWS
Marketplace, plus the listing content itself. Sections marked **per release**
are refreshed for each version; the rest is stable. No build has been run
yet, so every per-release table below is a placeholder to be filled in at
submission time, not a record of a completed build.

## Product identity

**Title:** Percona Server for MySQL 9.7

**Short description (fewer than 200 characters):**

> Percona Server for MySQL 9.7 is a free, fully compatible, enhanced drop-in
> replacement for MySQL Community Edition, built and tested by Percona for
> Amazon Linux 2023.

**Long description:**

> Percona Server for MySQL 9.7 packages the MySQL-compatible database server
> for production use on Amazon Linux 2023, built and tested by Percona from
> the same sources as the Percona Server DEB and RPM packages.
>
> The image includes the server, the client tools, and Percona XtraBackup for
> hot physical backups. Percona Toolkit is not included: it has no Amazon
> Linux 2023 build in Percona's repositories, so it is omitted rather than
> substituted with something else.
>
> Each instance generates a unique root password on first boot, prints it to
> the instance console log and to the message of the day, and listens on
> localhost only until you choose to expose it. The data directory lives on
> its own EBS volume, separate from the operating system volume, and
> `innodb_dedicated_server` sizes the buffer pool and redo log from the
> instance's detected memory automatically.
>
> Percona Server for MySQL is free. Percona offers optional commercial
> support, services and consulting.

## Published AMIs — per release

No build has been run. Populate this table at submission time:

```bash
aws ec2 describe-images --owners self --region us-east-1 \
  --filters "Name=name,Values=percona-server-mysql-${VERSION}-*" \
  --query 'sort_by(Images,&CreationDate)[].[Name,ImageId,Architecture,CreationDate]' \
  --output table
```

| Architecture | AMI name | AMI id |
|---|---|---|
| x86_64 | *to be filled at submission* | *to be filled at submission* |
| arm64 | *to be filled at submission* | *to be filled at submission* |

Region coverage is listed in `packer/release.pkvars.hcl`.

## Component versions — per release

| Component | Version |
|---|---|
| Percona Server for MySQL | *to be filled at submission — see Open decisions* |
| Percona XtraBackup (`percona-xtrabackup-97`) | *to be filled at submission — see Open decisions* |
| Base OS | Amazon Linux 2023 |

Percona Toolkit is not part of the image; see Product identity above.

Confirm the installed versions against the built image rather than this
table:

```bash
rpm -q percona-server-server percona-server-client percona-xtrabackup-97
```

## Instance type guidance

`innodb_dedicated_server=ON` derives the buffer pool, redo log capacity, and
flush method from the instance's detected memory at every start, so a larger
instance type gets a proportionally larger buffer pool without any
configuration change.

| Minimum | Recommended families |
|---|---|
| 2 GB memory | `m7i` / `m7g` for mixed workloads, `r7i` / `r7g` for larger, memory-bound datasets |

Graviton (`m7g`, `r7g`) is a straightforward choice: the arm64 image is built
from the same sources and package versions as the x86_64 image.

The build and smoke-test pipeline currently uses `t3.medium` and `t4g.medium`
for validation; these are convenient for functional testing, not a
production sizing recommendation.

## Security group guidance

The image listens on **localhost only** (`bind-address = 127.0.0.1`) until
reconfigured, so a permissive security group alone does not expose MySQL.
Both the security group and the configuration file must be changed to accept
remote connections.

| Port | Purpose | Recommended source |
|---|---|---|
| 22 | SSH administration | Administrator CIDR only |
| 3306 | MySQL | Application CIDR or security group only. Never `0.0.0.0/0` |

There is no host firewall on the image; security groups are the only network
boundary.

## Usage instructions

### Retrieving the generated password

Each instance generates its own 32-character root password on first boot.
It is not baked into the AMI and is not shared between instances.

Without logging in, from the instance system log:

```bash
aws ec2 get-console-output --region <region> --instance-id <instance-id> \
  --output text | grep -A6 'unique password was generated'
```

Or over SSH, where the same banner is shown automatically at login, and can
also be read directly:

```bash
ssh ec2-user@<address> "sudo cat /etc/motd.d/30-ps97"
```

### Connecting

```bash
mysql -u root -p
```

Enter the recovered password when prompted.

### Changing the password

```bash
mysql -u root -p -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '<new-password>';"
```

### Accepting remote connections

`root@localhost` cannot authenticate from a remote host regardless of what
`bind-address` is set to, so remote access needs a dedicated account in
addition to the network changes:

```bash
mysql -u root -p -e "
  CREATE USER 'admin'@'%' IDENTIFIED BY '<password>';
  GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;
"
sudo sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' \
  /etc/my.cnf.d/99-percona-ami.cnf
sudo systemctl restart mysqld.service
```

Then open port 3306 in the security group to the sources that need it.
Restrict `'admin'@'%'` to a specific host or CIDR-derived pattern rather than
`%` where the client population allows it. Do not do this without a strong
password set and the security group restricted.

### Configuration layout

| Path | Purpose |
|---|---|
| `/etc/my.cnf.d/99-percona-ami.cnf` | Baseline configuration for this image. Edit here. |
| `/etc/my.cnf` | Packaged defaults, left unmodified. A package upgrade can rewrite it, so the baseline is not placed here. |
| `/data/mysql` | Datadir, on the data volume |
| `/var/log/mysqld.log` | Error log |
| `/etc/motd.d/30-ps97` | First-boot credential banner, shown at login |
| `/etc/systemd/system/mysqld.service.d/10-limits.conf` | Raises `LimitNOFILE` to 65535 |
| `/etc/sysctl.d/99-ps97.conf` | `vm.swappiness=1`, `net.core.somaxconn=1024` |

The service is `mysqld.service`. `systemctl status mysqld.service` reports
its state. `ps97-firstboot.service` runs once, ordered before `mysqld.service`,
and is a no-op on every subsequent boot once its marker file exists.

`/etc/my.cnf.d/99-percona-ami.cnf` sorts after the packaged configuration and
wins on any setting it repeats, so a package upgrade cannot silently revert
the baseline.

## Security posture

Every item below is asserted by the bats suite that runs inside the build,
before the snapshot is taken. A failure blocks image creation.

| Requirement | How it is met |
|---|---|
| No default or shared credentials | Password generated per instance on first boot; datadir ships empty |
| No baked server identity | No `auto.cnf` and no system tables present in the shipped datadir |
| No baked SSH keys | No `authorized_keys` for any account |
| Unique host identity | SSH host keys removed at build, regenerated on first boot |
| No OS account passwords | Every account locked or password-less in `/etc/shadow` |
| Root SSH login disabled | `PermitRootLogin no` |
| No stored MySQL credentials | No `/root/.my.cnf` or `/home/ec2-user/.my.cnf` |
| No build artifacts | Package cache, provisioning logs, shell history, and machine id cleared |
| No build tooling shipped | Ansible removed before the snapshot |
| Not exposed by default | `bind-address = 127.0.0.1`; no host firewall, security groups are the boundary |

Access is via the `ec2-user` account using the key pair chosen at launch.

## Encryption

The published AMIs are **unencrypted** on both the root volume (30 GB gp3)
and the data volume (50 GB gp3), because AWS Marketplace does not accept
encrypted AMI products. Both volumes are also set to delete on termination.
Enable EBS encryption at launch, or copy the AMI with encryption into your
own account, if encryption at rest is required.

## Self-service scan — per release

No scan has been run; no build has been produced yet. Once a build exists,
share each AMI with the AWS Marketplace scanning account and run a scan from
the Marketplace Management Portal before submitting.

| Architecture | Scan date | Result |
|---|---|---|
| x86_64 | *to be filled at submission* | *to be filled at submission* |
| arm64 | *to be filled at submission* | *to be filled at submission* |

To re-verify the hardening assertions directly against a published image,
launch it and run the suite from the repository:

```bash
scp -i <key> -r images/ps97/test/bats ec2-user@<address>:/tmp/
ssh -i <key> ec2-user@<address> "sudo bats /tmp/bats/hardening.bats"
```

Run only `hardening.bats`. The other suites assert bake-time state: on a
booted instance the first-boot marker exists and the datadir is populated,
so `config.bats` and `storage.bats` report failures that are correct
behaviour for a running instance.

## Open decisions

These need resolving before a Marketplace candidate can be built and
submitted.

1. **Version and channel for the first published build.** At the time of
   writing, the `release` channel carries `percona-server-server` at
   `9.7.1-1.1` but `percona-xtrabackup-97` at `9.7.1-1.rc1`. The install role
   deliberately fails the build rather than produce a `release`-channel image
   that contains a release candidate. The `testing` channel currently carries
   `percona-server-server` `9.7.2-2.1` instead. There is therefore no channel
   today that yields a coherent, GA "9.7.1" image; the version and channel to
   publish is an open decision, not a settled fact, and needs revisiting
   against the state of both repositories at build time rather than assumed
   from this document.
2. **Listing structure.** Confirm whether the seller portal expresses
   x86_64 and arm64 as multiple delivery options within one product or as
   separate listings.
3. **Support and EULA.** The listing is free. Confirm which end user licence
   agreement applies and how optional Percona support is referenced.
4. **Region list.** `packer/release.pkvars.hcl` holds the current set.
   Confirm it matches the coverage the listing advertises.

## Licensing

Percona Server for MySQL is released under the GNU General Public License,
version 2. Percona XtraBackup is released under the GNU General Public
License, version 2. Amazon Linux 2023 is distributed under its own terms.
