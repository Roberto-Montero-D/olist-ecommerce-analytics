# Phase 3 — Python Exploratory Data Analysis

**Project:** Olist E-Commerce Analytics
**Status:** Complete
**Source:** validated PostgreSQL `dw` dimensional warehouse
**Primary analytical period:** January 1, 2017 through August 31, 2018
**Primary population:** delivered orders

## 1. Objective

Phase 3 uses Python as the analytical layer on top of the validated Phase 2 warehouse. The phase is designed
to add exploratory and statistical interpretation without bypassing the warehouse or reloading raw
CSV files.

The notebook is `notebooks/01_warehouse_eda.ipynb`.

## 2. Analytical design

The master analytical table has one row per order. Lower-grain facts are aggregated before merging:

- `fact_order_items` → order-level item, seller, revenue, and freight measures;
- `fact_payments` → order-level payment measures;
- `fact_reviews` → order-level review-event summary while retaining first/latest review semantics.

Every merge uses one-to-one validation. The resulting master table preserves 99,441 unique orders
with zero duplicate `order_id` values.

Expected source relationships remain missing rather than being imputed:

- 775 orders have no item rows;
- 1 order has no payment rows;
- 768 orders have no review events.

## 3. Marketplace evolution

The controlled delivered-order population contains 96,211 orders purchased from January 2017 through
August 2018.

November 2017 is a notable high-volume month:

| Metric              |      Oct 2017 |      Nov 2017 | MoM change |
|:--------------------|--------------:|--------------:|-----------:|
| Delivered orders    |         4,478 |         7,289 |    +62.77% |
| Merchandise revenue | R\$648,247.65 | R\$987,765.37 |    +52.37% |
| Merchandise AOV     |     R\$144.76 |     R\$135.51 |     -6.39% |

The revenue surge is therefore associated primarily with increased order volume rather than
increased order value. This is descriptive, not a causal claim about promotions or external events.

Early-2017 percentage growth is interpreted cautiously because it starts from a much smaller
activity base.

## 4. Category concentration

The leading categories by delivered merchandise revenue are:

1. `health_beauty` — R\$1,229,557.50
2. `watches_gifts` — R\$1,163,465.91
3. `bed_bath_table` — R\$1,022,955.77

Revenue concentration:

| Category group | Share of merchandise revenue |
|:---------------|-----------------------------:|
| Top 5          |                       39.88% |
| Top 8          |                       54.52% |
| Top 10         |                       62.47% |
| Top 15         |                       76.33% |

## 5. Seller concentration

There are 2,945 active sellers in the analytical population.

| Cumulative revenue share | Sellers required |
|:-------------------------|-----------------:|
| 25%                      |               28 |
| 50%                      |              127 |
| 75%                      |              424 |
| 90%                      |              885 |

Only 127 sellers, about 4.3% of active sellers, account for half of merchandise revenue. However,
the largest individual seller contributes only 1.72%.

The marketplace is therefore concentrated across a relatively small seller segment without being
dominated by a single seller.

## 6. Delivery performance and customer satisfaction

The controlled delivery/review population contains 95,560 orders:

- 87,902 on-time or early;
- 7,658 late.

| Delivery outcome | Orders | Avg latest review | Positive reviews | Negative reviews |
|:-----------------|-------:|------------------:|-----------------:|-----------------:|
| On-time / early  | 87,902 |              4.29 |           82.81% |            9.20% |
| Late             |  7,658 |              2.57 |           34.55% |           54.06% |

Review outcomes worsen with delay severity:

| Delivery performance | Orders | Avg latest review | Negative reviews |
|:---------------------|-------:|------------------:|-----------------:|
| ≥7d early            | 70,690 |              4.32 |            8.95% |
| \<7d early / on time | 17,218 |              4.20 |           10.23% |
| ≤3d late             |  2,633 |              3.76 |           19.22% |
| 3–7d late            |  1,773 |              2.32 |           61.31% |
| \>7d late            |  3,246 |              1.73 |           78.47% |

The observed negative-review rate is 54.06% for late deliveries versus 9.20% for on-time/early
deliveries. This corresponds to:

- observed risk ratio: **5.88×**;
- absolute difference: **44.86 percentage points**;
- Spearman rank correlation between delivery delay and latest review score: **ρ = -0.177, p \<
  0.001**.

The rank correlation is negative but not large at the individual-order level. The categorical
severity analysis nevertheless shows a pronounced deterioration in review outcomes as delays become
larger.

These are observational associations and do not establish that lateness alone caused review
outcomes.

## 7. Geography and repeat purchasing

Order-level geography is measured by the customer’s transaction location. The leading states are São
Paulo, Rio de Janeiro, and Minas Gerais; São Paulo accounts for roughly 42% of delivered orders in
the controlled analytical period.

Persistent customer identity uses `customer_unique_id`. Approximately 3% of observed customers
placed more than one delivered order during the analytical period, with average orders per customer
near 1.03.

This is described as repeat purchasing, not a retention rate. A retention metric would require an
explicit cohort definition, eligibility window, and return period.

## 8. Figures

The cleaned notebook saves formal, presentation-ready figures to `docs/figures/`:

- `phase_3_monthly_revenue.png`
- `phase_3_top_categories.png`
- `phase_3_seller_concentration.png`
- `phase_3_delivery_review_score.png`
- `phase_3_orders_by_state.png`

The plots intentionally use restrained Matplotlib formatting: clear labels, light reference grids,
direct annotations only where they add analytical value, and no decorative theme.

## 9. Phase 3 conclusions

Phase 3 confirms that the dimensional warehouse can serve as a reliable Python analytical source without
fact-grain fanout.

The strongest business findings are:

- marketplace growth during the analytical period is primarily associated with order-volume
  expansion;
- category and seller revenue are meaningfully concentrated;
- seller concentration is distributed rather than dependent on one dominant seller;
- delivery lateness is strongly associated with poorer review outcomes and worsens with delay
  severity;
- marketplace activity is geographically concentrated;
- repeat purchasing is uncommon in the observed window.

Phase 5 will translate these validated metrics into Power BI. Phase 6 will later treat late-delivery
prediction as a separate predictive problem with explicit causal-availability and leakage controls.
