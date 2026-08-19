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
| timescaledb | 2.29.1 | Pigsty | tsdb | 时序数据库，需 shared_preload_libraries，不能与 pg_duckdb 同库 |
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

## 添加新扩展步骤

安装新扩展需要修改 `group_vars` 配置，按以下步骤执行：

### 普通扩展（无需预加载）

只需安装扩展包并在指定库创建：

```bash
# 1. 编辑 group_vars/<group>/pg_all.yaml，添加扩展配置
#    pg_extensions: 添加 apt 包标识
#    pg_extensions_on: 添加 SQL 扩展名和目标库

# 2. 安装扩展包 + 在指定库 CREATE EXTENSION（幂等）
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
  -e HOSTS=pg-single -t pg-extension,initdb -e pg_create_extensions=true
```

### 需要预加载的扩展（shared_preload_libraries）

部分扩展（pg_duckdb、pg_documentdb、timescaledb 等）需要预加载 .so 文件，必须重启 PG 才能生效：

```bash
# 1. 编辑 group_vars/<group>/pg_all.yaml，添加扩展配置：
#    - postgres_shared_preload_libraries: 添加 .so 名称
#    - pg_extensions: 添加 apt 包标识
#    - pg_extensions_on: 添加 SQL 扩展名和目标库
#    - postgres_dbs: 如需新数据库，添加到列表
#    - postgres_privs: 按需配置用户权限

# 2. 更新 Patroni 配置（写入 shared_preload_libraries）
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
  -e HOSTS=pg-single -t patroni-config

# 3. 重启 Patroni 使预加载参数生效
ansible pg-single -i hosts.ini -b -a "supervisorctl restart patroni"

# 4. 安装扩展包 + 创建库 + CREATE EXTENSION（幂等）
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
  -e HOSTS=pg-single -t pg-extension,initdb -e pg_create_extensions=true
```

> **注意**：`pg-extension` tag 负责安装 apt 包和执行 `CREATE EXTENSION`（需要 `-e pg_create_extensions=true`）。`initdb` tag 负责创建数据库和用户权限。两者必须同时使用。

### 扩展冲突与隔离

部分扩展之间存在函数签名冲突，不能安装在同一数据库中，需要独立库隔离：

| 扩展 A | 扩展 B | 冲突函数 | 解决方案 |
|--------|--------|----------|----------|
| pg_duckdb | timescaledb | `time_bucket(interval, date)` 等 | 分别装在独立库（dev/prod vs tsdb） |

> 规划扩展安装时，先查阅扩展文档确认是否有函数名冲突。冲突时创建独立数据库是通用解决方案。

## 扩展详细文档

部分扩展除安装外，还需要在 `group_vars` 中配置额外参数。详细文档见 `docs/extensions/` 目录：

| 扩展 | 文档 | 说明 |
|------|------|------|
| pg_duckdb | [pg-duckdb.md](extensions/pg-duckdb.md) | DuckDB 嵌入式 OLAP（权限、文件系统访问、SQL 类型注意事项） |
| pg_documentdb | [pg-documentdb.md](extensions/pg-documentdb.md) | DocumentDB MongoDB 兼容（预加载、pg_hba、rum 依赖、权限配置） |
| FerretDB | [ferretdb.md](extensions/ferretdb.md) | MongoDB wire protocol 代理（多实例配置、独立剧本部署） |
| TimescaleDB | [timescaledb.md](extensions/timescaledb.md) | 时序数据库（独立库避免 pg_duckdb 冲突） |

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
