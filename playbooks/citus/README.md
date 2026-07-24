# Citus 分布式 PostgreSQL 数据库部署剧本

## ⚠️ 重要：架构要求

Citus 必须配合多个 Patroni 单节点使用，不能使用 Patroni HA 自动故障切换！

原因：Patroni 自动 failover 后，Citus 元数据（pg_dist_node）不会自动更新，
导致 coordinator 找不到 worker、worker 找不到 coordinator，整个分布式集群不可用。

**正确架构**：

```
pg_single_1 (Patroni 单节点) ←→ coordinator
pg_single_2 (Patroni 单节点) ←→ worker
pg_single_3 (Patroni 单节点) ←→ worker
```

**错误架构**：

```
Patroni HA 集群（1 primary + N replica）× Citus ❌
```

## 作用

1. 在 coordinator 和 worker 节点上安装 citus 扩展
2. 配置节点间 DNS 解析
3. 注册 coordinator 和 worker 节点到 citus 集群
4. 创建多租户 schema（可选）

## 参数说明

| 参数 | 说明 |
|------|------|
| `_coordinator_hostname` | 协调器主机名（如 `pg_single_1`） |
| `_worker_hostname` | 工作节点主机名（如 `pg_single_2`） |
| `_citus_to_db` | citus 扩展安装到的数据库名，仅在此数据库里使用 citus 分布式 |
| `_pg_user` | pg 的管理员账号（如 `admin`） |
| `_pg_password` | pg 管理员账号密码 |
| `_postgres_port` | postgresql 端口（默认 5432） |
| `_citus_all_nodes` | 所有节点主机名列表，用于配置 DNS |
| `_citus_tenant_name` | 多租户名称（可选，配合 `-t tenant`） |
| `_citus_tenant_password` | 多租户密码（可选，配合 `-t tenant`） |

## 前置条件 - 安装 citus 扩展（多个 Patroni 单节点）

Citus 需要在所有节点上安装扩展，假设有 3 个单节点分组：
- `pg_single_1` (coordinator)
- `pg_single_2` (worker)
- `pg_single_3` (worker)

### 1. 在每个节点的 group_vars 中添加 citus 配置

```yaml
# group_vars/pg_single_1/pg_all.yaml
# group_vars/pg_single_2/pg_all.yaml
# group_vars/pg_single_3/pg_all.yaml
postgres_shared_preload_libraries: "pg_cron,pg_stat_statements,uuid-ossp,citus"

pg_extensions:
  - "pg_cron"
  - "citus"

pg_extensions_on:
  - { db: 'dev', extension: 'citus' }
```

### 2. 在所有节点安装扩展包（apt 包）

```bash
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
    -e HOSTS=$host -t pg-extension
done
```

### 3. 在所有节点更新 Patroni 配置并重启 PostgreSQL

```bash
# 更新配置（生成 pg.yaml，包含 shared_preload_libraries）
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
    -e HOSTS=$host -t patroni-config
done

# 重启所有节点的 PostgreSQL（使 shared_preload_libraries 生效）
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible -i hosts.ini $host -b -m shell \
    -a "supervisorctl restart patroni"
done
```

### 4. 在所有节点创建扩展（CREATE EXTENSION）

注意：需要传入 `pg_create_extensions=true`，否则 create block 会被跳过。

```bash
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
    -e HOSTS=$host -e pg_create_extensions=true -t create
done
```

## 使用本剧本配置集群

每执行一次添加一个 worker 节点：

```bash
# 添加 pg_single_2 为 worker：
ansible-playbook -i hosts.ini playbooks/citus/citus.yaml \
  -e _coordinator_hostname=pg_single_1 \
  -e _worker_hostname=pg_single_2 \
  -e _citus_to_db=dev \
  -e _pg_user=admin \
  -e _pg_password=admin

# 添加 pg_single_3 为 worker：
ansible-playbook -i hosts.ini playbooks/citus/citus.yaml \
  -e _coordinator_hostname=pg_single_1 \
  -e _worker_hostname=pg_single_3 \
  -e _citus_to_db=dev \
  -e _pg_user=admin \
  -e _pg_password=admin
```

