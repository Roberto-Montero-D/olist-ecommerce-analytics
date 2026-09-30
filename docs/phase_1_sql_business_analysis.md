# Phase 1 — SQL Business Analysis

## Olist E-Commerce Analytics

**Status:** Complete
**Database:** PostgreSQL
**Source:** Olist Brazilian E-Commerce Public Dataset
**Analytical period:** January 1, 2017 through August 31, 2018

----------------------------------------------------------------------------------------------------

## 1. Objective

Phase 1 establishes a reproducible descriptive understanding of the Olist marketplace before dimensional
modeling, BI, and machine learning.

The analysis covers four business areas:

1. Orders and revenue
2. Products and sellers
3. Customers and geography
4. Delivery performance and customer satisfaction

The SQL analyses are stored in:

- `sql/analysis/01_orders_revenue.sql`
- `sql/analysis/02_products_sellers.sql`
- `sql/analysis/03_customers_geography.sql`
- `sql/analysis/04_delivery_satisfaction.sql`

Source-data validation is maintained separately in `sql/analysis/00_validate_source.sql`.

----------------------------------------------------------------------------------------------------

## 2. Analytical Scope and Definitions

### 2.1 Analytical period

The source dataset extends approximately from September 2016 through October 2018. The edge periods
are not equally suitable for direct monthly comparison: 2016 activity is sparse and discontinuous,
while September and October 2018 do not provide comparable delivered-order coverage.

Comparable Phase 1 business-performance analysis therefore uses:

`2017-01-01 <= order_purchase_timestamp < 2018-09-01`

This corresponds to January 2017 through August 2018. Records outside this interval remain preserved
in the source database; the restriction is analytical rather than a data-cleaning operation.

### 2.2 Delivered orders

Revenue, product-sales, seller-performance, customer-purchase, and delivery analyses generally use
delivered orders. Other lifecycle states remain preserved in the source database.

The complete source order-status distribution is:

| Status      | Orders |
|:------------|-------:|
| delivered   | 96,478 |
| shipped     |  1,107 |
| canceled    |    625 |
| unavailable |    609 |
| invoiced    |    314 |
| processing  |    301 |
| created     |      5 |
| approved    |      2 |

### 2.3 Core business metrics

**Product revenue** is the sum of `order_items.price` for delivered orders. Freight is excluded.
Product revenue represents merchandise sales value, not profit; the dataset does not contain the
costs required to calculate margins.

**Freight charged** is the sum of `order_items.freight_value`.

**Items sold** is the number of order-item rows associated with delivered orders.

**Merchandise average order value (AOV)** is product revenue divided by delivered orders. Freight is
excluded.

### 2.4 Customer identity

Olist contains two customer identifiers with different meanings.

`customer_id` identifies the customer record associated with a particular order. The source customer
table contains 99,441 distinct values.

`customer_unique_id` represents persistent customer identity across orders. The source contains
96,096 distinct persistent identities.

All repeat-purchase and unique-customer analyses therefore use `customer_unique_id`.

----------------------------------------------------------------------------------------------------

## 3. Phase 1.1 — Orders and Revenue

### 3.1 Objective

The orders and revenue analysis establishes the marketplace’s temporal business profile through
order status, monthly delivered orders, item volume, product revenue, freight charges, merchandise
AOV, and month-over-month changes.

### 3.2 Key findings

Marketplace activity varied substantially during the analytical period.

November 2017 showed one of the strongest increases:

- Delivered orders increased approximately **62.77%**.
- Product revenue increased approximately **52.37%**.
- Merchandise AOV decreased from approximately **R\$144.76 to R\$135.51**.

The simultaneous increase in order volume and decrease in AOV indicates that the revenue increase
was associated primarily with higher transaction volume rather than higher merchandise value per
order. No causal explanation is assigned from the Olist data alone.

Other months illustrate why order growth and revenue growth should be evaluated separately.

In September 2017:

- Orders decreased approximately **1.03%**.
- Product revenue increased approximately **9.50%**.
- AOV increased from approximately **R\$132.29 to R\$146.36**.

In August 2018:

- Orders increased approximately **3.12%**.
- Product revenue decreased approximately **3.38%**.
- AOV decreased from approximately **R\$140.92 to R\$132.04**.

These results show that marketplace revenue reflects both transaction volume and transaction value.

