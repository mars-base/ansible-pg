操作说明
========

对于patroni集群，需要在每个节点上都安装扩展包，并且重启数据库实例。

使用cli工具依次重启从库、主库，确保所有节点上的数据库实例都重启完成。

根据实际需要修改变量
---

pg_extensions/pg_extensions_on/postgres_shared_preload_libraries

安装扩展包
---

ap -e HOSTS=pg_cluster playbooks/pg-ha-cluster.yaml -t ext

更新配置
---

ap -e HOSTS=pg_cluster playbooks/pg-ha-cluster.yaml -t patroni,patroni-config

重载所有的patroni节点配置
---

curl -XPOST http://192.168.1.11:8008/reload && echo

curl -XPOST http://192.168.1.12:8008/reload && echo

登录到patroni节点 重启从库
---
sudo /srv/py3venv/bin/patronictl -c /srv/patroni/pg.yaml restart batman -r replica

登录到patroni节点 重启主库
---
sudo /srv/py3venv/bin/patronictl -c /srv/patroni/pg.yaml restart batman -r primary

增加扩展需要的权限
---

修改变量postgres_privs，增加扩展需要的权限，根据实际需要添加。
ap -e HOSTS=pg_cluster playbooks/pg-ha-cluster.yaml -t initdb


应用CREATE EXTENSION 语句
---

ap -e HOSTS=pg_cluster playbooks/pg-ha-cluster.yaml -t ext -e pg_create_extensions=true
