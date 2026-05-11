#!/usr/bin/env bash
set -euo pipefail

TARGET="${TARGET:-root@NEW_SERVER_IP}"

../bin/docker-migrate migrate \
  --target "$TARGET" \
  --containers nginx,redis \
  --volumes shared_data \
  --replace \
  --start
