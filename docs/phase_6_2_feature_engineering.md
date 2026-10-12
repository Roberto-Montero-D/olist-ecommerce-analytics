# Phase 6.2 — Delivery Feature Engineering and SQL Dataset

**Project:** Olist E-commerce Analytics  
**Objective:** Predict purchase-to-delivery duration conditional on recorded completion  
**Prediction reference:** Order purchase / checkout  
**Database:** PostgreSQL 17, schema `olist`  
**Source implementation:** `sql/ml/01_delivery_features.sql`  
**Published dataset:** `olist.ml_delivery_features` (SQL view)  
**Exploration and source audits:** `docs/phase_6_2_feature_exploration.md` and `sql/ml/00_feature_exploration.sql`  
**Problem definition and chronological protocol:** `docs/phase_6_1_problem_definition_and_data_contract.md`  
**Status:** SQL implementation and reported database validations complete; historical checkout availability remains an explicit limitation.

## 1. Objective and observational unit

The dataset contains **one row per eligible order**, with a positive observed purchase-to-delivery duration and checkout-associated explanatory variables. The target is defined as:

```sql
EXTRACT(EPOCH FROM (
    order_delivered_customer_date - order_purchase_timestamp
)) / 86400.0 AS delivery_days
```

Eligibility requires `order_status = 'delivered'` and `order_delivered_customer_date > order_purchase_timestamp`. The final status is **not** a predictor. This creates a retrospective *completed-delivery conditional* population, not a dataset representing all orders placed at checkout.

The SQL view contains **96,470** eligible orders, including **267** purchased before 2017. The Phase 6.1 modeling protocol excludes those 267 from its primary chronological cohorts. The view itself deliberately does not impose train/validation/test splits.

## 2. Reproducible SQL construction

Run `sql/ml/01_delivery_features.sql` against the populated Olist schema. The file contains eight independently executable verification steps, followed by a `CREATE OR REPLACE VIEW olist.ml_delivery_features AS ...` statement and its final verification query. The view is computed from the source tables when queried; it is **not a frozen historical snapshot** or a materialized training extract.

The assembly uses order-level CTEs to prevent many-to-many row multiplication:

1. `eligible_orders` — population, target and purchase calendar variables.
2. `basket_financials` — order-item counts, unique product/seller counts, price and freight sums.
3. `product_features` — item physical properties, category dominance and missingness flags.
4. `seller_state_features` — seller-state diversity and price-weighted dominant state.
5. `geographic_features` — customer/seller geography, ZIP-prefix coordinates, Haversine distances and coverage controls.
6. `assembled` — `LEFT JOIN` of the independent order-level feature groups using `order_id`.

The `LEFT JOIN` design retains eligible orders even when some geographic or physical attributes are missing. The validation queries check group-level uniqueness and agreement between independently derived item and seller counts.

## 3. Final dataset schema

There are **56 contracted columns**: **51 candidate predictors** and **5 metadata/label columns**.

### Metadata and label columns (never included in model predictors)

| Column | Purpose |
|---|---|
| `order_id` | Unique order key; row reconciliation |
| `customer_id` | Identifier; excluded from predictors |
| `purchased_at` | Chronological cohort assignment and prediction reference |
| `delivered_at` | Outcome-observation timestamp and as-of label availability |
| `delivery_days` | Regression target |

### Candidate predictor columns

| Group | Count | Columns |
|---|---:|---|
| Calendar | 4 | `purchase_year`, `purchase_month`, `purchase_day_of_week`, `purchase_hour` |
| Basket and financial | 10 | `n_items`, `n_products`, `n_sellers`, `total_item_price`, `total_freight`, `total_order_value`, `mean_item_price`, `max_item_price`, `freight_to_price_ratio`, `has_free_freight` |
| Product and category | 16 | `n_categories`, `dominant_category`, `dominant_category_value_share`, `has_multiple_categories`, `total_weight_g`, `max_item_weight_g`, `total_volume_cm3`, `max_item_volume_cm3`, `weight_coverage_ratio`, `volume_coverage_ratio`, `physical_coverage_ratio`, `invalid_weight_flag`, `invalid_dimensions_flag`, `missing_category_flag`, `all_categories_missing_flag`, `dominant_seller_state` |
| Seller state | 4 | `n_seller_states`, `has_multiple_seller_states`, `dominant_seller_state_value_share`, `customer_state` |
| Geography | 17 | `customer_zip_prefix`, `geo_n_items`, `geo_n_sellers`, `n_seller_zip_prefixes`, `n_valid_distances`, `n_missing_distances`, `distance_coverage_ratio`, `mean_distance_km`, `min_distance_km`, `max_distance_km`, `std_distance_km`, `n_same_state_items`, `n_cross_state_items`, `has_cross_state_seller`, `has_same_state_seller`, `distance_all_missing`, `distance_partially_missing` |

