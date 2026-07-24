# 测试Citus
#
# 微服务schema模式的分布式

# 操作说明
# 1. 使用管理员权限账号 在指定的需要进行分布式的数据库上 创建微服务使用的账号和schema 并启动自动按照schema进行分布式
# 2. 使用微服务账号 在指定的schema上 创建微服务需要的普通表
# 3. 验证 微服务账号 在指定的schema上 创建的普通表 是否已经是分布式表

# 示例：
# py scripts/citus-schema-test.py --host 10.241.21.97 --port 5433 --dbname dev --user admin --password xxx --tenant-password yyy

import argparse
import psycopg
from faker import Faker

fake = Faker()

# 解析命令行参数
parser = argparse.ArgumentParser(description='测试 Citus 微服务 schema 模式的分布式')
parser.add_argument('--host', default='192.168.1.11', help='PostgreSQL 主机地址 (默认: 192.168.1.11)')
parser.add_argument('--port', type=int, default=5432, help='PostgreSQL 端口 (默认: 5432)')
parser.add_argument('--dbname', default='dev', help='数据库名 (默认: dev)')
parser.add_argument('--user', default='admin', help='管理员用户名 (默认: admin)')
parser.add_argument('--password', default='admin', help='管理员密码 (默认: admin)')
parser.add_argument('--tenant-password', default='myfarm1', help='租户密码 (默认: myfarm1)')
parser.add_argument('--tenants', nargs='+', default=['myfarm1', 'myfarm2', 'myfarm3'], help='租户列表 (默认: myfarm1 myfarm2 myfarm3)')
args = parser.parse_args()

# 构建连接字符串
base = f"dbname={args.dbname} host='{args.host}' port={args.port}"
admin_connect = f"{base} user={args.user} password={args.password}"
tenant_connects = {t: f"{base} user={t} password={args.tenant_password}" for t in args.tenants}

print("connecting to pg with admin ...")
conn_admin = psycopg.connect(admin_connect)

# 连接所有租户
tenant_conns = {}
for tenant in args.tenants:
    print(f"connecting to pg with {tenant} user...")
    tenant_conns[tenant] = psycopg.connect(tenant_connects[tenant])

# create schema and enable distribution
for schema_name in args.tenants:
    conn_t = tenant_conns[schema_name]
    with conn_admin.cursor() as cur:
        print(f"create schema {schema_name}...")
        cur.execute("SELECT 1 FROM pg_namespace WHERE nspname = %s", (schema_name,))
        if not cur.fetchone():
            cur.execute(f"CREATE SCHEMA AUTHORIZATION {schema_name}")
            conn_admin.commit()
            print(f"Schema {schema_name} created successfully.")
        else:
            print(f"Schema {schema_name} already exists.")

        print(f"check schema {schema_name} is distributed...")
        cur.execute("SELECT 1 FROM citus_schemas WHERE schema_name = %s::regnamespace", (schema_name,))
        if not cur.fetchone():
            print(f"distribute schema {schema_name}...")
            cur.execute(f"SELECT citus_schema_distribute('{schema_name}');")
            conn_admin.commit()
            print(f"Schema {schema_name} distributed successfully.")
        else:
            print(f"Schema {schema_name} is already distributed.")

# 在每个租户 schema 下创建表并插入数据
for schema_name, conn in tenant_conns.items():
    print(f"creating tables in schema {schema_name}...")
    with conn.cursor() as cur:
        tables = [
            ("users", "id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, email VARCHAR(255) NOT NULL"),
            ("query_details", "id SERIAL PRIMARY KEY, ip_address INET NOT NULL, query_time TIMESTAMP NOT NULL"),
            ("ping_results", "id SERIAL PRIMARY KEY, host VARCHAR(255) NOT NULL, result TEXT NOT NULL")
        ]
        for table_name, table_def in tables:
            cur.execute("SELECT 1 FROM pg_tables WHERE schemaname = %s AND tablename = %s", (schema_name, table_name))
            if not cur.fetchone():
                cur.execute(f"CREATE TABLE {schema_name}.{table_name} ({table_def})")
                conn.commit()
                print(f"Table {table_name} in {schema_name} created successfully.")
            else:
                print(f"Table {table_name} in {schema_name} already exists.")

    with conn.cursor() as cur:
        print(f"insert 100 fake items to {schema_name}.users...")
        for _ in range(100):
            cur.execute(f"INSERT INTO {schema_name}.users (name, email) VALUES (%s, %s)", (fake.name(), fake.email()))
        conn.commit()

        print(f"insert 2 fake items to {schema_name}.query_details...")
        for _ in range(2):
            cur.execute(f"INSERT INTO {schema_name}.query_details (ip_address, query_time) VALUES (%s, %s)", (fake.ipv4(), fake.date_time_this_decade()))
        conn.commit()

        print(f"insert 2 fake items to {schema_name}.ping_results...")
        for _ in range(2):
            cur.execute(f"INSERT INTO {schema_name}.ping_results (host, result) VALUES (%s, %s)", (fake.domain_name(), fake.text()))
        conn.commit()

    print(f"close connection with {schema_name} user.")
    conn.close()



# data has been stored and we can check if citus_schemas reflects what we expect
with conn_admin.cursor() as cur:
    print("check citus_schemas...")
    print("schema_name  | colocation_id | schema_size | schema_owner")
    cur.execute("SELECT * FROM citus_schemas")
    rows = cur.fetchall()
    for row in rows:
        print(row)

# When we created the schemas, we didn’t tell Citus on which machines to create the schemas. It has done this for us automatically. We can see where each schema resides with the following query:
#   select nodename, nodeport, table_name, pg_size_pretty(sum(shard_size))
#     from citus_shards
# group by nodename,nodeport, table_name;
with conn_admin.cursor() as cur:
    print("check citus_shards...")
    print("nodename | nodeport | table_name | shard_size")
    cur.execute("SELECT nodename, nodeport, table_name, pg_size_pretty(sum(shard_size)) FROM citus_shards GROUP BY nodename,nodeport, table_name;")
    rows = cur.fetchall()
    for row in rows:
        print(row)

# close connection
print("close connection with admin user.")
conn_admin.close()
