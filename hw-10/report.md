# HW10 — Индексы в PostgreSQL

## 1. Цель

Создать и проверить четыре типа индексов PostgreSQL: обычный B-tree, полнотекстовый GIN, функциональный и составной. Подтвердить использование индексов с помощью `EXPLAIN (ANALYZE, BUFFERS)`, сохранить комментарии и описать ход работы.

## 2. Среда и тестовые данные

- СУБД: **PostgreSQL 17.11** в **Docker** на macOS.
- Контейнер: `hw09-postgres`; база данных: `hw09db`; учебная схема: `hw10`.
- Таблица: `hw10.orders`, заполнена **50 000 тестовыми заказами** через `generate_series(1, 50000)`.
- После загрузки данных выполнена команда `ANALYZE orders` для обновления статистики планировщика.
- Сценарий создания данных и индексов приведён в [indexes.sql](indexes.sql).

### Структура таблицы

| Поле | Тип | Особенности |
|---|---|---|
| `id` | `bigint` | `GENERATED ALWAYS AS IDENTITY`, первичный ключ |
| `order_number` | `text` | Номер заказа |
| `customer_name` | `text` | Имя клиента |
| `delivery_zone` | `integer` | Зона доставки |
| `description` | `text` | Описание заказа |
| `status` | `text` | Статус заказа |
| `created_at` | `timestamp` | Время создания |

При определении `PRIMARY KEY (id)` PostgreSQL автоматически создал индекс `orders_pkey`; он не относится к четырём индексам, созданным вручную в рамках ДЗ.

## 3. Обычный индекс B-tree

**Назначение:** ускорение точечного поиска заказа по `order_number`.

```sql
-- Обычный B-tree индекс для поиска по номеру заказа.
CREATE INDEX idx_orders_number
ON hw10.orders USING btree (order_number);

COMMENT ON INDEX hw10.idx_orders_number IS
'B-tree индекс для быстрого поиска заказа по order_number';
```

Запрос проверки:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM hw10.orders
WHERE order_number = 'ORD-025000';
```

Фрагмент **фактического** плана:

```text
Index Scan using idx_orders_number on orders  (cost=0.29..8.31 rows=1 width=95) (actual time=0.064..0.065 rows=1 loops=1)
  Index Cond: (order_number = 'ORD-025000'::text)
  Buffers: shared hit=1 read=2
Planning Time: 0.381 ms
Execution Time: 0.095 ms
```

**Вывод:** выбран `Index Scan` по `idx_orders_number`, найдена 1 строка. Условие поиска отражено в `Index Cond`.

## 4. Индекс для полнотекстового поиска GIN

**Назначение:** поиск по словам описания заказа с русской языковой нормализацией.

```sql
-- GIN индексирует текстовое представление описания для полнотекстового поиска.
CREATE INDEX idx_orders_description_fts
ON hw10.orders USING gin (to_tsvector('russian', description));

COMMENT ON INDEX hw10.idx_orders_description_fts IS
'GIN-индекс для полнотекстового поиска по описанию заказа на русском языке';
```

Проверка:

```sql
SELECT count(*)
FROM hw10.orders
WHERE to_tsvector('russian', description)
      @@ plainto_tsquery('russian', 'трюфельная');
-- Результат: 50

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM hw10.orders
WHERE to_tsvector('russian', description)
      @@ plainto_tsquery('russian', 'трюфельная');
```

Фрагмент фактического плана:

```text
Bitmap Heap Scan on orders  (cost=22.21..618.05 rows=250 width=95) (actual time=0.038..0.116 rows=50 loops=1)
  Recheck Cond: (to_tsvector('russian'::regconfig, description) @@ '''трюфельн'''::tsquery)
  Heap Blocks: exact=50
  Buffers: shared hit=52
  -> Bitmap Index Scan on idx_orders_description_fts  (cost=0.00..22.15 rows=250 width=0) (actual time=0.019..0.020 rows=50 loops=1)
       Buffers: shared hit=2
Planning Time: 0.135 ms
Execution Time: 0.137 ms
```

**Вывод:** `Bitmap Index Scan` обращается к GIN-индексу и находит 50 строк, затем `Bitmap Heap Scan` читает соответствующие страницы таблицы. Русский анализатор нормализовал «трюфельная» до лексемы `трюфельн`.

## 5. Функциональный индекс

**Назначение:** регистронезависимый поиск по имени клиента; индексируется результат функции `lower()`.

```sql
-- B-tree индекс по выражению lower(customer_name).
CREATE INDEX idx_orders_customer_lower
ON hw10.orders (lower(customer_name));

COMMENT ON INDEX hw10.idx_orders_customer_lower IS
'Функциональный индекс для поиска клиентов без учёта регистра';
```

Проверка:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM hw10.orders
WHERE lower(customer_name) = lower('Клиент 25000');
```

Фрагмент фактического плана:

```text
Bitmap Heap Scan on orders  (cost=10.35..544.32 rows=250 width=95) (actual time=0.138..0.140 rows=1 loops=1)
  Recheck Cond: (lower(customer_name) = 'клиент 25000'::text)
  Heap Blocks: exact=1
  Buffers: shared hit=1 read=3
  -> Bitmap Index Scan on idx_orders_customer_lower  (cost=0.00..10.29 rows=250 width=0) (actual time=0.067..0.067 rows=1 loops=1)
       Index Cond: (lower(customer_name) = 'клиент 25000'::text)
Planning Time: 0.260 ms
Execution Time: 0.154 ms
```

