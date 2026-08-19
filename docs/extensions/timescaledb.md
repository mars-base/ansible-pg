# TimescaleDB（时序数据库）

TimescaleDB 是 PostgreSQL 的时序数据库扩展，提供 hypertable、time_bucket 等时序优化功能，适用于 IoT、监控、日志分析等场景。

## 配置要求

### 1. shared_preload_libraries 预加载

在 `postgres_shared_preload_libraries` 中添加 `timescaledb`：

```yaml
postgres_shared_preload_libraries: "pg_cron,pg_stat_statements,uuid-ossp,pg_duckdb,pg_documentdb_core,pg_documentdb,timescaledb"
```

修改后需重启 Patroni 生效。

### 2. 独立数据库（避免冲突）

TimescaleDB 与 pg_duckdb 存在函数签名冲突（`time_bucket(interval, date)` 等），**不能安装在同一数据库**。需要创建独立数据库（如 `tsdb`）：

```yaml
postgres_dbs:
  - tsdb   # TimescaleDB 独立库

postgres_privs:
  - db: tsdb
    user: dba
    type: database
    priv: ALL
    schema: public
    schema_priv: CREATE,USAGE

pg_extensions_on:
  - { db: 'tsdb', extension: 'timescaledb' }
```

### 3. 扩展安装

```yaml
pg_extensions:
  - "timescaledb"  # Pigsty 源
```

## 部署步骤

```bash
# 1. 更新 Patroni 配置（写入 shared_preload_libraries）
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml -e HOSTS=pg-single -t patroni-config

# 2. 重启 Patroni 使预加载参数生效
ansible pg-single -i hosts.ini -b -a "supervisorctl restart patroni"

# 3. 安装扩展包 + 创建 tsdb 库 + CREATE EXTENSION（幂等）
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
  -e HOSTS=pg-single -t pg-extension,initdb -e pg_create_extensions=true
```

## 验证

```sql
-- 连接 tsdb 数据库
\c tsdb

-- 查看 TimescaleDB 版本
SELECT default_version, installed_version FROM pg_available_extensions WHERE name = 'timescaledb';

-- 创建 hypertable 测试
CREATE TABLE conditions (
  time TIMESTAMPTZ NOT NULL,
  device_id INTEGER,
  temperature DOUBLE PRECISION
);

SELECT create_hypertable('conditions', by_range('time'));

-- 插入测试数据
INSERT INTO conditions (time, device_id, temperature)
VALUES (now(), 1, 23.5), (now() - INTERVAL '1h', 2, 19.8);

-- 使用 time_bucket 聚合查询
SELECT time_bucket('1h', time) AS bucket, device_id, avg(temperature)
FROM conditions
GROUP BY bucket, device_id
ORDER BY bucket;
```

## 冲突说明

| 冲突扩展 | 冲突函数 | 解决方案 |
|----------|----------|----------|
| pg_duckdb | `time_bucket(interval, date)` 等 | 分别装在独立库（dev/prod vs tsdb） |

> 如果不需要 pg_duckdb，可以直接在 dev/prod 库中安装 timescaledb。冲突只在两者共存时发生。
