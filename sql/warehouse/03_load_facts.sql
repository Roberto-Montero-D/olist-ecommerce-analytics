/*
===============================================================================
Olist E-Commerce Analytics
File: sql/warehouse/03_load_facts.sql
Phase: B2.2 — Dimensional Modeling & Data Warehouse

Purpose
-------
Populate the four warehouse fact tables at their frozen grains:

    fact_orders       one row per order_id
    fact_order_items  one row per (order_id, order_item_id)
    fact_payments     one row per (order_id, payment_sequential)
    fact_reviews      one row per (review_id, order_id)

Prerequisites
-------------
1. 01_create_warehouse_schema.sql
2. 02_load_dimensions.sql
3. Loaded dimensions have passed 02b_validate_loaded_dimensions.sql.

Design rules
------------
- No fact-to-fact joins are used to resolve dimensional context.
- Shared order/customer/status context is resolved directly from source tables
  and conformed dimensions.
- order_id remains a degenerate business identifier in each relevant fact.
- Customer geography is the location associated with that order's customer_id.
- Seller geography is attached to fact_order_items through seller_location_key.
- Source rows are preserved at their natural grain; no aggregation is performed.
===============================================================================
*/

BEGIN;

-- Fail early if this loader is accidentally run twice.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM dw.fact_orders LIMIT 1)
       OR EXISTS (SELECT 1 FROM dw.fact_order_items LIMIT 1)
       OR EXISTS (SELECT 1 FROM dw.fact_payments LIMIT 1)
       OR EXISTS (SELECT 1 FROM dw.fact_reviews LIMIT 1) THEN
        RAISE EXCEPTION
            'Warehouse facts are not empty. Rebuild the warehouse before reloading facts.';
    END IF;
END $$;


-- ============================================================================
-- 0. PRE-LOAD DIMENSION-RESOLUTION ASSERTIONS
-- ============================================================================

-- Every source row required by a fact must resolve to all mandatory dimensions.
-- These checks deliberately occur before the first INSERT.

DO $$
DECLARE
    unresolved bigint;
BEGIN
    -- Orders -> persistent customer
    SELECT COUNT(*)
    INTO unresolved
    FROM olist.orders o
    JOIN olist.customers c
      ON c.customer_id = o.customer_id
    LEFT JOIN dw.dim_customer dc
      ON dc.customer_unique_id = c.customer_unique_id
    WHERE dc.customer_key IS NULL;

    IF unresolved <> 0 THEN
        RAISE EXCEPTION 'Unresolved order customer dimension rows: %', unresolved;
    END IF;

    -- Orders -> customer location
    SELECT COUNT(*)
    INTO unresolved
    FROM olist.orders o
    JOIN olist.customers c
      ON c.customer_id = o.customer_id
    LEFT JOIN dw.dim_location dl
      ON dl.zip_code_prefix = c.customer_zip_code_prefix
    WHERE dl.location_key IS NULL;

    IF unresolved <> 0 THEN
        RAISE EXCEPTION 'Unresolved order customer locations: %', unresolved;
    END IF;

    -- Orders -> status
    SELECT COUNT(*)
    INTO unresolved
    FROM olist.orders o
    LEFT JOIN dw.dim_order_status ds
      ON ds.order_status = o.order_status
    WHERE ds.order_status_key IS NULL;

    IF unresolved <> 0 THEN
        RAISE EXCEPTION 'Unresolved order statuses: %', unresolved;
    END IF;

    -- Order items -> product
    SELECT COUNT(*)
    INTO unresolved
    FROM olist.order_items oi
    LEFT JOIN dw.dim_product dp
      ON dp.product_id = oi.product_id
    WHERE dp.product_key IS NULL;

    IF unresolved <> 0 THEN
        RAISE EXCEPTION 'Unresolved order-item products: %', unresolved;
    END IF;

    -- Order items -> seller
    SELECT COUNT(*)
    INTO unresolved
    FROM olist.order_items oi
    LEFT JOIN dw.dim_seller ds
      ON ds.seller_id = oi.seller_id
    WHERE ds.seller_key IS NULL;

    IF unresolved <> 0 THEN
        RAISE EXCEPTION 'Unresolved order-item sellers: %', unresolved;
    END IF;

    -- Order items -> seller location
    SELECT COUNT(*)
    INTO unresolved
    FROM olist.order_items oi
    JOIN olist.sellers s
      ON s.seller_id = oi.seller_id
    LEFT JOIN dw.dim_location dl
      ON dl.zip_code_prefix = s.seller_zip_code_prefix
    WHERE dl.location_key IS NULL;

    IF unresolved <> 0 THEN
        RAISE EXCEPTION 'Unresolved order-item seller locations: %', unresolved;
    END IF;
