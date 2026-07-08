pgdog 分片代理
===

支持在同一主机上运行多个独立的 pgdog 实例，每个实例监听不同端口，连接不同的后端数据库。

## 配置方式

### 多实例（推荐）

在 `host_vars` 或 `group_vars` 中定义 `pgdog_instances` 列表：

```yaml
pgdog_host: "{{ ansible_default_ipv4.address }}"

pgdog_instances:
  - name: production
    port: 6432
    databases:
      - name: "pgdog"
        host: "127.0.0.1"
        port: 5432
        database_name: "shard1"
        shard: 0
        role: "primary"
    users:
      - database: "pgdog"
        name: "dba"
        password: "secret"
    sharded_tables:
      - database: "pgdog"
        name: "users"
        column: "id"
        data_type: "bigint"

  - name: dev
    port: 6433
    databases:
      - name: "pgdog"
        host: "127.0.0.1"
        port: 5432
        database_name: "test1"
        shard: 0
        role: "primary"
    users:
      - database: "pgdog"
        name: "dba"
        password: "secret"
    sharded_tables: []
```

每个实例独立运行：
- 配置文件：`/srv/pgdog/<name>/pgdog.toml`、`/srv/pgdog/<name>/users.toml`
- 日志：`/srv/pgdog/<name>/logs/`
- supervisor 进程：`pgdog-<name>`
- docker 容器：`pgdog-<name>`

### 单实例（向后兼容）

如果 `pgdog_instances` 为空或未定义，自动使用旧的扁平变量构建单实例：

```yaml
pgdog_port: 7432
pgdog_databases: [...]
pgdog_users: [...]
pgdog_sharded_tables: [...]
```

## 连接数据库

```bash
# production 实例
PGPASSWORD=dba psql -h 127.0.0.1 -p 6432 -U dba -d pgdog -c '\dt;'

# dev 实例
PGPASSWORD=dba psql -h 127.0.0.1 -p 6433 -U dba -d pgdog -c '\dt;'
```

## 创建分片表

```sql
CREATE TABLE users (
    id BIGINT PRIMARY KEY,
    name VARCHAR(50) NOT NULL
);
```

## 验证分片

```bash
# 通过 pgdog 查询（自动路由到对应 shard）
PGPASSWORD=dba psql -h 127.0.0.1 -p 6432 -U dba -d pgdog -c 'select * from users;'

# 直连 shard1（只看一部分数据）
PGPASSWORD=dba psql -h 127.0.0.1 -p 5432 -U dba -d shard1 -c 'select * from users;'

# 直连 shard2（只看另一部分数据）
PGPASSWORD=dba psql -h 127.0.0.1 -p 5432 -U dba -d shard2 -c 'select * from users;'
```