**Вывод:** использован `idx_orders_customer_lower`, найдена 1 строка. Для использования этого индекса запрос содержит такое же выражение `lower(customer_name)`.

## 6. Составной индекс

**Назначение:** поиск заказов по конкретной зоне доставки и диапазону времени.

```sql
-- В составном B-tree индексе зона идёт перед временной меткой.
CREATE INDEX idx_orders_zone_created
ON hw10.orders (delivery_zone, created_at);

COMMENT ON INDEX hw10.idx_orders_zone_created IS
'Составной индекс для поиска заказов по зоне доставки и времени создания';
```

Проверка:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM hw10.orders
WHERE delivery_zone = 7
  AND created_at >= timestamp '2026-11-10 00:00:00'
  AND created_at <  timestamp '2026-11-11 00:00:00';
```

Фрагмент фактического плана:

```text
Bitmap Heap Scan on orders  (cost=5.21..221.90 rows=72 width=95) (actual time=0.059..0.108 rows=72 loops=1)
  Recheck Cond: ((delivery_zone = 7) AND (created_at >= '2026-11-10 00:00:00'::timestamp without time zone) AND (created_at < '2026-11-11 00:00:00'::timestamp without time zone))
  Heap Blocks: exact=24
  Buffers: shared hit=27
  -> Bitmap Index Scan on idx_orders_zone_created  (cost=0.00..5.19 rows=72 width=0) (actual time=0.041..0.042 rows=72 loops=1)
       Index Cond: ((delivery_zone = 7) AND (created_at >= '2026-11-10 00:00:00'::timestamp without time zone) AND (created_at < '2026-11-11 00:00:00'::timestamp without time zone))
       Buffers: shared hit=3
Planning Time: 0.162 ms
Execution Time: 0.148 ms
```

**Вывод:** использован `idx_orders_zone_created`, найдено 72 строки. Порядок полей `(delivery_zone, created_at)` согласован с равенством по первому полю и диапазоном по второму.

## 7. Сводная таблица результатов

| Индекс | Тип | Метод доступа в EXPLAIN | Строк получено | Execution Time |
|---|---|---|---:|---:|
| `idx_orders_number` | B-tree | `Index Scan` | 1 | 0.095 мс |
| `idx_orders_description_fts` | GIN | `Bitmap Index Scan` + `Bitmap Heap Scan` | 50 | 0.137 мс |
| `idx_orders_customer_lower` | B-tree по выражению | `Bitmap Index Scan` + `Bitmap Heap Scan` | 1 | 0.154 мс |
| `idx_orders_zone_created` | Составной B-tree | `Bitmap Index Scan` + `Bitmap Heap Scan` | 72 | 0.148 мс |

> Это результаты **разных запросов**, а не сравнительный бенчмарк индексов. По ним можно подтвердить факт использования индекса, но нельзя утверждать, что один тип индекса быстрее другого.

Полные фактические фрагменты планов вынесены в [explain_results.txt](explain_results.txt).

## 8. Проверка комментариев в каталоге PostgreSQL

Использован запрос:

```sql
SELECT c.relname AS index_name,
       obj_description(c.oid, 'pg_class') AS comment
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'hw10' AND c.relkind = 'i'
ORDER BY c.relname;
```

По фактическому выводу все четыре пользовательских индекса имеют комментарии:

| Индекс | Комментарий |
|---|---|
| `idx_orders_customer_lower` | Функциональный индекс для поиска клиентов без учёта регистра |
| `idx_orders_description_fts` | GIN-индекс для полнотекстового поиска по описанию заказа на русском языке |
| `idx_orders_number` | B-tree индекс для быстрого поиска заказа по order_number |
| `idx_orders_zone_created` | Составной индекс для поиска заказов по зоне доставки и времени создания |

У автоматически созданного `orders_pkey` комментария нет; это не относится к требованию комментировать созданные в домашней работе индексы.

## 9. Ход работы и особенности

1. Вместо маленькой таблицы из HW09 создана отдельная учебная схема `hw10` с 50 000 строк, потому что на небольшой таблице PostgreSQL часто выгоднее выполнить `Seq Scan`. Это **учтённая особенность планировщика**, а не ошибка, которая была зафиксирована в ходе данного эксперимента.
2. После вставки строк выполнен `ANALYZE`, чтобы планировщик располагал актуальной статистикой.
3. Созданы четыре индекса с комментариями в SQL и `COMMENT ON INDEX`.
4. Каждый индекс проверен через реальный `EXPLAIN (ANALYZE, BUFFERS)`. Во всех четырёх случаях индекс присутствует в плане выполнения.
5. Для GIN важно соответствие выражений `to_tsvector('russian', description)` в индексе и запросе. Для функционального индекса важно использование `lower(customer_name)` в условии.
6. `Bitmap Index Scan` — нормальный способ использования индекса; отсутствие буквального `Index Scan` не означает, что индекс проигнорирован.
7. **Непреодолимых ошибок или проблем в предоставленных результатах не было.** Следует учитывать, что индекс занимает место и добавляет расходы при вставках и изменениях; в данной работе эти расходы отдельно не измерялись.

## 10. Заключение

Цель выполнена: созданы и прокомментированы обычный, полнотекстовый, функциональный и составной индексы, а их использование подтверждено фактическими планами `EXPLAIN`. Предоставленные результаты демонстрируют корректное применение разных типов индексации к соответствующим условиям поиска в PostgreSQL 17.11.
