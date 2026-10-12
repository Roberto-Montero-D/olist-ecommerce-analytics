-- Olist Phase 6.2 — Feature exploration and data quality audits
-- PostgreSQL 17; schema: olist. Run E01–E09 separately (read-only).
-- Canonical numbering matches the chronological verification discussion.
-- E01–E09 numerical outputs have been compared with executed database results.
-- Some statements were reconstructed from definitions, not recovered verbatim.
-- All descriptive eligibility filters use recorded delivery; never use these
-- post-purchase fields as prediction-time features.

-- E01 — Order-item cardinality
-- Reconstructed from the audit definition; verified against executed results.
WITH per_order AS (
 SELECT oi.order_id, COUNT(*) AS n_items,
 COUNT(DISTINCT oi.product_id) AS n_products,
 COUNT(DISTINCT oi.seller_id) AS n_sellers
 FROM olist.orders o JOIN olist.order_items oi USING(order_id)
 WHERE o.order_status='delivered'
 AND o.order_delivered_customer_date>o.order_purchase_timestamp
 GROUP BY oi.order_id
)
SELECT COUNT(*) AS eligible_orders, SUM(n_items) AS item_rows,
 ROUND(AVG(n_items)::numeric,2) AS mean_items, MAX(n_items) AS max_items,
 COUNT(*) FILTER(WHERE n_items>1) AS multi_item_orders,
 COUNT(*) FILTER(WHERE n_products>1) AS multi_product_orders,
 COUNT(*) FILTER(WHERE n_sellers>1) AS multi_seller_orders
FROM per_order;


-- E02 — Product quality overlap
-- Executed in conversation; expected 96,470 / 1,392 / 22 / 16 / 22 / 1,399 / 1,332.
WITH item_quality AS (
 SELECT oi.order_id,p.product_category_name,
 CASE WHEN p.product_weight_g>0 THEN 1 ELSE 0 END AS valid_weight,
 CASE WHEN p.product_length_cm>0 AND p.product_height_cm>0 AND p.product_width_cm>0
 THEN 1 ELSE 0 END AS valid_dimensions
 FROM olist.orders o JOIN olist.order_items oi USING(order_id)
 JOIN olist.products p USING(product_id)
 WHERE o.order_status='delivered'
 AND o.order_delivered_customer_date>o.order_purchase_timestamp
), per_order AS (
 SELECT order_id,COUNT(*) AS n_items,
 COUNT(*) FILTER(WHERE product_category_name IS NULL) AS missing_categories,
 COUNT(*) FILTER(WHERE valid_weight=0) AS invalid_weights,
 COUNT(*) FILTER(WHERE valid_dimensions=0) AS invalid_dimensions
 FROM item_quality GROUP BY order_id
)
SELECT COUNT(*) AS eligible_orders,
 COUNT(*) FILTER(WHERE missing_categories>0) AS orders_missing_category,
 COUNT(*) FILTER(WHERE invalid_weights>0) AS orders_invalid_weight,
 COUNT(*) FILTER(WHERE invalid_dimensions>0) AS orders_invalid_dimensions,
 COUNT(*) FILTER(WHERE invalid_weights>0 OR invalid_dimensions>0) AS orders_invalid_physical,
 COUNT(*) FILTER(WHERE missing_categories>0 OR invalid_weights>0 OR invalid_dimensions>0) AS orders_any_product_issue,
 COUNT(*) FILTER(WHERE missing_categories=n_items) AS orders_all_categories_missing
FROM per_order;


-- E03 — Category diversity and value dominance
-- Executed in conversation; expected 96,470 / 95,690 / 780 / 3 / 0.9972.
WITH category_values AS (
 SELECT oi.order_id, COALESCE(p.product_category_name,'__missing__') AS category,
 SUM(oi.price) AS category_value
 FROM olist.order_items oi JOIN olist.products p USING(product_id)
 JOIN olist.orders o USING(order_id)
 WHERE o.order_status='delivered'
 AND o.order_delivered_customer_date>o.order_purchase_timestamp
 GROUP BY oi.order_id, COALESCE(p.product_category_name,'__missing__')
), summary AS (
 SELECT order_id,COUNT(*) AS n_categories, MAX(category_value) AS max_value,
 SUM(category_value) AS total_value FROM category_values GROUP BY order_id
)
SELECT COUNT(*) AS eligible_orders,
 COUNT(*) FILTER(WHERE n_categories=1) AS single_category_orders,
 COUNT(*) FILTER(WHERE n_categories>1) AS multi_category_orders,
 MAX(n_categories) AS max_categories_per_order,
 ROUND(AVG(max_value/NULLIF(total_value,0))::numeric,4) AS mean_dominant_category_value_share
