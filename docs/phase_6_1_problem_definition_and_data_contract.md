# Phase 6.1 — Delivery Duration Regression: Problem Definition and Data Contract

**Project:** Olist E-commerce Analytics  
**Study type:** Retrospective, temporally ordered supervised regression  
**Prediction reference:** Order purchase / checkout  
**Primary outcome:** Purchase-to-customer-delivery elapsed time (days), conditional on a recorded completed delivery  
**Data source:** Olist historical order tables in PostgreSQL (`olist` schema)

## 1. Research objective and scope

This study investigates how accurately checkout-associated information predicts the time between purchase and customer delivery. The intended output is a duration estimate **conditional on an order ultimately being delivered**, not the probability that an order will be delivered. The model is evaluated on later purchase cohorts rather than on a random split.

For eligible order *i*, define:

$$
T_i = \frac{\mathrm{delivered\_at}_i - \mathrm{purchased\_at}_i}{86{,}400}
$$

Here, timestamps are in seconds and the target is in days. The estimand is the conditional delivery-time distribution, summarized by a model of $E[T \mid X, D=1]$, where $X$ contains checkout-associated predictors and $D=1$ denotes a recorded completed delivery. Some model objectives, such as MAE optimization, estimate a conditional median rather than a conditional mean; the conditional population is the same.

**Eligibility rule:** `order_status = 'delivered'` and `order_delivered_customer_date > order_purchase_timestamp`. An order contributes one observation. The delivery timestamp creates the target and is **never** an input predictor. Final order status defines the retrospective cohort and is **never** a predictor.

**Interpretation boundary:** Predictions do not imply a guaranteed delivery or describe the time to cancellation. This is a retrospective approximation of a checkout-time use case, not a production-validated real-time service.

## 2. Cohort definition and recorded outcomes

The full dataset contains **99,441 orders**. The primary eligibility rule identifies **96,470** completed deliveries with positive durations, including **267** purchases from 2016. The primary modeling period begins in 2017; its **96,203** eligible deliveries are assigned to chronological cohorts below.

### Recorded order statuses for purchases from 2017 onward

| Recorded status | Orders | Positive recorded delivery duration | Missing delivery timestamp |
|---|---:|---:|---:|
| Delivered | 96,211 | 96,203 | 8 |
| Shipped | 1,098 | 0 | 1,098 |
| Unavailable | 602 | 0 | 602 |
| Canceled | 599 | 1 | 598 |
| Processing | 299 | 0 | 299 |
| Invoiced | 296 | 0 | 296 |
| Created | 5 | 0 | 5 |
| Approved | 2 | 0 | 2 |
| **Total** | **99,112** | **96,204** | **2,908** |

The canceled order with a positive delivery duration is excluded because its recorded status is not `delivered`. The eight delivered orders without a delivery timestamp have no computable regression target. Intermediate statuses are not treated as confirmed failures, and no arbitrary duration is assigned to canceled or unresolved orders.

**Selection effect:** The eligible cohort is defined using a future outcome. This is appropriate for a *conditional* regression study but may select against orders with unusually difficult logistics, cancellation, or unresolved fulfillment. Recorded coverage is high but does not establish unbiased generalization to all checkout orders. An outcome-classification or competing-risk/survival extension would require more reliable terminal-status and observation-cutoff information.

## 3. Target distribution and temporal variation

### Distribution of `delivery_days` (96,470 eligible orders)

| Statistic | Days |
|---|---:|
| Minimum | 0.53 |
| 1st percentile | 1.83 |
| 25th percentile | 6.77 |
| Median | 10.22 |
| Mean | 12.56 |
| 75th percentile | 15.72 |
| 95th percentile | 29.27 |
| 99th percentile | 46.05 |
| Maximum | 209.63 |

| Long-delivery threshold | Orders above threshold |
|---|---:|
| More than 30 days | 4,550 |
| More than 60 days | 306 |
| More than 90 days | 77 |

The distribution is right-skewed. Long deliveries remain in scope; they are not removed solely because they are extreme. Later experiments will compare untransformed targets against `log1p(delivery_days)` and report all prediction errors in **original days**, including long-delivery subgroup performance.

### Illustrative monthly variation

| Purchase month | Mean delivery duration (days) |
|---|---:|
| February 2018 | ~16.95 |
| March 2018 | ~16.30 |
| August 2018 | ~7.73 |

