/*
===============================================================================
Olist E-Commerce Analytics
File: sql/warehouse/00_validate_dimensional_design.sql
Phase: B2 — Dimensional Modeling & Data Warehouse

Purpose
-------
Validate source-data assumptions that affect the dimensional model before
creating the warehouse schema.

Questions
---------
1. Is customer_unique_id associated with a stable geographic location?
2. Can geolocation_zip_code_prefix support a one-row-per-ZIP dimension?
3. How should multiple review records for the same order be represented?

No source data is modified by this script.
===============================================================================
*/


-- Reproducible dependency for accent/diacritic normalization.
CREATE EXTENSION IF NOT EXISTS unaccent;


-- ============================================================================
-- 1. CUSTOMER LOCATION STABILITY
-- ============================================================================

-- Proposed dim_customer grain:
--     one row per customer_unique_id
--
-- Geographic attributes are transactional in the source: the same persistent
-- customer can appear under more than one customer_id and more than one
-- location. Compare raw and normalized city strings before deciding whether
-- geography belongs on dim_customer.
--
-- Lexical city normalization used in this validation:
--   1. remove diacritics with PostgreSQL unaccent;
--   2. convert to lower case;
--   3. convert punctuation/dividers (hyphens, underscores, slashes, periods,
--      apostrophes, etc.) to spaces;
--   4. collapse repeated whitespace;
--   5. trim leading/trailing whitespace.
--
-- PostgreSQL's unaccent extension is required and created above if absent.
-- This is deterministic text normalization, not fuzzy matching or geographic
-- entity resolution. It intentionally does not guess that misspellings or
-- genuinely different place names are the same city.


-- 1.1 Overall customer-location stability: raw vs normalized city names

