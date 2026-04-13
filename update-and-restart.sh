#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
COMPOSE_OVERRIDE_FILE="$ROOT_DIR/docker/docker-compose.override.yml"
DATA_DIR="${METAPI_DATA_DIR:-/root/metapi/data}"

# Deployment config. Edit these values on the server before running the script.
METAPI_AUTH_TOKEN="shanliushi860224"
METAPI_PROXY_TOKEN="shanliushi860224860224"
METAPI_PORT="4000"
METAPI_TZ="Asia/Shanghai"
METAPI_BIND_HOST="0.0.0.0"
METAPI_DATA_DIR="${METAPI_DATA_DIR:-/root/metapi/data}"
METAPI_DOCKER_APT_MIRROR_BASE="${METAPI_DOCKER_APT_MIRROR_BASE:-http://mirrors.tuna.tsinghua.edu.cn/debian}"
METAPI_DOCKER_APT_SECURITY_MIRROR_BASE="${METAPI_DOCKER_APT_SECURITY_MIRROR_BASE:-http://mirrors.tuna.tsinghua.edu.cn/debian-security}"
METAPI_INSTALL_K8S_TOOLS="${METAPI_INSTALL_K8S_TOOLS:-false}"

DO_PULL=0
SKIP_BACKUP=0
BUILD_LOCAL=1

usage() {
  cat <<'EOF'
Usage: ./update-and-restart.sh [--pull] [--use-image] [--skip-backup]

默认行为:
  1. 保留现有 /root/metapi/data 数据
  2. 先备份数据目录
  3. 基于当前项目目录重新构建并重启容器
  4. 本地 Docker 构建默认使用脚本内配置的 Debian 镜像源，降低 apt 卡住概率
  5. 普通 Docker Compose 部署默认跳过 kubectl/helm 下载，避免构建阶段卡住
  6. 默认监听 0.0.0.0:4000，可通过 METAPI_BIND_HOST 改为仅本机访问

可选参数:
  --pull         先拉取最新 Git 代码后再部署
  --use-image    不构建本地源码，直接拉取预构建镜像并重启
  --with-k8s-tools
                 本地构建时安装 kubectl/helm；仅 K3s/Helm 更新中心场景需要
  --skip-backup  跳过启动前数据备份
  -h, --help     显示帮助
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_file() {
  if [ ! -f "$1" ]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

require_config() {
  local name="$1"
  local value="$2"
  local placeholder="$3"

  if [ -z "$value" ] || [ "$value" = "$placeholder" ]; then
    echo "Missing required config: $name. Edit the deployment config block in this script before running it." >&2
    exit 1
  fi
}

require_port() {
  if ! [[ "$METAPI_PORT" =~ ^[0-9]+$ ]]; then
    echo "Invalid METAPI_PORT: $METAPI_PORT" >&2
    exit 1
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pull)
      DO_PULL=1
      ;;
    --skip-backup)
      SKIP_BACKUP=1
      ;;
    --use-image)
      BUILD_LOCAL=0
      ;;
    --with-k8s-tools)
      METAPI_INSTALL_K8S_TOOLS=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

require_cmd docker
require_cmd tar
require_cmd git
require_file "$COMPOSE_FILE"
require_config "METAPI_AUTH_TOKEN" "$METAPI_AUTH_TOKEN" "change-me-admin-token"
require_config "METAPI_PROXY_TOKEN" "$METAPI_PROXY_TOKEN" "change-me-proxy-sk-token"
require_config "METAPI_TZ" "$METAPI_TZ" ""
require_config "METAPI_BIND_HOST" "$METAPI_BIND_HOST" ""
require_config "METAPI_DATA_DIR" "$METAPI_DATA_DIR" ""
require_port

