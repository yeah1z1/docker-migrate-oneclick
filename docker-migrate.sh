#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Docker迁移一键通"
VERSION="1.0.0"
HELPER_IMAGE="${HELPER_IMAGE:-alpine:3.20}"
WORK_ROOT="${WORK_ROOT:-/tmp/docker-migrate-cn}"
DEFAULT_PORT="${PORT:-8088}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ARCHIVE_PATH=""
SERVE_PID=""
STOPPED_FILE=""

log() { printf "${GREEN}[%s]${NC} %s\n" "$APP_NAME" "$*"; }
warn() { printf "${YELLOW}[提示]${NC} %s\n" "$*" >&2; }
err() { printf "${RED}[错误]${NC} %s\n" "$*" >&2; }
title() { printf "\n${BLUE}==== %s ====${NC}\n" "$*"; }
die() { err "$*"; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

maybe_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "需要 root 权限或 sudo：$*"
  fi
}

detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then echo apt
  elif command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v yum >/dev/null 2>&1; then echo yum
  elif command -v apk >/dev/null 2>&1; then echo apk
  else echo ""
  fi
}

install_pkg() {
  local pm="$1"
  shift
  case "$pm" in
    apt) maybe_sudo apt-get update && maybe_sudo apt-get install -y "$@" ;;
    dnf) maybe_sudo dnf install -y "$@" ;;
    yum) maybe_sudo yum install -y "$@" ;;
    apk) maybe_sudo apk add --no-cache "$@" ;;
    *) die "无法自动安装依赖，请手动安装：$*" ;;
  esac
}

ensure_deps() {
  local missing=()
  for cmd in docker jq tar gzip curl awk sed grep sort uniq; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  command -v python3 >/dev/null 2>&1 || missing+=("python3")

  if ((${#missing[@]})); then
    warn "准备安装缺少的依赖：${missing[*]}"
    local pm
    pm="$(detect_pm)"
    local pkgs=()
    for item in "${missing[@]}"; do
      case "$item" in
        python3) pkgs+=("python3") ;;
        docker) die "请先安装 Docker Engine，并确认当前用户可以执行 docker" ;;
        *) pkgs+=("$item") ;;
      esac
    done
    install_pkg "$pm" "${pkgs[@]}"
  fi

  docker version >/dev/null 2>&1 || die "Docker 不可用，请确认 Docker 已启动且当前用户有权限"
}

ensure_helper_image() {
  if ! docker image inspect "$HELPER_IMAGE" >/dev/null 2>&1; then
    log "拉取辅助镜像：$HELPER_IMAGE"
    docker pull "$HELPER_IMAGE"
  fi
}

safe_name() {
  printf '%s' "$1" | sed 's#[^A-Za-z0-9_.-]#_#g; s#^_*##; s#_*$##' | cut -c1-120
}

random_id() {
  date +%Y%m%d%H%M%S
}

local_ip() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="src"){print $(i+1); exit}}}' ||
    hostname -I 2>/dev/null | awk '{print $1}' ||
    echo "127.0.0.1"
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-Y}"
  local answer
  local suffix="[Y/n]"
  [[ "$default" == "N" ]] && suffix="[y/N]"
  read -r -p "$prompt $suffix " answer || true
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$|^[Yy][Ee][Ss]$|^是$ ]]
}

list_containers_table() {
  docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' |
    awk -F '\t' '{printf "  %2d) %-28s %-32s %s\n", NR, $1, $2, $3}'
}

all_container_names() {
  docker ps -a --format '{{.Names}}'
}

parse_range_selection() {
  local input="$1"
  local max="$2"
  local -a result=()
  local part start end i

  input="${input// /}"
  [[ -z "$input" ]] && return 0
  [[ "$input" == "all" || "$input" == "*" ]] && {
    for ((i=1; i<=max; i++)); do echo "$i"; done
    return 0
  }

  IFS=',' read -r -a parts <<< "$input"
  for part in "${parts[@]}"; do
    [[ -z "$part" ]] && continue
    if [[ "$part" == *-* ]]; then
      start="${part%-*}"
      end="${part#*-}"
      [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]] || continue
      for ((i=start; i<=end; i++)); do
        ((i >= 1 && i <= max)) && result+=("$i")
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      ((part >= 1 && part <= max)) && result+=("$part")
    fi
  done

  printf '%s\n' "${result[@]}" | awk '!seen[$0]++'
}

