/*
===============================================================================
Olist E-Commerce Analytics
File: sql/analysis/04_delivery_satisfaction.sql
Purpose: Analyze delivery performance and its relationship with customer
         satisfaction
===============================================================================

ANALYTICAL PERIOD
-----------------
Comparable business-performance analysis uses:

    2017-01-01 <= order_purchase_timestamp < 2018-09-01

Only delivered orders with a recorded customer delivery timestamp are included
in delivery-performance calculations.

METRIC DEFINITIONS
------------------
Delivery time:
    Time between order purchase and delivery to the customer.

Estimated delivery margin:
    Difference between actual delivery and the estimated delivery date.

Delivery status:
    On time / early:
        actual delivery <= estimated delivery date

    Late:
        actual delivery > estimated delivery date

Review score:
    Customer rating from 1 to 5.

IMPORTANT MODELING NOTES
------------------------
- Delivery performance is measured only for delivered orders with known
  delivery timestamps.
- Review data is not strictly one row per order. Some orders have multiple
  review records, so reviews must be aggregated to order level before joining
  them to orders.
- Missing reviews are preserved when appropriate instead of silently removing
  orders from delivery analysis.
- Associations between delivery performance and review score are descriptive.
  They do not establish that delivery performance caused the review score.

===============================================================================
*/


-- ============================================================================
-- 1. OVERALL DELIVERY PERFORMANCE
-- ============================================================================

-- Summarize delivery duration and estimated-delivery performance.

WITH delivery_metrics AS (
    SELECT
        order_id,

        EXTRACT(
            EPOCH FROM (
                order_delivered_customer_date - order_purchase_timestamp
            )
        ) / 86400.0 AS delivery_days,

        EXTRACT(
            EPOCH FROM (
                order_delivered_customer_date - order_estimated_delivery_date
            )
        ) / 86400.0 AS days_relative_to_estimate

    FROM olist.orders
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp >= DATE '2017-01-01'
      AND order_purchase_timestamp <  DATE '2018-09-01'
      AND order_delivered_customer_date IS NOT NULL
)

SELECT
    COUNT(*) AS delivered_orders,

    ROUND(
        AVG(delivery_days),
        2
    ) AS average_delivery_days,

    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY delivery_days
        )::NUMERIC,
        2
    ) AS median_delivery_days,

    ROUND(
        PERCENTILE_CONT(0.9) WITHIN GROUP (
            ORDER BY delivery_days
        )::NUMERIC,
        2
    ) AS p90_delivery_days,

    COUNT(*) FILTER (
        WHERE days_relative_to_estimate <= 0
    ) AS on_time_or_early_orders,

    COUNT(*) FILTER (
        WHERE days_relative_to_estimate > 0
    ) AS late_orders,

    ROUND(
        COUNT(*) FILTER (
            WHERE days_relative_to_estimate > 0
        )::NUMERIC
        / NULLIF(COUNT(*), 0)
        * 100,
        2
    ) AS late_delivery_percentage

FROM delivery_metrics;


-- ============================================================================
-- 2. DELIVERY PERFORMANCE BY CUSTOMER STATE
-- ============================================================================

-- Compare delivery speed and lateness across customer states.
--
-- State-level results should be interpreted together with order volume because
-- estimates based on small numbers of orders are less stable.

WITH state_delivery AS (
    SELECT
        c.customer_state,
        o.order_id,

        EXTRACT(
            EPOCH FROM (
                o.order_delivered_customer_date
                - o.order_purchase_timestamp
            )
        ) / 86400.0 AS delivery_days,

        CASE
            WHEN o.order_delivered_customer_date
                 > o.order_estimated_delivery_date
            THEN 1
            ELSE 0
        END AS is_late

    FROM olist.orders AS o
    JOIN olist.customers AS c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= DATE '2017-01-01'
      AND o.order_purchase_timestamp <  DATE '2018-09-01'
      AND o.order_delivered_customer_date IS NOT NULL
)

SELECT
    customer_state,
    COUNT(*) AS delivered_orders,

    ROUND(
        AVG(delivery_days),
        2
    ) AS average_delivery_days,

    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY delivery_days
        )::NUMERIC,
        2
    ) AS median_delivery_days,

    ROUND(
        AVG(is_late) * 100,
        2
    ) AS late_delivery_percentage

FROM state_delivery
GROUP BY customer_state
ORDER BY average_delivery_days;


