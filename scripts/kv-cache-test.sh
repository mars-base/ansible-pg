#!/usr/bin/env bash
#
# KV Cache E2E 测试脚本
# 测试 BYTEA 通用缓存 和 JSONB 专用缓存 的全部函数
#
# 用法：
#   ./scripts/kv-cache-test.sh -P 'your-password'
#   ./scripts/kv-cache-test.sh -h 127.0.0.1 -p 5433 -U dba -P 'H1p21FXF' -d dev
#   PGPASSWORD='your-password' ./scripts/kv-cache-test.sh
#
# 参数：
#   -h  PG host     （默认 10.241.21.97）
#   -p  PG port     （默认 5433）
#   -U  PG user     （默认 dba）
#   -P  PG password （或通过环境变量 PGPASSWORD 传入）
#   -d  PG database （默认 dev）
#   -t  测试类型    （all/bytea/json，默认 all）

set -euo pipefail

# 默认连接参数
PG_HOST="10.241.21.97"
PG_PORT="5433"
PG_USER="dba"
PG_PASS="${PGPASSWORD:-}"
PG_DB="dev"
TEST_TYPE="all"

while getopts "h:p:U:P:d:t:" opt; do
  case $opt in
    h) PG_HOST="$OPTARG" ;;
    p) PG_PORT="$OPTARG" ;;
    U) PG_USER="$OPTARG" ;;
    P) PG_PASS="$OPTARG" ;;
    d) PG_DB="$OPTARG" ;;
    t) TEST_TYPE="$OPTARG" ;;
    *) echo "Usage: $0 -P password [-h host] [-p port] [-U user] [-d database] [-t all|bytea|json]"; exit 1 ;;
  esac
done

if [ -z "$PG_PASS" ]; then
  echo "Error: password required. Use -P 'password' or set PGPASSWORD env var."
  exit 1
fi

export PGPASSWORD="$PG_PASS"
PSQL="psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d $PG_DB -t -A"

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  TOTAL=$((TOTAL + 1))

  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    printf "  \033[32m✓\033[0m %s\n" "$desc"
  else
    FAIL=$((FAIL + 1))
    printf "  \033[31m✗\033[0m %s\n" "$desc"
    printf "    expected: [%s]\n" "$expected"
    printf "    actual:   [%s]\n" "$actual"
  fi
}

# 添加 >= 断言（用于 cleanup_batch 等可能包含额外过期数据的场景）
assert_ge() {
  local desc="$1"
  local min="$2"
  local actual="$3"
  TOTAL=$((TOTAL + 1))

  if [ "$actual" -ge "$min" ] 2>/dev/null; then
    PASS=$((PASS + 1))
    printf "  \033[32m✓\033[0m %s (≥%s, got %s)\n" "$desc" "$min" "$actual"
  else
    FAIL=$((FAIL + 1))
    printf "  \033[31m✗\033[0m %s\n" "$desc"
    printf "    expected: ≥%s\n" "$min"
    printf "    actual:   [%s]\n" "$actual"
  fi
}

run_sql() {
  $PSQL -c "$1" 2>/dev/null
}

# -------------------------------------------------------
# 清理测试数据
# -------------------------------------------------------
cleanup() {
  run_sql "DELETE FROM kv_cache WHERE key LIKE 'e2e:%';" 2>/dev/null || true
  run_sql "DELETE FROM kv_cache_json WHERE key LIKE 'e2e:%';" 2>/dev/null || true
}

