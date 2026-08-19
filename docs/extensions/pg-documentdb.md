# pg_documentdb（DocumentDB - MongoDB 兼容）

pg_documentdb 是 Microsoft 开源的 MongoDB 兼容层，让 PostgreSQL 能够处理 MongoDB 协议和数据格式。

## 配置要求

### 1. shared_preload_libraries 预加载

在 `postgres_shared_preload_libraries` 中同时添加 `pg_documentdb_core` 和 `pg_documentdb`：

```yaml
postgres_shared_preload_libraries: "pg_cron,pg_stat_statements,uuid-ossp,pg_duckdb,pg_documentdb_core,pg_documentdb"
```

> **重要**：必须同时预加载 `pg_documentdb_core` 和 `pg_documentdb`，只加载 `pg_documentdb` 会导致 PG 启动失败。

修改后需重启 Patroni 生效。

### 2. pg_hba trust 规则（自动配置）

pg_documentdb 内部使用 libpq 回连 PG 执行操作，且会**自动覆盖连接字符串中的 `user` 为当前 session user**。Patroni 模板已自动添加以下 pg_hba 规则：

```yaml
- host all all 127.0.0.1/32 trust                       # documentdb 等扩展内部连接 localhost
- host all all {{ ansible_default_ipv4.address }}/32 trust  # documentdb 内部连接覆盖 user
```

同时 `postgresql.listen` 已包含 `127.0.0.1`，确保 PG 监听 localhost：

```yaml
postgresql:
  listen: "{{ ansible_default_ipv4.address }},127.0.0.1:5432"
```

> 这些规则在 Patroni 模板 `roles/patroni/templates/pg.yaml` 中自动配置。如果手动管理 pg_hba，需要确保添加对应的 trust 规则，否则 `documentdb_api.insert_one` 等调用会报错：`fe_sendauth: no password supplied` 或 `Connection refused`。

### 3. 依赖扩展 rum

pg_documentdb 依赖 `rum` 扩展（GIN 索引增强），需要先安装：

```yaml
pg_extensions:
  - "rum"           # pg_documentdb 依赖
  - "documentdb"    # DocumentDB
```

### 4. 数据库限制

pg_documentdb **只能**在 `postgres` 数据库中创建，不能在 `dev`、`prod` 等其他数据库中创建：

```yaml
pg_extensions_on:
  - { db: 'postgres', extension: 'documentdb', cascade: true }  # 必须用 postgres 库
```

> 在 `dev` 或 `prod` 库中执行 `CREATE EXTENSION documentdb` 会报错：`extension "documentdb" is not available for database "dev"`。

### 5. 名称映射

pg_documentdb 涉及多个名称，容易混淆：

| 场景 | 名称 | 说明 |
|------|------|------|
| apt 包名 | `postgresql-17-documentdb` | Pigsty 仓库提供 |
| pg_extensions 值 | `documentdb` | pig install 用 |
| .so 文件名 | `pg_documentdb.so` | shared_preload_libraries 中写 `pg_documentdb` |
| SQL 扩展名 | `documentdb` | CREATE EXTENSION 用 |
| Schema 名 | `documentdb_api` | API 函数所在 schema |

### 6. documentdb_postgres_role 权限配置

非 superuser 使用 documentdb API 需要额外权限，通过 `documentdb_postgres_role` 变量指定允许的角色：

```yaml
documentdb_postgres_role: "dba"
```

`documentdb` role（在 `pg-ha-cluster.yaml` 中）会自动为指定角色授予以下权限：
- 10 个 documentdb schema 的 USAGE 权限
- 5 个 documentdb 角色的成员资格
- documentdb_api_catalog 表/序列的 ALL 权限
- data schema 的 ALL 权限

> 如果不需要授权非 superuser 使用 documentdb，留空 `documentdb_postgres_role: ""` 即可。

## 部署步骤

```bash
# 1. 更新 Patroni 配置（写入 shared_preload_libraries）
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml -e HOSTS=pg-single -t patroni-config

# 2. 重启 Patroni 使预加载参数生效
ansible pg-single -i hosts.ini -b -a "supervisorctl restart patroni"

# 3. 安装扩展并启用（包括 documentdb 权限授予）
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml -e HOSTS=pg-single -t pg-extension,initdb,documentdb -e pg_create_extensions=true
```

## API 使用

pg_documentdb 提供 `documentdb_api` schema 下的函数，兼容 MongoDB API：

```sql
-- 创建集合（类似 MongoDB 的 collection）
SELECT documentdb_api.create_collection('mydb', 'products');

-- 插入文档（类似 MongoDB 的 insertOne）
SELECT documentdb_api.insert_one('mydb', 'products', '{
  "name": "iPhone 15 Pro",
  "category": "手机",
  "price": 8999,
  "tags": ["apple", "5g"]
}');

-- 查询所有文档
SELECT document FROM documentdb_api.collection('mydb', 'products');

-- 统计文档数量
SELECT count(*) FROM documentdb_api.collection('mydb', 'products');

-- 删除集合
SELECT documentdb_api.drop_collection('mydb', 'products');
```

> **注意**：当前版本（0.114-0）的 `documentdb_api.bson_match` 等查询函数可能不可用，建议使用基础 CRUD API。

## 验证

```bash
# 运行 Python 测试脚本（使用 dba 用户通过 pgbouncer 5433 端口测试）
python3 test/test_documentdb.py \
  -H 10.241.21.97 -p 5433 \
  -U dba -W <password> -d postgres
```

测试脚本会自动创建集合、插入 3 个文档、查询并清理，输出 PASS/FAIL 状态。

## 已知限制

- 只能在 `postgres` 数据库中创建和使用
- 查询结果返回 BSON 类型（hex 格式），需要额外解析或转换
- `bson_match` 等高级查询 API 在当前版本（0.114-0）可能不可用
- 建议使用基础 CRUD API（`create_collection`, `insert_one`, `collection`, `drop_collection`）
