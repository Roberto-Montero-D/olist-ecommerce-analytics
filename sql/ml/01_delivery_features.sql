-- Phase 6.2 | Delivery-duration regression feature dataset
-- Repository destination: sql/ml/01_delivery_features.sql
-- PostgreSQL 17 | schema: olist
-- Status: Steps 1–9 verified against PostgreSQL outputs; view published.
-- Population: recorded delivered orders with strictly positive purchase-to-delivery duration.
-- IMPORTANT: delivery_days and delivered_at are LABEL/METADATA, never predictors.
-- The status filter defines the retrospective study population; order_status is not a feature.
-- The full-population dataset is NOT an as-of training cohort; Phase 6.1 cutoff rules apply later.

-- STEP 1: Validate the eligible-order base before adding joins.
WITH eligible_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_purchase_timestamp AS purchased_at,
        o.order_delivered_customer_date AS delivered_at,
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date - o.order_purchase_timestamp
        )) / 86400.0 AS delivery_days,
        EXTRACT(YEAR FROM o.order_purchase_timestamp)::integer AS purchase_year,
        EXTRACT(MONTH FROM o.order_purchase_timestamp)::integer AS purchase_month,
        EXTRACT(DOW FROM o.order_purchase_timestamp)::integer AS purchase_day_of_week,
        EXTRACT(HOUR FROM o.order_purchase_timestamp)::integer AS purchase_hour
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date > o.order_purchase_timestamp
)
SELECT
    COUNT(*) AS eligible_orders,
    COUNT(DISTINCT order_id) AS unique_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_rows,
    COUNT(*) FILTER (WHERE customer_id IS NULL OR purchased_at IS NULL) AS missing_base_fields,
    COUNT(*) FILTER (WHERE delivery_days IS NULL OR delivery_days <= 0) AS invalid_targets,
    ROUND(MIN(delivery_days)::numeric, 2) AS min_delivery_days,
    ROUND(MAX(delivery_days)::numeric, 2) AS max_delivery_days,
    COUNT(*) FILTER (WHERE purchased_at < TIMESTAMP '2017-01-01') AS pre_2017_orders,
    COUNT(*) FILTER (WHERE purchased_at >= TIMESTAMP '2017-01-01') AS orders_2017_onward
FROM eligible_orders;

-- STEP 2: Independently aggregate basket and financial features at order_id grain.
-- This verification query is self-contained; the final feature assembly comes later.
WITH eligible_orders AS (
    SELECT o.order_id
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date > o.order_purchase_timestamp
),
basket_financials AS (
    SELECT
        oi.order_id,
        COUNT(*) AS n_items,
        COUNT(DISTINCT oi.product_id) AS n_products,
        COUNT(DISTINCT oi.seller_id) AS n_sellers,
        SUM(oi.price) AS total_item_price,
        SUM(oi.freight_value) AS total_freight,
        SUM(oi.price + oi.freight_value) AS total_order_value,
        AVG(oi.price) AS mean_item_price,
        MAX(oi.price) AS max_item_price,
        SUM(oi.freight_value) / NULLIF(SUM(oi.price), 0) AS freight_to_price_ratio,
        (SUM(oi.freight_value) = 0)::integer AS has_free_freight
    FROM olist.order_items AS oi
    INNER JOIN eligible_orders AS eo ON eo.order_id = oi.order_id
    GROUP BY oi.order_id
)
SELECT
    (SELECT COUNT(*) FROM eligible_orders) AS eligible_orders,
    COUNT(*) AS basket_rows,
    COUNT(DISTINCT order_id) AS unique_basket_orders,
    SUM(n_items) AS item_rows,
    COUNT(*) FILTER (WHERE n_items > 1) AS multi_item_orders,
    COUNT(*) FILTER (WHERE n_products > 1) AS multi_product_orders,
    COUNT(*) FILTER (WHERE n_sellers > 1) AS multi_seller_orders,
    COUNT(*) FILTER (WHERE total_item_price IS NULL OR total_freight IS NULL) AS missing_financial_totals,
    COUNT(*) FILTER (WHERE total_item_price <= 0) AS nonpositive_item_price_orders,
    COUNT(*) FILTER (WHERE total_freight < 0) AS negative_freight_orders,
    COUNT(*) FILTER (WHERE has_free_freight = 1) AS zero_freight_orders,
    ROUND(AVG(total_item_price)::numeric, 2) AS mean_item_price_total,
    ROUND(AVG(total_freight)::numeric, 2) AS mean_freight_total,
    ROUND(MAX(total_order_value)::numeric, 2) AS max_order_value
FROM basket_financials;

-- STEP 3: Product attributes and value-dominant category, each at order_id grain.
-- Missing categories are explicit '__missing__' members, including in n_categories.
-- Weight and volume sums use available positive measurements only; NULL if none.
-- Incomplete sums are accompanied by coverage ratios and invalidity flags.
-- Dominant-category ties are broken alphabetically (deterministic).
WITH eligible_orders AS (
    SELECT o.order_id
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date > o.order_purchase_timestamp
),
item_product AS (
    SELECT
        oi.order_id,
        oi.price,
        COALESCE(p.product_category_name, '__missing__') AS category,
        CASE WHEN p.product_weight_g > 0 THEN p.product_weight_g END AS valid_weight_g,
        CASE WHEN p.product_length_cm > 0
               AND p.product_height_cm > 0
               AND p.product_width_cm > 0
             THEN p.product_length_cm * p.product_height_cm * p.product_width_cm
        END AS valid_volume_cm3,
        (p.product_category_name IS NULL)::integer AS missing_category_item
    FROM eligible_orders eo
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.products p ON p.product_id = oi.product_id
),
product_aggregates AS (
    SELECT
        order_id,
        COUNT(*) AS n_items,
        SUM(valid_weight_g) AS total_weight_g,
        MAX(valid_weight_g) AS max_item_weight_g,
        SUM(valid_volume_cm3) AS total_volume_cm3,
        MAX(valid_volume_cm3) AS max_item_volume_cm3,
        COUNT(valid_weight_g)::numeric / COUNT(*) AS weight_coverage_ratio,
        COUNT(valid_volume_cm3)::numeric / COUNT(*) AS volume_coverage_ratio,
        COUNT(*) FILTER (
            WHERE valid_weight_g IS NOT NULL AND valid_volume_cm3 IS NOT NULL
        )::numeric / COUNT(*) AS physical_coverage_ratio,
        (COUNT(valid_weight_g) < COUNT(*))::integer AS invalid_weight_flag,
        (COUNT(valid_volume_cm3) < COUNT(*))::integer AS invalid_dimensions_flag,
        (SUM(missing_category_item) > 0)::integer AS missing_category_flag,
        (SUM(missing_category_item) = COUNT(*))::integer AS all_categories_missing_flag
    FROM item_product
    GROUP BY order_id
),
category_values AS (
    SELECT order_id, category, SUM(price) AS category_value
    FROM item_product
    GROUP BY order_id, category
),
category_ranked AS (
    SELECT
        order_id, category, category_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY category_value DESC, category ASC
        ) AS category_rank
    FROM category_values
),
category_aggregates AS (
    SELECT
        order_id,
        COUNT(*) AS n_categories,
        MAX(category) FILTER (WHERE category_rank = 1) AS dominant_category,
        MAX(category_value) FILTER (WHERE category_rank = 1)
            / NULLIF(SUM(category_value), 0) AS dominant_category_value_share,
        (COUNT(*) > 1)::integer AS has_multiple_categories
    FROM category_ranked
    GROUP BY order_id
),
product_features AS (
    SELECT pa.*, ca.n_categories, ca.dominant_category,
           ca.dominant_category_value_share, ca.has_multiple_categories
    FROM product_aggregates pa
    JOIN category_aggregates ca USING (order_id)
)
SELECT
    (SELECT COUNT(*) FROM eligible_orders) AS eligible_orders,
    COUNT(*) AS product_rows,
    COUNT(DISTINCT order_id) AS unique_product_orders,
    COUNT(*) FILTER (WHERE n_categories = 1) AS single_category_orders,
    COUNT(*) FILTER (WHERE n_categories > 1) AS multi_category_orders,
    MAX(n_categories) AS max_categories_per_order,
    ROUND(AVG(dominant_category_value_share)::numeric, 4)
        AS mean_dominant_category_value_share,
    COUNT(*) FILTER (WHERE missing_category_flag = 1) AS orders_missing_category,
    COUNT(*) FILTER (WHERE all_categories_missing_flag = 1) AS orders_all_categories_missing,
    COUNT(*) FILTER (WHERE invalid_weight_flag = 1) AS orders_invalid_weight,
    COUNT(*) FILTER (WHERE invalid_dimensions_flag = 1) AS orders_invalid_dimensions,
    COUNT(*) FILTER (
        WHERE invalid_weight_flag = 1 OR invalid_dimensions_flag = 1
    ) AS orders_invalid_physical,
    COUNT(*) FILTER (
        WHERE missing_category_flag = 1 OR invalid_weight_flag = 1
           OR invalid_dimensions_flag = 1
    ) AS orders_any_product_issue,
    COUNT(*) FILTER (WHERE weight_coverage_ratio = 1) AS complete_weight_orders,
    COUNT(*) FILTER (WHERE volume_coverage_ratio = 1) AS complete_volume_orders,
    ROUND(AVG(total_weight_g)::numeric, 2) AS mean_available_total_weight_g,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY total_weight_g
    )::numeric, 2) AS median_available_total_weight_g,
    MAX(total_weight_g) AS max_available_total_weight_g,
    ROUND(AVG(total_volume_cm3)::numeric, 2) AS mean_available_total_volume_cm3,
    MAX(total_volume_cm3) AS max_available_total_volume_cm3
