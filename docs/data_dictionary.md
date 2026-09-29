# Source Data Dictionary

## Purpose

This document describes the structure, grain, keys, relationships,
and known data-quality characteristics of the raw Olist Brazilian
E-Commerce dataset used by this project.

The definitions in this document are based on both the published
dataset structure and programmatic validation of the raw source files.

Raw source data is treated as immutable. Data-quality issues identified
here are preserved in the raw layer and handled explicitly in downstream
transformations.

### Postal Prefix Representation

The Olist files expose the first five digits of the Brazilian CEP rather than
the complete eight-digit CEP. These fields are identifiers, not numeric
measures. The source CSVs preserve leading zeroes (for example, `01037`), so
ZIP/CEP-prefix columns are read as five-character strings in Python and stored
as `CHAR(5)` in PostgreSQL. Downstream transformations must preserve this
representation; converting the prefix to an integer would discard significant
leading zeroes.

City names remain unchanged in the immutable source layer. Any case, accent,
whitespace, or punctuation normalization used to evaluate geographic
ambiguity is derived downstream and must retain the original city value for
traceability.

---

## Dataset Overview

| Table | Rows | Grain | Candidate Key |
|---|---:|---|---|
| customers | 99,441 | One customer record associated with an order | `customer_id` |
| orders | 99,441 | One order | `order_id` |
| order_items | 112,650 | One item position within an order | (`order_id`, `order_item_id`) |
| order_payments | 103,886 | One payment sequence within an order | (`order_id`, `payment_sequential`) |
| order_reviews | 99,224 | One review record associated with an order | (`review_id`, `order_id`) |
| products | 32,951 | One product | `product_id` |
| sellers | 3,095 | One seller | `seller_id` |
| geolocation | 1,000,163 | One geographic observation for a ZIP-code prefix | No unique raw key |
| category_translation | 71 | One category translation | `product_category_name` |

---

## 1. Customers

**Source file:** `olist_customers_dataset.csv`

**Grain:** One customer record associated with one order.

**Candidate primary key:** `customer_id`

**Relationships:**

- Referenced by `orders.customer_id`.
- `customer_zip_code_prefix` can be associated with
  `geolocation.geolocation_zip_code_prefix`, but the raw geolocation
  table contains multiple rows per ZIP-code prefix.

### Important Identity Distinction

`customer_id` identifies the customer record associated with an order.
It should not be interpreted as a persistent customer identity.

`customer_unique_id` identifies the same customer across multiple
orders and should therefore be used for repeat-customer, retention,
RFM, and customer-level analyses.

### Columns

| Column | Raw Type | Nullable | Description |
|---|---|---:|---|
| customer_id | string | No | Order-level customer identifier |
| customer_unique_id | string | No | Persistent customer identifier across orders |
| customer_zip_code_prefix | string (5 digits) | No | First five digits of the customer CEP; leading zeroes are significant |
| customer_city | string | No | Customer city |
| customer_state | string | No | Customer state |

### Validated Characteristics

- 99,441 rows and 5 columns.
- `customer_id` is unique, with 99,441 distinct values.
- 96,096 distinct `customer_unique_id` values.
- No exact duplicate rows.
- No missing values.
- Every `orders.customer_id` references an existing customer record.

---

## 2. Orders

**Source file:** `olist_orders_dataset.csv`

**Grain:** One order.

**Candidate primary key:** `order_id`

**Foreign key:**

- `customer_id` → `customers.customer_id`

**Relationships:**

- Referenced by `order_items.order_id`.
- Referenced by `order_payments.order_id`.
- Referenced by `order_reviews.order_id`.

### Columns

| Column | Raw Type | Nullable | Description |
|---|---|---:|---|
| order_id | string | No | Unique order identifier |
| customer_id | string | No | Customer record associated with the order |
| order_status | string | No | Recorded order status |
| order_purchase_timestamp | string | No | Order purchase timestamp |
| order_approved_at | string | Yes | Order/payment approval timestamp |
| order_delivered_carrier_date | string | Yes | Timestamp when the order was delivered to the carrier |
| order_delivered_customer_date | string | Yes | Timestamp when the order was delivered to the customer |
| order_estimated_delivery_date | string | No | Estimated customer delivery timestamp |

### Validated Characteristics

- 99,441 rows and 8 columns.
- `order_id` is unique, with 99,441 distinct values.
- No exact duplicate rows.
- Every `customer_id` references an existing customer record.
- 160 missing `order_approved_at` values.
- 1,783 missing `order_delivered_carrier_date` values.
- 2,965 missing `order_delivered_customer_date` values.
- 775 orders have no corresponding item records.
- 1 order has no corresponding payment record.
- 768 orders have no corresponding review record.

### Orders Without Item Records

The 775 orders without items have the following statuses:

| Status | Orders |
|---|---:|
| unavailable | 603 |
| canceled | 164 |
| created | 5 |
| invoiced | 2 |
| shipped | 1 |

Most orders without item records are therefore associated with
`unavailable` or `canceled` states and are preserved in the raw data.

