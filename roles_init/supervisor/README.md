# supervisor

## 概述

进程托管服务

## 说明

### supervisor_do_restart

变更时是否执行重启，改选项目的是避免托管进程被意外重启。默认True，发生变更时总是重启服务进程以及托管进程。

### supervisor_conf_d

`include`配置文件目录，一般用于配置托管进程。默认为`/etc/supervisor/conf.d`，一般无需修改。

### supervisor_sock_chown

`/var/run/supervisor.sock`的文件的归属，通过修改改Sock文件的权限，可以使得普通用户使用`supervisorctl`命令。默认为`root:root`。

## 样例

```yaml
---

supervisor_do_restart: false
supervisor_sock_chown: deployer:root
```
