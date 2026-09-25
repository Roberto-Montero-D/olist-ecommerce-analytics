/*
===============================================================================
Olist E-Commerce Analytics
File: sql/analysis/00_validate_source.sql
Purpose: Validate the PostgreSQL source layer after raw CSV ingestion
===============================================================================

This script verifies that:

1. PostgreSQL row counts match the expected source dataset.
2. Key business entities have the expected cardinality.
3. Parent-child relationships are consistent.
4. Known source-data gaps are preserved and measurable.
5. Important NULL patterns remain visible after ingestion.
6. Known source anomalies can be reproduced in SQL.

This is a validation script, not a cleaning script. No source records are
modified or removed.

===============================================================================
*/

SET search_path TO olist;


-- ============================================================================
-- 1. TABLE ROW COUNTS
-- ============================================================================

-- Expected counts from the raw CSV audit:
-- customers                99,441
-- orders                   99,441
-- products                 32,951
-- sellers                   3,095
-- order_items             112,650
-- order_payments          103,886
-- order_reviews            99,224
-- category_translation         71
-- geolocation           1,000,163

SELECT 'customers' AS table_name, COUNT(*) AS row_count
FROM customers

UNION ALL

SELECT 'orders', COUNT(*)
FROM orders

UNION ALL

SELECT 'products', COUNT(*)
FROM products

UNION ALL

SELECT 'sellers', COUNT(*)
FROM sellers

UNION ALL

SELECT 'order_items', COUNT(*)
FROM order_items

UNION ALL

SELECT 'order_payments', COUNT(*)
FROM order_payments

UNION ALL

SELECT 'order_reviews', COUNT(*)
FROM order_reviews

UNION ALL

SELECT 'category_translation', COUNT(*)
FROM category_translation

UNION ALL

SELECT 'geolocation', COUNT(*)
FROM geolocation

ORDER BY table_name;


-- ============================================================================
-- 2. ORDER STATUS DISTRIBUTION
-- ============================================================================

-- Confirm that order lifecycle states were preserved during ingestion.

SELECT
    order_status,
    COUNT(*) AS order_count
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;


-- ============================================================================
-- 3. KEY CARDINALITY
-- ============================================================================

-- Validate the expected one-row-per-entity source tables.

SELECT
    COUNT(*) AS customer_rows,
    COUNT(DISTINCT customer_id) AS distinct_customer_ids
FROM customers;

SELECT
    COUNT(*) AS order_rows,
    COUNT(DISTINCT order_id) AS distinct_order_ids
FROM orders;

SELECT
    COUNT(*) AS product_rows,
    COUNT(DISTINCT product_id) AS distinct_product_ids
FROM products;

SELECT
    COUNT(*) AS seller_rows,
    COUNT(DISTINCT seller_id) AS distinct_seller_ids
FROM sellers;


-- Validate composite grains for child tables.

SELECT
    COUNT(*) AS item_rows,
    COUNT(DISTINCT (order_id, order_item_id)) AS distinct_item_keys
FROM order_items;

SELECT
    COUNT(*) AS payment_rows,
    COUNT(DISTINCT (order_id, payment_sequential)) AS distinct_payment_keys
FROM order_payments;

SELECT
    COUNT(*) AS review_rows,
    COUNT(DISTINCT (review_id, order_id)) AS distinct_review_keys
FROM order_reviews;


-- ============================================================================
-- 4. CUSTOMER IDENTITY
-- ============================================================================

-- customer_id identifies the customer record associated with an order.
-- customer_unique_id represents the persistent customer identity and should
-- be used for analyses such as repeat purchasing, retention, RFM, and CLV.

SELECT
    COUNT(*) AS customer_records,
    COUNT(DISTINCT customer_id) AS distinct_customer_ids,
    COUNT(DISTINCT customer_unique_id) AS distinct_people
FROM customers;


-- ============================================================================
-- 5. REVIEW CARDINALITY
-- ============================================================================

-- review_id alone is not unique in the source data.
-- The source schema therefore uses (review_id, order_id) as the composite key.

SELECT
    COUNT(*) AS review_rows,
    COUNT(DISTINCT review_id) AS distinct_review_ids,
    COUNT(DISTINCT order_id) AS distinct_orders_reviewed,
    COUNT(DISTINCT (review_id, order_id)) AS distinct_review_order_pairs
FROM order_reviews;


-- ============================================================================
-- 6. FOREIGN-KEY / ORPHAN VALIDATION
-- ============================================================================

-- These counts should all be zero.

SELECT
    COUNT(*) AS orphan_orders
FROM orders AS o
LEFT JOIN customers AS c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;


SELECT
    COUNT(*) AS orphan_order_items
FROM order_items AS oi
LEFT JOIN orders AS o
    ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;


SELECT
    COUNT(*) AS orphan_item_products
FROM order_items AS oi
LEFT JOIN products AS p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;


SELECT
    COUNT(*) AS orphan_item_sellers
FROM order_items AS oi
LEFT JOIN sellers AS s
    ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;


SELECT
    COUNT(*) AS orphan_payments
FROM order_payments AS op
LEFT JOIN orders AS o
    ON op.order_id = o.order_id
