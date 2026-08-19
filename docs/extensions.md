# PostgreSQL 扩展安装

## APT 源配置

`pg-extension` role 自动配置两个 apt 源：

| 源 | 地址 | 提供扩展示例 |
|----|------|-------------|
| **Pigsty** | `repo.pigsty.io/apt/pgsql/` | pgmq, pg_cron, pg_stat_statements, pgvectorscale |
| **PGDG** | `apt.postgresql.org/pub/repos/apt/` | pgvector (pgvector_17), postgis, pgrouting |

> pgvector 等 PGDG-only 扩展需要先添加 PGDG 源，否则 `pig install pgvector` 会报 `Package 'postgresql-17-pgvector' has no installation candidate`。

## 已安装扩展清单

### pg-single 节点（PostgreSQL 17）

| 扩展 | 版本 | 来源 | 数据库 | 备注 |
|------|------|------|--------|------|
| pg_cron | 1.6.7 | PGDG | postgres | 定时任务 |
| uuid-ossp | 内置 | contrib | dev, prod | UUID 生成函数 |
| pg_stat_statements | 1.18 | contrib | dev, prod | SQL 统计 |
| pgmq | 1.5.1 | Pigsty | dev, prod | 消息队列 |
| pgvector (vector) | 0.8.6 | PGDG | dev, prod | 向量搜索 |
| pg_duckdb | 1.1.0 | Pigsty | dev, prod | DuckDB 嵌入式 OLAP，需 shared_preload_libraries |
| pgcrypto | 1.3 | contrib | dev, prod | 加密函数（md5/sha/gen_random_bytes 等） |
| documentdb | 0.114-0 | Pigsty | postgres | Microsoft DocumentDB（MongoDB 兼容），需 shared_preload_libraries |
| rum | - | PGDG | - | pg_documentdb 依赖（GIN 索引增强） |

## 常用扩展配置

配置扩展需要两个变量：

- `pg_extensions` — apt 包标识，`pig install` 用（pig 自动翻译为包名）
- `pg_extensions_on` — SQL 扩展名，`CREATE EXTENSION` 用

> **注意**：apt 包标识和 SQL 扩展名不一定相同，参考下表。

### pg_extensions（安装扩展包）

```yaml
pg_extensions:
  - "pg_cron"              # 定时任务
  - "uuid-ossp"            # UUID 生成函数
  - "pg_stat_statements"   # SQL 统计
  - "pgmq"                 # 消息队列
  - "pgvector"             # 向量搜索（PGDG 源）
  - "pg_duckdb"            # DuckDB 嵌入式 OLAP（需 shared_preload_libraries）
  - "pgcrypto"             # 加密函数（md5/sha/gen_random_bytes）
  - "postgis"              # GIS 空间数据（PGDG 源）
  - "timescaledb"          # 时序数据库
  - "citus"                # 分布式数据库
  - "pg_search"            # BM25 全文搜索
  - "pg_graphql"           # GraphQL 支持
  - "pg_partman"           # 分区管理
  - "pg_repack"            # 表在线重组
  - "pgjwt"                # JWT 生成与验证
  - "hstore"               # 键值对类型
```

### pg_extensions_on（在指定库启用）

```yaml
pg_extensions_on:
  # pg_cron — 必须装在 postgres 库
  - { db: 'postgres', extension: 'pg_cron' }

  # 通用扩展
  - { db: 'dev', extension: 'pg_stat_statements' }
  - { db: 'prod', extension: 'pg_stat_statements' }
  - { db: 'dev', extension: 'uuid-ossp' }
  - { db: 'prod', extension: 'uuid-ossp' }

  # 消息队列
  - { db: 'dev', extension: 'pgmq' }
  - { db: 'prod', extension: 'pgmq' }

  # 向量搜索（SQL 扩展名是 vector，不是 pgvector）
  - { db: 'dev', extension: 'vector' }
  - { db: 'prod', extension: 'vector' }

  # DuckDB 嵌入式 OLAP（需 shared_preload_libraries 预加载）
  - { db: 'dev', extension: 'pg_duckdb' }
  - { db: 'prod', extension: 'pg_duckdb' }

  # 加密函数
  - { db: 'dev', extension: 'pgcrypto' }
  - { db: 'prod', extension: 'pgcrypto' }

  # GIS（SQL 扩展名是 postgis）
  - { db: 'dev', extension: 'postgis' }
  - { db: 'prod', extension: 'postgis' }

  # 全文搜索
  - { db: 'dev', extension: 'pg_search' }
  - { db: 'prod', extension: 'pg_search' }
```

### 扩展包名与 SQL 名称对照