FROM product_features;

-- STEP 4: Seller-state diversity and value-dominant seller state.
-- Seller-state item values are summed before ranking, preventing row multiplication.
-- Ties in value are broken alphabetically for reproducibility.
WITH eligible_orders AS (
    SELECT o.order_id
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date > o.order_purchase_timestamp
),
seller_state_values AS (
    SELECT
        oi.order_id,
        s.seller_state,
        SUM(oi.price) AS state_item_value
    FROM eligible_orders eo
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.sellers s ON s.seller_id = oi.seller_id
    GROUP BY oi.order_id, s.seller_state
),
ranked_seller_states AS (
    SELECT
        order_id,
        seller_state,
        state_item_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY state_item_value DESC, seller_state ASC NULLS LAST
        ) AS state_rank,
        COUNT(*) OVER (PARTITION BY order_id) AS n_seller_states,
        SUM(state_item_value) OVER (PARTITION BY order_id) AS total_item_value
    FROM seller_state_values
),
seller_state_features AS (
    SELECT
        order_id,
        seller_state AS dominant_seller_state,
        n_seller_states,
        (n_seller_states > 1)::integer AS has_multiple_seller_states,
        state_item_value / NULLIF(total_item_value, 0)
            AS dominant_seller_state_value_share
    FROM ranked_seller_states
    WHERE state_rank = 1
)
SELECT
    (SELECT COUNT(*) FROM eligible_orders) AS eligible_orders,
    COUNT(*) AS seller_state_rows,
    COUNT(DISTINCT order_id) AS unique_seller_state_orders,
    COUNT(*) FILTER (WHERE n_seller_states = 1) AS single_seller_state_orders,
    COUNT(*) FILTER (WHERE n_seller_states > 1) AS multi_seller_state_orders,
    MAX(n_seller_states) AS max_seller_states_per_order,
    ROUND(AVG(dominant_seller_state_value_share)::numeric, 4)
        AS mean_dominant_seller_state_value_share,
    COUNT(*) FILTER (WHERE dominant_seller_state IS NULL)
        AS missing_dominant_seller_state,
    COUNT(*) FILTER (WHERE dominant_seller_state_value_share IS NULL)
        AS undefined_dominant_state_share
FROM seller_state_features;

-- Step 5 below verifies geographic aggregates. Final assembly follows.

-- STEP 5: Geographic features using robust ZIP-prefix median coordinates.
-- Coordinates are spatial proxies, not verified street addresses or travel routes.
-- A coordinate is available only when both customer and seller ZIP prefixes map
-- to a valid Brazilian latitude/longitude median. Partial orders are retained.
-- Each item is a separate row before order-level aggregation. Missing distances
-- do not enter AVG/MIN/MAX; coverage counts and flags preserve missingness.
-- This statement verifies both the E06 coverage and E09 order-level statistics.
WITH eligible_orders AS (
    SELECT o.order_id, o.customer_id
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date > o.order_purchase_timestamp
),
zip_coords AS (
    SELECT
        geolocation_zip_code_prefix AS zip_prefix,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lat) AS latitude,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lng) AS longitude
    FROM olist.geolocation
    WHERE geolocation_lat BETWEEN -35 AND 6
      AND geolocation_lng BETWEEN -75 AND -30
    GROUP BY geolocation_zip_code_prefix
),
item_geography AS (
    SELECT
        oi.order_id,
        oi.seller_id,
        s.seller_state,
        s.seller_zip_code_prefix,
        c.customer_state,
        c.customer_zip_code_prefix,
        CASE WHEN cg.latitude IS NOT NULL AND sg.latitude IS NOT NULL
             THEN 12742.0 * ASIN(SQRT(LEAST(1.0,
                 POWER(SIN(RADIANS(sg.latitude - cg.latitude) / 2.0), 2)
                 + COS(RADIANS(cg.latitude)) * COS(RADIANS(sg.latitude))
                 * POWER(SIN(RADIANS(sg.longitude - cg.longitude) / 2.0), 2)
             )))
        END AS distance_km
    FROM eligible_orders eo
    JOIN olist.customers c ON c.customer_id = eo.customer_id
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.sellers s ON s.seller_id = oi.seller_id
    LEFT JOIN zip_coords cg ON cg.zip_prefix = c.customer_zip_code_prefix
    LEFT JOIN zip_coords sg ON sg.zip_prefix = s.seller_zip_code_prefix
),
geographic_features AS (
    SELECT
        order_id,
        MIN(customer_state) AS customer_state,
        MIN(customer_zip_code_prefix) AS customer_zip_prefix,
        COUNT(*) AS geo_n_items,
        COUNT(DISTINCT seller_id) AS geo_n_sellers,
        COUNT(DISTINCT seller_zip_code_prefix) AS n_seller_zip_prefixes,
        COUNT(distance_km) AS n_valid_distances,
        COUNT(*) - COUNT(distance_km) AS n_missing_distances,
        COUNT(distance_km)::numeric / NULLIF(COUNT(*), 0) AS distance_coverage_ratio,
        AVG(distance_km) AS mean_distance_km,
        MIN(distance_km) AS min_distance_km,
        MAX(distance_km) AS max_distance_km,
        STDDEV_SAMP(distance_km) AS std_distance_km,
        COUNT(*) FILTER (WHERE seller_state = customer_state) AS n_same_state_items,
        COUNT(*) FILTER (WHERE seller_state <> customer_state) AS n_cross_state_items,
        (COUNT(*) FILTER (WHERE seller_state <> customer_state) > 0)::integer
            AS has_cross_state_seller,
        (COUNT(*) FILTER (WHERE seller_state = customer_state) > 0)::integer
            AS has_same_state_seller,
        (COUNT(distance_km) = 0)::integer AS distance_all_missing,
        (COUNT(distance_km) > 0 AND COUNT(distance_km) < COUNT(*))::integer
            AS distance_partially_missing
    FROM item_geography
    GROUP BY order_id
)
SELECT
    (SELECT COUNT(*) FROM eligible_orders) AS eligible_orders,
    COUNT(*) AS geographic_rows,
    COUNT(DISTINCT order_id) AS unique_geographic_orders,
    SUM(geo_n_items) AS item_rows,
    SUM(n_valid_distances) AS available_item_distances,
    COUNT(*) FILTER (WHERE n_valid_distances = geo_n_items) AS complete_distance_orders,
    COUNT(*) FILTER (WHERE n_valid_distances = 0) AS no_distance_orders,
    COUNT(*) FILTER (WHERE n_valid_distances > 0 AND n_valid_distances < geo_n_items)
        AS partial_distance_orders,
    COUNT(mean_distance_km) AS orders_with_distance,
    ROUND(AVG(mean_distance_km)::numeric, 2) AS mean_order_distance_km,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mean_distance_km)::numeric, 2)
        AS median_order_distance_km,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY mean_distance_km)::numeric, 2)
        AS p95_order_distance_km,
    ROUND(MAX(max_distance_km)::numeric, 2) AS max_item_distance_km,
    COUNT(*) FILTER (WHERE max_distance_km > 2000) AS orders_with_item_distance_over_2000_km,
    COUNT(*) FILTER (WHERE customer_state IS NULL OR customer_zip_prefix IS NULL)
        AS orders_missing_customer_geography,
    COUNT(*) FILTER (WHERE distance_coverage_ratio IS NULL) AS undefined_distance_coverage
FROM geographic_features;


