# KV Cache（基于 PostgreSQL 的缓存方案）

使用 PostgreSQL UNLOGGED TABLE 替代 Redis 缓存，支持自动过期（TTL）、并发安全（UPSERT 原子性）、分批清理。适用于中低频场景（< 500 QPS），高频场景仍建议 Redis。

## 缓存方案

| 方案 | 表名 | 值类型 | 适用场景 |
|------|------|--------|---------|
| **BYTEA 通用缓存** | `kv_cache` | BYTEA | 通用缓存、二进制数据、序列化对象 |
| **JSONB 专用缓存** | `kv_cache_json` | JSONB | JSON 对象缓存，支持字段级读写和包含查询 |

## 部署

```bash
# 部署两套缓存（默认）
ansible-playbook -i hosts.ini playbooks/kv-cache.yaml

# 仅部署 JSONB 缓存
ansible-playbook -i hosts.ini playbooks/kv-cache.yaml -e kv_type=json

# 仅部署 BYTEA 缓存
ansible-playbook -i hosts.ini playbooks/kv-cache.yaml -e kv_type=bytea

# 指定目标主机和数据库
ansible-playbook -i hosts.ini playbooks/kv-cache.yaml \
  -e HOSTS=d37-mongo-log -e 'pg_databases=["dev"]'

# 连接到外部 PG 实例
ansible-playbook -i hosts.ini playbooks/kv-cache.yaml \
  -e pg_host=120.24.237.92 -e pg_port=5433 -e pg_user=dba -e pg_password=CHANGEME
```

## BYTEA 通用缓存函数

### kv_set — 写入缓存

```sql
-- 写入（默认 300s 过期）
SELECT kv_set('user:123', '{"name":"张三","age":30}', 300);

-- 自定义过期时间（60s）
SELECT kv_set('session:abc', 'token_value', 60);

-- UPSERT：key 已存在则覆盖（原子操作）
SELECT kv_set('user:123', '{"name":"张三","age":31}', 300);
```

### kv_set_with_result — 写入并返回结果

```sql
-- 返回 BOOLEAN（true=成功）
SELECT kv_set_with_result('user:123', 'hello world', 60);
```

### kv_get — 读取缓存

```sql
-- 返回 BYTEA
SELECT kv_get('user:123');

-- 返回 TEXT（自动转换）
SELECT kv_get_text('user:123');
```

### kv_del — 删除缓存

```sql
SELECT kv_del('user:123');
```

### kv_cleanup_batch — 批量清理过期

```sql
-- 每次最多清理 1000 条过期数据，返回实际删除数量
SELECT kv_cleanup_batch(1000);
```

## JSONB 专用缓存函数

### json_set — 写入 JSON 缓存

```sql
SELECT json_set('user:123', '{"name":"张三","age":18,"active":true}'::jsonb);
```

### json_get — 读取整个 JSON 对象

```sql
SELECT json_get('user:123');
```

### json_get_field — 读取特定字段

```sql
-- 返回 TEXT
SELECT json_get_field('user:123', 'name');       -- 返回: "张三"

-- 返回 JSONB
SELECT json_get_field_json('user:123', 'age');   -- 返回: 18
```

### json_contains — 包含查询

```sql
-- 利用 GIN 索引，判断缓存值是否包含指定 JSON
SELECT json_contains('user:123', '{"age":18}'::jsonb);  -- 返回 BOOLEAN
```

### json_update_field — 局部更新字段

支持数字、布尔、数组、对象类型，自动类型转换：

```sql
-- 更新数字
SELECT json_update_field('user:123', 'age', '25');

-- 更新布尔
SELECT json_update_field('user:123', 'active', 'false');

-- 更新数组
SELECT json_update_field('user:123', 'tags', '["vip","active"]');

-- 更新对象
SELECT json_update_field('user:123', 'address', '{"city":"北京"}');
```

### json_del — 删除 JSON 缓存

```sql
SELECT json_del('user:123');
```

### json_cleanup_batch — 批量清理过期

```sql
SELECT json_cleanup_batch(1000);
```

## E2E 测试

```bash
# 运行全部测试（默认连接 pg-single）
PGPASSWORD='your-password' ./scripts/kv-cache-test.sh

# 指定连接参数
./scripts/kv-cache-test.sh -h 120.24.237.92 -p 5433 -U dba -P 'your-password' -d dev

# 仅测试 JSONB 缓存
PGPASSWORD='your-password' ./scripts/kv-cache-test.sh -t json

# 仅测试 BYTEA 缓存
PGPASSWORD='your-password' ./scripts/kv-cache-test.sh -t bytea
```

测试覆盖：SET/GET/DEL、UPSERT 覆盖写入、TTL 过期、批量清理、字段级读写、JSON 包含查询、嵌套对象操作。
