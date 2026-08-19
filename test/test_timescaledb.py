#!/usr/bin/env python3
"""
TimescaleDB 时序数据库基础测试
测试 hypertable 创建、数据插入、time_bucket 聚合、连续聚合、retention policy 等核心功能
"""

import sys
import argparse
import subprocess
import time


def psql(args, query):
    cmd = [
        "psql",
        "-h", args.host,
        "-p", str(args.port),
        "-U", args.user,
        "-d", args.database,
        "-t", "-A",
        "-c", query,
    ]
    env = {"PGPASSWORD": args.password}
    result = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        print(f"  SQL Error: {result.stderr.strip()}")
        return None
    return result.stdout.strip()


def psql_exec(args, query):
    """执行不返回结果的语句"""
    result = psql(args, query)
    return result is not None


def run_tests(args):
    table_name = "test_conditions"
    passed = 0
    failed = 0

    def check(desc, ok):
        nonlocal passed, failed
        status = "PASS" if ok else "FAIL"
        if ok:
            passed += 1
        else:
            failed += 1
        print(f"  [{status}] {desc}")

    # 0. 清理残留数据
    print(f"\n0. 清理残留数据")
    psql_exec(args, f"DROP TABLE IF EXISTS {table_name} CASCADE")

    # 1. 验证 TimescaleDB 扩展已加载
    print(f"\n1. 检查 TimescaleDB 扩展")
    result = psql(args, "SELECT extversion FROM pg_extension WHERE extname = 'timescaledb'")
    check(f"TimescaleDB 版本: {result}", result is not None and len(result) > 0)

    # 2. 创建时序表
    print(f"\n2. 创建时序表 {table_name}")
    ok = psql_exec(args, f"""
        CREATE TABLE {table_name} (
            time TIMESTAMPTZ NOT NULL,
            device_id INTEGER NOT NULL,
            temperature DOUBLE PRECISION,
            humidity DOUBLE PRECISION
        )
    """)
    check("CREATE TABLE", ok)

    # 3. 转换为 hypertable
    print(f"\n3. 创建 hypertable")
    ok = psql_exec(args, f"SELECT create_hypertable('{table_name}', by_range('time'))")
    check("create_hypertable", ok)

    # 4. 插入时序数据
    print(f"\n4. 插入时序数据")
    ok = psql_exec(args, f"""
        INSERT INTO {table_name} (time, device_id, temperature, humidity) VALUES
            (now() - INTERVAL '4h', 1, 22.5, 45.0),
            (now() - INTERVAL '3h', 1, 23.1, 44.5),
            (now() - INTERVAL '2h', 1, 24.0, 43.2),
            (now() - INTERVAL '1h', 1, 23.8, 44.1),
            (now(),                  1, 24.2, 43.8),
            (now() - INTERVAL '4h', 2, 19.8, 55.0),
            (now() - INTERVAL '3h', 2, 20.1, 54.2),
            (now() - INTERVAL '2h', 2, 20.5, 53.8),
            (now() - INTERVAL '1h', 2, 21.0, 53.0),
            (now(),                  2, 21.3, 52.5)
    """)
    check("INSERT 10 行", ok)

    # 5. 验证数据量
    print(f"\n5. 验证数据量")
    result = psql(args, f"SELECT count(*) FROM {table_name}")
    count = int(result) if result else 0
    check(f"count = {count}", count == 10)

    # 6. time_bucket 聚合查询
    print(f"\n6. time_bucket 聚合查询（按 2 小时分组）")
    result = psql(args, f"""
        SELECT time_bucket('2h', time) AS bucket,
               device_id,
               round(avg(temperature)::numeric, 1) AS avg_temp,
               count(*) AS cnt
        FROM {table_name}
        GROUP BY bucket, device_id
        ORDER BY bucket, device_id
    """)
    if result:
        rows = [r for r in result.split('\n') if r]
        check(f"聚合返回 {len(rows)} 行", len(rows) >= 2)
        for row in rows:
            print(f"    {row}")
    else:
        check("time_bucket 聚合", False)

    # 7. 按设备统计
    print(f"\n7. 按设备统计平均温度")
    result = psql(args, f"""
        SELECT device_id,
               round(avg(temperature)::numeric, 1) AS avg_temp,
               round(min(temperature)::numeric, 1) AS min_temp,
               round(max(temperature)::numeric, 1) AS max_temp
        FROM {table_name}
        GROUP BY device_id
        ORDER BY device_id
    """)
    if result:
        rows = [r for r in result.split('\n') if r]
        check(f"设备统计: {len(rows)} 个设备", len(rows) == 2)
        for row in rows:
            print(f"    device_id={row}")
    else:
        check("设备统计", False)

    # 8. 最近值查询
    print(f"\n8. 最近数据查询")
    result = psql(args, f"""
        SELECT device_id, temperature, time
        FROM {table_name}
        ORDER BY time DESC
        LIMIT 1
    """)
    check("最近一条记录", result is not None and len(result) > 0)
    if result:
        print(f"    {result}")

    # 9. 清理测试数据
    print(f"\n9. 清理测试数据")
    ok = psql_exec(args, f"DROP TABLE IF EXISTS {table_name} CASCADE")
    check("DROP TABLE", ok)

    # 汇总
    total = passed + failed
    print(f"\n{'='*40}")
    print(f"测试完成: {passed}/{total} 通过, {failed} 失败")
    print(f"{'='*40}")
    return failed == 0