-- STEP 6: Assemble verified order-level feature groups without row multiplication.
-- Execute this statement independently; earlier statements remain audit queries.
-- No table is persisted yet. This SELECT audits the integrated order grain.
-- `delivered_at` and `delivery_days` are restricted to label/metadata use.
-- Do not include these fields or order_id/customer_id in model predictors.
-- ZIP coordinates are approximate; historical checkout-time availability of
-- seller assignments, freight, and catalog attributes remains an assumption.
WITH
eligible_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_purchase_timestamp AS purchased_at,
        o.order_delivered_customer_date AS delivered_at,
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date - o.order_purchase_timestamp
        )) / 86400.0 AS delivery_days,
        EXTRACT(YEAR FROM o.order_purchase_timestamp)::integer AS purchase_year,
        EXTRACT(MONTH FROM o.order_purchase_timestamp)::integer AS purchase_month,
        EXTRACT(DOW FROM o.order_purchase_timestamp)::integer AS purchase_day_of_week,
        EXTRACT(HOUR FROM o.order_purchase_timestamp)::integer AS purchase_hour
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date > o.order_purchase_timestamp
),
basket_financials AS (
    SELECT
        oi.order_id,
        COUNT(*) AS n_items,
        COUNT(DISTINCT oi.product_id) AS n_products,
        COUNT(DISTINCT oi.seller_id) AS n_sellers,
        SUM(oi.price) AS total_item_price,
        SUM(oi.freight_value) AS total_freight,
        SUM(oi.price + oi.freight_value) AS total_order_value,
        AVG(oi.price) AS mean_item_price,
        MAX(oi.price) AS max_item_price,
        SUM(oi.freight_value) / NULLIF(SUM(oi.price), 0) AS freight_to_price_ratio,
        (SUM(oi.freight_value) = 0)::integer AS has_free_freight
    FROM olist.order_items AS oi
    INNER JOIN eligible_orders AS eo ON eo.order_id = oi.order_id
    GROUP BY oi.order_id
),
item_product AS (
    SELECT
        oi.order_id,
        oi.price,
        COALESCE(p.product_category_name, '__missing__') AS category,
        CASE WHEN p.product_weight_g > 0 THEN p.product_weight_g END AS valid_weight_g,
        CASE WHEN p.product_length_cm > 0
               AND p.product_height_cm > 0
               AND p.product_width_cm > 0
             THEN p.product_length_cm * p.product_height_cm * p.product_width_cm
        END AS valid_volume_cm3,
        (p.product_category_name IS NULL)::integer AS missing_category_item
    FROM eligible_orders eo
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.products p ON p.product_id = oi.product_id
),
product_aggregates AS (
    SELECT
        order_id,
        COUNT(*) AS n_items,
        SUM(valid_weight_g) AS total_weight_g,
        MAX(valid_weight_g) AS max_item_weight_g,
        SUM(valid_volume_cm3) AS total_volume_cm3,
        MAX(valid_volume_cm3) AS max_item_volume_cm3,
        COUNT(valid_weight_g)::numeric / COUNT(*) AS weight_coverage_ratio,
        COUNT(valid_volume_cm3)::numeric / COUNT(*) AS volume_coverage_ratio,
        COUNT(*) FILTER (
            WHERE valid_weight_g IS NOT NULL AND valid_volume_cm3 IS NOT NULL
        )::numeric / COUNT(*) AS physical_coverage_ratio,
        (COUNT(valid_weight_g) < COUNT(*))::integer AS invalid_weight_flag,
        (COUNT(valid_volume_cm3) < COUNT(*))::integer AS invalid_dimensions_flag,
        (SUM(missing_category_item) > 0)::integer AS missing_category_flag,
        (SUM(missing_category_item) = COUNT(*))::integer AS all_categories_missing_flag
    FROM item_product
    GROUP BY order_id
),
category_values AS (
    SELECT order_id, category, SUM(price) AS category_value
    FROM item_product
    GROUP BY order_id, category
),
category_ranked AS (
    SELECT
        order_id, category, category_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY category_value DESC, category ASC
        ) AS category_rank
    FROM category_values
),
category_aggregates AS (
    SELECT
        order_id,
        COUNT(*) AS n_categories,
        MAX(category) FILTER (WHERE category_rank = 1) AS dominant_category,
        MAX(category_value) FILTER (WHERE category_rank = 1)
            / NULLIF(SUM(category_value), 0) AS dominant_category_value_share,
        (COUNT(*) > 1)::integer AS has_multiple_categories
    FROM category_ranked
    GROUP BY order_id
),
product_features AS (
    SELECT pa.*, ca.n_categories, ca.dominant_category,
           ca.dominant_category_value_share, ca.has_multiple_categories
    FROM product_aggregates pa
    JOIN category_aggregates ca USING (order_id)
),
seller_state_values AS (
    SELECT
        oi.order_id,
        s.seller_state,
        SUM(oi.price) AS state_item_value
    FROM eligible_orders eo
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.sellers s ON s.seller_id = oi.seller_id
    GROUP BY oi.order_id, s.seller_state
),
ranked_seller_states AS (
    SELECT
        order_id,
        seller_state,
        state_item_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY state_item_value DESC, seller_state ASC NULLS LAST
        ) AS state_rank,
        COUNT(*) OVER (PARTITION BY order_id) AS n_seller_states,
        SUM(state_item_value) OVER (PARTITION BY order_id) AS total_item_value
    FROM seller_state_values
),
seller_state_features AS (
    SELECT
        order_id,
        seller_state AS dominant_seller_state,
        n_seller_states,
        (n_seller_states > 1)::integer AS has_multiple_seller_states,
        state_item_value / NULLIF(total_item_value, 0)
            AS dominant_seller_state_value_share
    FROM ranked_seller_states
    WHERE state_rank = 1
),
zip_coords AS (
    SELECT
        geolocation_zip_code_prefix AS zip_prefix,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lat) AS latitude,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lng) AS longitude
    FROM olist.geolocation
    WHERE geolocation_lat BETWEEN -35 AND 6
      AND geolocation_lng BETWEEN -75 AND -30
    GROUP BY geolocation_zip_code_prefix
),
item_geography AS (
    SELECT
        oi.order_id,
        oi.seller_id,
        s.seller_state,
        s.seller_zip_code_prefix,
        c.customer_state,
        c.customer_zip_code_prefix,
        CASE WHEN cg.latitude IS NOT NULL AND sg.latitude IS NOT NULL
             THEN 12742.0 * ASIN(SQRT(LEAST(1.0,
                 POWER(SIN(RADIANS(sg.latitude - cg.latitude) / 2.0), 2)
                 + COS(RADIANS(cg.latitude)) * COS(RADIANS(sg.latitude))
                 * POWER(SIN(RADIANS(sg.longitude - cg.longitude) / 2.0), 2)
             )))
        END AS distance_km
    FROM eligible_orders eo
    JOIN olist.customers c ON c.customer_id = eo.customer_id
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.sellers s ON s.seller_id = oi.seller_id
    LEFT JOIN zip_coords cg ON cg.zip_prefix = c.customer_zip_code_prefix
    LEFT JOIN zip_coords sg ON sg.zip_prefix = s.seller_zip_code_prefix
),
geographic_features AS (
    SELECT
        order_id,
        MIN(customer_state) AS customer_state,
        MIN(customer_zip_code_prefix) AS customer_zip_prefix,
        COUNT(*) AS geo_n_items,
        COUNT(DISTINCT seller_id) AS geo_n_sellers,
        COUNT(DISTINCT seller_zip_code_prefix) AS n_seller_zip_prefixes,
        COUNT(distance_km) AS n_valid_distances,
        COUNT(*) - COUNT(distance_km) AS n_missing_distances,
        COUNT(distance_km)::numeric / NULLIF(COUNT(*), 0) AS distance_coverage_ratio,
        AVG(distance_km) AS mean_distance_km,
        MIN(distance_km) AS min_distance_km,
        MAX(distance_km) AS max_distance_km,
        STDDEV_SAMP(distance_km) AS std_distance_km,
        COUNT(*) FILTER (WHERE seller_state = customer_state) AS n_same_state_items,
        COUNT(*) FILTER (WHERE seller_state <> customer_state) AS n_cross_state_items,
        (COUNT(*) FILTER (WHERE seller_state <> customer_state) > 0)::integer
            AS has_cross_state_seller,
        (COUNT(*) FILTER (WHERE seller_state = customer_state) > 0)::integer
            AS has_same_state_seller,
        (COUNT(distance_km) = 0)::integer AS distance_all_missing,
        (COUNT(distance_km) > 0 AND COUNT(distance_km) < COUNT(*))::integer
            AS distance_partially_missing
    FROM item_geography
    GROUP BY order_id
),
assembled AS (
    SELECT
        eo.order_id, eo.customer_id, eo.purchased_at, eo.delivered_at,
        eo.delivery_days, eo.purchase_year, eo.purchase_month,
        eo.purchase_day_of_week, eo.purchase_hour,
        b.n_items, b.n_products, b.n_sellers, b.total_item_price,
        b.total_freight, b.total_order_value, b.mean_item_price,
        b.max_item_price, b.freight_to_price_ratio, b.has_free_freight,
        p.n_categories, p.dominant_category, p.dominant_category_value_share,
        p.has_multiple_categories, p.total_weight_g, p.max_item_weight_g,
        p.total_volume_cm3, p.max_item_volume_cm3,
        p.weight_coverage_ratio, p.volume_coverage_ratio,
        p.physical_coverage_ratio, p.invalid_weight_flag,
        p.invalid_dimensions_flag, p.missing_category_flag,
        p.all_categories_missing_flag,
        ss.dominant_seller_state, ss.n_seller_states,
        ss.has_multiple_seller_states, ss.dominant_seller_state_value_share,
        g.customer_state, g.customer_zip_prefix, g.geo_n_items,
        g.geo_n_sellers, g.n_seller_zip_prefixes, g.n_valid_distances,
        g.n_missing_distances, g.distance_coverage_ratio,
        g.mean_distance_km, g.min_distance_km, g.max_distance_km,
        g.std_distance_km, g.n_same_state_items, g.n_cross_state_items,
        g.has_cross_state_seller, g.has_same_state_seller,
        g.distance_all_missing, g.distance_partially_missing
    FROM eligible_orders eo
    LEFT JOIN basket_financials b USING (order_id)
    LEFT JOIN product_features p USING (order_id)
    LEFT JOIN seller_state_features ss USING (order_id)
    LEFT JOIN geographic_features g USING (order_id)
)
SELECT
    COUNT(*) AS assembled_rows,
    COUNT(DISTINCT order_id) AS unique_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_rows,
    COUNT(*) FILTER (WHERE n_items IS NULL) AS missing_basket_join,
    COUNT(*) FILTER (WHERE n_categories IS NULL) AS missing_product_join,
    COUNT(*) FILTER (WHERE n_seller_states IS NULL) AS missing_seller_state_join,
    COUNT(*) FILTER (WHERE geo_n_items IS NULL) AS missing_geographic_join,
    COUNT(*) FILTER (WHERE n_items <> geo_n_items) AS basket_geography_item_mismatch,
    COUNT(*) FILTER (WHERE n_sellers <> geo_n_sellers) AS basket_geography_seller_mismatch,
    SUM(n_items) AS item_rows,
    COUNT(*) FILTER (WHERE n_items > 1) AS multi_item_orders,
    COUNT(*) FILTER (WHERE n_categories > 1) AS multi_category_orders,
    COUNT(*) FILTER (WHERE n_seller_states > 1) AS multi_seller_state_orders,
    COUNT(*) FILTER (WHERE distance_all_missing = 1) AS no_distance_orders,
    COUNT(*) FILTER (WHERE distance_partially_missing = 1) AS partial_distance_orders,
    COUNT(mean_distance_km) AS orders_with_distance,
    ROUND(AVG(mean_distance_km)::numeric, 2) AS mean_order_distance_km,
    ROUND(AVG(total_item_price)::numeric, 2) AS mean_item_price_total,
    COUNT(*) FILTER (WHERE delivery_days IS NULL OR delivery_days <= 0) AS invalid_targets
