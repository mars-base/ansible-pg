-- 统计 CSV 文件中的记录数
select count(*) as cnt from read_csv('/pg/vm.csv') r;

-- 从 CSV 文件中读取数据，使用 r 作为结果集别名
WITH csv_data AS (
    SELECT
        -- 显式将 r['dataVolume'] 转换为 TEXT 类型，再进行替换操作
        CAST(REPLACE(CAST(r['dataVolume'] AS TEXT), 'Gi', '') AS DOUBLE PRECISION) AS data_volume_num
    FROM read_csv('/pg/vm.csv') r
    -- 筛选出 node 列为 指定node名称 的记录
    WHERE r['node'] = 'lhcloud6'
)
-- 对筛选后的 dataVolume 数值进行求和
SELECT SUM(data_volume_num) AS total_data_volume
FROM csv_data;
