/*
===============================================================================
Olist E-Commerce Analytics
File: sql/warehouse/02_load_dimensions.sql
Phase: B2.2 — Dimensional Modeling & Data Warehouse

Purpose
-------
Populate the six conformed dimensions defined in
01_create_warehouse_schema.sql.

Prerequisite
------------
Run 01_create_warehouse_schema.sql first. This loader expects empty dimension
tables. It does not modify the immutable `olist` source schema.

Geography rule
--------------
For each five-digit CEP prefix:
  1. normalize city with lower(unaccent(...)) + separator/whitespace cleanup;
  2. normalize state with upper(trim(...));
  3. count candidate (city,state) pairs;
  4. choose the modal pair;
  5. break ties by normalized_state ASC, normalized_city ASC;
  6. choose a deterministic raw city label within the winning pair;
  7. use median latitude/longitude across all geolocation observations for
     the CEP prefix;
  8. preserve ambiguity/count metadata.

Customer/seller CEP prefixes absent from geolocation are still represented
using their source city/state and NULL coordinates.
===============================================================================
*/

BEGIN;

CREATE EXTENSION IF NOT EXISTS unaccent;

-- Fail early if this is accidentally run on an already-populated warehouse.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM dw.dim_date LIMIT 1)
       OR EXISTS (SELECT 1 FROM dw.dim_customer LIMIT 1)
       OR EXISTS (SELECT 1 FROM dw.dim_location LIMIT 1)
       OR EXISTS (SELECT 1 FROM dw.dim_product LIMIT 1)
       OR EXISTS (SELECT 1 FROM dw.dim_seller LIMIT 1)
       OR EXISTS (SELECT 1 FROM dw.dim_order_status LIMIT 1) THEN
        RAISE EXCEPTION
            'Warehouse dimensions are not empty. Re-run 01_create_warehouse_schema.sql before rebuilding dimensions.';
    END IF;
END $$;


-- ============================================================================
-- 1. DIM_DATE
-- ============================================================================

-- Cover every date referenced by the source facts, including item shipping
-- limits and review timestamps.
WITH source_dates AS (
    SELECT order_purchase_timestamp::date AS d FROM olist.orders
    UNION ALL
    SELECT order_approved_at::date FROM olist.orders
    UNION ALL
    SELECT order_delivered_carrier_date::date FROM olist.orders
    UNION ALL
    SELECT order_delivered_customer_date::date FROM olist.orders
    UNION ALL
    SELECT order_estimated_delivery_date::date FROM olist.orders
    UNION ALL
    SELECT shipping_limit_date::date FROM olist.order_items
    UNION ALL
    SELECT review_creation_date::date FROM olist.order_reviews
    UNION ALL
    SELECT review_answer_timestamp::date FROM olist.order_reviews
),
bounds AS (
    SELECT MIN(d) AS min_date, MAX(d) AS max_date
    FROM source_dates
    WHERE d IS NOT NULL
)
INSERT INTO dw.dim_date (
    date_key,
    full_date,
    year,
    quarter,
    month,
    month_name,
    year_month,
    day,
    day_of_week,
    day_name,
    is_weekend
)
SELECT
    TO_CHAR(d::date, 'YYYYMMDD')::integer,
    d::date,
    EXTRACT(YEAR FROM d)::smallint,
    EXTRACT(QUARTER FROM d)::smallint,
    EXTRACT(MONTH FROM d)::smallint,
    TO_CHAR(d, 'FMMonth'),
    TO_CHAR(d, 'YYYY-MM'),
    EXTRACT(DAY FROM d)::smallint,
    EXTRACT(ISODOW FROM d)::smallint,
    TO_CHAR(d, 'FMDay'),
    EXTRACT(ISODOW FROM d) IN (6, 7)
FROM bounds
CROSS JOIN LATERAL generate_series(
    bounds.min_date::timestamp,
    bounds.max_date::timestamp,
    interval '1 day'
) AS g(d);


-- ============================================================================
-- 2. DIM_CUSTOMER
-- ============================================================================

INSERT INTO dw.dim_customer (customer_unique_id)
SELECT DISTINCT customer_unique_id
FROM olist.customers
ORDER BY customer_unique_id;


