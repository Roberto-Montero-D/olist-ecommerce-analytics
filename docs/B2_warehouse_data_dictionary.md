# B2 Warehouse Data Dictionary Addendum

This addendum documents the warehouse layer. The existing `docs/data_dictionary.md` remains the
source-layer data dictionary and should not be overwritten.

## Warehouse grains

| Table                 | Grain                                         | Business key                       |
|-----------------------|-----------------------------------------------|------------------------------------|
| `dw.dim_date`         | One calendar date                             | `full_date` / `date_key`           |
| `dw.dim_customer`     | One persistent customer                       | `customer_unique_id`               |
| `dw.dim_location`     | One five-digit CEP prefix                     | `zip_code_prefix`                  |
| `dw.dim_product`      | One product                                   | `product_id`                       |
| `dw.dim_seller`       | One seller                                    | `seller_id`                        |
| `dw.dim_order_status` | One order status                              | `order_status`                     |
| `dw.fact_orders`      | One order                                     | `order_id`                         |
| `dw.fact_order_items` | One item position in an order                 | (`order_id`, `order_item_id`)      |
| `dw.fact_payments`    | One payment sequence in an order              | (`order_id`, `payment_sequential`) |
| `dw.fact_reviews`     | One raw review event associated with an order | (`review_id`, `order_id`)          |

## Important semantic decisions

- `customer_unique_id`, not `customer_id`, defines persistent customer identity.
- Customer location is transactional and is not frozen onto `dim_customer`.
- CEP prefixes are `CHAR(5)` identifiers and retain leading zeroes.
- `dim_location` canonicalizes noisy geolocation labels at CEP-prefix grain.
- Ambiguous CEP prefixes use the modal normalized `(city,state)` pair with a deterministic lexical
  tie-break.
- Geographic coordinates use CEP-level medians.
- `fact_reviews` preserves every source review row; reviews are not averaged or collapsed during
  warehouse loading.
- `order_id` is a degenerate dimension carried by each relevant fact; no `dim_order` is created.
- Facts connect to shared conformed dimensions rather than to one another.
- Monetary measures use fixed-precision `NUMERIC`.
