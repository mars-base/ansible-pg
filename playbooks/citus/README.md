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

## pg_hba 配置

Citus 节点间通过 PostgreSQL 协议通信（分布式查询、shard 路由等），需要 pg_hba 规则允许跨节点连接。

当前 patroni 模板（`roles/patroni/templates/pg.yaml`）中的 pg_hba 规则：

```yaml
pg_hba:
  - host replication replicator {{ postgres_replication_trust_cidr }} md5
  - host replication replicator 127.0.0.1/32 md5
  - host all all 0.0.0.0/0 md5
```

- `host all all 0.0.0.0/0 md5`：Citus 分布式查询走这条规则，允许所有来源的 md5 密码认证连接
- citus.yaml 中所有 psql 命令都已传递 `PGPASSWORD`，md5 认证没有问题
- 认证方法由 `postgres_hba_auth_method` 控制，默认 `md5`（`roles/patroni/defaults/main.yml`）

**默认配置已满足 Citus 基础需求，无需额外 hba 配置。**

**可选优化 — 节点间 trust 免密**：

如果希望 Citus 节点间免密通信（减少分布式查询的密码传递开销），
可修改 patroni 模板，在 `0.0.0.0/0 md5` 规则之前添加 trust 规则：

```yaml
# 在 roles/patroni/templates/pg.yaml 的 pg_hba 中添加（放在 0.0.0.0/0 之前）
# - host all all {{ hostvars['pg_single_1']['ansible_host'] }}/32 trust
# - host all all {{ hostvars['pg_single_2']['ansible_host'] }}/32 trust
# - host all all {{ hostvars['pg_single_3']['ansible_host'] }}/32 trust
```

修改后更新 hba 并重启：

```bash
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
    -e HOSTS=$host -t patroni-config
done
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible -i hosts.ini $host -b -m shell -a "supervisorctl restart patroni"
done
```

> 注意：pg_hba 位于 `bootstrap.dcs` 下，只在集群首次初始化时写入 etcd。
> 已有集群修改 hba 需要通过 `patronictl edit-config` 操作，或通过 `-t patroni-config` 重新生成 pg.yaml 并重启生效。

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

## 删除 Citus

完全移除 Citus 分布式配置，恢复到普通 PostgreSQL 单节点。

### 1. 移除所有 worker 节点

```sql
-- 查询当前 worker 列表
SELECT * FROM citus_get_active_worker_nodes();

-- 逐个移除 worker（需要先迁移分片数据，参考上方"删除节点"章节）
SELECT citus_remove_node('pg_single_3', 5432);
SELECT citus_remove_node('pg_single_2', 5432);
```

### 2. 移除 coordinator 注册

```sql
SELECT citus_remove_node('pg_single_1', 5432);
```

### 3. 清理 DNS 记录

手动编辑各节点 `/etc/hosts`，删除 Citus 节点相关的行。

### 4. 移除 citus 扩展

```bash
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible -i hosts.ini $host -b -m shell -a \
    "PGPASSWORD='<password>' psql -h localhost -p 5432 -U admin -d dev \
     -c 'DROP EXTENSION IF EXISTS citus CASCADE;'"
done
```

### 5. 移除 citus 配置并重启

在各节点的 group_vars 中：
- 从 `postgres_shared_preload_libraries` 移除 `citus`
- 从 `pg_extensions` 移除 `citus`
- 从 `pg_extensions_on` 移除 citus 相关条目

然后更新配置并重启：

```bash
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible-playbook -i hosts.ini playbooks/pg-ha-cluster.yaml \
    -e HOSTS=$host -t patroni-config
done
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible -i hosts.ini $host -b -m shell -a "supervisorctl restart patroni"
done
```

### 6. 卸载 apt 包（可选）

```bash
for host in pg_single_1 pg_single_2 pg_single_3; do
  ansible -i hosts.ini $host -b -m apt -a "name=postgresql-17-citus-13.0 state=absent"
done
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
