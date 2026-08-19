# PostgreSQL 扩展安装

## APT 源配置

`pg-extension` role 自动配置两个 apt 源：

| 源 | 地址 | 提供扩展示例 |
|----|------|-------------|
| **Pigsty** | `repo.pigsty.io/apt/pgsql/` | pgmq, pg_cron, pg_stat_statements, pgvectorscale |
| **PGDG** | `apt.postgresql.org/pub/repos/apt/` | pgvector (pgvector_17), postgis, pgrouting |

> pgvector 等 PGDG-only 扩展需要先添加 PGDG 源，否则 `pig install pgvector` 会报 `Package 'postgresql-17-pgvector' has no installation candidate`。

## 已安装扩展清单

### pg-single 节点（PostgreSQL 17）

| 扩展 | 版本 | 来源 | 数据库 |
|------|------|------|--------|
| pg_cron | 1.6.7 | PGDG | postgres |
| uuid-ossp | 内置 | contrib | dev, prod |
| pg_stat_statements | 1.18 | contrib | dev, prod |
| pgmq | 1.5.1 | Pigsty | dev, prod |
| pgvector (vector) | 0.8.6 | PGDG | dev, prod |

## 安装新扩展

### 1. 在 group_vars 配置中添加

编辑 `group_vars/pg_single/pg_all.yaml`：

```yaml
# 添加扩展包（pig install 用）
pg_extensions:
  - "pg_cron"
  - "uuid-ossp"
  - "pg_stat_statements"
  - "pgmq"
  - "pgvector"        # PGDG 源，包名: postgresql-17-pgvector

# 在指定数据库启用扩展（CREATE EXTENSION 用）
pg_extensions_on:
  - { db: 'dev', extension: 'vector' }   # pgvector 的 SQL 扩展名是 vector
  - { db: 'prod', extension: 'vector' }
```

### 2. 执行部署

```bash
ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
  -e HOSTS=pg-single \
  -t pg-extension \
  -e pg_create_extensions=true
```

### 3. 验证

```bash
# 检查扩展版本
PGPASSWORD='<password>' psql -h <host> -p 5433 -U dba -d dev \
  -c "SELECT extname, extversion FROM pg_extension;"

# 快速测试 pgvector
psql -c "SELECT '[1,2,3]'::vector;"
```

## 扩展包名与 SQL 名称对照

| apt 包名 | SQL CREATE EXTENSION 名称 | 说明 |
|----------|--------------------------|------|
| `postgresql-17-pgvector` | `vector` | pgvector 向量扩展 |
| `postgresql-17-pgmq` | `pgmq` | 消息队列 |
| `postgresql-17-cron` | `pg_cron` | 定时任务 |
| `postgresql-17-pg-stat-statements` | `pg_stat_statements` | SQL 统计 |
| `postgresql-17-pgvectorscale` | `vectorscale` | pgvector 补充 |
| `postgresql-17-postgis-3` | `postgis` | GIS 扩展 |

## 常见问题

### pig install 报 Package has no installation candidate

检查扩展来源仓库：

```bash
# 搜索 Pigsty 源
apt-cache search <package-name>

# 如果搜不到，可能需要 PGDG 源
# pg-extension role 已自动添加 PGDG 源
```

参考 https://ext.pigsty.io/list/pkg/ 查看扩展的 DEB 包名和来源仓库。
