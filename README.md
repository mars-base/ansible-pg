# ansible-pg

使用 Ansible 部署 PostgreSQL（基于 Patroni 的高可用集群）。

## 高可用架构

```
                          ┌─────────────────────────────────────┐
                          │           HAProxy (备份服务器)        │
                          │  :5000 primary    :5001 replica     │
                          │  :8090 stats      :8008 health-check│
                          └──────┬─────────────────┬────────────┘
                                 │                 │
                    ┌────────────┴───┐        ┌────┴────────────┐
                    │   pg-patroni-01│        │   pg-patroni-02 │
                    │  (replica)     │        │   (primary)     │
                    │  PostgreSQL 17 │        │  PostgreSQL 17  │
                    │  pgbouncer:5433│        │  pgbouncer:5433 │
                    └───────┬────────┘        └────────┬────────┘
                            │    Streaming Replication │
                            │◄─────────────────────────┘
                            │
                    ┌───────┴─────────────────────────────────┐
                    │              etcd (备份服务器)            │
                    │  存储集群状态、leader 选举、故障切换       │
                    └─────────────────────────────────────────┘
                            │
                    ┌───────┴─────────────────────────────────┐
                    │          pgbackrest (备份服务器)          │
                    │  SSH 连接各 patroni 节点，WAL 归档 + 备份 │
                    │  :5433 pgbouncer  :32200 SSH             │
                    └─────────────────────────────────────────┘
```

**核心组件**

| 组件 | 角色 |
|------|------|
| **Patroni** | 集群管理、leader 选举、自动故障切换 |
| **PostgreSQL** | 1 个 primary（读写）+ N 个 replica（只读，流复制） |

**故障切换**：primary 宕机后，Patroni 通过 etcd 感知状态变化，自动从存活的 replica 中选举新的 primary，HAProxy 健康检查随之将流量路由到新主节点，整个过程无需人工干预。
| **pgbouncer** | 各节点 sidecar 连接池，代理端口 5433 |
| **HAProxy** | 读写分离入口，L7 健康检查路由到对应角色节点 |
| **etcd** | DCS（分布式配置存储），保存集群元数据 |
| **pgbackrest** | 备份服务器，WAL 归档 + 定时全量备份 |
| **PostgREST** | RESTful API 代理（可选） |
| **pgdog** | 分片代理（可选，支持多实例） |

## 环境准备

> **推荐系统**：Debian / Ubuntu。本项目基于 APT 包管理、systemd 服务管理开发测试，其他操作系统未经验证，可能存在兼容性问题。

### 使用 uv（推荐）

```bash
uv sync
source .venv/bin/activate
```

### 使用 pip

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 配置 inventory 和分组变量

1. 复制示例 ansible.cfg 并调整：

```bash
cp ansible.cfg.example ansible.cfg
# 默认示例中 inventory=hosts.ini，可按实际环境修改
```

2. 复制示例 inventory 并按实际环境修改：

```bash
cp hosts.ini.example hosts.ini
# 编辑 hosts.ini，替换为实际的主机 IP、用户名
```

3. 复制示例 group_vars 并替换密码：

```bash
# HA 集群配置
cp group_vars/pg_cluster/pg_all.yaml.example group_vars/pg_cluster/pg_all.yaml

# 编辑上述 pg_all.yaml，将所有 CHANGEME 替换为实际密码
# 建议使用 Ansible Vault 加密敏感字段
```

4. **重点**：修改 `group_vars/pg_cluster/pg_all.yaml` 或 `group_vars/pg_single/pg_all.yaml`：
   - 节点角色 `pg_node_role`
   - PostgreSQL 管理员/业务用户密码
   - etcd 地址、pgbackrest 仓库路径与 stanza
   - 防火墙可信网段

## 快速开始

### HA（或单节点） 集群部署

```bash
ansible-playbook -e HOSTS=pg_cluster playbooks/pg-ha-cluster.yaml
```

### 只初始化数据库、用户、权限