WITH normalized_customers AS (
    SELECT
        customer_unique_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state,
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
customer_locations AS (
    SELECT
        customer_unique_id,
        COUNT(*) AS customer_records,
        COUNT(DISTINCT customer_zip_code_prefix) AS zip_count,
        COUNT(DISTINCT customer_city) AS raw_city_count,
        COUNT(DISTINCT normalized_city) AS normalized_city_count,
        COUNT(DISTINCT customer_state) AS raw_state_count,
        COUNT(DISTINCT normalized_state) AS normalized_state_count
    FROM normalized_customers
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) AS unique_customers,
    COUNT(*) FILTER (WHERE customer_records > 1)
        AS customers_with_multiple_records,
    COUNT(*) FILTER (WHERE zip_count > 1)
        AS customers_with_multiple_zips,
    COUNT(*) FILTER (WHERE raw_city_count > 1)
        AS customers_with_multiple_raw_city_strings,
    COUNT(*) FILTER (WHERE normalized_city_count > 1)
        AS customers_with_multiple_normalized_cities,
    COUNT(*) FILTER (WHERE raw_state_count > 1)
        AS customers_with_multiple_raw_states,
    COUNT(*) FILTER (WHERE normalized_state_count > 1)
        AS customers_with_multiple_normalized_states
FROM customer_locations;


-- 1.2 Distribution of persistent-customer locations after normalization

WITH normalized_customers AS (
    SELECT
        customer_unique_id,
        customer_zip_code_prefix,
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
customer_locations AS (
    SELECT
        customer_unique_id,
        COUNT(*) AS customer_records,
        COUNT(DISTINCT customer_zip_code_prefix) AS zip_count,
        COUNT(DISTINCT normalized_city) AS city_count,
        COUNT(DISTINCT normalized_state) AS state_count
    FROM normalized_customers
    GROUP BY customer_unique_id
)
SELECT
    zip_count,
    city_count,
    state_count,
    COUNT(*) AS customers
FROM customer_locations
GROUP BY zip_count, city_count, state_count
ORDER BY zip_count, city_count, state_count;


-- 1.3 Examples of customers whose normalized recorded location changes

WITH normalized_customers AS (
    SELECT
        customer_unique_id,
        customer_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state,
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
changing_customers AS (
    SELECT customer_unique_id
    FROM normalized_customers
    GROUP BY customer_unique_id
    HAVING COUNT(DISTINCT customer_zip_code_prefix) > 1
        OR COUNT(DISTINCT normalized_city) > 1
        OR COUNT(DISTINCT normalized_state) > 1
)
SELECT
    c.customer_unique_id,
    c.customer_id,
    c.customer_zip_code_prefix,
    c.customer_city AS raw_city,
    c.normalized_city,
    c.customer_state AS raw_state,
    c.normalized_state
FROM normalized_customers AS c
JOIN changing_customers AS cc
    ON c.customer_unique_id = cc.customer_unique_id
ORDER BY c.customer_unique_id, c.customer_id
LIMIT 50;


-- ============================================================================
-- 2. GEOLOCATION GRAIN, TEXT NORMALIZATION, AND AMBIGUITY
-- ============================================================================

-- Raw geolocation contains many rows per five-digit CEP prefix. The raw source
-- is immutable. Normalized city/state values below exist only inside the
-- validation queries so that formatting differences are not mistaken for
-- genuine geographic ambiguity. The normalization pipeline is:
--   BTRIM -> unaccent -> lower -> non-alphanumeric separators to spaces
--   -> collapse repeated separators/whitespace -> BTRIM -> NULLIF empty.


-- 2.1 Basic CEP-prefix cardinality and representation checks

SELECT
    COUNT(*) AS geolocation_rows,
    COUNT(DISTINCT geolocation_zip_code_prefix) AS distinct_zip_prefixes,
    ROUND(
        COUNT(*)::NUMERIC
        / NULLIF(COUNT(DISTINCT geolocation_zip_code_prefix), 0),
        2
    ) AS average_rows_per_zip,
    COUNT(*) FILTER (
        WHERE geolocation_zip_code_prefix !~ '^[0-9]{5}$'
    ) AS invalid_five_digit_prefixes,
    COUNT(*) FILTER (
        WHERE geolocation_zip_code_prefix LIKE '0%'
    ) AS prefixes_with_leading_zero_rows
FROM olist.geolocation;


-- 2.2 Raw vs normalized city/state ambiguity by CEP prefix

WITH normalized_geolocation AS (
    SELECT
        geolocation_zip_code_prefix,
        geolocation_city,
        geolocation_state,
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
zip_geography AS (
    SELECT
        geolocation_zip_code_prefix,
        COUNT(*) AS rows_per_zip,
        COUNT(DISTINCT geolocation_city) AS raw_city_count,
        COUNT(DISTINCT normalized_city) AS normalized_city_count,
        COUNT(DISTINCT geolocation_state) AS raw_state_count,
        COUNT(DISTINCT normalized_state) AS normalized_state_count
    FROM normalized_geolocation
    GROUP BY geolocation_zip_code_prefix
)
SELECT
    COUNT(*) AS zip_prefixes,
    COUNT(*) FILTER (WHERE raw_city_count > 1)
        AS zips_with_multiple_raw_city_strings,
    COUNT(*) FILTER (WHERE normalized_city_count > 1)
        AS zips_with_multiple_normalized_cities,
    COUNT(*) FILTER (WHERE raw_state_count > 1)
        AS zips_with_multiple_raw_states,
    COUNT(*) FILTER (WHERE normalized_state_count > 1)
        AS zips_with_multiple_normalized_states,
    MAX(raw_city_count) AS maximum_raw_city_strings_per_zip,
    MAX(normalized_city_count) AS maximum_normalized_cities_per_zip,
    MAX(normalized_state_count) AS maximum_normalized_states_per_zip,
    MAX(rows_per_zip) AS maximum_rows_per_zip
FROM zip_geography;


-- 2.3 Distribution of ambiguity after normalization

WITH normalized_geolocation AS (
    SELECT
        geolocation_zip_code_prefix,
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
zip_geography AS (
    SELECT
        geolocation_zip_code_prefix,
        COUNT(DISTINCT normalized_city) AS city_count,
        COUNT(DISTINCT normalized_state) AS state_count
    FROM normalized_geolocation
    GROUP BY geolocation_zip_code_prefix
)
SELECT
    city_count,
    state_count,
    COUNT(*) AS zip_prefixes
FROM zip_geography
GROUP BY city_count, state_count
ORDER BY city_count, state_count;


-- 2.4 Normalization diagnostics
--
-- Shows how many raw spellings collapse to the same normalized city and checks
-- that normalization never produces an empty city value.

WITH normalized_geolocation AS (
    SELECT
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
        ) AS normalized_city
    FROM olist.geolocation
),
normalization_groups AS (
    SELECT
        normalized_city,
        COUNT(DISTINCT raw_city) AS raw_variants,
        COUNT(*) AS observations
    FROM normalized_geolocation
    GROUP BY normalized_city
)
SELECT
    (SELECT COUNT(*)
     FROM normalized_geolocation
     WHERE normalized_city IS NULL) AS empty_after_normalization,
    COUNT(*) FILTER (WHERE raw_variants > 1)
        AS normalized_cities_with_multiple_raw_variants,
    MAX(raw_variants) AS maximum_raw_variants_for_one_normalized_city
FROM normalization_groups;


-- 2.5 Largest raw-city normalization collisions
--
-- A collision here is expected when strings differ only by accents, case,
-- punctuation, separators, or whitespace. Inspecting examples guards against
-- overly aggressive normalization.

WITH normalized_geolocation AS (
    SELECT
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
        ) AS normalized_city
    FROM olist.geolocation
),
variant_counts AS (
    SELECT
        normalized_city,
        raw_city,
        COUNT(*) AS observations
    FROM normalized_geolocation
    GROUP BY normalized_city, raw_city
),
collisions AS (
    SELECT normalized_city
    FROM variant_counts
    GROUP BY normalized_city
    HAVING COUNT(*) > 1
)
SELECT
    v.normalized_city,
    v.raw_city,
    v.observations
FROM variant_counts AS v
JOIN collisions AS c
    ON v.normalized_city = c.normalized_city
ORDER BY
    v.normalized_city,
    v.observations DESC,
    v.raw_city
LIMIT 100;


-- 2.6 Remaining genuinely ambiguous CEP prefixes after normalization

WITH normalized_geolocation AS (
    SELECT
        geolocation_zip_code_prefix,
        geolocation_city,
        geolocation_state,
        geolocation_lat,
        geolocation_lng,
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
ambiguous_zips AS (
    SELECT geolocation_zip_code_prefix
    FROM normalized_geolocation
    GROUP BY geolocation_zip_code_prefix
    HAVING COUNT(DISTINCT normalized_city) > 1
        OR COUNT(DISTINCT normalized_state) > 1
)
SELECT
    g.geolocation_zip_code_prefix,
    g.normalized_city,
    g.normalized_state,
    COUNT(*) AS observations,
    COUNT(DISTINCT g.geolocation_city) AS raw_city_variants,
    ROUND(AVG(g.geolocation_lat)::NUMERIC, 6) AS average_latitude,
    ROUND(AVG(g.geolocation_lng)::NUMERIC, 6) AS average_longitude
FROM normalized_geolocation AS g
JOIN ambiguous_zips AS az
    ON g.geolocation_zip_code_prefix = az.geolocation_zip_code_prefix
GROUP BY
    g.geolocation_zip_code_prefix,
    g.normalized_city,
    g.normalized_state
ORDER BY
    g.geolocation_zip_code_prefix,
    observations DESC,
    g.normalized_city
LIMIT 100;


-- 2.7 Candidate one-row-per-CEP-prefix coordinate representation
--
-- Median coordinates are included alongside averages. Geolocation contains
-- repeated/noisy coordinate observations, so the median can be more robust
-- to extreme coordinate values.

SELECT
    geolocation_zip_code_prefix,
    ROUND(AVG(geolocation_lat)::NUMERIC, 6) AS mean_latitude,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lat)::NUMERIC,
        6
    ) AS median_latitude,
    ROUND(AVG(geolocation_lng)::NUMERIC, 6) AS mean_longitude,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lng)::NUMERIC,
        6
    ) AS median_longitude,
    COUNT(*) AS observations
