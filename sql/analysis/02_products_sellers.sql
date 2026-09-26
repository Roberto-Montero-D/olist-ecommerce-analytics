/*
===============================================================================
Olist E-Commerce Analytics
File: sql/analysis/02_products_sellers.sql
Purpose: Product-category performance, seller performance, and revenue
         concentration analysis
===============================================================================

ANALYTICAL PERIOD
-----------------
Comparable business-performance analysis uses:

    2017-01-01 <= order_purchase_timestamp < 2018-09-01

Only delivered orders are included in revenue and sales-volume metrics.

The raw source contains records outside this period, but September 2016 through
December 2016 is sparse/discontinuous and September-October 2018 does not
provide comparable delivered-order coverage.

METRIC DEFINITIONS
------------------
Product revenue:
    Sum of order_items.price for delivered orders. Freight is excluded.

Orders:
    Number of distinct delivered orders associated with a category or seller.

Items sold:
    Number of order-item rows associated with delivered orders.

Average item price:
    Product revenue / items sold.

Items per order:
    Number of seller items sold / number of delivered orders containing that
    seller. This is a seller-level metric, not marketplace-wide basket size.

Seller revenue per order:
    Seller product revenue / number of delivered orders containing that seller.
    This should not be interpreted as marketplace average order value because
    a marketplace order can contain products from multiple sellers.

Revenue share:
    Percentage of total delivered product revenue attributable to a category
    or seller.

Cumulative revenue share:
    Running percentage of total product revenue after entities are ordered
    from highest to lowest product revenue.

IMPORTANT MODELING NOTES
------------------------
- Product categories are stored in Portuguese in the products table.
- category_translation is incomplete, so category translation uses a LEFT JOIN.
- COALESCE preserves untranslated and missing categories instead of dropping
  them from the analysis.
- Revenue ranking measures sales value, not profitability. The dataset does
  not contain seller costs or profit margins.
- Seller revenue should not be interpreted as an overall seller-quality score.
  High revenue can result from sales volume, higher item prices, or both.

===============================================================================
*/


-- ============================================================================
-- 1. PRODUCT CATEGORY PERFORMANCE
-- ============================================================================

-- Compare product categories by delivered-order participation, unit volume,
-- product revenue, and average item price.
--
-- Category labels use the English translation when available, fall back to
-- the original Portuguese category when no translation exists, and use
-- 'unknown' when the product itself has no category.

WITH category_metrics AS (
    SELECT
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        ) AS category,
        COUNT(DISTINCT o.order_id) AS orders,
        COUNT(*) AS items_sold,
        SUM(oi.price) AS product_revenue
    FROM olist.orders AS o
    JOIN olist.order_items AS oi
        ON o.order_id = oi.order_id
    JOIN olist.products AS p
        ON oi.product_id = p.product_id
    LEFT JOIN olist.category_translation AS ct
        ON p.product_category_name = ct.product_category_name
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= DATE '2017-01-01'
      AND o.order_purchase_timestamp <  DATE '2018-09-01'
    GROUP BY category
),

category_kpis AS (
    SELECT
        category,
        orders,
        items_sold,
        product_revenue,
        product_revenue
            / NULLIF(items_sold, 0) AS average_item_price
    FROM category_metrics
)

SELECT
    category,
    orders,
    items_sold,
    ROUND(product_revenue, 2) AS product_revenue,
    ROUND(average_item_price, 2) AS average_item_price,

    RANK() OVER (
        ORDER BY product_revenue DESC
    ) AS revenue_rank,

    RANK() OVER (
        ORDER BY items_sold DESC
    ) AS volume_rank,

    RANK() OVER (
        ORDER BY average_item_price DESC
    ) AS average_item_price_rank,

    ROUND(
        product_revenue
        / NULLIF(SUM(product_revenue) OVER (), 0)
        * 100,
        2
    ) AS revenue_share_percentage,

    ROUND(
        SUM(product_revenue) OVER (
            ORDER BY product_revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )
        / NULLIF(SUM(product_revenue) OVER (), 0)
        * 100,
        2
    ) AS cumulative_revenue_share_percentage

FROM category_kpis
ORDER BY product_revenue DESC
LIMIT 15;


-- ============================================================================
-- 2. TOP SELLERS BY PRODUCT REVENUE
-- ============================================================================