----------------------------------------------------------------------------------------------------

## 4. Phase 1.2 — Products and Sellers

### 4.1 Product-category performance

Product category names originate in Portuguese and are translated through the category translation
table. Because translation coverage is incomplete, the analysis preserves untranslated and missing
categories rather than dropping them.

The five largest categories by delivered product revenue were:

| Revenue Rank | Category              | Orders |  Items | Product Revenue | Avg. Item Price |
|--------------|:----------------------|-------:|-------:|----------------:|----------------:|
| 1            | health_beauty         |  8,610 |  9,422 | R\$1,229,557.50 |       R\$130.50 |
| 2            | watches_gifts         |  5,491 |  5,855 | R\$1,163,465.91 |       R\$198.71 |
| 3            | bed_bath_table        |  9,267 | 10,945 | R\$1,022,955.77 |        R\$93.46 |
| 4            | sports_leisure        |  7,513 |  8,414 |   R\$952,840.40 |       R\$113.24 |
| 5            | computers_accessories |  6,518 |  7,632 |   R\$888,055.59 |       R\$116.36 |

### Category concentration

- Top 5 categories: **39.88%** of product revenue
- Top 8 categories: **54.52%**
- Top 10 categories: **62.47%**
- Top 15 categories: **76.33%**

The largest individual category, `health_beauty`, represented **9.33%** of product revenue. Category
revenue is therefore concentrated among leading categories without being dominated by a single
category.

### Volume and price profiles

Revenue leadership arises from different combinations of sales volume and average selling price.

`health_beauty` ranked first in revenue and second in item volume, but only 31st in average item
price, indicating a predominantly volume-driven revenue profile.

`bed_bath_table` ranked third in revenue and first in volume while ranking 47th in average item
price, providing another strong example of volume-driven revenue.

`watches_gifts` ranked second in revenue, seventh in volume, and tenth in average item price,
combining substantial volume with relatively high prices.

`telephony` ranked eighth in volume but only 14th in revenue and 64th in average item price,
illustrating how lower prices can limit revenue despite high unit sales.

----------------------------------------------------------------------------------------------------

### 4.2 Seller performance

Seller analysis is performed at seller grain. Because an individual marketplace order can contain
products from multiple sellers, seller-level order counts represent orders in which each seller
participated and cannot be summed to obtain marketplace-wide order totals.

The highest-revenue seller generated **R\$226,987.93**, or **1.72%** of total delivered product
revenue.

The second-highest revenue seller generated **R\$217,940.44** from only 348 orders and 400 items,
with an average item price of **R\$544.85**.

By contrast, the highest-volume seller among the leading sellers participated in 1,819 orders and
sold 1,996 items but generated **R\$120,702.83**, ranking only 11th by revenue. Its average item
price was **R\$60.47**.

These contrasting profiles show that seller revenue can arise from high volume, high item prices, or
combinations of both. Revenue rank is therefore not an overall measure of seller quality.

### Seller revenue concentration

There were **2,945 active sellers** in the analytical population.

| Revenue Threshold | Sellers Required | Share of Active Sellers |
|------------------:|-----------------:|------------------------:|
|               25% |               28 |                   0.95% |
|               50% |              127 |                   4.31% |
|               75% |              424 |                  14.40% |
|               90% |              885 |                  30.05% |

Only **127 sellers (4.31%) generated 50% of delivered product revenue**, while **885 sellers
(30.05%) generated 90%**.

The marketplace therefore shows substantial seller-level revenue concentration. However, the leading
individual seller contributes only 1.72%, indicating concentration among a relatively small group
rather than dominance by a single seller.

----------------------------------------------------------------------------------------------------

## 5. Phase 1.3 — Customers and Geography

### 5.1 Geographic distribution

Customer activity is strongly concentrated geographically.

São Paulo represented:

- **39,065 unique customers**.
- **41.94% of the customer population**.
- **40,406 delivered orders**.
- approximately **R\$5.06 million in product revenue**
- **38.36% of total product revenue**.

Rio de Janeiro represented **12.75%** of customers and **13.29%** of revenue, while Minas Gerais
represented **11.78%** of customers and **11.75%** of revenue.

Together, SP, RJ, and MG accounted for **66.47% of customers** and **63.40% of product revenue**.

### Market size and spending intensity

São Paulo dominates total revenue through scale, but its product revenue per delivered order was
approximately **R\$125.12**.

