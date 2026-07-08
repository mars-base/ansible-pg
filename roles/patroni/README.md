数据库访问架构
===

App -> Haproxy -> [pgbouncer -> Patroni/Postgres]

patroni 集群操作
===

查看etcd配置
---

ETCDCTL_API=2 etcdctl --endpoints=http://192.168.1.13:12379 ls /service --recursive


删除etcd配置
---

ETCDCTL_API=2 etcdctl --endpoints=http://192.168.1.13:12379 rm /service/batman/ --recursive


登录到patroni节点执行
---

列出所有节点状态

sudo /srv/py3venv/bin/patronictl -c /srv/patroni/pg.yaml list

重启从库 batman是集群默认名称

sudo /srv/py3venv/bin/patronictl -c /srv/patroni/pg.yaml restart batman -r replica

重启主库

sudo /srv/py3venv/bin/patronictl -c /srv/patroni/pg.yaml restart batman -r primary

重载配置
---

curl -XPOST http://192.168.1.11:8008/reload && echo

修改配置 修改后需要重载配置
---

curl -X PATCH http://192.168.1.12:8008/config -H "Content-Type: application/json" -d '{"postgresql":{"parameters":{"restore_command":"pgbackrest --stanza=patroni_backup archive-get %f %p"}}}'


集群成员
---

curl -s http://192.168.1.11:8008/cluster |jq

主从切换
---

sudo /srv/py3venv/bin/patronictl -c /srv/patroni/pg.yaml switchover


PITR备份恢复
===
    ```
    在使用pgbackrest恢复数据库时，需要先停止所有数据库实例，包括主库和从库。

    使用patronictl pause 暂停所有数据库实例 将 Patroni 集群置于维护模式并禁用自动故障转移。
    sudo /srv/py3venv/bin/patronictl -c /srv/patroni/pg.yaml pause
    > Success: cluster management is paused

    sudo /srv/py3venv/bin/patronictl -c /srv/patroni/pg.yaml list
    + Cluster: batman (7599590669847416613) ------+----+-------------+-----+------------+-----+
    | Member | Host         | Role    | State     | TL | Receive LSN | Lag | Replay LSN | Lag |
    +--------+--------------+---------+-----------+----+-------------+-----+------------+-----+
    | pg01   | 192.168.1.11 | Leader  | running   |  2 |             |     |            |     |
    | pg02   | 192.168.1.12 | Replica | streaming |  2 |  0/21013530 |   0 | 0/21013530 |   0 |
    +--------+--------------+---------+-----------+----+-------------+-----+------------+-----+
    Maintenance mode: on -- 维护模式 开启


    停止所有从库 patroni
    sudo supervisorctl stop patroni
    手动执行停止数据库实例
    sudo -iu postgres /usr/lib/postgresql/17/bin/pg_ctl -D /srv/patroni/postgres/data stop -m fast
    检查是否有数据库进程残留
    ps aux |grep postgres |grep -v -i -E '(pgbouncer|grep)'

    停止主库 patroni
    sudo supervisorctl stop patroni
    手动执行停止数据库实例
    sudo -iu postgres /usr/lib/postgresql/17/bin/pg_ctl -D /srv/patroni/postgres/data stop -m fast
    检查是否有数据库进程残留
    ps aux |grep postgres |grep -v -i -E '(pgbouncer|grep)'

    在备份服务器上查看全量备份信息
    sudo -iu postgres pgbackrest --stanza=patroni_backup info
    stanza: patroni_backup
        status: ok
        cipher: none

        db (current)
            wal archive min/max (17): 000000010000000000000001/000000010000000000000005

            full backup: 20260130-152543F
                timestamp start/stop: 2026-01-30 15:25:43+08 / 2026-01-30 15:25:48+08
                wal start/stop: 000000010000000000000005 / 000000010000000000000005
                database size: 36.8MB, database backup size: 36.8MB
                repo1: backup set size: 4.8MB, backup size: 4.8MB


    在primary节点上 恢复数据库操作
    【注意】
    PITR时间点要在全量备份时间点之后

    【可选】备份数据目录
    sudo -iu postgres cp -ra /srv/patroni/postgres/data{,.bak}
    - 建议备份pg_wal目录，避免恢复时丢失wal归档文件
    sudo -iu postgres mkdir -p /srv/patroni/postgres/pg_wal.bak
    sudo -iu postgres cp -ran /srv/patroni/postgres/data/pg_wal /srv/patroni/postgres/pg_wal.bak

    删除primary节点的 data目录
    sudo -iu postgres
    rm -rf /srv/patroni/postgres/data/*

    执行恢复数据库操作
    sudo -iu postgres pgbackrest --stanza=patroni_backup --type=time "--target=2026-01-30 15:30:00" --target-action=promote --log-level-console=info restore

    启动patroni
    sudo supervisorctl start patroni

    恢复自动故障转移
    sudo /srv/py3venv/bin/patronictl -c /srv/patroni/pg.yaml resume
    > Success: cluster management is resumed

    检查数据库状态
    sudo /srv/py3venv/bin/patronictl -c /srv/patroni/pg.yaml list
    发现数据库状态为replica stopped
    需要等待一段时间 数据库状态变成Leader

    在primary节点上 检查数据库状态
    sudo -iu postgres PGPASSWORD=postgres psql -h 192.168.1.11 -p 5432 -U postgres -c "SELECT now(); SELECT pg_is_in_recovery();"
    2026-01-30 15:30:00.000000+08 | f
    数据库状态为f 说明数据库已成为主库

    启动所有的从库 patroni
    sudo supervisorctl start patroni

    检查所有从库状态
    sudo /srv/py3venv/bin/patronictl -c /srv/patroni/pg.yaml list
    发现所有从库状态为streaming 说明从库已启动

    最后，再次检查primary和replica节点是否数据一致
    同时在primary和replica节点上运行
    查看时间线
    sudo -iu postgres PGPASSWORD=postgres psql -h 192.168.1.12 -p 5432 -U postgres -c "SELECT pg_is_in_recovery(), timeline_id FROM pg_control_checkpoint();"

    在primary上查看WAL复制状态
    sudo -iu postgres PGPASSWORD=postgres psql -h 192.168.1.11 -p 5432 -U postgres -c "SELECT client_addr, application_name, state, sync_state, flush_lsn, replay_lsn FROM pg_stat_replication;"
    > flush_lsn 和 replay_lsn 相同，表示副本节点已处理完接收到的日志


    【注意】
    如果发现replica节点数据和primary节点数据不一致，可以强制重建replica节点pg02或其他
    可以加上 --wait 和 --from-leader 参数
    sudo /srv/py3venv/bin/patronictl -c /srv/patroni/pg.yaml reinit batman pg02 --force

    ```
