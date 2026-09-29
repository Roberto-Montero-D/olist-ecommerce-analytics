# Olist E-Commerce Analytics

End-to-end analytics and data-science portfolio project built from the
Brazilian E-Commerce Public Dataset by Olist.

The project develops a reproducible path from immutable raw CSV files to
PostgreSQL source tables, SQL business analysis, a dimensional data
warehouse, and later BI, Python analytics, feature engineering, and
machine learning.

## Project status

  -----------------------------------------------------------------------
  Phase                   Scope                   Status
  ----------------------- ----------------------- -----------------------
  B0                      Environment, raw-data   Complete
                          audit, source schema,
                          ingestion, validation

  B1                      SQL business analysis   Complete

  B2                      Dimensional modeling    Complete
                          and PostgreSQL data
                          warehouse

  B3                      Python / exploratory    Next
                          analytics

  B4                      Power BI / business     Planned
                          intelligence

  B5                      Feature engineering /   Planned
                          machine learning
  -----------------------------------------------------------------------

## Current architecture

``` text
Raw Olist CSV files
        |
        v
PostgreSQL `olist` source schema
        |
        +--> source validation / data-quality audit
        |
        +--> B1 SQL business analysis
        |
        v
PostgreSQL `dw` dimensional warehouse
        |
        +--> 6 conformed dimensions
        +--> 4 fact tables
        |
        v
Python / BI / ML
```

The source layer is treated as immutable. Cleaning, geographic
canonicalization, derived measures, and dimensional transformations
occur downstream.

## Technology

-   PostgreSQL 17
-   Docker / Docker Compose
-   SQL
-   Python
-   pandas
-   Git / GitHub
-   Power BI (planned downstream phase)

## Repository structure

``` text
olist-ecommerce-analytics/
├── data/
│   ├── raw/                  # ignored raw source files
│   ├── processed/
│   └── README.md
├── sql/
│   ├── schema/
│   ├── ingestion/
│   ├── analysis/
│   └── warehouse/
│       ├── 00_validate_dimensional_design.sql
│       ├── 01_create_warehouse_schema.sql
│       ├── 02_load_dimensions.sql
│       ├── 02b_validate_loaded_dimensions.sql
│       ├── 03_load_facts.sql
│       └── 04_validate_warehouse.sql
├── notebooks/
├── src/
├── powerbi/
├── docs/
│   ├── data_dictionary.md
│   ├── B1_sql_business_analysis.md
│   ├── B2_dimensional_model.md
│   ├── B2_warehouse_data_dictionary.md
│   └── B2_warehouse_validation.md
├── tests/
├── .gitignore
├── docker-compose.yml
├── README.md
└── requirements.txt
```

## Source data

Nine Olist source tables are loaded into PostgreSQL.

  Table                         Rows
  ---------------------- -----------
  customers                   99,441
  geolocation              1,000,163
  order_items                112,650
  order_payments             103,886
  order_reviews               99,224
  orders                      99,441
  products                    32,951
  sellers                      3,095
  category_translation            71

Five-digit Brazilian CEP prefixes are stored as character identifiers so
leading zeroes remain significant.

## B1 --- SQL business analysis

The comparable business-analysis period is January 2017 through August
2018, generally using delivered orders.

The SQL analysis covers:

-   orders, revenue, freight, AOV, and monthly trends;
-   product-category and seller performance;
-   customer identity, repeat purchasing, and geography;
-   delivery performance and customer satisfaction.

Examples of validated findings include:

-   November 2017 delivered orders increased 62.77% month over month
    while merchandise revenue increased 52.37%, with AOV decreasing from
    approximately R\$144.76 to R\$135.51.
-   `health_beauty`, `watches_gifts`, and `bed_bath_table` are the three
    largest categories by delivered merchandise revenue.
-   Repeat purchasing is uncommon in the observed period: approximately
    3% of persistent customers have multiple delivered purchases.
-   Late deliveries are strongly associated with lower submitted review
    scores: 2.57 stars on average versus 4.30 for on-time or early
    deliveries.

These are descriptive historical associations; the dataset does not
establish causal effects.

## B2 --- Dimensional data warehouse

The warehouse uses a fact constellation with conformed dimensions rather
than a single flattened table.