-- ============================================================================
-- 3. DIM_LOCATION
-- ============================================================================

-- Normalize the raw geolocation observations once.
CREATE TEMP TABLE tmp_geo_normalized ON COMMIT DROP AS
SELECT
    geolocation_zip_code_prefix AS zip_code_prefix,
    geolocation_city AS raw_city,
    NULLIF(
        BTRIM(
            REGEXP_REPLACE(
                LOWER(unaccent(BTRIM(geolocation_city))),
                '[^a-z0-9]+',
                ' ',
                'g'
            )
        ),
        ''
    ) AS normalized_city,
    UPPER(BTRIM(geolocation_state)) AS normalized_state,
    geolocation_lat AS latitude,
    geolocation_lng AS longitude
FROM olist.geolocation;

-- Candidate city/state pairs and their support.
CREATE TEMP TABLE tmp_geo_candidates ON COMMIT DROP AS
SELECT
    zip_code_prefix,
    normalized_city,
    normalized_state,
    COUNT(*) AS observations
FROM tmp_geo_normalized
GROUP BY
    zip_code_prefix,
    normalized_city,
    normalized_state;

-- Rank canonical pairs using the frozen deterministic rule.
CREATE TEMP TABLE tmp_geo_ranked ON COMMIT DROP AS
SELECT
    zip_code_prefix,
    normalized_city,
    normalized_state,
    observations,
    COUNT(*) OVER (
        PARTITION BY zip_code_prefix
    ) AS candidate_location_count,
    ROW_NUMBER() OVER (
        PARTITION BY zip_code_prefix
        ORDER BY
            observations DESC,
            normalized_state ASC NULLS LAST,
            normalized_city ASC NULLS LAST
    ) AS candidate_rank
FROM tmp_geo_candidates;

-- Pick a deterministic display label from the raw spellings that map to the
-- winning normalized pair. Frequency wins; lexical order breaks ties.
CREATE TEMP TABLE tmp_geo_display_city ON COMMIT DROP AS
WITH winning_pairs AS (
    SELECT
        zip_code_prefix,
        normalized_city,
        normalized_state
    FROM tmp_geo_ranked
    WHERE candidate_rank = 1
),
raw_variants AS (
    SELECT
        g.zip_code_prefix,
        g.raw_city,
        COUNT(*) AS observations,
        ROW_NUMBER() OVER (
            PARTITION BY g.zip_code_prefix
            ORDER BY COUNT(*) DESC, g.raw_city ASC
        ) AS raw_rank
    FROM tmp_geo_normalized g
    JOIN winning_pairs w
      ON w.zip_code_prefix = g.zip_code_prefix
     AND w.normalized_city IS NOT DISTINCT FROM g.normalized_city
     AND w.normalized_state IS NOT DISTINCT FROM g.normalized_state
    GROUP BY g.zip_code_prefix, g.raw_city
)
SELECT zip_code_prefix, raw_city
FROM raw_variants
WHERE raw_rank = 1;

-- Median coordinates use every raw observation for the prefix, not only the
-- winning city label, because the dimension grain is the CEP prefix.
CREATE TEMP TABLE tmp_geo_coordinates ON COMMIT DROP AS
SELECT
    zip_code_prefix,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY latitude) AS latitude,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY longitude) AS longitude,
    COUNT(*) AS geolocation_observation_count
FROM tmp_geo_normalized
GROUP BY zip_code_prefix;

-- Primary location members: all prefixes observed in geolocation.
INSERT INTO dw.dim_location (
    zip_code_prefix,
    city,
    city_normalized,
    state,
    latitude,
    longitude,
    geolocation_observation_count,
    candidate_location_count,
    canonical_observation_count,
    is_ambiguous
)
SELECT
    r.zip_code_prefix,
    d.raw_city,
    r.normalized_city,
    r.normalized_state,
    c.latitude,
    c.longitude,
    c.geolocation_observation_count,
    r.candidate_location_count,
    r.observations,
    r.candidate_location_count > 1