```bash
ansible-playbook -e HOSTS=pg_cluster playbooks/pg-ha-cluster.yaml -t initdb
```

### 执行 SQL 文件

```bash
ansible-playbook -e HOSTS=pg_cluster playbooks/pgsql.yaml \
  -e pg_port=5432 \
  -e pg_user=dba \
  -e pg_password=CHANGEME \
  -e pg_database=dev \
  -e sql_file=pg.sql
```

### 备份数据库

```bash
ansible-playbook -e HOSTS=pg_cluster playbooks/pgdump.yaml \
  -e _mode=sql \
  -e _db=dev \
  -e _user=dba \
  -e _password=CHANGEME
```

## 常用 Tag

| Tag | 说明 |
|-----|------|
| `py3venv` | 部署 Python 虚拟环境 |
| `etcd_cluster` | 部署 etcd |
| `haproxy` | 部署 HAProxy |
| `pgbouncer` | 部署 pgbouncer |
| `patroni` | 部署 Patroni + PostgreSQL |
| `patroni-config` | 只更新 Patroni 配置 |
| `initdb` | 初始化数据库、用户、权限 |
| `pg-extension` | 安装 PostgreSQL 扩展 |
| `pgbackrest` | 部署 pgbackrest |
| `cron` | 配置定时备份 |
| `postgrest` | 部署 PostgREST |

## 检查各组件状态

部署完成后，在目标主机上执行以下命令逐一检查组件是否正常运行：

```bash
# Patroni 集群健康状态
curl -s http://$(hostname -I | awk '{print $1}'):8008/health

# etcd
sudo supervisorctl status etcd_12380

# pgbouncer
systemctl status pgbouncer --no-pager

# postgrest
systemctl status postgrest --no-pager

# pgbackrest（WAL 归档检查）
sudo -iu postgres pgbackrest --stanza=pg-single check

# pgbackrest 备份信息
sudo -iu postgres pgbackrest --stanza=pg-single info

# pgdog 多实例
sudo supervisorctl status pgdog-production pgdog-dev

# HAProxy 读写分离
systemctl status haproxy --no-pager
curl -s http://<haproxy_ip>:5000/primary   # 写入端口（连接到 primary）
curl -s http://<haproxy_ip>:5001/replica   # 只读端口（连接到 replica）
# 健康检查统计页面
curl -s http://<haproxy_ip>:8090/haproxy/stats

# cron 定时备份
sudo crontab -l -u root | grep backup
```

### HAProxy 端口说明

| 端口 | 用途 | 连接方式 |
|------|------|---------|
| `5000` | primary（读写） | TCP，通过 L7 健康检查 `/primary` 路由到主节点 |
| `5001` | replica（只读） | TCP，通过 L7 健康检查 `/replica` 路由到从节点，roundrobin 负载均衡 |
| `8008` | 健康检查端口 | Patroni REST API，HAProxy 通过此端口判断节点角色 |
| `8090` | stats 统计页面 | HTTP，访问 `/haproxy/stats` 查看代理状态 |

### PostgREST RESTful API

PostgREST 自动将 PostgreSQL 数据库的表、视图、函数转化为 RESTful API，无需编写后端代码。

**配置**：
- 数据库：通过 HAProxy primary (`192.168.1.13:5000`) 连接
- Schema：`public`
- 匿名角色：`anno`（未认证请求）
- 认证：JWT token（`Authorization: Bearer <token>`）
- 监听端口：`4000`

**常用 API 示例**：

