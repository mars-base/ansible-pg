# FerretDB（MongoDB Wire Protocol 代理）

FerretDB 是一个开源的 Go 语言 MongoDB 兼容代理，通过 MongoDB wire protocol 接收客户端请求，转换为 PostgreSQL SQL 执行。与 pg_documentdb（PG 扩展）配合使用，提供完整的 MongoDB 兼容体验。

| | FerretDB | pg_documentdb |
|---|---------|---------------|
| 类型 | 独立 Go 进程 | PG 扩展 |
| 协议 | MongoDB wire protocol | SQL 函数 API |
| 连接方式 | MongoDB 驱动直连 | `documentdb_api.*` SQL 调用 |
| 适用场景 | 迁移现有 MongoDB 应用 | 新应用，同时用关系型和文档型 |

## 前置条件

- pg_documentdb 扩展已安装并启用（FerretDB v2.x 依赖 documentdb 扩展）
- pgbouncer 已运行（FerretDB 通过 pgbouncer 连接 PG 后端）

## 配置

### 1. 多实例配置

在 `host_vars/<host>/ferretdb.yaml` 中配置（每个实例独立的 MongoDB 端口和 debug 端口）：

```yaml
ferretdb_host: "{{ ansible_default_ipv4.address }}"

ferretdb_instances:
  - name: app1
    listen_port: 27017                # MongoDB 监听端口
    debug_port: 18088                 # metrics/pprof 端口
    pg_host: "{{ ansible_default_ipv4.address }}"
    pg_port: 5433                    # pgbouncer 端口
    pg_user: "dba"
    pg_password: "<password>"
  - name: app2
    listen_port: 27018
    debug_port: 18089
    pg_host: "{{ ansible_default_ipv4.address }}"
    pg_port: 5433
    pg_user: "dba"
    pg_password: "<password>"
```

### 2. hosts.ini 配置

将需要部署 FerretDB 的主机加入 `[ferretdb]` 组：

```ini
[ferretdb]
pg-single
```

### 3. 安装方式

FerretDB 使用二进制下载 + supervisor 管理，与 pgdog 的部署模式一致：

- 二进制从 GitHub Releases 下载到 `/usr/local/bin/ferretdb`
- 每个实例由 supervisor 管理独立进程（`ferretdb-<name>`）
- 日志在 `/srv/ferretdb/<name>/logs/`

## 部署

```bash
# 部署 FerretDB
ansible-playbook -i hosts.ini playbooks/ferretdb.yaml -e HOSTS=ferretdb

# 重启实例（配置变更后）
ansible pg-single -i hosts.ini -b -a "supervisorctl restart ferretdb-app1"
```

## 验证

```bash
# 使用 mongosh 连接
mongosh "mongodb://dba:<password>@10.241.21.97:27017/myapp"

# 运行 Python 测试脚本（需要 pymongo: uv add pymongo）
uv run python3 test/test_ferretdb.py -H 10.241.21.97 -p 27017 -U dba -W <password>
uv run python3 test/test_ferretdb.py -H 10.241.21.97 -p 27018 -U dba -W <password>

# 指定 MongoDB 逻辑数据库名（映射为 PG schema）
uv run python3 test/test_ferretdb.py -H 10.241.21.97 -p 27017 -U dba -W <password> -s myapp
```

## 架构

```
MongoDB 客户端 (pymongo/mongosh/...)
    │
    ├── port 27017 ──► ferretdb-app1 ──► pgbouncer:5433 ──► PostgreSQL (documentdb)
    │
    └── port 27018 ──► ferretdb-app2 ──► pgbouncer:5433 ──► PostgreSQL (documentdb)
```

## 注意事项

- FerretDB v2.x **依赖** DocumentDB PG 扩展，必须先安装 pg_documentdb
- MongoDB 连接 URI 中的数据库名是逻辑名，FerretDB 会映射为 PG 中的不同 schema（数据隔离）
- PG 后端只能连 `postgres` 库（documentdb 扩展限制）
- 每个实例需要独立的 `listen_port` 和 `debug_port`
- 认证使用 MongoDB SCRAM 方式，用户名密码是 PG 用户