The single order without a payment record has status `delivered`.

---

## 3. Order Items

**Source file:** `olist_order_items_dataset.csv`

**Grain:** One item position within an order.

**Candidate primary key:** (`order_id`, `order_item_id`)

**Foreign keys:**

- `order_id` → `orders.order_id`
- `product_id` → `products.product_id`
- `seller_id` → `sellers.seller_id`

### Columns

| Column | Raw Type | Nullable | Description |
|---|---|---:|---|
| order_id | string | No | Identifier of the order containing the item |
| order_item_id | int64 | No | Sequential item identifier within an order |
| product_id | string | No | Identifier of the product |
| seller_id | string | No | Identifier of the seller |
| shipping_limit_date | string | No | Seller shipping limit timestamp |
| price | float64 | No | Item price |
| freight_value | float64 | No | Freight value associated with the item |

### Validated Characteristics

- 112,650 rows and 7 columns.
- (`order_id`, `order_item_id`) is unique.
- 98,666 distinct `order_id` values.
- No exact duplicate rows.
- No missing values.
- Every `order_id` references an existing order.
- Every `product_id` references an existing product.
- Every `seller_id` references an existing seller.

---

## 4. Order Payments

**Source file:** `olist_order_payments_dataset.csv`

**Grain:** One payment sequence associated with an order.

An order may contain multiple payment records when more than one
payment method or payment sequence is used.

**Candidate primary key:** (`order_id`, `payment_sequential`)

**Foreign key:**

- `order_id` → `orders.order_id`

### Columns

| Column | Raw Type | Nullable | Description |
|---|---|---:|---|
| order_id | string | No | Identifier of the order associated with the payment |
| payment_sequential | int64 | No | Sequential payment identifier within an order |
| payment_type | string | No | Payment method used by the customer |
| payment_installments | int64 | No | Number of payment installments |
| payment_value | float64 | No | Payment transaction value |

### Validated Characteristics

- 103,886 rows and 5 columns.
- (`order_id`, `payment_sequential`) is unique.
- 99,440 distinct `order_id` values.
- No exact duplicate rows.
- No missing values.
- Every `order_id` references an existing order.
- One order has no corresponding payment record.

---

## 5. Order Reviews

**Source file:** `olist_order_reviews_dataset.csv`

**Grain:** One review record associated with an order.

**Candidate primary key:** (`review_id`, `order_id`)

**Foreign key:**

- `order_id` → `orders.order_id`

### Columns

| Column | Raw Type | Nullable | Description |
|---|---|---:|---|
| review_id | string | No | Identifier of the review |
| order_id | string | No | Identifier of the order being reviewed |
| review_score | int64 | No | Satisfaction score given by the customer from 1 to 5 |
| review_comment_title | string | Yes | Optional title of the review left by the customer |
| review_comment_message | string | Yes | Optional review message left by the customer |
| review_creation_date | string | No | Date on which the satisfaction survey was sent |
| review_answer_timestamp | string | No | Timestamp at which the satisfaction survey was answered |

### Validated Characteristics

- 99,224 rows and 7 columns.
- (`review_id`, `order_id`) is unique.
- Neither `review_id` nor `order_id` is individually unique.
- 98,410 distinct `review_id` values.
- 98,673 distinct `order_id` values.
- No exact duplicate rows.
- 87,656 missing `review_comment_title` values.
- 58,247 missing `review_comment_message` values.
- Every `order_id` references an existing order.
- 768 orders have no corresponding review record.

### Modeling Note

The raw data does not support a strict one-order-to-one-review
assumption. Some orders have multiple review records.

---

## 6. Products

**Source file:** `olist_products_dataset.csv`

**Grain:** One product.

**Candidate primary key:** `product_id`

**Relationships:**

- Referenced by `order_items.product_id`.
- `product_category_name` maps to
  `category_translation.product_category_name`, but the source data
  contains 2 category values without a corresponding translation.

### Columns

| Column | Raw Type | Nullable | Description |
|---|---|---:|---|
| product_id | string | No | Identifier of the product |
| product_category_name | string | Yes | Product category name in Portuguese |
| product_name_lenght | float64 | Yes | Number of characters in the product name |
| product_description_lenght | float64 | Yes | Number of characters in the product description |
| product_photos_qty | float64 | Yes | Number of published product photos |
| product_weight_g | float64 | Yes | Product weight in grams |
| product_length_cm | float64 | Yes | Product length in centimeters |
| product_height_cm | float64 | Yes | Product height in centimeters |
| product_width_cm | float64 | Yes | Product width in centimeters |

### Validated Characteristics

- 32,951 rows and 9 columns.
- `product_id` is unique, with 32,951 distinct values.
- No exact duplicate rows.
- 610 missing values in each of:
  - `product_category_name`
  - `product_name_lenght`
  - `product_description_lenght`
  - `product_photos_qty`
- 2 missing values in each of:
  - `product_weight_g`
  - `product_length_cm`
  - `product_height_cm`
  - `product_width_cm`