```bash
# 查询所有记录
curl http://192.168.1.13:4000/department

# 条件筛选
curl "http://192.168.1.13:4000/department?id=eq.1"
curl "http://192.168.1.13:4000/department?name=like.*admin*"
curl "http://192.168.1.13:4000/department?id=gt.5&id=lt.10"  # AND 条件

# 分页
curl "http://192.168.1.13:4000/department?limit=10&offset=0"

# 排序
curl "http://192.168.1.13:4000/department?order=name.desc"
curl "http://192.168.1.13:4000/department?order=id.asc,name.desc"  # 多字段排序

# 选择特定字段
curl "http://192.168.1.13:4000/department?select=id,name"

# 插入数据
curl -X POST http://192.168.1.13:4000/department \
  -H "Content-Type: application/json" \
  -d '{"name": "New Department"}'

# 更新数据
curl -X PATCH "http://192.168.1.13:4000/department?id=eq.1" \
  -H "Content-Type: application/json" \
  -d '{"name": "Updated Department"}'

# 删除数据
curl -X DELETE "http://192.168.1.13:4000/department?id=eq.1"

# 获取 OpenAPI 文档
curl http://192.168.1.13:4000/
```

**JWT 认证**：

PostgREST 权限模型：
- 未认证请求：使用 `db-anon-role`（默认 `anno`），仅有 SELECT 权限
- 已认证请求：使用 JWT 中的 `role` 字段对应 PostgreSQL 角色权限

部署时自动生成 100 年有效期的 JWT token，输出在 Ansible playbook 的 "Generate JWT token" 步骤中。

```bash
# 使用 JWT token 认证（需替换为实际 token）
JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiZGJhIiwiZXhwIjo0OTQwNDcxMjc5fQ.xxx"

# 读取（anno 也可，但已认证角色权限更大）
curl -H "Authorization: Bearer $JWT" \
  http://192.168.1.13:4000/department

# 插入（需要 JWT 认证 + 对应角色有 INSERT 权限）
curl -X POST http://192.168.1.13:4000/department \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d '{"name": "Engineering"}'

# 更新
curl -X PATCH "http://192.168.1.13:4000/department?id=eq.1" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d '{"name": "Updated"}'

# 删除
curl -X DELETE "http://192.168.1.13:4000/department?id=eq.1" \
  -H "Authorization: Bearer $JWT"
```

JWT 生成说明（HS256 算法）：
```bash
# Header:  {"alg": "HS256", "typ": "JWT"}
# Payload: {"role": "dba", "exp": <unix_timestamp>}
# 签名密钥: pg_all.yaml 中的 postgrest_jwt_secret（至少 32 字符）
#
# 可用 Python 快速生成：
#   import jwt, time
#   token = jwt.encode({"role": "dba", "exp": int(time.time()) + 3600*24*365*100},
#                      "YOUR_JWT_SECRET", algorithm="HS256")
```

> 注意：写入操作（POST/PATCH/DELETE）返回 403 时，说明 JWT 中的 `role` 用户对目标表没有对应权限，需在 PostgreSQL 中 `GRANT` 授权。

**检查状态**：

```bash
systemctl status postgrest --no-pager
curl -s http://192.168.1.13:4000/ | python3 -m json.tool  # OpenAPI 文档
```

### 测试 pgbouncer 连接

```bash
PGPASSWORD=<dba_password> PGUSER=dba PGHOST=<host_ip> PGPORT=5433 PGDATABASE=postgres /usr/bin/psql -c "SELECT current_database(), version()"
```

> 注意：Debian 系统的 `/usr/bin/psql` 是 pg_wrapper 包装脚本，通过 URI 连接会冲突，建议使用环境变量方式或 `/usr/lib/postgresql/<version>/bin/psql` 直连。

## 注意事项

1. 首次使用请从对应的 `.example` 文件复制并修改。
2. 首次部署会安装 PostgreSQL 17，如需其他版本，修改 `postgres_version`。
3. `pgbackrest` 通过 ssh 免密连接，请在对应的 `group_vars/*/pg_all.yaml` 中配置 `pgbackrest_ssh_private_key` 与 `pgbackrest_ssh_public_key`。
4. `roles/*/defaults/main.yml` 中的密码类变量默认值为 `CHANGEME`，部署前请在 `group_vars/*/pg_all.yaml` 或 `host_vars/*/pgdog.yaml` 中替换为实际值。
5. 各 role 的详细说明见 `roles/<role>/README.md`。
6. 测试脚本 `scripts/*.py` 中的连接串多为示例，使用前请按需修改。
