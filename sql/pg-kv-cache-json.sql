-- ===========================================================================
-- JSON专用缓存表（基于JSONB类型，支持丰富的JSON查询操作）
-- ===========================================================================

-- 支持的数据类型 采用 TEXT 类型输入
-- 基本类型：整数、浮点数、文本、布尔值
-- 数组类型：整数数组、文本数组等
-- JSON类型：仍然支持JSONB对象
-- NULL值：也支持设置为NULL

-- JSON缓存使用示例
-- -- 设置用户信息缓存（默认300秒）
-- SELECT json_set('user:123', '{"name":"张三","age":30,"active":true}');
-- -- 设置用户信息缓存（10秒过期）（默认300秒）
-- SELECT json_set_with_result('user:123', '{"name":"张三","age":30,"active":true}', 10);
--
-- -- 获取整个JSON对象
-- SELECT json_get('user:123');
--
-- -- 获取特定字段（文本值）
-- SELECT json_get_field('user:123', 'name');  -- 返回 "张三"
--
-- -- 获取特定字段（JSONB值）
-- SELECT json_get_field_json('user:123', 'age');  -- 返回 30
-- -- 获取特定字段（JSONB值）可以直接进行json进一步操作
-- -- SELECT json_get_field_json('user:123', 'address')->>'city' AS address_city;
--
-- -- 检查是否包含特定条件
-- SELECT json_contains('user:123', '{"age":30}');  -- 返回 true
--
-- -- 更新特定字段 ttl可选项（默认300秒）返回boolean
-- -- 更新特定字段（支持多种数据类型，必须是字符串）
-- -- 没有的字段会自动创建
-- -- SELECT json_update_field('user:123', 'age', '19.9');
-- -- SELECT json_update_field('user:123', 'active', 'false');
-- -- SELECT json_update_field('user:123', 'tags', '["vip", "active"]');
-- -- SELECT json_update_field('user:123', 'address', '{"city":"北京","zip":"100000"}');

-- 删除缓存
-- SELECT json_del('user:123');
--
-- -- 清理过期缓存
-- SELECT json_cleanup_batch(1000);

-- JSON专用缓存表
CREATE UNLOGGED TABLE IF NOT EXISTS kv_cache_json (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,                    -- 使用JSONB替代BYTEA
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()     -- 记录创建时间
);

-- 为JSON缓存创建索引
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_kv_cache_json_expires ON kv_cache_json (expires_at);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_kv_cache_json_gin ON kv_cache_json USING GIN (value);


-- JSON专用缓存操作函数

-- SET JSON缓存
CREATE OR REPLACE FUNCTION json_set(
    p_key TEXT,
    p_value JSONB,
    p_ttl_seconds INT DEFAULT 300
) RETURNS VOID AS $$
BEGIN
    INSERT INTO kv_cache_json (key, value, expires_at)
    VALUES (p_key, p_value, NOW() + INTERVAL '1 second' * p_ttl_seconds)
    ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, expires_at = EXCLUDED.expires_at, created_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- SET JSON缓存（带返回值）
CREATE OR REPLACE FUNCTION json_set_with_result(
    p_key TEXT,
    p_value JSONB,
    p_ttl_seconds INT DEFAULT 300
) RETURNS BOOLEAN AS $$
BEGIN
    INSERT INTO kv_cache_json (key, value, expires_at)
    VALUES (p_key, p_value, NOW() + INTERVAL '1 second' * p_ttl_seconds)
    ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, expires_at = EXCLUDED.expires_at, created_at = NOW();

    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- GET JSON缓存（返回JSONB）
CREATE OR REPLACE FUNCTION json_get(p_key TEXT)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT value INTO result
    FROM kv_cache_json
    WHERE key = p_key AND expires_at > NOW();

    IF result IS NOT NULL THEN
        RETURN result;
    ELSE
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- GET JSON缓存中的特定字段（文本值）
CREATE OR REPLACE FUNCTION json_get_field(p_key TEXT, p_field TEXT)
RETURNS TEXT AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT value INTO result
    FROM kv_cache_json
    WHERE key = p_key AND expires_at > NOW();

    IF result IS NOT NULL THEN
        RETURN result->>p_field;
    ELSE
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- GET JSON缓存中的特定字段（JSONB值）
CREATE OR REPLACE FUNCTION json_get_field_json(p_key TEXT, p_field TEXT)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT value INTO result
    FROM kv_cache_json
    WHERE key = p_key AND expires_at > NOW();

    IF result IS NOT NULL THEN
        RETURN result->p_field;
    ELSE
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 检查JSON缓存是否包含特定字段和值
CREATE OR REPLACE FUNCTION json_contains(p_key TEXT, p_query JSONB)
RETURNS BOOLEAN AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT value INTO result
    FROM kv_cache_json
    WHERE key = p_key AND expires_at > NOW();

    IF result IS NOT NULL THEN
        RETURN result @> p_query;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 更新JSON缓存中的特定字段（支持多种数据类型，必须是字符串）
