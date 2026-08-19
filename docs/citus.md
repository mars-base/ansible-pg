# Citus 分布式 PostgreSQL

Citus 是 PostgreSQL 的分布式扩展，将多个 PG 实例组成分布式集群，支持水平分片和多租户。

## 架构要求

Citus **必须配合多个 Patroni 单节点使用**，不能使用 Patroni HA 自动故障切换。

原因：Patroni 自动 failover 后，Citus 元数据（`pg_dist_node`）不会自动更新，导致 coordinator 找不到 worker，整个分布式集群不可用。

```
正确：
pg_single_1 (Patroni 单节点) ←→ coordinator
pg_single_2 (Patroni 单节点) ←→ worker
pg_single_3 (Patroni 单节点) ←→ worker

错误：
Patroni HA 集群（1 primary + N replica）× Citus ❌
```

## 前置条件：安装 citus 扩展

假设有 3 个单节点：`pg_single_1`（coordinator）、`pg_single_2`、`pg_single_3`（worker）。

### 1. 在每个节点的 group_vars 中添加 citus 配置

```yaml
# group_vars/pg_single_1/pg_all.yaml
# group_vars/pg_single_2/pg_all.yaml
# group_vars/pg_single_3/pg_all.yaml
postgres_shared_preload_libraries: "pg_cron,pg_stat_statements,uuid-ossp,citus"

pg_extensions:
  - "citus"

pg_extensions_on:
  - { db: 'dev', extension: 'citus' }
```

### 2. 在所有节点安装扩展包

```bash
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
    -e HOSTS=$host -t pg-extension,initdb -e pg_create_extensions=true
done
```

### 3. 更新 Patroni 配置并重启（使 shared_preload_libraries 生效）

```bash
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
    -e HOSTS=$host -t patroni-config
done
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible -i hosts.ini $host -b -m shell -a "supervisorctl restart patroni"
done
```

## 部署剧本

剧本路径：`playbooks/citus/citus.yaml`

### 参数说明

| 参数 | 说明 |
|------|------|
| `_coordinator_hostname` | 协调器主机名（如 `pg_single_1`） |
| `_worker_hostname` | 工作节点主机名（如 `pg_single_2`） |
| `_citus_to_db` | citus 扩展安装到的数据库名 |
| `_pg_user` | PG 管理员账号 |
| `_pg_password` | PG 管理员密码 |
| `_postgres_port` | PostgreSQL 端口（默认 5432） |
| `_citus_all_nodes` | 所有节点主机名列表，用于配置 DNS |
| `_citus_tenant_name` | 多租户名称（可选，配合 `-t tenant`） |
| `_citus_tenant_password` | 多租户密码（可选，配合 `-t tenant`） |

### Tag 说明

| Tag | 说明 |
|-----|------|
| _(默认)_ | 安装扩展 + 配置 DNS + 注册 coordinator 和 worker 节点 |
| `verify` | 验证集群状态 |
| `dns` | 配置所有节点 DNS（多节点场景） |
| `tenant` | 创建多租户 schema 并启用分布式 |

### 基础部署（coordinator + worker）

每执行一次添加一个 worker 节点：

```bash
# 添加 pg_single_2 为 worker
ansible-playbook -i hosts.ini playbooks/citus/citus.yaml \
  -e _coordinator_hostname=pg_single_1 \
  -e _worker_hostname=pg_single_2 \
  -e _citus_to_db=dev \
  -e _pg_user=admin -e _pg_password=admin

# 添加 pg_single_3 为 worker
ansible-playbook -i hosts.ini playbooks/citus/citus.yaml \
  -e _coordinator_hostname=pg_single_1 \
  -e _worker_hostname=pg_single_3 \
  -e _citus_to_db=dev \
  -e _pg_user=admin -e _pg_password=admin
```

### 验证集群状态

```bash
ansible-playbook -i hosts.ini playbooks/citus/citus.yaml \
  -e _coordinator_hostname=pg_single_1 \
  -e _worker_hostname=pg_single_2 \
  -e _citus_to_db=dev \
  -e _pg_user=admin -e _pg_password=admin \
  -t verify
```

### 配置所有节点 DNS

```bash
ansible-playbook -i hosts.ini playbooks/citus/citus.yaml \
  -e _coordinator_hostname=pg_single_1 \
  -e _worker_hostname=pg_single_2 \
  -e _citus_to_db=dev \
  -e _pg_user=admin -e _pg_password=admin \
  -t dns \
  -e "_citus_all_nodes=['pg_single_1','pg_single_2','pg_single_3']"
```

### 创建多租户

适用于对 schema 进行分布式的场景，schema 对应租户名一致：

```bash
ansible-playbook -i hosts.ini playbooks/citus/citus.yaml \
  -e _coordinator_hostname=pg_single_1 \
  -e _worker_hostname=pg_single_2 \
  -e _citus_to_db=dev \
  -e _pg_user=admin -e _pg_password=admin \
  -t tenant \
  -e _citus_tenant_name=myfarm1 \
  -e _citus_tenant_password=myfarm1
```

## pg_hba 配置

Citus 节点间通过 PG 协议通信，需要 pg_hba 允许跨节点连接。

默认配置 `host all all 0.0.0.0/0 md5` 已满足需求。

**可选优化 — 节点间 trust 免密**：

```yaml
# group_vars 中配置
patroni_citus_nodes:
  - pg_single_1
  - pg_single_2
  - pg_single_3
```

配置后更新并重启：

```bash
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml -e HOSTS=$host -t patroni-config
done
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible -i hosts.ini $host -b -m shell -a "supervisorctl restart patroni"
done
```

## 水平扩容

1. 在新节点安装 citus 扩展（同前置条件步骤）
2. 配置新节点 DNS
3. 使用剧本添加新 worker
4. 重新分片（低峰期执行）：

```sql
SELECT rebalance_table_shards();
```

## 删除节点

```sql
-- 查看节点持有的分片
SELECT * FROM pg_dist_shard_placement WHERE nodename='pg_single_2' AND nodeport=5432;

-- 迁移分片后再移除节点
SELECT citus_remove_node('pg_single_2', 5432);
```

## 完全移除 Citus

```sql
-- 1. 逐个移除 worker
SELECT citus_remove_node('pg_single_3', 5432);
SELECT citus_remove_node('pg_single_2', 5432);

-- 2. 移除 coordinator
SELECT citus_remove_node('pg_single_1', 5432);
```

```bash
# 3. 删除扩展
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible -i hosts.ini $host -b -m shell -a \
    "PGPASSWORD='<password>' psql -h localhost -p 5432 -U admin -d dev \
     -c 'DROP EXTENSION IF EXISTS citus CASCADE;'"
done

# 4. 从 group_vars 移除 citus 配置，更新并重启
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml -e HOSTS=$host -t patroni-config
done
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible -i hosts.ini $host -b -m shell -a "supervisorctl restart patroni"
done
```