These descriptive means are computed on recorded completed deliveries. They may reflect operational changes, seasonality, differing order mix, and outcome selection. They motivate chronological evaluation and month-stratified error analysis; they do not establish causality.

## 4. Platform estimated-delivery field

The platform estimate (`order_estimated_delivery_date`) is present for all **96,470** eligible orders. Its purchase-time availability cannot be verified from historical field-availability logs, so it is excluded from the primary independent-feature model and reserved for a separately labeled estimate-assisted comparison.

| Measurement | Result |
|---|---:|
| Mean platform estimated purchase-to-delivery interval | 23.74 days |
| Mean actual purchase-to-delivery interval | 12.56 days |
| Delivered before estimated calendar date | 88,644 (91.89%) |
| Delivered on estimated calendar date | 1,292 (1.34%) |
| Delivered after estimated calendar date | 6,534 (6.77%) |
| Mean actual-minus-estimated calendar-day difference | −11.88 days |
| Median actual-minus-estimated calendar-day difference | −12 days |

Calendar-date early/on-time/late comparisons are distinct from exact timestamp-duration errors. The platform estimate is conservative in this observed cohort; this alone does not prove it was intended as a point prediction of expected delivery time.

## 5. Purchase-time feature availability contract

The prediction timestamp is `order_purchase_timestamp`. Olist lacks field-level availability histories and time-versioned catalog snapshots. The following contract uses explicit **checkout-associated assumptions**, not assertions of verified real-time availability.

| Candidate information | Primary model | Availability rationale / limitation |
|---|---|---|
| Purchase timestamp; derived month, weekday, hour, weekend | Include | Purchase-time information |
| Customer state and ZIP prefix | Include | Assumed known from checkout delivery destination |
| Purchased item and distinct-product counts | Include | Assumed known from the purchased basket |
| Item prices | Include | Assumed known at checkout |
| Seller counts, assignments, state and ZIP prefix | Include, assumption flagged | Seller allocation assumed fixed/known at checkout; may differ in historical operational reality |
| Freight charges | Include, assumption flagged | Assumed checkout quote rather than later finalized charge |
| Product category, weight, dimensions | Include, assumption flagged | Historical catalog used as proxy; values are not time-versioned |
| Customer–seller ZIP-centroid distances | Include, assumption flagged | Derived from static median coordinates; geographic approximation, not driving distance |
| Platform estimated delivery date | Separate experiment only | Purchase-time availability unverified |
| Approval, carrier handoff, actual delivery, reviews | Exclude | Occur after prediction point or reveal the outcome |
| Final order status | Eligibility only | Not known at checkout |
| Historical delivery aggregates | Exclude initially | Would require a strict as-of construction |

**Implementation requirements:** Build all order-level predictors without referencing delivery outcomes, approval, carrier timestamps, review outcomes, or final status. Aggregate item-level and geographic records before joining to avoid row multiplication. Fit all imputers, encoders, scalers, and supervised transformations only on the permitted fitting population. The data contract defines safeguards; SQL and Python tests in later phases must verify compliance.

## 6. Chronological evaluation and label availability

All date intervals are **start-inclusive, end-exclusive**. Cohorts are defined by **purchase time**, while training-label eligibility additionally requires that the actual delivery timestamp precede the relevant fitting cutoff.

| Role | Purchase interval | Eventually delivered | Labels usable at stated cutoff |
|---|---|---:|---:|
| Initial training | 2017-01-01 to 2018-01-01 | 43,426 | 40,930 by 2018-01-01 |
| Validation | 2018-01-01 to 2018-03-01 | 13,624 | 13,587 by 2018-05-01 |
| March–April refit pool | 2018-03-01 to 2018-05-01 | 13,801 | 11,040 by 2018-05-01 |
| Held-out test | 2018-05-01 to 2018-09-01 | 25,352 | All 25,352 eventually observed; 58 delivered after 2018-09-01 |

### Development procedure

