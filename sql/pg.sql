-- \l
-- \dt
-- \d users;
-- \dn
-- \dx

-- -- \x 竖版显示
-- \x
-- open time show
\timing
-- -- 显示 NULL 值为 'NULL'
\pset null 'NULL'

-- -- 获取表的列信息
-- -- ordinal_position 列序号
-- -- column_name 列名
-- -- data_type 数据类型
-- -- is_nullable 是否可空
-- -- column_default 默认值
-- SELECT ordinal_position, column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_name = 'ads';

-- 列出当前数据库所有表
select table_schema, table_name
from information_schema.tables
where table_catalog = current_database()
order by 1, 2;

-- -- 获取用户权限
-- -- rolname 用户名
-- -- rolsuper 是否是超级用户
-- -- rolinherit 是否可以继承权限
-- SELECT rolname, rolsuper, rolinherit
-- FROM pg_roles;

-- -- 获取归档状态
-- SELECT * FROM pg_stat_archiver;

-- -- 从 Parquet 文件中读取数据，按城市分组统计，并添加别名
-- select
--     r['city'] as city,
--     count(*) as record_count,
--     sum(r['temp_lo']) as total_temp_lo,
--     sum(r['temp_hi']) as total_temp_hi,
--     sum(r['prcp']) as total_prcp
-- from read_parquet(
--     '/pg/data/*.parquet'
-- ) r
-- group by r['city']
-- order by r['city'];


-- -- read from s3

-- SELECT * FROM read_csv(
--   's3://olap/t.csv?s3_access_key_id=tZonSwKwutmK2eOtst80&s3_secret_access_key=4TDTn5bsgVT1U939Sbqz4lfOH4DRUTlhj0LlDUtQ&s3_endpoint=127.0.0.1:9000&s3_url_style=path&s3_use_ssl=false'
-- );

-- SELECT * FROM read_parquet(
--   's3://olap/weather-1.3y.parquet?s3_access_key_id=tZonSwKwutmK2eOtst80&s3_secret_access_key=4TDTn5bsgVT1U939Sbqz4lfOH4DRUTlhj0LlDUtQ&s3_endpoint=127.0.0.1:9000&s3_url_style=path&s3_use_ssl=false'
-- ) limit 10;

    --      city      | temp_lo | temp_hi | prcp |    date
    -- ---------------+---------+---------+------+------------
    --  San Francisco |      46 |      50 | 0.25 | 1994-11-27
    --  New York      |      43 |      57 | 0.12 | 1994-11-29
    --  San Francisco |      46 |      50 | 0.25 | 1994-11-27
    --  New York      |      43 |      57 | 0.12 | 1994-11-29
    --  San Francisco |      46 |      50 | 0.25 | 1994-11-27
    --  New York      |      43 |      57 | 0.12 | 1994-11-29
    --  San Francisco |      46 |      50 | 0.25 | 1994-11-27
    --  New York      |      43 |      57 | 0.12 | 1994-11-29
    --  San Francisco |      46 |      50 | 0.25 | 1994-11-27
    --  New York      |      43 |      57 | 0.12 | 1994-11-29
    -- (10 rows)

-- SELECT count(*) as total_cnt FROM read_parquet(
-- 's3://olap/weather-1.3y.parquet?s3_access_key_id=tZonSwKwutmK2eOtst80&s3_secret_access_key=4TDTn5bsgVT1U939Sbqz4lfOH4DRUTlhj0LlDUtQ&s3_endpoint=127.0.0.1:9000&s3_url_style=path&s3_use_ssl=false'
-- ) t;

-- copy (
--     SELECT * FROM read_parquet(
--     's3://olap/weather-1.3y.parquet?s3_access_key_id=tZonSwKwutmK2eOtst80&s3_secret_access_key=4TDTn5bsgVT1U939Sbqz4lfOH4DRUTlhj0LlDUtQ&s3_endpoint=127.0.0.1:9000&s3_url_style=path&s3_use_ssl=false'
--     ) t limit 10
-- ) to 's3://olap/weather-1.3y.limit10.csv?s3_access_key_id=tZonSwKwutmK2eOtst80&s3_secret_access_key=4TDTn5bsgVT1U939Sbqz4lfOH4DRUTlhj0LlDUtQ&s3_endpoint=127.0.0.1:9000&s3_url_style=path&s3_use_ssl=false';


