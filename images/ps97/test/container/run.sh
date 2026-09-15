#!/bin/bash
set -euo pipefail

# Applies the image playbook inside a systemd-enabled Amazon Linux 2023
# container. systemd is required because the roles enable units; without a
# running service manager those tasks would be skipped rather than verified.
#
# The container has no second disk, so the storage role runs in directory mode.
#
# Usage: run.sh
#   KEEP=1  leave the container running for inspection

IMAGE="${CONTAINER_IMAGE:-amazonlinux:2023}"
CHANNEL="${PS97_REPO_CHANNEL:-release}"
VERSION="${PS97_VERSION:-9.7.1}"
KEEP="${KEEP:-0}"

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTAINER="ps97-image-$$"
PREPARED_TAG="${PREPARED_TAG:-ps97-image-base:al2023}"

cleanup() {
    if [ "$KEEP" = "1" ]; then
        echo "Container left running: $CONTAINER"
        return
    fi
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

prepare_image() {
    # amazonlinux:2023 ships neither systemd nor /sbin/init, so the container
    # cannot be started with init until those are installed. Installing them
    # into a throwaway container and committing the result is the only order
    # that works: exec-ing into a container whose entrypoint already failed
    # would target a dead container.
    if docker image inspect "$PREPARED_TAG" >/dev/null 2>&1; then
        echo "$PREPARED_TAG"
        return
    fi

    local tmp="ps97-image-prep-$$"
    if ! docker run --name "$tmp" "$IMAGE" bash -c "
            set -euo pipefail
            dnf -y install systemd ansible-core findutils procps-ng \
                shadow-utils tar gzip policycoreutils >/dev/null
            ansible-galaxy collection install community.general ansible.posix >/dev/null
        " >&2; then
        docker rm -f "$tmp" >/dev/null 2>&1 || true
        echo "failed to prepare the base image" >&2
        exit 1
    fi
    docker commit "$tmp" "$PREPARED_TAG" >/dev/null
    docker rm -f "$tmp" >/dev/null 2>&1 || true
    echo "$PREPARED_TAG"
}

BASE="$(prepare_image)"

docker run -d \
    --privileged \
    --cgroupns=host \
    --name "$CONTAINER" \
    --tmpfs /run \
    --tmpfs /run/lock \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    -v "$WORKDIR":/images:ro \
    "$BASE" /sbin/init >/dev/null

elapsed=0
while [ "$elapsed" -lt 60 ]; do
    state="$(docker exec "$CONTAINER" systemctl is-system-running 2>/dev/null || true)"
    case "$state" in
        running|degraded) break ;;
    esac
    sleep 1
    elapsed=$(( elapsed + 1 ))
done

if [ "$elapsed" -ge 60 ]; then
    echo "systemd did not become ready (last state: ${state:-unknown})" >&2
    exit 1
fi

docker exec "$CONTAINER" ansible-playbook \
    -i localhost, -c local /images/ansible/ps97-ami.yml \
    -e "ps97_version=${VERSION}" \
    -e "ps97_repo_channel=${CHANNEL}" \
    -e "ps97_storage_mode=directory"
