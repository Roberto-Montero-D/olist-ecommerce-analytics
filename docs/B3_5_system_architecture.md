# B3.5 — System Architecture

**Project:** Olist E-Commerce Analytics
**Status:** Architecture documented
**Database:** PostgreSQL 17
**Architecture:** Source relational schema → dimensional warehouse → analytical consumers

## 1. Objective

This document describes the end-to-end architecture of the Olist E-Commerce Analytics project.

The project separates four concerns:

1. source-data validation and ingestion;
2. relational source storage;
3. dimensional transformation and validation;
4. downstream analytics through SQL, Python, Power BI, and later machine learning.

The PostgreSQL `dw` schema is the reusable analytical source of truth for downstream analytical
workloads.

----------------------------------------------------------------------------------------------------

## 2. High-Level Architecture

``` mermaid
flowchart TD
    CSV["Olist CSV Dataset<br/>data/raw/"]
    AUDIT["Python Data Audits<br/>src/audit_raw_data.py<br/>src/audit_relationships.py"]
    SOURCE["PostgreSQL Source Layer<br/>schema: olist"]
    DW["PostgreSQL Data Warehouse<br/>schema: dw"]
    SQL["SQL Business Analysis<br/>sql/analysis/"]
    PY["Python EDA<br/>notebooks/01_warehouse_eda.ipynb"]
    BI["Power BI<br/>Semantic Model & Dashboards"]
    ML["Machine Learning<br/>Future B5 Phase"]

    CSV --> AUDIT
    CSV --> SOURCE
    AUDIT -. validates .-> SOURCE
    SOURCE --> DW
    SOURCE --> SQL
    DW --> PY
    DW --> BI
    DW --> ML
```

The raw Olist files remain outside version control. Python audit scripts inspect their structure,
quality, candidate keys, foreign-key relationships, and coverage before analytical modeling.

The `olist` schema represents the validated source layer. The `dw` schema transforms that source
into a dimensional fact constellation while preserving the natural grain of the underlying business
processes.

Power BI and machine-learning workloads are separate consumers of the analytical warehouse. Power BI
is not an upstream dependency of the ML pipeline.

----------------------------------------------------------------------------------------------------

## 3. Source Database Model

The `olist` schema preserves the source business entities and enforces relationships where the
source data supports them.

``` mermaid
erDiagram
    CUSTOMERS ||--o{ ORDERS : places
    ORDERS ||--o{ ORDER_ITEMS : contains
    ORDERS ||--o{ ORDER_PAYMENTS : has
    ORDERS ||--o{ ORDER_REVIEWS : receives
    PRODUCTS ||--o{ ORDER_ITEMS : referenced_by
    SELLERS ||--o{ ORDER_ITEMS : sells

    CUSTOMERS {
        text customer_id PK
        text customer_unique_id
        char customer_zip_code_prefix
        text customer_city
        text customer_state
    }

    ORDERS {
        text order_id PK
        text customer_id FK
        text order_status
        timestamp order_purchase_timestamp
        timestamp order_approved_at
        timestamp order_delivered_carrier_date
        timestamp order_delivered_customer_date
        timestamp order_estimated_delivery_date
    }

    ORDER_ITEMS {
        text order_id PK,FK
        integer order_item_id PK
        text product_id FK
        text seller_id FK
        timestamp shipping_limit_date
        numeric price
        numeric freight_value
    }

    ORDER_PAYMENTS {
        text order_id PK,FK
        integer payment_sequential PK
        text payment_type
        integer payment_installments
        numeric payment_value
    }

    ORDER_REVIEWS {
        text review_id PK
        text order_id PK,FK
        integer review_score
        text review_comment_title
        text review_comment_message
        timestamp review_creation_date
        timestamp review_answer_timestamp
    }

    PRODUCTS {
        text product_id PK
        text product_category_name
        integer product_name_lenght
        integer product_description_lenght
        integer product_photos_qty
        numeric product_weight_g
        numeric product_length_cm
        numeric product_height_cm
        numeric product_width_cm
    }

    SELLERS {
        text seller_id PK
        char seller_zip_code_prefix
        text seller_city
        text seller_state
    }

    CATEGORY_TRANSLATION {
        text product_category_name PK
        text product_category_name_english
    }

    GEOLOCATION {
        char geolocation_zip_code_prefix
        numeric geolocation_lat
        numeric geolocation_lng
        text geolocation_city
        text geolocation_state
    }
```

### Logical but non-enforced source relationships

