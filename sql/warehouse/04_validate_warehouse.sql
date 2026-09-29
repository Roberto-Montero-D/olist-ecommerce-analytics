/*
===============================================================================
Olist E-Commerce Analytics
File: sql/warehouse/04_validate_warehouse.sql
Phase: Phase 2.3 — Final Warehouse Validation

Purpose
-------
Final read-only validation of the populated `dw` dimensional warehouse.

Checks
------
1. Row-count reconciliation
2. Natural-grain uniqueness
3. Foreign-key / dimension resolution
4. Date-key integrity
5. Derived order-delivery rules
6. Financial reconciliation
7. Geography coverage and fallback behavior
8. Review-event preservation
9. Analytical smoke tests

This script does not modify source or warehouse data.
===============================================================================
*/


-- ============================================================================
-- 1. ROW-COUNT RECONCILIATION
-- ============================================================================

SELECT
    'fact_orders' AS object_name,
    (SELECT COUNT(*) FROM olist.orders) AS expected_rows,
    (SELECT COUNT(*) FROM dw.fact_orders) AS actual_rows,
    (SELECT COUNT(*) FROM dw.fact_orders)
      - (SELECT COUNT(*) FROM olist.orders) AS difference

UNION ALL

SELECT
    'fact_order_items',
    (SELECT COUNT(*) FROM olist.order_items),
    (SELECT COUNT(*) FROM dw.fact_order_items),
    (SELECT COUNT(*) FROM dw.fact_order_items)
      - (SELECT COUNT(*) FROM olist.order_items)

UNION ALL

SELECT
    'fact_payments',
    (SELECT COUNT(*) FROM olist.order_payments),
    (SELECT COUNT(*) FROM dw.fact_payments),
    (SELECT COUNT(*) FROM dw.fact_payments)
      - (SELECT COUNT(*) FROM olist.order_payments)

UNION ALL

SELECT
    'fact_reviews',
    (SELECT COUNT(*) FROM olist.order_reviews),
    (SELECT COUNT(*) FROM dw.fact_reviews),
    (SELECT COUNT(*) FROM dw.fact_reviews)
      - (SELECT COUNT(*) FROM olist.order_reviews)

UNION ALL

SELECT
    'dim_customer',
    (SELECT COUNT(DISTINCT customer_unique_id) FROM olist.customers),
    (SELECT COUNT(*) FROM dw.dim_customer),
    (SELECT COUNT(*) FROM dw.dim_customer)
      - (SELECT COUNT(DISTINCT customer_unique_id) FROM olist.customers)

UNION ALL

SELECT
    'dim_product',
    (SELECT COUNT(*) FROM olist.products),
    (SELECT COUNT(*) FROM dw.dim_product),
    (SELECT COUNT(*) FROM dw.dim_product)
      - (SELECT COUNT(*) FROM olist.products)

UNION ALL

SELECT
    'dim_seller',
    (SELECT COUNT(*) FROM olist.sellers),
    (SELECT COUNT(*) FROM dw.dim_seller),
    (SELECT COUNT(*) FROM dw.dim_seller)
      - (SELECT COUNT(*) FROM olist.sellers)

UNION ALL

SELECT
    'dim_order_status',
    (SELECT COUNT(DISTINCT order_status) FROM olist.orders),
    (SELECT COUNT(*) FROM dw.dim_order_status),
    (SELECT COUNT(*) FROM dw.dim_order_status)
      - (SELECT COUNT(DISTINCT order_status) FROM olist.orders)

ORDER BY object_name;


-- ============================================================================
-- 2. NATURAL-GRAIN UNIQUENESS
-- ============================================================================

SELECT
    'fact_orders(order_id)' AS grain,
    COUNT(*) AS duplicate_groups
FROM (
    SELECT order_id
    FROM dw.fact_orders
    GROUP BY order_id
    HAVING COUNT(*) > 1
) q

UNION ALL

SELECT
    'fact_order_items(order_id, order_item_id)',
    COUNT(*)
FROM (
    SELECT order_id, order_item_id
    FROM dw.fact_order_items
    GROUP BY order_id, order_item_id
    HAVING COUNT(*) > 1
) q

UNION ALL

