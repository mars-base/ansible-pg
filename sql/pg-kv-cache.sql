-- PostgreSQL 缓存方案 （基于 UNLOGGED TABLE 在数据库崩溃或非正常关机时会清空所有数据，仅适用于可重建的缓存）
-- 创建缓存表 替换掉redis缓存
-- 高性能（UNLOGGED TABLE）
-- 自动过期（TTL + 分批清理）
-- 安全并发（UPSERT 原子性 ON CONFLICT 保证 SET 原子性；GET 无副作用，天然并发安全）
-- 资源可控（每次清理 ≤1000 行）
-- 注意事项：
-- 1. 大 Key/Value 避免单条记录 > 1MB，否则影响性能
-- 2. Vacuum UNLOGGED TABLE 仍需 VACUUM 回收空间，但可降低频率
-- 3. 在低频场景（< 500 QPS）下完全可用，高频场景仍建议 Redis


-- 缓存数据结构
-- key: 缓存键（TEXT）
-- value: 缓存值（BYTEA）
-- expires_at: 过期时间（TIMESTAMPTZ）

-- 缓存操作函数
-- SET/GET/DEL

-- 缓存清理策略
-- 方案1：定时任务（如 CRON）调用 kv_cleanup_batch() 清理过期数据
-- 建议每 5 分钟运行一次，清理 1000 条过期数据
-- 方案2：应用层中定期调用 kv_cleanup_batch() 清理过期数据
-- 建议在业务低峰期调用，避免对正常业务造成影响

-- SQL使用示例
-- -- 示例：设置缓存 过期时间 10 秒
-- SELECT kv_set('user:123', '{"name":"张三","age":30}', 10);
-- -- 示例：设置缓存 过期时间 10 秒 并返回是否成功
-- SELECT kv_set_with_result('user:123', '{"name":"张三","age":30}', 10);

-- -- 示例：获取缓存
-- SELECT kv_get('user:123');

-- -- 示例：将缓存值转换为文本
-- SELECT kv_get_text('user:123');

-- -- 示例：删除缓存
-- SELECT kv_del('user:123');

-- -- 示例：清理过期缓存
-- SELECT kv_cleanup_batch(1000);  -- 返回实际删除数量


-- 使用 UNLOGGED TABLE：写入更快，但崩溃会丢失数据（适合缓存）
CREATE UNLOGGED TABLE IF NOT EXISTS kv_cache (
    key TEXT PRIMARY KEY,
    value BYTEA NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);

-- 为过期时间建索引，加速清理
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_kv_cache_expires ON kv_cache (expires_at);


-- 操作函数 SET/GET/DEL

-- SET（带TTL过期时间，默认5分钟）
CREATE OR REPLACE FUNCTION kv_set(
    p_key TEXT,
    p_value BYTEA,
    p_ttl_seconds INT DEFAULT 300  -- 默认 5 分钟
) RETURNS VOID AS $$  -- 声明为 VOID 类型，不返回任何值
BEGIN
    INSERT INTO kv_cache (key, value, expires_at)
    VALUES (p_key, p_value, NOW() + INTERVAL '1 second' * p_ttl_seconds)
    ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, expires_at = EXCLUDED.expires_at;
END;
$$ LANGUAGE plpgsql;

-- SET 带返回值 bool 类型
-- 返回布尔值表示是否成功
CREATE OR REPLACE FUNCTION kv_set_with_result(
    p_key TEXT,
    p_value BYTEA,
    p_ttl_seconds INT DEFAULT 300
) RETURNS BOOLEAN AS $$
BEGIN
    INSERT INTO kv_cache (key, value, expires_at)
    VALUES (p_key, p_value, NOW() + INTERVAL '1 second' * p_ttl_seconds)
    ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, expires_at = EXCLUDED.expires_at;

    RETURN TRUE;  -- 明确返回成功状态
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;  -- 返回失败状态
END;
$$ LANGUAGE plpgsql;


-- GET
CREATE OR REPLACE FUNCTION kv_get(p_key TEXT)
RETURNS BYTEA AS $$
DECLARE
    result BYTEA;
BEGIN
    SELECT value INTO result
    FROM kv_cache
    WHERE key = p_key AND expires_at > NOW();

    IF result IS NOT NULL THEN
        RETURN result;
    ELSE
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 辅助函数，将缓存值转换为文本
CREATE OR REPLACE FUNCTION kv_get_text(p_key TEXT)
RETURNS TEXT AS $$
DECLARE
    result BYTEA;
BEGIN
    SELECT value INTO result
    FROM kv_cache
    WHERE key = p_key AND expires_at > NOW();

    IF result IS NOT NULL THEN
        RETURN convert_from(result, 'UTF8');
    ELSE
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- DEL
CREATE OR REPLACE FUNCTION kv_del(p_key TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM kv_cache WHERE key = p_key;
END;
$$ LANGUAGE plpgsql;


-- 分批清理过期数据（每次 ≤1000 条）
-- 每次最多删 1000 行，避免长事务阻塞
-- 返回实际删除数量，便于监控
-- 使用 CTE + ORDER BY 确保清理顺序
CREATE OR REPLACE FUNCTION kv_cleanup_batch(max_rows INT DEFAULT 1000)
RETURNS INT AS $$
DECLARE
    deleted_count INT;
BEGIN
    WITH expired AS (
        SELECT key
        FROM kv_cache
        WHERE expires_at < NOW()
        ORDER BY expires_at  -- 按过期时间排序，优先清理最早过期的
        LIMIT max_rows
    )
    DELETE FROM kv_cache
    WHERE key IN (SELECT key FROM expired);

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- 显示缓存表结构
\d+ kv_cache

-- 测试用例
\pset null 'NULL'
SELECT kv_set('user:101', '{"name":"张三","age":30}', 1000) AS set_user_101;
SELECT kv_set_with_result('user:102', '{"name":"李四","age":30}', 1000) AS set_user_102;
-- 检查缓存是否存在
SELECT kv_get_text('user:101') AS get_user_101_text;
SELECT kv_get_text('user:102') AS get_user_102_text;
-- 删除
SELECT kv_del('user:101') AS del_user_101;
SELECT kv_del('user:102') AS del_user_102;
-- 检查缓存是否不存在
SELECT kv_get('user:101') IS NULL AS get_user_101_null;
SELECT kv_get_text('user:102') AS get_user_102_text;
-- 清理过期缓存
SELECT kv_cleanup_batch(1000) AS cleanup_batch;
