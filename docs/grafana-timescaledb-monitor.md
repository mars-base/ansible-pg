# Grafana + TimescaleDB 监控面板（测试）

测试在 Grafana 中使用 TimescaleDB 作为数据源，构建游戏区服在线人数的实时监控面板。

面板 JSON 配置：[grafana-timescaledb-monitor.json](grafana-timescaledb-monitor.json)

## 数据源

- **Name**: pg-single-tsdb
- **Type**: grafana-postgresql-datasource (PostgreSQL)
- **UID**: efvph8gdzdtz4a
- **Host**: <pg-host>:5433 (pgbouncer)
- **Database**: tsdb
- **User**: dba
- **TimescaleDB**: enabled

## 数据表

```sql
CREATE TABLE game_server_online (
    time         TIMESTAMPTZ NOT NULL,
    server_id    TEXT NOT NULL,
    region       TEXT NOT NULL,
    online_count INTEGER NOT NULL
);

SELECT create_hypertable('game_server_online', by_range('time'), if_not_exists => true);

CREATE INDEX idx_game_server_online_server ON game_server_online (server_id, time DESC);
CREATE INDEX idx_game_server_online_region ON game_server_online (region, time DESC);
```

## 采样脚本

`scripts/sample_online.py` — 后台运行，每 5 秒写入 8 个区服数据：

```bash
# 启动
PGPASSWORD='xxx' PYTHONUNBUFFERED=1 nohup python3 scripts/sample_online.py > /tmp/sample_online.log 2>&1 &

# 停止
kill <PID>

# 查看日志
tail -f /tmp/sample_online.log
```
