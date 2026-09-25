-- ============================================================
-- Olist Source Data Validation
-- ============================================================

SET search_path TO olist;

-- ------------------------------------------------------------
-- 1. Row counts
-- ------------------------------------------------------------

SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL
SELECT 'category_translation', COUNT(*) FROM category_translation
UNION ALL
SELECT 'geolocation', COUNT(*) FROM geolocation
ORDER BY table_name;

-- ------------------------------------------------------------
-- 2. Order status distribution
-- ------------------------------------------------------------

SELECT
    order_status,
    COUNT(*) AS order_count
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;

-- ------------------------------------------------------------
-- 3. Orders without item records
-- ------------------------------------------------------------

SELECT
    o.order_status,
    COUNT(*) AS order_count
FROM orders AS o
LEFT JOIN order_items AS oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status
ORDER BY order_count DESC;

-- ------------------------------------------------------------
-- 4. Parent records without children
-- ------------------------------------------------------------

SELECT
    COUNT(*) FILTER (WHERE NOT EXISTS (
        SELECT 1
        FROM order_items AS oi
        WHERE oi.order_id = o.order_id
    )) AS orders_without_items,

    COUNT(*) FILTER (WHERE NOT EXISTS (
        SELECT 1
        FROM order_payments AS op
        WHERE op.order_id = o.order_id
    )) AS orders_without_payments,

    COUNT(*) FILTER (WHERE NOT EXISTS (
        SELECT 1
        FROM order_reviews AS r
        WHERE r.order_id = o.order_id
    )) AS orders_without_reviews

FROM orders AS o;

-- ------------------------------------------------------------
-- 5. Customer identity
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS customer_records,
    COUNT(DISTINCT customer_id) AS distinct_customer_ids,
    COUNT(DISTINCT customer_unique_id) AS distinct_people
FROM customers;

-- ------------------------------------------------------------
-- 6. Review cardinality
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS review_rows,
    COUNT(DISTINCT review_id) AS distinct_review_ids,
    COUNT(DISTINCT order_id) AS distinct_orders_reviewed
FROM order_reviews;

-- ------------------------------------------------------------
-- 7. Important NULL counts
-- ------------------------------------------------------------

SELECT
    COUNT(*) FILTER (WHERE order_approved_at IS NULL)
        AS missing_order_approved_at,

    COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL)
        AS missing_carrier_date,

    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL)
        AS missing_customer_delivery_date

FROM orders;

SELECT
    COUNT(*) FILTER (WHERE review_comment_title IS NULL)
        AS missing_review_titles,

    COUNT(*) FILTER (WHERE review_comment_message IS NULL)
        AS missing_review_messages

FROM order_reviews;