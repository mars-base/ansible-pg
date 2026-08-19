# pg_duckdb（DuckDB 嵌入式 OLAP）

pg_duckdb 将 DuckDB 的分析引擎嵌入 PostgreSQL，支持直接查询 Parquet/CSV 文件、高性能 OLAP 分析。

## 配置要求

### 1. shared_preload_libraries 预加载

在 `postgres_shared_preload_libraries` 中添加 `pg_duckdb`：

```yaml
postgres_shared_preload_libraries: "pg_cron,pg_stat_statements,uuid-ossp,pg_duckdb"
```

修改后需重启 Patroni 生效。

### 2. duckdb.postgres_role 权限配置

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

### 3. 本地文件系统访问（read_csv 等）

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

### 4. SQL 类型注意事项

pg_duckdb 返回的数值类型是 `double precision`（FLOAT8），PG 的 `round()` 函数不支持 `(FLOAT8, integer)` 签名，需要先转为 `NUMERIC`：

```sql
-- 错误：round(double precision, integer) does not exist
SELECT round(avg(CAST(r['price'] AS FLOAT8)), 2) FROM read_csv('/data/file.csv') r;

-- 正确：转为 NUMERIC
SELECT round(avg(CAST(r['price'] AS NUMERIC)), 2) FROM read_csv('/data/file.csv') r;
```

## 部署步骤

```bash
# 1. 更新 Patroni 配置（写入 shared_preload_libraries + duckdb.postgres_role）
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml -e HOSTS=pg-single -t patroni-config

# 2. 重启 Patroni 使预加载参数生效
ansible pg-single -i hosts.ini -b -a "supervisorctl restart patroni"

# 3. 安装扩展并启用（同时执行 initdb 授予 pg_read_server_files 等角色）
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml -e HOSTS=pg-single -t pg-extension,initdb -e pg_create_extensions=true
```

## 验证

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

## 冲突与隔离

pg_duckdb 与 timescaledb 存在函数签名冲突（`time_bucket(interval, date)` 等），**不能安装在同一数据库**。需要在独立数据库（如 `tsdb`）中安装 timescaledb。
