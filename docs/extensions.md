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

| 扩展 | 版本 | 来源 | 数据库 |
|------|------|------|--------|
| pg_cron | 1.6.7 | PGDG | postgres |
| uuid-ossp | 内置 | contrib | dev, prod |
| pg_stat_statements | 1.18 | contrib | dev, prod |
| pgmq | 1.5.1 | Pigsty | dev, prod |
| pgvector (vector) | 0.8.6 | PGDG | dev, prod |

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

> 更多扩展见 https://ext.pigsty.io/list/pkg/

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
