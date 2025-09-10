-- Задача 1. Время активности объявлений 
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
activity_category AS (
    SELECT
        CASE
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'Ленинградская область'
        END AS region,
        CASE
            WHEN a.days_exposition <= 30 THEN 'до месяца'
            WHEN a.days_exposition <= 90 THEN 'до трех месяцев'
            WHEN a.days_exposition <= 180 THEN 'до полугода'
            ELSE 'более полугода'
        END AS activity_period,
        a.last_price / f.total_area AS price_per_sqm,
        f.total_area,
        f.rooms,
        f.balcony,
        f.floor,
        f.ceiling_height,
        CASE WHEN f.rooms = 1 THEN 1 ELSE 0 END as is_studio
    FROM real_estate.flats AS f
    JOIN real_estate.advertisement AS a USING (id) -- Улучшила
    JOIN real_estate.city AS c USING (city_id)
    JOIN real_estate.TYPE AS t USING (type_id)
    WHERE
        f.id IN (SELECT id FROM filtered_id)
        AND t.TYPE = 'город'
        AND a.days_exposition IS NOT NULL
        AND a.last_price > 0
        AND f.total_area > 0
) -- Удалила подзапрос, добавила вместо него оконную функцию в основном запросе
SELECT
    ac.region,
    ac.activity_period,
    COUNT(*) AS ad_count,
    ROUND((COUNT(*) * 100.0 / SUM(COUNT(*)) OVER())::numeric, 2) AS ad_share_total, -- Доля от общего числа
    ROUND((COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY region))::numeric, 2) AS ad_share_region, -- Доля в регионе
    ROUND(AVG(ac.price_per_sqm)::numeric, 2) AS avg_price_per_sqm,
    ROUND(AVG(ac.total_area)::NUMERIC,2) AS avg_total_area,
    ROUND (AVG(ac.rooms)::NUMERIC,0) AS avg_rooms,
    ROUND (AVG(ac.balcony)::NUMERIC,0) AS avg_balconies,
    ROUND(AVG(ac.ceiling_height)::numeric, 2) AS avg_ceiling_height,
    ROUND(AVG(ac.is_studio)::numeric, 2) AS studio_share 
FROM activity_category ac
GROUP BY ac.region, ac.activity_period
ORDER BY ac.region, ac.activity_period;


-- Задача 2. Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),  
publication_activity AS (
    SELECT
        a.days_exposition,
        TO_CHAR(a.first_day_exposition, 'Month') AS "Месяц публикации", -- Изменение: TO_CHAR
        TO_CHAR(a.first_day_exposition + INTERVAL '1 day' * a.days_exposition, 'Month') AS "День снятия объявления", -- Изменение: TO_CHAR,
        a.last_price / f.total_area AS "Стоимость кв. метра",
        f.total_area
    FROM real_estate.flats AS f
    JOIN real_estate.advertisement AS a USING (id)
    JOIN real_estate.TYPE AS t USING (type_id)
    WHERE
        EXTRACT(YEAR FROM a.first_day_exposition::timestamp) BETWEEN 2015 AND 2018
        AND f.id IN (SELECT id FROM filtered_id)
        AND t.TYPE = 'город'
        AND EXTRACT(YEAR FROM (a.first_day_exposition + INTERVAL '1 day' * a.days_exposition)) BETWEEN 2015 AND 2018
),
monthly_publication_counts AS (
    SELECT
        "Месяц публикации",
        COUNT(*) AS "Кол-во объявлений",
        RANK() OVER (ORDER BY COUNT(*) DESC) AS "Ранг публикации",
        AVG("Стоимость кв. метра") AS "Средняя стоимость кв. метра",
        AVG(total_area) AS "Средняя площадь"
    FROM publication_activity
    GROUP BY "Месяц публикации"
),
monthly_removal_counts AS (
    SELECT
        "День снятия объявления",
        COUNT(*) AS "Кол-во снятых объявлений",
        RANK() OVER (ORDER BY COUNT(*) DESC) AS "Ранг снятых",
        AVG("Стоимость кв. метра") AS "Средняя стоимость кв. метра_1",
        AVG(total_area) AS "Средняя площадь_1"
    FROM publication_activity
    WHERE days_exposition IS NOT NULL --Добавила условие сюда, убрала из CTE выше
    GROUP BY "День снятия объявления"
)
SELECT
    "Месяц публикации",
    "Кол-во объявлений",
    mpc."Средняя стоимость кв. метра",
    mpc."Средняя площадь",
    "Ранг публикации",
    "Кол-во снятых объявлений", -- Добавлены аналогичные показатели для снятых объявлений
    mrc."Средняя стоимость кв. метра_1",
    mrc."Средняя площадь_1",
    "Ранг снятых",
    CASE
        WHEN mpc."Ранг публикации" = mrc."Ранг снятых" THEN 'Совпадают'
        ELSE 'Не совпадают'
    END AS ranks_match
FROM monthly_publication_counts mpc
JOIN monthly_removal_counts mrc ON mpc."Месяц публикации" = mrc."День снятия объявления"
ORDER BY "Ранг публикации"; -- Исправила частично то, что было в "можно улучшить" + доработало то, что было выделено красным

-- Задача 3. Анализ рынка недвижимости Ленобласти
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
SELECT 
    c.city,
    COUNT(a.days_exposition) AS "Кол-во продаж",  
    COUNT(f.id) AS "кол-во публикаций",
    ROUND(COUNT(a.days_exposition)::NUMERIC / COUNT (f.id) * 100, 2) AS "Доля проданных (%)",
    ROUND(AVG(a.days_exposition)::NUMERIC, 0) AS "Среднее время продажи (дни)",
    ROUND(AVG(a.last_price / f.total_area)::NUMERIC, 2) AS "Средняя стоимость кв. метра",
    ROUND(AVG(f.total_area)::NUMERIC, 2) AS "Средняя площадь",
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.rooms) AS "Медиана количества комнат",
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.balcony) AS "Медиана количества балконов",
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.floor) AS "Медиана этажности"
FROM real_estate.flats AS f
JOIN real_estate.advertisement AS a ON f.id = a.id
JOIN real_estate.city AS c ON c.city_id = f.city_id
WHERE c.city <> 'Санкт-Петербург' AND f.id IN (SELECT * FROM filtered_id)
GROUP BY c.city
ORDER BY "Кол-во продаж" DESC
LIMIT 15;

 