**Contract boundary:** The 51 fields are a *candidate predictor allowlist*, not a guarantee of historical real-time availability. Downstream Python code must select exactly these fields (or a documented subset) and exclude all five metadata/label fields. No target encoding, imputation, or scaling is performed in SQL.

## 4. Feature definitions and assumptions

### 4.1 Basket and financial features

Counts use `COUNT(*)`, `COUNT(DISTINCT product_id)` and `COUNT(DISTINCT seller_id)` at order grain. Monetary aggregates use item-level `SUM(price)` and `SUM(freight_value)`. `total_order_value` is the sum of item prices and freight, **not** payment-system revenue. `freight_to_price_ratio` divides total freight by total item price with `NULLIF` to guard against zero denominators; `has_free_freight` indicates zero total freight.

### 4.2 Products, categories and physical dimensions

Missing category names are assigned `__missing__` for categorical counting and dominance. `n_categories` therefore counts this sentinel as a distinct category where present. Dominance is based on the **sum of item prices** within each category; exact ties are resolved alphabetically using `ROW_NUMBER()`.

Valid weight requires `product_weight_g > 0`. Valid volume requires strictly positive length, height and width; item volume is their product in cm³. Total weight and volume are sums of **available valid** item values. An incomplete order can have a non-null partial total; completeness ratios and invalidity flags distinguish partial coverage from complete coverage. Missing physical measurements are not silently treated as zero.

### 4.3 Seller state

Distinct seller states are counted at order grain. The dominant state maximizes total item price attributed to that state; ties are resolved alphabetically. The dominant-state value share is calculated from the corresponding order-level state totals. The features describe assigned sellers in the historical dataset, under the checkout-availability assumption.

### 4.4 Geography and distance

Representative latitude and longitude for each Brazilian ZIP prefix are computed separately as medians of geolocation records within latitude **−35 to 6** and longitude **−75 to −30**. Item-level distances use the Haversine great-circle formula with Earth radius **6,371 km**. They are geographic proxies, **not** road distances or historical shipping trajectories.

`mean_distance_km` averages available item-level distances **within an order**; `std_distance_km` uses PostgreSQL `STDDEV_SAMP`, which is null when fewer than two valid distances exist. The mean across orders of `mean_distance_km` gives each order equal weight and is distinct from the global item-level mean. Missing and partial distance coverage are represented explicitly.

## 5. Validation results

All values below were reconciled against the PostgreSQL query outputs recorded during implementation.

| Audit | Verified result |
|---|---:|
| Final view rows / distinct order IDs | 96,470 / 96,470 |
| Duplicate rows | 0 |
| Invalid or nonpositive labels | 0 |
| Missing basket, product, seller-state or geography group joins | 0 each |
| Basket/geography item-count mismatches | 0 |
| Basket/geography seller-count mismatches | 0 |
| Associated order-item rows | 110,189 |
| Multi-item / multi-category / multi-seller-state orders | 9,635 / 780 / 509 |
| Mean item-price total / mean freight total | R$137.04 / R$22.79 |
| Maximum item-plus-freight order value | R$13,664.08 |
| Invalid-weight / invalid-dimension orders | 22 / 16 |
| Null total weight / total volume | 22 / 16 |
| Complete / partial / no-distance orders | 95,989 / 4 / 477 |
| Orders with any calculable distance | 95,993 |
| Available item distances | 109,652 |
| Mean / median / p95 order-level mean distance | 600.44 / 433.82 / 2,095.38 km |
| Maximum item distance | 3,398.49 km |
| Null `std_distance_km` | 86,883 |
| Missing mandatory metadata / basket / product / seller / geography controls | 0 each |
| Invalid ratios, geography counts, or inconsistent flags | 0 each |
| Schema columns / predictor columns / metadata-label columns | 56 / 51 / 5 |
| Unexpected / missing contracted columns / forbidden predictors | 0 / 0 / 0 |