# -------------------------------------------------------
# BYTEA 通用缓存测试
# -------------------------------------------------------
test_bytea() {
  echo ""
  echo "═══════════════════════════════════════════"
  echo "  BYTEA 通用缓存测试 (kv_cache)"
  echo "═══════════════════════════════════════════"

  # 1. kv_set - 写入缓存
  echo ""
  echo "▸ kv_set"
  run_sql "SELECT kv_set('e2e:str', 'hello world', 300);"
  local val
  val=$(run_sql "SELECT kv_get_text('e2e:str');")
  assert_eq "kv_set + kv_get_text 写入读取字符串" "hello world" "$val"

  # 写入 JSON 字符串
  run_sql "SELECT kv_set('e2e:json', '{\"name\":\"张三\",\"age\":30}', 300);"
  val=$(run_sql "SELECT kv_get_text('e2e:json');")
  assert_eq "kv_set + kv_get_text 写入读取 JSON 字符串" '{"name":"张三","age":30}' "$val"

  # 2. kv_set_with_result - 写入并返回结果
  echo ""
  echo "▸ kv_set_with_result"
  val=$(run_sql "SELECT kv_set_with_result('e2e:result', 'test value', 300);")
  assert_eq "kv_set_with_result 返回 true" "t" "$val"

  val=$(run_sql "SELECT kv_get_text('e2e:result');")
  assert_eq "kv_set_with_result 数据写入成功" "test value" "$val"

  # 3. kv_set UPSERT - 覆盖写入
  echo ""
  echo "▸ kv_set UPSERT（覆盖写入）"
  run_sql "SELECT kv_set('e2e:upsert', 'v1', 300);"
  val=$(run_sql "SELECT kv_get_text('e2e:upsert');")
  assert_eq "UPSERT 第一次写入" "v1" "$val"

  run_sql "SELECT kv_set('e2e:upsert', 'v2', 300);"
  val=$(run_sql "SELECT kv_get_text('e2e:upsert');")
  assert_eq "UPSERT 覆盖写入" "v2" "$val"

  # 4. kv_get - 读取不存在的 key
  echo ""
  echo "▸ kv_get"
  val=$(run_sql "SELECT kv_get('e2e:not_exist') IS NULL;")
  assert_eq "kv_get 不存在的 key 返回 NULL" "t" "$val"

  val=$(run_sql "SELECT kv_get_text('e2e:not_exist') IS NULL;")
  assert_eq "kv_get_text 不存在的 key 返回 NULL" "t" "$val"

  # 5. kv_del - 删除缓存
  echo ""
  echo "▸ kv_del"
  run_sql "SELECT kv_set('e2e:del', 'to delete', 300);"
  val=$(run_sql "SELECT kv_get_text('e2e:del');")
  assert_eq "kv_del 前数据存在" "to delete" "$val"

  run_sql "SELECT kv_del('e2e:del');"
  val=$(run_sql "SELECT kv_get_text('e2e:del') IS NULL;")
  assert_eq "kv_del 删除后返回 NULL" "t" "$val"

  # 6. TTL 过期测试
  echo ""
  echo "▸ TTL 过期"
  run_sql "SELECT kv_set('e2e:ttl', 'expire soon', 1);"
  val=$(run_sql "SELECT kv_get_text('e2e:ttl');")
  assert_eq "TTL 未过期时能读到" "expire soon" "$val"

  sleep 2
  val=$(run_sql "SELECT kv_get_text('e2e:ttl') IS NULL;")
  assert_eq "TTL 过期后返回 NULL" "t" "$val"

  # 7. kv_cleanup_batch - 批量清理
  echo ""
  echo "▸ kv_cleanup_batch"
  run_sql "SELECT kv_set('e2e:exp1', 'a', 1);"
  run_sql "SELECT kv_set('e2e:exp2', 'b', 1);"
  run_sql "SELECT kv_set('e2e:exp3', 'c', 1);"
  sleep 2
  val=$(run_sql "SELECT kv_cleanup_batch(10);")
  assert_ge "kv_cleanup_batch 至少清理 3 条过期数据" "3" "$val"

  # 再清理一次应该返回 0
  val=$(run_sql "SELECT kv_cleanup_batch(10);")
  assert_eq "kv_cleanup_batch 无过期数据时返回 0" "0" "$val"
}

