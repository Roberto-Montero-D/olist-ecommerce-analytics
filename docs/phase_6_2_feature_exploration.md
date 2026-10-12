# Phase 6.2 — Checkout-Feature Exploration and Data Quality

**Project:** Olist E-commerce Analytics  
**Task:** Purchase-to-delivery duration regression  
**Scope:** Descriptive feature audits and feature-specification decisions, before implementation  
**Database:** PostgreSQL (`olist` schema)  
**Reproduction script:** `sql/ml/00_feature_exploration.sql`  
**Status:** Exploratory audits complete; feature extraction and implementation validation are separate tasks.

## 1. Objective and analysis population

Evaluate the relational structure, missingness, geographic plausibility, and order-level aggregation strategies for checkout-associated predictors. The observational unit is one order. For consistency with Phase 6.1, descriptive audits use **96,470** orders with `order_status = 'delivered'` and an actual delivery timestamp later than purchase. The eventual model follows the chronological label-availability policy in Phase 6.1; these descriptive full-population audits do **not** authorize fitting transformations, target encodings, or feature selection using held-out outcomes.

**Reproducibility:** Run the accompanying read-only SQL statements individually against the loaded Olist database. Query IDs E01–E09 correspond to the audit tables below. All nine query definitions (E01–E09) have been checked against the executed database results supplied during the project. Some SQL statements were reconstructed from the documented definitions, not recovered verbatim; agreement of the outputs verifies numerical reproducibility, not textual identity with the original statements. Numerical findings below come from the recorded database outputs.

## 2. Relational cardinality and aggregation grain

| Measure | Result |
|---|---:|
| Eligible orders | 96,470 |
| Associated order-item rows | 110,189 |
| Average items per order | 1.14 |
| Maximum items in one order | 21 |
| Orders with multiple items | 9,635 (9.99%) |
| Orders with multiple distinct products | 3,197 (3.31%) |
| Orders with multiple sellers | 1,275 (1.32%) |

**Design decision:** Build separate order-level aggregations from `order_items`, product, seller, and geography data before joining. Each subquery must return a unique `order_id`; never join several unaggregated one-to-many relations into the final modeling table. `order_payments` and reviews are excluded from the primary checkout-feature dataset.

## 3. Categorical feature diversity

| Audit measure | Product category | Seller state |
|---|---:|---:|
| Orders with one distinct value | 95,690 (99.19%) | 95,961 (99.47%) |
| Orders with multiple values | 780 (0.81%) | 509 (0.53%) |
| Maximum distinct values per order | 3 | 3 |
| Mean leading-value item-price share | 99.72% | 99.82% |

Category nulls are represented as `__missing__` for counting and dominance selection. For each order, the dominant category and dominant seller state are the values with the largest **sum of item prices**. Resolve exact ties by ascending category/state string to guarantee deterministic output. Preserve distinct counts and multiple-value flags; multiple sellers need not imply multiple seller states. The reported mean leading-value share is the **mean of order-level shares**, not a global revenue-weighted percentage.

**Reproduction:** E03–E04.

## 4. Financial aggregation and validity

| Measure | Result |
|---|---:|
| Orders with missing financial totals | 0 |
| Orders with nonpositive total item price | 0 |
| Orders with negative total freight | 0 |
| Orders with zero total freight | 336 (0.35%) |
| Mean total item price | R$137.04 |
| Mean total freight | R$22.79 |
| Maximum item-plus-freight order value | R$13,664.08 |

Keep valid zero-freight values and high-value observations. Use `SUM(price)` and `SUM(freight_value)` at order grain; derive total item-plus-freight value and freight-to-price ratio from these sums. Payment totals are not substituted for checkout-associated basket charges. Distribution-sensitive transformations belong in training-fitted Python preprocessing.

**Reproduction:** E05.

## 5. Geographic data and distance coverage

### Method

For each ZIP prefix, estimate representative coordinates using the median latitude and median longitude of geolocation records after restricting coordinates to plausible Brazil bounds: latitude −35 to 6, longitude −75 to −30. Calculate the Haversine great-circle distance (Earth radius 6,371 km) from customer ZIP-prefix coordinate to each item's seller ZIP-prefix coordinate. This is a geographic proxy, **not** road distance, transit time, or verified historical shipping route.