FROM summary;


-- E04 — Seller-state diversity and value dominance
-- Executed in conversation; expected 96,470 / 95,961 / 509 / 3 / 0.9982.
WITH state_values AS (
 SELECT oi.order_id,s.seller_state,SUM(oi.price) AS state_value
 FROM olist.orders o JOIN olist.order_items oi USING(order_id)
 JOIN olist.sellers s USING(seller_id)
 WHERE o.order_status='delivered'
 AND o.order_delivered_customer_date>o.order_purchase_timestamp
 GROUP BY oi.order_id,s.seller_state
), summary AS (
 SELECT order_id,COUNT(*) AS n_states,MAX(state_value) AS max_value,
 SUM(state_value) AS total_value FROM state_values GROUP BY order_id
)
SELECT COUNT(*) AS eligible_orders,
 COUNT(*) FILTER(WHERE n_states=1) AS single_seller_state_orders,
 COUNT(*) FILTER(WHERE n_states>1) AS multi_seller_state_orders,
 MAX(n_states) AS max_seller_states_per_order,
 ROUND(AVG(max_value/NULLIF(total_value,0))::numeric,4) AS mean_dominant_seller_state_value_share
FROM summary;


-- E05 — Financial aggregation integrity
-- Executed in conversation; expected 96,470 / 0 / 0 / 0 / 336 / 137.04 / 22.79 / 13,664.08.
WITH financials AS (
 SELECT oi.order_id,COUNT(*) AS n_items,SUM(oi.price) AS item_price,
 SUM(oi.freight_value) AS freight,SUM(oi.price+oi.freight_value) AS order_value
 FROM olist.order_items oi JOIN olist.orders o USING(order_id)
 WHERE o.order_status='delivered'
 AND o.order_delivered_customer_date>o.order_purchase_timestamp
 GROUP BY oi.order_id
)
SELECT COUNT(*) AS eligible_orders,
 COUNT(*) FILTER(WHERE item_price IS NULL OR freight IS NULL) AS missing_financial_totals,
 COUNT(*) FILTER(WHERE item_price<=0) AS nonpositive_item_price_orders,
 COUNT(*) FILTER(WHERE freight<0) AS negative_freight_orders,
 COUNT(*) FILTER(WHERE freight=0) AS zero_freight_orders,
 ROUND(AVG(item_price)::numeric,2) AS mean_item_price_total,
 ROUND(AVG(freight)::numeric,2) AS mean_freight_total,
 ROUND(MAX(order_value)::numeric,2) AS max_order_value
FROM financials;


-- E06 — Geographic distance coverage
-- Executed in conversation; expected complete 95,989, none 477, partial 4.
WITH zip_coords AS (
 SELECT geolocation_zip_code_prefix AS zip_prefix,
 PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY geolocation_lat) AS latitude,
 PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY geolocation_lng) AS longitude
 FROM olist.geolocation
 WHERE geolocation_lat BETWEEN -35 AND 6 AND geolocation_lng BETWEEN -75 AND -30
 GROUP BY geolocation_zip_code_prefix
), item_geo AS (
 SELECT oi.order_id,oi.seller_id,c.customer_state,s.seller_state,
 CASE WHEN cg.latitude IS NOT NULL AND sg.latitude IS NOT NULL THEN
 6371.0*2.0*ASIN(SQRT(
 POWER(SIN(RADIANS(sg.latitude-cg.latitude)/2.0),2)
 +COS(RADIANS(cg.latitude))*COS(RADIANS(sg.latitude))
 *POWER(SIN(RADIANS(sg.longitude-cg.longitude)/2.0),2)))
 END AS distance_km
 FROM olist.orders o JOIN olist.customers c USING(customer_id)
 JOIN olist.order_items oi USING(order_id)
 JOIN olist.sellers s USING(seller_id)
 LEFT JOIN zip_coords cg ON cg.zip_prefix=c.customer_zip_code_prefix
 LEFT JOIN zip_coords sg ON sg.zip_prefix=s.seller_zip_code_prefix
 WHERE o.order_status='delivered'
 AND o.order_delivered_customer_date>o.order_purchase_timestamp
), per_order AS (
 SELECT order_id,COUNT(*) AS n_items,COUNT(DISTINCT seller_id) AS n_sellers,
 COUNT(distance_km) AS n_distances_available
 FROM item_geo GROUP BY order_id
)
SELECT CASE WHEN n_distances_available=n_items THEN 'complete'
 WHEN n_distances_available=0 THEN 'none' ELSE 'partial' END AS distance_coverage,
 COUNT(*) AS orders,COUNT(*) FILTER(WHERE n_sellers>1) AS multi_seller_orders,
 ROUND(AVG(n_items)::numeric,2) AS mean_items,MAX(n_items) AS max_items
