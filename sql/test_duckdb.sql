-- DuckDB 扩展测试：商品数据分析
-- 数据文件：/srv/pgsql/products.csv（500 条商品记录）

-- 1. 统计商品总数
SELECT count(*) AS total_products FROM read_csv('/srv/pgsql/products.csv') r;

-- 2. 按品类统计商品数量和平均价格
SELECT
    r['category'] AS category,
    count(*) AS cnt,
    round(avg(CAST(r['price'] AS NUMERIC)), 2) AS avg_price,
    round(sum(CAST(r['sales'] AS NUMERIC)), 0) AS total_sales
FROM read_csv('/srv/pgsql/products.csv') r
GROUP BY r['category']
ORDER BY total_sales DESC;

-- 3. 品牌销售额 TOP 5
SELECT
    r['brand'] AS brand,
    count(*) AS product_count,
    round(sum(CAST(r['price'] AS NUMERIC) * CAST(r['sales'] AS NUMERIC)), 2) AS revenue
FROM read_csv('/srv/pgsql/products.csv') r
GROUP BY r['brand']
ORDER BY revenue DESC
LIMIT 5;

-- 4. 高评分商品（rating >= 4.5）统计
SELECT
    r['city'] AS city,
    count(*) AS high_rated_count,
    round(avg(CAST(r['price'] AS NUMERIC)), 2) AS avg_price
FROM read_csv('/srv/pgsql/products.csv') r
WHERE CAST(r['rating'] AS NUMERIC) >= 4.5
GROUP BY r['city']
ORDER BY high_rated_count DESC;

-- 5. 利润率分析（price vs cost）
SELECT
    r['category'] AS category,
    round(avg(CAST(r['price'] AS NUMERIC) - CAST(r['cost'] AS NUMERIC)), 2) AS avg_profit,
    round(avg((CAST(r['price'] AS NUMERIC) - CAST(r['cost'] AS NUMERIC)) / CAST(r['price'] AS NUMERIC) * 100), 1) AS avg_margin_pct
FROM read_csv('/srv/pgsql/products.csv') r
GROUP BY r['category']
ORDER BY avg_margin_pct DESC;
