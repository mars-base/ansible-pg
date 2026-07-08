#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
@Time    :   2026/02/13 16:07:30
@Author  :   ansible-pg
'''

# 测试pgmq扩展 消息队列

# pgmq扩展通常是postgres的管理员账号创建，需要给dba账号在dev数据库中使用pgmq的权限

# 例子
# py playbooks/pgmq-test.py --host 192.168.1.10 --port 5433 --dbname dev --user dba --password [xxx]


import psycopg2
import argparse

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

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='PostgreSQL连接测试脚本')
    parser.add_argument('--host', default='localhost', help='数据库主机地址 (默认: localhost)')
    parser.add_argument('--port', type=int, default=5432, help='数据库端口 (默认: 5432)')
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

    # create extension pgmq
    with conn.cursor() as cur:
        cur.execute("CREATE EXTENSION IF NOT EXISTS pgmq;")
        conn.commit()
        print("extension pgmq created")

    # create queue test_queue
    queue_name = "test_queue"
    with conn.cursor() as cur:
        cur.execute(f"SELECT pgmq.create('{queue_name}');")
        conn.commit()
        print(f"queue {queue_name} created")

    # look all queues
    with conn.cursor() as cur:
        cur.execute("""
            SELECT * FROM pgmq.list_queues();
        """)
        conn.commit()
        print("all queues:")
        for row in cur.fetchall():
            queue_name, is_partitioned, has_archive, created_at = row
            formatted_time = created_at.strftime('%Y-%m-%d %H:%M:%S')
            print(f"    Queue: {queue_name}, Partitioned: {is_partitioned}, Archived: {has_archive}, Created: {formatted_time}")


    # look all queue tables
    with conn.cursor() as cur:
        cur.execute("""
            SELECT schemaname, tablename
            FROM pg_tables
            WHERE schemaname = 'pgmq'
            AND tablename LIKE 'q_%';
        """)
        conn.commit()
        print("all queue tables:")
        for row in cur.fetchall():
            schema_name, table_name = row
            print(f"    Schema: {schema_name}, Table: {table_name}")

    # look all archive tables
    with conn.cursor() as cur:
        cur.execute("""
            SELECT schemaname, tablename
            FROM pg_tables
            WHERE schemaname = 'pgmq'
            AND tablename LIKE 'a_%';
        """)
        conn.commit()
        print("all archives:")
        for row in cur.fetchall():
            schema_name, table_name = row
            print(f"    Schema: {schema_name}, Table: {table_name}")


    # send message to queue
    json_message = '{"name": "alice", "age": 30}'
    with conn.cursor() as cur:
        cur.execute("""
            SELECT pgmq.send(
                queue_name => %(queue_name)s,
                msg    => %(message)s
            )
        """, {'queue_name': queue_name, 'message': json_message})
        conn.commit()
        print(f"message {json_message} sent to queue {queue_name}")
        # show the return message id
        print(f"message id: {cur.fetchone()[0]}")

    # receive message from queue
    print("wait 1 seconds for message to be received")
    import time
    time.sleep(1)
    with conn.cursor() as cur:
        # vt: visibility timeout in seconds 消息被读取后，等待30秒后再次可见，可以评估消息处理的时间是否超过30秒
        # qty: number of messages to read 一次读取n条消息
        cur.execute("""
            SELECT * FROM pgmq.read(
                queue_name => %(queue_name)s,
                vt         => 30,
                qty        => 5
            )
        """, {'queue_name': queue_name})
        conn.commit()
        results = cur.fetchall()
        if results:
            for row in results:
                print(f"message id: {row[0]}, message: {row[5]} received from queue {queue_name}")

                # 消息处理完成后，可以删除或者归档
                # -- Archive message with msg_id=2.
                # SELECT pgmq.archive(
                # queue_name => 'my_queue',
                # msg_id     => 2
                # );

                # delete or archive message from queue
                cur.execute("""
                    SELECT pgmq.delete(
                        queue_name => %(queue_name)s,
                        msg_id     => %(msg_id)s
                    )
                """, {'queue_name': queue_name, 'msg_id': row[0]})
                conn.commit()
                # fetch the return value
                ret = cur.fetchone()[0]
                print(f"delete message id: {row[0]} from queue {queue_name}, return value: {ret}")
        else:
            print("no message received")

    # close connection
    conn.close()
