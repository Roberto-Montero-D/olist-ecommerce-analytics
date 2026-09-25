/*
===============================================================================
Olist E-Commerce Analytics
File: sql/analysis/01_orders_revenue.sql
Purpose: Orders, revenue, temporal coverage, and monthly KPI analysis
===============================================================================

ANALYTICAL PERIOD
-----------------
The source dataset spans 2016-09-04 through 2018-10-17.

However, temporal coverage is sparse outside the period 2017-01 through
2018-08:

- 2016 contains sparse and discontinuous observations.
- September and October 2018 contain only a small number of non-delivered
  orders.

Therefore, comparable monthly business-performance analysis uses:

    2017-01-01 <= order_purchase_timestamp < 2018-09-01

All source records remain preserved in the source schema. The date restriction
applies only to analyses requiring comparable monthly coverage.

METRIC DEFINITIONS
------------------
Product revenue:
    Sum of order_items.price for delivered orders.
    Freight is excluded.

Freight charged:
    Sum of order_items.freight_value for delivered orders.

Items sold:
    Number of order-item rows associated with delivered orders.

Average order value (AOV):
    Product revenue / number of delivered orders.
    This represents average merchandise value per delivered order and
    excludes freight.

===============================================================================
*/


-- ============================================================================
-- 1. ORDER STATUS DISTRIBUTION
-- ============================================================================

SELECT
    order_status,
    COUNT(*) AS order_count,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    ) AS percentage_of_total
FROM olist.orders
GROUP BY order_status
ORDER BY order_count DESC;


-- ============================================================================
-- 2. SOURCE TEMPORAL COVERAGE
-- ============================================================================

-- Determine the full purchase timestamp range available in the source data.

SELECT
    MIN(order_purchase_timestamp) AS first_purchase,
    MAX(order_purchase_timestamp) AS last_purchase
FROM olist.orders;


-- Inspect order volume and status across the full source timeline.
-- This query was used to identify sparse/incomplete periods at the
-- beginning and end of the dataset.

SELECT
    TO_CHAR(
        DATE_TRUNC('month', order_purchase_timestamp),
        'YYYY-MM'
    ) AS month,
    order_status,
    COUNT(*) AS order_count
FROM olist.orders
GROUP BY month, order_status
ORDER BY month, order_status;


-- Inspect the earliest source records.

SELECT
    order_id,
    order_status,
    order_purchase_timestamp
FROM olist.orders
ORDER BY order_purchase_timestamp ASC
LIMIT 20;


-- Inspect the latest source records.

SELECT
    order_id,
    order_status,
    order_purchase_timestamp
FROM olist.orders
ORDER BY order_purchase_timestamp DESC
LIMIT 20;


-- ============================================================================
-- 3. MONTHLY DELIVERED-ORDER METRICS
-- ============================================================================

-- Full-source view.
-- Retained for data exploration and comparison with the core analytical
-- period. Sparse edge periods should not be interpreted as comparable
-- monthly business performance.

SELECT
    TO_CHAR(
        DATE_TRUNC('month', o.order_purchase_timestamp),
        'YYYY-MM'
    ) AS month,
    COUNT(DISTINCT o.order_id) AS order_count,
    COUNT(*) AS items_sold,
    ROUND(SUM(oi.price), 2) AS product_revenue,
    ROUND(SUM(oi.freight_value), 2) AS freight_charged
FROM olist.orders AS o
JOIN olist.order_items AS oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY month
ORDER BY month;


-- ============================================================================
-- 4. CORE MONTHLY KPI ANALYSIS
-- ============================================================================

-- Restrict monthly business-performance comparisons to the continuous
-- analytical period: January 2017 through August 2018.

WITH monthly_metrics AS (
    SELECT
        TO_CHAR(
            DATE_TRUNC('month', o.order_purchase_timestamp),
            'YYYY-MM'
        ) AS month,
        COUNT(DISTINCT o.order_id) AS order_count,
        COUNT(*) AS items_sold,
        SUM(oi.price) AS product_revenue,
        SUM(oi.freight_value) AS freight_charged
    FROM olist.orders AS o
    JOIN olist.order_items AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= DATE '2017-01-01'
      AND o.order_purchase_timestamp <  DATE '2018-09-01'
    GROUP BY month
),

monthly_with_previous AS (
    SELECT
        *,
        LAG(order_count) OVER (
            ORDER BY month
        ) AS previous_order_count,
        LAG(product_revenue) OVER (
            ORDER BY month
        ) AS previous_product_revenue
    FROM monthly_metrics
)

SELECT
    month,
    order_count,
    items_sold,
    ROUND(product_revenue, 2) AS product_revenue,
    ROUND(freight_charged, 2) AS freight_charged,

    ROUND(
        product_revenue / NULLIF(order_count, 0),
        2
    ) AS average_order_value,

    ROUND(
        (order_count - previous_order_count)::NUMERIC
        / NULLIF(previous_order_count, 0) * 100,
        2
    ) AS month_over_month_order_growth_percentage,

    ROUND(
        (product_revenue - previous_product_revenue)
        / NULLIF(previous_product_revenue, 0) * 100,
        2
    ) AS month_over_month_revenue_growth_percentage

FROM monthly_with_previous
ORDER BY month;