-- 用户表
-- 示例调用

-- 创建扩展以支持UUID生成（如果尚未创建）
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 创建扩展以支持密码加密（如果尚未创建）
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 创建用户表，使用JSONB存储用户数据，user_id采用UUID类型
CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
    password_hash TEXT NOT NULL,  -- 密码哈希字段
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_data JSONB
);

-- 创建索引以提高查询性能
CREATE INDEX IF NOT EXISTS idx_users_user_id ON users(user_id);
CREATE INDEX IF NOT EXISTS idx_users_user_data_gin ON users USING GIN (user_data);

-- 创建插入用户的函数
-- 创建新用户函数，返回用户ID和创建时间(user_id, created_at)
-- 在应用层调用此函数时，需要处理返回的(NULL, NULL)情况, 表示用户名已存在, 不允许重复注册
DROP FUNCTION IF EXISTS new_user;
CREATE OR REPLACE FUNCTION new_user(
    p_username VARCHAR(255),
    p_password TEXT,
    p_profile JSONB DEFAULT '{}'
) RETURNS TABLE(
    user_id UUID,
    created_at TIMESTAMP
) AS $$
DECLARE
    v_user_id UUID;
    v_email TEXT;
    v_phone TEXT;
    v_gender TEXT;
    v_age INTEGER;
BEGIN
    -- 检查用户名是否已存在，如果存在则返回NULL
    IF EXISTS (SELECT 1 FROM users WHERE user_data->>'username' = p_username) THEN
        RETURN QUERY SELECT NULL::UUID, NULL::TIMESTAMP;
        RETURN;
    END IF;

    -- 生成新的用户ID
    v_user_id := uuid_generate_v4();

    -- 从 profile JSON 中提取信息
    v_email := COALESCE(p_profile->>'email', '');
    v_phone := COALESCE(p_profile->>'phone', '');
    v_gender := COALESCE(p_profile->>'gender', '');
    v_age := CASE
        WHEN p_profile ? 'age' AND jsonb_typeof(p_profile->'age') = 'number'
        THEN (p_profile->>'age')::INTEGER
        ELSE NULL
    END;

    -- 插入新用户
    INSERT INTO users (user_id, password_hash, user_data)
    VALUES (
        v_user_id,
        crypt(p_password, gen_salt('bf', 13)), -- 使用 bcrypt 加密密码，成本因子为 13，较高的成本因子增加密码存储的安全性
        json_build_object(
            'username', p_username,
            'email', v_email,
            'profile', json_build_object(
                'first_name', '',
                'last_name', '',
                'age', v_age,
                'gender', v_gender,
                'phone', v_phone,
                'bio', ''
            ),
            'login_info', json_build_object(
                'last_login', NULL,
                'login_count', 0,
                'failed_attempts', 0
            ),
            'preferences', json_build_object(
                'theme', 'light',
                'language', 'zh-CN',
                'notifications', json_build_object(
                    'email', true,
                    'push', true,
                    'sms', false
                )
            ),
            'status', 'active',
            'metadata', json_build_object(
                'created_ip', '',
                'last_activity', NULL,
                'session_timeout', 3600
            )
        )::jsonb
    );

    -- 返回新创建的用户信息（修复：使用 NOW()::timestamp 以确保类型匹配）
    RETURN QUERY SELECT v_user_id, NOW()::timestamp;
END;
$$ LANGUAGE plpgsql;


-- 查询用户信息，根据user_id，返回用户ID、创建时间、更新时间和用户数据，用户数据返回json格式的字符串
DROP FUNCTION IF EXISTS get_user_by_id;
CREATE OR REPLACE FUNCTION get_user_by_id(input_user_id UUID)
RETURNS TABLE(
    user_id UUID,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    user_data TEXT
) AS $$
BEGIN
    RETURN QUERY SELECT u.user_id, u.created_at, u.updated_at, u.user_data::TEXT
        FROM users u
        WHERE u.user_id = input_user_id;
END;
$$ LANGUAGE plpgsql;

-- 检查用户是否存在，根据用户名
DROP FUNCTION IF EXISTS user_exists;
CREATE OR REPLACE FUNCTION user_exists(input_username VARCHAR(255))
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM users u WHERE u.user_data->>'username' = input_username
    );
