-- HW05 / commands.sql
-- PostgreSQL 17. Используйте две отдельные интерактивные сессии psql.
-- Подключение каждой: docker exec -it pg17-hw03 psql -U postgres -d hw05db
-- Базу hw05db создайте при необходимости ДО запуска скрипта:
-- docker exec pg17-hw03 createdb -U postgres hw05db
--
-- ЧАСТЬ A. Подготовка (один раз, под postgres, в отдельной сессии).
-- ВНИМАНИЕ: следующие DROP удаляют только учебные таблицы hw05db.
DROP TABLE IF EXISTS report_window;
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    amount NUMERIC(10,2) NOT NULL
);
INSERT INTO orders (created_at, amount)
VALUES (now(), 100), (now(), 200), (now(), 300);
CREATE TABLE report_window (started_at TIMESTAMPTZ NOT NULL);
-- Фиксированная нижняя граница гарантированно раньше исходных трёх заказов.
INSERT INTO report_window (started_at)
SELECT min(created_at) - interval '1 second' FROM orders;
SELECT * FROM orders;
-- Завершите подготовку, если autocommit был отключён:
COMMIT;

-- ЧАСТЬ B. Откройте ДВА терминала с psql к hw05db.
-- В каждой сессии отключите autocommit (метакоманда psql):
-- \set AUTOCOMMIT off
-- \echo :AUTOCOMMIT
-- После этого выполняйте действия ниже по очереди; не запускайте
-- этот файл целиком, поскольку нужны синхронные действия двух сессий.

-- Шаг 1: СЕССИЯ 2 (Report)
-- COMMIT; -- на случай неявно начатой транзакции
-- BEGIN ISOLATION LEVEL READ COMMITTED;
-- SELECT count(*), sum(amount) FROM orders
-- WHERE created_at >= (SELECT started_at FROM report_window);
-- ожидается 3 / 600.00

-- Шаг 2: СЕССИЯ 1 (Writer)
-- COMMIT;
-- BEGIN ISOLATION LEVEL READ COMMITTED;
-- INSERT INTO orders (created_at, amount) VALUES (clock_timestamp(), 400);
-- COMMIT;

-- Шаг 3: СЕССИЯ 2 (Report), та же транзакция
-- SELECT count(*), sum(amount) FROM orders
-- WHERE created_at >= (SELECT started_at FROM report_window);
-- ожидается 4 / 1000.00
-- COMMIT;

-- Шаг 4: СЕССИЯ 2 (Report)
-- BEGIN ISOLATION LEVEL REPEATABLE READ;
-- SELECT count(*), sum(amount) FROM orders
-- WHERE created_at >= (SELECT started_at FROM report_window);
-- ожидается 4 / 1000.00

-- Шаг 5: СЕССИЯ 1 (Writer)
-- BEGIN ISOLATION LEVEL REPEATABLE READ;
-- INSERT INTO orders (created_at, amount) VALUES (clock_timestamp(), 500);
-- COMMIT;

-- Шаг 6: СЕССИЯ 2 (Report), всё ещё та же Repeatable Read транзакция
-- SELECT count(*), sum(amount) FROM orders
-- WHERE created_at >= (SELECT started_at FROM report_window);
-- ожидается 4 / 1000.00
-- COMMIT;

-- Шаг 7: СЕССИЯ 2 (Report), новая транзакция
-- BEGIN ISOLATION LEVEL REPEATABLE READ;
-- SELECT count(*), sum(amount) FROM orders
-- WHERE created_at >= (SELECT started_at FROM report_window);
-- ожидается 5 / 1500.00
-- COMMIT;
