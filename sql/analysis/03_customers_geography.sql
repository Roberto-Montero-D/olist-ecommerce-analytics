/*
===============================================================================
Olist E-Commerce Analytics
File: sql/analysis/03_customers_geography.sql
Purpose: Customer distribution, geographic performance, and repeat-purchase
         behavior analysis
===============================================================================

ANALYTICAL PERIOD
-----------------
Comparable business-performance analysis uses:

    2017-01-01 <= order_purchase_timestamp < 2018-09-01

Only delivered orders are included in business-performance and repeat-purchase
metrics.

CUSTOMER IDENTITY
-----------------
Olist contains two different customer identifiers:

customer_id:
    Identifies the customer record associated with a specific order.
    It should not be used to identify repeat customers.

customer_unique_id:
    Represents the persistent customer identity across multiple orders.
    It is therefore used for unique-customer and repeat-purchase analysis.

IMPORTANT MODELING NOTES
------------------------
- Customer geography comes from the customers table.
- Geographic performance is attributed to the customer's state.
- Product revenue is defined as SUM(order_items.price); freight is excluded.
- Revenue analysis requires joining orders to order_items, changing the grain
  from one row per order to one row per order item.
- COUNT(DISTINCT order_id) is therefore required when counting orders after
  joining to order_items.
- Geolocation coordinates are intentionally not joined directly here because
  the raw geolocation table contains multiple rows per ZIP-code prefix and
  would multiply records without prior aggregation.

===============================================================================
*/


-- ============================================================================
-- 1. CUSTOMER GEOGRAPHIC DISTRIBUTION
-- ============================================================================

-- Count distinct persistent customers and delivered orders by customer state.

SELECT
    c.customer_state,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    ROUND(
        COUNT(DISTINCT c.customer_unique_id)::NUMERIC
        / SUM(COUNT(DISTINCT c.customer_unique_id)) OVER ()
        * 100,
        2
    ) AS customer_share_percentage
FROM olist.orders AS o
JOIN olist.customers AS c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= DATE '2017-01-01'
  AND o.order_purchase_timestamp <  DATE '2018-09-01'
GROUP BY c.customer_state
ORDER BY unique_customers DESC;

-- ============================================================================
-- 2. GEOGRAPHIC BUSINESS PERFORMANCE
-- ============================================================================

-- Compare customer states by unique customers, delivered orders, item volume,
-- and product revenue.

WITH state_metrics AS (
    SELECT
        c.customer_state,
        COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
        COUNT(DISTINCT o.order_id) AS delivered_orders,
        COUNT(*) AS items_sold,
        SUM(oi.price) AS product_revenue
    FROM olist.orders AS o
    JOIN olist.customers AS c
        ON o.customer_id = c.customer_id
    JOIN olist.order_items AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= DATE '2017-01-01'
      AND o.order_purchase_timestamp < DATE '2018-09-01'
    GROUP BY c.customer_state
)

SELECT
    customer_state,
    unique_customers,
    delivered_orders,
    items_sold,
    ROUND(product_revenue, 2) AS product_revenue,

    ROUND(
        product_revenue / NULLIF(delivered_orders, 0),
        2
    ) AS product_revenue_per_order,

    ROUND(
        product_revenue / NULLIF(unique_customers, 0),
        2
    ) AS product_revenue_per_customer,

    ROUND(
        product_revenue
        / NULLIF(SUM(product_revenue) OVER (), 0)
        * 100,
        2
    ) AS revenue_share_percentage,

    RANK() OVER (
        ORDER BY product_revenue DESC
    ) AS revenue_rank

FROM state_metrics
ORDER BY product_revenue DESC;

-- ============================================================================
-- 3. REPEAT-CUSTOMER BEHAVIOR
-- ============================================================================

-- Aggregate delivered purchasing activity at the persistent-customer level.
-- customer_unique_id is required because customer_id is order-specific.

WITH customer_activity AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS delivered_orders,
        MIN(o.order_purchase_timestamp) AS first_purchase,
        MAX(o.order_purchase_timestamp) AS last_purchase
    FROM olist.orders AS o
    JOIN olist.customers AS c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= DATE '2017-01-01'
      AND o.order_purchase_timestamp < DATE '2018-09-01'
    GROUP BY c.customer_unique_id
)

SELECT
    COUNT(*) AS unique_customers,

    COUNT(*) FILTER (
        WHERE delivered_orders = 1
    ) AS one_time_customers,

    COUNT(*) FILTER (
        WHERE delivered_orders > 1
    ) AS repeat_customers,

    ROUND(
        COUNT(*) FILTER (
            WHERE delivered_orders > 1
        )::NUMERIC
        / NULLIF(COUNT(*), 0)
        * 100,
        2
    ) AS repeat_customer_percentage,

    ROUND(
        AVG(delivered_orders),
        2
    ) AS average_orders_per_customer,

    MAX(delivered_orders) AS maximum_orders_per_customer

FROM customer_activity;

-- ============================================================================
-- 4. CUSTOMER PURCHASE-FREQUENCY DISTRIBUTION
-- ============================================================================

-- Show how the customer population is distributed by number of delivered
-- orders during the analytical period.

WITH customer_activity AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS delivered_orders
    FROM olist.orders AS o
    JOIN olist.customers AS c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= DATE '2017-01-01'
      AND o.order_purchase_timestamp < DATE '2018-09-01'
    GROUP BY c.customer_unique_id
),

frequency_distribution AS (
    SELECT
        delivered_orders,
        COUNT(*) AS customers
    FROM customer_activity
    GROUP BY delivered_orders
)

SELECT
    delivered_orders,
    customers,

    ROUND(
        customers::NUMERIC
        / SUM(customers) OVER ()
        * 100,
        2
    ) AS customer_percentage

FROM frequency_distribution
ORDER BY delivered_orders;