#!/usr/bin/env bash
#Time    :   2025/06/11 10:29:12
#Author  :   fish
#Desc    :   Setup pgadmin4 Docker container

set -euo pipefail

# 参数说明
email=${1:-admin@domain.com}
password=${2:-admin}

cat<<EOF
[TIPS] The default binary paths set in the container are as follows:

DEFAULT_BINARY_PATHS = {
    'pg-17': '/usr/local/pgsql-17',
    'pg-16': '/usr/local/pgsql-16',
    'pg-15': '/usr/local/pgsql-15',
    'pg-14': '/usr/local/pgsql-14',
    'pg-13': '/usr/local/pgsql-13'
}

EOF

containerName="pgadmin4"
dataDir="/srv/pgadmin4"

echo "[INFO] Container name: $containerName"
echo "[INFO] Data directory: $dataDir"
echo "[INFO] Email: $email"

# 创建数据目录
sudo mkdir -p "$dataDir"

# 创建 pgadmin 用户（UID/GID 5050）
if ! id pgadmin > /dev/null 2>&1; then
    echo "[INFO] Creating pgadmin user (UID 5050)..."
    sudo useradd -M -s /usr/sbin/nologin -U -u 5050 pgadmin
fi

# 修改数据目录权限
sudo chown -R pgadmin:pgadmin "$dataDir"

# 检查 Docker
if ! command -v docker > /dev/null 2>&1; then
    echo "[ERROR] Docker not installed"
    exit 1
fi

# 检查并拉取镜像
if ! docker image ls | grep -q dpage/pgadmin4; then
    echo "[INFO] Pulling dpage/pgadmin4 image..."
    docker pull dpage/pgadmin4
fi

# 启动容器
echo "[INFO] Starting pgadmin4 container..."
docker run \
    -d \
    --name "$containerName" \
    --net host \
    -e PGADMIN_DEFAULT_EMAIL="$email" \
    -e PGADMIN_DEFAULT_PASSWORD="$password" \
    -v "$dataDir":/var/lib/pgadmin \
    dpage/pgadmin4

echo "[INFO] pgadmin4 started successfully"
echo "[INFO] Access: http://127.0.0.1:80"
echo "[INFO] Email: $email"
echo "[INFO] Password: $password"