| pg_extensions 值 | pg_extensions_on 值 | 来源 | 说明 |
|------------------|---------------------|------|------|
| `pg_cron` | `pg_cron` | PGDG | 定时任务，须装在 postgres 库 |
| `uuid-ossp` | `uuid-ossp` | contrib | UUID 生成 |
| `pg_stat_statements` | `pg_stat_statements` | contrib | SQL 统计 |
| `pgmq` | `pgmq` | Pigsty | 消息队列 |
| `pgvector` | `vector` | PGDG | 向量搜索 |
| `pg_duckdb` | `pg_duckdb` | Pigsty | DuckDB 嵌入式 OLAP，需预加载 |
| `pgcrypto` | `pgcrypto` | contrib | 加密函数（md5/sha/uuid） |
| `postgis` | `postgis` | PGDG | GIS 空间数据 |
| `timescaledb` | `timescaledb` | Pigsty | 时序数据库 |
| `citus` | `citus` | Pigsty | 分布式 |
| `pg_search` | `pg_search` | Pigsty | BM25 全文搜索 |
| `pg_graphql` | `pg_graphql` | Pigsty | GraphQL |
| `pg_partman` | `pg_partman` | Pigsty | 分区管理 |
| `pg_repack` | `pg_repack` | Pigsty | 表在线重组 |
| `pgjwt` | `pgjwt` | Pigsty | JWT 生成验证 |
| `hstore` | `hstore` | contrib | 键值对 |
| `pgvectorscale` | `vectorscale` | Pigsty | pgvector 高性能补充 |
| `documentdb` | `documentdb` | Pigsty | DocumentDB（MongoDB 兼容），需 `cascade: true` |
| `rum` | `rum` | PGDG | GIN 索引增强，pg_documentdb 依赖 |

> 更多扩展见 https://ext.pigsty.io/list/pkg/

## 扩展特殊配置

部分扩展除安装外，还需要在 `group_vars` 中配置额外参数。

### pg_duckdb（DuckDB 嵌入式 OLAP）

pg_duckdb 需要多项额外配置：

**1. shared_preload_libraries 预加载**

在 `postgres_shared_preload_libraries` 中添加 `pg_duckdb`：

```yaml
postgres_shared_preload_libraries: "pg_cron,pg_stat_statements,uuid-ossp,pg_duckdb"
```

修改后需重启 Patroni 生效。

**2. duckdb.postgres_role 权限配置**

pg_duckdb 默认只允许 superuser 使用，非 superuser 需要配置 `duckdb.postgres_role` 指定允许的角色：

```yaml
duckdb_postgres_role: "dba"  # 仅支持单个角色名，不支持逗号分隔多角色
```

此参数通过 Patroni 的 `postgresql.parameters` 写入 PG 配置（`duckdb.postgres_role = "dba"`），Patroni 模板中对应：

```yaml
{% if duckdb_postgres_role is defined and duckdb_postgres_role %}
    duckdb.postgres_role: "{{ duckdb_postgres_role }}"
{% endif %}
```

> **注意**：`duckdb.postgres_role` 不支持逗号分隔多角色。配置 `"postgres,dba"` 会被当作一个不存在的角色名，导致所有非 superuser 都无法使用 DuckDB。

**3. 本地文件系统访问（read_csv 等）**

非 superuser 使用 `read_csv`、`read_parquet` 等本地文件读取功能，还需要 GRANT PostgreSQL 内置角色。

通过 `postgres_role_grants` 变量声明式配置（推荐，在 `pg_all.yaml` 中）：

```yaml
postgres_role_grants:
  - { user: dba, role: pg_read_server_files }
  - { user: dba, role: pg_write_server_files }
```

或直接以 superuser 执行：

```sql
GRANT pg_read_server_files TO dba;
GRANT pg_write_server_files TO dba;
```

> 不授予这两个角色，非 superuser 调用 `read_csv` 会报错：`Permission Error: File system LocalFileSystem has been disabled by configuration`。

**4. SQL 类型注意事项**

pg_duckdb 返回的数值类型是 `double precision`（FLOAT8），PG 的 `round()` 函数不支持 `(FLOAT8, integer)` 签名，需要先转为 `NUMERIC`：

```sql
-- 错误：round(double precision, integer) does not exist
SELECT round(avg(CAST(r['price'] AS FLOAT8)), 2) FROM read_csv('/data/file.csv') r;

-- 正确：转为 NUMERIC
SELECT round(avg(CAST(r['price'] AS NUMERIC)), 2) FROM read_csv('/data/file.csv') r;
```

**部署步骤**：

```bash
# 1. 更新 Patroni 配置（写入 shared_preload_libraries + duckdb.postgres_role）
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml -e HOSTS=pg-single -t patroni-config

# 2. 重启 Patroni 使预加载参数生效
ansible pg-single -i hosts.ini -b -a "supervisorctl restart patroni"

# 3. 安装扩展并启用（同时执行 initdb 授予 pg_read_server_files 等角色）
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml -e HOSTS=pg-single -t pg-extension,initdb -e pg_create_extensions=true
```