FROM per_order GROUP BY 1 ORDER BY 1;


-- E07 — Product attributes and physical aggregation
-- Reconstructed from the audit definition; verified against executed results.
-- SQL SUM ignores invalid items, so incomplete totals require coverage flags.
WITH item_physical AS (
 SELECT oi.order_id,oi.price,
 CASE WHEN p.product_weight_g>0 THEN p.product_weight_g END AS weight_g,
 CASE WHEN p.product_length_cm>0 AND p.product_height_cm>0 AND p.product_width_cm>0
 THEN p.product_length_cm*p.product_height_cm*p.product_width_cm END AS volume_cm3
 FROM olist.orders o JOIN olist.order_items oi USING(order_id)
 JOIN olist.products p USING(product_id)
 WHERE o.order_status='delivered'
 AND o.order_delivered_customer_date>o.order_purchase_timestamp
), per_order AS (
 SELECT order_id,COUNT(*) AS n_items,COUNT(weight_g) AS valid_weights,
 COUNT(volume_cm3) AS valid_volumes,
 SUM(weight_g) AS total_weight_g,SUM(volume_cm3) AS total_volume_cm3
 FROM item_physical GROUP BY order_id
)
SELECT COUNT(*) AS eligible_orders,
 COUNT(*) FILTER(WHERE valid_weights=n_items) AS orders_all_weights_valid,
 COUNT(*) FILTER(WHERE valid_volumes=n_items) AS orders_all_volumes_valid,
 ROUND(AVG(total_weight_g)::numeric,2) AS mean_available_weight_g,
 ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY total_weight_g)::numeric,2) AS median_available_weight_g,
 ROUND(MAX(total_weight_g)::numeric,2) AS max_available_weight_g,
 ROUND(AVG(total_volume_cm3)::numeric,2) AS mean_available_volume_cm3,
 ROUND(MAX(total_volume_cm3)::numeric,2) AS max_available_volume_cm3
FROM per_order;


