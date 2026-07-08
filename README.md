# ansible-pg

使用 Ansible 部署 PostgreSQL（基于 Patroni 的高可用集群）。

## 项目结构

```
.
├── ansible.cfg              # 本地 Ansible 配置（不提交）
├── ansible.cfg.example      # Ansible 配置示例
├── hosts.ini                # 本地 inventory（含真实 IP/用户名，不提交）
├── hosts.ini.example        # inventory 示例
├── requirements.txt         # pip 依赖
├── pyproject.toml           # uv/pip 项目依赖
├── uv.lock                  # uv 锁定文件
├── playbooks/
│   ├── pg-ha-cluster.yaml   # 部署 Patroni + pgbouncer + pgbackrest HA 集群
│   ├── pgsql.yaml           # 在 PostgreSQL 上执行 SQL 文件
│   ├── pgdump.yaml          # 备份 PostgreSQL 数据库
│   └── citus.yaml           # 在已有 PostgreSQL 上配置 Citus 分布式扩展
├── roles/                   # PostgreSQL 相关 roles
│   ├── patroni              # Patroni + PostgreSQL
│   ├── patroni-wait         # 等待 Patroni 集群就绪
│   ├── patroni-initdb       # 初始化数据库、用户、权限
│   ├── pgbouncer            # 连接池
│   ├── pgbackrest           # 备份恢复
│   ├── pg-extension         # PostgreSQL 扩展
│   ├── pgdog                # 分片代理（可选）
│   ├── postgrest            # RESTful API（可选）
│   ├── pgpitr               # PITR 恢复（可选）
│   ├── etcd_cluster         # etcd 集群（Patroni 依赖）
│   ├── proxy_haproxy_multi  # HAProxy 读写分离
│   ├── py3venv              # Python 虚拟环境
│   └── cron                 # pgbackrest 定时全量备份
├── roles_init/              # 基础依赖 roles
│   ├── supervisor
│   ├── logrotate
│   └── rsyslog
├── group_vars/              # 分组变量（核心配置，必须按环境修改）
│   ├── pg_cluster/          # HA 集群配置
│   │   ├── pg_all.yaml.example
│   │   └── pg_all.yaml      # 本地生成，不提交（含密码）
│   ├── pg_fish/             # 单节点测试配置
│   │   ├── pg_all.yaml.example
│   │   └── pg_all.yaml      # 本地生成，不提交（含密码）
│   └── dev/                 # pgbouncer 等独立覆盖
├── host_vars/               # 主机变量
│   └── pg-single/pgdog.yaml # pgdog 示例配置
├── sql/                     # SQL 初始化脚本
└── scripts/                 # 测试/辅助脚本
    ├── postgres_api_test.py
    ├── postgres_health_check.py
    └── postgres_sub_pub_test.py
```

## 环境准备

### 使用 uv（推荐）

```bash
uv sync
source .venv/bin/activate
```

### 使用 pip

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 配置 inventory 和分组变量

1. 复制示例 ansible.cfg 并调整：

```bash
cp ansible.cfg.example ansible.cfg
# 默认示例中 inventory=hosts.ini，remote_port=32200，可按实际环境修改
```

2. 复制示例 inventory 并按实际环境修改：

```bash
cp hosts.ini.example hosts.ini
# 编辑 hosts.ini，替换为实际的主机 IP、用户名
```

3. 复制示例 group_vars 并替换密码：

```bash
# HA 集群配置
cp group_vars/pg_cluster/pg_all.yaml.example group_vars/pg_cluster/pg_all.yaml
# 单节点测试配置
cp group_vars/pg_fish/pg_all.yaml.example group_vars/pg_fish/pg_all.yaml

# 编辑上述 pg_all.yaml，将所有 CHANGEME 替换为实际密码
# 建议使用 Ansible Vault 加密敏感字段
```

4. **重点**：修改 `group_vars/pg_cluster/pg_all.yaml` 或 `group_vars/pg_fish/pg_all.yaml`：
   - 节点角色 `pg_node_role`
   - PostgreSQL 管理员/业务用户密码
   - etcd 地址、pgbackrest 仓库路径与 stanza
   - 防火墙可信网段

## 快速开始

### 单节点测试部署

```bash
ansible-playbook -e HOSTS=pg_fish playbooks/pg-ha-cluster.yaml
```

### 双节点 HA 集群部署

```bash
ansible-playbook -e HOSTS=pg_cluster playbooks/pg-ha-cluster.yaml
```

### 只初始化数据库、用户、权限

```bash
ansible-playbook -e HOSTS=pg_cluster playbooks/pg-ha-cluster.yaml -t initdb
```

### 执行 SQL 文件

```bash
ansible-playbook -e HOSTS=pg_cluster playbooks/pgsql.yaml \
  -e pg_port=5432 \
  -e pg_user=dba \
  -e pg_password=dba \
  -e pg_database=dev \
  -e sql_file=pg.sql
```

### 备份数据库

```bash
ansible-playbook -e HOSTS=pg_cluster playbooks/pgdump.yaml \
  -e _mode=sql \
  -e _db=dev \
  -e _user=dba \
  -e _password=dba
```

## 常用 Tag

| Tag | 说明 |
|-----|------|
| `py3venv` | 部署 Python 虚拟环境 |
| `etcd_cluster` | 部署 etcd |
| `haproxy` | 部署 HAProxy |
| `pgbouncer` | 部署 pgbouncer |
| `patroni` | 部署 Patroni + PostgreSQL |
| `patroni-config` | 只更新 Patroni 配置 |
| `initdb` | 初始化数据库、用户、权限 |
| `pg-extension` | 安装 PostgreSQL 扩展 |
| `pgbackrest` | 部署 pgbackrest |
| `cron` | 配置定时备份 |
| `postgrest` | 部署 PostgREST |

## 注意事项

1. `ansible.cfg`、`hosts.ini`、`group_vars/*/pg_all.yaml`、`host_vars/*/pgdog.yaml` 已加入 `.gitignore`，不会提交到仓库；首次使用请从对应的 `.example` 文件复制并修改。
2. 首次部署会安装 PostgreSQL 17，如需其他版本，修改 `postgres_version`。
3. `pgbackrest` 通过 ssh 免密连接，请在对应的 `group_vars/*/pg_all.yaml` 中配置 `pgbackrest_ssh_private_key` 与 `pgbackrest_ssh_public_key`；原 `roles/pgbackrest/files/id_rsa_pgbackrest*` 硬编码密钥已移除。
4. `roles/*/defaults/main.yml` 中的密码类变量默认值为 `CHANGEME`，部署前请在 `group_vars/*/pg_all.yaml` 或 `host_vars/*/pgdog.yaml` 中替换为实际值。
5. 各 role 的详细说明见 `roles/<role>/README.md`。
6. 测试脚本 `scripts/*.py` 中的连接串多为示例，使用前请按需修改。

## 来源

本项目文件整理自 `/home/fish/leihuo/just-for-fun`，仅保留 PostgreSQL 部署相关部分。
