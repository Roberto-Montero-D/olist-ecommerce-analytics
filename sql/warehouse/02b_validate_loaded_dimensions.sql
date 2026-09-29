/*
===============================================================================
Olist E-Commerce Analytics
File: sql/warehouse/02b_validate_loaded_dimensions.sql
Phase: B2.2 — Post-load dimensional validation

Purpose
-------
Perform the three targeted checks required before freezing loaded dimensions:
1. Identify which source field produces the maximum dim_date date.
2. Reconcile 518 pair-level ambiguous CEPs with city/state ambiguity.
3. Audit the 162 fallback dim_location members by source coverage.

Read-only: no source or warehouse data is modified.
===============================================================================
*/


-- ============================================================================
-- CHECK 1 — SOURCE OF THE MAXIMUM DIM_DATE DATE
-- ============================================================================

WITH source_dates AS (
    SELECT 'orders.order_purchase_timestamp' AS source_column,
           order_id AS source_id,
           order_purchase_timestamp AS source_timestamp
    FROM olist.orders
    WHERE order_purchase_timestamp IS NOT NULL

    UNION ALL
    SELECT 'orders.order_approved_at',
           order_id,
           order_approved_at
    FROM olist.orders
    WHERE order_approved_at IS NOT NULL

    UNION ALL
    SELECT 'orders.order_delivered_carrier_date',
           order_id,
           order_delivered_carrier_date
    FROM olist.orders
    WHERE order_delivered_carrier_date IS NOT NULL

    UNION ALL
    SELECT 'orders.order_delivered_customer_date',
           order_id,
           order_delivered_customer_date
    FROM olist.orders
    WHERE order_delivered_customer_date IS NOT NULL

    UNION ALL
    SELECT 'orders.order_estimated_delivery_date',
           order_id,
           order_estimated_delivery_date
    FROM olist.orders
    WHERE order_estimated_delivery_date IS NOT NULL

    UNION ALL
    SELECT 'order_items.shipping_limit_date',
           order_id || ':' || order_item_id::text,
           shipping_limit_date
    FROM olist.order_items
    WHERE shipping_limit_date IS NOT NULL

    UNION ALL
    SELECT 'order_reviews.review_creation_date',
           review_id || ':' || order_id,
           review_creation_date
    FROM olist.order_reviews
    WHERE review_creation_date IS NOT NULL

    UNION ALL
    SELECT 'order_reviews.review_answer_timestamp',
           review_id || ':' || order_id,
           review_answer_timestamp
    FROM olist.order_reviews
    WHERE review_answer_timestamp IS NOT NULL
),
ranked AS (
    SELECT
        source_column,
        source_id,
        source_timestamp,
        MAX(source_timestamp) OVER () AS overall_max_timestamp
    FROM source_dates
)
SELECT
    source_column,
    source_id,
    source_timestamp
FROM ranked
WHERE source_timestamp = overall_max_timestamp
ORDER BY source_column, source_id;


-- Maximum timestamp independently for every contributing source field.
SELECT *
FROM (
    SELECT 'orders.order_purchase_timestamp' AS source_column,
           MAX(order_purchase_timestamp) AS max_timestamp
    FROM olist.orders
    UNION ALL
    SELECT 'orders.order_approved_at', MAX(order_approved_at)
    FROM olist.orders
    UNION ALL
    SELECT 'orders.order_delivered_carrier_date',
           MAX(order_delivered_carrier_date)
    FROM olist.orders
    UNION ALL
    SELECT 'orders.order_delivered_customer_date',
           MAX(order_delivered_customer_date)
    FROM olist.orders
    UNION ALL
    SELECT 'orders.order_estimated_delivery_date',
           MAX(order_estimated_delivery_date)
    FROM olist.orders
    UNION ALL
    SELECT 'order_items.shipping_limit_date', MAX(shipping_limit_date)
    FROM olist.order_items
    UNION ALL
    SELECT 'order_reviews.review_creation_date', MAX(review_creation_date)
    FROM olist.order_reviews
    UNION ALL
    SELECT 'order_reviews.review_answer_timestamp',
           MAX(review_answer_timestamp)
    FROM olist.order_reviews
) q
ORDER BY max_timestamp DESC NULLS LAST;


