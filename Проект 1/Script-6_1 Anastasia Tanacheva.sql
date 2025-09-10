/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Anastasia Tanacheva
 * Дата: 25.01.2025
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
SELECT COUNT (id) AS all_players, -- Все зарегистрированные игроки
       SUM(payer) AS pay_players, -- Все платящие игроки
       AVG(payer) AS part_of_pay_players -- Доля платязих игроков от всех зарегистрированных
FROM fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
SELECT r.race, -- Раса персонажа
       SUM(u.payer) AS paying_players, -- Все платящие игроки
       COUNT(u.id) AS total_players_by_race, -- Все игроки всех рас
       CAST(SUM(u.payer) AS REAL)/ COUNT(u.id) AS paying_percentage_by_race -- Доля платящих игроков в разрезе расы
FROM fantasy.users u
LEFT JOIN fantasy.race r ON u.race_id = r.race_id
GROUP BY r.race
ORDER BY total_players_by_race DESC;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
-- Задача 1: Основные статистические показатели по полю amount
SELECT COUNT(amount) AS total_purchases,
       SUM(amount) AS total_amount,
       MIN(amount) AS min_amount,
       MAX(amount) AS max_amount,
       ROUND(AVG (amount)::NUMERIC, 3) AS avg_amount, -- Значения округлены
       ROUND (PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount)::NUMERIC,3) AS median_amount, -- Значения округлены
       ROUND(STDDEV(amount)::NUMERIC, 3) AS stddev_amount -- Значения округлены
FROM fantasy.events
WHERE amount > 0; -- Исключаем покупки с нулевой стоимостью

-- 2.2: Аномальные нулевые покупки:
SELECT COUNT(*) AS zero_amount_purchases,
       CAST(COUNT(*) AS REAL)/ (SELECT COUNT(*) FROM fantasy.events) AS zero_amount_percentage
FROM fantasy.events
WHERE amount = 0;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
    SELECT
        CASE u.payer
            WHEN 1 THEN 'Платящий'
            ELSE 'Неплатящий'
        END AS payer_category,
        CAST(COUNT(e.amount) AS REAL) / COUNT (DISTINCT u.id) AS avg_purchase_count,
        CAST(SUM(e.amount) AS REAL)/ COUNT(DISTINCT u.id) AS avg_total_purchase_amount
    FROM fantasy.users AS u
    JOIN fantasy.events AS e ON u.id = e.id
    WHERE e.amount > 0
    GROUP BY u.payer
    ORDER BY payer_category;
-- Так действительно выглядит гораздо проще, а результат тот же:)

-- 2.4: Популярные эпические предметы:
SELECT game_items, 
    COUNT(amount) as number, 
    (COUNT(amount)::FLOAT / (SELECT COUNT(amount) FROM fantasy.events)) AS rel_number,
    COUNT (DISTINCT id),
    COUNT (DISTINCT id)::FLOAT / (SELECT COUNT(DISTINCT id) FROM fantasy.events)
FROM fantasy.events
RIGHT JOIN fantasy.items USING(item_code)
WHERE amount <> 0
GROUP BY game_items
ORDER BY number DESC;
-- Добавила более оптимальный вариант, предложенный тобой


-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
WITH race_players AS (
    SELECT r.race_id,
           r.race,
           COUNT(u.id) AS total_players
    FROM fantasy.race AS r
    LEFT JOIN fantasy.users AS u ON r.race_id = u.race_id
    GROUP BY r.race_id, r.race
),
purchasing_players AS (
    SELECT r.race_id,
           COUNT(DISTINCT e.id) AS purchasing_players,
           COUNT(DISTINCT CASE WHEN u.payer = 1 THEN e.id END) AS paying_purchasing_players
    FROM fantasy.race AS r
    LEFT JOIN fantasy.users AS u ON r.race_id = u.race_id
    LEFT JOIN fantasy.events AS e ON u.id = e.id AND e.amount > 0
    GROUP BY r.race_id
),
player_activity AS (
    SELECT r.race_id,
           u.id AS user_id,
           COUNT(e.id) AS purchase_count,
           AVG(e.amount) AS avg_purchase_amount,
           SUM(e.amount) AS total_purchase_amount
    FROM fantasy.race AS r
    LEFT JOIN fantasy.users AS u ON r.race_id = u.race_id
    LEFT JOIN fantasy.events AS e ON u.id = e.id AND e.amount > 0
    GROUP BY r.race_id, u.id
)
SELECT rp.race,
       rp.total_players,
       pp.purchasing_players,
       CAST(pp.purchasing_players AS REAL)/ rp.total_players AS purchasing_players_percentage,
       CAST (pp.paying_purchasing_players AS REAL)/ pp.purchasing_players AS paying_purchasing_percentage,
       SUM(pa.purchase_count)/pp.purchasing_players AS avg_purchases_per_player,
       SUM(pa.total_purchase_amount)/SUM(pa.purchase_count) AS avg_amount_per_purchase,
       SUM(pa.total_purchase_amount) / pp.purchasing_players AS avg_total_amount_per_player
FROM race_players AS rp
LEFT JOIN purchasing_players AS pp ON rp.race_id = pp.race_id
LEFT JOIN player_activity AS pa ON rp.race_id = pa.race_id
GROUP BY rp.race, rp.total_players, pp.purchasing_players, pp.paying_purchasing_players;


-- Задача 2. Частота покупок*:
WITH purchase_intervals AS (
    SELECT
        id,
        CAST (date AS date),
        amount,
        LAG(CAST (date AS date), 1, CAST (date AS date)) OVER (PARTITION BY id ORDER BY CAST (CAST (date AS date) AS date)) AS previous_purchase_time,
        COALESCE(CAST (date AS date) - LAG(CAST (date AS date), 1, CAST (date AS date)) OVER (PARTITION BY id ORDER BY CAST (date AS date)), 0) AS days_since_last_purchase
    FROM fantasy.events
    WHERE amount > 0
),
player_purchase_stats AS (
    SELECT
        p.id,
        u.payer,
        COUNT(p.amount) AS total_purchases,
        AVG(p.days_since_last_purchase) AS avg_days_between_purchases
    FROM purchase_intervals AS p
    JOIN fantasy.users AS u ON p.id = u.id
    GROUP BY p.id, u.payer
    HAVING COUNT(p.amount) >= 25
),
ranked_players AS (
    SELECT
        id,
        payer,
        total_purchases,
        avg_days_between_purchases,
        NTILE(3) OVER (ORDER BY avg_days_between_purchases) AS purchase_frequency_group
    FROM player_purchase_stats
),
frequency_group_stats AS (
    SELECT
        purchase_frequency_group,
        CASE purchase_frequency_group
            WHEN 1 THEN 'высокая частота'
            WHEN 2 THEN 'умеренная частота'
            WHEN 3 THEN 'низкая частота'
        END AS purchase_frequency_group_name,
        COUNT(DISTINCT id) AS total_players_in_group,
        COUNT(DISTINCT CASE WHEN payer = 1 THEN id END) AS paying_players_in_group,
        CAST(COUNT(DISTINCT CASE WHEN payer = 1 THEN id END) AS REAL) / COUNT(DISTINCT id) AS paying_players_ratio,
        AVG(total_purchases) AS avg_purchases_per_player,
        AVG(avg_days_between_purchases) AS avg_days_between_purchases_in_group
    FROM ranked_players
    GROUP BY purchase_frequency_group
)
SELECT *
FROM frequency_group_stats;

