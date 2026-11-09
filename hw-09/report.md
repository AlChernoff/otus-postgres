# HW09 — Соединения таблиц в PostgreSQL

## Цель

Продемонстрировать `INNER JOIN`, `LEFT JOIN`, `CROSS JOIN`, `FULL OUTER JOIN` и запрос, объединяющий разные типы соединений. Для каждого запроса даны пояснения. Используется учебная модель службы доставки «Ночная Лама».

**Среда выполнения:** PostgreSQL **17.11** (Debian 17.11-1.pgdg13+2), Docker-контейнер `hw09-postgres`, база данных `hw09db`, схема `hw09`, клиент `psql`. Все SQL-команды выполнены пользователем; фактические результаты приведены ниже по выводу `psql`. Виртуальная машина не использовалась.

## 1. Структура таблиц

Все таблицы создаются в отдельной схеме `hw09` скриптом [`joins.sql`](joins.sql). Скрипт удаляет и пересоздаёт **только схему `hw09`** при повторном запуске.

| Таблица | Поля | Ключи и связи | Назначение |
|---|---|---|---|
| `zones` | `zone_id integer`, `zone_name text` | PK: `zone_id`; UNIQUE: `zone_name` | Зоны доставки |
| `orders` | `order_id integer`, `customer_name text`, `zone_id integer`, `client_status text` | PK: `order_id`; FK `zone_id → zones.zone_id` | Заказы и клиентский статус |
| `couriers` | `courier_id integer`, `courier_name text`, `courier_status text` | PK: `courier_id` | Курьеры и отдельный курьерский статус |
| `assignments` | `assignment_id integer`, `order_id integer`, `courier_id integer`, `assigned_at timestamp` | PK: `assignment_id`; FK `order_id → orders.order_id` (NULL разрешён, UNIQUE); FK `courier_id → couriers.courier_id` (UNIQUE) | Назначения курьеров на заказы; возможен резерв без заказа |

### DDL (структура)

```sql
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
```

### Связи

```text
zones (1) ──── (N) orders (1) ──── (0..1) assignments (1) ──── (1) couriers
                               order_id может быть NULL: резервное назначение
```

Тестовые данные: 2 зоны, 4 заказа, 4 курьера и 4 записи назначения. Заказы 1–3 имеют курьеров, заказ 4 не имеет. Назначение 1004 привязано к курьеру 104, но не к заказу (`order_id IS NULL`), чтобы в `FULL JOIN` проявилась правая несопоставленная строка.

## 2. INNER JOIN — внутреннее (прямое) соединение

```sql
-- Оставляет только заказы, к которым прикреплены курьеры.
SELECT o.order_id, o.customer_name, c.courier_name
FROM hw09.orders AS o
INNER JOIN hw09.assignments AS a ON a.order_id = o.order_id
INNER JOIN hw09.couriers AS c ON c.courier_id = a.courier_id
ORDER BY o.order_id;
```

**Пояснение:** соединение возвращает лишь строки, для которых нашлось соответствие по обеим связям. Заказ 4 и резервное назначение 1004 не войдут в результат. **Фактически получено 3 строки.**

**Фактический результат `INNER JOIN`:**

| order_id | customer_name | courier_name |
|---:|---|---|
| 1 | Анна | Илья |
| 2 | Борис | Мария |
| 3 | Вера | Олег |

## 3. LEFT JOIN — левостороннее соединение

```sql
-- Показывает все заказы, даже если курьер пока не назначен.
SELECT o.order_id, o.customer_name, c.courier_name
FROM hw09.orders AS o
LEFT JOIN hw09.assignments AS a ON a.order_id = o.order_id
LEFT JOIN hw09.couriers AS c ON c.courier_id = a.courier_id
ORDER BY o.order_id;
```

**Пояснение:** сохраняются все строки слева (`orders`); для отсутствующего назначения у заказа 4 поля курьера будут `NULL`. **Фактически получено 4 строки.**

**Фактический результат `LEFT JOIN`:**

| order_id | customer_name | courier_name |
|---:|---|---|
| 1 | Анна | Илья |
| 2 | Борис | Мария |
| 3 | Вера | Олег |
| 4 | Глеб | `NULL` |

## 4. CROSS JOIN — перекрёстное соединение

```sql
-- Показывает все возможные пары заказ/курьер независимо от назначения.
SELECT o.order_id, c.courier_id, c.courier_name
FROM hw09.orders AS o
CROSS JOIN hw09.couriers AS c
ORDER BY o.order_id, c.courier_id;
```

**Пояснение:** каждая строка первой таблицы комбинируется с каждой строкой второй. При четырёх заказах и четырёх курьерах **получено 16 строк**. Это возможные комбинации, а не реальные назначения.

**Фактический результат `CROSS JOIN`:** 16 строк — для каждого из заказов 1, 2, 3, 4 получены комбинации с курьерами 101 (Илья), 102 (Мария), 103 (Олег) и 104 (Рита).

