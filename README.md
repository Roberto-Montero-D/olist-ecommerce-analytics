# Olist E-Commerce Analytics

End-to-end analytics and data-science portfolio project built from the
Brazilian E-Commerce Public Dataset by Olist.

The project develops a reproducible path from immutable raw CSV files to
PostgreSQL source tables, SQL business analysis, a dimensional
warehouse, Python exploratory analytics, and later Power BI and machine
learning.

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

  B3                      Python exploratory      Complete
                          analytics               

  B4                      Power BI / business     Next
                          intelligence            

  B5                      Feature engineering /   Planned
                          machine learning        
  -----------------------------------------------------------------------

## Architecture

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
B3 Python / pandas / statistical EDA
        |
        +--> B4 Power BI
        |
        +--> B5 ML
```

The source layer is treated as immutable. Cleaning, geographic
canonicalization, derived measures, and dimensional transformations
occur downstream.

## Technology

-   PostgreSQL 17
-   Docker / Docker Compose
-   SQL
-   Python
-   pandas / NumPy
-   SQLAlchemy / psycopg2
-   Matplotlib
-   SciPy
-   Jupyter
-   Git / GitHub
-   Power BI (B4)

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
├── notebooks/
│   └── 01_warehouse_eda.ipynb
├── src/
│   ├── __init__.py
│   ├── database.py
│   ├── audit_raw_data.py
│   └── audit_relationships.py
├── powerbi/
├── docs/
│   ├── figures/
│   ├── data_dictionary.md
│   ├── B1_sql_business_analysis.md
│   ├── B2_dimensional_model.md
│   ├── B2_warehouse_data_dictionary.md
│   ├── B2_warehouse_validation.md
│   └── B3_python_eda_findings.md
├── tests/
├── .gitignore
├── docker-compose.yml
├── pyproject.toml
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

B1 establishes the descriptive baseline for orders/revenue,
categories/sellers, customers/geography, and delivery/satisfaction.
November 2017 delivered orders increased 62.77% month over month while
merchandise revenue increased 52.37%, with AOV declining from
approximately R\$144.76 to R\$135.51.

See `docs/B1_sql_business_analysis.md`.

## B2 --- Dimensional data warehouse

The warehouse uses a fact constellation with conformed dimensions rather
than flattening business processes with different grains.

### Dimensions

-   `dw.dim_date`
-   `dw.dim_customer`
-   `dw.dim_location`
-   `dw.dim_product`
-   `dw.dim_seller`
-   `dw.dim_order_status`

### Facts

-   `dw.fact_orders` --- one row per order
-   `dw.fact_order_items` --- one row per `(order_id, order_item_id)`
-   `dw.fact_payments` --- one row per `(order_id, payment_sequential)`
-   `dw.fact_reviews` --- one raw review event per
    `(review_id, order_id)`

Final validation found zero source-to-warehouse fact-count differences,
zero tested natural-grain duplicates, zero tested dimensional orphans,
zero invalid date-key mappings, and exact financial reconciliation.

See `docs/B2_dimensional_model.md` and
`docs/B2_warehouse_validation.md`.

## B3 --- Python exploratory analytics

B3 consumes the validated `dw` schema through SQLAlchemy and pandas. It
does not reload the raw CSVs.

The master analytical dataset preserves one row per order. Lower-grain
item, payment, and review facts are aggregated before merging, and
pandas `validate="one_to_one"` checks prevent silent fanout.

### Key findings

-   The controlled EDA population contains **96,211 delivered orders**
    from January 2017 through August 2018.
-   November 2017 order volume increased **62.77%** month over month and
    merchandise revenue increased **52.37%**, while AOV declined
    **6.39%**.
-   The top five product categories account for **39.88%** of
    merchandise revenue; the top 15 account for **76.33%**.
-   **127 of 2,945 active sellers (\~4.3%)** account for 50% of
    merchandise revenue, while the largest seller contributes only
    **1.72%**.
-   Late deliveries have a **54.06%** negative-review rate versus
    **9.20%** for on-time/early deliveries.
-   The observed late-vs-on-time negative-review risk ratio is
    **5.88×**, with an absolute difference of **44.86 percentage
    points**.
-   Delivery delay and latest review score have **Spearman ρ = -0.177 (p
    \< 0.001)**.
-   Review outcomes deteriorate sharply with delay severity: average
    latest review score falls to **1.73** for deliveries more than seven
    days late.
-   Repeat purchasing is approximately **3%** of observed persistent
    customers in the analytical window; this is not treated as a formal
    retention rate.

All delivery/review statements are descriptive associations, not causal
claims.

See `notebooks/01_warehouse_eda.ipynb` and
`docs/B3_python_eda_findings.md`.

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

## Python setup

Create/activate the virtual environment, install the project
dependencies, and install the local project in editable mode:

``` powershell
pip install -r requirements.txt
pip install -e .
```

Database credentials are read from a local `.env` file and are not
committed.

Run Jupyter from the repository environment and execute
`notebooks/01_warehouse_eda.ipynb` with the PostgreSQL container
running.

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
-   `docs/B3_python_eda_findings.md` --- Python EDA design, results,
    interpretation, and limitations

## Next phase

B4 will build the Power BI analytical/reporting layer from the validated
warehouse and B3 findings. B5 will later address late-delivery
prediction with explicit leakage controls.