-- -- 从 Parquet 文件中读取数据，按城市分组统计，并添加别名
-- select
--     r['city'] as city,
--     count(*) as record_count,
--     sum(r['temp_lo']) as total_temp_lo,
--     sum(r['temp_hi']) as total_temp_hi,
--     sum(r['prcp']) as total_prcp
-- from read_parquet(
--     's3://olap/weather-1.3y.parquet?s3_access_key_id=tZonSwKwutmK2eOtst80&s3_secret_access_key=4TDTn5bsgVT1U939Sbqz4lfOH4DRUTlhj0LlDUtQ&s3_endpoint=127.0.0.1:9000&s3_url_style=path&s3_use_ssl=false'
-- ) r
-- group by r['city']
-- order by r['city'];


-- -- 计算 prcp、temp_lo 和 temp_hi 字段的平均值，并分别命名
-- SELECT
--     avg(r['prcp']) as prcp_avg,
--     avg(r['temp_lo']) as temp_lo_avg,
--     avg(r['temp_hi']) as temp_hi_avg
-- FROM read_parquet(
--     's3://olap/weather-1.3y.parquet?s3_access_key_id=tZonSwKwutmK2eOtst80&s3_secret_access_key=4TDTn5bsgVT1U939Sbqz4lfOH4DRUTlhj0LlDUtQ&s3_endpoint=127.0.0.1:9000&s3_url_style=path&s3_use_ssl=false'
-- ) r;

-- -- 使用通配符 读取s3 parquet文件
-- SELECT count(*) as total_cnt FROM read_parquet(
--   's3://olap/data/*.parquet?s3_access_key_id=tZonSwKwutmK2eOtst80&s3_secret_access_key=4TDTn5bsgVT1U939Sbqz4lfOH4DRUTlhj0LlDUtQ&s3_endpoint=127.0.0.1:9000&s3_url_style=path&s3_use_ssl=false'
-- );
-- SELECT count(*) as file_4_cnt FROM read_parquet(
--   's3://olap/data/[1|2|4-5].parquet?s3_access_key_id=tZonSwKwutmK2eOtst80&s3_secret_access_key=4TDTn5bsgVT1U939Sbqz4lfOH4DRUTlhj0LlDUtQ&s3_endpoint=127.0.0.1:9000&s3_url_style=path&s3_use_ssl=false'
-- );

-- select distinct r['namespace'] as ns_all from read_csv('/pg/vm.csv') r;
-- select count(*) as cnt from read_csv('/pg/vm.csv') r;

-- copy (
-- select distinct r['ip'] from read_csv('/pg/ips-ntes.csv') r
-- order by r['ip']
-- ) to '/pg/vpn-ip.csv';


-- -- verify citus distribution
-- select count(*) from emp;

-- -- 查看citus集群节点
-- SELECT * FROM citus_get_active_worker_nodes();

-- -- 查询分片位置，验证数据分布
-- SELECT * FROM pg_dist_shard_placement;

-- -- 指定 shardid 列来自 pg_dist_shard 表
-- SELECT 'emp' as table_name, pg_dist_shard.shardid, shardstate, shardlength, placementid, nodename, nodeport
-- FROM pg_dist_shard_placement
-- JOIN pg_dist_shard ON pg_dist_shard_placement.shardid = pg_dist_shard.shardid
-- JOIN pg_dist_partition ON pg_dist_shard.logicalrelid = pg_dist_partition.logicalrelid
-- WHERE pg_dist_partition.logicalrelid = 'emp'::regclass
-- order by nodename;

-- -- 测试删除一个worker节点
-- -- 迁移 shardid 为 102018 的分片
-- SELECT master_move_shard_placement(102018, 'dev2', 5432, 'dev3', 5432);
-- -- 迁移 shardid 为 102020 的分片
-- SELECT master_move_shard_placement(102020, 'dev2', 5432, 'dev3', 5432);
-- -- 依次类推，迁移其他分片
-- SELECT master_move_shard_placement(102022, 'dev2', 5432, 'dev3', 5432);
-- SELECT master_move_shard_placement(102024, 'dev2', 5432, 'dev3', 5432);
-- SELECT master_move_shard_placement(102026, 'dev2', 5432, 'dev3', 5432);
-- SELECT master_move_shard_placement(102028, 'dev2', 5432, 'dev3', 5432);
-- SELECT master_move_shard_placement(102030, 'dev2', 5432, 'dev3', 5432);
-- SELECT master_move_shard_placement(102032, 'dev2', 5432, 'dev3', 5432);
-- SELECT master_move_shard_placement(102034, 'dev2', 5432, 'dev3', 5432);
-- SELECT master_move_shard_placement(102036, 'dev2', 5432, 'dev3', 5432);
-- SELECT master_move_shard_placement(102038, 'dev2', 5432, 'dev3', 5432);