**Interpretation of missingness:** The 477 null mean distances indicate no calculable item distance. The 86,883 null distance standard deviations are expected to be largely due to fewer than two valid distances; the precise count of one-valid-distance orders was not separately verified. Nulls in these derived measures are not grounds for dropping rows at SQL construction time.

**Verification scope:** The reported zero-error audits validate the tested structural and numerical invariants. They do not establish that every feature was actually available at purchase time, that all SQL edge cases have been exhaustively tested, or that a later Python pipeline is free of leakage.

## 6. Prediction-time contract and limitations

| Risk | Treatment |
|---|---|
| Future delivery outcome | `delivered_at` and `delivery_days` are metadata/target only; not predictors |
| Retrospective order status | Used solely to define eligible completed deliveries; never a feature |
| Identifier memorization | `order_id` and `customer_id` excluded from predictors |
| Purchase timestamp | Used for splits; calendar derivatives may be predictors |
| Seller assignment and freight quote availability | Assumed checkout-associated; historical as-of evidence unavailable |
| Product catalog and seller locations | Assumed available at checkout; no versioned historical snapshots |
| Geolocation table | Static ZIP-prefix proxy; may incorporate information not archived as of historical purchase time |
| Outcome-dependent selection | Model estimates duration conditional on eventual recorded delivery, not all placed orders |
| Temporal validation | Apply frozen as-of cohort and label-maturity rules from Phase 6.1 in Phase 6.3 |
| Data leakage via transformations | Fit imputers, encoders, feature selectors and models on training data only |

The reference prediction time is **purchase**, not approval or carrier handoff. Order approval, delivery estimates (in the primary independent model), carrier handoff, actual delivery, reviews, and final order status are excluded as predictors. The SQL view's retrospective population selection is an acknowledged estimand limitation; it does not make a deployment-time completion label available.

## 7. Phase 6.1 / Phase 6.2 interface

The frozen Phase 6.1 chronology governs all later use of the view:

| Purpose | Purchase cohort | Label-availability rule | Count |
|---|---|---|---:|
| Initial training | 2017 calendar year | Delivered before 2018-01-01 | 40,930 |
| Model-selection validation | Jan–Feb 2018 | Delivered before 2018-05-01 | 13,587 |
| Final refit | Purchases before 2018-05-01, from 2017 onward | Delivered before 2018-05-01 | 68,051 |
| Untouched final test | May–Aug 2018 | Retrospectively evaluate once labels are observed | 25,352 |

The final refit includes **43,424** observed 2017 labels, **13,587** Jan–Feb labels and **11,040** March–April labels. Training at an as-of cutoff excludes deliveries not yet observed by that cutoff. Such label maturity is outcome-dependent, especially for recent purchases; it may underrepresent long deliveries. Do not refit or tune on held-out test labels.

The January–February validation result applies to the *initial* fitted model; after model selection, the May 1 refit is a different model and is not independently validated by those same scores. This is a temporally constrained retrospective evaluation, **not** a production-proven rolling-origin backtest.

## 8. Reproduction and acceptance criteria

1. Load the nine Olist tables into the `olist` schema, preserving ZIP prefixes as five-digit text where applicable.
2. Run E01–E09 in `sql/ml/00_feature_exploration.sql` to reproduce descriptive audits.
3. Run Steps 1–8 in `sql/ml/01_delivery_features.sql` for component and contract checks.
4. Execute Step 9's `CREATE OR REPLACE VIEW`, then its verification `SELECT`.
5. Confirm 96,470 rows, 96,470 unique order IDs, zero invalid labels, the expected missingness and 56-column contract.
6. In Phase 6.3, use an explicit predictor allowlist and apply frozen temporal and label-availability splits **before fitting preprocessing**.

**Completion boundary:** Phase 6.2 establishes a reproducible, structurally validated SQL feature view. Phase 6.3 remains responsible for train/validation/test extraction, leakage-safe preprocessing, and executable tests of the chronological contract.