FROM tmp_geo_ranked r
JOIN tmp_geo_coordinates c
  ON c.zip_code_prefix = r.zip_code_prefix
LEFT JOIN tmp_geo_display_city d
  ON d.zip_code_prefix = r.zip_code_prefix
WHERE r.candidate_rank = 1
ORDER BY r.zip_code_prefix;

-- Fallback members for customer CEP prefixes not present in geolocation.
-- Choose the modal normalized (city,state) representation per prefix.
WITH normalized AS (
    SELECT
        customer_zip_code_prefix AS zip_code_prefix,
        customer_city AS raw_city,
        NULLIF(
            BTRIM(
                REGEXP_REPLACE(
                    LOWER(unaccent(BTRIM(customer_city))),
                    '[^a-z0-9]+',
                    ' ',
                    'g'
                )
            ),
            ''
        ) AS normalized_city,
        UPPER(BTRIM(customer_state)) AS normalized_state
    FROM olist.customers
),
candidates AS (
    SELECT
        zip_code_prefix,
        normalized_city,
        normalized_state,
        COUNT(*) AS observations
    FROM normalized
    GROUP BY zip_code_prefix, normalized_city, normalized_state
),
ranked AS (
    SELECT
        *,
        COUNT(*) OVER (PARTITION BY zip_code_prefix) AS candidate_count,
        ROW_NUMBER() OVER (
            PARTITION BY zip_code_prefix
            ORDER BY observations DESC,
                     normalized_state ASC NULLS LAST,
                     normalized_city ASC NULLS LAST
        ) AS rn
    FROM candidates
),
display AS (
    SELECT
        n.zip_code_prefix,
        n.raw_city,
        ROW_NUMBER() OVER (
            PARTITION BY n.zip_code_prefix
            ORDER BY COUNT(*) DESC, n.raw_city ASC
        ) AS rn
    FROM normalized n
    JOIN ranked r
      ON r.zip_code_prefix = n.zip_code_prefix
     AND r.normalized_city IS NOT DISTINCT FROM n.normalized_city
     AND r.normalized_state IS NOT DISTINCT FROM n.normalized_state
     AND r.rn = 1
    GROUP BY n.zip_code_prefix, n.raw_city
)
INSERT INTO dw.dim_location (
    zip_code_prefix,
    city,
    city_normalized,
    state,
    latitude,
    longitude,
    geolocation_observation_count,
    candidate_location_count,
    canonical_observation_count,
    is_ambiguous
)
SELECT
    r.zip_code_prefix,
    d.raw_city,
    r.normalized_city,
    r.normalized_state,
    NULL,
    NULL,
    0,
    r.candidate_count,
    r.observations,
    r.candidate_count > 1
FROM ranked r
LEFT JOIN display d
  ON d.zip_code_prefix = r.zip_code_prefix
 AND d.rn = 1
WHERE r.rn = 1
  AND NOT EXISTS (
      SELECT 1
      FROM dw.dim_location l
      WHERE l.zip_code_prefix = r.zip_code_prefix
  )
ORDER BY r.zip_code_prefix;