**验证**：

```sql
-- 使用 DuckDB 查询（dba 用户）
SELECT * FROM duckdb.query('SELECT 1 + 1 AS result');

-- 使用 DuckDB 读取 CSV 文件
SELECT count(*) FROM read_csv('/srv/pgsql/products.csv') r;

-- 运行测试 SQL（playbook 自动同步 test/ 目录到远程 /srv/pgsql/）
ansible-playbook -i hosts.ini playbooks/pgsql.yaml \
  -e HOSTS=pg-single -e pg_port=5432 -e pg_user=dba \
  -e pg_password=<password> -e pg_database=dev \
  -e sql_file=test_duckdb.sql
```

### pg_documentdb（DocumentDB - MongoDB 兼容）

pg_documentdb 是 Microsoft 开源的 MongoDB 兼容层，让 PostgreSQL 能够处理 MongoDB 协议和数据格式。需要多项额外配置：

**1. shared_preload_libraries 预加载**

在 `postgres_shared_preload_libraries` 中同时添加 `pg_documentdb_core` 和 `pg_documentdb`：

```yaml
postgres_shared_preload_libraries: "pg_cron,pg_stat_statements,uuid-ossp,pg_duckdb,pg_documentdb_core,pg_documentdb"
```

> **重要**：必须同时预加载 `pg_documentdb_core` 和 `pg_documentdb`，只加载 `pg_documentdb` 会导致 PG 启动失败。

修改后需重启 Patroni 生效。

**2. pg_hba trust 规则（自动配置）**

pg_documentdb 内部使用 libpq 回连 PG 执行操作，且会**自动覆盖连接字符串中的 `user` 为当前 session user**。Patroni 模板已自动添加以下 pg_hba 规则：

```yaml
- host all all 127.0.0.1/32 trust                       # documentdb 等扩展内部连接 localhost
- host all all {{ ansible_default_ipv4.address }}/32 trust  # documentdb 内部连接覆盖 user
```

同时 `postgresql.listen` 已包含 `127.0.0.1`，确保 PG 监听 localhost：

```yaml
postgresql:
  listen: "{{ ansible_default_ipv4.address }},127.0.0.1:5432"
```

> 这些规则在 Patroni 模板 `roles/patroni/templates/pg.yaml` 中自动配置。如果手动管理 pg_hba，需要确保添加对应的 trust 规则，否则 `documentdb_api.insert_one` 等调用会报错：`fe_sendauth: no password supplied` 或 `Connection refused`。

**3. 依赖扩展 rum**

pg_documentdb 依赖 `rum` 扩展（GIN 索引增强），需要先安装：

```yaml
pg_extensions:
  - "rum"           # pg_documentdb 依赖
  - "documentdb"    # DocumentDB
```

**4. 数据库限制**

pg_documentdb **只能**在 `postgres` 数据库中创建，不能在 `dev`、`prod` 等其他数据库中创建：

```yaml
pg_extensions_on:
  - { db: 'postgres', extension: 'documentdb', cascade: true }  # 必须用 postgres 库
```

> 在 `dev` 或 `prod` 库中执行 `CREATE EXTENSION documentdb` 会报错：`extension "documentdb" is not available for database "dev"`。

**5. 名称映射**

pg_documentdb 涉及多个名称，容易混淆：

| 场景 | 名称 | 说明 |
|------|------|------|
| apt 包名 | `postgresql-17-documentdb` | Pigsty 仓库提供 |
| pg_extensions 值 | `documentdb` | pig install 用 |
| .so 文件名 | `pg_documentdb.so` | shared_preload_libraries 中写 `pg_documentdb` |
| SQL 扩展名 | `documentdb` | CREATE EXTENSION 用 |
| Schema 名 | `documentdb_api` | API 函数所在 schema |

**6. API 使用说明**

pg_documentdb 提供 `documentdb_api` schema 下的函数，兼容 MongoDB API：

```sql
-- 创建集合（类似 MongoDB 的 collection）
SELECT documentdb_api.create_collection('mydb', 'products');

-- 插入文档（类似 MongoDB 的 insertOne）
SELECT documentdb_api.insert_one('mydb', 'products', '{
  "name": "iPhone 15 Pro",
  "category": "手机",
  "price": 8999,
  "tags": ["apple", "5g"]
}');

-- 查询所有文档
SELECT document FROM documentdb_api.collection('mydb', 'products');

-- 统计文档数量
SELECT count(*) FROM documentdb_api.collection('mydb', 'products');

-- 删除集合
SELECT documentdb_api.drop_collection('mydb', 'products');
```

> **注意**：当前版本（0.114-0）的 `documentdb_api.bson_match` 等查询函数可能不可用，建议使用基础 CRUD API。

**部署步骤**：