def run_retention_test(args):
    """测试 Retention Policy 自动清理过期数据"""
    rp_table = "test_rp"
    # retention 保留时长（秒）
    rp_seconds = args.rp_seconds
    # chunk 间隔设短一些，确保旧数据落在独立 chunk 中
    chunk_interval_sec = max(rp_seconds // 4, 10)
    # 旧数据的时间偏移（秒），要远大于 rp_seconds
    old_offset = rp_seconds * 3

    passed = 0
    failed = 0

    def check(desc, ok):
        nonlocal passed, failed
        status = "PASS" if ok else "FAIL"
        if ok:
            passed += 1
        else:
            failed += 1
        print(f"  [{status}] {desc}")

    print(f"\n{'='*50}")
    print(f"Retention Policy 测试（保留 {rp_seconds}s，chunk 间隔 {chunk_interval_sec}s）")
    print(f"{'='*50}")

    # 0. 清理残留
    print(f"\n0. 清理残留数据")
    psql_exec(args, f"DROP TABLE IF EXISTS {rp_table} CASCADE")

    # 1. 创建表 + hypertable（短 chunk 间隔）
    print(f"\n1. 创建 hypertable（chunk_time_interval = {chunk_interval_sec}s）")
    ok = psql_exec(args, f"""
        CREATE TABLE {rp_table} (
            time TIMESTAMPTZ NOT NULL,
            device_id INTEGER NOT NULL,
            temperature DOUBLE PRECISION
        )
    """)
    check("CREATE TABLE", ok)

    ok = psql_exec(args, f"""
        SELECT create_hypertable('{rp_table}',
            by_range('time', INTERVAL '{chunk_interval_sec} seconds'))
    """)
    check("create_hypertable", ok)

    # 2. 插入旧数据和新数据
    print(f"\n2. 插入数据（旧: {old_offset}s 前, 新: 当前时间）")
    ok = psql_exec(args, f"""
        INSERT INTO {rp_table} (time, device_id, temperature) VALUES
            (now() - INTERVAL '{old_offset} seconds', 1, 10.0),
            (now() - INTERVAL '{old_offset - 5} seconds', 1, 11.0),
            (now() - INTERVAL '{old_offset - 10} seconds', 2, 20.0),
            (now(), 1, 30.0),
            (now() - INTERVAL '2 seconds', 2, 25.0)
    """)
    check("INSERT 5 行（3 旧 + 2 新）", ok)

    # 3. 验证数据量
    print(f"\n3. 验证数据量")
    result = psql(args, f"SELECT count(*) FROM {rp_table}")
    count = int(result) if result else 0
    check(f"count = {count}（期望 5）", count == 5)

    # 4. 查看 chunk 分布
    print(f"\n4. 查看 chunk 分布")
    result = psql(args, f"""
        SELECT chunk_name, range_start, range_end
        FROM timescaledb_information.chunks
        WHERE hypertable_name = '{rp_table}'
        ORDER BY range_start
    """)
    if result:
        rows = [r for r in result.split('\n') if r]
        print(f"    chunk 数量: {len(rows)}")
        for row in rows:
            print(f"    {row}")
        check(f"至少 2 个 chunk（新旧分离）", len(rows) >= 2)
    else:
        check("查看 chunk", False)

    # 5. 添加 retention policy（返回值就是 job_id）
    print(f"\n5. 添加 retention policy（保留 {rp_seconds}s）")
    result = psql(args, f"""
        SELECT add_retention_policy('{rp_table}',
            INTERVAL '{rp_seconds} seconds',
            if_not_exists => true)
    """)
    job_id = result if result else None
    check(f"add_retention_policy, job_id={job_id}", job_id is not None and len(job_id) > 0)

    # 6. 查看 policy 信息
    print(f"\n6. 查看 retention job")
    if job_id:
        result = psql(args, f"""
            SELECT job_id, proc_name, schedule_interval, config
            FROM timescaledb_information.jobs
            WHERE job_id = {job_id}
        """)
        if result:
            print(f"    {result}")
            check("retention job 存在", True)
        else:
            check("查看 retention job", False)
    else:
        check("查看 retention job（无 job_id）", False)

    # 7. 手动触发 retention job（不用等后台调度）
    if job_id:
        print(f"\n7. 手动触发 retention job {job_id}")
        ok = psql_exec(args, f"CALL run_job({job_id})")
        check("run_job 执行成功", ok)

        # 8. 验证旧数据已被清理
        print(f"\n8. 验证清理结果")
        result = psql(args, f"SELECT count(*) FROM {rp_table}")
        count = int(result) if result else -1
        check(f"count = {count}（期望 2，旧 3 行已删除）", count == 2)

        # 9. 验证只保留新数据
        print(f"\n9. 验证保留的数据都是新数据")
        result = psql(args, f"""
            SELECT device_id, temperature,
                   round(extract(epoch from now() - time))::int AS seconds_ago
            FROM {rp_table}
            ORDER BY time
        """)
        if result:
            rows = [r for r in result.split('\n') if r]
            check(f"保留 {len(rows)} 行", len(rows) == 2)
            for row in rows:
                print(f"    {row}（秒前）")
        else:
            check("查询保留数据", False)
    else:
        print(f"\n7-9. 跳过（无法获取 job_id）")

    # 10. 清理
    print(f"\n10. 清理测试数据")
    psql_exec(args, f"""
        SELECT remove_retention_policy('{rp_table}', if_exists => true)
    """)
    ok = psql_exec(args, f"DROP TABLE IF EXISTS {rp_table} CASCADE")
    check("DROP TABLE", ok)

    # 汇总
    total = passed + failed
    print(f"\n{'='*50}")
    print(f"Retention Policy 测试完成: {passed}/{total} 通过, {failed} 失败")
    print(f"{'='*50}")
    return failed == 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="TimescaleDB 测试")
    parser.add_argument("-H", "--host", default="127.0.0.1", help="PG 地址")
    parser.add_argument("-p", "--port", type=int, default=5433, help="PG 端口（默认 pgbouncer 5433）")
    parser.add_argument("-U", "--user", default="dba", help="用户名")
    parser.add_argument("-W", "--password", default="", help="密码")
    parser.add_argument("-d", "--database", default="tsdb", help="数据库（默认 tsdb）")
    parser.add_argument("--retention", action="store_true", help="运行 Retention Policy 测试")
    parser.add_argument("--rp-seconds", type=int, default=30,
                        help="Retention 保留时长（秒），默认 30s，用于 --retention 测试")
    parser.add_argument("--all", action="store_true", help="运行所有测试（基础 + retention）")
    args = parser.parse_args()

    try:
        results = []

        if not args.retention:
            # 默认运行基础测试
            results.append(("基础测试", run_tests(args)))

        if args.retention or args.all:
            results.append(("Retention Policy", run_retention_test(args)))

        if args.all and not args.retention:
            # --all 时基础测试已经跑过了
            pass

        # 总汇总
        if len(results) > 1:
            all_pass = all(r for _, r in results)
            print(f"\n{'#'*50}")
            for name, ok in results:
                print(f"  {'PASS' if ok else 'FAIL'}: {name}")
            print(f"{'#'*50}")
            sys.exit(0 if all_pass else 1)
        else:
            sys.exit(0 if results[0][1] else 1)

    except Exception as e:
        print(f"\n测试异常: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
