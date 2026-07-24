-- Test SQL file for pgsql.yaml
CREATE TABLE IF NOT EXISTS test_pgsql_playbook (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO test_pgsql_playbook (name) VALUES ('test1'), ('test2'), ('test3');

SELECT * FROM test_pgsql_playbook;