- 73 distinct non-null `product_category_name` values.
- 2 product category values have no corresponding entry in the
  category translation table.

The identical null counts do not by themselves prove that the missing
values occur in exactly the same product records.

---

## 7. Sellers

**Source file:** `olist_sellers_dataset.csv`

**Grain:** One seller.

**Candidate primary key:** `seller_id`

**Relationships:**

- Referenced by `order_items.seller_id`.
- `seller_zip_code_prefix` can be associated with
  `geolocation.geolocation_zip_code_prefix`, but the raw geolocation
  table contains multiple rows per ZIP-code prefix.

### Columns

| Column | Raw Type | Nullable | Description |
|---|---|---:|---|
| seller_id | string | No | Identifier of the seller |
| seller_zip_code_prefix | string (5 digits) | No | First five digits of the seller CEP; leading zeroes are significant |
| seller_city | string | No | Seller city |
| seller_state | string | No | Seller state |

### Validated Characteristics

- 3,095 rows and 4 columns.
- `seller_id` is unique, with 3,095 distinct values.
- 2,246 distinct `seller_zip_code_prefix` values.
- No exact duplicate rows.
- No missing values.
- Every `order_items.seller_id` references an existing seller.

---

## 8. Geolocation

**Source file:** `olist_geolocation_dataset.csv`

**Grain:** One geographic observation associated with a ZIP-code prefix.

**Candidate primary key:** None identified in the raw source.

### Relationships

- `customer_zip_code_prefix` can be associated with
  `geolocation_zip_code_prefix`.
- `seller_zip_code_prefix` can be associated with
  `geolocation_zip_code_prefix`.

These relationships must not be interpreted as conventional
many-to-one foreign-key relationships against the raw geolocation
table because a ZIP-code prefix can occur in multiple geolocation rows.

### Columns

| Column | Raw Type | Nullable | Description |
|---|---|---:|---|
| geolocation_zip_code_prefix | string (5 digits) | No | First five digits of the CEP associated with the geographic observation; leading zeroes are significant |
| geolocation_lat | float64 | No | Latitude |
| geolocation_lng | float64 | No | Longitude |
| geolocation_city | string | No | City |
| geolocation_state | string | No | State |

### Validated Characteristics

- 1,000,163 rows and 5 columns.
- 19,015 distinct `geolocation_zip_code_prefix` values.
- 261,831 exact duplicate rows.
- No missing values.
- `geolocation_zip_code_prefix` is not unique.
- No unique raw key has been established.

### Modeling Warning

A direct join such as:

`customers.customer_zip_code_prefix = geolocation.geolocation_zip_code_prefix`

can produce multiple output rows for a single customer because the
geolocation table contains multiple records for the same ZIP-code
prefix.

The same issue applies to sellers.

The raw geolocation dataset must therefore not be treated as a
one-row-per-ZIP dimension.

A downstream transformation should derive an explicitly documented
one-row-per-ZIP representation before geolocation is used as a
dimension or joined to customer/seller records where one geographic
row per ZIP is required.

Exact duplicates are preserved in the immutable raw layer until that
transformation is defined.

---

## 9. Category Translation

**Source file:** `product_category_name_translation.csv`

**Grain:** One Portuguese-to-English product category translation.

**Candidate primary key:** `product_category_name`

**Relationships:**

- Referenced conceptually by `products.product_category_name`.
- Translation coverage is incomplete: 2 category values appearing in
  products do not have corresponding translation records.

### Columns

| Column | Raw Type | Nullable | Description |
|---|---|---:|---|
| product_category_name | string | No | Product category name in Portuguese |
| product_category_name_english | string | No | English translation of the product category name |

### Validated Characteristics

- 71 rows and 2 columns.
- `product_category_name` is unique, with 71 distinct values.
- No exact duplicate rows.
- No missing values.
- Products contain 73 distinct non-null category values.
- 2 category values appearing in products have no corresponding
  translation record.

---

## Source Data Quality Summary

The raw source files are generally relationally consistent.

All tested core foreign-key relationships contain zero orphan key
values:

- `orders.customer_id` → `customers.customer_id`
- `order_items.order_id` → `orders.order_id`
- `order_items.product_id` → `products.product_id`
- `order_items.seller_id` → `sellers.seller_id`
- `order_payments.order_id` → `orders.order_id`
- `order_reviews.order_id` → `orders.order_id`

Known exceptions and modeling considerations include:

- Product-category translation coverage is incomplete.
- One delivered order has no payment record.
- Some orders have no item or review records.
- Review text fields contain substantial optional missing data.
- Several order lifecycle timestamps contain missing values.
- Product metadata contains missing values.
- The geolocation table contains substantial duplication and does not
  have one row per ZIP-code prefix.
- Review records are not one-to-one with orders.
- Customer identity requires distinguishing `customer_id` from
  `customer_unique_id`.

These characteristics are preserved in the raw layer and will be
handled explicitly during downstream schema design, transformation,
analysis, and warehouse construction.