FROM assembled;



-- STEP 7: Audit assembled feature missingness, ranges, and flag consistency.
-- Execute independently. NULL totals/distance may be legitimate and must not be
-- imputed in SQL; std_distance_km is also NULL for one valid item distance.
-- All missing-* controls, invalid ratios/counts/flags should be zero.
WITH
eligible_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_purchase_timestamp AS purchased_at,
        o.order_delivered_customer_date AS delivered_at,
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date - o.order_purchase_timestamp
        )) / 86400.0 AS delivery_days,
        EXTRACT(YEAR FROM o.order_purchase_timestamp)::integer AS purchase_year,
        EXTRACT(MONTH FROM o.order_purchase_timestamp)::integer AS purchase_month,
        EXTRACT(DOW FROM o.order_purchase_timestamp)::integer AS purchase_day_of_week,
        EXTRACT(HOUR FROM o.order_purchase_timestamp)::integer AS purchase_hour
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date > o.order_purchase_timestamp
),
basket_financials AS (
    SELECT
        oi.order_id,
        COUNT(*) AS n_items,
        COUNT(DISTINCT oi.product_id) AS n_products,
        COUNT(DISTINCT oi.seller_id) AS n_sellers,
        SUM(oi.price) AS total_item_price,
        SUM(oi.freight_value) AS total_freight,
        SUM(oi.price + oi.freight_value) AS total_order_value,
        AVG(oi.price) AS mean_item_price,
        MAX(oi.price) AS max_item_price,
        SUM(oi.freight_value) / NULLIF(SUM(oi.price), 0) AS freight_to_price_ratio,
        (SUM(oi.freight_value) = 0)::integer AS has_free_freight
    FROM olist.order_items AS oi
    INNER JOIN eligible_orders AS eo ON eo.order_id = oi.order_id
    GROUP BY oi.order_id
),
item_product AS (
    SELECT
        oi.order_id,
        oi.price,
        COALESCE(p.product_category_name, '__missing__') AS category,
        CASE WHEN p.product_weight_g > 0 THEN p.product_weight_g END AS valid_weight_g,
        CASE WHEN p.product_length_cm > 0
               AND p.product_height_cm > 0
               AND p.product_width_cm > 0
             THEN p.product_length_cm * p.product_height_cm * p.product_width_cm
        END AS valid_volume_cm3,
        (p.product_category_name IS NULL)::integer AS missing_category_item
    FROM eligible_orders eo
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.products p ON p.product_id = oi.product_id
),
product_aggregates AS (
    SELECT
        order_id,
        COUNT(*) AS n_items,
        SUM(valid_weight_g) AS total_weight_g,
        MAX(valid_weight_g) AS max_item_weight_g,
        SUM(valid_volume_cm3) AS total_volume_cm3,
        MAX(valid_volume_cm3) AS max_item_volume_cm3,
        COUNT(valid_weight_g)::numeric / COUNT(*) AS weight_coverage_ratio,
        COUNT(valid_volume_cm3)::numeric / COUNT(*) AS volume_coverage_ratio,
        COUNT(*) FILTER (
            WHERE valid_weight_g IS NOT NULL AND valid_volume_cm3 IS NOT NULL
        )::numeric / COUNT(*) AS physical_coverage_ratio,
        (COUNT(valid_weight_g) < COUNT(*))::integer AS invalid_weight_flag,
        (COUNT(valid_volume_cm3) < COUNT(*))::integer AS invalid_dimensions_flag,
        (SUM(missing_category_item) > 0)::integer AS missing_category_flag,
        (SUM(missing_category_item) = COUNT(*))::integer AS all_categories_missing_flag
    FROM item_product
    GROUP BY order_id
),
category_values AS (
    SELECT order_id, category, SUM(price) AS category_value
    FROM item_product
    GROUP BY order_id, category
),
category_ranked AS (
    SELECT
        order_id, category, category_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY category_value DESC, category ASC
        ) AS category_rank
    FROM category_values
),
category_aggregates AS (
    SELECT
        order_id,
        COUNT(*) AS n_categories,
        MAX(category) FILTER (WHERE category_rank = 1) AS dominant_category,
        MAX(category_value) FILTER (WHERE category_rank = 1)
            / NULLIF(SUM(category_value), 0) AS dominant_category_value_share,
        (COUNT(*) > 1)::integer AS has_multiple_categories
    FROM category_ranked
    GROUP BY order_id
),
product_features AS (
    SELECT pa.*, ca.n_categories, ca.dominant_category,
           ca.dominant_category_value_share, ca.has_multiple_categories
    FROM product_aggregates pa
    JOIN category_aggregates ca USING (order_id)
),
seller_state_values AS (
    SELECT
        oi.order_id,
        s.seller_state,
        SUM(oi.price) AS state_item_value
    FROM eligible_orders eo
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.sellers s ON s.seller_id = oi.seller_id
    GROUP BY oi.order_id, s.seller_state
),
ranked_seller_states AS (
    SELECT
        order_id,
        seller_state,
        state_item_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY state_item_value DESC, seller_state ASC NULLS LAST
        ) AS state_rank,
        COUNT(*) OVER (PARTITION BY order_id) AS n_seller_states,
        SUM(state_item_value) OVER (PARTITION BY order_id) AS total_item_value
    FROM seller_state_values
),
seller_state_features AS (
    SELECT
        order_id,
        seller_state AS dominant_seller_state,
        n_seller_states,
        (n_seller_states > 1)::integer AS has_multiple_seller_states,
        state_item_value / NULLIF(total_item_value, 0)
            AS dominant_seller_state_value_share
    FROM ranked_seller_states
    WHERE state_rank = 1
),
zip_coords AS (
    SELECT
        geolocation_zip_code_prefix AS zip_prefix,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lat) AS latitude,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lng) AS longitude
    FROM olist.geolocation
    WHERE geolocation_lat BETWEEN -35 AND 6
      AND geolocation_lng BETWEEN -75 AND -30
    GROUP BY geolocation_zip_code_prefix
),
item_geography AS (
    SELECT
        oi.order_id,
        oi.seller_id,
        s.seller_state,
        s.seller_zip_code_prefix,
        c.customer_state,
        c.customer_zip_code_prefix,
        CASE WHEN cg.latitude IS NOT NULL AND sg.latitude IS NOT NULL
             THEN 12742.0 * ASIN(SQRT(LEAST(1.0,
                 POWER(SIN(RADIANS(sg.latitude - cg.latitude) / 2.0), 2)
                 + COS(RADIANS(cg.latitude)) * COS(RADIANS(sg.latitude))
                 * POWER(SIN(RADIANS(sg.longitude - cg.longitude) / 2.0), 2)
             )))
        END AS distance_km
    FROM eligible_orders eo
    JOIN olist.customers c ON c.customer_id = eo.customer_id
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.sellers s ON s.seller_id = oi.seller_id
    LEFT JOIN zip_coords cg ON cg.zip_prefix = c.customer_zip_code_prefix
    LEFT JOIN zip_coords sg ON sg.zip_prefix = s.seller_zip_code_prefix
),
geographic_features AS (
    SELECT
        order_id,
        MIN(customer_state) AS customer_state,
        MIN(customer_zip_code_prefix) AS customer_zip_prefix,
        COUNT(*) AS geo_n_items,
        COUNT(DISTINCT seller_id) AS geo_n_sellers,
        COUNT(DISTINCT seller_zip_code_prefix) AS n_seller_zip_prefixes,
        COUNT(distance_km) AS n_valid_distances,
        COUNT(*) - COUNT(distance_km) AS n_missing_distances,
        COUNT(distance_km)::numeric / NULLIF(COUNT(*), 0) AS distance_coverage_ratio,
        AVG(distance_km) AS mean_distance_km,
        MIN(distance_km) AS min_distance_km,
        MAX(distance_km) AS max_distance_km,
        STDDEV_SAMP(distance_km) AS std_distance_km,
        COUNT(*) FILTER (WHERE seller_state = customer_state) AS n_same_state_items,
        COUNT(*) FILTER (WHERE seller_state <> customer_state) AS n_cross_state_items,
        (COUNT(*) FILTER (WHERE seller_state <> customer_state) > 0)::integer
            AS has_cross_state_seller,
        (COUNT(*) FILTER (WHERE seller_state = customer_state) > 0)::integer
            AS has_same_state_seller,
        (COUNT(distance_km) = 0)::integer AS distance_all_missing,
        (COUNT(distance_km) > 0 AND COUNT(distance_km) < COUNT(*))::integer
            AS distance_partially_missing
    FROM item_geography
    GROUP BY order_id
),
assembled AS (
    SELECT
        eo.order_id, eo.customer_id, eo.purchased_at, eo.delivered_at,
        eo.delivery_days, eo.purchase_year, eo.purchase_month,
        eo.purchase_day_of_week, eo.purchase_hour,
        b.n_items, b.n_products, b.n_sellers, b.total_item_price,
        b.total_freight, b.total_order_value, b.mean_item_price,
        b.max_item_price, b.freight_to_price_ratio, b.has_free_freight,
        p.n_categories, p.dominant_category, p.dominant_category_value_share,
        p.has_multiple_categories, p.total_weight_g, p.max_item_weight_g,
        p.total_volume_cm3, p.max_item_volume_cm3,
        p.weight_coverage_ratio, p.volume_coverage_ratio,
        p.physical_coverage_ratio, p.invalid_weight_flag,
        p.invalid_dimensions_flag, p.missing_category_flag,
        p.all_categories_missing_flag,
        ss.dominant_seller_state, ss.n_seller_states,
        ss.has_multiple_seller_states, ss.dominant_seller_state_value_share,
        g.customer_state, g.customer_zip_prefix, g.geo_n_items,
        g.geo_n_sellers, g.n_seller_zip_prefixes, g.n_valid_distances,
        g.n_missing_distances, g.distance_coverage_ratio,
        g.mean_distance_km, g.min_distance_km, g.max_distance_km,
        g.std_distance_km, g.n_same_state_items, g.n_cross_state_items,
        g.has_cross_state_seller, g.has_same_state_seller,
        g.distance_all_missing, g.distance_partially_missing
    FROM eligible_orders eo
    LEFT JOIN basket_financials b USING (order_id)
    LEFT JOIN product_features p USING (order_id)
    LEFT JOIN seller_state_features ss USING (order_id)
    LEFT JOIN geographic_features g USING (order_id)
)
SELECT
    COUNT(*) AS assembled_rows,
    COUNT(*) FILTER (WHERE order_id IS NULL OR customer_id IS NULL OR purchased_at IS NULL) AS missing_metadata,
    COUNT(*) FILTER (WHERE delivered_at IS NULL OR delivery_days IS NULL OR delivery_days <= 0) AS invalid_labels,
    COUNT(*) FILTER (WHERE n_items IS NULL OR n_products IS NULL OR n_sellers IS NULL
        OR total_item_price IS NULL OR total_freight IS NULL OR total_order_value IS NULL
        OR mean_item_price IS NULL OR max_item_price IS NULL
        OR freight_to_price_ratio IS NULL OR has_free_freight IS NULL) AS missing_basket_features,
    COUNT(*) FILTER (WHERE n_categories IS NULL OR dominant_category IS NULL
        OR dominant_category_value_share IS NULL OR has_multiple_categories IS NULL
        OR weight_coverage_ratio IS NULL OR volume_coverage_ratio IS NULL
        OR physical_coverage_ratio IS NULL OR invalid_weight_flag IS NULL
        OR invalid_dimensions_flag IS NULL OR missing_category_flag IS NULL
        OR all_categories_missing_flag IS NULL) AS missing_product_controls,
    COUNT(*) FILTER (WHERE dominant_seller_state IS NULL OR n_seller_states IS NULL
        OR has_multiple_seller_states IS NULL OR dominant_seller_state_value_share IS NULL)
        AS missing_seller_features,
    COUNT(*) FILTER (WHERE customer_state IS NULL OR customer_zip_prefix IS NULL
        OR geo_n_items IS NULL OR geo_n_sellers IS NULL OR n_seller_zip_prefixes IS NULL
        OR n_valid_distances IS NULL OR n_missing_distances IS NULL
        OR distance_coverage_ratio IS NULL OR n_same_state_items IS NULL
        OR n_cross_state_items IS NULL OR has_cross_state_seller IS NULL
        OR has_same_state_seller IS NULL OR distance_all_missing IS NULL
        OR distance_partially_missing IS NULL) AS missing_geography_controls,
    COUNT(*) FILTER (WHERE total_weight_g IS NULL) AS null_total_weight,
    COUNT(*) FILTER (WHERE total_volume_cm3 IS NULL) AS null_total_volume,
    COUNT(*) FILTER (WHERE mean_distance_km IS NULL) AS null_mean_distance,
    COUNT(*) FILTER (WHERE std_distance_km IS NULL) AS null_std_distance,
    COUNT(*) FILTER (WHERE weight_coverage_ratio < 0 OR weight_coverage_ratio > 1
        OR volume_coverage_ratio < 0 OR volume_coverage_ratio > 1
        OR physical_coverage_ratio < 0 OR physical_coverage_ratio > 1
        OR distance_coverage_ratio < 0 OR distance_coverage_ratio > 1
        OR dominant_category_value_share < 0 OR dominant_category_value_share > 1
        OR dominant_seller_state_value_share < 0 OR dominant_seller_state_value_share > 1)
        AS invalid_ratios,
    COUNT(*) FILTER (WHERE n_valid_distances + n_missing_distances <> n_items
        OR n_same_state_items + n_cross_state_items <> n_items) AS invalid_geography_counts,
    COUNT(*) FILTER (WHERE (distance_all_missing = 1) <> (n_valid_distances = 0)
        OR (distance_partially_missing = 1) <>
            (n_valid_distances > 0 AND n_missing_distances > 0)) AS inconsistent_distance_flags,
    COUNT(*) FILTER (WHERE (invalid_weight_flag = 0 AND weight_coverage_ratio <> 1)
        OR (invalid_dimensions_flag = 0 AND volume_coverage_ratio <> 1))
        AS inconsistent_physical_flags
