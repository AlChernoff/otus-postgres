-- HW08: выполняйте блоки ПО ОТДЕЛЬНОСТИ, ориентируясь на заголовки.
-- Все команды SQL запускаются внутри psql; Linux-команды см. commands.txt.
-- База: hw08db. Сценарии выполняются в учебной базе, не в production.

-- [SETUP: суперпользователь, каждый ALTER SYSTEM отдельным вызовом]
ALTER SYSTEM SET log_lock_waits = on;
-- ВЫПОЛНИТЬ ОТДЕЛЬНО (нельзя обе ALTER SYSTEM одним psql -c):
ALTER SYSTEM SET deadlock_timeout = '200ms';
-- После перезагрузки конфигурации: SHOW log_lock_waits; SHOW deadlock_timeout;

-- [SETUP: одна свободная сессия в hw08db]
CREATE TABLE IF NOT EXISTS orders (id integer PRIMARY KEY, status text NOT NULL);
INSERT INTO orders (id, status) VALUES (1, 'new')
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status;

-- [QUEUE, SESSION 1]
SET application_name = 'hw08_session_1';
BEGIN;
UPDATE orders SET status = 'processing' WHERE id = 1;
-- Держать открытой до снятия pg_locks.

-- [QUEUE, SESSION 2]
SET application_name = 'hw08_session_2';
BEGIN;
UPDATE orders SET status = 'courier_assigned' WHERE id = 1;
-- Ожидает SESSION 1.

-- [QUEUE, SESSION 3]
SET application_name = 'hw08_session_3';
BEGIN;
UPDATE orders SET status = 'delivered' WHERE id = 1;
-- Ожидает SESSION 2 на tuple.

-- [MONITOR: ЧЕТВЁРТАЯ свободная сессия]
SELECT a.pid, a.application_name, a.state, a.wait_event_type, a.wait_event,
       l.locktype, l.mode, l.granted,
       l.relation::regclass AS relation, l.transactionid,
       pg_blocking_pids(a.pid) AS blocked_by
FROM pg_stat_activity AS a
JOIN pg_locks AS l ON l.pid = a.pid
WHERE a.datname = 'hw08db'
  AND a.application_name LIKE 'hw08_session_%'
ORDER BY a.application_name, l.granted, l.locktype;

-- [QUEUE CLEANUP: SESSION 1 COMMIT; затем SESSION 2 и 3 ROLLBACK]
-- Не вставлять эти команды в сессии, пока UPDATE ожидает.

-- [THREE-WAY DEADLOCK: SETUP после завершения прежних транзакций]
INSERT INTO orders (id, status)
VALUES (2, 'new'), (3, 'new')
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status;

-- [THREE-WAY DEADLOCK: SESSION 1]
BEGIN;
UPDATE orders SET status = 'session_1' WHERE id = 1;
-- Затем, ПОСЛЕ захвата остальных двух строк:
UPDATE orders SET status = 'wait_2' WHERE id = 2;

-- [THREE-WAY DEADLOCK: SESSION 2]
BEGIN;
UPDATE orders SET status = 'session_2' WHERE id = 2;
-- Затем:
UPDATE orders SET status = 'wait_3' WHERE id = 3;

-- [THREE-WAY DEADLOCK: SESSION 3]
BEGIN;
UPDATE orders SET status = 'session_3' WHERE id = 3;
-- Затем, последним, чтобы замкнуть цикл:
UPDATE orders SET status = 'wait_1' WHERE id = 1;
-- После ошибки deadlock выполнить ROLLBACK во всех трёх сессиях.

-- [STAR: SETUP, свободная сессия]
DROP TABLE IF EXISTS deadlock_star;
CREATE TABLE deadlock_star (id integer PRIMARY KEY, value integer NOT NULL);
INSERT INTO deadlock_star SELECT i, i FROM generate_series(1, 10000) AS i;
CREATE INDEX deadlock_star_value_idx ON deadlock_star (value DESC);
ANALYZE deadlock_star;
SELECT count(*) FROM deadlock_star;
EXPLAIN (COSTS OFF) UPDATE deadlock_star SET value = value + 1;
-- Проверка в другой сессии с enable_seqscan = off, enable_bitmapscan = off
-- тоже дала Seq Scan; это не вызвало deadlock в чистом сценарии.

-- [STAR: CONTROLLED TRIGGER SETUP]
CREATE TABLE star_resources (id integer PRIMARY KEY, value integer NOT NULL DEFAULT 0);
INSERT INTO star_resources (id) VALUES (1), (2);
CREATE OR REPLACE FUNCTION star_update_trigger()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('application_name') = 'star_a' THEN
        UPDATE star_resources SET value = value + 1 WHERE id = 1;
        PERFORM pg_sleep(2);
        UPDATE star_resources SET value = value + 1 WHERE id = 2;
    ELSE
        UPDATE star_resources SET value = value + 1 WHERE id = 2;
        PERFORM pg_sleep(2);
        UPDATE star_resources SET value = value + 1 WHERE id = 1;
    END IF;
    RETURN NULL;
END;
$$;
CREATE TRIGGER star_deadlock_trigger
BEFORE UPDATE ON deadlock_star
FOR EACH STATEMENT
EXECUTE FUNCTION star_update_trigger();

-- [STAR: SESSION A; отправить обновление]
SET application_name = 'star_a';
UPDATE deadlock_star SET value = value + 1;

-- [STAR: SESSION B; отправить обновление в пределах двух секунд]
SET application_name = 'star_b';
UPDATE deadlock_star SET value = value + 1;

-- [CLEANUP: только когда все конкурентные запросы и транзакции завершены]
DROP TRIGGER IF EXISTS star_deadlock_trigger ON deadlock_star;
DROP FUNCTION IF EXISTS star_update_trigger();
-- Проверка:
SELECT tgname FROM pg_trigger
WHERE tgrelid = 'deadlock_star'::regclass AND NOT tgisinternal;
