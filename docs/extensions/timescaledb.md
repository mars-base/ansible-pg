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

### 测试脚本（推荐）

```bash
# 基础测试（hypertable、time_bucket 聚合、按设备统计等）
python3 test/test_timescaledb.py -H 10.241.21.97 -p 5433 -U dba -W <password> -d tsdb

# Retention Policy 测试（默认保留 30s，验证自动清理）
python3 test/test_timescaledb.py -H 10.241.21.97 -p 5433 -U dba -W <password> -d tsdb --retention

# 自定义保留时长（如 60s）
python3 test/test_timescaledb.py -H 10.241.21.97 -p 5433 -U dba -W <password> -d tsdb --retention --rp-seconds 60

# 全部测试（基础 + retention）
python3 test/test_timescaledb.py -H 10.241.21.97 -p 5433 -U dba -W <password> -d tsdb --all
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-H` | PG 地址 | `127.0.0.1` |
| `-p` | PG 端口 | `5433`（pgbouncer） |
| `-U` | 用户名 | `dba` |
| `-W` | 密码 | 空 |
| `-d` | 数据库 | `tsdb` |
| `--retention` | 运行 Retention Policy 测试 | 不运行 |
| `--rp-seconds` | 保留时长（秒） | `30` |
| `--all` | 运行全部测试 | 不运行 |

### 手动 SQL 验证

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

-- Retention Policy：只保留最近 30 天数据
SELECT add_retention_policy('conditions', INTERVAL '30 days');

-- 查看所有后台 job
SELECT job_id, proc_name, schedule_interval FROM timescaledb_information.jobs;

-- 手动触发清理
CALL run_job(<job_id>);
```

## Retention Policy（数据保留策略）

设置时间窗口，超出窗口的数据自动按 chunk 粒度删除（DROP chunk，非逐行 DELETE）：

```sql
-- 保留最近 30 天
SELECT add_retention_policy('conditions', INTERVAL '30 days');

-- 保留最近 7 天
SELECT add_retention_policy('conditions', INTERVAL '7 days');

-- 移除策略
SELECT remove_retention_policy('conditions');

-- 更新策略：必须先移除再重建（重复 add 会报错，if_not_exists => true 不会更新）
SELECT remove_retention_policy('conditions');
SELECT add_retention_policy('conditions', INTERVAL '7 days');
```

> Retention job 默认每天执行一次（`schedule_interval = 1 day`）。可通过 `CALL run_job(<job_id>)` 手动触发。

## 冲突说明

| 冲突扩展 | 冲突函数 | 解决方案 |
|----------|----------|----------|
| pg_duckdb | `time_bucket(interval, date)` 等 | 分别装在独立库（dev/prod vs tsdb） |

> 如果不需要 pg_duckdb，可以直接在 dev/prod 库中安装 timescaledb。冲突只在两者共存时发生。

## 与 InfluxDB 对比

### 数据模型差异

InfluxDB 强制区分 tag / field，TimescaleDB 就是标准关系表，所有列地位平等：

```
# InfluxDB
measurement: conditions
tags:        device_id, location    # 元数据，自动建索引，只能存字符串
fields:      temperature, humidity  # 实际数值，不建索引

# TimescaleDB
CREATE TABLE conditions (
    time        TIMESTAMPTZ NOT NULL,
    device_id   INTEGER,            # 想做 tag？自己建索引
    location    TEXT,               # 想做 tag？自己建索引
    temperature DOUBLE PRECISION,
    humidity    DOUBLE PRECISION
);
```

模拟 InfluxDB tag 效果，对过滤/分组列手动建索引：

```sql
CREATE INDEX ON conditions (device_id, time DESC);
CREATE INDEX ON conditions (location, time DESC);
```

### 功能对比

| | TimescaleDB | InfluxDB |
|---|---|---|
| 底层 | PostgreSQL 扩展 | 独立时序数据库 |
| 查询语言 | SQL | InfluxQL / Flux |
| 数据模型 | 标准关系表，列地位平等 | tag/field 强制区分 |
| 索引 | 手动建（time 自动） | tag 自动建，field 不支持 |
| JOIN | 支持（与其他 PG 表关联） | 不支持 |
| 写入协议 | PostgreSQL（push） | HTTP line protocol（push） |
| 数据保留 | `add_retention_policy` | retention policy（内置） |
| 清理粒度 | chunk 级 DROP | shard 级 DROP |
| 降采样 | Continuous Aggregates | Continuous Queries |
| Grafana | 直接用 PostgreSQL 数据源 | 需要 InfluxDB 数据源 |
| 运维 | 复用 PG 基础设施 | 独立部署维护 |
| 写入性能 | 万级/秒 | 十万级/秒 |
| 存储规模 | TB 级 | TB 级 |

### 适用场景

**选 TimescaleDB**：
- 已有 PG 基础设施，不想引入新组件
- 时序数据需要和业务表 JOIN
- 团队熟悉 SQL，不想学 InfluxQL/Flux
- 数据量在 TB 以内，写入压力不大

**选 InfluxDB**：
- 写入量极大（每秒十万级以上）
- 需要极致压缩比（line protocol 编码更紧凑）
- 纯监控场景，不需要和业务表关联
