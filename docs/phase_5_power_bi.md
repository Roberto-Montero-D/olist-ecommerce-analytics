# Phase 5 --- Power BI Business Intelligence

## Objective

Phase 5 turns the validated PostgreSQL `dw` warehouse into an
interactive Power BI report for business monitoring and exploratory
analysis. Power BI consumes the dimensional warehouse rather than
rebuilding source relationships inside the report.

The report contains three pages:

1. **Executive Overview** --- high-level revenue, order, customer,
    fulfillment, category, and geographic performance.
2. **Sales & Customers** --- revenue/order trends, product-category
    performance, customer geography, and payment mix.
3. **Delivery & Customer Experience** --- delivery performance,
    late-delivery patterns, review-score distribution, and the
    relationship between delivery outcome and customer satisfaction.

The Power BI report is stored at:

`powerbi/olist_ecommerce_analytics.pbix`

## Semantic Model

The Power BI model preserves the warehouse fact-constellation design.

### Dimensions

- `dw dim_date`
- `dw dim_customer`
- `dw dim_location`
- `dw dim_order_status`
- `dw dim_product`
- `dw dim_seller`

### Facts

- `dw fact_orders`
- `dw fact_order_items`
- `dw fact_payments`
- `dw fact_reviews`

Relationships are primarily one-to-many, single-direction relationships
from conformed dimensions to facts. Facts are not joined directly to one
another.

The active date role is purchase date. Other warehouse date keys are
retained as inactive role-playing relationships, including approval,
carrier, delivery, estimated-delivery, shipping-limit, review-creation,
and review-answer dates where applicable.

The seller-location relationship on order items is also inactive;
customer location is the active location role used by the report.

This design intentionally prevents arbitrary fact-to-fact filter
propagation. Where a cross-fact calculation is analytically required,
the report uses explicit DAX logic rather than changing the model to
bidirectional filtering.

## Core Measures

The semantic layer includes reusable measures for:

- orders, customers, and order items;
- item revenue, freight, payment value, and revenue plus freight;
- average order value and average items per order;
- delivered and canceled orders and rates;
- late orders, late-delivery rate, delivery duration, and delivery
    delay;
- reviews, reviewed orders, average review score, and
    positive/negative review metrics;
- year-to-date and year-over-year revenue/order analysis;
- delivery-date analysis through the inactive delivery-date
    relationship.

Examples of validated report-level values at the default filter context
include:

  Metric                        Value
  ----------------------- -----------
  Item revenue              R\$13.59M
  Orders                        99.4K
  Customers                     96.1K
  Delivered order rate         97.02%
  Late orders                    7.8K
  Average delivery days         12.56
  Average review score           4.09

Displayed values are rounded by the report formatting; warehouse
validation retains full precision.

### Status-rate semantics

Delivered and canceled order rates intentionally remove the order-status
filter before calculating their numerator and denominator. This prevents
a status selection such as `delivered` from turning the
delivered-order-rate KPI into a misleading 100%.

### Delivery outcome and review score

The delivery and review facts remain separate. To compare customer
satisfaction across delivery outcomes, the report obtains the relevant
order IDs from `dw fact_orders` and applies them to
`dw fact_reviews[order_id]` with `TREATAS`.

At the default report context:

- on-time or early deliveries average approximately **4.29** stars;
- late deliveries average approximately **2.57** stars.

This reproduces the warehouse-level finding that late delivery is
strongly associated with lower submitted review scores. The result is
descriptive and does not establish causality.

## Report Pages

### Executive Overview

![Executive Overview](figures/powerbi/executive_overview.png)

The landing page summarizes the business with:

- item revenue;
- orders;
- customers;
- average order value;
- delivered-order rate;
- monthly item revenue;
- orders by status;
- top product categories by revenue;
- top customer states by orders.

### Sales & Customers

![Sales & Customers](figures/powerbi/sales_customers.png)

This page focuses on commercial activity and customer geography:

- item revenue, orders, customers, and average order value;
- combined revenue and order-volume trend;
- top product categories by revenue;
- top customer states by order volume;
- payment-value mix by payment type.

Category-level tooltips deliberately avoid measures whose denominator
would remain at global order or customer grain. This prevents
technically valid but semantically misleading cross-fact ratios.

### Delivery & Customer Experience

![Delivery & Customer
Experience](figures/powerbi/delivery_customer_experience.png)

This page focuses on fulfillment and review behavior:

- delivered orders and delivered-order rate;
- late orders;
- average delivery days;
- average review score;
- monthly late-delivery-rate trend;
- late-delivery rate by customer state;
- review-score distribution;
- average review score for on-time/early versus late deliveries.

## Filtering and Interactions

All pages provide a shared **Date Range** slicer and **Order Status**
slicer, plus report-page navigation.

The report was tested for filter-context behavior rather than relying
blindly on Power BI's default cross-highlighting. Important design
decisions include:

- date and order-status slicers act as the primary report controls;
- single-direction warehouse relationships are preserved;
- product-category selections do not justify artificial bidirectional
    fact filtering;
- customer geography can legitimately filter multiple facts through
    the shared location dimension;
- review-score selection does not filter delivery facts backward;
- interactions that produce misleading cross-fact interpretations are
    disabled where appropriate.

## Time-Period Handling

The source contains a very small transaction tail after August 2018.
Monthly transaction/revenue trend visuals therefore use a date flag that
limits those charts to complete transaction months through **August
2018**.

The underlying records remain in the model and are not deleted.
Report-level KPIs retain the full available date range unless explicitly
filtered.

## Validation

Phase 5 was checked against the validated warehouse and against direct
Power BI filter behavior.

Key checks included:

- base KPI reconciliation with warehouse totals;
- status-rate behavior under order-status selections;
- monthly trend cutoff behavior;
- category and geographic grain checks;
- tooltip denominator checks;
- date-slicer propagation across delivery and review visuals;
- order-status propagation;
- cross-fact delivery/review calculations;
- chart interaction behavior under the fact-constellation model.

The Power BI model therefore remains consistent with the dimensional
design documented in
[`phase_2_dimensional_model.md`](phase_2_dimensional_model.md) and the
architecture documented in
[`phase_4_system_architecture.md`](phase_4_system_architecture.md).

## Portfolio Artifacts

- [Power BI report](../powerbi/olist_ecommerce_analytics.pbix)
- [Executive Overview
    screenshot](figures/powerbi/executive_overview.png)
- [Sales & Customers screenshot](figures/powerbi/sales_customers.png)
- [Delivery & Customer Experience
    screenshot](figures/powerbi/delivery_customer_experience.png)

## Phase 5 Status

**Complete.**

The project now has a validated analytical path from immutable source
data through PostgreSQL, dimensional modeling, Python analysis, and an
interactive Power BI reporting layer.