| Заказ | Курьеры в результате | Количество строк |
|---:|---|---:|
| 1 | 101, 102, 103, 104 | 4 |
| 2 | 101, 102, 103, 104 | 4 |
| 3 | 101, 102, 103, 104 | 4 |
| 4 | 101, 102, 103, 104 | 4 |
| **Всего** | | **16** |

## 5. FULL OUTER JOIN — полное внешнее соединение

```sql
-- Показывает сопоставленные и несопоставленные строки с обеих сторон.
SELECT o.order_id, a.assignment_id, a.courier_id
FROM hw09.orders AS o
FULL OUTER JOIN hw09.assignments AS a ON a.order_id = o.order_id
ORDER BY o.order_id NULLS LAST, a.assignment_id;
```

**Пояснение:** кроме трёх совпадений, возвращается заказ 4 с `NULL` в столбцах назначения и назначение 1004 с `NULL` в `order_id`. **Фактически получено 5 строк.** Этот пример показывает обе стороны полного соединения.

**Фактический результат `FULL OUTER JOIN`:**

| order_id | assignment_id | courier_id |
|---:|---:|---:|
| 1 | 1001 | 101 |
| 2 | 1002 | 102 |
| 3 | 1003 | 103 |
| 4 | `NULL` | `NULL` |
| `NULL` | 1004 | 104 |

## 6. Комбинированный запрос: INNER JOIN + LEFT JOIN + CROSS JOIN

```sql
-- INNER: берём зону каждого заказа.
-- LEFT: сохраняем заказы, у которых нет назначения и курьера.
-- CROSS: создаём по две записи для клиентского и курьерского статуса.
SELECT o.order_id, z.zone_name, ch.channel,
       CASE WHEN ch.channel = 'client' THEN o.client_status
            ELSE COALESCE(c.courier_status, 'Курьер не назначен') END
            AS visible_status,
       c.courier_name
FROM hw09.orders AS o
INNER JOIN hw09.zones AS z ON z.zone_id = o.zone_id
LEFT JOIN hw09.assignments AS a ON a.order_id = o.order_id
LEFT JOIN hw09.couriers AS c ON c.courier_id = a.courier_id
CROSS JOIN (VALUES ('client'), ('courier')) AS ch(channel)
ORDER BY o.order_id, ch.channel;
```

**Пояснение:** демонстрирует три различных типа соединений в одном запросе. Клиент и курьер видят разные статусы; у заказа 4 курьерский статус выводится как «Курьер не назначен». **Фактически получено 8 строк** (4 заказа × 2 канала).

**Фактический результат смешанного соединения:**

| order_id | zone_name | channel | visible_status | courier_name |
|---:|---|---|---|---|
| 1 | Центр | client | Готовится | Илья |
| 1 | Центр | courier | Едет в ресторан | Илья |
| 2 | Север | client | В пути | Мария |
| 2 | Север | courier | Доставляет | Мария |
| 3 | Центр | client | Передан | Олег |
| 3 | Центр | courier | Свободен | Олег |
| 4 | Север | client | Новый | `NULL` |
| 4 | Север | courier | Курьер не назначен | `NULL` |

## 7. Запрос структуры таблиц

```sql
-- Список столбцов и типов данных для приложения к работе.
SELECT table_name, ordinal_position, column_name, data_type,
       is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'hw09'
ORDER BY table_name, ordinal_position;
```

Полные определения `CREATE TABLE` приведены в разделе 1 и в файле `joins.sql`.

**Результат запроса структуры:** 13 столбцов в четырёх таблицах. `assignments`: 4 столбца (`assignment_id`, `order_id`, `courier_id`, `assigned_at`); `couriers`: 3; `orders`: 4; `zones`: 2. `order_id` в `assignments` допускает `NULL`, остальные перечисленные поля — нет.

**Контроль количества записей:**

| Таблица | Строк |
|---|---:|
| `zones` | 2 |
| `orders` | 4 |
| `couriers` | 4 |
| `assignments` | 4 |

## 8. Вывод

В работе подготовлены все требуемые типы соединений: внутреннее, левостороннее, перекрёстное, полное внешнее и комбинированное. Отсутствующие соответствия представлены `NULL`, а `CROSS JOIN` формирует декартово произведение. SQL-запросы снабжены комментариями, структура таблиц приложена. **Все запросы были фактически выполнены в PostgreSQL 17.11 через `psql` в Docker; полученные количества строк совпадают с ожидаемыми.**

## Воспроизводимость

Исходный скрипт `joins.sql` содержит DDL, тестовые данные, пять видов соединений, комментарии и запрос структуры таблиц. Он выполнен в `psql`, а результаты отражены в данном отчёте. Для повторного запуска можно выполнить `psql -U student -d hw09db -f joins.sql` внутри контейнера после копирования скрипта.

**Осторожно:** в начале файла есть `DROP SCHEMA IF EXISTS hw09 CASCADE`; он удаляет существующую схему `hw09`, если она уже есть. Запускайте только в учебной базе.