SELECT
    'fact_payments(order_id, payment_sequential)',
    COUNT(*)
FROM (
    SELECT order_id, payment_sequential
    FROM dw.fact_payments
    GROUP BY order_id, payment_sequential
    HAVING COUNT(*) > 1
) q

UNION ALL

SELECT
    'fact_reviews(review_id, order_id)',
    COUNT(*)
FROM (
    SELECT review_id, order_id
    FROM dw.fact_reviews
    GROUP BY review_id, order_id
    HAVING COUNT(*) > 1
) q

UNION ALL

SELECT
    'dim_customer(customer_unique_id)',
    COUNT(*)
FROM (
    SELECT customer_unique_id
    FROM dw.dim_customer
    GROUP BY customer_unique_id
    HAVING COUNT(*) > 1
) q

UNION ALL

SELECT
    'dim_location(zip_code_prefix)',
    COUNT(*)
FROM (
    SELECT zip_code_prefix
    FROM dw.dim_location
    GROUP BY zip_code_prefix
    HAVING COUNT(*) > 1
) q

UNION ALL

SELECT
    'dim_product(product_id)',
    COUNT(*)
FROM (
    SELECT product_id
    FROM dw.dim_product
    GROUP BY product_id
    HAVING COUNT(*) > 1
) q

UNION ALL

SELECT
    'dim_seller(seller_id)',
    COUNT(*)
FROM (
    SELECT seller_id
    FROM dw.dim_seller
    GROUP BY seller_id
    HAVING COUNT(*) > 1
) q

UNION ALL

SELECT
    'dim_order_status(order_status)',
    COUNT(*)
FROM (
    SELECT order_status
    FROM dw.dim_order_status
    GROUP BY order_status
    HAVING COUNT(*) > 1
) q

ORDER BY grain;


-- ============================================================================
-- 3. FOREIGN-KEY / DIMENSION RESOLUTION
-- ============================================================================

-- PostgreSQL constraints already protect FK integrity. These explicit checks
-- make the validation output portfolio-readable and independently auditable.

SELECT 'fact_orders.customer_key' AS relationship, COUNT(*) AS orphan_rows
FROM dw.fact_orders f
LEFT JOIN dw.dim_customer d ON d.customer_key = f.customer_key
WHERE d.customer_key IS NULL

UNION ALL
SELECT 'fact_orders.customer_location_key', COUNT(*)
FROM dw.fact_orders f
LEFT JOIN dw.dim_location d ON d.location_key = f.customer_location_key
WHERE f.customer_location_key IS NOT NULL AND d.location_key IS NULL

UNION ALL
SELECT 'fact_orders.order_status_key', COUNT(*)
FROM dw.fact_orders f
LEFT JOIN dw.dim_order_status d ON d.order_status_key = f.order_status_key
WHERE d.order_status_key IS NULL

UNION ALL
SELECT 'fact_order_items.product_key', COUNT(*)
FROM dw.fact_order_items f
LEFT JOIN dw.dim_product d ON d.product_key = f.product_key
WHERE d.product_key IS NULL

UNION ALL
SELECT 'fact_order_items.seller_key', COUNT(*)
FROM dw.fact_order_items f
LEFT JOIN dw.dim_seller d ON d.seller_key = f.seller_key
WHERE d.seller_key IS NULL

UNION ALL
SELECT 'fact_order_items.customer_key', COUNT(*)
FROM dw.fact_order_items f
LEFT JOIN dw.dim_customer d ON d.customer_key = f.customer_key
WHERE d.customer_key IS NULL

UNION ALL
SELECT 'fact_order_items.customer_location_key', COUNT(*)
FROM dw.fact_order_items f
LEFT JOIN dw.dim_location d ON d.location_key = f.customer_location_key
WHERE f.customer_location_key IS NOT NULL AND d.location_key IS NULL

UNION ALL
SELECT 'fact_order_items.seller_location_key', COUNT(*)
FROM dw.fact_order_items f
LEFT JOIN dw.dim_location d ON d.location_key = f.seller_location_key
WHERE f.seller_location_key IS NOT NULL AND d.location_key IS NULL

UNION ALL
SELECT 'fact_order_items.order_status_key', COUNT(*)
FROM dw.fact_order_items f
LEFT JOIN dw.dim_order_status d ON d.order_status_key = f.order_status_key
WHERE d.order_status_key IS NULL