1. **Initial candidate fitting, as of January 1, 2018:** Train on the **40,930** 2017-purchase orders whose deliveries were already recorded. All fitted preprocessing is restricted to those rows.
2. **Delayed-label validation, by May 1, 2018:** Score the fixed candidate models on January–February purchases. Use the **13,587** labels available before May 1 for model selection. The remaining **37** eventually delivered orders are not available for as-of selection. This is *offline model selection after validation outcomes mature*, not a claim of deployment or tuning before January–February purchases.
3. **Final refit, as of May 1, 2018:** After fixing model choices, rebuild and refit the pipeline on all eligible purchases before May 1 with delivery outcomes observed before May 1: **43,424** (2017) + **13,587** (Jan–Feb) + **11,040** (Mar–Apr) = **68,051** rows. This refitted model is not independently validated by the original January–February scores because those rows now enter fitting.
4. **Untouched final test:** Evaluate the frozen refitted model on the **25,352** eventually delivered May–August purchases, once outcomes are available. Do not use test labels to select features, transformations, models, hyperparameters, or thresholds.

### Why January–February validation was selected

| Validation purchase window | Eventually delivered | Labels available by May 1 | Completeness among eventually delivered |
|---|---:|---:|---:|
| January–February | 13,624 | 13,587 | 99.73% |
| January–March | 20,627 | 20,403 | 98.91% |
| January–April | 27,425 | 24,627 | 89.80% |

The January–February window preserves substantial validation size while reducing maturity-based exclusion near May 1. Its completeness percentage is **conditional on eventual recorded delivery** and does not quantify all-order follow-up.

### Administrative label truncation

The January 1 training cutoff is causally defensible but changes the observed training distribution: purchases late in December have less time to complete than purchases earlier in 2017. **2,496** eventually delivered 2017 orders were not yet labeled on January 1; **2,494** became available by May 1, leaving two unavailable for that refit. Similarly, **37** eventual validation deliveries were not labeled by May 1.

This is an **outcome-maturity selection effect**, not a post-purchase feature leak. Prespecified later reporting will compare duration distributions by purchase month, assess long-delivery errors, and separately report a retrospective fully matured 2017 training-cohort sensitivity experiment. A model using labels unavailable on January 1 must **not** be represented as deployable on January 1. No sensitivity result may be used to revise the frozen primary model after test inspection.

## 7. Observation coverage and unresolved outcomes

### Recorded timestamp limits

| Field | Latest timestamp in dataset |
|---|---|
| Purchase | 2018-10-17 17:30:18 |
| Approval | 2018-09-03 17:40:06 |
| Carrier handoff | 2018-09-11 19:48:28 |
| Actual customer delivery | 2018-10-17 13:22:46 |
| Estimated delivery date | 2018-11-12 00:00:00 |

There are **1,729** orders with intermediate recorded statuses across the full dataset and **8** delivered orders missing delivery timestamps. These maximum timestamps do **not** establish the actual extraction date. In particular, future estimated dates are not observed outcomes, and some unresolved statuses occur well before the dataset's end. Thus no exact censoring cutoff or definitive non-delivery labels can be inferred.

### Monthly recorded delivery coverage, 2018

| Purchase month | Purchases | Valid deliveries | Canceled / unavailable | Intermediate unresolved | Delivered, missing timestamp | Coverage |
|---|---:|---:|---:|---:|---:|---:|
| Jan | 7,269 | 7,069 | 82 | 118 | 0 | 97.25% |
| Feb | 6,728 | 6,555 | 103 | 70 | 0 | 97.43% |
| Mar | 7,211 | 7,003 | 43 | 165 | 0 | 97.12% |
| Apr | 6,939 | 6,798 | 20 | 121 | 0 | 97.97% |
| May | 6,873 | 6,749 | 40 | 84 | 0 | 98.20% |
| Jun | 6,167 | 6,096 | 22 | 46 | 3 | 98.85% |
| Jul | 6,292 | 6,156 | 59 | 74 | 3 | 97.84% |
| Aug | 6,512 | 6,351 | 91 | 70 | 0 | 97.53% |
| **Test period: May–Aug** | **25,844** | **25,352** | **212** | **274** | **6** | **98.10%** |

The May–August recorded-delivery coverage remains between **97.53% and 98.85%**, with no monotonic decline toward August. This reduces concern about an obvious end-period coverage collapse but does not prove complete follow-up or remove outcome selection. The categories reconcile exactly: **25,352 + 212 + 274 + 6 = 25,844**.

## 8. Limitations and prespecified evaluation commitments

