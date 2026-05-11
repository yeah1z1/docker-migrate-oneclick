#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

install -d "$BIN_DIR"
install -m 0755 "$SOURCE_DIR/docker-migrate.sh" "$BIN_DIR/docker-migrate-cn"

echo "已安装 Docker迁移一键通: $BIN_DIR/docker-migrate-cn"