```bash
# 1. 更新 Patroni 配置（写入 shared_preload_libraries）
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml -e HOSTS=pg-single -t patroni-config

# 2. 重启 Patroni 使预加载参数生效
ansible pg-single -i hosts.ini -b -a "supervisorctl restart patroni"

# 3. 安装扩展并启用
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml -e HOSTS=pg-single -t pg-extension,initdb -e pg_create_extensions=true
```

**验证**：

```bash
# 运行 Python 测试脚本（使用 dba 用户通过 pgbouncer 5433 端口测试）
python3 sql/test_documentdb.py \
  -H 10.241.21.97 -p 5433 \
  -U dba -W <password> -d postgres
```

测试脚本会自动创建集合、插入 3 个文档、查询并清理，输出 PASS/FAIL 状态。

**已知限制**：

- 只能在 `postgres` 数据库中创建和使用
- 查询结果返回 BSON 类型（hex 格式），需要额外解析或转换
- `bson_match` 等高级查询 API 在当前版本（0.114-0）可能不可用
- 建议使用基础 CRUD API（`create_collection`, `insert_one`, `collection`, `drop_collection`）

### FerretDB（MongoDB Wire Protocol 代理）

FerretDB 是一个开源的 Go 语言 MongoDB 兼容代理，通过 MongoDB wire protocol 接收客户端请求，转换为 PostgreSQL SQL 执行。与 pg_documentdb（PG 扩展）配合使用，提供完整的 MongoDB 兼容体验。

| | FerretDB | pg_documentdb |
|---|---------|---------------|
| 类型 | 独立 Go 进程 | PG 扩展 |
| 协议 | MongoDB wire protocol | SQL 函数 API |
| 连接方式 | MongoDB 驱动直连 | `documentdb_api.*` SQL 调用 |
| 适用场景 | 迁移现有 MongoDB 应用 | 新应用，同时用关系型和文档型 |

**前置条件**

- pg_documentdb 扩展已安装并启用（FerretDB v2.x 依赖 documentdb 扩展）
- pgbouncer 已运行（FerretDB 通过 pgbouncer 连接 PG 后端）

**1. 多实例配置**

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

**2. hosts.ini 配置**

将需要部署 FerretDB 的主机加入 `[ferretdb]` 组：

```ini
[ferretdb]
pg-single
```

**3. 安装方式**

FerretDB 使用二进制下载 + supervisor 管理，与 pgdog 的部署模式一致：

- 二进制从 GitHub Releases 下载到 `/usr/local/bin/ferretdb`
- 每个实例由 supervisor 管理独立进程（`ferretdb-<name>`）
- 日志在 `/srv/ferretdb/<name>/logs/`

**部署步骤**：

```bash
# 部署 FerretDB
ansible-playbook -i hosts.ini playbooks/ferretdb.yaml -e HOSTS=ferretdb

# 重启实例（配置变更后）
ansible pg-single -i hosts.ini -b -a "supervisorctl restart ferretdb-app1"
```

**验证**：

```bash
# 使用 mongosh 连接
mongosh "mongodb://dba:<password>@10.241.21.97:27017/postgres"

# 运行 Python 测试脚本（需要 pymongo: uv add pymongo）
uv run python3 sql/test_ferretdb.py -H 10.241.21.97 -p 27017 -U dba -W <password>
uv run python3 sql/test_ferretdb.py -H 10.241.21.97 -p 27018 -U dba -W <password>

# 指定 MongoDB 逻辑数据库名（映射为 PG schema）
uv run python3 sql/test_ferretdb.py -H 10.241.21.97 -p 27017 -U dba -W <password> -s myapp
```

**架构**：

```
MongoDB 客户端 (pymongo/mongosh/...)
    │
    ├── port 27017 ──► ferretdb-app1 ──► pgbouncer:5433 ──► PostgreSQL (documentdb)
    │
    └── port 27018 ──► ferretdb-app2 ──► pgbouncer:5433 ──► PostgreSQL (documentdb)
```

**注意事项**：

- FerretDB v2.x **依赖** DocumentDB PG 扩展，必须先安装 pg_documentdb
- MongoDB 连接 URI 中的数据库名是逻辑名，FerretDB 会映射为 PG 中的不同 schema（数据隔离）
- PG 后端只能连 `postgres` 库（documentdb 扩展限制）
- 每个实例需要独立的 `listen_port` 和 `debug_port`
- 认证使用 MongoDB SCRAM 方式，用户名密码是 PG 用户

## 常见问题

### pig install 报 Package has no installation candidate

检查扩展来源仓库：

```bash
# 搜索 Pigsty 源
apt-cache search <package-name>

# 如果搜不到，可能需要 PGDG 源
# pg-extension role 已自动添加 PGDG 源
```

参考 https://ext.pigsty.io/list/pkg/ 查看扩展的 DEB 包名和来源仓库。