END $$;


-- ============================================================================
-- 1. FACT_ORDERS
-- ============================================================================

INSERT INTO dw.fact_orders (
    order_id,
    customer_key,
    customer_location_key,
    order_status_key,
    purchase_date_key,
    approved_date_key,
    carrier_date_key,
    delivered_customer_date_key,
    estimated_delivery_date_key,
    customer_id,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    delivery_days,
    delivery_delay_days,
    is_late_delivery
)
SELECT
    o.order_id,
    dc.customer_key,
    dl.location_key,
    dos.order_status_key,

    TO_CHAR(o.order_purchase_timestamp::date, 'YYYYMMDD')::integer,
    CASE
        WHEN o.order_approved_at IS NOT NULL
        THEN TO_CHAR(o.order_approved_at::date, 'YYYYMMDD')::integer
    END,
    CASE
        WHEN o.order_delivered_carrier_date IS NOT NULL
        THEN TO_CHAR(o.order_delivered_carrier_date::date, 'YYYYMMDD')::integer
    END,
    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
        THEN TO_CHAR(o.order_delivered_customer_date::date, 'YYYYMMDD')::integer
    END,
    TO_CHAR(o.order_estimated_delivery_date::date, 'YYYYMMDD')::integer,

    o.customer_id,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL THEN
            ROUND(
                (
                    EXTRACT(EPOCH FROM (
                        o.order_delivered_customer_date
                        - o.order_purchase_timestamp
                    )) / 86400.0
                )::numeric,
                2
            )
    END AS delivery_days,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL THEN
            ROUND(
                (
                    EXTRACT(EPOCH FROM (
                        o.order_delivered_customer_date
                        - o.order_estimated_delivery_date
                    )) / 86400.0
                )::numeric,
                2
            )
    END AS delivery_delay_days,

    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        ELSE o.order_delivered_customer_date > o.order_estimated_delivery_date
    END AS is_late_delivery

FROM olist.orders o
JOIN olist.customers c
  ON c.customer_id = o.customer_id
JOIN dw.dim_customer dc
  ON dc.customer_unique_id = c.customer_unique_id
JOIN dw.dim_location dl
  ON dl.zip_code_prefix = c.customer_zip_code_prefix
JOIN dw.dim_order_status dos
  ON dos.order_status = o.order_status
ORDER BY o.order_id;


-- ============================================================================
-- 2. FACT_ORDER_ITEMS
-- ============================================================================

INSERT INTO dw.fact_order_items (
    order_id,
    order_item_id,
    product_key,
    seller_key,
    customer_key,
    customer_location_key,
    seller_location_key,
    order_status_key,
    purchase_date_key,
    shipping_limit_date_key,
    shipping_limit_date,
    price,
    freight_value
)
SELECT
    oi.order_id,
    oi.order_item_id,
    dp.product_key,
    ds.seller_key,
    dc.customer_key,
    dcl.location_key,
    dsl.location_key,
    dos.order_status_key,
    TO_CHAR(o.order_purchase_timestamp::date, 'YYYYMMDD')::integer,
    TO_CHAR(oi.shipping_limit_date::date, 'YYYYMMDD')::integer,
    oi.shipping_limit_date,
    oi.price,
    oi.freight_value