FROM assembled;


-- STEP 8: Explicit predictor allowlist / label separation audit.
-- This is a schema contract, NOT proof of historical checkout availability.
-- Only `predictor` fields may enter X in Phase 6.3; all others are metadata/labels.
WITH
eligible_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_purchase_timestamp AS purchased_at,
        o.order_delivered_customer_date AS delivered_at,
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date - o.order_purchase_timestamp
        )) / 86400.0 AS delivery_days,
        EXTRACT(YEAR FROM o.order_purchase_timestamp)::integer AS purchase_year,
        EXTRACT(MONTH FROM o.order_purchase_timestamp)::integer AS purchase_month,
        EXTRACT(DOW FROM o.order_purchase_timestamp)::integer AS purchase_day_of_week,
        EXTRACT(HOUR FROM o.order_purchase_timestamp)::integer AS purchase_hour
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date > o.order_purchase_timestamp
),
basket_financials AS (
    SELECT
        oi.order_id,
        COUNT(*) AS n_items,
        COUNT(DISTINCT oi.product_id) AS n_products,
        COUNT(DISTINCT oi.seller_id) AS n_sellers,
        SUM(oi.price) AS total_item_price,
        SUM(oi.freight_value) AS total_freight,
        SUM(oi.price + oi.freight_value) AS total_order_value,
        AVG(oi.price) AS mean_item_price,
        MAX(oi.price) AS max_item_price,
        SUM(oi.freight_value) / NULLIF(SUM(oi.price), 0) AS freight_to_price_ratio,
        (SUM(oi.freight_value) = 0)::integer AS has_free_freight
    FROM olist.order_items AS oi
    INNER JOIN eligible_orders AS eo ON eo.order_id = oi.order_id
    GROUP BY oi.order_id
),
item_product AS (
    SELECT
        oi.order_id,
        oi.price,
        COALESCE(p.product_category_name, '__missing__') AS category,
        CASE WHEN p.product_weight_g > 0 THEN p.product_weight_g END AS valid_weight_g,
        CASE WHEN p.product_length_cm > 0
               AND p.product_height_cm > 0
               AND p.product_width_cm > 0
             THEN p.product_length_cm * p.product_height_cm * p.product_width_cm
        END AS valid_volume_cm3,
        (p.product_category_name IS NULL)::integer AS missing_category_item
    FROM eligible_orders eo
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.products p ON p.product_id = oi.product_id
),
product_aggregates AS (
    SELECT
        order_id,
        COUNT(*) AS n_items,
        SUM(valid_weight_g) AS total_weight_g,
        MAX(valid_weight_g) AS max_item_weight_g,
        SUM(valid_volume_cm3) AS total_volume_cm3,
        MAX(valid_volume_cm3) AS max_item_volume_cm3,
        COUNT(valid_weight_g)::numeric / COUNT(*) AS weight_coverage_ratio,
        COUNT(valid_volume_cm3)::numeric / COUNT(*) AS volume_coverage_ratio,
        COUNT(*) FILTER (
            WHERE valid_weight_g IS NOT NULL AND valid_volume_cm3 IS NOT NULL
        )::numeric / COUNT(*) AS physical_coverage_ratio,
        (COUNT(valid_weight_g) < COUNT(*))::integer AS invalid_weight_flag,
        (COUNT(valid_volume_cm3) < COUNT(*))::integer AS invalid_dimensions_flag,
        (SUM(missing_category_item) > 0)::integer AS missing_category_flag,
        (SUM(missing_category_item) = COUNT(*))::integer AS all_categories_missing_flag
    FROM item_product
    GROUP BY order_id
),
category_values AS (
    SELECT order_id, category, SUM(price) AS category_value
    FROM item_product
    GROUP BY order_id, category
),
category_ranked AS (
    SELECT
        order_id, category, category_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY category_value DESC, category ASC
        ) AS category_rank
    FROM category_values
),
category_aggregates AS (
    SELECT
        order_id,
        COUNT(*) AS n_categories,
        MAX(category) FILTER (WHERE category_rank = 1) AS dominant_category,
        MAX(category_value) FILTER (WHERE category_rank = 1)
            / NULLIF(SUM(category_value), 0) AS dominant_category_value_share,
        (COUNT(*) > 1)::integer AS has_multiple_categories
    FROM category_ranked
    GROUP BY order_id
),
product_features AS (
    SELECT pa.*, ca.n_categories, ca.dominant_category,
           ca.dominant_category_value_share, ca.has_multiple_categories
    FROM product_aggregates pa
    JOIN category_aggregates ca USING (order_id)
),
seller_state_values AS (
    SELECT
        oi.order_id,
        s.seller_state,
        SUM(oi.price) AS state_item_value
    FROM eligible_orders eo
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.sellers s ON s.seller_id = oi.seller_id
    GROUP BY oi.order_id, s.seller_state
),
ranked_seller_states AS (
    SELECT
        order_id,
        seller_state,
        state_item_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY state_item_value DESC, seller_state ASC NULLS LAST
        ) AS state_rank,
        COUNT(*) OVER (PARTITION BY order_id) AS n_seller_states,
        SUM(state_item_value) OVER (PARTITION BY order_id) AS total_item_value
    FROM seller_state_values
),
seller_state_features AS (
    SELECT
        order_id,
        seller_state AS dominant_seller_state,
        n_seller_states,
        (n_seller_states > 1)::integer AS has_multiple_seller_states,
        state_item_value / NULLIF(total_item_value, 0)
            AS dominant_seller_state_value_share
    FROM ranked_seller_states
    WHERE state_rank = 1
),
zip_coords AS (
    SELECT
        geolocation_zip_code_prefix AS zip_prefix,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lat) AS latitude,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lng) AS longitude
    FROM olist.geolocation
    WHERE geolocation_lat BETWEEN -35 AND 6
      AND geolocation_lng BETWEEN -75 AND -30
    GROUP BY geolocation_zip_code_prefix
),
item_geography AS (
    SELECT
        oi.order_id,
        oi.seller_id,
        s.seller_state,
        s.seller_zip_code_prefix,
        c.customer_state,
        c.customer_zip_code_prefix,
        CASE WHEN cg.latitude IS NOT NULL AND sg.latitude IS NOT NULL
             THEN 12742.0 * ASIN(SQRT(LEAST(1.0,
                 POWER(SIN(RADIANS(sg.latitude - cg.latitude) / 2.0), 2)
                 + COS(RADIANS(cg.latitude)) * COS(RADIANS(sg.latitude))
                 * POWER(SIN(RADIANS(sg.longitude - cg.longitude) / 2.0), 2)
             )))
        END AS distance_km
    FROM eligible_orders eo
    JOIN olist.customers c ON c.customer_id = eo.customer_id
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.sellers s ON s.seller_id = oi.seller_id
    LEFT JOIN zip_coords cg ON cg.zip_prefix = c.customer_zip_code_prefix
    LEFT JOIN zip_coords sg ON sg.zip_prefix = s.seller_zip_code_prefix
),
geographic_features AS (
    SELECT
        order_id,
        MIN(customer_state) AS customer_state,
        MIN(customer_zip_code_prefix) AS customer_zip_prefix,
        COUNT(*) AS geo_n_items,
        COUNT(DISTINCT seller_id) AS geo_n_sellers,
        COUNT(DISTINCT seller_zip_code_prefix) AS n_seller_zip_prefixes,
        COUNT(distance_km) AS n_valid_distances,
        COUNT(*) - COUNT(distance_km) AS n_missing_distances,
        COUNT(distance_km)::numeric / NULLIF(COUNT(*), 0) AS distance_coverage_ratio,
        AVG(distance_km) AS mean_distance_km,
        MIN(distance_km) AS min_distance_km,
        MAX(distance_km) AS max_distance_km,
        STDDEV_SAMP(distance_km) AS std_distance_km,
        COUNT(*) FILTER (WHERE seller_state = customer_state) AS n_same_state_items,
        COUNT(*) FILTER (WHERE seller_state <> customer_state) AS n_cross_state_items,
        (COUNT(*) FILTER (WHERE seller_state <> customer_state) > 0)::integer
            AS has_cross_state_seller,
        (COUNT(*) FILTER (WHERE seller_state = customer_state) > 0)::integer
            AS has_same_state_seller,
        (COUNT(distance_km) = 0)::integer AS distance_all_missing,
        (COUNT(distance_km) > 0 AND COUNT(distance_km) < COUNT(*))::integer
            AS distance_partially_missing
    FROM item_geography
    GROUP BY order_id
),
assembled AS (
    SELECT
        eo.order_id, eo.customer_id, eo.purchased_at, eo.delivered_at,
        eo.delivery_days, eo.purchase_year, eo.purchase_month,
        eo.purchase_day_of_week, eo.purchase_hour,
        b.n_items, b.n_products, b.n_sellers, b.total_item_price,
        b.total_freight, b.total_order_value, b.mean_item_price,
        b.max_item_price, b.freight_to_price_ratio, b.has_free_freight,
        p.n_categories, p.dominant_category, p.dominant_category_value_share,
        p.has_multiple_categories, p.total_weight_g, p.max_item_weight_g,
        p.total_volume_cm3, p.max_item_volume_cm3,
        p.weight_coverage_ratio, p.volume_coverage_ratio,
        p.physical_coverage_ratio, p.invalid_weight_flag,
        p.invalid_dimensions_flag, p.missing_category_flag,
        p.all_categories_missing_flag,
        ss.dominant_seller_state, ss.n_seller_states,
        ss.has_multiple_seller_states, ss.dominant_seller_state_value_share,
        g.customer_state, g.customer_zip_prefix, g.geo_n_items,
        g.geo_n_sellers, g.n_seller_zip_prefixes, g.n_valid_distances,
        g.n_missing_distances, g.distance_coverage_ratio,
        g.mean_distance_km, g.min_distance_km, g.max_distance_km,
        g.std_distance_km, g.n_same_state_items, g.n_cross_state_items,
        g.has_cross_state_seller, g.has_same_state_seller,
        g.distance_all_missing, g.distance_partially_missing
    FROM eligible_orders eo
    LEFT JOIN basket_financials b USING (order_id)
    LEFT JOIN product_features p USING (order_id)
    LEFT JOIN seller_state_features ss USING (order_id)
    LEFT JOIN geographic_features g USING (order_id)
),
contract(column_name, role) AS (
    VALUES
        ('order_id', 'metadata_or_label'),
        ('customer_id', 'metadata_or_label'),
        ('purchased_at', 'metadata_or_label'),
        ('delivered_at', 'metadata_or_label'),
        ('delivery_days', 'metadata_or_label'),
        ('purchase_year', 'predictor'),
        ('purchase_month', 'predictor'),
        ('purchase_day_of_week', 'predictor'),
        ('purchase_hour', 'predictor'),
        ('n_items', 'predictor'),
        ('n_products', 'predictor'),
        ('n_sellers', 'predictor'),
        ('total_item_price', 'predictor'),
        ('total_freight', 'predictor'),
        ('total_order_value', 'predictor'),
        ('mean_item_price', 'predictor'),
        ('max_item_price', 'predictor'),
        ('freight_to_price_ratio', 'predictor'),
        ('has_free_freight', 'predictor'),
        ('n_categories', 'predictor'),
        ('dominant_category', 'predictor'),
        ('dominant_category_value_share', 'predictor'),
        ('has_multiple_categories', 'predictor'),
        ('total_weight_g', 'predictor'),
        ('max_item_weight_g', 'predictor'),
        ('total_volume_cm3', 'predictor'),
        ('max_item_volume_cm3', 'predictor'),
        ('weight_coverage_ratio', 'predictor'),
        ('volume_coverage_ratio', 'predictor'),
        ('physical_coverage_ratio', 'predictor'),
        ('invalid_weight_flag', 'predictor'),
        ('invalid_dimensions_flag', 'predictor'),
        ('missing_category_flag', 'predictor'),
        ('all_categories_missing_flag', 'predictor'),
        ('dominant_seller_state', 'predictor'),
        ('n_seller_states', 'predictor'),
        ('has_multiple_seller_states', 'predictor'),
        ('dominant_seller_state_value_share', 'predictor'),
        ('customer_state', 'predictor'),
        ('customer_zip_prefix', 'predictor'),
        ('geo_n_items', 'predictor'),
        ('geo_n_sellers', 'predictor'),
        ('n_seller_zip_prefixes', 'predictor'),
        ('n_valid_distances', 'predictor'),
        ('n_missing_distances', 'predictor'),
        ('distance_coverage_ratio', 'predictor'),
        ('mean_distance_km', 'predictor'),
        ('min_distance_km', 'predictor'),
        ('max_distance_km', 'predictor'),
        ('std_distance_km', 'predictor'),
        ('n_same_state_items', 'predictor'),
        ('n_cross_state_items', 'predictor'),
        ('has_cross_state_seller', 'predictor'),
        ('has_same_state_seller', 'predictor'),
        ('distance_all_missing', 'predictor'),
        ('distance_partially_missing', 'predictor')
),
actual_columns AS (
    SELECT DISTINCT key AS column_name
    FROM (SELECT to_jsonb(a) AS payload FROM assembled a LIMIT 1) sample
    CROSS JOIN LATERAL jsonb_object_keys(sample.payload) AS key
)
SELECT
    (SELECT COUNT(*) FROM actual_columns) AS actual_columns,
    (SELECT COUNT(*) FROM contract) AS contracted_columns,
    (SELECT COUNT(*) FROM contract WHERE role = 'predictor') AS predictor_columns,
    (SELECT COUNT(*) FROM contract WHERE role = 'metadata_or_label') AS metadata_label_columns,
    (SELECT COUNT(*) FROM actual_columns a LEFT JOIN contract c USING (column_name) WHERE c.column_name IS NULL) AS unexpected_columns,
    (SELECT COUNT(*) FROM contract c LEFT JOIN actual_columns a USING (column_name) WHERE a.column_name IS NULL) AS missing_contracted_columns,
    (SELECT COUNT(*) FROM contract WHERE role = 'predictor' AND column_name IN ('order_id', 'customer_id', 'purchased_at', 'delivered_at', 'delivery_days')) AS forbidden_predictors;


