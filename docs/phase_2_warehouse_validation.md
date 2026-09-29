# Phase 2 Warehouse Validation

**Project:** Olist E-Commerce Analytics
**Phase:** Phase 2.3
**Status:** Passed
**Validation script:** `sql/warehouse/04_validate_warehouse.sql`

## 1. Purpose

This document records the final validation of the populated PostgreSQL dimensional warehouse. The
validation is read-only and verifies structural integrity, source reconciliation, dimensional
relationships, derived measures, and representative analytical queries.

## 2. Row reconciliation

| Object             | Expected |  Actual | Difference |
|:-------------------|---------:|--------:|-----------:|
| `dim_customer`     |   96,096 |  96,096 |          0 |
| `dim_order_status` |        8 |       8 |          0 |
| `dim_product`      |   32,951 |  32,951 |          0 |
| `dim_seller`       |    3,095 |   3,095 |          0 |
| `fact_order_items` |  112,650 | 112,650 |          0 |
| `fact_orders`      |   99,441 |  99,441 |          0 |
| `fact_payments`    |  103,886 | 103,886 |          0 |
| `fact_reviews`     |   99,224 |  99,224 |          0 |

## 3. Grain integrity

All tested natural grains returned zero duplicate groups:

- `dim_customer(customer_unique_id)`
- `dim_location(zip_code_prefix)`
- `dim_order_status(order_status)`
- `dim_product(product_id)`
- `dim_seller(seller_id)`
- `fact_orders(order_id)`
- `fact_order_items(order_id, order_item_id)`
- `fact_payments(order_id, payment_sequential)`
- `fact_reviews(review_id, order_id)`

## 4. Dimension resolution

Fifteen tested fact-to-dimension relationships returned zero orphan rows, including customer,
customer location, order status, product, seller, and seller location relationships.

## 5. Date integrity

Eleven role-playing date-key checks returned zero invalid mappings. Populated date keys resolve to
`dim_date`, and timestamp-derived date keys agree with the corresponding source timestamp dates.

`dim_date` extends to 2020-04-09 because four source order-item shipping-limit records occur after
2018. They are preserved rather than imputed or rewritten.

## 6. Delivery-derived measures

Across all 99,441 orders:

- invalid derivations for missing deliveries: 0;
- missing derivations when delivery exists: 0;
- invalid late flags: 0;
- invalid `delivery_days`: 0;
- invalid `delivery_delay_days`: 0.

Descriptive source coverage:

- 160 orders lack approval timestamp;
- 1,783 lack carrier timestamp;
- 2,965 lack customer-delivery timestamp;
- 7,827 are late under the warehouse definition;
- 88,649 are on-time or early.

These full-source counts should not be confused with Phase 1 metrics calculated on a restricted
analytical population.

## 7. Financial reconciliation

| Measure    |           Source |        Warehouse | Difference |
|:-----------|-----------------:|-----------------:|-----------:|
| Item price | R\$13,591,643.70 | R\$13,591,643.70 |    R\$0.00 |
| Freight    |  R\$2,251,909.54 |  R\$2,251,909.54 |    R\$0.00 |
| Payments   | R\$16,008,872.12 | R\$16,008,872.12 |    R\$0.00 |

## 8. Geography

`dim_location` contains:

- 19,177 total members;
- 19,015 geolocation-backed members;
- 162 fallback members;
- 518 ambiguous geolocation members under the `(city,state)` pair definition;
- 0 ambiguous fallback members;
- 0 members missing city;
- 0 members missing state.

Fallback locations are actively used by the warehouse:

| Relationship                | Fact rows using fallback |
|:----------------------------|-------------------------:|
| `fact_orders.customer`      |                      278 |
| `fact_order_items.customer` |                      302 |
| `fact_order_items.seller`   |                      253 |
| `fact_payments.customer`    |                      287 |
| `fact_reviews.customer`     |                      279 |

This confirms that fallback members prevent otherwise valid business rows from losing geographic
dimensional context.

## 9. Review preservation

The warehouse contains:

- 99,224 review rows;
- 98,410 distinct `review_id` values;
- 98,673 reviewed orders;
- 551 rows above a one-review-per-order representation;
- 547 multi-review orders;
- 345 multi-review orders with the same score;
- 202 multi-review orders with different scores;
- maximum 3 reviews per order.

Validation found:

- invalid review scores: 0;
- invalid `has_title` flags: 0;
- invalid `has_message` flags: 0.

## 10. Analytical smoke tests

The final warehouse was queried at business-analysis grain to verify that dimensional
transformations did not change established results.

Examples:

- November 2017: 7,289 delivered orders and R\$987,765.37 merchandise revenue.
- Top categories remain `health_beauty` (R\$1,229,557.50), `watches_gifts` (R\$1,163,465.91), and
  `bed_bath_table` (R\$1,022,955.77).
- Late reviewed deliveries average 2.57 stars and +9.44 days relative to the estimate.
- On-time/early reviewed deliveries average 4.30 stars and -12.94 days relative to the estimate.

The state smoke test measures orders by customer state, not unique-customer share, so its
percentages are not expected to equal the Phase 1 unique-customer geography percentages.

## 11. Conclusion

Phase 2 validation passed. The warehouse:

- preserves source fact counts and natural grains;
- has no detected dimensional orphans;
- has valid role-playing date relationships;
- computes delivery fields consistently;
- reconciles monetary measures exactly;
- provides complete customer/seller CEP coverage through documented fallback members;
- preserves atomic review events;
- reproduces established Phase 1 analytical results.

The warehouse is accepted as the validated analytical source for subsequent project phases.