Two useful source relationships are deliberately not represented as physical foreign keys:

- `products.product_category_name` → `category_translation.product_category_name`
- customer/seller CEP prefixes → `geolocation.geolocation_zip_code_prefix`

The category translation is incomplete for the source product categories.

Geolocation cannot safely be modeled as a conventional source lookup table because multiple
observations can exist for the same CEP prefix. A direct join could therefore multiply business
rows.

These issues are resolved during dimensional modeling rather than by modifying the source data.

----------------------------------------------------------------------------------------------------

## 4. Dimensional Warehouse Model

The `dw` schema uses a fact constellation (galaxy) with shared conformed dimensions.

### Dimensions

- `dw.dim_date`
- `dw.dim_customer`
- `dw.dim_location`
- `dw.dim_product`
- `dw.dim_seller`
- `dw.dim_order_status`

### Facts

- `dw.fact_orders`
- `dw.fact_order_items`
- `dw.fact_payments`
- `dw.fact_reviews`

The four facts deliberately preserve different natural grains:

| Fact               | Grain                                        |
|--------------------|----------------------------------------------|
| `fact_orders`      | One row per `order_id`                       |
| `fact_order_items` | One row per `(order_id, order_item_id)`      |
| `fact_payments`    | One row per `(order_id, payment_sequential)` |
| `fact_reviews`     | One row per `(review_id, order_id)`          |

Facts are not joined directly to one another to resolve dimensional context.

``` mermaid
flowchart TB
    DATE["dim_date"]
    CUSTOMER["dim_customer"]
    LOCATION["dim_location"]
    PRODUCT["dim_product"]
    SELLER["dim_seller"]
    STATUS["dim_order_status"]

    ORDERS["fact_orders<br/>grain: order_id"]
    ITEMS["fact_order_items<br/>grain: order_id + order_item_id"]
    PAYMENTS["fact_payments<br/>grain: order_id + payment_sequential"]
    REVIEWS["fact_reviews<br/>grain: review_id + order_id"]

    CUSTOMER --> ORDERS
    LOCATION --> ORDERS
    STATUS --> ORDERS
    DATE --> ORDERS

    PRODUCT --> ITEMS
    SELLER --> ITEMS
    CUSTOMER --> ITEMS
    LOCATION --> ITEMS
    STATUS --> ITEMS
    DATE --> ITEMS

    CUSTOMER --> PAYMENTS
    LOCATION --> PAYMENTS
    STATUS --> PAYMENTS
    DATE --> PAYMENTS

    CUSTOMER --> REVIEWS
    LOCATION --> REVIEWS
    STATUS --> REVIEWS
    DATE --> REVIEWS
```

`dim_location` is a conformed dimension used for both customer and seller geography.

`dim_date` is a role-playing dimension. Different foreign keys represent purchase, approval, carrier
handoff, customer delivery, estimated delivery, shipping-limit, review-creation, and review-answer
dates.

----------------------------------------------------------------------------------------------------

## 5. Warehouse Transformation Pipeline

Warehouse construction is deterministic and executed in the following order:

``` mermaid
flowchart TD
    A["00_validate_dimensional_design.sql<br/>Validate modeling assumptions"]
    B["01_create_warehouse_schema.sql<br/>Create dimensions, facts, constraints & indexes"]
    C["02_load_dimensions.sql<br/>Build conformed dimensions"]
    D["02b_validate_loaded_dimensions.sql<br/>Validate dimensional results"]
    E["03_load_facts.sql<br/>Populate facts at natural grain"]
    F["04_validate_warehouse.sql<br/>Final reconciliation & analytical validation"]

    A --> B --> C --> D --> E --> F
```

### Transformation principles

The warehouse pipeline:

- leaves the `olist` source schema unchanged;
- uses surrogate integer warehouse keys;
- retains durable source identifiers as business keys;
- preserves each business process at its natural grain;
- resolves dimensions before loading facts;
- prevents fact-to-fact dimensional resolution;
- canonicalizes geographic information deterministically;
- preserves multi-review events;
- validates financial and row-count reconciliation against the source.

----------------------------------------------------------------------------------------------------

## 6. Geographic Modeling

Raw geolocation contains multiple observations for individual CEP prefixes and therefore cannot be
joined directly to business facts without risking row multiplication.

`dw.dim_location` resolves this by producing one canonical member per five-digit CEP prefix.

Canonicalization includes:

