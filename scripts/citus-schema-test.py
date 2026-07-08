# 测试Citus
#
# 微服务schema模式的分布式

# 操作说明
# 1. 使用管理员权限账号 在指定的需要进行分布式的数据库上 创建微服务使用的账号和schema 并启动自动按照schema进行分布式
# 2. 使用微服务账号 在指定的schema上 创建微服务需要的普通表
# 3. 验证 微服务账号 在指定的schema上 创建的普通表 是否已经是分布式表

import psycopg
from faker import Faker

fake = Faker()

# 管理员账号连接字符串
admin_connect = "dbname=dev host='192.168.1.11' user=admin password=admin"
# 微服务账号连接字符串
ms1_connect = "dbname=dev host='192.168.1.11' user=myfarm1 password=myfarm1"
ms2_connect = "dbname=dev host='192.168.1.11' user=myfarm2 password=myfarm2"
ms3_connect = "dbname=dev host='192.168.1.11' user=myfarm3 password=myfarm3"

print("connecting to pg with admin ...")
conn_admin = psycopg.connect(admin_connect)
print("connecting to pg with myfarm1 user...")
conn_ms1 = psycopg.connect(ms1_connect)
print("connecting to pg with myfarm2 user...")
conn_ms2 = psycopg.connect(ms2_connect)
print("connecting to pg with myfarm3 user...")
conn_ms3 = psycopg.connect(ms3_connect)

# create schema names myfarm1, myfarm2, myfarm3, and open schema distribution
schema_names = ['myfarm1', 'myfarm2', 'myfarm3']
for schema_name in schema_names:
    with conn_admin.cursor() as cur:
        print(f"create schema {schema_name}...")
        # 检查schema是否存在
        cur.execute("SELECT 1 FROM pg_namespace WHERE nspname = %s", (schema_name,))
        if not cur.fetchone():
            cur.execute(f"CREATE SCHEMA AUTHORIZATION {schema_name}")
            conn_admin.commit()
            print(f"Schema {schema_name} created successfully.")
        else:
            print(f"Schema {schema_name} already exists.")

        # 检查schema是否已经是分布式schema
        print(f"check schema {schema_name} is distributed...")
        cur.execute("SELECT 1 FROM citus_schemas WHERE schema_name = %s::regnamespace", (schema_name,))
        if not cur.fetchone():
            # 开启schema分布
            print(f"distribute schema {schema_name}...")
            cur.execute(f"SELECT citus_schema_distribute('{schema_name}');")
            conn_admin.commit()
            print(f"Schema {schema_name} distributed successfully.")
        else:
            print(f"Schema {schema_name} is already distributed.")



# 定义连接和 schema 名称的映射
schema_conn_mapping = {
    'myfarm1': conn_ms1,
    'myfarm2': conn_ms2,
    'myfarm3': conn_ms3
}

for schema_name, conn in schema_conn_mapping.items():
    print(f"connecting to pg with {schema_name} user...")
    with conn.cursor() as cur:
        print(f"create tables in schema {schema_name}...")
        tables = [
            ("users", "id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, email VARCHAR(255) NOT NULL"),
            ("query_details", "id SERIAL PRIMARY KEY, ip_address INET NOT NULL, query_time TIMESTAMP NOT NULL"),
            ("ping_results", "id SERIAL PRIMARY KEY, host VARCHAR(255) NOT NULL, result TEXT NOT NULL")
        ]
        for table_name, table_def in tables:
            # 检查表是否存在
            cur.execute("SELECT 1 FROM pg_tables WHERE schemaname = %s AND tablename = %s", (schema_name, table_name))
            if not cur.fetchone():
                cur.execute(f"CREATE TABLE {schema_name}.{table_name} ({table_def})")
                conn.commit()
                print(f"Table {table_name} in {schema_name} created successfully.")
            else:
                print(f"Table {table_name} in {schema_name} already exists.")

    # insert 100 fake item to table users in schema myfarmX, using faker module
    with conn.cursor() as cur:
        print(f"insert 100 fake item to table users in schema {schema_name}...")
        for _ in range(100):
            name = fake.name()
            email = fake.email()
            cur.execute(f"INSERT INTO {schema_name}.users (name, email) VALUES (%s, %s)", (name, email))
        conn.commit()

    # insert 2 fake item to table query_details in schema myfarmX, using faker module
    with conn.cursor() as cur:
        print(f"insert 2 fake item to table query_details in schema {schema_name}...")
        for _ in range(2):
            ip_address = fake.ipv4()
            query_time = fake.date_time_this_decade()
            cur.execute(f"INSERT INTO {schema_name}.query_details (ip_address, query_time) VALUES (%s, %s)", (ip_address, query_time))
        conn.commit()

    # insert 2 fake item to table ping_results in schema myfarmX, using faker module
    with conn.cursor() as cur:
        print(f"insert 2 fake item to table ping_results in schema {schema_name}...")
        for _ in range(2):
            host = fake.domain_name()
            result = fake.text()
            cur.execute(f"INSERT INTO {schema_name}.ping_results (host, result) VALUES (%s, %s)", (host, result))
        conn.commit()

    # close connection
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