UNION ALL
SELECT 'fact_payments.customer_key', COUNT(*)
FROM dw.fact_payments f
LEFT JOIN dw.dim_customer d ON d.customer_key = f.customer_key
WHERE d.customer_key IS NULL

UNION ALL
SELECT 'fact_payments.customer_location_key', COUNT(*)
FROM dw.fact_payments f
LEFT JOIN dw.dim_location d ON d.location_key = f.customer_location_key
WHERE f.customer_location_key IS NOT NULL AND d.location_key IS NULL

UNION ALL
SELECT 'fact_payments.order_status_key', COUNT(*)
FROM dw.fact_payments f
LEFT JOIN dw.dim_order_status d ON d.order_status_key = f.order_status_key
WHERE d.order_status_key IS NULL

UNION ALL
SELECT 'fact_reviews.customer_key', COUNT(*)
FROM dw.fact_reviews f
LEFT JOIN dw.dim_customer d ON d.customer_key = f.customer_key
WHERE d.customer_key IS NULL

UNION ALL
SELECT 'fact_reviews.customer_location_key', COUNT(*)
FROM dw.fact_reviews f
LEFT JOIN dw.dim_location d ON d.location_key = f.customer_location_key
WHERE f.customer_location_key IS NOT NULL AND d.location_key IS NULL

UNION ALL
SELECT 'fact_reviews.order_status_key', COUNT(*)
FROM dw.fact_reviews f
LEFT JOIN dw.dim_order_status d ON d.order_status_key = f.order_status_key
WHERE d.order_status_key IS NULL

ORDER BY relationship;


-- ============================================================================
-- 4. DATE-KEY INTEGRITY
-- ============================================================================

-- Every populated date key must resolve to dim_date and agree with the date
-- portion of its corresponding timestamp.

WITH checks AS (
    SELECT
        'fact_orders.purchase_date_key' AS relationship,
        COUNT(*) FILTER (
            WHERE d.date_key IS NULL
               OR d.full_date <> f.order_purchase_timestamp::date
        ) AS invalid_rows
    FROM dw.fact_orders f
    LEFT JOIN dw.dim_date d ON d.date_key = f.purchase_date_key

    UNION ALL

    SELECT
        'fact_orders.approved_date_key',
        COUNT(*) FILTER (
            WHERE f.approved_date_key IS NOT NULL
              AND (
                  d.date_key IS NULL
                  OR d.full_date <> f.order_approved_at::date
              )
        )
    FROM dw.fact_orders f
    LEFT JOIN dw.dim_date d ON d.date_key = f.approved_date_key

    UNION ALL

    SELECT
        'fact_orders.carrier_date_key',
        COUNT(*) FILTER (
            WHERE f.carrier_date_key IS NOT NULL
              AND (
                  d.date_key IS NULL
                  OR d.full_date <> f.order_delivered_carrier_date::date
              )
        )
    FROM dw.fact_orders f
    LEFT JOIN dw.dim_date d ON d.date_key = f.carrier_date_key

    UNION ALL

    SELECT
        'fact_orders.delivered_customer_date_key',
        COUNT(*) FILTER (
            WHERE f.delivered_customer_date_key IS NOT NULL
              AND (
                  d.date_key IS NULL
                  OR d.full_date <> f.order_delivered_customer_date::date
              )
        )
    FROM dw.fact_orders f
    LEFT JOIN dw.dim_date d ON d.date_key = f.delivered_customer_date_key

    UNION ALL

    SELECT
        'fact_orders.estimated_delivery_date_key',
        COUNT(*) FILTER (
            WHERE d.date_key IS NULL
               OR d.full_date <> f.order_estimated_delivery_date::date
        )
    FROM dw.fact_orders f
    LEFT JOIN dw.dim_date d ON d.date_key = f.estimated_delivery_date_key

    UNION ALL

    SELECT
        'fact_order_items.purchase_date_key',
        COUNT(*) FILTER (
            WHERE d.date_key IS NULL
        )
    FROM dw.fact_order_items f
    LEFT JOIN dw.dim_date d ON d.date_key = f.purchase_date_key

    UNION ALL

    SELECT
        'fact_order_items.shipping_limit_date_key',
        COUNT(*) FILTER (
            WHERE d.date_key IS NULL
               OR d.full_date <> f.shipping_limit_date::date
        )
    FROM dw.fact_order_items f
    LEFT JOIN dw.dim_date d ON d.date_key = f.shipping_limit_date_key

    UNION ALL

    SELECT
        'fact_payments.purchase_date_key',
        COUNT(*) FILTER (
            WHERE d.date_key IS NULL
        )
    FROM dw.fact_payments f
    LEFT JOIN dw.dim_date d ON d.date_key = f.purchase_date_key

    UNION ALL

    SELECT
        'fact_reviews.purchase_date_key',
        COUNT(*) FILTER (
            WHERE d.date_key IS NULL
        )
    FROM dw.fact_reviews f
    LEFT JOIN dw.dim_date d ON d.date_key = f.purchase_date_key

    UNION ALL

    SELECT
        'fact_reviews.review_creation_date_key',
        COUNT(*) FILTER (
            WHERE d.date_key IS NULL
               OR d.full_date <> f.review_creation_date::date
        )
    FROM dw.fact_reviews f
    LEFT JOIN dw.dim_date d ON d.date_key = f.review_creation_date_key

    UNION ALL

    SELECT
        'fact_reviews.review_answer_date_key',
        COUNT(*) FILTER (
            WHERE d.date_key IS NULL
               OR d.full_date <> f.review_answer_timestamp::date
        )
    FROM dw.fact_reviews f
    LEFT JOIN dw.dim_date d ON d.date_key = f.review_answer_date_key
)
SELECT *
FROM checks
ORDER BY relationship;