export AUTH_TOKEN="$METAPI_AUTH_TOKEN"
export PROXY_TOKEN="$METAPI_PROXY_TOKEN"
export PORT="$METAPI_PORT"
export TZ="$METAPI_TZ"
export METAPI_DATA_DIR
export METAPI_BIND_HOST
export METAPI_DOCKER_APT_MIRROR_BASE
export METAPI_DOCKER_APT_SECURITY_MIRROR_BASE
export METAPI_INSTALL_K8S_TOOLS

COMPOSE_ARGS=(
  -f "$COMPOSE_FILE"
)

if [ "$BUILD_LOCAL" -eq 1 ]; then
  require_file "$COMPOSE_OVERRIDE_FILE"
  COMPOSE_ARGS=(
    -f "$COMPOSE_FILE"
    -f "$COMPOSE_OVERRIDE_FILE"
  )
fi

if [ "$DO_PULL" -eq 1 ]; then
  echo "[0/5] Checking git worktree..."
  if [ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]; then
    echo "Git worktree has uncommitted changes. Commit/stash them first, or rerun without --pull to deploy the current local code." >&2
    exit 1
  fi

  echo "[1/5] Pulling latest git changes..."
  git -C "$ROOT_DIR" pull --rebase
else
  if [ "$BUILD_LOCAL" -eq 1 ]; then
    echo "[1/4] Using current local source code..."
  else
    echo "[1/4] Using prebuilt Docker image..."
  fi
fi

BACKUP_FILE=""
RESTORE_ON_ERROR=0

restore_if_failed() {
  if [ "$RESTORE_ON_ERROR" -eq 1 ]; then
    echo "Update failed after containers were stopped; attempting to restore service..." >&2
    docker compose "${COMPOSE_ARGS[@]}" up -d --force-recreate || true
  fi
}

trap restore_if_failed ERR

if [ "$DO_PULL" -eq 1 ]; then
  echo "[2/5] Stopping current containers..."
else
  echo "[2/4] Stopping current containers..."
fi
docker compose "${COMPOSE_ARGS[@]}" down --remove-orphans
RESTORE_ON_ERROR=1

if [ "$SKIP_BACKUP" -eq 0 ]; then
  mkdir -p "$DATA_DIR"
  BACKUP_FILE="$ROOT_DIR/docker/data-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  if [ "$DO_PULL" -eq 1 ]; then
    echo "[3/5] Backing up data directory..."
  else
    echo "[3/4] Backing up data directory..."
  fi
  tar -czf "$BACKUP_FILE" -C "$DATA_DIR" .
else
  if [ "$DO_PULL" -eq 1 ]; then
    echo "[3/5] Skipping data backup by request..."
  else
    echo "[3/4] Skipping data backup by request..."
  fi
fi

if [ "$DO_PULL" -eq 1 ]; then
  if [ "$BUILD_LOCAL" -eq 1 ]; then
    echo "[4/5] Rebuilding and starting containers..."
  else
    echo "[4/5] Pulling prebuilt image and starting containers..."
  fi
else
  if [ "$BUILD_LOCAL" -eq 1 ]; then
    echo "[4/4] Rebuilding and starting containers..."
  else
    echo "[4/4] Pulling prebuilt image and starting containers..."
  fi
fi
if [ "$BUILD_LOCAL" -eq 1 ]; then
  docker compose "${COMPOSE_ARGS[@]}" up -d --build --force-recreate
else
  docker compose "${COMPOSE_ARGS[@]}" pull metapi
  docker compose "${COMPOSE_ARGS[@]}" up -d --force-recreate --no-build
fi
RESTORE_ON_ERROR=0
trap - ERR

echo
echo "Container status:"
docker compose "${COMPOSE_ARGS[@]}" ps

echo
echo "Recent logs:"
docker compose "${COMPOSE_ARGS[@]}" logs --tail 20

if [ -n "$BACKUP_FILE" ]; then
  echo
  echo "Data backup saved to: $BACKUP_FILE"
fi

if PORT_MAPPING="$(docker compose "${COMPOSE_ARGS[@]}" port metapi 4000 2>/dev/null)"; then
  echo
  echo "Service is available at: $PORT_MAPPING"
fi