| Threat | Implication | Mitigation / reporting commitment |
|---|---|---|
| Conditioning on completed delivery | Cannot generalize unqualified to all purchases | State conditional estimand and recorded completion coverage |
| Unknown extraction cutoff and unresolved statuses | Cannot reliably infer all non-deliveries or censoring times | Do not fabricate negative outcomes or a survival cutoff |
| Administrative label truncation | Early-fit data underrepresent longer late-cohort deliveries | Explicit cutoffs; month/long-delay analysis; separate retrospective sensitivity |
| Historical snapshot availability | Some checkout features are assumptions, not verified as-of records | Field-level contract; separate estimate-assisted study |
| Temporal drift | Random split may overstate future generalization | Chronological holdout and month-stratified residuals |
| Long-tailed durations | Mean-only or overall metrics can hide long-delay failures | MAE, RMSE, R² in days; long-duration subgroup metrics; raw vs `log1p` targets |
| Data joins and preprocessing | Row duplication or fitted transformations may leak information | Order-level SQL uniqueness checks; train-only transformations; automated tests |
| Test contamination | Repeated test-driven decisions invalidate holdout interpretation | Freeze modeling protocol before final test inspection |

**Scope of completion:** Phase 6.1 establishes the objective, population, feature-availability assumptions, evaluation cohorts, label-cutoff policy, and limitations. Actual feature-table integrity and leakage tests are required deliverables of subsequent implementation phases; they are not claimed as already verified here.

---

## Appendix A — Reproducible PostgreSQL audit queries

The queries below reproduce the Phase 6.1 measurements from `olist.orders`. Run them in PostgreSQL against the loaded Olist schema. They are organized by analysis rather than by the order in which exploratory questions arose. Published descriptive values are rounded; percentile and interval calculations use the underlying timestamp precision.

### A1. Eligible population, target distribution, and long-delivery counts

```sql
WITH durations AS (
    SELECT
        order_id,
        EXTRACT(EPOCH FROM (
            order_delivered_customer_date - order_purchase_timestamp
        )) / 86400.0 AS delivery_days
    FROM olist.orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date > order_purchase_timestamp
)
SELECT
    COUNT(*) AS eligible_orders,
    ROUND(MIN(delivery_days)::numeric, 2) AS min_days,
    ROUND((PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2) AS p01_days,
    ROUND((PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2) AS p25_days,
    ROUND(AVG(delivery_days)::numeric, 2) AS mean_days,
    ROUND((PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2) AS median_days,
    ROUND((PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2) AS p75_days,
    ROUND((PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2) AS p95_days,
    ROUND((PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2) AS p99_days,
    ROUND(MAX(delivery_days)::numeric, 2) AS max_days,
    COUNT(*) FILTER (WHERE delivery_days > 30) AS over_30_days,
    COUNT(*) FILTER (WHERE delivery_days > 60) AS over_60_days,
    COUNT(*) FILTER (WHERE delivery_days > 90) AS over_90_days
FROM durations;
```

### A2. Recorded statuses and target completeness (2017 onward)

```sql
SELECT
    order_status,
    COUNT(*) AS orders,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date IS NOT NULL
    ) AS with_delivery_timestamp,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date > order_purchase_timestamp
    ) AS positive_delivery_duration,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date IS NULL
    ) AS missing_delivery_timestamp,
    MIN(order_purchase_timestamp) AS first_purchase,
    MAX(order_purchase_timestamp) AS last_purchase
FROM olist.orders
WHERE order_purchase_timestamp >= TIMESTAMP '2017-01-01'
GROUP BY order_status
ORDER BY orders DESC;
```

### A3. Monthly target behavior

```sql
WITH durations AS (
    SELECT
        DATE_TRUNC('month', order_purchase_timestamp)::date AS purchase_month,
        EXTRACT(EPOCH FROM (
            order_delivered_customer_date - order_purchase_timestamp
        )) / 86400.0 AS delivery_days
    FROM olist.orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date > order_purchase_timestamp
)
SELECT
    purchase_month,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(delivery_days)::numeric, 2) AS mean_delivery_days,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2)
        AS median_delivery_days
FROM durations
GROUP BY purchase_month
ORDER BY purchase_month;
```

### A4. Platform estimated date and calendar-day delivery outcomes

