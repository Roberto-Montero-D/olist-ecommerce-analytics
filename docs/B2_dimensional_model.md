# B2 — Dimensional Modeling & Data Warehouse

**Project:** Olist E-Commerce Analytics
**Status:** Complete / validated
**Database:** PostgreSQL
**Model:** Fact constellation (galaxy) using conformed dimensions

## 1. Objective

B2 transforms the validated Olist source layer into a reusable analytical warehouse for SQL, Python,
Power BI, and later machine-learning work.

The model preserves the natural grain of orders, items, payments, and reviews instead of flattening
multiple business processes into one table. This prevents fan-out and accidental double-counting.

## 2. Modeling principles

- The `olist` source schema remains immutable.
- Facts do not use fact-to-fact foreign keys.
- Shared business entities are represented by conformed dimensions.
- `order_id` is retained as a degenerate identifier; no `dim_order` is created.
- Warehouse entity keys are surrogate integers.
- Durable source identifiers remain available as business keys.
- `dim_date.date_key` uses `YYYYMMDD`.
- CEP prefixes are five-character identifiers and retain leading zeroes.
- Geographic canonicalization is deterministic and auditable.
- Reviews preserve their source event grain.

## 3. Dimensions

| Dimension             | Grain                     | Final rows |
|:----------------------|:--------------------------|-----------:|
| `dw.dim_date`         | One calendar date         |      1,314 |
| `dw.dim_customer`     | One `customer_unique_id`  |     96,096 |
| `dw.dim_location`     | One five-digit CEP prefix |     19,177 |
| `dw.dim_product`      | One product               |     32,951 |
| `dw.dim_seller`       | One seller                |      3,095 |
| `dw.dim_order_status` | One order status          |          8 |

### `dw.dim_date`

Role-playing date dimension for purchase, approval, carrier handoff, customer delivery, estimated
delivery, shipping limit, review creation, and review answer dates.

The generated range is 2016-09-04 through 2020-04-09. The 2020 upper boundary is caused by four
preserved source `order_items.shipping_limit_date` rows: one on 2020-02-03, one on 2020-02-05, and
two on 2020-04-09. No inferred correction is applied.

### `dw.dim_customer`

Grain is persistent `customer_unique_id`, not order-level `customer_id`.

Customer geography is deliberately excluded because persistent customers can appear under different
transaction locations. Location is attached to fact context instead.

### `dw.dim_location`

Grain is one five-digit CEP prefix.

Raw geolocation contains 1,000,163 observations but only 19,015 distinct prefixes, so it is not
directly usable as a conventional one-row-per-location dimension.

Canonicalization:

1. remove diacritics with PostgreSQL `unaccent`;
2. lowercase;
3. normalize punctuation/separators to spaces;
4. collapse/trim whitespace;
5. uppercase/trim state;
6. count normalized `(city,state)` candidates;
7. choose the modal pair;
8. break ties by normalized state then normalized city;
9. choose the most frequent raw city spelling within the winning pair, with lexical tie-breaking;
10. use CEP-level median latitude/longitude.

Validation distinguishes two ambiguity definitions:

- 513 prefixes contain multiple normalized cities;
- 518 prefixes contain multiple normalized `(city,state)` pairs.

`is_ambiguous` uses the broader pair-level definition. Source and warehouse pair-level ambiguity
counts are both 518 with zero mismatched prefixes.

The final dimension contains:

- 19,015 geolocation-backed prefixes;
- 162 fallback prefixes absent from geolocation;
- 155 fallback prefixes used only by customers;
- 5 used only by sellers;
- 2 used by both;
- 0 ambiguous fallback prefixes;
- 0 fallback prefixes missing city/state.

Fallback locations retain source customer/seller city/state and have NULL coordinates rather than
causing business rows to be dropped.

### `dw.dim_product`

One row per `product_id`, including Portuguese category and available English translation. Missing
or untranslated categories are preserved.

### `dw.dim_seller`

One row per `seller_id`. Seller location is contextualized through `seller_location_key` on the
order-item fact.

### `dw.dim_order_status`

One row per distinct source order status.

## 4. Facts

| Fact                  | Grain                                    | Final rows |
|:----------------------|:-----------------------------------------|-----------:|
| `dw.fact_orders`      | One `order_id`                           |     99,441 |
| `dw.fact_order_items` | One `(order_id, order_item_id)`          |    112,650 |
| `dw.fact_payments`    | One `(order_id, payment_sequential)`     |    103,886 |
| `dw.fact_reviews`     | One `(review_id, order_id)` review event |     99,224 |

### `dw.fact_orders`

Carries customer, transaction location, status, role-playing date keys, lifecycle timestamps, and
derived delivery measures.

Derived measures:

- `delivery_days`: actual customer delivery minus purchase timestamp;
- `delivery_delay_days`: actual delivery minus estimated delivery;
- `is_late_delivery`: actual delivery later than estimated delivery.

These fields remain NULL when actual customer delivery is unavailable.

### `dw.fact_order_items`

Preserves item-position grain and carries product, seller, customer, customer location, seller
location, status, purchase date, shipping-limit date, price, and freight.

### `dw.fact_payments`

Preserves payment-sequence grain and stores payment type, installments, and payment value with
conformed order context.

### `dw.fact_reviews`

Preserves every raw review event.

The source/warehouse contains:

- 99,224 review rows;
- 98,410 distinct review IDs;
- 98,673 reviewed orders;
- 547 orders with multiple review rows;
- 345 multi-review orders with the same score;
- 202 multi-review orders with different scores;
- maximum 3 reviews for one order.

Collapsing reviews to one row per order during warehouse loading would therefore destroy source
information.

## 5. Final validation

B2.3 validates:

- exact row-count reconciliation;
- natural-grain uniqueness;
- dimension/FK resolution;
- role-playing date-key integrity;
- delivery-derived fields;
- financial reconciliation;
- geographic coverage;
- review preservation;
- analytical smoke tests.

All tested structural/error metrics returned zero.

Financial reconciliation:

| Measure    |           Source |        Warehouse | Difference |
|:-----------|-----------------:|-----------------:|-----------:|
| Item price | R\$13,591,643.70 | R\$13,591,643.70 |    R\$0.00 |
| Freight    |  R\$2,251,909.54 |  R\$2,251,909.54 |    R\$0.00 |
| Payments   | R\$16,008,872.12 | R\$16,008,872.12 |    R\$0.00 |

Analytical smoke tests reproduce the established B1 monthly revenue/category results and the
delivery-satisfaction relationship.

## 6. SQL execution order

``` text
00_validate_dimensional_design.sql
01_create_warehouse_schema.sql
02_load_dimensions.sql
02b_validate_loaded_dimensions.sql
03_load_facts.sql
04_validate_warehouse.sql
```

## 7. Phase conclusion

B2 is complete and frozen. The PostgreSQL warehouse preserves source grains, resolves reusable
dimensions, prevents raw-geolocation fan-out, retains multi-review events, and reconciles exactly to
the source for fact counts and financial measures.

The validated `dw` schema is ready to serve as the analytical source for the next project phase.
