#!/usr/bin/env bash

set -euo pipefail

if command -v rclone >/dev/null 2>&1; then
  rclone version
  exit 0
fi

for attempt in 1 2 3; do
  if sudo apt-get update -o Acquire::Retries=3 &&
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Acquire::Retries=3 rclone; then
    break
  fi

  if [[ "$attempt" -eq 3 ]]; then
    echo "Unable to install rclone after $attempt attempts." >&2
    exit 1
  fi

  delay=$((attempt * 5))
  echo "rclone installation attempt $attempt failed; retrying in ${delay}s..."
  sleep "$delay"
done

rclone version
