-- HW10: Индексы PostgreSQL 17.11
-- Учебная база: hw09db; отдельная схема: hw10.
-- ВНИМАНИЕ: скрипт повторного развёртывания пересоздаёт учебную схему hw10.

DROP SCHEMA IF EXISTS hw10 CASCADE;
CREATE SCHEMA hw10;
SET search_path TO hw10, public;

CREATE TABLE orders (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_number text NOT NULL,
    customer_name text NOT NULL,
    delivery_zone integer NOT NULL,
    description text NOT NULL,
    status text NOT NULL,
    created_at timestamp NOT NULL
);

-- 50 000 заказов: достаточно данных, чтобы увидеть осмысленный выбор плана.
INSERT INTO orders (order_number, customer_name, delivery_zone, description, status, created_at)
SELECT
    'ORD-' || lpad(i::text, 6, '0'),
    'Клиент ' || i,
    (i % 20) + 1,
    CASE
        WHEN i % 997 = 0 THEN 'Трюфельная пицца с грибами'
        WHEN i % 3 = 0 THEN 'Пицца с сыром и томатами'
        WHEN i % 3 = 1 THEN 'Бургер с картофелем'
        ELSE 'Салат с овощами'
    END,
    CASE
        WHEN i % 4 = 0 THEN 'new'
        WHEN i % 4 = 1 THEN 'processing'
        WHEN i % 4 = 2 THEN 'delivering'
        ELSE 'completed'
    END,
    timestamp '2026-11-01 00:00:00' + (i * interval '1 minute')
FROM generate_series(1, 50000) AS i;
ANALYZE orders;

-- 1. Обычный B-tree: точечный поиск по номеру заказа.
-- Первичный ключ id создаёт собственный индекс orders_pkey автоматически,
-- поэтому дополнительный индекс строим по другому столбцу.
CREATE INDEX idx_orders_number ON orders USING btree (order_number);
COMMENT ON INDEX idx_orders_number IS
'B-tree индекс для быстрого поиска заказа по order_number';

-- 2. GIN: полнотекстовый поиск с русским стеммингом.
-- Выражение в запросе должно совпадать с выражением индекса.
CREATE INDEX idx_orders_description_fts
ON orders USING gin (to_tsvector('russian', description));
COMMENT ON INDEX idx_orders_description_fts IS
'GIN-индекс для полнотекстового поиска по описанию заказа на русском языке';

-- 3. Функциональный B-tree: поиск по приведённому к нижнему регистру имени.
CREATE INDEX idx_orders_customer_lower ON orders (lower(customer_name));
COMMENT ON INDEX idx_orders_customer_lower IS
'Функциональный индекс для поиска клиентов без учёта регистра';

-- 4. Составной B-tree: равенство по зоне плюс диапазон дат.
-- Порядок столбцов важен: сначала delivery_zone, затем created_at.
CREATE INDEX idx_orders_zone_created ON orders (delivery_zone, created_at);
COMMENT ON INDEX idx_orders_zone_created IS
'Составной индекс для поиска заказов по зоне доставки и времени создания';

-- Проверка использования обычного индекса.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE order_number = 'ORD-025000';

-- Проверка GIN индекса; 50 совпадений в тестовом наборе.
SELECT count(*) AS found_fts FROM orders
WHERE to_tsvector('russian', description)
      @@ plainto_tsquery('russian', 'трюфельная');
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE to_tsvector('russian', description)
      @@ plainto_tsquery('russian', 'трюфельная');

-- Проверка функционального индекса.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE lower(customer_name) = lower('Клиент 25000');

-- Проверка составного индекса.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE delivery_zone = 7
  AND created_at >= timestamp '2026-11-10 00:00:00'
  AND created_at < timestamp '2026-11-11 00:00:00';

-- Список индексов и фактически сохранённые в каталоге комментарии.
SELECT c.relname AS index_name,
       pg_get_indexdef(c.oid) AS index_definition,
       obj_description(c.oid, 'pg_class') AS comment
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'hw10' AND c.relkind IN ('i', 'I')
ORDER BY c.relname;