FROM olist.geolocation
GROUP BY geolocation_zip_code_prefix
ORDER BY observations DESC
LIMIT 30;


-- ============================================================================
-- 3. MULTIPLE REVIEWS PER ORDER
-- ============================================================================

-- Candidate warehouse review grain:
--     one row per raw review event: (review_id, order_id)
--
-- Quantify the information that would be lost by collapsing multiple raw
-- review events to one row per order. This validation supports preserving
-- atomic review-event grain in fact_reviews.


-- 3.1 Review-order cardinality

SELECT
    COUNT(*) AS review_rows,
    COUNT(DISTINCT review_id) AS distinct_review_ids,
    COUNT(DISTINCT order_id) AS reviewed_orders,

    COUNT(*) - COUNT(DISTINCT order_id)
        AS extra_review_rows_above_one_per_order

FROM olist.order_reviews;


-- 3.2 Number of review records per order

WITH reviews_per_order AS (
    SELECT
        order_id,
        COUNT(*) AS review_count
    FROM olist.order_reviews
    GROUP BY order_id
)
SELECT
    review_count,
    COUNT(*) AS orders
FROM reviews_per_order
GROUP BY review_count
ORDER BY review_count;


-- 3.3 Do multi-review orders contain different scores?

WITH multi_review_orders AS (
    SELECT
        order_id,
        COUNT(*) AS review_count,
        COUNT(DISTINCT review_score) AS distinct_scores,
        MIN(review_score) AS minimum_score,
        MAX(review_score) AS maximum_score,
        AVG(review_score::NUMERIC) AS average_score
    FROM olist.order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*) AS multi_review_orders,

    COUNT(*) FILTER (
        WHERE distinct_scores = 1
    ) AS same_score_orders,

    COUNT(*) FILTER (
        WHERE distinct_scores > 1
    ) AS different_score_orders,

    ROUND(
        COUNT(*) FILTER (
            WHERE distinct_scores > 1
        )::NUMERIC
        / NULLIF(COUNT(*), 0)
        * 100,
        2
    ) AS different_score_percentage