-- STEP 9: Publish the verified feature dataset as a reproducible SQL VIEW.
-- Run this CREATE VIEW statement separately in DBeaver.
-- A VIEW recomputes from source tables and does not materialize a static snapshot.
-- This is a retrospective labeled research dataset, NOT an as-of inference dataset.
-- The five metadata/label fields must be excluded from model predictors.
CREATE OR REPLACE VIEW olist.ml_delivery_features AS
WITH
eligible_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_purchase_timestamp AS purchased_at,
        o.order_delivered_customer_date AS delivered_at,
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date - o.order_purchase_timestamp
        )) / 86400.0 AS delivery_days,
        EXTRACT(YEAR FROM o.order_purchase_timestamp)::integer AS purchase_year,
        EXTRACT(MONTH FROM o.order_purchase_timestamp)::integer AS purchase_month,
        EXTRACT(DOW FROM o.order_purchase_timestamp)::integer AS purchase_day_of_week,
        EXTRACT(HOUR FROM o.order_purchase_timestamp)::integer AS purchase_hour
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date > o.order_purchase_timestamp
),
basket_financials AS (
    SELECT
        oi.order_id,
        COUNT(*) AS n_items,
        COUNT(DISTINCT oi.product_id) AS n_products,
        COUNT(DISTINCT oi.seller_id) AS n_sellers,
        SUM(oi.price) AS total_item_price,
        SUM(oi.freight_value) AS total_freight,
        SUM(oi.price + oi.freight_value) AS total_order_value,
        AVG(oi.price) AS mean_item_price,
        MAX(oi.price) AS max_item_price,
        SUM(oi.freight_value) / NULLIF(SUM(oi.price), 0) AS freight_to_price_ratio,
        (SUM(oi.freight_value) = 0)::integer AS has_free_freight
    FROM olist.order_items AS oi
    INNER JOIN eligible_orders AS eo ON eo.order_id = oi.order_id
    GROUP BY oi.order_id
),
item_product AS (
    SELECT
        oi.order_id,
        oi.price,
        COALESCE(p.product_category_name, '__missing__') AS category,
        CASE WHEN p.product_weight_g > 0 THEN p.product_weight_g END AS valid_weight_g,
        CASE WHEN p.product_length_cm > 0
               AND p.product_height_cm > 0
               AND p.product_width_cm > 0
             THEN p.product_length_cm * p.product_height_cm * p.product_width_cm
        END AS valid_volume_cm3,
        (p.product_category_name IS NULL)::integer AS missing_category_item
    FROM eligible_orders eo
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.products p ON p.product_id = oi.product_id
),
product_aggregates AS (
    SELECT
        order_id,
        COUNT(*) AS n_items,
        SUM(valid_weight_g) AS total_weight_g,
        MAX(valid_weight_g) AS max_item_weight_g,
        SUM(valid_volume_cm3) AS total_volume_cm3,
        MAX(valid_volume_cm3) AS max_item_volume_cm3,
        COUNT(valid_weight_g)::numeric / COUNT(*) AS weight_coverage_ratio,
        COUNT(valid_volume_cm3)::numeric / COUNT(*) AS volume_coverage_ratio,
        COUNT(*) FILTER (
            WHERE valid_weight_g IS NOT NULL AND valid_volume_cm3 IS NOT NULL
        )::numeric / COUNT(*) AS physical_coverage_ratio,
        (COUNT(valid_weight_g) < COUNT(*))::integer AS invalid_weight_flag,
        (COUNT(valid_volume_cm3) < COUNT(*))::integer AS invalid_dimensions_flag,
        (SUM(missing_category_item) > 0)::integer AS missing_category_flag,
        (SUM(missing_category_item) = COUNT(*))::integer AS all_categories_missing_flag
    FROM item_product
    GROUP BY order_id
),
category_values AS (
    SELECT order_id, category, SUM(price) AS category_value
    FROM item_product
    GROUP BY order_id, category
),
category_ranked AS (
    SELECT
        order_id, category, category_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY category_value DESC, category ASC
        ) AS category_rank
    FROM category_values
),
category_aggregates AS (
    SELECT
        order_id,
        COUNT(*) AS n_categories,
        MAX(category) FILTER (WHERE category_rank = 1) AS dominant_category,
        MAX(category_value) FILTER (WHERE category_rank = 1)
            / NULLIF(SUM(category_value), 0) AS dominant_category_value_share,
        (COUNT(*) > 1)::integer AS has_multiple_categories
    FROM category_ranked
    GROUP BY order_id
),
product_features AS (
    SELECT pa.*, ca.n_categories, ca.dominant_category,
           ca.dominant_category_value_share, ca.has_multiple_categories
    FROM product_aggregates pa
    JOIN category_aggregates ca USING (order_id)
),
seller_state_values AS (
    SELECT
        oi.order_id,
        s.seller_state,
        SUM(oi.price) AS state_item_value
    FROM eligible_orders eo
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.sellers s ON s.seller_id = oi.seller_id
    GROUP BY oi.order_id, s.seller_state
),
ranked_seller_states AS (
    SELECT
        order_id,
        seller_state,
        state_item_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY state_item_value DESC, seller_state ASC NULLS LAST
        ) AS state_rank,
        COUNT(*) OVER (PARTITION BY order_id) AS n_seller_states,
        SUM(state_item_value) OVER (PARTITION BY order_id) AS total_item_value
    FROM seller_state_values
),
seller_state_features AS (
    SELECT
        order_id,
        seller_state AS dominant_seller_state,
        n_seller_states,
        (n_seller_states > 1)::integer AS has_multiple_seller_states,
        state_item_value / NULLIF(total_item_value, 0)
            AS dominant_seller_state_value_share
    FROM ranked_seller_states
    WHERE state_rank = 1
),
zip_coords AS (
    SELECT
        geolocation_zip_code_prefix AS zip_prefix,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lat) AS latitude,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lng) AS longitude
    FROM olist.geolocation
    WHERE geolocation_lat BETWEEN -35 AND 6
      AND geolocation_lng BETWEEN -75 AND -30
    GROUP BY geolocation_zip_code_prefix
),
item_geography AS (
    SELECT
        oi.order_id,
        oi.seller_id,
        s.seller_state,
        s.seller_zip_code_prefix,
        c.customer_state,
        c.customer_zip_code_prefix,
        CASE WHEN cg.latitude IS NOT NULL AND sg.latitude IS NOT NULL
             THEN 12742.0 * ASIN(SQRT(LEAST(1.0,
                 POWER(SIN(RADIANS(sg.latitude - cg.latitude) / 2.0), 2)
                 + COS(RADIANS(cg.latitude)) * COS(RADIANS(sg.latitude))
                 * POWER(SIN(RADIANS(sg.longitude - cg.longitude) / 2.0), 2)
             )))
        END AS distance_km
    FROM eligible_orders eo
    JOIN olist.customers c ON c.customer_id = eo.customer_id
    JOIN olist.order_items oi ON oi.order_id = eo.order_id
    JOIN olist.sellers s ON s.seller_id = oi.seller_id
    LEFT JOIN zip_coords cg ON cg.zip_prefix = c.customer_zip_code_prefix
    LEFT JOIN zip_coords sg ON sg.zip_prefix = s.seller_zip_code_prefix
),
geographic_features AS (
    SELECT
        order_id,
        MIN(customer_state) AS customer_state,
        MIN(customer_zip_code_prefix) AS customer_zip_prefix,
        COUNT(*) AS geo_n_items,
        COUNT(DISTINCT seller_id) AS geo_n_sellers,
        COUNT(DISTINCT seller_zip_code_prefix) AS n_seller_zip_prefixes,
        COUNT(distance_km) AS n_valid_distances,
        COUNT(*) - COUNT(distance_km) AS n_missing_distances,
        COUNT(distance_km)::numeric / NULLIF(COUNT(*), 0) AS distance_coverage_ratio,
        AVG(distance_km) AS mean_distance_km,
        MIN(distance_km) AS min_distance_km,
        MAX(distance_km) AS max_distance_km,
        STDDEV_SAMP(distance_km) AS std_distance_km,
        COUNT(*) FILTER (WHERE seller_state = customer_state) AS n_same_state_items,
        COUNT(*) FILTER (WHERE seller_state <> customer_state) AS n_cross_state_items,
        (COUNT(*) FILTER (WHERE seller_state <> customer_state) > 0)::integer
            AS has_cross_state_seller,
        (COUNT(*) FILTER (WHERE seller_state = customer_state) > 0)::integer
            AS has_same_state_seller,
        (COUNT(distance_km) = 0)::integer AS distance_all_missing,
        (COUNT(distance_km) > 0 AND COUNT(distance_km) < COUNT(*))::integer
            AS distance_partially_missing
    FROM item_geography
    GROUP BY order_id
),
assembled AS (
    SELECT
        eo.order_id, eo.customer_id, eo.purchased_at, eo.delivered_at,
        eo.delivery_days, eo.purchase_year, eo.purchase_month,
        eo.purchase_day_of_week, eo.purchase_hour,
        b.n_items, b.n_products, b.n_sellers, b.total_item_price,
        b.total_freight, b.total_order_value, b.mean_item_price,
        b.max_item_price, b.freight_to_price_ratio, b.has_free_freight,
        p.n_categories, p.dominant_category, p.dominant_category_value_share,
        p.has_multiple_categories, p.total_weight_g, p.max_item_weight_g,
        p.total_volume_cm3, p.max_item_volume_cm3,
        p.weight_coverage_ratio, p.volume_coverage_ratio,
        p.physical_coverage_ratio, p.invalid_weight_flag,
        p.invalid_dimensions_flag, p.missing_category_flag,
        p.all_categories_missing_flag,
        ss.dominant_seller_state, ss.n_seller_states,
        ss.has_multiple_seller_states, ss.dominant_seller_state_value_share,
        g.customer_state, g.customer_zip_prefix, g.geo_n_items,
        g.geo_n_sellers, g.n_seller_zip_prefixes, g.n_valid_distances,
        g.n_missing_distances, g.distance_coverage_ratio,
        g.mean_distance_km, g.min_distance_km, g.max_distance_km,
        g.std_distance_km, g.n_same_state_items, g.n_cross_state_items,
        g.has_cross_state_seller, g.has_same_state_seller,
        g.distance_all_missing, g.distance_partially_missing
    FROM eligible_orders eo
    LEFT JOIN basket_financials b USING (order_id)
    LEFT JOIN product_features p USING (order_id)
    LEFT JOIN seller_state_features ss USING (order_id)
    LEFT JOIN geographic_features g USING (order_id)
)
SELECT * FROM assembled;

-- STEP 9 VERIFICATION: Run this SELECT after creating the view.
SELECT
    COUNT(*) AS dataset_rows,
    COUNT(DISTINCT order_id) AS unique_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_rows,
    COUNT(*) FILTER (WHERE delivery_days IS NULL OR delivery_days <= 0) AS invalid_labels,
    COUNT(*) FILTER (WHERE n_items IS NULL OR total_item_price IS NULL) AS missing_basket_features,
    COUNT(*) FILTER (WHERE dominant_category IS NULL OR dominant_seller_state IS NULL) AS missing_categorical_features,
    COUNT(*) FILTER (WHERE mean_distance_km IS NULL) AS null_mean_distance,
    ROUND(AVG(mean_distance_km)::numeric, 2) AS mean_order_distance_km,
    ROUND(AVG(total_item_price)::numeric, 2) AS mean_item_price_total
FROM olist.ml_delivery_features;