-- ============================================================================
-- 5. DERIVED ORDER-DELIVERY RULES
-- ============================================================================

SELECT
    COUNT(*) AS orders,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date IS NULL
          AND (
              delivery_days IS NOT NULL
              OR delivery_delay_days IS NOT NULL
              OR is_late_delivery IS NOT NULL
          )
    ) AS invalid_missing_delivery_derivations,

    COUNT(*) FILTER (
        WHERE order_delivered_customer_date IS NOT NULL
          AND (
              delivery_days IS NULL
              OR delivery_delay_days IS NULL
              OR is_late_delivery IS NULL
          )
    ) AS invalid_present_delivery_derivations,

    COUNT(*) FILTER (
        WHERE order_delivered_customer_date IS NOT NULL
          AND is_late_delivery IS DISTINCT FROM
              (order_delivered_customer_date > order_estimated_delivery_date)
    ) AS invalid_late_flags,

    COUNT(*) FILTER (
        WHERE delivery_days IS NOT NULL
          AND delivery_days <> ROUND(
              (
                  EXTRACT(EPOCH FROM (
                      order_delivered_customer_date - order_purchase_timestamp
                  )) / 86400.0
              )::numeric,
              2
          )
    ) AS invalid_delivery_days,

    COUNT(*) FILTER (
        WHERE delivery_delay_days IS NOT NULL
          AND delivery_delay_days <> ROUND(
              (
                  EXTRACT(EPOCH FROM (
                      order_delivered_customer_date
                      - order_estimated_delivery_date
                  )) / 86400.0
              )::numeric,
              2
          )
    ) AS invalid_delivery_delay_days
FROM dw.fact_orders;


-- Descriptive lifecycle counts (not errors).
SELECT
    COUNT(*) FILTER (WHERE order_approved_at IS NULL)
        AS missing_approved_timestamp,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL)
        AS missing_carrier_timestamp,
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL)
        AS missing_customer_delivery_timestamp,
    COUNT(*) FILTER (WHERE is_late_delivery IS TRUE)
        AS late_orders,
    COUNT(*) FILTER (WHERE is_late_delivery IS FALSE)
        AS on_time_or_early_orders
FROM dw.fact_orders;


-- ============================================================================
-- 6. FINANCIAL RECONCILIATION
-- ============================================================================

