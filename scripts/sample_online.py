#!/usr/bin/env python3
"""
游戏服在线人数实时采样脚本
每 5 秒写入一批模拟数据到 game_server_online 表
后台运行: nohup python3 sample_online.py > /dev/null 2>&1 &
"""

import os
import time
import random
import psycopg2
from datetime import datetime, timezone

# 连接参数
PG_HOST = os.getenv("PGHOST", "10.241.21.97")
PG_PORT = os.getenv("PGPORT", "5433")
PG_USER = os.getenv("PGUSER", "dba")
PG_PASS = os.getenv("PGPASSWORD", "CHANGEME")
PG_DB = os.getenv("PGDATABASE", "tsdb")

# 区服配置
SERVERS = [
    ("s1", "华东"), ("s2", "华东"),
    ("s3", "华南"), ("s4", "华南"),
    ("s5", "华北"), ("s6", "华北"),
    ("s7", "西南"), ("s8", "西南"),
]

# 每个服的基础在线人数
BASE_ONLINE = {
    "s1": 3500, "s2": 2800,
    "s3": 3200, "s4": 2600,
    "s5": 3000, "s6": 2400,
    "s7": 2200, "s8": 1800,
}

INSERT_SQL = """
INSERT INTO game_server_online (time, server_id, region, online_count)
VALUES (%s, %s, %s, %s)
"""

INTERVAL = 5  # 采样间隔（秒）


def generate_data():
    """生成一批采样数据，围绕基准值小幅波动"""
    now = datetime.now(timezone.utc)
    rows = []
    for server_id, region in SERVERS:
        base = BASE_ONLINE[server_id]
        # 在基准值 ±3% 内波动，保持平稳
        online = int(base * random.uniform(0.97, 1.03))
        rows.append((now, server_id, region, online))
    return rows


def main():
    print(f"连接 {PG_HOST}:{PG_PORT}/{PG_DB} ...")
    conn = psycopg2.connect(host=PG_HOST, port=PG_PORT, user=PG_USER, password=PG_PASS, dbname=PG_DB)
    conn.autocommit = True
    cur = conn.cursor()
    print(f"采样开始，间隔 {INTERVAL}s，Ctrl+C 停止")

    count = 0
    while True:
        rows = generate_data()
        cur.executemany(INSERT_SQL, rows)
        count += len(rows)
        total_online = sum(r[3] for r in rows)
        ts = datetime.now().strftime("%H:%M:%S")
        print(f"[{ts}] 写入 {len(rows)} 条，总在线 {total_online}，累计 {count}")
        time.sleep(INTERVAL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n采样停止")
    except Exception as e:
        print(f"错误: {e}")