Several much smaller states showed higher values:

- PB: **R\$218.09/order**
- AP: **R\$199.62/order**
- AC: **R\$199.14/order**
- AL: **R\$199.00/order**

These values should be interpreted alongside sample size. Smaller states have substantially fewer
orders, making their averages less stable and their overall marketplace impact much smaller.

----------------------------------------------------------------------------------------------------

### 5.2 Repeat-purchase behavior

Within the analytical period:

- Unique customers: **93,104**
- One-time customers: **90,315**
- Repeat customers: **2,789**
- Repeat-customer share: **3.00%**
- Average delivered orders per customer: **1.03**
- Maximum delivered orders observed for one customer: **15**

### Purchase-frequency distribution

| Delivered Orders | Customers | Customer Share |
|-----------------:|----------:|---------------:|
|                1 |    90,315 |         97.00% |
|                2 |     2,562 |          2.75% |
|                3 |       180 |          0.19% |
|                4 |        28 |          0.03% |
|                5 |         9 |          0.01% |
|                6 |         5 |          0.01% |
|                7 |         3 |        \<0.01% |
|                9 |         1 |        \<0.01% |
|               15 |         1 |        \<0.01% |

Purchasing is therefore predominantly one-time within the observed period. Even among repeat
customers, most made only two delivered purchases.

### Interpretation limitation

The **3.00%** figure describes repeat purchasing within the analytical period and is not a formal
retention rate.

Customers entered the dataset at different dates and therefore had unequal opportunities to make
subsequent purchases. A formal retention analysis would require time-aware cohorts and comparable
observation windows.

----------------------------------------------------------------------------------------------------

## 6. Phase 1.4 — Delivery and Customer Satisfaction

### 6.1 Overall delivery performance

Among **96,203 delivered orders with known customer-delivery timestamps**:

- Average delivery time: **12.54 days**
- Median delivery time: **10.21 days**
- 90th percentile delivery time: **23.06 days**
- On-time or early orders: **88,381**
- Late orders: **7,822**
- Late-delivery rate: **8.13%**

The mean exceeds the median, indicating a right-tailed delivery-time distribution in which longer
deliveries pull the average upward.

### 6.2 Geographic delivery performance

Delivery performance varies substantially across customer states.

| State | Delivered Orders | Avg. Delivery Days | Median Days | Late % |
|:------|-----------------:|-------------------:|------------:|-------:|
| SP    |           40,399 |               8.74 |        7.20 |  5.90% |
| MG    |           11,319 |              11.98 |       10.31 |  5.63% |
| RJ    |           12,310 |              15.30 |       12.04 | 13.52% |
| BA    |            3,253 |              19.33 |       16.91 | 14.05% |
| MA    |              713 |              21.54 |       19.18 | 19.64% |
| AL    |              396 |              24.52 |       22.33 | 23.99% |

São Paulo combines the largest customer population with comparatively fast delivery.

Absolute delivery duration and lateness relative to the promised date are different measures. A
region can have longer delivery times without an equally high late rate when customers were
originally given longer delivery estimates.

State-level percentages should also be interpreted in light of sample size.

----------------------------------------------------------------------------------------------------

### 6.3 Review-score distribution

| Review Score | Reviews |  Share |
|-------------:|--------:|-------:|
|            1 |  11,424 | 11.51% |
|            2 |   3,151 |  3.18% |
|            3 |   8,179 |  8.24% |
|            4 |  19,142 | 19.29% |
|            5 |  57,328 | 57.78% |

Overall:

- 4–5 star reviews: **77.07%**
- 1–2 star reviews: **14.69%**

Submitted reviews are predominantly positive.

----------------------------------------------------------------------------------------------------

### 6.4 Delivery performance and satisfaction

Because review data is not strictly one row per order, review records were aggregated to order level
before comparison with delivery information. Phase 1 uses the mean of all submitted review scores
within each order. Phase 3 instead uses the latest review event per order for its satisfaction
analyses, so small differences in review-derived metrics between the two phases are expected.

The resulting relationship was:

| Delivery Status | Reviewed Orders | Avg. Review | Positive Reviews | Negative Reviews |
|:----------------|----------------:|------------:|-----------------:|-----------------:|
| Late            |           7,658 |        2.57 |           34.57% |           53.98% |
| On time / early |          87,902 |        4.30 |           82.79% |            9.17% |

