#!/bin/bash
set -euo pipefail

# Terminates build and smoke-test instances left behind by an interrupted run.
#
# Packer cleans up after its own errors, but not when the machine running it
# disappears, which happens when a spot build agent is reclaimed mid-build.
#
# Instances are matched on the billing tag alone, which is unique to this job.
# Key pairs are deleted only if a matched instance was using them: the packer_*
# name pattern is shared with the other Percona image jobs, so matching on the
# name would risk deleting a key pair belonging to a concurrent build.
#
# Usage: cleanup-orphans.sh [region] [billing-tag] [max-age-minutes]

REGION="${1:-us-east-1}"
BILLING_TAG="${2:-ps97-ami}"

# An orphan is an instance whose build agent vanished. A live build's
# instances are minutes old, so an age floor is what separates the two.
# Without it this script would terminate a healthy concurrent build.
MAX_AGE_MINUTES="${3:-180}"

if ! command -v aws >/dev/null 2>&1; then
    echo "aws CLI is not available, skipping orphan cleanup"
    exit 0
fi

echo "Looking for orphaned instances tagged iit-billing-tag=${BILLING_TAG} in ${REGION}, older than ${MAX_AGE_MINUTES} minutes"

CUTOFF="$(date -u -d "-${MAX_AGE_MINUTES} minutes" +%Y-%m-%dT%H:%M:%S)"

echo "Ignoring instances launched after ${CUTOFF}Z"

instances="$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:iit-billing-tag,Values=${BILLING_TAG}" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[?LaunchTime<='${CUTOFF}'].[InstanceId,KeyName,Tags[?Key=='Name']|[0].Value]" \
    --output text 2>/dev/null || true)"

if [ -z "$instances" ]; then
    echo "No orphaned instances found"
    exit 0
fi

echo "Found:"
echo "$instances"

instance_ids=""
key_names=""
while read -r instance_id key_name name; do
    [ -n "$instance_id" ] || continue
    instance_ids="${instance_ids} ${instance_id}"
    case "$key_name" in
        packer_*) key_names="${key_names} ${key_name}" ;;
    esac
    echo "Terminating ${instance_id} (${name:-unnamed}, key ${key_name:-none})"
done <<< "$instances"

if [ -n "$instance_ids" ]; then
    # shellcheck disable=SC2086
    aws ec2 terminate-instances --region "$REGION" --instance-ids $instance_ids >/dev/null
    echo "Termination requested"
fi

for key_name in $key_names; do
    echo "Deleting temporary key pair ${key_name}"
    aws ec2 delete-key-pair --region "$REGION" --key-name "$key_name" >/dev/null 2>&1 || true
done

echo "Orphan cleanup complete"