-- Show all source records dated after the end of 2018, if any.
WITH late_dates AS (
    SELECT 'orders.order_purchase_timestamp' AS source_column,
           order_id AS source_id,
           order_purchase_timestamp AS source_timestamp
    FROM olist.orders
    WHERE order_purchase_timestamp >= TIMESTAMP '2019-01-01'

    UNION ALL
    SELECT 'orders.order_approved_at', order_id, order_approved_at
    FROM olist.orders
    WHERE order_approved_at >= TIMESTAMP '2019-01-01'

    UNION ALL
    SELECT 'orders.order_delivered_carrier_date',
           order_id, order_delivered_carrier_date
    FROM olist.orders
    WHERE order_delivered_carrier_date >= TIMESTAMP '2019-01-01'

    UNION ALL
    SELECT 'orders.order_delivered_customer_date',
           order_id, order_delivered_customer_date
    FROM olist.orders
    WHERE order_delivered_customer_date >= TIMESTAMP '2019-01-01'

    UNION ALL
    SELECT 'orders.order_estimated_delivery_date',
           order_id, order_estimated_delivery_date
    FROM olist.orders
    WHERE order_estimated_delivery_date >= TIMESTAMP '2019-01-01'

    UNION ALL
    SELECT 'order_items.shipping_limit_date',
           order_id || ':' || order_item_id::text, shipping_limit_date
    FROM olist.order_items
    WHERE shipping_limit_date >= TIMESTAMP '2019-01-01'

    UNION ALL
    SELECT 'order_reviews.review_creation_date',
           review_id || ':' || order_id, review_creation_date
    FROM olist.order_reviews
    WHERE review_creation_date >= TIMESTAMP '2019-01-01'

    UNION ALL
    SELECT 'order_reviews.review_answer_timestamp',
           review_id || ':' || order_id, review_answer_timestamp
    FROM olist.order_reviews
    WHERE review_answer_timestamp >= TIMESTAMP '2019-01-01'
)
SELECT *
FROM late_dates
ORDER BY source_timestamp, source_column, source_id;


-- ============================================================================
-- CHECK 2 — RECONCILE THE 518 AMBIGUOUS GEOLOCATION PREFIXES
-- ============================================================================

WITH normalized AS (
    SELECT
        geolocation_zip_code_prefix AS zip_code_prefix,
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
        UPPER(BTRIM(geolocation_state)) AS normalized_state
    FROM olist.geolocation
),
per_prefix AS (
    SELECT
        zip_code_prefix,
        COUNT(DISTINCT normalized_city) AS city_count,
        COUNT(DISTINCT normalized_state) AS state_count,
        COUNT(DISTINCT (normalized_city, normalized_state)) AS pair_count
    FROM normalized
    GROUP BY zip_code_prefix
)
SELECT
    COUNT(*) AS geolocation_prefixes,
    COUNT(*) FILTER (WHERE city_count > 1) AS multiple_normalized_cities,
    COUNT(*) FILTER (WHERE state_count > 1) AS multiple_normalized_states,
    COUNT(*) FILTER (WHERE pair_count > 1) AS multiple_city_state_pairs,
    COUNT(*) FILTER (
        WHERE city_count = 1 AND state_count > 1
    ) AS state_only_ambiguity,
    COUNT(*) FILTER (
        WHERE city_count > 1 AND state_count = 1
    ) AS city_only_ambiguity,
    COUNT(*) FILTER (
        WHERE city_count > 1 AND state_count > 1
    ) AS both_city_and_state_ambiguity
FROM per_prefix;


-- Distribution should make the 513-vs-518 distinction explicit.
WITH normalized AS (
    SELECT
        geolocation_zip_code_prefix AS zip_code_prefix,
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
        UPPER(BTRIM(geolocation_state)) AS normalized_state
    FROM olist.geolocation
),
per_prefix AS (
    SELECT
        zip_code_prefix,
        COUNT(DISTINCT normalized_city) AS city_count,
        COUNT(DISTINCT normalized_state) AS state_count,
        COUNT(DISTINCT (normalized_city, normalized_state)) AS pair_count
    FROM normalized
    GROUP BY zip_code_prefix
)
SELECT
    city_count,
    state_count,
    pair_count,
    COUNT(*) AS prefixes
FROM per_prefix
GROUP BY city_count, state_count, pair_count
ORDER BY city_count, state_count, pair_count;


-- The state-only ambiguous prefixes responsible for pair ambiguity not counted
-- by the "multiple normalized cities" metric.
WITH normalized AS (
    SELECT
        geolocation_zip_code_prefix AS zip_code_prefix,
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
        UPPER(BTRIM(geolocation_state)) AS normalized_state
    FROM olist.geolocation
),
per_prefix AS (
    SELECT
        zip_code_prefix,
        COUNT(DISTINCT normalized_city) AS city_count,
        COUNT(DISTINCT normalized_state) AS state_count
    FROM normalized
    GROUP BY zip_code_prefix
)
SELECT
    n.zip_code_prefix,
    n.normalized_city,
    n.normalized_state,
    COUNT(*) AS observations
FROM normalized n
JOIN per_prefix p USING (zip_code_prefix)
WHERE p.city_count = 1
  AND p.state_count > 1
GROUP BY
    n.zip_code_prefix,
    n.normalized_city,
    n.normalized_state
ORDER BY n.zip_code_prefix, observations DESC, n.normalized_state;