Late delivery is strongly associated with lower customer satisfaction in the observed data.

### Satisfaction by degree of delay

| Delivery Timing | Reviewed Orders | Avg. Review | Negative Reviews |
|:----------------|----------------:|------------:|-----------------:|
| 7+ days early   |          70,673 |        4.32 |            8.92% |
| 0–7 days early  |          17,229 |        4.20 |           10.19% |
| 1–3 days late   |           2,635 |        3.77 |           19.09% |
| 4–7 days late   |           1,773 |        2.32 |           61.25% |
| 8+ days late    |           3,250 |        1.73 |           78.31% |

The relationship becomes substantially stronger as delay increases.

Orders delivered 1–3 days late still averaged **3.77 stars**, but orders delivered 4–7 days late
averaged **2.32**, with **61.25%** receiving negative reviews. At 8 or more days late, average
review score fell to **1.73** and **78.31%** of reviewed orders received a 1–2 star rating.

The appropriate descriptive conclusion is that **customer satisfaction is strongly associated with
delivery performance in the Olist dataset**. This observational analysis does not establish that
delivery delay alone caused lower review scores.

----------------------------------------------------------------------------------------------------

## 7. Cross-Analysis Findings

### 7.1 Marketplace demand is geographically concentrated

São Paulo accounts for approximately **42% of unique customers** and **38% of delivered product
revenue**. SP, RJ, and MG together represent **66.47% of customers** and **63.40% of product
revenue**.

### 7.2 Product revenue is concentrated but category-diversified

The top 15 categories generate **76.33%** of delivered product revenue, but the largest individual
category contributes only **9.33%**.

Different categories reach high revenue through different combinations of item volume and selling
price.

### 7.3 Seller revenue is substantially concentrated

Only **127 of 2,945 active sellers (4.31%)** generate half of delivered product revenue.
Nevertheless, the largest individual seller represents only **1.72%**, so concentration is
distributed across a group of leading sellers rather than a single dominant seller.

### 7.4 Repeat purchasing is uncommon

Approximately **97%** of customers make only one delivered purchase during the analytical period,
while **3%** make multiple purchases. This is a repeat-purchase measurement rather than a formal
retention rate.

### 7.5 Delivery performance has a strong relationship with satisfaction

On-time or early deliveries average **4.30 stars**, compared with **2.57** for late deliveries.

For orders delivered eight or more days after the estimated date, the average review falls to **1.73
stars** and **78.31%** of reviews are negative.

This relationship provides a potentially useful direction for later predictive modeling, although
the machine-learning target is not frozen at this stage.

----------------------------------------------------------------------------------------------------

## 8. Analytical Limitations

Phase 1 is descriptive and should be interpreted within the limitations of the source data.

1. The dataset covers a finite historical period and does not represent the complete lifetime
    history of each customer.

2. Sparse edge periods are excluded from comparable business-performance analysis but remain
    preserved in the source database.

3. Product revenue excludes freight and does not represent profit.

4. Product costs and seller margins are unavailable.

5. Repeat-purchase percentages are not formal customer-retention rates.

6. Not every order has a review, so review-based analyses reflect the subset of orders with
    submitted ratings.

7. Delivery and review relationships are observational and do not establish causality.

8. Geographic populations differ substantially in size, so comparisons of averages and percentages
    require sample-size context.

9. Raw geolocation contains multiple observations per ZIP-code prefix and is not directly joined to
    order facts without first defining an appropriate geographic representation.

10. Seller revenue rankings measure sales contribution rather than seller quality or profitability.

----------------------------------------------------------------------------------------------------

## 9. Phase Conclusion

Phase 1 establishes a reproducible SQL-based business profile of the Olist marketplace.

The analysis identifies a marketplace characterized by:

- strong geographic concentration,
- meaningful but distributed product-category concentration,
- substantial seller-revenue concentration,
- predominantly one-time customer purchasing,
- generally positive submitted reviews,
- and a strong negative association between delivery delays and customer satisfaction.

These findings also establish the business definitions and analytical constraints required for
subsequent project phases.

The next phase, **Phase 2 — Dimensional Modeling and Data Warehouse**, will transform the normalized
source data into a reusable analytical fact-and-dimension model for reporting, BI, and downstream
analytics.
