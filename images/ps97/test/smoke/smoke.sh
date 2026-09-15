#!/bin/bash
set -euo pipefail

# Launches a published AMI, verifies first-boot behaviour against the running
# instance, and terminates it. Exits non-zero if any check fails.
#
# Usage: smoke.sh <ami-id> <region> [instance-type]
#
# Required environment:
#   SMOKE_SUBNET_ID           subnet to launch into
#   SMOKE_SECURITY_GROUP_ID   security group allowing SSH from this host
#   SMOKE_KEY_NAME            EC2 key pair name
#   SMOKE_KEY_FILE            matching private key file

usage() {
    echo "usage: smoke.sh <ami-id> <region> [instance-type]" >&2
    exit 2
}

[ "$#" -ge 2 ] || usage

AMI_ID="$1"
REGION="$2"
INSTANCE_TYPE="${3:-t3.medium}"

for tool in aws ssh timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "required tool '${tool}' is not installed" >&2
        exit 2
    }
done

: "${SMOKE_SUBNET_ID:?SMOKE_SUBNET_ID must be set}"
: "${SMOKE_SECURITY_GROUP_ID:?SMOKE_SECURITY_GROUP_ID must be set}"
: "${SMOKE_KEY_NAME:?SMOKE_KEY_NAME must be set}"
: "${SMOKE_KEY_FILE:?SMOKE_KEY_FILE must be set}"

INSTANCE_ID=""
PUBLIC_IP=""
PASSWORD=""
FAILURES=0

cleanup() {
    if [ -n "$INSTANCE_ID" ]; then
        echo "Terminating ${INSTANCE_ID}"
        aws ec2 terminate-instances --region "$REGION" \
            --instance-ids "$INSTANCE_ID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

check() {
    local name="$1"; shift
    if "$@"; then
        echo "ok   - ${name}"
    else
        echo "FAIL - ${name}"
        FAILURES=$(( FAILURES + 1 ))
    fi
}

remote() {
    ssh -i "$SMOKE_KEY_FILE" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
        "ec2-user@${PUBLIC_IP}" "$@"
}

sql() {
    remote "mysql -u root -p'${PASSWORD}' -N -B -e \"$1\""
}

echo "Launching ${AMI_ID} as ${INSTANCE_TYPE} in ${REGION}"
INSTANCE_ID="$(aws ec2 run-instances --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --subnet-id "$SMOKE_SUBNET_ID" \
    --security-group-ids "$SMOKE_SECURITY_GROUP_ID" \
    --key-name "$SMOKE_KEY_NAME" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=iit-billing-tag,Value=ps97-ami},{Key=Name,Value=ps97-smoke}]' \
    --query 'Instances[0].InstanceId' --output text)"

aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
PUBLIC_IP="$(aws ec2 describe-instances --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
echo "Instance ${INSTANCE_ID} at ${PUBLIC_IP}"

echo "Waiting for the credential banner on the console"
elapsed=0
while [ "$elapsed" -lt 600 ]; do
    console="$(aws ec2 get-console-output --region "$REGION" \
        --instance-id "$INSTANCE_ID" --output text 2>/dev/null || true)"
    PASSWORD="$(printf '%s' "$console" \
        | grep -A2 'A unique password was generated' \
        | grep -oE '[A-Za-z0-9]{32}' | head -1 || true)"
    [ -n "$PASSWORD" ] && break
    sleep 15
    elapsed=$(( elapsed + 15 ))
done

if [ -z "$PASSWORD" ]; then
    echo "FAIL - the credential banner never appeared on the console"
    exit 1
fi
echo "ok   - the credential banner appeared on the console"

echo "Waiting for SSH"
elapsed=0
until remote true 2>/dev/null; do
    [ "$elapsed" -ge 300 ] && { echo "FAIL - SSH never became available"; exit 1; }
    sleep 10
    elapsed=$(( elapsed + 10 ))
done

check "the generated password authenticates" \
    bash -c "[ \"\$(sql 'SELECT 1')\" = '1' ]"

check "a write and read round-trip succeeds" bash -c '
    sql "CREATE DATABASE smoke; CREATE TABLE smoke.t (id INT PRIMARY KEY); INSERT INTO smoke.t VALUES (42);" >/dev/null
    [ "$(sql "SELECT id FROM smoke.t")" = "42" ]'

check "the datadir is on the data volume" \
    bash -c "[ \"\$(sql 'SELECT @@datadir')\" = '/data/mysql/' ]"

check "the data volume is a separate mount" \
    bash -c "remote 'findmnt -n -o TARGET /data' | grep -qx /data"

check "a server identity was generated on this instance" \
    bash -c "remote 'sudo test -s /data/mysql/auto.cnf'"

check "innodb_dedicated_server sized the buffer pool above the default" \
    bash -c "[ \"\$(sql 'SELECT @@innodb_buffer_pool_size')\" -gt 134217728 ]"

check "port 3306 is not reachable from outside the instance" \
    bash -c "! timeout 5 bash -c \"</dev/tcp/${PUBLIC_IP}/3306\" 2>/dev/null"

check "xtrabackup completes a backup and prepare" bash -c '
    remote "sudo rm -rf /tmp/xb && sudo mkdir -p /tmp/xb \
      && sudo xtrabackup --backup --target-dir=/tmp/xb --user=root --password='\''"$PASSWORD"'\'' \
      && sudo xtrabackup --prepare --target-dir=/tmp/xb" >/dev/null 2>&1'

echo "Rebooting to confirm the credential survives"
remote "sudo systemctl reboot" >/dev/null 2>&1 || true
sleep 45
elapsed=0
until remote true 2>/dev/null; do
    [ "$elapsed" -ge 300 ] && { echo "FAIL - the instance never came back"; exit 1; }
    sleep 10
    elapsed=$(( elapsed + 10 ))
done

check "the password is unchanged after a reboot" \
    bash -c "[ \"\$(sql 'SELECT 1')\" = '1' ]"

check "mysqld is running after a reboot" \
    bash -c "remote 'systemctl is-active --quiet mysqld.service'"

check "the first-boot marker is present" \
    bash -c "remote 'sudo test -f /data/.ps97-firstboot-done'"

check "the data written before the reboot is still there" \
    bash -c "[ \"\$(sql 'SELECT id FROM smoke.t')\" = '42' ]"

if [ "$FAILURES" -gt 0 ]; then
    echo "${FAILURES} check(s) failed"
    exit 1
fi

echo "All checks passed"
