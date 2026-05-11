#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

install -d "$BIN_DIR"
install -m 0755 "$SOURCE_DIR/bin/docker-migrate" "$BIN_DIR/docker-migrate"

echo "Installed docker-migrate to $BIN_DIR/docker-migrate"
