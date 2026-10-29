-- HW06: PostgreSQL 17; выполнять в базе postgres.
-- Подготовка pgbench и сам прогон выполняются ИЗ SHELL (не SQL):
-- sudo -u postgres /usr/lib/postgresql/17/bin/pgbench -i postgres
-- sudo -u postgres /usr/lib/postgresql/17/bin/pgbench -c 8 -P 6 -T 60 -U postgres postgres
-- sudo -u postgres psql -d postgres -f commands.sql
-- ВАЖНО: файл ниже демонстрирует этапы последовательно и содержит длительные обновления.
-- Для точного повторения наблюдений выполняйте разделы ПОЭТАПНО,
-- делайте снимок статистики после каждого этапа; autovacuum асинхронен.
-- Не запускайте файл целиком, если вам важны промежуточные измерения.

-- Проверка обслуживания после pgbench:
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, last_vacuum
FROM pg_stat_user_tables ORDER BY relname;

-- Подготовка таблицы (для повторения на чистом учебном стенде):
CREATE TABLE vacuum_test (
    id BIGSERIAL PRIMARY KEY,
    description TEXT NOT NULL
);
INSERT INTO vacuum_test(description)
SELECT 'order_' || generate_series(1, 1000000);
SELECT count(*) FROM vacuum_test;

-- Универсальная проверка размера и статистики:
SELECT relname AS table_name,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       pg_total_relation_size(relid) AS total_size_bytes,
       n_live_tup, n_dead_tup, last_autovacuum, last_vacuum
FROM pg_stat_user_tables WHERE relname = 'vacuum_test';

-- Пять отдельных UPDATE, каждый завершится собственным COMMIT при autocommit=on:
UPDATE vacuum_test SET description = description || 'x';
UPDATE vacuum_test SET description = description || 'x';
UPDATE vacuum_test SET description = description || 'x';
UPDATE vacuum_test SET description = description || 'x';
UPDATE vacuum_test SET description = description || 'x';

-- Снимок статистики после пяти UPDATE:
SELECT relname, n_dead_tup, last_autovacuum, last_vacuum,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables WHERE relname='vacuum_test';
-- Наблюдайте last_autovacuum в отдельной shell-сессии, например:
-- watch -n 5 'sudo -u postgres psql -d postgres -c "SELECT relname,n_dead_tup,last_autovacuum,last_vacuum,pg_size_pretty(pg_total_relation_size(relid)) AS size FROM pg_stat_user_tables WHERE relname = '''vacuum_test''';"'

-- Только для учебной таблицы:
ALTER TABLE vacuum_test SET (autovacuum_enabled = false);
SELECT relname, reloptions FROM pg_class
WHERE oid = 'vacuum_test'::regclass;

-- Задание со звёздочкой: 10 полных обновлений и NOTICE после каждой итерации.
-- Весь DO-блок — одна транзакция; выполнение может быть ресурсоёмким.
DO $$
DECLARE
    i integer;
BEGIN
    FOR i IN 1..10 LOOP
        UPDATE vacuum_test
        SET description = description || 'x';
        RAISE NOTICE 'Итерация % из 10 завершена', i;
    END LOOP;
END;
$$;

SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, last_vacuum,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables WHERE relname='vacuum_test';

-- ОБЯЗАТЕЛЬНО вернуть autovacuum:
ALTER TABLE vacuum_test SET (autovacuum_enabled = true);
SELECT relname, reloptions FROM pg_class
WHERE oid = 'vacuum_test'::regclass;