select_containers() {
  local mode="${1:-}"
  local explicit="${2:-}"
  mapfile -t ALL_CONTAINERS < <(all_container_names)
  ((${#ALL_CONTAINERS[@]})) || die "当前机器没有 Docker 容器"

  if [[ -n "$explicit" ]]; then
    tr ',' '\n' <<< "$explicit" | sed '/^$/d'
    return 0
  fi

  if [[ "$mode" == "all" ]]; then
    printf '%s\n' "${ALL_CONTAINERS[@]}"
    return 0
  fi

  title "选择迁移范围"
  printf "1) 全部容器\n"
  printf "2) 按编号单选/多选容器\n"
  local choice
  read -r -p "请选择 [1-2]：" choice
  if [[ "${choice:-1}" == "1" ]]; then
    printf '%s\n' "${ALL_CONTAINERS[@]}"
    return 0
  fi

  title "容器列表"
  list_containers_table
  local selected
  read -r -p "输入编号，例如 1,3-5；输入 all 表示全部：" selected
  local idx
  while read -r idx; do
    [[ -n "$idx" ]] && printf '%s\n' "${ALL_CONTAINERS[$((idx - 1))]}"
  done < <(parse_range_selection "$selected" "${#ALL_CONTAINERS[@]}")
}

container_image() {
  docker inspect "$1" | jq -r '.[0].Config.Image'
}

container_state_running() {
  docker inspect "$1" | jq -r '.[0].State.Running'
}

container_networks() {
  docker inspect "$1" | jq -r '.[0].NetworkSettings.Networks | keys[]?' | grep -Ev '^(bridge|host|none)$' || true
}

container_volumes() {
  docker inspect "$1" | jq -r '.[0].Mounts[]? | select(.Type=="volume") | .Name' || true
}

container_binds() {
  docker inspect "$1" | jq -r '.[0].Mounts[]? | select(.Type=="bind") | .Source' || true
}

stop_selected_containers() {
  local stopped_file="$1"
  shift
  : > "$stopped_file"
  local name
  for name in "$@"; do
    if [[ "$(container_state_running "$name")" == "true" ]]; then
      log "停止容器：$name"
      docker stop "$name" >/dev/null
      printf '%s\n' "$name" >> "$stopped_file"
    fi
  done
}

restart_stopped_containers() {
  local stopped_file="$1"
  [[ -f "$stopped_file" ]] || return 0
  local name
  while read -r name; do
    [[ -z "$name" ]] && continue
    log "恢复启动容器：$name"
    docker start "$name" >/dev/null || true
  done < "$stopped_file"
}

create_restore_script() {
  local target="$1"
  cat > "$target" <<'RESTORE_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Docker迁移一键通"
HELPER_IMAGE="${HELPER_IMAGE:-alpine:3.20}"

log() { printf '[%s] %s\n' "$APP_NAME" "$*"; }
warn() { printf '[提示] %s\n' "$*" >&2; }
die() { printf '[错误] %s\n' "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"; }

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

ensure_runtime() {
  need_cmd docker
  need_cmd jq
  need_cmd tar
  docker version >/dev/null 2>&1 || die "Docker 不可用"
  if [[ -d "$SCRIPT_DIR/volumes" ]] && find "$SCRIPT_DIR/volumes" -type f -name '*.tgz' | grep -q .; then
    docker image inspect "$HELPER_IMAGE" >/dev/null 2>&1 || docker pull "$HELPER_IMAGE"
  fi
}

safe_name() {
  printf '%s' "$1" | sed 's#[^A-Za-z0-9_.-]#_#g; s#^_*##; s#_*$##' | cut -c1-120
}

create_network_from_json() {
  local file="$1"
  local name driver internal attachable subnet gateway
  name="$(jq -r '.Name' "$file")"
  [[ -z "$name" || "$name" == "null" || "$name" =~ ^(bridge|host|none)$ ]] && return 0
  if docker network inspect "$name" >/dev/null 2>&1; then
    log "网络已存在，跳过：$name"
    return 0
  fi

  driver="$(jq -r '.Driver // "bridge"' "$file")"
  internal="$(jq -r '.Internal // false' "$file")"
  attachable="$(jq -r '.Attachable // false' "$file")"
  subnet="$(jq -r '.IPAM.Config[0].Subnet // empty' "$file")"
  gateway="$(jq -r '.IPAM.Config[0].Gateway // empty' "$file")"

  local args=(network create --driver "$driver")
  [[ "$internal" == "true" ]] && args+=(--internal)
  [[ "$attachable" == "true" ]] && args+=(--attachable)
  [[ -n "$subnet" ]] && args+=(--subnet "$subnet")
  [[ -n "$gateway" ]] && args+=(--gateway "$gateway")
  while IFS= read -r item; do args+=(--label "$item"); done < <(jq -r '.Labels // {} | to_entries[] | "\(.key)=\(.value)"' "$file")
  while IFS= read -r item; do args+=(--opt "$item"); done < <(jq -r '.Options // {} | to_entries[] | "\(.key)=\(.value)"' "$file")
  args+=("$name")

  log "创建网络：$name"
  docker "${args[@]}"
}

restore_networks() {
  [[ -d "$SCRIPT_DIR/networks" ]] || return 0
  local file
  while IFS= read -r -d '' file; do
    create_network_from_json "$file"
  done < <(find "$SCRIPT_DIR/networks" -type f -name '*.json' -print0)
}

restore_volumes() {
  [[ -f "$SCRIPT_DIR/volumes.tsv" ]] || return 0
  local name archive
  while IFS=$'\t' read -r name archive; do
    [[ -z "$name" || -z "$archive" ]] && continue
    if ! docker volume inspect "$name" >/dev/null 2>&1; then
      log "创建数据卷：$name"
      docker volume create "$name" >/dev/null
    else
      warn "数据卷已存在，将覆盖写入：$name"
    fi
    log "恢复数据卷：$name"
    docker run --rm \
      -v "$name:/to" \
      -v "$SCRIPT_DIR/volumes:/backup:ro" \
      "$HELPER_IMAGE" sh -c "cd /to && tar xzf /backup/$archive"
  done < "$SCRIPT_DIR/volumes.tsv"
}

restore_binds() {
  [[ -f "$SCRIPT_DIR/binds.tsv" ]] || return 0
  local source archive parent
  while IFS=$'\t' read -r source archive; do
    [[ -z "$source" || -z "$archive" ]] && continue
    parent="$(dirname "$source")"
    mkdir -p "$parent"
    log "恢复宿主机挂载目录：$source"
    tar xzf "$SCRIPT_DIR/binds/$archive" -C /
  done < "$SCRIPT_DIR/binds.tsv"
}

port_args() {
  local file="$1"
  jq -r '
    .[0].HostConfig.PortBindings // {}
    | to_entries[]
    | .key as $container
    | (.value // [null])[]
    | if . == null then $container
      else
        (.HostIp // "") as $ip
        | (.HostPort // "") as $port
        | if $ip != "" and $port != "" then "\($ip):\($port):\($container)"
          elif $port != "" then "\($port):\($container)"
          else $container end
      end
  ' "$file"
}

mount_args() {
  local file="$1"
  jq -r '
    .[0].Mounts[]?
    | select(.Type=="volume" or .Type=="bind")
    | if .Type=="volume" then
        (.Name // .Source) + ":" + .Destination + (if .RW == false then ":ro" else "" end)
      else
        .Source + ":" + .Destination + (if .RW == false then ":ro" else "" end)
      end
  ' "$file"
}

network_mode_arg() {
  local file="$1"
  local mode
  mode="$(jq -r '.[0].HostConfig.NetworkMode // "bridge"' "$file")"
  case "$mode" in
    host|none|bridge) printf '%s\n' "$mode" ;;
    container:*) printf '%s\n' "$mode" ;;
    *) jq -r '.[0].NetworkSettings.Networks | keys[0] // "bridge"' "$file" ;;
  esac
}

run_container_from_inspect() {
  local file="$1"
  local name image restart hostname user workdir privileged readonly init network_mode running
  name="$(jq -r '.[0].Name | ltrimstr("/")' "$file")"
  image="$(jq -r '.[0].Config.Image' "$file")"
  running="$(jq -r '.[0].State.Running' "$file")"

  if docker inspect "$name" >/dev/null 2>&1; then
    warn "目标机已有同名容器，删除后重建：$name"
    docker rm -f "$name" >/dev/null
  fi

  local args=(--name "$name")
  hostname="$(jq -r '.[0].Config.Hostname // empty' "$file")"
  user="$(jq -r '.[0].Config.User // empty' "$file")"
  workdir="$(jq -r '.[0].Config.WorkingDir // empty' "$file")"
  privileged="$(jq -r '.[0].HostConfig.Privileged // false' "$file")"
  readonly="$(jq -r '.[0].HostConfig.ReadonlyRootfs // false' "$file")"
  init="$(jq -r '.[0].HostConfig.Init // false' "$file")"
  restart="$(jq -r '.[0].HostConfig.RestartPolicy.Name // empty' "$file")"
  network_mode="$(network_mode_arg "$file")"

  [[ -n "$hostname" && "$hostname" != "null" ]] && args+=(--hostname "$hostname")
  [[ -n "$user" && "$user" != "null" ]] && args+=(--user "$user")
  [[ -n "$workdir" && "$workdir" != "null" ]] && args+=(--workdir "$workdir")
  [[ "$privileged" == "true" ]] && args+=(--privileged)
  [[ "$readonly" == "true" ]] && args+=(--read-only)
  [[ "$init" == "true" ]] && args+=(--init)
  [[ -n "$restart" && "$restart" != "no" && "$restart" != "null" ]] && args+=(--restart "$restart")
  args+=(--network "$network_mode")

  while IFS= read -r env_item; do [[ -n "$env_item" ]] && args+=(-e "$env_item"); done < <(jq -r '.[0].Config.Env[]?' "$file")
  while IFS= read -r label; do [[ -n "$label" ]] && args+=(--label "$label"); done < <(jq -r '.[0].Config.Labels // {} | to_entries[] | "\(.key)=\(.value)"' "$file")
  while IFS= read -r port; do [[ -n "$port" ]] && args+=(-p "$port"); done < <(port_args "$file")
  while IFS= read -r mount; do [[ -n "$mount" ]] && args+=(-v "$mount"); done < <(mount_args "$file")

  local entrypoint
  entrypoint="$(jq -r '.[0].Config.Entrypoint // empty | if type=="array" then .[0] // empty else . end' "$file")"
  [[ -n "$entrypoint" && "$entrypoint" != "null" ]] && args+=(--entrypoint "$entrypoint")

  args+=("$image")
  while IFS= read -r cmd; do [[ -n "$cmd" ]] && args+=("$cmd"); done < <(jq -r '.[0].Config.Cmd // [] | if type=="array" then .[] else . end' "$file")

  log "重建容器：$name"
  if [[ "$running" == "true" ]]; then
    docker run -d "${args[@]}"
  else
    docker create "${args[@]}" >/dev/null
  fi

  while IFS= read -r net; do
    [[ -z "$net" || "$net" == "$network_mode" || "$net" =~ ^(bridge|host|none)$ ]] && continue
    docker network connect "$net" "$name" >/dev/null 2>&1 || true
  done < <(jq -r '.[0].NetworkSettings.Networks | keys[]?' "$file")
}

restore_containers() {
  [[ -d "$SCRIPT_DIR/containers" ]] || return 0
  local file
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    run_container_from_inspect "$file"
  done < <(find "$SCRIPT_DIR/containers" -type f -name '*.json' | sort)
}

main() {
  ensure_runtime
  log "加载镜像"
  [[ -f "$SCRIPT_DIR/images.tar" ]] && docker load -i "$SCRIPT_DIR/images.tar"
  restore_networks
  restore_volumes
  restore_binds
  restore_containers
  log "恢复完成"
}

main "$@"
RESTORE_EOF
  chmod +x "$target"
}

write_manifest() {
  local bundle="$1"
  local created_at="$2"
  local containers_json volumes_json binds_json networks_json
  containers_json="$(jq -R . < "$bundle/containers.txt" | jq -s .)"
  volumes_json="$(awk -F '\t' 'NF>=2 {printf "{\"name\":%s,\"archive\":%s}\n", q($1), q($2)} function q(s){gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); return "\"" s "\""}' "$bundle/volumes.tsv" | jq -s .)"
  binds_json="$(awk -F '\t' 'NF>=2 {printf "{\"source\":%s,\"archive\":%s}\n", q($1), q($2)} function q(s){gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); return "\"" s "\""}' "$bundle/binds.tsv" | jq -s .)"
  networks_json="$(awk -F '\t' 'NF>=2 {printf "{\"name\":%s,\"file\":%s}\n", q($1), q($2)} function q(s){gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); return "\"" s "\""}' "$bundle/networks.tsv" | jq -s .)"
  jq -n \
    --arg app "$APP_NAME" \
    --arg version "$VERSION" \
    --arg created_at "$created_at" \
    --arg helper_image "$HELPER_IMAGE" \
    --argjson containers "$containers_json" \
    --argjson volumes "$volumes_json" \
    --argjson binds "$binds_json" \
    --argjson networks "$networks_json" \
    '{app:$app,version:$version,created_at:$created_at,helper_image:$helper_image,containers:$containers,volumes:$volumes,binds:$binds,networks:$networks}' \
    > "$bundle/manifest.json"
}

backup_bundle() {
  local mode="${1:-}"
  local explicit="${2:-}"
  local serve="${3:-no}"
  ensure_deps
  mkdir -p "$WORK_ROOT"

  mapfile -t SELECTED_CONTAINERS < <(select_containers "$mode" "$explicit")
  ((${#SELECTED_CONTAINERS[@]})) || die "没有选择任何容器"

  local id bundle archive_name created_at
  id="$(random_id)"
  bundle="$WORK_ROOT/docker_migrate_$id"
  archive_name="docker_migrate_${id}.tar.gz"
  ARCHIVE_PATH="$WORK_ROOT/$archive_name"
  created_at="$(date -Iseconds)"

  rm -rf "$bundle"
  mkdir -p "$bundle/containers" "$bundle/volumes" "$bundle/binds" "$bundle/networks"
  : > "$bundle/containers.txt"
  : > "$bundle/volumes.tsv"
  : > "$bundle/binds.tsv"
  : > "$bundle/networks.tsv"

  STOPPED_FILE="$bundle/stopped_containers.txt"
  : > "$STOPPED_FILE"
  if ask_yes_no "是否临时停止选中的运行容器以保证数据一致性？" "Y"; then
    stop_selected_containers "$STOPPED_FILE" "${SELECTED_CONTAINERS[@]}"
  else
    warn "未停止容器，数据库类服务建议自行做业务备份"
  fi

  local images_file="$bundle/images.list"
  : > "$images_file"

  local container safe image
  for container in "${SELECTED_CONTAINERS[@]}"; do
    log "读取容器配置：$container"
    safe="$(safe_name "$container")"
    docker inspect "$container" > "$bundle/containers/$safe.json"
    printf '%s\n' "$container" >> "$bundle/containers.txt"
    image="$(container_image "$container")"
    printf '%s\n' "$image" >> "$images_file"
  done
  sort -u "$images_file" -o "$images_file"

  if [[ -s "$images_file" ]]; then
    log "打包镜像"
    mapfile -t IMAGE_LIST < "$images_file"
    docker save -o "$bundle/images.tar" "${IMAGE_LIST[@]}"
  fi

  ensure_helper_image

  local volumes_file binds_file networks_file
  volumes_file="$bundle/volumes.list"
  binds_file="$bundle/binds.list"
  networks_file="$bundle/networks.list"
  : > "$volumes_file"
  : > "$binds_file"
  : > "$networks_file"

  for container in "${SELECTED_CONTAINERS[@]}"; do
    container_volumes "$container" >> "$volumes_file"
    container_binds "$container" >> "$binds_file"
    container_networks "$container" >> "$networks_file"
  done
  sort -u "$volumes_file" -o "$volumes_file"
  sort -u "$binds_file" -o "$binds_file"
  sort -u "$networks_file" -o "$networks_file"

  local volume vol_archive
  while read -r volume; do
    [[ -z "$volume" ]] && continue
    vol_archive="$(safe_name "$volume").tgz"
    log "打包数据卷：$volume"
    docker run --rm \
      -v "$volume:/from:ro" \
      -v "$bundle/volumes:/backup" \
      "$HELPER_IMAGE" sh -c "cd /from && tar czf /backup/$vol_archive ."
    printf '%s\t%s\n' "$volume" "$vol_archive" >> "$bundle/volumes.tsv"
  done < "$volumes_file"

  local bind index bind_archive stripped
  index=0
  while read -r bind; do
    [[ -z "$bind" ]] && continue
    if [[ ! -e "$bind" ]]; then
      warn "宿主机挂载路径不存在，跳过数据打包：$bind"
      continue
    fi
    index=$((index + 1))
    bind_archive="$(printf '%03d_%s.tgz' "$index" "$(safe_name "$bind")")"
    stripped="${bind#/}"
    log "打包宿主机挂载路径：$bind"
    tar czf "$bundle/binds/$bind_archive" -C / "$stripped"
    printf '%s\t%s\n' "$bind" "$bind_archive" >> "$bundle/binds.tsv"
  done < "$binds_file"

  local network net_file
  while read -r network; do
    [[ -z "$network" ]] && continue
    net_file="$(safe_name "$network").json"
    log "保存网络配置：$network"
    docker network inspect "$network" | jq '.[0]' > "$bundle/networks/$net_file"
    printf '%s\t%s\n' "$network" "$net_file" >> "$bundle/networks.tsv"
  done < "$networks_file"

  create_restore_script "$bundle/restore.sh"
  write_manifest "$bundle" "$created_at"

  log "生成迁移包：$ARCHIVE_PATH"
  tar czf "$ARCHIVE_PATH" -C "$WORK_ROOT" "$(basename "$bundle")"

  restart_stopped_containers "$STOPPED_FILE"

  if [[ "$serve" == "yes" ]]; then
    serve_archive "$ARCHIVE_PATH"
  else
    log "备份完成：$ARCHIVE_PATH"
  fi
}

serve_archive() {
  local archive="$1"
  local port="${SERVE_PORT:-$DEFAULT_PORT}"
  local dir
  dir="$(dirname "$archive")"
  title "新机器恢复命令"
  local url="http://$(local_ip):$port/$(basename "$archive")"
  printf "在新机器执行：\n\n"
  printf "bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh)\n\n"
  printf "然后选择：2) 新机器：输入链接下载并恢复\n"
  printf "迁移包链接：%s\n\n" "$url"
  warn "保持本窗口不要关闭；新机器恢复完成后按 Ctrl+C 结束分享"
  python3 -m http.server "$port" --bind 0.0.0.0 --directory "$dir"
}

restore_from_archive() {
  local archive="$1"
  ensure_deps
  [[ -f "$archive" ]] || die "文件不存在：$archive"
  local tmp
  tmp="$(mktemp -d "${WORK_ROOT}/restore.XXXXXX")"
  tar xzf "$archive" -C "$tmp"
  local bundle
  bundle="$(find "$tmp" -maxdepth 1 -type d -name 'docker_migrate_*' | head -n1)"
  [[ -n "$bundle" && -x "$bundle/restore.sh" ]] || die "迁移包格式不正确"
  bash "$bundle/restore.sh"
}

download_and_restore() {
  ensure_deps
  mkdir -p "$WORK_ROOT"
  local url archive
  read -r -p "请输入老机器生成的迁移包链接：" url
  [[ -n "$url" ]] || die "链接不能为空"
  archive="$WORK_ROOT/download_$(random_id).tar.gz"
  log "下载迁移包"
  curl -fL "$url" -o "$archive"
  restore_from_archive "$archive"
}

main_menu() {
  title "$APP_NAME v$VERSION"
  printf "1) 老机器：备份并生成下载链接\n"
  printf "2) 新机器：输入链接下载并恢复\n"
  printf "3) 只备份到本地文件\n"
  printf "4) 从本地迁移包恢复\n"
  printf "5) 退出\n"
  local choice archive
  read -r -p "请选择 [1-5]：" choice
  case "${choice:-}" in
    1) backup_bundle "" "" "yes" ;;
    2) download_and_restore ;;
    3) backup_bundle "" "" "no" ;;
    4)
      read -r -p "请输入本地迁移包路径：" archive
      restore_from_archive "$archive"
      ;;
    5) exit 0 ;;
    *) die "无效选择" ;;
  esac
}