WHERE o.order_id IS NULL;


SELECT
    COUNT(*) AS orphan_reviews
FROM order_reviews AS r
LEFT JOIN orders AS o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;


-- ============================================================================
-- 7. PARENT RECORDS WITHOUT CHILD RECORDS
-- ============================================================================

-- These are coverage checks, not foreign-key violations.
-- A parent record can legitimately exist without a corresponding child row.

SELECT
    COUNT(*) FILTER (
        WHERE NOT EXISTS (
            SELECT 1
            FROM order_items AS oi
            WHERE oi.order_id = o.order_id
        )
    ) AS orders_without_items,

    COUNT(*) FILTER (
        WHERE NOT EXISTS (
            SELECT 1
            FROM order_payments AS op
            WHERE op.order_id = o.order_id
        )
    ) AS orders_without_payments,

    COUNT(*) FILTER (
        WHERE NOT EXISTS (
            SELECT 1
            FROM order_reviews AS r
            WHERE r.order_id = o.order_id
        )
    ) AS orders_without_reviews

FROM orders AS o;


-- ============================================================================
-- 8. ORDERS WITHOUT ITEMS BY STATUS
-- ============================================================================

-- Most orders without item records belong to incomplete lifecycle states,
-- particularly unavailable and canceled orders.

SELECT
    o.order_status,
    COUNT(*) AS order_count
FROM orders AS o
LEFT JOIN order_items AS oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status
ORDER BY order_count DESC;


-- ============================================================================
-- 9. ORDERS WITHOUT PAYMENTS
-- ============================================================================

-- Inspect the status distribution of orders without payment records.
-- The source audit identified one delivered order without a payment record.

SELECT
    o.order_status,
    COUNT(*) AS order_count
FROM orders AS o
LEFT JOIN order_payments AS op
    ON o.order_id = op.order_id
WHERE op.order_id IS NULL
GROUP BY o.order_status
ORDER BY order_count DESC;


-- ============================================================================
-- 10. ORDERS WITHOUT REVIEWS
-- ============================================================================

SELECT
    o.order_status,
    COUNT(*) AS order_count
FROM orders AS o
LEFT JOIN order_reviews AS r
    ON o.order_id = r.order_id
WHERE r.order_id IS NULL
GROUP BY o.order_status
ORDER BY order_count DESC;


-- ============================================================================
-- 11. CATEGORY TRANSLATION COVERAGE
-- ============================================================================

-- The translation table does not contain every non-null Portuguese category
-- found in products. This is why the source schema intentionally does not
-- enforce a foreign key from products to category_translation.

SELECT
    COUNT(DISTINCT p.product_category_name) AS untranslated_categories
FROM products AS p
LEFT JOIN category_translation AS ct
    ON p.product_category_name = ct.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND ct.product_category_name IS NULL;


-- Show the actual untranslated category values.

SELECT DISTINCT
    p.product_category_name
FROM products AS p
LEFT JOIN category_translation AS ct
    ON p.product_category_name = ct.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND ct.product_category_name IS NULL
ORDER BY p.product_category_name;


-- ============================================================================
-- 12. IMPORTANT NULL COUNTS: ORDERS
-- ============================================================================

-- Missing lifecycle timestamps should not automatically be treated as data
-- errors because their presence can depend on the order's lifecycle state.

SELECT
    COUNT(*) FILTER (
        WHERE order_approved_at IS NULL
    ) AS missing_order_approved_at,

    COUNT(*) FILTER (
        WHERE order_delivered_carrier_date IS NULL
    ) AS missing_carrier_date,

    COUNT(*) FILTER (
        WHERE order_delivered_customer_date IS NULL
    ) AS missing_customer_delivery_date

FROM orders;


-- ============================================================================
-- 13. IMPORTANT NULL COUNTS: REVIEWS
-- ============================================================================

-- Review title and message fields are optional and therefore contain a large
-- number of NULL values.

SELECT
    COUNT(*) FILTER (
        WHERE review_comment_title IS NULL
    ) AS missing_review_titles,

    COUNT(*) FILTER (
        WHERE review_comment_message IS NULL
    ) AS missing_review_messages

FROM order_reviews;


-- ============================================================================
-- 14. IMPORTANT NULL COUNTS: PRODUCTS
-- ============================================================================

SELECT
    COUNT(*) FILTER (
        WHERE product_category_name IS NULL
    ) AS missing_product_category,

    COUNT(*) FILTER (
        WHERE product_name_lenght IS NULL
    ) AS missing_product_name_length,

    COUNT(*) FILTER (
        WHERE product_description_lenght IS NULL
    ) AS missing_product_description_length,

    COUNT(*) FILTER (
        WHERE product_photos_qty IS NULL
    ) AS missing_product_photos,

    COUNT(*) FILTER (
        WHERE product_weight_g IS NULL
    ) AS missing_product_weight,

    COUNT(*) FILTER (
        WHERE product_length_cm IS NULL
    ) AS missing_product_length,

    COUNT(*) FILTER (
        WHERE product_height_cm IS NULL
    ) AS missing_product_height,

    COUNT(*) FILTER (
        WHERE product_width_cm IS NULL
    ) AS missing_product_width

FROM products;