# -------------------------------------------------------
# JSONB 专用缓存测试
# -------------------------------------------------------
test_json() {
  echo ""
  echo "═══════════════════════════════════════════"
  echo "  JSONB 专用缓存测试 (kv_cache_json)"
  echo "═══════════════════════════════════════════"

  # 1. json_set - 写入
  echo ""
  echo "▸ json_set"
  run_sql "SELECT json_set('e2e:user', '{\"name\":\"张三\",\"age\":18,\"active\":true}'::jsonb, 300);"
  # 检查字段而非完整字符串（JSONB 不保证键顺序）
  val=$(run_sql "SELECT json_get_field('e2e:user', 'name');")
  assert_eq "json_set + json_get_field 写入读取 name" "张三" "$val"
  val=$(run_sql "SELECT json_get_field('e2e:user', 'age');")
  assert_eq "json_set + json_get_field 写入读取 age" "18" "$val"
  val=$(run_sql "SELECT json_get_field('e2e:user', 'active');")
  assert_eq "json_set + json_get_field 写入读取 active" "true" "$val"

  # 2. json_set_with_result - 写入并返回结果
  echo ""
  echo "▸ json_set_with_result"
  val=$(run_sql "SELECT json_set_with_result('e2e:cfg', '{\"debug\":false}'::jsonb, 300);")
  assert_eq "json_set_with_result 返回 true" "t" "$val"

  # 3. json_get - 不存在的 key
  echo ""
  echo "▸ json_get"
  val=$(run_sql "SELECT json_get('e2e:not_exist') IS NULL;")
  assert_eq "json_get 不存在的 key 返回 NULL" "t" "$val"

  # 4. json_get_field - 读取字段文本值
  echo ""
  echo "▸ json_get_field"
  val=$(run_sql "SELECT json_get_field('e2e:user', 'name');")
  assert_eq "json_get_field 读取文本字段" "张三" "$val"

  val=$(run_sql "SELECT json_get_field('e2e:user', 'age');")
  assert_eq "json_get_field 读取数字字段（文本形式）" "18" "$val"

  val=$(run_sql "SELECT json_get_field('e2e:user', 'active');")
  assert_eq "json_get_field 读取布尔字段（文本形式）" "true" "$val"

  val=$(run_sql "SELECT json_get_field('e2e:user', 'email') IS NULL;")
  assert_eq "json_get_field 不存在的字段返回 NULL" "t" "$val"

  # 5. json_get_field_json - 读取字段 JSONB 值
  echo ""
  echo "▸ json_get_field_json"
  val=$(run_sql "SELECT json_get_field_json('e2e:user', 'age');")
  assert_eq "json_get_field_json 读取数字字段" "18" "$val"

  # 6. json_contains - 包含检查
  echo ""
  echo "▸ json_contains"
  val=$(run_sql "SELECT json_contains('e2e:user', '{\"age\":18}'::jsonb);")
  assert_eq "json_contains 匹配返回 true" "t" "$val"

  val=$(run_sql "SELECT json_contains('e2e:user', '{\"name\":\"张三\"}'::jsonb);")
  assert_eq "json_contains 文本匹配" "t" "$val"

  val=$(run_sql "SELECT json_contains('e2e:user', '{\"age\":99}'::jsonb);")
  assert_eq "json_contains 不匹配返回 false" "f" "$val"

  # 7. json_update_field - 局部更新
  echo ""
  echo "▸ json_update_field"

  # 更新数字
  val=$(run_sql "SELECT json_update_field('e2e:user', 'age', '25');")
  assert_eq "json_update_field 更新数字返回 true" "t" "$val"
  val=$(run_sql "SELECT json_get_field('e2e:user', 'age');")
  assert_eq "json_update_field 数字更新生效" "25" "$val"

  # 更新布尔
  val=$(run_sql "SELECT json_update_field('e2e:user', 'active', 'false');")
  assert_eq "json_update_field 更新布尔返回 true" "t" "$val"
  val=$(run_sql "SELECT json_get_field('e2e:user', 'active');")
  assert_eq "json_update_field 布尔更新生效" "false" "$val"

  # 更新数组
  val=$(run_sql "SELECT json_update_field('e2e:user', 'tags', '[\"vip\",\"active\"]');")
  assert_eq "json_update_field 更新数组返回 true" "t" "$val"
  val=$(run_sql "SELECT json_get_field_json('e2e:user', 'tags')::text;")
  assert_eq "json_update_field 数组更新生效" '["vip", "active"]' "$val"

  # 更新嵌套对象
  val=$(run_sql "SELECT json_update_field('e2e:user', 'address', '{\"city\":\"北京\",\"zip\":\"100000\"}');")
  assert_eq "json_update_field 更新嵌套对象返回 true" "t" "$val"
  val=$(run_sql "SELECT json_get_field_json('e2e:user', 'address')->>'city';")
  assert_eq "json_update_field 嵌套对象字段读取" "北京" "$val"

  # 新增字段
  val=$(run_sql "SELECT json_update_field('e2e:user', 'email', '\"test@example.com\"');")
  assert_eq "json_update_field 新增字段返回 true" "t" "$val"
  val=$(run_sql "SELECT json_get_field('e2e:user', 'email');")
  assert_eq "json_update_field 新增字段生效" "test@example.com" "$val"

  # 更新不存在的 key
  val=$(run_sql "SELECT json_update_field('e2e:not_exist', 'field', 'value');")
  assert_eq "json_update_field 不存在的 key 返回 false" "f" "$val"

  # 8. json_del - 删除
  echo ""
  echo "▸ json_del"
  run_sql "SELECT json_set('e2e:del_json', '{\"x\":1}'::jsonb, 300);"
  val=$(run_sql "SELECT json_get_field('e2e:del_json', 'x');")
  assert_eq "json_del 前数据存在" "1" "$val"

  run_sql "SELECT json_del('e2e:del_json');"
  val=$(run_sql "SELECT json_get('e2e:del_json') IS NULL;")
  assert_eq "json_del 删除后返回 NULL" "t" "$val"

  # 9. TTL 过期
  echo ""
  echo "▸ TTL 过期"
  run_sql "SELECT json_set('e2e:ttl_json', '{\"temp\":true}'::jsonb, 1);"
  val=$(run_sql "SELECT json_get_field('e2e:ttl_json', 'temp');")
  assert_eq "TTL 未过期时能读到" "true" "$val"

  sleep 2
  val=$(run_sql "SELECT json_get('e2e:ttl_json') IS NULL;")
  assert_eq "TTL 过期后返回 NULL" "t" "$val"

  # 10. json_cleanup_batch - 批量清理
  echo ""
  echo "▸ json_cleanup_batch"
  run_sql "SELECT json_set('e2e:jexp1', '{\"a\":1}'::jsonb, 1);"
  run_sql "SELECT json_set('e2e:jexp2', '{\"b\":2}'::jsonb, 1);"
  sleep 2
  val=$(run_sql "SELECT json_cleanup_batch(10);")
  assert_ge "json_cleanup_batch 至少清理 2 条过期数据" "2" "$val"

  val=$(run_sql "SELECT json_cleanup_batch(10);")
  assert_eq "json_cleanup_batch 无过期数据时返回 0" "0" "$val"
}