FROM olist.order_items oi
JOIN olist.orders o
  ON o.order_id = oi.order_id
JOIN olist.customers c
  ON c.customer_id = o.customer_id
JOIN olist.sellers s
  ON s.seller_id = oi.seller_id
JOIN dw.dim_product dp
  ON dp.product_id = oi.product_id
JOIN dw.dim_seller ds
  ON ds.seller_id = oi.seller_id
JOIN dw.dim_customer dc
  ON dc.customer_unique_id = c.customer_unique_id
JOIN dw.dim_location dcl
  ON dcl.zip_code_prefix = c.customer_zip_code_prefix
JOIN dw.dim_location dsl
  ON dsl.zip_code_prefix = s.seller_zip_code_prefix
JOIN dw.dim_order_status dos
  ON dos.order_status = o.order_status
ORDER BY oi.order_id, oi.order_item_id;


-- ============================================================================
-- 3. FACT_PAYMENTS
-- ============================================================================

INSERT INTO dw.fact_payments (
    order_id,
    payment_sequential,
    customer_key,
    customer_location_key,
    order_status_key,
    purchase_date_key,
    payment_type,
    payment_installments,
    payment_value
)
SELECT
    p.order_id,
    p.payment_sequential,
    dc.customer_key,
    dl.location_key,
    dos.order_status_key,
    TO_CHAR(o.order_purchase_timestamp::date, 'YYYYMMDD')::integer,
    p.payment_type,
    p.payment_installments,
    p.payment_value
FROM olist.order_payments p
JOIN olist.orders o
  ON o.order_id = p.order_id
JOIN olist.customers c
  ON c.customer_id = o.customer_id
JOIN dw.dim_customer dc
  ON dc.customer_unique_id = c.customer_unique_id
JOIN dw.dim_location dl
  ON dl.zip_code_prefix = c.customer_zip_code_prefix
JOIN dw.dim_order_status dos
  ON dos.order_status = o.order_status
ORDER BY p.order_id, p.payment_sequential;


-- ============================================================================
-- 4. FACT_REVIEWS
-- ============================================================================

INSERT INTO dw.fact_reviews (
    review_id,
    order_id,
    customer_key,
    customer_location_key,
    order_status_key,
    purchase_date_key,
    review_creation_date_key,
    review_answer_date_key,
    review_score,
    review_creation_date,
    review_answer_timestamp,
    review_comment_title,
    review_comment_message,
    has_title,
    has_message
)
SELECT
    r.review_id,
    r.order_id,
    dc.customer_key,
    dl.location_key,
    dos.order_status_key,
    TO_CHAR(o.order_purchase_timestamp::date, 'YYYYMMDD')::integer,
    TO_CHAR(r.review_creation_date::date, 'YYYYMMDD')::integer,
    TO_CHAR(r.review_answer_timestamp::date, 'YYYYMMDD')::integer,
    r.review_score,
    r.review_creation_date,
    r.review_answer_timestamp,
    r.review_comment_title,
    r.review_comment_message,
    r.review_comment_title IS NOT NULL,
    r.review_comment_message IS NOT NULL
FROM olist.order_reviews r
JOIN olist.orders o
  ON o.order_id = r.order_id
JOIN olist.customers c
  ON c.customer_id = o.customer_id
JOIN dw.dim_customer dc
  ON dc.customer_unique_id = c.customer_unique_id
JOIN dw.dim_location dl
  ON dl.zip_code_prefix = c.customer_zip_code_prefix
JOIN dw.dim_order_status dos
  ON dos.order_status = o.order_status
ORDER BY r.order_id, r.review_id;


-- ============================================================================
-- 5. POST-LOAD ASSERTIONS
-- ============================================================================

DO $$
DECLARE
    source_count bigint;
    warehouse_count bigint;
    duplicate_count bigint;