usage() {
  cat <<EOF
$APP_NAME v$VERSION

用法：
  bash docker-migrate.sh                  # 打开中文菜单
  bash docker-migrate.sh --backup-link    # 老机器备份并生成下载链接
  bash docker-migrate.sh --backup-local   # 只备份到本地
  bash docker-migrate.sh --restore URL    # 新机器下载并恢复
  bash docker-migrate.sh --restore-file FILE
  bash docker-migrate.sh --all            # 配合备份命令，全量迁移
  bash docker-migrate.sh --containers a,b # 配合备份命令，指定容器

环境变量：
  PORT=8088                 分享迁移包的端口
  HELPER_IMAGE=alpine:3.20  数据卷打包辅助镜像
EOF
}

main() {
  local action="" mode="" containers="" restore_url="" restore_file=""
  while (($#)); do
    case "$1" in
      --backup-link) action="backup-link" ;;
      --backup-local) action="backup-local" ;;
      --restore) action="restore-url"; restore_url="${2:-}"; shift ;;
      --restore-file) action="restore-file"; restore_file="${2:-}"; shift ;;
      --all) mode="all" ;;
      --containers) containers="${2:-}"; shift ;;
      -h|--help) usage; exit 0 ;;
      -v|--version) echo "$VERSION"; exit 0 ;;
      *) die "未知参数：$1" ;;
    esac
    shift
  done

  case "$action" in
    backup-link) backup_bundle "$mode" "$containers" "yes" ;;
    backup-local) backup_bundle "$mode" "$containers" "no" ;;
    restore-url)
      [[ -n "$restore_url" ]] || die "--restore 需要 URL"
      mkdir -p "$WORK_ROOT"
      local archive="$WORK_ROOT/download_$(random_id).tar.gz"
      ensure_deps
      curl -fL "$restore_url" -o "$archive"
      restore_from_archive "$archive"
      ;;
    restore-file)
      [[ -n "$restore_file" ]] || die "--restore-file 需要文件路径"
      restore_from_archive "$restore_file"
      ;;
    "") main_menu ;;
  esac
}

trap '[[ -n "${SERVE_PID:-}" ]] && kill "$SERVE_PID" 2>/dev/null || true; [[ -n "${STOPPED_FILE:-}" ]] && restart_stopped_containers "$STOPPED_FILE" || true' EXIT
main "$@"
