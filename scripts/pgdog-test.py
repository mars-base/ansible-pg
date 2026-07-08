#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
@Time    :   2026/02/05 10:53:33
@Author  :   ansible-pg
'''

# 测试pgdog代理分片功能，测试写入和读取分片数据

# 测试说明

# 连接到pgdog代理，默认端口7432
# py playbooks/pgdog-test.py --host 192.168.1.10 --port 6432 --dbname pgdog --user dba --password [xxx]
# 运行测试后，分别在pgdog代理和原始数据库中查询数据，验证分片数据是否正确写入和读取
# PGPASSWORD=[xxx] psql -h 192.168.1.10 -p 5433 -U dba -d shard1 -c "select * from users;"
# PGPASSWORD=[xxx] psql -h 192.168.1.10 -p 5433 -U dba -d shard2 -c "select * from users;"

import psycopg2
import faker
import argparse

fake = faker.Faker()

def connect_to_db(host='localhost', port=5432, dbname='dev', user='dba', password='dba'):
    """连接到PostgreSQL数据库"""
    connection_config = {
        'host': host,
        'port': port,
        'user': user,
        'password': password,
        'database': dbname,
        'connect_timeout': 10,
    }
    print(f"connecting to pg... ({connection_config})")
    return psycopg2.connect(**connection_config)

def main():
    parser = argparse.ArgumentParser(description='PostgreSQL连接测试脚本')
    parser.add_argument('--host', default='localhost', help='数据库主机地址 (默认: localhost)')
    parser.add_argument('--port', type=int, default=7432, help='数据库端口 (默认: 7432)')
    parser.add_argument('--dbname', default='dev', help='数据库名 (默认: dev)')
    parser.add_argument('--user', default='dba', help='用户名 (默认: dba)')
    parser.add_argument('--password', default='dba', help='密码 (默认: dba)')

    args = parser.parse_args()

    # 使用命令行参数连接数据库
    conn = connect_to_db(
        host=args.host,
        port=args.port,
        dbname=args.dbname,
        user=args.user,
        password=args.password
    )

    # create table users with uuid as primary key
    with conn.cursor() as cur:
        # 确保uuid扩展已安装
        cur.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";")
        conn.commit()

        cur.execute("""
            DROP TABLE IF EXISTS users;
            CREATE TABLE IF NOT EXISTS users (
                id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                name VARCHAR(50) NOT NULL
            );
        """)
        conn.commit()
        print("create table users with uuid primary key done")

    # insert 10 rows with fake data - 使用UUID作为主键
    with conn.cursor() as cur:
        for i in range(10):
            cur.execute("INSERT INTO users (name) VALUES (%s);", (fake.name(),))
        conn.commit()
        print("insert 10 rows with uuid done")

    # query all rows
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM users;")
        rows = cur.fetchall()
        for row in rows:
            print(row)
        print("query all rows done")

    # query count of rows
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM users;")
        count = cur.fetchone()[0]
        print(f"total rows: {count}")
        print("query count of rows done")

    # close connection
    conn.close()

if __name__ == "__main__":
    main()