SELECT
    (SELECT SUM(price) FROM olist.order_items) AS source_price,
    (SELECT SUM(price) FROM dw.fact_order_items) AS warehouse_price,
    (SELECT SUM(price) FROM dw.fact_order_items)
      - (SELECT SUM(price) FROM olist.order_items) AS price_difference,

    (SELECT SUM(freight_value) FROM olist.order_items) AS source_freight,
    (SELECT SUM(freight_value) FROM dw.fact_order_items) AS warehouse_freight,
    (SELECT SUM(freight_value) FROM dw.fact_order_items)
      - (SELECT SUM(freight_value) FROM olist.order_items) AS freight_difference,

    (SELECT SUM(payment_value) FROM olist.order_payments) AS source_payments,
    (SELECT SUM(payment_value) FROM dw.fact_payments) AS warehouse_payments,
    (SELECT SUM(payment_value) FROM dw.fact_payments)
      - (SELECT SUM(payment_value) FROM olist.order_payments)
        AS payment_difference;


-- ============================================================================
-- 7. GEOGRAPHY COVERAGE
-- ============================================================================

SELECT
    COUNT(*) AS location_members,
    COUNT(*) FILTER (WHERE geolocation_observation_count > 0)
        AS geolocation_members,
    COUNT(*) FILTER (WHERE geolocation_observation_count = 0)
        AS fallback_members,
    COUNT(*) FILTER (
        WHERE geolocation_observation_count > 0 AND is_ambiguous
    ) AS ambiguous_geolocation_members,
    COUNT(*) FILTER (
        WHERE geolocation_observation_count = 0 AND is_ambiguous
    ) AS ambiguous_fallback_members,
    COUNT(*) FILTER (WHERE city IS NULL) AS missing_city,
    COUNT(*) FILTER (WHERE state IS NULL) AS missing_state
FROM dw.dim_location;


SELECT
    'fact_orders.customer' AS relationship,
    COUNT(*) AS fallback_fact_rows
FROM dw.fact_orders f
JOIN dw.dim_location l ON l.location_key = f.customer_location_key
WHERE l.geolocation_observation_count = 0

UNION ALL

SELECT 'fact_order_items.customer', COUNT(*)
FROM dw.fact_order_items f
JOIN dw.dim_location l ON l.location_key = f.customer_location_key
WHERE l.geolocation_observation_count = 0

UNION ALL

SELECT 'fact_order_items.seller', COUNT(*)
FROM dw.fact_order_items f
JOIN dw.dim_location l ON l.location_key = f.seller_location_key
WHERE l.geolocation_observation_count = 0

UNION ALL

SELECT 'fact_payments.customer', COUNT(*)
FROM dw.fact_payments f
JOIN dw.dim_location l ON l.location_key = f.customer_location_key
WHERE l.geolocation_observation_count = 0

UNION ALL

SELECT 'fact_reviews.customer', COUNT(*)
FROM dw.fact_reviews f
JOIN dw.dim_location l ON l.location_key = f.customer_location_key
WHERE l.geolocation_observation_count = 0

ORDER BY relationship;


-- ============================================================================
-- 8. REVIEW-EVENT PRESERVATION
-- ============================================================================

SELECT
    COUNT(*) AS review_rows,
    COUNT(DISTINCT review_id) AS distinct_review_ids,
    COUNT(DISTINCT order_id) AS reviewed_orders,
    COUNT(*) - COUNT(DISTINCT order_id) AS rows_above_one_per_order,
    COUNT(*) FILTER (WHERE review_score NOT BETWEEN 1 AND 5)
        AS invalid_review_scores,
    COUNT(*) FILTER (
        WHERE has_title IS DISTINCT FROM (review_comment_title IS NOT NULL)
    ) AS invalid_has_title_flags,
    COUNT(*) FILTER (
        WHERE has_message IS DISTINCT FROM (review_comment_message IS NOT NULL)
    ) AS invalid_has_message_flags
FROM dw.fact_reviews;


WITH per_order AS (
    SELECT
        order_id,
        COUNT(*) AS review_count,
        COUNT(DISTINCT review_score) AS score_count
    FROM dw.fact_reviews
    GROUP BY order_id
)
SELECT
    COUNT(*) FILTER (WHERE review_count > 1) AS multi_review_orders,
    COUNT(*) FILTER (
        WHERE review_count > 1 AND score_count = 1
    ) AS multi_review_same_score,
    COUNT(*) FILTER (
        WHERE review_count > 1 AND score_count > 1
    ) AS multi_review_different_score,
    MAX(review_count) AS max_reviews_per_order