-- Fallback members for seller CEP prefixes absent from both geolocation and
-- the already-loaded customer fallback population.
WITH normalized AS (
    SELECT
        seller_zip_code_prefix AS zip_code_prefix,
        seller_city AS raw_city,
        NULLIF(
            BTRIM(
                REGEXP_REPLACE(
                    LOWER(unaccent(BTRIM(seller_city))),
                    '[^a-z0-9]+',
                    ' ',
                    'g'
                )
            ),
            ''
        ) AS normalized_city,
        UPPER(BTRIM(seller_state)) AS normalized_state
    FROM olist.sellers
),
candidates AS (
    SELECT
        zip_code_prefix,
        normalized_city,
        normalized_state,
        COUNT(*) AS observations
    FROM normalized
    GROUP BY zip_code_prefix, normalized_city, normalized_state
),
ranked AS (
    SELECT
        *,
        COUNT(*) OVER (PARTITION BY zip_code_prefix) AS candidate_count,
        ROW_NUMBER() OVER (
            PARTITION BY zip_code_prefix
            ORDER BY observations DESC,
                     normalized_state ASC NULLS LAST,
                     normalized_city ASC NULLS LAST
        ) AS rn
    FROM candidates
),
display AS (
    SELECT
        n.zip_code_prefix,
        n.raw_city,
        ROW_NUMBER() OVER (
            PARTITION BY n.zip_code_prefix
            ORDER BY COUNT(*) DESC, n.raw_city ASC
        ) AS rn
    FROM normalized n
    JOIN ranked r
      ON r.zip_code_prefix = n.zip_code_prefix
     AND r.normalized_city IS NOT DISTINCT FROM n.normalized_city
     AND r.normalized_state IS NOT DISTINCT FROM n.normalized_state
     AND r.rn = 1
    GROUP BY n.zip_code_prefix, n.raw_city
)
INSERT INTO dw.dim_location (
    zip_code_prefix,
    city,
    city_normalized,
    state,
    latitude,
    longitude,
    geolocation_observation_count,
    candidate_location_count,
    canonical_observation_count,
    is_ambiguous
)
SELECT
    r.zip_code_prefix,
    d.raw_city,
    r.normalized_city,
    r.normalized_state,
    NULL,
    NULL,
    0,
    r.candidate_count,
    r.observations,
    r.candidate_count > 1
FROM ranked r
LEFT JOIN display d
  ON d.zip_code_prefix = r.zip_code_prefix
 AND d.rn = 1
WHERE r.rn = 1
  AND NOT EXISTS (
      SELECT 1
      FROM dw.dim_location l
      WHERE l.zip_code_prefix = r.zip_code_prefix
  )
ORDER BY r.zip_code_prefix;


-- ============================================================================
-- 4. DIM_PRODUCT
-- ============================================================================

INSERT INTO dw.dim_product (
    product_id,
    product_category_name,
    product_category_name_english,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
)
SELECT
    p.product_id,
    p.product_category_name,
    t.product_category_name_english,
    p.product_name_lenght,
    p.product_description_lenght,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
FROM olist.products p
LEFT JOIN olist.category_translation t
  ON t.product_category_name = p.product_category_name
ORDER BY p.product_id;


-- ============================================================================
-- 5. DIM_SELLER
-- ============================================================================

INSERT INTO dw.dim_seller (seller_id)
SELECT seller_id
FROM olist.sellers
ORDER BY seller_id;


-- ============================================================================
-- 6. DIM_ORDER_STATUS
-- ============================================================================

INSERT INTO dw.dim_order_status (order_status)
SELECT DISTINCT order_status
FROM olist.orders
ORDER BY order_status;


-- ============================================================================
-- 7. POST-LOAD ASSERTIONS
-- ============================================================================

DO $$
DECLARE
    source_customers bigint;
    warehouse_customers bigint;
    source_products bigint;
    warehouse_products bigint;
    source_sellers bigint;
    warehouse_sellers bigint;
    source_statuses bigint;
    warehouse_statuses bigint;
    source_geo_prefixes bigint;
    missing_customer_prefixes bigint;
    missing_seller_prefixes bigint;