-- -- 查看dev2节点上是否还有分片
-- SELECT * FROM pg_dist_shard_placement where nodename='dev2' and nodeport=5432;

-- -- 从citus集群中移除节点 -- 需要管理员账号
-- SELECT citus_remove_node('dev2', 5432);


-- -- ---------------------- 测试 ----------------------
-- CREATE TABLE companies (
--     id bigint NOT NULL,
--     name text NOT NULL,
--     image_url text,
--     created_at timestamp without time zone NOT NULL,
--     updated_at timestamp without time zone NOT NULL
-- );

-- CREATE TABLE campaigns (
--     id bigint NOT NULL,
--     company_id bigint NOT NULL,
--     name text NOT NULL,
--     cost_model text NOT NULL,
--     state text NOT NULL,
--     monthly_budget bigint,
--     blacklisted_site_urls text[],
--     created_at timestamp without time zone NOT NULL,
--     updated_at timestamp without time zone NOT NULL
-- );

-- CREATE TABLE ads (
--     id bigint NOT NULL,
--     company_id bigint NOT NULL,
--     campaign_id bigint NOT NULL,
--     name text NOT NULL,
--     image_url text,
--     target_url text,
--     impressions_count bigint DEFAULT 0,
--     clicks_count bigint DEFAULT 0,
--     created_at timestamp without time zone NOT NULL,
--     updated_at timestamp without time zone NOT NULL
-- );

-- ALTER TABLE companies ADD PRIMARY KEY (id);
-- ALTER TABLE campaigns ADD PRIMARY KEY (id, company_id);
-- ALTER TABLE ads ADD PRIMARY KEY (id, company_id);

-- \copy companies from '/pg/companies.csv' with csv
-- \copy campaigns from '/pg/campaigns.csv' with csv
-- \copy ads from '/pg/ads.csv' with csv
-- select count(*) as company_cnt from companies;
-- select count(*) as campaign_cnt from campaigns;
-- select count(*) as ad_cnt from ads;
-- -- ------------ End

-- -- 查看myfarm1.users表的分片分布
-- (
--     SELECT 'myfarm1.users' as table_name, pg_dist_shard.shardid, shardstate, shardlength, placementid, nodename, nodeport
--     FROM pg_dist_shard_placement
--     JOIN pg_dist_shard ON pg_dist_shard_placement.shardid = pg_dist_shard.shardid
--     JOIN pg_dist_partition ON pg_dist_shard.logicalrelid = pg_dist_partition.logicalrelid
--     WHERE pg_dist_partition.logicalrelid = 'myfarm1.users'::regclass
-- )
-- UNION ALL
-- -- 查看myfarm2.users表的分片分布
-- (
--     SELECT 'myfarm2.users' as table_name, pg_dist_shard.shardid, shardstate, shardlength, placementid, nodename, nodeport
--     FROM pg_dist_shard_placement
--     JOIN pg_dist_shard ON pg_dist_shard_placement.shardid = pg_dist_shard.shardid
--     JOIN pg_dist_partition ON pg_dist_shard.logicalrelid = pg_dist_partition.logicalrelid
--     WHERE pg_dist_partition.logicalrelid = 'myfarm2.users'::regclass
-- )
-- UNION ALL
-- -- 查看myfarm3.users表的分片分布
-- (
--     SELECT 'myfarm3.users' as table_name, pg_dist_shard.shardid, shardstate, shardlength, placementid, nodename, nodeport
--     FROM pg_dist_shard_placement
--     JOIN pg_dist_shard ON pg_dist_shard_placement.shardid = pg_dist_shard.shardid
--     JOIN pg_dist_partition ON pg_dist_shard.logicalrelid = pg_dist_partition.logicalrelid
--     WHERE pg_dist_partition.logicalrelid = 'myfarm3.users'::regclass
-- )
-- ORDER BY table_name, nodename;


-- 查看数据库里所有的分布式schema
-- select * from citus_schemas;

-- -- 查看数据库里所有的分布式表 节点分布和所在节点的上的存储大小
-- select nodename, nodeport, table_name, pg_size_pretty(sum(shard_size))
-- from citus_shards
-- group by nodename, nodeport, table_name
-- order by table_name, nodename;

-- -- 查看数据库里所有的分布式表大小
-- SELECT table_name, table_size
--   FROM citus_tables;