END;
$$ LANGUAGE plpgsql;

-- 查询当前所有用户的总数
CREATE OR REPLACE FUNCTION count_all_users()
RETURNS BIGINT AS $$
DECLARE
    user_count BIGINT;
BEGIN
    SELECT COUNT(u.user_id) INTO user_count FROM users u;
    RETURN user_count;
END;
$$ LANGUAGE plpgsql;


-- 验证密码是否匹配，根据用户ID和输入密码
DROP FUNCTION IF EXISTS verify_password;
CREATE OR REPLACE FUNCTION verify_password(input_user_id UUID, input_password TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    stored_password_hash TEXT;
BEGIN
    -- 检查用户是否存在
    IF NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = input_user_id) THEN
        RETURN FALSE;
    END IF;

    -- 获取存储的密码哈希
    SELECT password_hash INTO stored_password_hash
    FROM users u
    WHERE u.user_id = input_user_id;

    -- 验证密码是否匹配
    IF stored_password_hash IS NOT NULL THEN
        RETURN crypt(input_password, stored_password_hash) = stored_password_hash;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 验证输入的用户名和密码是否匹配
DROP FUNCTION IF EXISTS verify_login;
CREATE OR REPLACE FUNCTION verify_login(input_username VARCHAR(255), input_password TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    user_id UUID;
BEGIN
    -- 检查用户名是否存在
    IF NOT user_exists(input_username) THEN
        RETURN FALSE;
    END IF;

    -- 获取用户ID
    SELECT u.user_id INTO user_id
    FROM users u
    WHERE u.user_data->>'username' = input_username;

    -- 验证密码是否匹配
    RETURN verify_password(user_id, input_password);
END;
$$ LANGUAGE plpgsql;


-- 将用户的状态设置为 inactive
DROP FUNCTION IF EXISTS set_user_inactive;
CREATE OR REPLACE FUNCTION set_user_inactive(input_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    -- 检查用户是否存在
    IF NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = input_user_id) THEN
        RETURN FALSE;
    END IF;

    -- 更新用户状态为 inactive，同时更新updated_at字段
    UPDATE users u
    SET user_data = jsonb_set(u.user_data, '{status}', '"inactive"'),
        updated_at = NOW()
    WHERE u.user_id = input_user_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- 检查用户是否 active
DROP FUNCTION IF EXISTS is_user_active;
CREATE OR REPLACE FUNCTION is_user_active(input_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    -- 检查用户是否存在
    IF NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = input_user_id) THEN
        RETURN FALSE;
    END IF;

    -- 检查用户状态是否为 active
    RETURN (SELECT u.user_data->>'status' FROM users u WHERE u.user_id = input_user_id) = 'active';
END;
$$ LANGUAGE plpgsql;


-- 测试
\pset null 'NULL'
\timing
\x
SELECT * FROM new_user('john_doe', 'secure_password', '{"email":"john@example.com","phone":"13800138000","gender":"male","age":30}');
SELECT * FROM get_user_by_id('6902163e-4a11-4bcd-9708-66fc254fdce0');
SELECT user_exists('john_doe');
SELECT user_exists('john_do'); -- 失败，用户名不存在
SELECT count_all_users();
SELECT verify_password('6902163e-4a11-4bcd-9708-66fc254fdce0', 'secure_password');
SELECT verify_password('6902163e-4a11-4bcd-9708-66fc254fdce0', 'secure_passwor'); -- 失败，密码错误
SELECT verify_login('john_doe', 'secure_password'); -- 成功
SELECT verify_login('john_do', 'secure_password'); -- 失败，用户名不存在
SELECT verify_login('john_doe', 'secure_passwor'); -- 失败，密码错误
SELECT set_user_inactive('6902163e-4a11-4bcd-9708-66fc254fdce0');
SELECT * FROM get_user_by_id('6902163e-4a11-4bcd-9708-66fc254fdce0');
SELECT is_user_active('6902163e-4a11-4bcd-9708-66fc254fdce0') as is_active; -- 失败，用户状态为 inactive
