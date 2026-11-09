-- HW09. PostgreSQL: INNER, LEFT, CROSS, FULL и смешанные соединения.
-- Скрипт самодостаточен; запускать целиком в любой учебной базе PostgreSQL.
-- Он изменяет только схему hw09 (если она уже существует, пересоздает ее).

DROP SCHEMA IF EXISTS hw09 CASCADE;
CREATE SCHEMA hw09;
SET search_path TO hw09, public;

-- Структура: зоны доставки, заказы, курьеры и назначения.
CREATE TABLE zones (
    zone_id integer PRIMARY KEY,
    zone_name text NOT NULL UNIQUE
);

CREATE TABLE orders (
    order_id integer PRIMARY KEY,
    customer_name text NOT NULL,
    zone_id integer NOT NULL REFERENCES zones(zone_id),
    client_status text NOT NULL
);

CREATE TABLE couriers (
    courier_id integer PRIMARY KEY,
    courier_name text NOT NULL,
    courier_status text NOT NULL
);

CREATE TABLE assignments (
    assignment_id integer PRIMARY KEY,
    order_id integer UNIQUE REFERENCES orders(order_id),
    courier_id integer NOT NULL UNIQUE REFERENCES couriers(courier_id),
    assigned_at timestamp NOT NULL
);

-- Данные специально включают заказ без назначения и резервного курьера.
INSERT INTO zones (zone_id, zone_name) VALUES
    (1, 'Центр'), (2, 'Север');
INSERT INTO orders (order_id, customer_name, zone_id, client_status) VALUES
    (1, 'Анна', 1, 'Готовится'),
    (2, 'Борис', 2, 'В пути'),
    (3, 'Вера', 1, 'Передан'),
    (4, 'Глеб', 2, 'Новый');
INSERT INTO couriers (courier_id, courier_name, courier_status) VALUES
    (101, 'Илья', 'Едет в ресторан'),
    (102, 'Мария', 'Доставляет'),
    (103, 'Олег', 'Свободен'),
    (104, 'Рита', 'Резерв');
INSERT INTO assignments (assignment_id, order_id, courier_id, assigned_at) VALUES
    (1001, 1, 101, '2026-11-09 19:50:00'),
    (1002, 2, 102, '2026-11-09 19:51:00'),
    (1003, 3, 103, '2026-11-09 19:52:00'),
    (1004, NULL, 104, '2026-11-09 19:53:00');

-- 1. INNER JOIN (прямое/внутреннее соединение).
-- Вернет лишь заказы с назначенным курьером: 3 строки; заказ 4 исключен.
SELECT o.order_id, o.customer_name, c.courier_name
FROM orders AS o
INNER JOIN assignments AS a ON a.order_id = o.order_id
INNER JOIN couriers AS c ON c.courier_id = a.courier_id
ORDER BY o.order_id;

-- 2. LEFT JOIN (левостороннее соединение).
-- Сохранит все 4 заказа; для заказа 4 курьер будет NULL.
SELECT o.order_id, o.customer_name, c.courier_name
FROM orders AS o
LEFT JOIN assignments AS a ON a.order_id = o.order_id
LEFT JOIN couriers AS c ON c.courier_id = a.courier_id
ORDER BY o.order_id;

-- 3. CROSS JOIN (декартово произведение).
-- Каждая из 4 строк orders сочетается с каждым из 4 couriers: 16 комбинаций.
-- Это возможные пары, а не реальные назначения.
SELECT o.order_id, c.courier_id, c.courier_name
FROM orders AS o
CROSS JOIN couriers AS c
ORDER BY o.order_id, c.courier_id;

-- 4. FULL OUTER JOIN (полное внешнее соединение).
-- Показывает 3 сопоставленных назначения, заказ 4 без назначения
-- и резервное назначение 1004 без заказа: всего 5 строк.
SELECT o.order_id, a.assignment_id, a.courier_id
FROM orders AS o
FULL OUTER JOIN assignments AS a ON a.order_id = o.order_id
ORDER BY o.order_id NULLS LAST, a.assignment_id;

-- 5. Разные типы JOIN в одном запросе: INNER + LEFT + CROSS.
-- INNER JOIN zones: обязательная зона каждого заказа.
-- LEFT JOIN assignments/couriers: незакрепленные заказы тоже видны.
-- CROSS JOIN двух каналов: отдельные клиентский и курьерский статусы.
-- Получаем 4 заказа x 2 канала = 8 строк.
SELECT
    o.order_id,
    z.zone_name,
    ch.channel,
    CASE WHEN ch.channel = 'client' THEN o.client_status
         ELSE COALESCE(c.courier_status, 'Курьер не назначен') END AS visible_status,
    c.courier_name
FROM orders AS o
INNER JOIN zones AS z ON z.zone_id = o.zone_id
LEFT JOIN assignments AS a ON a.order_id = o.order_id
LEFT JOIN couriers AS c ON c.courier_id = a.courier_id
CROSS JOIN (VALUES ('client'), ('courier')) AS ch(channel)
ORDER BY o.order_id, ch.channel;

-- 6. Структура таблиц для приложения к работе.
-- Выводит имена колонок, типы, NULL/NOT NULL и значения по умолчанию.
SELECT table_name, ordinal_position, column_name, data_type,
       is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'hw09'
ORDER BY table_name, ordinal_position;

-- 7. Дополнительная проверка количества строк каждой таблицы.
SELECT 'zones' AS table_name, count(*) AS row_count FROM zones
UNION ALL SELECT 'orders', count(*) FROM orders
UNION ALL SELECT 'couriers', count(*) FROM couriers
UNION ALL SELECT 'assignments', count(*) FROM assignments
ORDER BY table_name;