## 验证集群状态

```bash
ansible-playbook -i hosts.ini playbooks/citus/citus.yaml \
  -e _coordinator_hostname=pg_single_1 -e _worker_hostname=pg_single_2 \
  -e _citus_to_db=dev -e _pg_user=admin -e _pg_password=admin \
  -t verify
```

## 配置所有节点 DNS

```bash
playbooks/citus/citus.yaml \
  -e _coordinator_hostname=pg_single_1 \
  -e _citus_to_db=dev \
  -e _pg_user=admin -e _pg_password=admin \
  -e _worker_hostname=pg_single_2 \
  -t dns \
  -e "_citus_all_nodes=['pg_single_1','pg_single_2','pg_single_3','pg_single_4']"
```

## 水平扩容节点

如果所有节点在同一网段（pg_single 默认 `postgres_replication_trust_cidr` 为 `/24`），
hba 无需修改，跳到步骤 3 即可。仅当新节点在不同网段时才需要步骤 1-2。

1. 更新 group_vars 中 `postgres_replication_trust_cidr` 增加新节点 IP 网段
2. 在所有节点更新 Patroni 配置并重启使 hba 生效

```bash
for host in pg_single_1 pg_single_2 pg_single_3 pg_single_4; do
  ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
    -e HOSTS=$host -t patroni-config
done
for host in pg_single_1 pg_single_2 pg_single_3 pg_single_4; do
  ansible -i hosts.ini $host -b -m shell -a "supervisorctl restart patroni"
done
```

3. 配置新节点的 DNS（参考上面的"配置所有节点 DNS"）
4. 使用本剧本添加新 worker（参考上方"使用本剧本配置集群"示例）
5. 在 coordinator 执行重新分片以分担数据负载（低峰期）：

```sql
SELECT rebalance_table_shards();
```

## 删除节点

```sql
-- 查询 shardid 分片数据
SELECT * FROM pg_dist_shard_placement WHERE nodename='pg_single_2' AND nodeport=5432;
-- 如果返回非空结果，说明它还持有数据，不能直接删除

-- 根据上面的查询结果逐个移动分片
-- SELECT master_move_shard_placement(102018, 'pg_single_2', 5432, 'pg_single_3', 5432);

-- 当该节点上不再持有任何分片后，可以安全移除
-- SELECT citus_remove_node('pg_single_2', 5432); -- 需要管理员账号
-- 这会从 pg_dist_node 中删除该条记录，并停止将其用于新分片分配。
```

## 创建 Citus 多租户（可选）

适用于对 schema 进行分布式的场景，schema 对应租户名一致：

```bash
playbooks/citus/citus.yaml \
  -e _coordinator_hostname=pg_single_1 \
  -e _citus_to_db=dev \
  -e _pg_user=admin -e _pg_password=admin \
  -e _worker_hostname=pg_single_2 \
  -t tenant \
  -e _citus_tenant_name=myfarm1 -e _citus_tenant_password=myfarm1

playbooks/citus/citus.yaml \
  -e _coordinator_hostname=pg_single_1 \
  -e _citus_to_db=dev \
  -e _pg_user=admin -e _pg_password=admin \
  -e _worker_hostname=pg_single_2 \
  -t tenant \
  -e _citus_tenant_name=myfarm2 -e _citus_tenant_password=myfarm2

playbooks/citus/citus.yaml \
  -e _coordinator_hostname=pg_single_1 \
  -e _citus_to_db=dev \
  -e _pg_user=admin -e _pg_password=admin \
  -e _worker_hostname=pg_single_2 \
  -t tenant \
  -e _citus_tenant_name=myfarm3 -e _citus_tenant_password=myfarm3
```