BEGIN
    -- fact_orders
    SELECT COUNT(*) INTO source_count FROM olist.orders;
    SELECT COUNT(*) INTO warehouse_count FROM dw.fact_orders;

    IF source_count <> warehouse_count THEN
        RAISE EXCEPTION
            'fact_orders row-count mismatch: source %, warehouse %',
            source_count, warehouse_count;
    END IF;

    SELECT COUNT(*)
    INTO duplicate_count
    FROM (
        SELECT order_id
        FROM dw.fact_orders
        GROUP BY order_id
        HAVING COUNT(*) > 1
    ) q;

    IF duplicate_count <> 0 THEN
        RAISE EXCEPTION 'fact_orders contains duplicate order_id values';
    END IF;

    -- fact_order_items
    SELECT COUNT(*) INTO source_count FROM olist.order_items;
    SELECT COUNT(*) INTO warehouse_count FROM dw.fact_order_items;

    IF source_count <> warehouse_count THEN
        RAISE EXCEPTION
            'fact_order_items row-count mismatch: source %, warehouse %',
            source_count, warehouse_count;
    END IF;

    SELECT COUNT(*)
    INTO duplicate_count
    FROM (
        SELECT order_id, order_item_id
        FROM dw.fact_order_items
        GROUP BY order_id, order_item_id
        HAVING COUNT(*) > 1
    ) q;

    IF duplicate_count <> 0 THEN
        RAISE EXCEPTION
            'fact_order_items contains duplicate grain values';
    END IF;

    -- fact_payments
    SELECT COUNT(*) INTO source_count FROM olist.order_payments;
    SELECT COUNT(*) INTO warehouse_count FROM dw.fact_payments;

    IF source_count <> warehouse_count THEN
        RAISE EXCEPTION
            'fact_payments row-count mismatch: source %, warehouse %',
            source_count, warehouse_count;
    END IF;

    SELECT COUNT(*)
    INTO duplicate_count
    FROM (
        SELECT order_id, payment_sequential
        FROM dw.fact_payments
        GROUP BY order_id, payment_sequential
        HAVING COUNT(*) > 1
    ) q;

    IF duplicate_count <> 0 THEN
        RAISE EXCEPTION
            'fact_payments contains duplicate grain values';
    END IF;

    -- fact_reviews
    SELECT COUNT(*) INTO source_count FROM olist.order_reviews;
    SELECT COUNT(*) INTO warehouse_count FROM dw.fact_reviews;

    IF source_count <> warehouse_count THEN
        RAISE EXCEPTION
            'fact_reviews row-count mismatch: source %, warehouse %',
            source_count, warehouse_count;
    END IF;

    SELECT COUNT(*)
    INTO duplicate_count
    FROM (
        SELECT review_id, order_id
        FROM dw.fact_reviews
        GROUP BY review_id, order_id
        HAVING COUNT(*) > 1
    ) q;

    IF duplicate_count <> 0 THEN
        RAISE EXCEPTION
            'fact_reviews contains duplicate grain values';
    END IF;
END $$;

COMMIT;


-- ============================================================================
-- 6. HUMAN-READABLE VALIDATION OUTPUT
-- ============================================================================

-- Fact row counts.
SELECT 'fact_orders' AS fact_table, COUNT(*) AS rows
FROM dw.fact_orders
UNION ALL
SELECT 'fact_order_items', COUNT(*) FROM dw.fact_order_items
UNION ALL
SELECT 'fact_payments', COUNT(*) FROM dw.fact_payments
UNION ALL
SELECT 'fact_reviews', COUNT(*) FROM dw.fact_reviews
ORDER BY fact_table;


-- Source vs warehouse reconciliation.
SELECT
    'orders' AS entity,
    (SELECT COUNT(*) FROM olist.orders) AS source_rows,
    (SELECT COUNT(*) FROM dw.fact_orders) AS warehouse_rows,
    (SELECT COUNT(*) FROM olist.orders)
      - (SELECT COUNT(*) FROM dw.fact_orders) AS difference
UNION ALL
SELECT
    'order_items',
    (SELECT COUNT(*) FROM olist.order_items),
    (SELECT COUNT(*) FROM dw.fact_order_items),
    (SELECT COUNT(*) FROM olist.order_items)
      - (SELECT COUNT(*) FROM dw.fact_order_items)