# -------------------------------------------------------
# 执行测试
# -------------------------------------------------------
echo "╔═══════════════════════════════════════════╗"
echo "║        KV Cache E2E Test Suite           ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
echo "Connection: $PG_USER@$PG_HOST:$PG_PORT/$PG_DB"
echo "Test type:  $TEST_TYPE"
echo "Time:       $(date '+%Y-%m-%d %H:%M:%S')"

# 连接测试
echo ""
echo "▸ 连接测试"
pg_version=$(run_sql "SELECT version();" 2>&1 || echo "FAIL")
if [ "$pg_version" = "FAIL" ]; then
  echo "  ✗ 连接失败: $PG_USER@$PG_HOST:$PG_PORT/$PG_DB"
  exit 1
fi
echo "  ✓ $pg_version"

# 检查表是否存在
echo ""
echo "▸ 表存在性检查"
if [ "$TEST_TYPE" = "all" ] || [ "$TEST_TYPE" = "bytea" ]; then
  val=$(run_sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='kv_cache';")
  assert_eq "kv_cache 表存在" "1" "$val"
fi
if [ "$TEST_TYPE" = "all" ] || [ "$TEST_TYPE" = "json" ]; then
  val=$(run_sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='kv_cache_json';")
  assert_eq "kv_cache_json 表存在" "1" "$val"
fi

# 清理旧测试数据
cleanup

# 执行测试
case $TEST_TYPE in
  all)
    test_bytea
    test_json
    ;;
  bytea)
    test_bytea
    ;;
  json)
    test_json
    ;;
  *)
    echo "Invalid test type: $TEST_TYPE (use all/bytea/json)"
    exit 1
    ;;
esac

# 清理测试数据
cleanup

# 结果汇总
echo ""
echo "═══════════════════════════════════════════"
printf "  Results: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m, %d total\n" "$PASS" "$FAIL" "$TOTAL"
echo "═══════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  printf "  \033[31m✗ SOME TESTS FAILED\033[0m\n"
  exit 1
else
  echo ""
  printf "  \033[32m✓ ALL TESTS PASSED\033[0m\n"
  exit 0
fi
