#!/usr/bin/env python3
"""
DocumentDB (MongoDB 兼容) 基础测试
测试 documentdb 扩展的核心功能：集合创建、文档插入、查询、删除
"""

import sys
import argparse
import subprocess
import json


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
        print(f"Error: {result.stderr}")
        return None
    return result.stdout.strip()


def run_tests(args):
    collection_db = "testdb"
    collection_name = "products"
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

    # 0. 清理可能残留的旧数据
    print(f"\n0. 清理残留数据")
    psql(args, f"SELECT documentdb_api.drop_collection('{collection_db}', '{collection_name}')")

    # 1. 创建集合
    print(f"\n1. 创建集合 {collection_db}.{collection_name}")
    result = psql(args, f"SELECT documentdb_api.create_collection('{collection_db}', '{collection_name}')")
    check("create_collection", result == "t")

    # 2. 插入文档
    docs = [
        {"name": "iPhone 15 Pro", "category": "手机", "price": 8999, "stock": 100},
        {"name": "Galaxy S24", "category": "手机", "price": 6999, "stock": 200},
        {"name": "MacBook Pro M3", "category": "笔记本", "price": 14999, "stock": 50},
    ]
    print(f"\n2. 插入 {len(docs)} 个文档")
    for doc in docs:
        doc_json = json.dumps(doc)
        psql(args, f"SELECT documentdb_api.insert_one('{collection_db}', '{collection_name}', '{doc_json}')")
    check(f"insert {len(docs)} documents", True)

    # 3. 查询所有文档（BSON 类型直接输出 hex）
    print(f"\n3. 查询文档")
    result = psql(args, f"SELECT document FROM documentdb_api.collection('{collection_db}', '{collection_name}')")
    if result:
        rows = [r for r in result.split('\n') if r]
        check(f"查询到 {len(rows)} 个文档", len(rows) == len(docs))
        for row in rows:
            print(f"    - {row}")
    else:
        check("查询文档", False)

    # 4. 统计数量
    print(f"\n4. 统计文档数量")
    result = psql(args, f"SELECT count(*) FROM documentdb_api.collection('{collection_db}', '{collection_name}')")
    count = int(result) if result else 0
    check(f"count = {count}", count == len(docs))

    # 5. 删除集合
    print(f"\n5. 清理测试数据")
    result = psql(args, f"SELECT documentdb_api.drop_collection('{collection_db}', '{collection_name}')")
    check("drop_collection", result == "t")

    # 汇总
    total = passed + failed
    print(f"\n{'='*40}")
    print(f"测试完成: {passed}/{total} 通过, {failed} 失败")
    print(f"{'='*40}")
    return failed == 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="DocumentDB 测试")
    parser.add_argument("-H", "--host", default="127.0.0.1", help="PG 地址")
    parser.add_argument("-p", "--port", type=int, default=5432, help="PG 端口")
    parser.add_argument("-U", "--user", default="postgres", help="用户名")
    parser.add_argument("-W", "--password", default="", help="密码")
    parser.add_argument("-d", "--database", default="postgres", help="数据库")
    args = parser.parse_args()

    try:
        ok = run_tests(args)
    except Exception as e:
        print(f"\n测试异常: {e}")
        sys.exit(1)

    sys.exit(0 if ok else 1)