CREATE OR REPLACE FUNCTION json_update_field(
    p_key TEXT,
    p_field TEXT,
    p_new_value TEXT,  -- 统一使用TEXT类型
    p_ttl_seconds INT DEFAULT 300
) RETURNS BOOLEAN AS $$
DECLARE
    current_value JSONB;
    new_json_value JSONB;
BEGIN
    -- 获取当前值
    SELECT value INTO current_value
    FROM kv_cache_json
    WHERE key = p_key AND expires_at > NOW();

    IF current_value IS NOT NULL THEN
        -- 智能转换：尝试解析为JSON，如果失败则作为字符串处理
        BEGIN
            new_json_value := p_new_value::jsonb;
        EXCEPTION
            WHEN invalid_text_representation THEN
                -- 如果不是有效的JSON，则作为字符串处理
                new_json_value := to_jsonb(p_new_value);
        END;

        -- 更新特定字段
        UPDATE kv_cache_json
        SET value = jsonb_set(current_value, ARRAY[p_field], new_json_value),
            expires_at = NOW() + INTERVAL '1 second' * p_ttl_seconds
        WHERE key = p_key;

        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- 删除JSON缓存
CREATE OR REPLACE FUNCTION json_del(p_key TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM kv_cache_json WHERE key = p_key;
END;
$$ LANGUAGE plpgsql;

-- 清理过期JSON缓存
CREATE OR REPLACE FUNCTION json_cleanup_batch(max_rows INT DEFAULT 1000)
RETURNS INT AS $$
DECLARE
    deleted_count INT;
BEGIN
    WITH expired AS (
        SELECT key
        FROM kv_cache_json
        WHERE expires_at < NOW()
        ORDER BY expires_at
        LIMIT max_rows
    )
    DELETE FROM kv_cache_json
    WHERE key IN (SELECT key FROM expired);

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- 显示JSON缓存表结构
\d+ kv_cache_json

-- 补充测试用例
\pset null 'NULL'
SELECT json_set('user:123', '{"name":"张三","age":18,"active":true}');
SELECT json_get('user:123');

SELECT json_get('user:100') AS get_user_100_null;
SELECT json_get_field('user:123', 'email') AS get_field_email_null;

SELECT json_get_field('user:123', 'name') AS name;
SELECT json_get_field_json('user:123', 'age') AS age_json;
SELECT json_contains('user:123', '{"age":18}') AS age_contains;

SELECT json_update_field('user:123', 'age', '18.8') as age_updated;
SELECT json_get('user:123');
SELECT json_contains('user:123', '{"age":18.8}') AS age_contains_updated;

SELECT json_update_field('user:123', 'active', 'false') as active_updated;
SELECT json_get('user:123');
SELECT json_contains('user:123', '{"active":false}') AS active_contains_updated;

select json_update_field('user:123', 'tags', '["tag1","tag2"]') as tags_updated;
SELECT json_get_field_json('user:123', 'tags') AS tags_json;
select json_contains('user:123', '{"tags":["tag1","tag2"]}') AS tags_contains_updated;

SELECT json_update_field('user:123', 'address', '{"city":"北京","zip":"100"}');
SELECT json_get_field_json('user:123', 'address') AS address_json;
SELECT json_get_field_json('user:123', 'address')->>'city' AS address_city;
SELECT json_contains('user:123', '{"address":{"city":"北京"}}') AS address_contains_updated;
SELECT json_contains('user:123', '{"address":{"zip":"100"}}') AS address_contains_zip_100;
SELECT json_contains('user:123', '{"address":{"zip":"101"}}') AS address_contains_zip_101;

SELECT json_cleanup_batch();

SELECT json_del('user:123') AS deleted;

SELECT * from kv_cache_json limit 10;