FROM multi_review_orders;


-- 3.4 Score-change magnitude for multi-review orders

WITH multi_review_orders AS (
    SELECT
        order_id,
        COUNT(*) AS review_count,
        COUNT(DISTINCT review_score) AS distinct_scores,
        MIN(review_score) AS minimum_score,
        MAX(review_score) AS maximum_score
    FROM olist.order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
)
SELECT
    maximum_score - minimum_score AS score_range,
    COUNT(*) AS orders
FROM multi_review_orders
GROUP BY maximum_score - minimum_score
ORDER BY score_range;


-- 3.5 Inspect examples where review scores differ

WITH conflicting_reviews AS (
    SELECT
        order_id
    FROM olist.order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
       AND COUNT(DISTINCT review_score) > 1
)
SELECT
    r.order_id,
    r.review_id,
    r.review_score,
    r.review_creation_date,
    r.review_answer_timestamp,
    CASE
        WHEN r.review_comment_title IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS has_title,
    CASE
        WHEN r.review_comment_message IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS has_message
FROM olist.order_reviews AS r
JOIN conflicting_reviews AS cr
    ON r.order_id = cr.order_id
ORDER BY
    r.order_id,
    r.review_answer_timestamp
LIMIT 100;


-- ============================================================================
-- 4. REVIEW TIMESTAMP ORDERING
-- ============================================================================

-- Review events remain atomic in the warehouse design. Timestamp ordering is
-- still validated because it is useful for downstream temporal review analyses
-- and for understanding whether a deterministic latest-review view is possible.

WITH multi_review_orders AS (
    SELECT
        order_id
    FROM olist.order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
),
timestamp_check AS (
    SELECT
        r.order_id,
        COUNT(*) AS review_count,
        COUNT(DISTINCT r.review_answer_timestamp) AS answer_timestamp_count,
        COUNT(DISTINCT r.review_creation_date) AS creation_date_count
    FROM olist.order_reviews AS r
    JOIN multi_review_orders AS m
        ON r.order_id = m.order_id
    GROUP BY r.order_id
)
SELECT
    COUNT(*) AS multi_review_orders,

    COUNT(*) FILTER (
        WHERE answer_timestamp_count = review_count
    ) AS uniquely_ordered_by_answer_timestamp,

    COUNT(*) FILTER (
        WHERE answer_timestamp_count < review_count
    ) AS duplicate_answer_timestamps,

    COUNT(*) FILTER (
        WHERE creation_date_count < review_count
    ) AS duplicate_creation_dates

FROM timestamp_check;