FROM per_order;


-- ============================================================================
-- 9. ANALYTICAL SMOKE TESTS
-- ============================================================================

-- 9.1 Delivered-order monthly revenue from the warehouse.
-- Grain protection: revenue comes only from the item fact; order counts are
-- distinct because an order may contain multiple item rows.
SELECT
    d.year_month,
    COUNT(DISTINCT fi.order_id) AS delivered_orders,
    COUNT(*) AS item_rows,
    ROUND(SUM(fi.price), 2) AS item_revenue,
    ROUND(SUM(fi.freight_value), 2) AS freight
FROM dw.fact_order_items fi
JOIN dw.dim_order_status s
  ON s.order_status_key = fi.order_status_key
JOIN dw.dim_date d
  ON d.date_key = fi.purchase_date_key
WHERE s.order_status = 'delivered'
  AND d.full_date >= DATE '2017-01-01'
  AND d.full_date <  DATE '2018-09-01'
GROUP BY d.year_month
ORDER BY d.year_month;


-- 9.2 Top product categories by delivered item revenue.
SELECT
    COALESCE(p.product_category_name_english,
             p.product_category_name,
             '[missing category]') AS category,
    ROUND(SUM(fi.price), 2) AS item_revenue,
    COUNT(*) AS item_rows
FROM dw.fact_order_items fi
JOIN dw.dim_product p
  ON p.product_key = fi.product_key
JOIN dw.dim_order_status s
  ON s.order_status_key = fi.order_status_key
JOIN dw.dim_date d
  ON d.date_key = fi.purchase_date_key
WHERE s.order_status = 'delivered'
  AND d.full_date >= DATE '2017-01-01'
  AND d.full_date <  DATE '2018-09-01'
GROUP BY
    COALESCE(p.product_category_name_english,
             p.product_category_name,
             '[missing category]')
ORDER BY item_revenue DESC
LIMIT 10;


-- 9.3 Customer-state order distribution.
-- Use fact_orders, not an item/payment fact, to avoid fan-out.
SELECT
    l.state,
    COUNT(*) AS orders,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS order_share_pct
FROM dw.fact_orders fo
JOIN dw.dim_location l
  ON l.location_key = fo.customer_location_key
JOIN dw.dim_date d
  ON d.date_key = fo.purchase_date_key
WHERE d.full_date >= DATE '2017-01-01'
  AND d.full_date <  DATE '2018-09-01'
GROUP BY l.state
ORDER BY orders DESC
LIMIT 10;


-- 9.4 Delivery/satisfaction relationship without fact-to-fact joining.
-- Both source events are independently reduced to one row per order first,
-- then compared by degenerate order_id only for this analytical smoke test.
-- This is not a warehouse relationship or FK.
WITH delivered AS (
    SELECT
        order_id,
        is_late_delivery,
        delivery_delay_days
    FROM dw.fact_orders fo
    JOIN dw.dim_order_status s
      ON s.order_status_key = fo.order_status_key
    JOIN dw.dim_date d
      ON d.date_key = fo.purchase_date_key
    WHERE s.order_status = 'delivered'
      AND d.full_date >= DATE '2017-01-01'
      AND d.full_date <  DATE '2018-09-01'
      AND fo.order_delivered_customer_date IS NOT NULL
),
review_per_order AS (
    SELECT
        order_id,
        AVG(review_score::numeric) AS avg_review_score
    FROM dw.fact_reviews
    GROUP BY order_id
)
SELECT
    CASE
        WHEN d.is_late_delivery THEN 'late'
        ELSE 'on_time_or_early'
    END AS delivery_group,
    COUNT(*) AS reviewed_orders,
    ROUND(AVG(r.avg_review_score), 2) AS avg_review_score,
    ROUND(AVG(d.delivery_delay_days), 2) AS avg_delivery_delay_days
FROM delivered d
JOIN review_per_order r USING (order_id)
GROUP BY
    CASE
        WHEN d.is_late_delivery THEN 'late'
        ELSE 'on_time_or_early'
    END
ORDER BY delivery_group;
