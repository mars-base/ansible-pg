#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
@Time    :   2026/03/11 15:11:09
@Author  :   ansible-pg
'''

# 发布订阅功能

import time
import sys
import signal
import psycopg2
import argparse
import select

running = True

def signal_handler(signum, frame):
    global running
    print("\n收到退出信号，正在关闭...")
    running = False

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
    parser = argparse.ArgumentParser(description='PostgreSQL 发布订阅功能')
    parser.add_argument('--host', default='localhost', help='PostgreSQL 主机地址 (默认: localhost)')
    parser.add_argument('--port', type=int, default=5432, help='PostgreSQL 端口 (默认: 5432)')
    parser.add_argument('--user', default='postgres', help='PostgreSQL 用户名 (默认: postgres)')
    parser.add_argument('--password', default='', help='PostgreSQL 密码 (默认: 空)')
    parser.add_argument('--database', default='dev', help='PostgreSQL 数据库名 (可选)')

    parser.add_argument('--mode', choices=['publish', 'subscribe'], default='subscribe',
                        help='运行模式: publish(发布) 或 subscribe(订阅) (默认: subscribe)')
    parser.add_argument('--channel', default='my_channel', help='频道名称 (默认: my_channel)')

    args = parser.parse_args()

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    conn = connect_to_db(args.host, args.port, args.database, args.user, args.password)

    if args.mode == 'publish':
        publish_mode(conn, args.channel)
    else:
        subscribe_mode(conn, args.channel)

def publish_mode(conn, channel):
    """发布模式：每5秒发送一次通知"""
    print("运行模式: 发布者 (Publisher)")
    conn.autocommit = True  # 发布者也需要设置 autocommit
    idx = 0
    while running:
        with conn.cursor() as cur:
            cur.execute(f"NOTIFY {channel}, 'Hello, World! ({idx})'")
            print(f"[PUBLISH] channel={channel} payload=Hello, World! ({idx}) (time: {time.strftime('%H:%M:%S')})")
        time.sleep(5)
        idx += 1

def subscribe_mode(conn, channel):
    print("运行模式: 订阅者 (Subscriber)")
    conn.rollback()
    conn.autocommit = True  # 必须设置 autocommit 才能异步接收通知
    with conn.cursor() as cur:
        cur.execute(f"LISTEN {channel};")
        print(f"正在监听频道: {channel}...")
    while running:
        if select.select([conn], [], [], 1.0)[0]:
            conn.poll()
            while conn.notifies:
                notifications = conn.notifies[:] # 批量获取通知
                conn.notifies.clear()  # 清空通知列表
                for notify in notifications:
                    print(f"[RECV] channel={notify.channel} payload={notify.payload} (time: {time.strftime('%H:%M:%S')})")

if __name__ == "__main__":
    main()