| Coverage of item-level distances | Orders | Multi-seller orders | Mean items | Max items |
|---|---:|---:|---:|---:|
| Complete | 95,989 (99.50%) | 1,265 | 1.14 | 21 |
| None available | 477 (0.49%) | 6 | 1.12 | 5 |
| Partial | 4 (0.004%) | 4 | 2.00 | 2 |
| **Total** | **96,470** | **1,275** | — | — |

Previously audited geographic findings include 265 orders without customer coordinates and 217 with at least one missing seller coordinate, with overlap. The distance distributions are reported at two distinct aggregation grains:

| Geographic statistic | Item-level (E08) | Order-level (E09) |
|---|---:|---:|
| Observations with distance | 109,652 item rows | 95,993 orders |
| Mean distance | 595.96 km | 600.44 km |
| Median distance | 431.87 km | 433.82 km |
| 95th percentile | 2,085.64 km | 2,095.38 km |
| Maximum distance | 3,398.49 km | 3,398.49 km (maximum item distance) |

E08 gives each available item row equal weight. E09 first averages the available item distances **within each order**, then gives each order with at least one available distance equal weight. Thus the order-level mean is 600.44 km, not the global item-row mean of 595.96 km. E09 also finds **477 orders with no available distance** and **5,625 orders with at least one item distance above 2,000 km**. The 4 partially covered orders contribute their available item distances to E09.

State-level plausibility audit (E08): 39,861 item rows had same-state customer/seller locations; 70,328 crossed states. Of same-state rows, 994 had distance greater than 500 km and none greater than 1,000 km; 11 cross-state item rows had distance below 10 km. These observations do not establish a systematic coordinate failure, but median ZIP-prefix locations remain approximations.

**Missing-distance policy:** Compute min/mean/max from available item distances; use `NULL` when none exist. Track the number and share of item distances available and an incomplete-coverage flag. Do not impute missing geographic values in SQL or replace them with zero. Any imputation must be fitted only on the training subset in Python. The mean distance is item-weighted (one contribution per `order_items` row), not seller-weighted.

**Reproduction:** E06 (coverage), E08 (item-level distances and state plausibility), E09 (order-level distances, verified). Do not conflate item-level and order-level means.

## 6. Product physical attributes and data quality

| Order-level condition | Orders | Share |
|---|---:|---:|
| At least one missing category | 1,392 | 1.443% |
| All categories missing | 1,332 | 1.381% |
| At least one invalid/missing weight | 22 | 0.023% |
| At least one invalid/missing dimension | 16 | 0.017% |
| Any invalid physical attribute | 22 | 0.023% |
| Any category or physical issue | 1,399 | 1.450% |

The 16 orders with invalid dimensions are included in the 22 with invalid weight. Exactly 15 orders have both a missing-category issue and an invalid-physical issue (`1,392 + 22 − 1,399`). Previously audited complete-validity counts were 96,448 orders for weight and 96,454 for volume. Available-item total weight had mean 2,387.02 g, median 750 g, 95th percentile 10,500 g, maximum 184,400 g; available-item total volume had mean 17,331.94 cm³ and maximum 1,476,000 cm³. Extremes were retained as potentially legitimate multi-item orders.

**Physical feature policy:** Treat nonpositive or null weights/dimensions as invalid. Sum valid item measurements, but set the aggregate to `NULL` if no valid item exists; never silently equate unknown measurements with zero. Preserve item-level completeness ratios and invalid-attribute flags. A partially observed total is explicitly a partial total, not an estimate of the true complete total. Do not exclude affected orders.

**Reproduction:** E02 (quality overlap) and E07 (physical aggregation). The physical means average available-value order totals; orders with no valid values are excluded by SQL AVG.

## 7. Proposed order-level feature dictionary

