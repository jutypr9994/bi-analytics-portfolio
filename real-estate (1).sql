/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Седов Арсений 
 * Дата: 10.8.25
 */



-- Задача 1: Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
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
    filterd_advertisement AS (
    SELECT ad.id,
    ad.first_day_exposition,
    ad.days_exposition,
    ad.last_price,
    fl.total_area,
    fl.rooms,
    fl.city_id,
   t.type AS city_type, -- тип насленного пункта -
    CASE WHEN ci.city= 'Санкт-Петербург' THEN 'Санкт-Петербург'
    ELSE 'ЛенОбл'
    END AS region,
    CASE WHEN ad.days_exposition <= 30 THEN 'до месяца'
    WHEN ad.days_exposition <=90 THEN 'до трех месяцев'
    WHEN ad.days_exposition <=180 THEN 'до полугола'
    WHEN ad.days_exposition <=365 THEN 'более полугода'
    ELSE 'активные объявления' -- активная категория--
    END AS activity_segment
    FroM real_estate.advertisement ad 
    JOIN real_estate.flats fl on  ad.id = fl.id
    JOIN real_estate.city ci ON fl.city_id = ci.city_id
     JOIN real_estate.type t ON fl.type_id = t.type_id
    WHERE ad.id IN (SELECT id FROM filtered_id)
    AND t.type = 'город' -- только городск. кв.--
    AND EXTRACT(YEAR FROM ad.first_day_exposition) BETWEEN 2015 AND 2018 -- огранич временной диапазо
),
filterd_types AS (
    SELECT
        region,
        activity_segment,
          COUNT(*) AS number_of_ads,
        ROUND(AVG(last_price / total_area)::NUMERIC, 2) AS  avg_cost_per_square_meter,
        ROUND(AVG(total_area)::NUMERIC, 2) AS avg_area,
        ROUND(SUM(CASE WHEN rooms = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS SHARE_of_studios
    FROM  filterd_advertisement
    GROUP BY region, activity_segment   
)
SELECT * FROM filterd_types ORDER BY region, activity_segment;
-- Задача 2: Сезонность объявлений
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
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
 filtered_dates AS(
       SELECT
        EXTRACT(YEAR FROM ad.first_day_exposition) AS pub_year,
        EXTRACT(MONTH FROM ad.first_day_exposition) AS pub_month,
        EXTRACT(YEAR FROM (ad.first_day_exposition + INTERVAL '1 DAY' * ad.days_exposition)) AS rem_year,
        EXTRACT(MONTH FROM (ad.first_day_exposition + INTERVAL '1 DAY' * ad.days_exposition)) AS rem_month,
        ad.last_price / fl.total_area AS price_per_meter,
        fl.total_area,
        ad.days_exposition -- для учета подачи (вероятно можно было и не видоизменять все до такой степени, не знаю)
    FROM real_estate.advertisement ad
    JOIN real_estate.flats fl ON ad.id = fl.id
    JOIN real_estate.city c ON fl.city_id = c.city_id
    JOIN real_estate.type t ON fl.type_id = t.type_id
    WHERE ad.id IN (SELECT id FROM filtered_id)
      AND t.type = 'город' -- фильтрация только городских квартир
      AND EXTRACT(YEAR FROM ad.first_day_exposition) BETWEEN 2015 AND 2018
),
publication_stats AS (
    SELECT
        pub_month,
        COUNT(*) AS publication_count,
        AVG(price_per_meter) AS avg_price_per_meter_pub,
        AVG(total_area) AS avg_total_area_pub
    FROM filtered_dates 
    GROUP BY pub_month
),
removal_stats AS (
    SELECT
        rem_month,
        COUNT(*) FILTER (WHERE days_exposition IS NOT NULL) AS removal_count, -- только завершенные объявления
        AVG(price_per_meter) FILTER (WHERE days_exposition IS NOT NULL) AS avg_price_per_meter_rem, -- усреднение цен только для завершенных объявлений
        AVG(total_area) FILTER (WHERE days_exposition IS NOT NULL) AS avg_total_area_rem -- усреднение площадей только для завершенных объявлений
    FROM filtered_dates 
    GROUP BY rem_month
)
-- пускай останется
SELECT
    ps.pub_month AS MONTH,
     ps.publication_count AS number_of_published,
    rs.removal_count AS number_of_removed,
    ROUND(CAST(ps.avg_price_per_meter_pub AS NUMERIC), 2) AS avg_cost_per_square_meter_at_publication,
    ROUND(CAST(rs.avg_price_per_meter_rem AS NUMERIC), 2) AS avg_cost_per_square_meter_removed,
    ROUND(CAST(ps.avg_total_area_pub AS NUMERIC), 2) AS avg_publication_area,
    ROUND(CAST(rs.avg_total_area_rem AS NUMERIC), 2) AS avg_removed_area
FROM publication_stats ps
FULL JOIN removal_stats rs ON ps.pub_month = rs.rem_month
ORDER BY month
-------
