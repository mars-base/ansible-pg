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

非 superuser 使用 `read_csv`、`read_parquet` 等本地文件读取功能，还需要 GRANT PostgreSQL 内置角色：

```sql
-- 以 superuser (postgres) 执行
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

# 3. 安装扩展并启用
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml -e HOSTS=pg-single -t pg-extension -e pg_create_extensions=true

# 4. 授予文件系统访问权限（以 superuser 执行）
PGPASSWORD='***' psql -h <host> -p 5432 -U postgres -d <db> \
  -c "GRANT pg_read_server_files TO dba; GRANT pg_write_server_files TO dba;"
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