-- Compare sellers across multiple dimensions rather than treating revenue
-- ranking as a general measure of seller quality.
--
-- Rankings are calculated across the complete active-seller population before
-- the final result is restricted to the 15 highest-revenue sellers.

WITH seller_metrics AS (
    SELECT
        s.seller_id,
        s.seller_city,
        s.seller_state,
        COUNT(DISTINCT o.order_id) AS orders,
        COUNT(*) AS items_sold,
        SUM(oi.price) AS product_revenue,
        SUM(oi.price)
            / NULLIF(COUNT(*), 0) AS average_item_price
    FROM olist.orders AS o
    JOIN olist.order_items AS oi
        ON o.order_id = oi.order_id
    JOIN olist.sellers AS s
        ON oi.seller_id = s.seller_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= DATE '2017-01-01'
      AND o.order_purchase_timestamp <  DATE '2018-09-01'
    GROUP BY
        s.seller_id,
        s.seller_city,
        s.seller_state
),

seller_rankings AS (
    SELECT
        *,
        RANK() OVER (
            ORDER BY product_revenue DESC
        ) AS revenue_rank,

        RANK() OVER (
            ORDER BY orders DESC
        ) AS order_rank,

        RANK() OVER (
            ORDER BY items_sold DESC
        ) AS volume_rank,

        RANK() OVER (
            ORDER BY average_item_price DESC
        ) AS average_item_price_rank,

        product_revenue
            / NULLIF(SUM(product_revenue) OVER (), 0)
            * 100 AS revenue_share_percentage

    FROM seller_metrics
)

SELECT
    seller_id,
    seller_city,
    seller_state,
    orders,
    items_sold,
    ROUND(product_revenue, 2) AS product_revenue,
    ROUND(average_item_price, 2) AS average_item_price,

    ROUND(
        items_sold::NUMERIC
        / NULLIF(orders, 0),
        2
    ) AS items_per_order,

    ROUND(
        product_revenue
        / NULLIF(orders, 0),
        2
    ) AS seller_revenue_per_order,

    ROUND(
        revenue_share_percentage,
        2
    ) AS revenue_share_percentage,

    revenue_rank,
    order_rank,
    volume_rank,
    average_item_price_rank

FROM seller_rankings
ORDER BY product_revenue DESC
LIMIT 15;


-- ============================================================================
-- 3. SELLER REVENUE CONCENTRATION
-- ============================================================================

-- Measure how concentrated marketplace product revenue is across active
-- sellers.
--
-- Sellers are ordered from highest to lowest product revenue. The cumulative
-- revenue distribution is then used to determine the minimum number of
-- sellers required to account for 25%, 50%, 75%, and 90% of total delivered
-- product revenue.
--
-- ROW_NUMBER() is used instead of RANK() because seller_position represents
-- the actual number of sellers included in the cumulative distribution.

WITH seller_revenue AS (
    SELECT
        oi.seller_id,
        SUM(oi.price) AS product_revenue
    FROM olist.orders AS o
    JOIN olist.order_items AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= DATE '2017-01-01'
      AND o.order_purchase_timestamp <  DATE '2018-09-01'
    GROUP BY oi.seller_id
),

seller_concentration AS (
    SELECT
        seller_id,
        product_revenue,

        ROW_NUMBER() OVER (
            ORDER BY product_revenue DESC
        ) AS seller_position,

        product_revenue
            / NULLIF(SUM(product_revenue) OVER (), 0)
            * 100 AS revenue_share_percentage,

        SUM(product_revenue) OVER (
            ORDER BY product_revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )
            / NULLIF(SUM(product_revenue) OVER (), 0)
            * 100 AS cumulative_revenue_share_percentage

    FROM seller_revenue
)

SELECT
    COUNT(*) AS total_active_sellers,

    MIN(seller_position) FILTER (
        WHERE cumulative_revenue_share_percentage >= 25
    ) AS sellers_for_25_percent_revenue,

    MIN(seller_position) FILTER (
        WHERE cumulative_revenue_share_percentage >= 50
    ) AS sellers_for_50_percent_revenue,

    MIN(seller_position) FILTER (
        WHERE cumulative_revenue_share_percentage >= 75
    ) AS sellers_for_75_percent_revenue,

    MIN(seller_position) FILTER (
        WHERE cumulative_revenue_share_percentage >= 90
    ) AS sellers_for_90_percent_revenue

FROM seller_concentration;