1. city text normalization;
2. state normalization;
3. candidate `(city, state)` frequency calculation;
4. deterministic modal-pair selection;
5. deterministic tie-breaking;
6. canonical raw city-label selection;
7. median latitude and longitude;
8. ambiguity and observation metadata.

CEP prefixes used by customers or sellers but absent from the raw geolocation dataset are retained
as fallback dimension members with source city/state information and NULL coordinates.

This allows the warehouse to preserve business records without fabricating geographic coordinates.

----------------------------------------------------------------------------------------------------

## 7. Analytical Consumption

### SQL

`sql/analysis/` contains business-analysis queries covering:

- orders and revenue;
- products and sellers;
- customers and geography;
- delivery and satisfaction.

### Python

Python connects to PostgreSQL through `src/database.py`.

The primary B3 exploratory analysis is:

`notebooks/01_warehouse_eda.ipynb`

The warehouse provides the analytical dataset rather than requiring the notebook to reconstruct
business relationships from raw CSV files.

### Power BI

Power BI will connect to the PostgreSQL warehouse and build its semantic model from the conformed
dimensions and facts.

Multiple date roles and customer/seller location roles must be represented deliberately in the Power
BI model to avoid ambiguous relationships.

Facts should not be joined directly to other facts because their different grains can produce
fan-out and double-counting.

### Machine Learning

The later B5 machine-learning phase will consume engineered analytical data derived from the
validated warehouse through Python.

Machine learning is independent of the Power BI semantic layer.

----------------------------------------------------------------------------------------------------

## 8. Development and Runtime Architecture

``` mermaid
flowchart LR
    DEV["Local Development<br/>Python / SQL / Jupyter"]
    DOCKER["Docker Compose"]
    PG["PostgreSQL 17<br/>olist database"]
    SOURCE["olist schema"]
    DW["dw schema"]

    DEV --> DOCKER
    DOCKER --> PG
    PG --> SOURCE
    SOURCE --> DW
```

Local PostgreSQL is provided through Docker Compose.

Application/database utilities obtain connection information from environment variables rather than
embedding connection details in Python code.

Raw datasets and local environment configuration remain outside version control.

----------------------------------------------------------------------------------------------------

## 9. Continuous Integration Boundary

Continuous Integration validates the repository but is not part of the analytical data flow.

``` mermaid
flowchart TD
    PUSH["Git Push / Pull Request"]
    GHA["GitHub Actions"]
    PY["Python Quality & Unit Tests"]
    PG["Ephemeral PostgreSQL 17"]
    FIX["Synthetic Test Fixture"]
    SQL["Source + Warehouse Integration Tests"]
    RESULT["CI Pass / Fail"]

    PUSH --> GHA
    GHA --> PY
    GHA --> PG
    FIX --> PG
    PG --> SQL
    PY --> RESULT
    SQL --> RESULT
```

The CI environment must not depend on the full Olist dataset because raw data is intentionally
excluded from version control.

Instead, CI uses a small deterministic fixture designed to exercise:

- source primary and foreign keys;
- dimensional transformations;
- geographic canonicalization;
- surrogate-key resolution;
- fact grains;
- date dimensions;
- derived delivery fields;
- financial reconciliation;
- warehouse integrity.

CI uses an ephemeral PostgreSQL instance and disposable credentials.

The local persistent Docker database is not used by GitHub Actions.

----------------------------------------------------------------------------------------------------

## 10. CI vs. CD

At the current project stage, the repository implements **Continuous Integration**, not Continuous
Deployment.

No production application or analytical artifact is currently deployed automatically.

Continuous Deployment should only be introduced if a later phase produces an appropriate deployable
target, such as:

- a hosted ML application or API; or
- an automated supported BI publication workflow.

Until such a deployment target exists, project documentation should describe the automation as
**GitHub Actions CI**, not CI/CD.

----------------------------------------------------------------------------------------------------

## 11. Architecture Summary

The resulting architecture is:

``` text
Olist CSV Dataset
        │
        ├──── Python source-data audits
        │
        ▼
PostgreSQL `olist` source schema
        │
        ├──── SQL business analysis
        │
        ▼
Dimensional transformation
        │
        ▼
PostgreSQL `dw` warehouse
        │
        ├──────── Python EDA
        ├──────── Power BI
        └──────── Machine Learning
```

The architecture deliberately separates source storage, dimensional transformation, analytical
consumption, and repository validation.

The PostgreSQL warehouse is the common analytical foundation while SQL, Python, Power BI, and
machine learning remain independent downstream workloads.