BEGIN
    SELECT COUNT(DISTINCT customer_unique_id)
      INTO source_customers
      FROM olist.customers;

    SELECT COUNT(*) INTO warehouse_customers FROM dw.dim_customer;

    IF source_customers <> warehouse_customers THEN
        RAISE EXCEPTION
            'dim_customer mismatch: source %, warehouse %',
            source_customers, warehouse_customers;
    END IF;

    SELECT COUNT(*) INTO source_products FROM olist.products;
    SELECT COUNT(*) INTO warehouse_products FROM dw.dim_product;

    IF source_products <> warehouse_products THEN
        RAISE EXCEPTION
            'dim_product mismatch: source %, warehouse %',
            source_products, warehouse_products;
    END IF;

    SELECT COUNT(*) INTO source_sellers FROM olist.sellers;
    SELECT COUNT(*) INTO warehouse_sellers FROM dw.dim_seller;

    IF source_sellers <> warehouse_sellers THEN
        RAISE EXCEPTION
            'dim_seller mismatch: source %, warehouse %',
            source_sellers, warehouse_sellers;
    END IF;

    SELECT COUNT(DISTINCT order_status)
      INTO source_statuses
      FROM olist.orders;

    SELECT COUNT(*) INTO warehouse_statuses FROM dw.dim_order_status;

    IF source_statuses <> warehouse_statuses THEN
        RAISE EXCEPTION
            'dim_order_status mismatch: source %, warehouse %',
            source_statuses, warehouse_statuses;
    END IF;

    SELECT COUNT(DISTINCT geolocation_zip_code_prefix)
      INTO source_geo_prefixes
      FROM olist.geolocation;

    IF (
        SELECT COUNT(*)
        FROM dw.dim_location
        WHERE geolocation_observation_count > 0
    ) <> source_geo_prefixes THEN
        RAISE EXCEPTION
            'Geolocation CEP coverage mismatch.';
    END IF;

    SELECT COUNT(*)
      INTO missing_customer_prefixes
      FROM (
          SELECT DISTINCT c.customer_zip_code_prefix
          FROM olist.customers c
          LEFT JOIN dw.dim_location l
            ON l.zip_code_prefix = c.customer_zip_code_prefix
          WHERE l.location_key IS NULL
      ) q;

    IF missing_customer_prefixes <> 0 THEN
        RAISE EXCEPTION
            'Missing % customer CEP prefixes from dim_location',
            missing_customer_prefixes;
    END IF;

    SELECT COUNT(*)
      INTO missing_seller_prefixes
      FROM (
          SELECT DISTINCT s.seller_zip_code_prefix
          FROM olist.sellers s
          LEFT JOIN dw.dim_location l
            ON l.zip_code_prefix = s.seller_zip_code_prefix
          WHERE l.location_key IS NULL
      ) q;

    IF missing_seller_prefixes <> 0 THEN
        RAISE EXCEPTION
            'Missing % seller CEP prefixes from dim_location',
            missing_seller_prefixes;
    END IF;
END $$;

COMMIT;


-- ============================================================================
-- 8. HUMAN-READABLE VALIDATION OUTPUT
-- ============================================================================

SELECT 'dim_date' AS dimension, COUNT(*) AS rows FROM dw.dim_date
UNION ALL
SELECT 'dim_customer', COUNT(*) FROM dw.dim_customer
UNION ALL
SELECT 'dim_location', COUNT(*) FROM dw.dim_location
UNION ALL
SELECT 'dim_product', COUNT(*) FROM dw.dim_product
UNION ALL
SELECT 'dim_seller', COUNT(*) FROM dw.dim_seller
UNION ALL
SELECT 'dim_order_status', COUNT(*) FROM dw.dim_order_status
ORDER BY dimension;

SELECT
    MIN(full_date) AS min_date,
    MAX(full_date) AS max_date,
    COUNT(*) AS calendar_days
FROM dw.dim_date;

SELECT
    COUNT(*) AS location_rows,
    COUNT(*) FILTER (WHERE geolocation_observation_count > 0)
        AS geolocation_prefixes,
    COUNT(*) FILTER (WHERE geolocation_observation_count = 0)
        AS fallback_prefixes,
    COUNT(*) FILTER (
        WHERE geolocation_observation_count > 0 AND is_ambiguous
    ) AS ambiguous_geolocation_prefixes,
    COUNT(*) FILTER (WHERE latitude IS NULL OR longitude IS NULL)
        AS prefixes_without_coordinates
FROM dw.dim_location;

SELECT
    zip_code_prefix,
    city,
    city_normalized,
    state,
    geolocation_observation_count,
    candidate_location_count,
    canonical_observation_count,
    is_ambiguous
FROM dw.dim_location
WHERE is_ambiguous
ORDER BY
    candidate_location_count DESC,
    geolocation_observation_count DESC,
    zip_code_prefix
LIMIT 30;

SELECT
    COUNT(*) AS products,
    COUNT(*) FILTER (WHERE product_category_name IS NULL)
        AS products_without_source_category,
    COUNT(*) FILTER (
        WHERE product_category_name IS NOT NULL
          AND product_category_name_english IS NULL
    ) AS products_with_untranslated_category
FROM dw.dim_product;
