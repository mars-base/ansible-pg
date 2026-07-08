pgbackrest 操作
===============

- 登录到备份服务器
  ```
  切换到运行备份程序的 postgres 用户
  sudo -iu postgres
  ```

- 检查备份配置
  ```
  sudo -iu postgres pgbackrest --stanza=patroni_backup --log-level-console=info check
  ```

- 创建备份仓库 stanza
  ```
  sudo -iu postgres pgbackrest --stanza=patroni_backup --log-level-console=info stanza-create
  ```

- 全量 备份数据库
  ```
  sudo -iu postgres pgbackrest --stanza=patroni_backup --log-level-console=info --type=full backup
  ```

- 增量 备份数据库
  ```
  sudo -iu postgres pgbackrest --stanza=patroni_backup --log-level-console=info --type=incr backup
  ```

- 查看备份信息
  ```
  sudo -iu postgres pgbackrest --stanza=patroni_backup --log-level-console=info info
  ```

- 查看wal归档信息
  ```
  # 查看wal最大归档位置
  sudo -iu postgres pgbackrest --stanza=example info --output=json | jq -r '.[0].archive[0].max'
  # 检查主库wal归档是否正常
  SELECT * FROM pg_stat_archiver;
  # 归档命令是否正常 检查patroni的日志
  tail /srv/patroni/logs/*.log
  ```

- 创建定时任务 例子
  ```
  在备份服务器上创建定时任务
  在postgres用户下创建定时任务

  # Full backup every Sunday at 1 AM
  0 1 * * 0 pgbackrest --stanza=patroni_backup --type=full backup

  # Incremental backup every day at 1 AM
  0 1 * * 1-6 pgbackrest --stanza=patroni_backup --type=incr backup
  ```