| Family | Output features | Aggregation or definition |
|---|---|---|
| Calendar | `purchase_month`, `purchase_day_of_week`, `purchase_hour` | Derived from purchase timestamp |
| Basket | `n_items`, `n_products`, `n_sellers` | Item-row count and distinct identifiers |
| Financial | `total_item_price`, `total_freight`, `total_order_value`, `mean_item_price`, `max_item_price`, `freight_to_price_ratio`, `has_free_freight` | Price/freight aggregations at order grain |
| Product category | `dominant_category`, `n_categories`, `dominant_category_value_share`, `has_multiple_categories` | Item-price dominance; missing category explicit |
| Product physical | `total_weight_g`, `max_item_weight_g`, `total_volume_cm3`, `max_item_volume_cm3`, `physical_coverage_ratio` | Valid-item measurements; coverage counts |
| Product quality | `missing_category_flag`, `invalid_weight_flag`, `invalid_dimensions_flag` | Any affected item in order |
| Customer location | `customer_state`, `customer_zip_prefix` | Customer delivery geography; ZIP prefix as string |
| Seller location | `dominant_seller_state`, `n_seller_states`, `has_multiple_seller_states`, `dominant_seller_state_value_share` | Item-price-weighted dominance and diversity |
| Geographic relation | `distance_mean_km`, `distance_min_km`, `distance_max_km`, `distance_coverage_ratio`, `distance_missing_flag`, `same_state_item_share` | Item-level Haversine and state comparison |

**Implementation precision:** `physical_coverage_ratio` counts item rows with both valid weight and valid dimensions divided by all item rows. Retain separate valid-weight and valid-volume counts if needed to interpret partial aggregates. Use `NULLIF` in denominators. Stable alphabetical tie-breaks and consistent handling of category placeholders must be tested in SQL. All missing flags reflect checkout-associated source data, not future delivery outcomes.

## 8. Prediction-time availability and leakage safeguards

These features are *checkout-associated proxies*, not verified real-time snapshots. Item-to-seller assignment, freight, product dimensions, catalog category, and ZIP-based locations are assumed available at purchase time; the historical dataset cannot establish the exact moment each value was recorded or updated. The model must be described as retrospective rather than production-validated.

Exclude actual delivery time, final order status, order approval, carrier handoff, reviews, customer satisfaction, and all future-outcome aggregates from predictors. Retain the delivery timestamp and target **only** as restricted labels/metadata for split construction and evaluation. The estimated delivery date belongs in a separately labeled estimate-assisted baseline or experiment, not the primary independent-feature model.

**No training/validation/test preprocessing is performed in this exploration.** Feature selection based on held-out target associations, scaling, imputation, encoders, and learned transformations must be isolated in later training pipelines. The finalized Phase 6.1 cohort and label-availability rules remain authoritative.

## 9. Implementation acceptance criteria (subsequent Phase 6.2 work)

1. One row per eligible order: 96,470 rows and 96,470 unique `order_id` values before 2016 exclusion and temporal splits.
2. Each component aggregation has unique order keys before joining; financial totals and item counts reconcile with E01/E05.
3. Product and geographic missingness counts reconcile with E02/E06; incomplete aggregates are flagged, not represented as complete.
4. Dominant category and seller-state selection is deterministic under ties; shares are bounded between zero and one for positive item-price totals.
5. No prohibited post-purchase columns enter the predictor matrix; target and metadata are separately named.
6. SQL files and run instructions are version controlled. Feature engineering is validated before moving to Phase 6.3.

## 10. Tooling and next stages

PostgreSQL owns relational joins, order-grain aggregation, data-integrity checks, and reproducible feature extraction. Pandas is used for exported-dataset verification, temporal split inspection, and exploratory model diagnostics. Scikit-learn pipelines own training-only imputation, encoding, scaling, transformations, and regression estimators. This separation reduces duplicate implementations and makes leakage controls easier to audit.

The next implementation artifact is `sql/ml/01_delivery_features.sql`. This exploration document and `sql/ml/00_feature_exploration.sql` are the evidence and specification that precede it.

## Appendix — SQL query index

The accompanying SQL script preserves the full read-only queries. Numbering is aligned with the chronological verification sequence.

| ID | Audit | Verification status |
|---|---|---|
| E01 | Eligible order-item cardinality | Verified |
| E02 | Product-quality flags and overlap | Verified |
| E03 | Category diversity and item-price dominance | Verified |
| E04 | Seller-state diversity and item-price dominance | Verified |
| E05 | Financial validity and order-level totals | Verified |
| E06 | Geographic distance availability by order | Verified |
| E07 | Product physical aggregation and completeness | Verified |
| E08 | Geographic plausibility and item-level distance summary | Verified |
| E09 | Order-level geographic distance distribution | Verified |

The geographic means differ by unit of analysis: E08 averages item distances over all valid item rows; E09 first averages within each order and then averages across orders. They should not be expected to match. The numerical results are documented in Section 5; SQL is the executable source of each calculation.