```sql
WITH eligible AS (
    SELECT
        order_purchase_timestamp,
        order_delivered_customer_date,
        order_estimated_delivery_date,
        EXTRACT(EPOCH FROM (
            order_delivered_customer_date - order_purchase_timestamp
        )) / 86400.0 AS actual_days,
        EXTRACT(EPOCH FROM (
            order_estimated_delivery_date - order_purchase_timestamp
        )) / 86400.0 AS estimated_days,
        (order_delivered_customer_date::date - order_estimated_delivery_date::date)
            AS calendar_day_difference
    FROM olist.orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date > order_purchase_timestamp
)
SELECT
    COUNT(*) AS eligible_orders,
    COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NOT NULL)
        AS with_estimated_date,
    ROUND(AVG(actual_days)::numeric, 2) AS mean_actual_days,
    ROUND(AVG(estimated_days)::numeric, 2) AS mean_estimated_days,
    COUNT(*) FILTER (WHERE calendar_day_difference < 0) AS early,
    COUNT(*) FILTER (WHERE calendar_day_difference = 0) AS on_estimated_date,
    COUNT(*) FILTER (WHERE calendar_day_difference > 0) AS late,
    ROUND(AVG(calendar_day_difference)::numeric, 2) AS mean_calendar_day_difference,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY calendar_day_difference)
        AS median_calendar_day_difference
FROM eligible;
```

### A5. Cohort assignment and labels crossing the purchase-cohort boundaries

```sql
WITH eligible AS (
    SELECT
        order_id,
        order_purchase_timestamp AS purchased_at,
        order_delivered_customer_date AS delivered_at
    FROM olist.orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date > order_purchase_timestamp
), cohorts AS (
    SELECT *,
        CASE
            WHEN purchased_at >= TIMESTAMP '2017-01-01'
             AND purchased_at < TIMESTAMP '2018-01-01' THEN 'train_2017'
            WHEN purchased_at >= TIMESTAMP '2018-01-01'
             AND purchased_at < TIMESTAMP '2018-03-01' THEN 'validation_jan_feb'
            WHEN purchased_at >= TIMESTAMP '2018-03-01'
             AND purchased_at < TIMESTAMP '2018-05-01' THEN 'refit_mar_apr'
            WHEN purchased_at >= TIMESTAMP '2018-05-01'
             AND purchased_at < TIMESTAMP '2018-09-01' THEN 'test_may_aug'
            ELSE 'excluded'
        END AS cohort
    FROM eligible
)
SELECT
    cohort,
    COUNT(*) AS eventually_delivered,
    COUNT(*) FILTER (WHERE delivered_at < TIMESTAMP '2018-01-01')
        AS labels_by_jan_1,
    COUNT(*) FILTER (WHERE delivered_at < TIMESTAMP '2018-05-01')
        AS labels_by_may_1,
    COUNT(*) FILTER (WHERE delivered_at < TIMESTAMP '2018-09-01')
        AS labels_by_sep_1,
    COUNT(*) FILTER (WHERE delivered_at >= TIMESTAMP '2018-09-01')
        AS labels_after_sep_1
FROM cohorts
GROUP BY cohort
ORDER BY cohort;
```

### A6. Candidate validation-window maturity at May 1

```sql
WITH eligible AS (
    SELECT
        order_id,
        order_purchase_timestamp AS purchased_at,
        order_delivered_customer_date AS delivered_at
    FROM olist.orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date > order_purchase_timestamp
), windows AS (
    SELECT 'Jan-Feb' AS window_name,
           TIMESTAMP '2018-01-01' AS start_at,
           TIMESTAMP '2018-03-01' AS end_at
    UNION ALL
    SELECT 'Jan-Mar', TIMESTAMP '2018-01-01', TIMESTAMP '2018-04-01'
    UNION ALL
    SELECT 'Jan-Apr', TIMESTAMP '2018-01-01', TIMESTAMP '2018-05-01'
)
SELECT
    w.window_name,
    COUNT(e.order_id) AS eventually_delivered,
    COUNT(e.order_id) FILTER (
        WHERE e.delivered_at < TIMESTAMP '2018-05-01'
    ) AS labels_available_may_1,
    COUNT(e.order_id) FILTER (
        WHERE e.delivered_at >= TIMESTAMP '2018-05-01'
    ) AS labels_after_may_1,
    ROUND(100.0 * COUNT(e.order_id) FILTER (
        WHERE e.delivered_at < TIMESTAMP '2018-05-01'
    ) / NULLIF(COUNT(e.order_id), 0), 2) AS completeness_pct
FROM windows w
LEFT JOIN eligible e
    ON e.purchased_at >= w.start_at
   AND e.purchased_at < w.end_at
GROUP BY w.window_name
ORDER BY w.window_name;
```