-- ============================================================================
-- 3. REVIEW SCORE DISTRIBUTION
-- ============================================================================

-- Reviews are analyzed at review-record level here because this section
-- describes the distribution of submitted ratings themselves.

SELECT
    review_score,
    COUNT(*) AS reviews,

    ROUND(
        COUNT(*)::NUMERIC
        / SUM(COUNT(*)) OVER ()
        * 100,
        2
    ) AS review_percentage

FROM olist.order_reviews
GROUP BY review_score
ORDER BY review_score;


-- ============================================================================
-- 4. DELIVERY PERFORMANCE VS CUSTOMER SATISFACTION
-- ============================================================================

-- Aggregate reviews to one row per order before joining them to orders.
--
-- AVG(review_score) is used for the small number of orders with multiple
-- review records so that those orders are not duplicated in the analysis.

WITH order_reviews AS (
    SELECT
        order_id,
        AVG(review_score) AS review_score
    FROM olist.order_reviews
    GROUP BY order_id
),

delivery_reviews AS (
    SELECT
        o.order_id,

        CASE
            WHEN o.order_delivered_customer_date
                 > o.order_estimated_delivery_date
            THEN 'late'
            ELSE 'on_time_or_early'
        END AS delivery_status,

        EXTRACT(
            EPOCH FROM (
                o.order_delivered_customer_date
                - o.order_estimated_delivery_date
            )
        ) / 86400.0 AS days_relative_to_estimate,

        r.review_score

    FROM olist.orders AS o
    JOIN order_reviews AS r
        ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= DATE '2017-01-01'
      AND o.order_purchase_timestamp <  DATE '2018-09-01'
      AND o.order_delivered_customer_date IS NOT NULL
)

SELECT
    delivery_status,
    COUNT(*) AS reviewed_orders,

    ROUND(
        AVG(review_score),
        2
    ) AS average_review_score,

    ROUND(
        COUNT(*) FILTER (
            WHERE review_score >= 4
        )::NUMERIC
        / NULLIF(COUNT(*), 0)
        * 100,
        2
    ) AS positive_review_percentage,

    ROUND(
        COUNT(*) FILTER (
            WHERE review_score <= 2
        )::NUMERIC
        / NULLIF(COUNT(*), 0)
        * 100,
        2
    ) AS negative_review_percentage,

    ROUND(
        AVG(days_relative_to_estimate),
        2
    ) AS average_days_relative_to_estimate

FROM delivery_reviews
GROUP BY delivery_status
ORDER BY delivery_status;


-- ============================================================================
-- 5. REVIEW SCORE BY DELIVERY-TIMING BUCKET
-- ============================================================================

-- Move beyond a binary late/on-time classification by grouping orders
-- according to how early or late they arrived relative to the promised date.

WITH order_reviews AS (
    SELECT
        order_id,
        AVG(review_score) AS review_score
    FROM olist.order_reviews
    GROUP BY order_id
),

delivery_reviews AS (
    SELECT
        o.order_id,

        EXTRACT(
            EPOCH FROM (
                o.order_delivered_customer_date
                - o.order_estimated_delivery_date
            )
        ) / 86400.0 AS days_relative_to_estimate,

        r.review_score

    FROM olist.orders AS o
    JOIN order_reviews AS r
        ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= DATE '2017-01-01'
      AND o.order_purchase_timestamp <  DATE '2018-09-01'
      AND o.order_delivered_customer_date IS NOT NULL
),

delivery_buckets AS (
    SELECT
        *,
        CASE
            WHEN days_relative_to_estimate <= -7
                THEN '01_7+ days early'

            WHEN days_relative_to_estimate <= 0
                THEN '02_0-7 days early'

            WHEN days_relative_to_estimate <= 3
                THEN '03_1-3 days late'

            WHEN days_relative_to_estimate <= 7
                THEN '04_4-7 days late'

            ELSE '05_8+ days late'
        END AS delivery_timing_bucket

    FROM delivery_reviews
)

SELECT
    delivery_timing_bucket,
    COUNT(*) AS reviewed_orders,

    ROUND(
        AVG(review_score),
        2
    ) AS average_review_score,

    ROUND(
        COUNT(*) FILTER (
            WHERE review_score <= 2
        )::NUMERIC
        / NULLIF(COUNT(*), 0)
        * 100,
        2
    ) AS negative_review_percentage

FROM delivery_buckets
GROUP BY delivery_timing_bucket
ORDER BY delivery_timing_bucket;