-- E08 — Distance distribution and state plausibility
-- Reconstructed geographic check; verified against executed results.
-- Expected: 110189 items, 109652 distances, mean 595.96 km, median 431.87 km,
-- p95 2085.64 km, max 3398.49 km; same-state 39861, cross-state 70328,
-- same-state >500 km 994, >1000 km 0, cross-state <10 km 11.
-- The 600.44-km E09 mean gives each order equal weight, unlike this item-row mean.
WITH zip_coords AS (
 SELECT geolocation_zip_code_prefix AS zip_prefix,
 PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY geolocation_lat) AS latitude,
 PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY geolocation_lng) AS longitude
 FROM olist.geolocation
 WHERE geolocation_lat BETWEEN -35 AND 6 AND geolocation_lng BETWEEN -75 AND -30
 GROUP BY geolocation_zip_code_prefix
), item_geo AS (
 SELECT oi.order_id,oi.seller_id,c.customer_state,s.seller_state,
 CASE WHEN cg.latitude IS NOT NULL AND sg.latitude IS NOT NULL THEN
 6371.0*2.0*ASIN(SQRT(
 POWER(SIN(RADIANS(sg.latitude-cg.latitude)/2.0),2)
 +COS(RADIANS(cg.latitude))*COS(RADIANS(sg.latitude))
 *POWER(SIN(RADIANS(sg.longitude-cg.longitude)/2.0),2)))
 END AS distance_km
 FROM olist.orders o JOIN olist.customers c USING(customer_id)
 JOIN olist.order_items oi USING(order_id)
 JOIN olist.sellers s USING(seller_id)
 LEFT JOIN zip_coords cg ON cg.zip_prefix=c.customer_zip_code_prefix
 LEFT JOIN zip_coords sg ON sg.zip_prefix=s.seller_zip_code_prefix
 WHERE o.order_status='delivered'
 AND o.order_delivered_customer_date>o.order_purchase_timestamp
)
SELECT COUNT(*) AS item_rows,COUNT(distance_km) AS available_item_distances,
 ROUND(AVG(distance_km)::numeric,2) AS mean_item_distance_km,
 ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY distance_km)::numeric,2) AS median_item_distance_km,
 ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP(ORDER BY distance_km)::numeric,2) AS p95_item_distance_km,
 ROUND(MAX(distance_km)::numeric,2) AS max_item_distance_km,
 COUNT(*) FILTER(WHERE customer_state=seller_state) AS same_state_items,
 COUNT(*) FILTER(WHERE customer_state<>seller_state) AS cross_state_items,
 COUNT(*) FILTER(WHERE customer_state=seller_state AND distance_km>500) AS same_state_over_500_km,
 COUNT(*) FILTER(WHERE customer_state=seller_state AND distance_km>1000) AS same_state_over_1000_km,
 COUNT(*) FILTER(WHERE customer_state<>seller_state AND distance_km<10) AS cross_state_under_10_km
FROM item_geo;


-- E09 — Order-level geographic distance distribution (verified)
-- Each order has equal weight; the within-order average weights item rows equally.
-- Expected: 96470 eligible, 95993 with distance, 477 without; mean 600.44 km,
-- median 433.82 km, p95 2095.38 km, maximum item 3398.49 km,
-- 5625 orders with an item distance >2000 km.
WITH zip_coords AS (
 SELECT geolocation_zip_code_prefix AS zip_prefix,
 PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY geolocation_lat) AS latitude,
 PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY geolocation_lng) AS longitude
 FROM olist.geolocation
 WHERE geolocation_lat BETWEEN -35 AND 6 AND geolocation_lng BETWEEN -75 AND -30
 GROUP BY geolocation_zip_code_prefix
), item_geo AS (
 SELECT oi.order_id,oi.seller_id,c.customer_state,s.seller_state,
 CASE WHEN cg.latitude IS NOT NULL AND sg.latitude IS NOT NULL THEN
 6371.0*2.0*ASIN(SQRT(
 POWER(SIN(RADIANS(sg.latitude-cg.latitude)/2.0),2)
 +COS(RADIANS(cg.latitude))*COS(RADIANS(sg.latitude))
 *POWER(SIN(RADIANS(sg.longitude-cg.longitude)/2.0),2)))
 END AS distance_km
 FROM olist.orders o JOIN olist.customers c USING(customer_id)
 JOIN olist.order_items oi USING(order_id)
 JOIN olist.sellers s USING(seller_id)
 LEFT JOIN zip_coords cg ON cg.zip_prefix=c.customer_zip_code_prefix
 LEFT JOIN zip_coords sg ON sg.zip_prefix=s.seller_zip_code_prefix
 WHERE o.order_status='delivered'
 AND o.order_delivered_customer_date>o.order_purchase_timestamp
), order_distances AS (
 SELECT order_id, AVG(distance_km) AS mean_distance_km,
 MAX(distance_km) AS max_distance_km
 FROM item_geo GROUP BY order_id
)
SELECT COUNT(*) AS eligible_orders,
 COUNT(mean_distance_km) AS orders_with_distance,
 COUNT(*) FILTER (WHERE mean_distance_km IS NULL) AS orders_without_distance,
 ROUND(AVG(mean_distance_km)::numeric,2) AS mean_order_distance_km,
 ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mean_distance_km)::numeric,2) AS median_order_distance_km,
 ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY mean_distance_km)::numeric,2) AS p95_order_distance_km,
 ROUND(MAX(max_distance_km)::numeric,2) AS maximum_item_distance_km,
 COUNT(*) FILTER (WHERE max_distance_km>2000) AS orders_with_item_distance_over_2000_km
FROM order_distances;