-- Confirm warehouse flag count equals source pair-level ambiguity.
WITH normalized AS (
    SELECT
        geolocation_zip_code_prefix AS zip_code_prefix,
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
        UPPER(BTRIM(geolocation_state)) AS normalized_state
    FROM olist.geolocation
),
source_ambiguous AS (
    SELECT zip_code_prefix
    FROM normalized
    GROUP BY zip_code_prefix
    HAVING COUNT(DISTINCT (normalized_city, normalized_state)) > 1
),
warehouse_ambiguous AS (
    SELECT zip_code_prefix
    FROM dw.dim_location
    WHERE geolocation_observation_count > 0
      AND is_ambiguous
)
SELECT
    (SELECT COUNT(*) FROM source_ambiguous) AS source_pair_ambiguous,
    (SELECT COUNT(*) FROM warehouse_ambiguous) AS warehouse_flagged_ambiguous,
    (
        SELECT COUNT(*)
        FROM source_ambiguous s
        FULL OUTER JOIN warehouse_ambiguous w USING (zip_code_prefix)
        WHERE s.zip_code_prefix IS NULL
           OR w.zip_code_prefix IS NULL
    ) AS mismatched_prefixes;


-- ============================================================================
-- CHECK 3 — AUDIT THE 162 FALLBACK LOCATION MEMBERS
-- ============================================================================

WITH customer_prefixes AS (
    SELECT DISTINCT customer_zip_code_prefix AS zip_code_prefix
    FROM olist.customers
),
seller_prefixes AS (
    SELECT DISTINCT seller_zip_code_prefix AS zip_code_prefix
    FROM olist.sellers
),
fallback AS (
    SELECT
        l.location_key,
        l.zip_code_prefix,
        l.city,
        l.city_normalized,
        l.state,
        l.candidate_location_count,
        l.canonical_observation_count,
        l.is_ambiguous,
        (c.zip_code_prefix IS NOT NULL) AS used_by_customers,
        (s.zip_code_prefix IS NOT NULL) AS used_by_sellers
    FROM dw.dim_location l
    LEFT JOIN customer_prefixes c USING (zip_code_prefix)
    LEFT JOIN seller_prefixes s USING (zip_code_prefix)
    WHERE l.geolocation_observation_count = 0
)
SELECT
    COUNT(*) AS fallback_prefixes,
    COUNT(*) FILTER (
        WHERE used_by_customers AND NOT used_by_sellers
    ) AS customer_only,
    COUNT(*) FILTER (
        WHERE used_by_sellers AND NOT used_by_customers
    ) AS seller_only,
    COUNT(*) FILTER (
        WHERE used_by_customers AND used_by_sellers
    ) AS customer_and_seller,
    COUNT(*) FILTER (WHERE is_ambiguous) AS ambiguous_fallbacks,
    COUNT(*) FILTER (WHERE city IS NULL) AS missing_city,
    COUNT(*) FILTER (WHERE state IS NULL) AS missing_state
FROM fallback;


-- Count source rows that will rely on fallback members in the facts.
SELECT
    COUNT(*) AS customer_rows_using_fallback,
    COUNT(DISTINCT c.customer_zip_code_prefix)
        AS customer_fallback_prefixes
FROM olist.customers c
JOIN dw.dim_location l
  ON l.zip_code_prefix = c.customer_zip_code_prefix
WHERE l.geolocation_observation_count = 0;

SELECT
    COUNT(*) AS seller_rows_using_fallback,
    COUNT(DISTINCT s.seller_zip_code_prefix)
        AS seller_fallback_prefixes
FROM olist.sellers s
JOIN dw.dim_location l
  ON l.zip_code_prefix = s.seller_zip_code_prefix
WHERE l.geolocation_observation_count = 0;


-- Detailed fallback list for audit/documentation.
WITH customer_prefixes AS (
    SELECT DISTINCT customer_zip_code_prefix AS zip_code_prefix
    FROM olist.customers
),
seller_prefixes AS (
    SELECT DISTINCT seller_zip_code_prefix AS zip_code_prefix
    FROM olist.sellers
)
SELECT
    l.zip_code_prefix,
    l.city,
    l.city_normalized,
    l.state,
    l.candidate_location_count,
    l.canonical_observation_count,
    l.is_ambiguous,
    (c.zip_code_prefix IS NOT NULL) AS used_by_customers,
    (s.zip_code_prefix IS NOT NULL) AS used_by_sellers
FROM dw.dim_location l
LEFT JOIN customer_prefixes c USING (zip_code_prefix)
LEFT JOIN seller_prefixes s USING (zip_code_prefix)
WHERE l.geolocation_observation_count = 0
ORDER BY
    used_by_customers DESC,
    used_by_sellers DESC,
    l.zip_code_prefix;
