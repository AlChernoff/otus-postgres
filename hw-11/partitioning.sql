-- HW11: Секционирование bookings по месяцам (PostgreSQL 17, база demo).
-- Подключаться к базе demo; исходная bookings.bookings НЕ меняется.
-- ВНИМАНИЕ: следующий DROP удаляет только ранее созданную учебную таблицу
-- hw11.bookings_part с её секциями и данными. Не выполняйте при наличии
-- собственных ценных данных в этой учебной таблице.

-- 1. Диагностика структуры и дат исходной таблицы.
-- В psql отдельно можно выполнить: \d bookings.bookings
SELECT count(*) AS total_bookings,
       min(book_date) AS first_booking,
       max(book_date) AS last_booking
FROM bookings.bookings;

-- Явный UTC обеспечивает сопоставимое группирование и вывод месяцев.
SET TIME ZONE 'UTC';
SELECT date_trunc('month', book_date) AS month, count(*) AS bookings_count
FROM bookings.bookings
GROUP BY 1 ORDER BY 1;

-- 2. План до секционирования: сентябрь 2025, интервал [начало, конец).
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM bookings.bookings
WHERE book_date >= timestamptz '2025-09-01 00:00:00+00'
  AND book_date <  timestamptz '2025-10-01 00:00:00+00';

-- 3. Учебная копия, секционированная по датам бронирования.
CREATE SCHEMA IF NOT EXISTS hw11;
DROP TABLE IF EXISTS hw11.bookings_part CASCADE;

-- Ключ book_date обязательно должен входить в PRIMARY KEY
-- секционированной таблицы; book_ref сам по себе больше не глобально уникален.
CREATE TABLE hw11.bookings_part (
    book_ref character(6) NOT NULL,
    book_date timestamptz NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    PRIMARY KEY (book_ref, book_date)
) PARTITION BY RANGE (book_date);

COMMENT ON TABLE hw11.bookings_part IS
'Учебная RANGE-секционированная копия bookings по месяцам в UTC';

-- Диапазоны FROM включительно, TO исключительно.
CREATE TABLE hw11.bookings_2025_09 PARTITION OF hw11.bookings_part
    FOR VALUES FROM ('2025-09-01 00:00:00+00') TO ('2025-10-01 00:00:00+00');
CREATE TABLE hw11.bookings_2025_10 PARTITION OF hw11.bookings_part
    FOR VALUES FROM ('2025-10-01 00:00:00+00') TO ('2025-11-01 00:00:00+00');
CREATE TABLE hw11.bookings_2025_11 PARTITION OF hw11.bookings_part
    FOR VALUES FROM ('2025-11-01 00:00:00+00') TO ('2025-12-01 00:00:00+00');

-- Страховочная секция для дат вне трёх известных месяцев.
CREATE TABLE hw11.bookings_default PARTITION OF hw11.bookings_part DEFAULT;

-- 4. Перенос оригинальных записей в родителя: маршрутизация по book_date.
INSERT INTO hw11.bookings_part (book_ref, book_date, total_amount)
SELECT book_ref, book_date, total_amount FROM bookings.bookings;
ANALYZE hw11.bookings_part;

-- 5. Проверка физического распределения строк по секциям.
SELECT tableoid::regclass AS partition_name, count(*) AS rows_count
FROM hw11.bookings_part GROUP BY tableoid ORDER BY partition_name;
SELECT (SELECT count(*) FROM bookings.bookings) AS original_count,
       (SELECT count(*) FROM hw11.bookings_part) AS partitioned_count;
-- Отдельная проверка пустоты DEFAULT (она не видна при GROUP BY tableoid).
SELECT count(*) AS default_count FROM hw11.bookings_default;

-- 6. Тот же запрос после секционирования: план должен содержать
-- только hw11.bookings_2025_09 (partition pruning).
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM hw11.bookings_part
WHERE book_date >= timestamptz '2025-09-01 00:00:00+00'
  AND book_date <  timestamptz '2025-10-01 00:00:00+00';

-- 7. CRUD в отменяемой тестовой транзакции.
BEGIN;
-- Декабрь попадает в DEFAULT, т.к. отдельной декабрьской секции нет.
INSERT INTO hw11.bookings_part (book_ref, book_date, total_amount)
VALUES ('HW11ZZ', timestamptz '2025-12-15 12:00:00+00', 15000.00);
SELECT tableoid::regclass AS partition_name, book_ref, book_date, total_amount
FROM hw11.bookings_part WHERE book_ref = 'HW11ZZ';

-- Изменение даты перемещает строку из DEFAULT в ноябрьскую секцию.
UPDATE hw11.bookings_part
SET book_date = timestamptz '2025-11-15 12:00:00+00', total_amount = 17500.00
WHERE book_ref = 'HW11ZZ';
SELECT tableoid::regclass AS partition_name, book_ref, book_date, total_amount
FROM hw11.bookings_part WHERE book_ref = 'HW11ZZ';

-- Удаление через секционированного родителя.
DELETE FROM hw11.bookings_part WHERE book_ref = 'HW11ZZ';
SELECT count(*) FROM hw11.bookings_part WHERE book_ref = 'HW11ZZ';

-- Откат тестовой транзакции: исходный объём данных сохраняется.
ROLLBACK;
SELECT count(*) AS rows_after_rollback FROM hw11.bookings_part;
