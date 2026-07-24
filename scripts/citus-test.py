# 测试Citus
#
# 普通模式：对指定表进行分布式

# 在Coordinator节点上执行
# 1. 创建一个普通表 dept
# 2. 转换为分布式表
# 3. 插入数据
# 4. 查询数据分布
# 5. 查询分片位置，验证数据分布

# 示例：
# py scripts/citus-test.py --host 10.241.21.97 --port 5433 --dbname dev --user dba --password xxx

import argparse
import psycopg
from faker import Faker

fake = Faker()

# 解析命令行参数
parser = argparse.ArgumentParser(description='测试 Citus 普通分布式表')
parser.add_argument('--host', default='192.168.1.11', help='PostgreSQL 主机地址 (默认: 192.168.1.11)')
parser.add_argument('--port', type=int, default=5432, help='PostgreSQL 端口 (默认: 5432)')
parser.add_argument('--dbname', default='dev', help='数据库名 (默认: dev)')
parser.add_argument('--user', default='dba', help='用户名 (默认: dba)')
parser.add_argument('--password', default='dba', help='密码 (默认: dba)')
args = parser.parse_args()

# 构建连接字符串
dba_conn = f"dbname={args.dbname} user={args.user} host='{args.host}' port={args.port} password={args.password}"

print("connecting to pg...")
conn = psycopg.connect(dba_conn)

# create a table dept
with conn.cursor() as cur:
    print("create table dept...")
    cur.execute("CREATE TABLE IF NOT EXISTS dept (id serial PRIMARY KEY, name VARCHAR (50), email VARCHAR (50), date_of_birth DATE, department_id INT);")
    conn.commit()

# 检查 dept 表是否已经是分布式表
with conn.cursor() as cur:
    cur.execute("SELECT EXISTS(SELECT 1 FROM pg_dist_partition WHERE logicalrelid = 'dept'::regclass);")
    is_distributed = cur.fetchone()[0]
    if not is_distributed:
        print("create table dept as a distributed table...")
        cur.execute("SELECT create_distributed_table('dept', 'id');")
        conn.commit()
    else:
        print("dept table is already distributed, skipping conversion.")

# query data count
with conn.cursor() as cur:
    cur.execute("SELECT COUNT(*) FROM dept;")
    count = cur.fetchone()[0]
    print(f"Total rows: {count}")

# if count == 0, insert 100 rows of random data
if count == 0:
    print("insert 100 rows of random data...")
    with conn.cursor() as cur:
        insert_data = []
        for _ in range(100):
            name = fake.name()
            email = fake.email()
            date_of_birth = fake.date_of_birth(minimum_age=18, maximum_age=60)
            department_id = fake.random_int(min=1, max=10)
            insert_data.append((name, email, date_of_birth, department_id))

        cur.executemany("INSERT INTO dept (name, email, date_of_birth, department_id) VALUES (%s, %s, %s, %s)", insert_data)
        conn.commit()
else:
    print("skip insert data, because table dept already has data.")

# query data
print("query table dept...")
with conn.cursor() as cur:
    cur.execute("SELECT * FROM dept;")
    rows = cur.fetchall()
    for row in rows:
        print(row)

# show count
print(f"Total rows: {count}")


# Verify data distribution
print("Verify data distribution...")
# -- 查询分片位置，验证数据分布
# -- 明确指定 shardid 列来自 pg_dist_shard 表
# SELECT pg_dist_shard.shardid, nodename, nodeport
# FROM pg_dist_shard_placement
# JOIN pg_dist_shard ON pg_dist_shard_placement.shardid = pg_dist_shard.shardid
# JOIN pg_dist_partition ON pg_dist_shard.logicalrelid = pg_dist_partition.logicalrelid
# WHERE pg_dist_partition.logicalrelid = 'dept'::regclass order by shardid;
with conn.cursor() as cur:
    cur.execute("SELECT pg_dist_shard.shardid, nodename, nodeport FROM pg_dist_shard_placement JOIN pg_dist_shard ON pg_dist_shard_placement.shardid = pg_dist_shard.shardid JOIN pg_dist_partition ON pg_dist_shard.logicalrelid = pg_dist_partition.logicalrelid WHERE pg_dist_partition.logicalrelid = 'dept'::regclass order by nodename;")
    rows = cur.fetchall()
    for row in rows:
        print(row)


# close connection
print("close connection.")
conn.close()