### A7. Final refit sample count and component reconciliation

```sql
WITH eligible AS (
    SELECT
        order_purchase_timestamp AS purchased_at,
        order_delivered_customer_date AS delivered_at
    FROM olist.orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date > order_purchase_timestamp
      AND order_purchase_timestamp >= TIMESTAMP '2017-01-01'
      AND order_purchase_timestamp < TIMESTAMP '2018-05-01'
      AND order_delivered_customer_date < TIMESTAMP '2018-05-01'
)
SELECT
    CASE
        WHEN purchased_at < TIMESTAMP '2018-01-01' THEN '2017'
        WHEN purchased_at < TIMESTAMP '2018-03-01' THEN '2018 Jan-Feb'
        ELSE '2018 Mar-Apr'
    END AS refit_component,
    COUNT(*) AS available_labels
FROM eligible
GROUP BY 1
ORDER BY 1;
-- Expected component counts: 43,424 + 13,587 + 11,040 = 68,051.
```

### A8. Dataset timestamp bounds and unresolved statuses

```sql
SELECT
    COUNT(*) AS total_orders,
    MAX(order_purchase_timestamp) AS latest_purchase,
    MAX(order_approved_at) AS latest_approval,
    MAX(order_delivered_carrier_date) AS latest_carrier_handoff,
    MAX(order_delivered_customer_date) AS latest_customer_delivery,
    MAX(order_estimated_delivery_date) AS latest_estimated_delivery,
    COUNT(*) FILTER (
        WHERE order_status IN (
            'shipped', 'processing', 'invoiced', 'created', 'approved'
        )
    ) AS intermediate_status_orders,
    COUNT(*) FILTER (
        WHERE order_status = 'delivered'
          AND order_delivered_customer_date IS NULL
    ) AS delivered_missing_timestamp
FROM olist.orders;
```

### A9. Monthly completion and status coverage (January–August 2018)

```sql
SELECT
    DATE_TRUNC('month', order_purchase_timestamp)::date AS purchase_month,
    COUNT(*) AS total_orders,
    COUNT(*) FILTER (
        WHERE order_status = 'delivered'
          AND order_delivered_customer_date > order_purchase_timestamp
    ) AS valid_deliveries,
    COUNT(*) FILTER (
        WHERE order_status IN ('canceled', 'unavailable')
    ) AS canceled_or_unavailable,
    COUNT(*) FILTER (
        WHERE order_status IN (
            'shipped', 'processing', 'invoiced', 'created', 'approved'
        )
    ) AS unresolved,
    COUNT(*) FILTER (
        WHERE order_status = 'delivered'
          AND order_delivered_customer_date IS NULL
    ) AS delivered_missing_timestamp,
    ROUND(100.0 * COUNT(*) FILTER (
        WHERE order_status = 'delivered'
          AND order_delivered_customer_date > order_purchase_timestamp
    ) / NULLIF(COUNT(*), 0), 2) AS valid_delivery_pct
FROM olist.orders
WHERE order_purchase_timestamp >= TIMESTAMP '2018-01-01'
  AND order_purchase_timestamp < TIMESTAMP '2018-09-01'
GROUP BY 1
ORDER BY 1;
```

### Reproduction notes

- PostgreSQL percentile functions (`PERCENTILE_CONT`) interpolate between observations; reported values are rounded for presentation.
- Time-based inclusion uses timestamps, not calendar-day rounding. The estimated-delivery early/on-time/late analysis intentionally uses calendar dates.
- Audit queries are read-only and require no materialized feature table.
- Re-running these queries against a different version of the Olist source or modified ingestion logic can change counts; the reported results correspond to the loaded dataset described above.
- These SQL statements reproduce observational audits. They do **not** substitute for the feature-construction and leakage tests required in later phases.