### Dimensions

-   `dw.dim_date` --- one calendar date
-   `dw.dim_customer` --- one persistent `customer_unique_id`
-   `dw.dim_location` --- one five-digit CEP prefix
-   `dw.dim_product` --- one product
-   `dw.dim_seller` --- one seller
-   `dw.dim_order_status` --- one order status

### Facts

-   `dw.fact_orders` --- one row per order
-   `dw.fact_order_items` --- one row per `(order_id, order_item_id)`
-   `dw.fact_payments` --- one row per `(order_id, payment_sequential)`
-   `dw.fact_reviews` --- one raw review event per
    `(review_id, order_id)`

`order_id` is retained as a degenerate business identifier. Facts share
dimensions and are not modeled with fact-to-fact foreign keys.

### Geographic modeling

Raw geolocation contains many observations per CEP prefix, so it cannot
safely be joined directly as a one-row-per-location dimension.

The warehouse:

1.  preserves CEP prefixes as five-character identifiers;
2.  performs deterministic lexical city normalization;
3.  selects the modal normalized `(city, state)` pair per prefix;
4.  uses deterministic lexical tie-breaking;
5.  stores median latitude and longitude per geolocation prefix;
6.  retains ambiguity/provenance metadata;
7.  creates fallback location members for customer/seller prefixes
    absent from geolocation.

Final `dim_location` contains 19,177 members: 19,015 geolocation-backed
prefixes and 162 fallback prefixes. Pair-level ambiguity is explicitly
flagged for 518 geolocation prefixes.

### Review modeling

Reviews are not collapsed to one row per order. The source contains
99,224 review rows for 98,673 reviewed orders; 547 orders have multiple
reviews and 202 of those have differing scores. The warehouse therefore
preserves the atomic review-event grain.

## Warehouse validation

B2 final validation passed:

-   source-to-warehouse fact row differences: 0;
-   natural-grain duplicate groups: 0;
-   tested dimensional orphan rows: 0;
-   invalid date-key mappings: 0;
-   invalid derived delivery calculations: 0;
-   merchandise-price difference from source: R\$0.00;
-   freight difference from source: R\$0.00;
-   payment-value difference from source: R\$0.00;
-   invalid review scores/comment flags: 0.

Warehouse analytical smoke tests also reproduce the established B1
revenue, category, and delivery/satisfaction results.

See `docs/B2_warehouse_validation.md` for the validation record.

## Rebuilding the warehouse

With the PostgreSQL container running and the source `olist` schema
already loaded:

``` powershell
Get-Content sql/warehouse/00_validate_dimensional_design.sql |
    docker exec -i olist_postgres psql -v ON_ERROR_STOP=1 -U olist -d olist

Get-Content sql/warehouse/01_create_warehouse_schema.sql |
    docker exec -i olist_postgres psql -v ON_ERROR_STOP=1 -U olist -d olist

Get-Content sql/warehouse/02_load_dimensions.sql |
    docker exec -i olist_postgres psql -v ON_ERROR_STOP=1 -U olist -d olist

Get-Content sql/warehouse/02b_validate_loaded_dimensions.sql |
    docker exec -i olist_postgres psql -v ON_ERROR_STOP=1 -U olist -d olist

Get-Content sql/warehouse/03_load_facts.sql |
    docker exec -i olist_postgres psql -v ON_ERROR_STOP=1 -U olist -d olist

Get-Content sql/warehouse/04_validate_warehouse.sql |
    docker exec -i olist_postgres psql -v ON_ERROR_STOP=1 -U olist -d olist
```

## Documentation

-   `docs/data_dictionary.md` --- immutable source-layer data dictionary
    and data-quality notes
-   `docs/B1_sql_business_analysis.md` --- SQL business analysis and
    findings
-   `docs/B2_dimensional_model.md` --- dimensional-model design and
    modeling decisions
-   `docs/B2_warehouse_data_dictionary.md` --- warehouse grains and
    field semantics
-   `docs/B2_warehouse_validation.md` --- final warehouse validation
    record

## Next phase

B3 will use the validated dimensional warehouse as the analytical source
for Python-based exploratory analysis and downstream portfolio work.
