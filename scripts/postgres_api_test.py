#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
@Time    :   2026/03/13 15:36:12
@Author  :   ansible-pg
'''


"""
PostgreSQL 健康检查脚本
功能：
- 检查 PostgreSQL 连接
- 检查 PostgreSQL 写入能力
- 检查 PostgreSQL 查询能力
- 提供健康状态报告

增加 Postgrest API 测试功能：
- 连接到 Postgrest API
- 测试 API 读写功能
- 验证 API 响应正确性
"""

from http import client

import psycopg2
from psycopg2 import OperationalError, DatabaseError
import argparse
import sys
import time
from datetime import datetime
import requests

class PostgreSQLHealthChecker:
    def __init__(self, host='localhost', port=5432, user='postgres', password='', database=None):
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database
        self.connection = None

    def connect(self):
        """建立 PostgreSQL 连接"""
        try:
            connection_config = {
                'host': self.host,
                'port': self.port,
                'user': self.user,
                'password': self.password,
                'connect_timeout': 10,
            }

            if self.database:
                connection_config['database'] = self.database

            self.connection = psycopg2.connect(**connection_config)
            return True
        except (OperationalError, DatabaseError) as e:
            print(f"连接 PostgreSQL 失败: {e}")
            return False

    def disconnect(self):
        """关闭 PostgreSQL 连接"""
        if self.connection:
            self.connection.close()

    def test_connection(self):
        """测试连接"""
        if self.connect():
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ✓ 连接测试成功")
            return True
        else:
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ✗ 连接测试失败")
            return False

    def test_write(self):
        """测试写入功能"""
        try:
            if not self.connection:
                if not self.connect():
                    return False

            cursor = self.connection.cursor()

            # 创建测试表（如果不存在）
            create_table_query = """
            CREATE TABLE IF NOT EXISTS health_check_test (
                id SERIAL PRIMARY KEY,
                test_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                test_data VARCHAR(100)
            );
            """
            cursor.execute(create_table_query)

            # 插入测试数据
            insert_query = "INSERT INTO health_check_test (test_data) VALUES (%s);"
            cursor.execute(insert_query, (f"Health check at {datetime.now()}",))
            self.connection.commit()

            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ✓ 写入测试成功")
            cursor.close()
            return True
        except (OperationalError, DatabaseError) as e:
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ✗ 写入测试失败: {e}")
            return False

    def test_read(self):
        """测试读取功能"""
        try:
            if not self.connection:
                if not self.connect():
                    return False

            cursor = self.connection.cursor()

            # 查询最新插入的数据
            select_query = "SELECT id, test_time, test_data FROM health_check_test ORDER BY id DESC LIMIT 1;"
            cursor.execute(select_query)
            result = cursor.fetchone()

            if result:
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ✓ 查询测试成功")
                print(f"   最新记录: ID={result[0]}, 时间={result[1]}, 数据='{result[2]}'")
            else:
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ⚠ 查询测试 - 表中无数据")

            cursor.close()
            return True
        except (OperationalError, DatabaseError) as e:
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ✗ 查询测试失败: {e}")
            return False

    def cleanup_test_data(self):
        """清理测试数据（保留最近10条记录）"""
        try:
            if not self.connection:
                if not self.connect():
                    return False

            cursor = self.connection.cursor()

            # 删除较旧的测试记录，只保留最新的10条
            delete_query = """
            DELETE FROM health_check_test
            WHERE id NOT IN (
                SELECT id FROM (
                    SELECT id FROM health_check_test
                    ORDER BY id DESC
                    LIMIT 10
                ) AS temp
            );
            """
            cursor.execute(delete_query)
            affected_rows = cursor.rowcount
            self.connection.commit()

            if affected_rows > 0:
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 清理了 {affected_rows} 条旧测试数据")

            cursor.close()
            return True
        except (OperationalError, DatabaseError) as e:
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 清理测试数据失败: {e}")
            return False

    def run_full_check(self):
        """运行完整检查"""
        print("=" * 50)
        print(f"PostgreSQL 健康检查开始 - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"目标: {self.host}:{self.port}")
        print(f"用户: {self.user}")
        if self.database:
            print(f"数据库: {self.database}")
        print("=" * 50)

        results = {}

        # 测试连接
        results['connection'] = self.test_connection()

        if results['connection']:
            # 测试写入
            results['write'] = self.test_write()

            # 测试读取
            results['read'] = self.test_read()

            # 清理测试数据
            self.cleanup_test_data()

        # 输出总结
        print("\n" + "=" * 50)
        print("检查结果汇总:")
        print(f"连接测试: {'✓ 通过' if results.get('connection', False) else '✗ 失败'}")
        print(f"写入测试: {'✓ 通过' if results.get('write', False) else '✗ 失败'}")
        print(f"读取测试: {'✓ 通过' if results.get('read', False) else '✗ 失败'}")

        all_passed = all(results.values()) if results else False
        print(f"\n总体状态: {'✓ 健康' if all_passed else '✗ 异常'}")
        print("=" * 50)

        # 关闭连接
        self.disconnect()

        return all_passed

def main():
    parser = argparse.ArgumentParser(description='PostgreSQL 健康检查脚本')
    parser.add_argument('--host', default='localhost', help='PostgreSQL 主机地址 (默认: localhost)')
    parser.add_argument('--port', type=int, default=5432, help='PostgreSQL 端口 (默认: 5432)')
    parser.add_argument('--user', default='postgres', help='PostgreSQL 用户名 (默认: postgres)')
    parser.add_argument('--password', default='', help='PostgreSQL 密码 (默认: 空)')
    parser.add_argument('--database', help='PostgreSQL 数据库名 (可选)')
    parser.add_argument('--interval', type=int, help='循环检查间隔秒数 (可选)')
    # 增加 Postgrest API 测试参数
    parser.add_argument('--api-url', default='http://localhost:3000', help='Postgrest API 地址 (默认: http://localhost:3000)')
    # 增加 JWT 令牌参数
    parser.add_argument('--jwt-token', default='', help='Postgrest API JWT 令牌 (默认: 空)')

    args = parser.parse_args()

    checker = PostgreSQLHealthChecker(
        host=args.host,
        port=args.port,
        user=args.user,
        password=args.password,
        database=args.database
    )

    if args.interval:
        print(f"启动循环监控，间隔 {args.interval} 秒...")
        while True:
            try:
                success = checker.run_full_check()
                if not success:
                    print("检测到异常，退出监控")
                    sys.exit(1)

                print(f"等待 {args.interval} 秒后继续...")
                time.sleep(args.interval)
            except KeyboardInterrupt:
                print("\n收到中断信号，停止监控")
                break
    else:
        # 单次检查
        success = checker.run_full_check()
        # sys.exit(0 if success else 1)
        if not success:
            print("PostgreSQL 健康检查失败")
            sys.exit(1)

    # 增加 Postgrest API 测试
    print("\n" + "=" * 50)
    print("Postgrest API 测试")

    api_tester = PostgrestAPITester(api_url=args.api_url, jwt_token=args.jwt_token)
    if api_tester.test_url_is_reachable():
        print(f"Postgrest API URL {args.api_url} 可访问")
    else:
        print(f"Postgrest API URL {args.api_url} 不可访问")
        sys.exit(1)

    if api_tester.test_get_latest_record():
        print("Postgrest API 获取最新记录 测试通过")
    else:
        print("Postgrest API 获取最新记录 测试失败")
        sys.exit(1)

    if api_tester.test_create_record():
        print("Postgrest API 创建记录 测试通过")
        if api_tester.test_get_latest_record():
            print("Postgrest API 创建记录 测试通过，再次获取最新记录验证创建成功")
        else:
            print("Postgrest API 创建记录 测试通过，但再次获取最新记录失败，可能存在问题")
    else:
        print("Postgrest API 创建记录 测试失败")
        sys.exit(1)

    if api_tester.test_with_client():
        print("Postgrest client 测试通过")
    else:
        print("Postgrest client 测试失败")
        sys.exit(1)

# 增加 Postgrest API 测试功能
class PostgrestAPITester:
    def __init__(self, api_url, jwt_token):
        self.api_url = api_url
        self.jwt_token = jwt_token
        self.table = "health_check_test"

    def test_url_is_reachable(self):
        """测试 Postgrest API URL 是否可访问"""
        try:
            response = requests.get(self.api_url + "/health_check_test")
            return response.status_code == 200
        except requests.RequestException:
            return False

    def test_get_latest_record(self):
        """测试通过 Postgrest API 获取最新记录"""
        try:
            headers = {"Authorization": f"Bearer {self.jwt_token}"} if self.jwt_token else {}
            headers["Content-Type"] = "application/json"
            response = requests.get(f"{self.api_url}/{self.table}?order=id.desc&limit=1", headers=headers)
            if response.status_code == 200:
                data = response.json()
                if data:
                    print(f"通过 API 获取到最新记录: {data[0]}")
                    return True
                else:
                    print("通过 API 获取到的记录为空")
                    return False
            else:
                print(f"通过 API 获取记录失败，状态码: {response.status_code}")
                return False
        except requests.RequestException as e:
            print(f"通过 API 获取记录失败，异常: {e}")
            return False

    def test_create_record(self):
        """测试通过 Postgrest API 创建记录"""
        try:
            headers = {"Authorization": f"Bearer {self.jwt_token}"} if self.jwt_token else {}
            headers["Content-Type"] = "application/json"
            payload = {"test_data": f"API test at {datetime.now()}"}
            response = requests.post(f"{self.api_url}/{self.table}", json=payload, headers=headers)
            print(f"通过 API 创建记录，状态码: {response.status_code}, 响应: {response.text}")
            return response.status_code == 201
        except requests.RequestException as e:
            print(f"通过 API 创建记录失败，异常: {e}")
            return False

    def test_with_client(self):
        """测试使用Postgrest client库"""
        # https://github.com/supabase/postgrest-py

        import postgrest
        import json
        with postgrest.SyncPostgrestClient(self.api_url, headers={"Authorization": f"Bearer {self.jwt_token}"}) as client_with_jwt:
            try:
                # 创建记录
                # build 2 records with different test_data
                payload = [
                    {"test_data": f"Client test 1 at {datetime.now()}"},
                    {"test_data": f"Client test 2 at {datetime.now()}"},
                ]
                response = client_with_jwt.from_(self.table).insert(payload).execute()
                if len(response.data) == 2:
                    print("通过 Postgrest SyncClient(带JWT) 创建了 2 条记录")
                    for record in response.data:
                        print(f"  - 创建记录: {record}")

                # 测试pg内置函数
                # json_set_with_result
                json_data = {
                    "name": "alice",
                    "aget": 18
                }
                response = client_with_jwt.rpc("json_set_with_result", {
                    "p_key": "user1",
                    "p_value": json.dumps(json_data)
                }).execute()
                print(f"通过 Postgrest SyncClient(带JWT) 调用函数 json_set_with_result('user1', {json.dumps(json_data)}) 记录: {response}")
                if response.data:
                    print("通过 Postgrest SyncClient(带JWT) 调用函数 json_set_with_result 成功")
                else:
                    print("通过 Postgrest SyncClient(带JWT) 调用函数 json_set_with_result 失败")
            except postgrest.exceptions.APIError as e:
                print(f"通过 Postgrest SyncClient(带JWT) 创建记录失败，异常: {e}")
                return False

        with postgrest.SyncPostgrestClient(self.api_url) as client:
            # 获取最新记录
            response = client.from_(self.table).select("*").order("id", desc=True).limit(1).execute()
            if response.data:
                print(f"通过 Postgrest SyncClient 获取到最新记录: {response.data[0]}")
            else:
                print("通过 Postgrest SyncClient 获取到的记录为空")
                return False

            # 测试pg内置函数
            # json_get
            response = client.rpc("json_get", {
                "p_key": "user1",
            }).execute()
            print(f"通过 Postgrest SyncClient 调用函数 json_get('user1') 记录: {response.data}")

        return True

if __name__ == "__main__":
    main()
