注意事项
===

连接数据库
---
```
数据库名称为定义的分片数据库名pgdog
PGPASSWORD=dba psql -h 127.0.0.1 -p 7432 -U dba -d pgdog -c '\dt;'

分片数据库分别为 shard1, shard2
```

创建分片表users
---
```
pgdog=> CREATE TABLE users (
    id BIGINT PRIMARY KEY,
    name VARCHAR(50) NOT NULL
);

INSERT INTO users VALUES (1, 'user1');    -- 可能到 shard0
INSERT INTO users VALUES (2, 'user2');    -- 可能到 shard1
...
```

验证分片表数据是否为根据pgdog_sharded_tables定义的分片列分片
---
```
PGPASSWORD=dba psql -h 127.0.0.1 -p 7432 -U dba -d pgdog -c 'select * from users ;'
```

连接shard1数据库 - 一部分数据
---
```
PGPASSWORD=dba psql -h 127.0.0.1 -p 5432 -U dba -d shard1 -c 'select * from users ;'
```

连接shard2数据库 - 一部分数据
---
```
PGPASSWORD=dba psql -h 127.0.0.1 -p 5432 -U dba -d shard2 -c 'select * from users ;'
```