UNION ALL
SELECT
    'payments',
    (SELECT COUNT(*) FROM olist.order_payments),
    (SELECT COUNT(*) FROM dw.fact_payments),
    (SELECT COUNT(*) FROM olist.order_payments)
      - (SELECT COUNT(*) FROM dw.fact_payments)
UNION ALL
SELECT
    'reviews',
    (SELECT COUNT(*) FROM olist.order_reviews),
    (SELECT COUNT(*) FROM dw.fact_reviews),
    (SELECT COUNT(*) FROM olist.order_reviews)
      - (SELECT COUNT(*) FROM dw.fact_reviews)
ORDER BY entity;


-- Orders: lifecycle coverage and derived delivery measures.
SELECT
    COUNT(*) AS orders,
    COUNT(*) FILTER (WHERE order_approved_at IS NULL)
        AS missing_approved_timestamp,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL)
        AS missing_carrier_timestamp,
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL)
        AS missing_customer_delivery_timestamp,
    COUNT(*) FILTER (WHERE delivery_days IS NOT NULL)
        AS orders_with_delivery_days,
    COUNT(*) FILTER (WHERE is_late_delivery IS TRUE)
        AS late_orders,
    COUNT(*) FILTER (WHERE is_late_delivery IS FALSE)
        AS on_time_or_early_orders
FROM dw.fact_orders;


-- Confirm that the known 2020 shipping-limit anomalies were preserved.
SELECT
    order_id,
    order_item_id,
    shipping_limit_date
FROM dw.fact_order_items
WHERE shipping_limit_date >= TIMESTAMP '2019-01-01'
ORDER BY shipping_limit_date, order_id, order_item_id;


-- Geography fallback usage in each fact.
SELECT
    'fact_orders.customer' AS relationship,
    COUNT(*) AS fact_rows_using_fallback
FROM dw.fact_orders f
JOIN dw.dim_location l
  ON l.location_key = f.customer_location_key
WHERE l.geolocation_observation_count = 0

UNION ALL

SELECT
    'fact_order_items.customer',
    COUNT(*)
FROM dw.fact_order_items f
JOIN dw.dim_location l
  ON l.location_key = f.customer_location_key
WHERE l.geolocation_observation_count = 0

UNION ALL

SELECT
    'fact_order_items.seller',
    COUNT(*)
FROM dw.fact_order_items f
JOIN dw.dim_location l
  ON l.location_key = f.seller_location_key
WHERE l.geolocation_observation_count = 0

UNION ALL

SELECT
    'fact_payments.customer',
    COUNT(*)
FROM dw.fact_payments f
JOIN dw.dim_location l
  ON l.location_key = f.customer_location_key
WHERE l.geolocation_observation_count = 0

UNION ALL

SELECT
    'fact_reviews.customer',
    COUNT(*)
FROM dw.fact_reviews f
JOIN dw.dim_location l
  ON l.location_key = f.customer_location_key
WHERE l.geolocation_observation_count = 0

ORDER BY relationship;


-- Financial reconciliation: these must match source exactly.
SELECT
    (SELECT SUM(price) FROM olist.order_items) AS source_price,
    (SELECT SUM(price) FROM dw.fact_order_items) AS warehouse_price,
    (SELECT SUM(freight_value) FROM olist.order_items) AS source_freight,
    (SELECT SUM(freight_value) FROM dw.fact_order_items) AS warehouse_freight;

SELECT
    (SELECT SUM(payment_value) FROM olist.order_payments) AS source_payments,
    (SELECT SUM(payment_value) FROM dw.fact_payments) AS warehouse_payments;


-- Review preservation.
SELECT
    COUNT(*) AS review_rows,
    COUNT(DISTINCT review_id) AS distinct_review_ids,
    COUNT(DISTINCT order_id) AS reviewed_orders,
    COUNT(*) - COUNT(DISTINCT order_id) AS rows_above_one_per_order
FROM dw.fact_reviews;
