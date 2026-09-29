# B3.5 --- System Architecture

**Project:** Olist E-Commerce Analytics\
**Status:** Complete\
**Database:** PostgreSQL 17\
**Architecture:** Source relational schema → dimensional warehouse →
analytical consumers

## 1. Objective

This document describes the end-to-end architecture of the Olist
E-Commerce Analytics project.

The project separates four concerns:

1.  source-data validation and ingestion;
2.  relational source storage;
3.  dimensional transformation and validation;
4.  downstream analytics through SQL, Python, Power BI, and later
    machine learning.

The PostgreSQL `dw` schema is the reusable analytical source of truth
for downstream analytical workloads.

------------------------------------------------------------------------

## 2. High-Level Architecture

![Olist E-Commerce Analytics end-to-end
architecture](diagrams/system_architecture.svg)

The raw Olist files remain outside version control. Python audit scripts
inspect their structure, quality, candidate keys, foreign-key
relationships, and coverage before analytical modeling.

The `olist` schema represents the validated source layer. The `dw`
schema transforms that source into a dimensional fact constellation
while preserving the natural grain of the underlying business processes.

Power BI and machine-learning workloads are separate consumers of the
analytical warehouse. Power BI is not an upstream dependency of the ML
pipeline.

------------------------------------------------------------------------

## 3. Source Database Model

The `olist` schema preserves the source business entities and enforces
relationships where the source data supports them.

![Olist PostgreSQL source database
ERD](diagrams/source_database_erd.svg)

### Logical but non-enforced source relationships

Two useful source relationships are deliberately not represented as
physical foreign keys:

-   `products.product_category_name` →
    `category_translation.product_category_name`
-   customer/seller CEP prefixes →
    `geolocation.geolocation_zip_code_prefix`

The category translation is incomplete for the source product
categories.

Geolocation cannot safely be modeled as a conventional source lookup
table because multiple observations can exist for the same CEP prefix. A
direct join could therefore multiply business rows.

These issues are resolved during dimensional modeling rather than by
modifying the source data.

------------------------------------------------------------------------

## 4. Dimensional Warehouse Model

The `dw` schema uses a fact constellation (galaxy) with shared conformed
dimensions.

### Dimensions

-   `dw.dim_date`
-   `dw.dim_customer`
-   `dw.dim_location`
-   `dw.dim_product`
-   `dw.dim_seller`
-   `dw.dim_order_status`

### Facts

-   `dw.fact_orders`
-   `dw.fact_order_items`
-   `dw.fact_payments`
-   `dw.fact_reviews`

The four facts deliberately preserve different natural grains:

  Fact                 Grain
  -------------------- ----------------------------------------------
  `fact_orders`        One row per `order_id`
  `fact_order_items`   One row per `(order_id, order_item_id)`
  `fact_payments`      One row per `(order_id, payment_sequential)`
  `fact_reviews`       One row per `(review_id, order_id)`

Facts are not joined directly to one another to resolve dimensional
context.

![Olist dimensional warehouse fact
constellation](diagrams/warehouse_model.svg)

The diagram uses a conformed-dimension relationship bus to keep the
constellation readable without implying direct fact-to-fact
relationships. `dim_product` and `dim_seller` remain explicit item-level
dimensions because they relate specifically to `fact_order_items`.

`dim_location` is a conformed dimension used for both customer and
seller geography.

`dim_date` is a role-playing dimension. Different foreign keys represent
purchase, approval, carrier handoff, customer delivery, estimated
delivery, shipping-limit, review-creation, and review-answer dates.

------------------------------------------------------------------------

## 5. Warehouse Transformation Pipeline

Warehouse construction is deterministic and executed in the following
order:

![Olist warehouse build and validation
pipeline](diagrams/warehouse_pipeline.svg)

### Transformation principles

The warehouse pipeline:

-   leaves the `olist` source schema unchanged;
-   uses surrogate integer warehouse keys;
-   retains durable source identifiers as business keys;
-   preserves each business process at its natural grain;
-   resolves dimensions before loading facts;
-   prevents fact-to-fact dimensional resolution;
-   canonicalizes geographic information deterministically;
-   preserves multi-review events;
-   validates financial and row-count reconciliation against the source.

------------------------------------------------------------------------

## 6. Geographic Modeling

Raw geolocation contains multiple observations for individual CEP
prefixes and therefore cannot be joined directly to business facts
without risking row multiplication.

`dw.dim_location` resolves this by producing one canonical member per
five-digit CEP prefix.

Canonicalization includes:

1.  city text normalization;
2.  state normalization;
3.  candidate `(city, state)` frequency calculation;
4.  deterministic modal-pair selection;
5.  deterministic tie-breaking;
6.  canonical raw city-label selection;
7.  median latitude and longitude;
8.  ambiguity and observation metadata.

CEP prefixes used by customers or sellers but absent from the raw
geolocation dataset are retained as fallback dimension members with
source city/state information and NULL coordinates.

This allows the warehouse to preserve business records without
fabricating geographic coordinates.

------------------------------------------------------------------------

## 7. Analytical Consumption

### SQL

`sql/analysis/` contains business-analysis queries covering:

-   orders and revenue;
-   products and sellers;
-   customers and geography;
-   delivery and satisfaction.

### Python

Python connects to PostgreSQL through `src/database.py`.

The primary B3 exploratory analysis is:

`notebooks/01_warehouse_eda.ipynb`

The warehouse provides the analytical dataset rather than requiring the
notebook to reconstruct business relationships from raw CSV files.

### Power BI

Power BI will connect to the PostgreSQL warehouse and build its semantic
model from the conformed dimensions and facts.

Multiple date roles and customer/seller location roles must be
represented deliberately in the Power BI model to avoid ambiguous
relationships.

Facts should not be joined directly to other facts because their
different grains can produce fan-out and double-counting.

### Machine Learning

The later B5 machine-learning phase will consume engineered analytical
data derived from the validated warehouse through Python.

Machine learning is independent of the Power BI semantic layer.

------------------------------------------------------------------------

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

Application/database utilities obtain connection information from
environment variables rather than embedding connection details in Python
code.

Raw datasets and local environment configuration remain outside version
control.

------------------------------------------------------------------------

## 9. Continuous Integration Boundary

Continuous Integration validates the repository but is not part of the
analytical data flow. The CI boundary is shown in the end-to-end
architecture diagram in Section 2.

GitHub Actions runs two complementary checks on pushes and pull requests
to `main`:

-   Python quality validation with Ruff;
-   warehouse integration tests against an ephemeral PostgreSQL 17
    service.

The CI environment does not depend on the full Olist dataset because raw
data is intentionally excluded from version control.

Instead, CI uses a small deterministic fixture designed to exercise:

-   source primary and foreign keys;
-   dimensional transformations;
-   geographic canonicalization;
-   surrogate-key resolution;
-   fact grains;
-   date dimensions;
-   derived delivery fields;
-   financial reconciliation;
-   warehouse integrity.

The current integration suite contains nine warehouse tests. CI uses an
ephemeral `olist_test` PostgreSQL database and disposable credentials.
The local persistent Docker database is not used by GitHub Actions.

------------------------------------------------------------------------

## 10. CI vs. CD

At the current project stage, the repository implements **Continuous
Integration**, not Continuous Deployment.

No production application or analytical artifact is currently deployed
automatically.

Continuous Deployment should only be introduced if a later phase
produces an appropriate deployable target, such as:

-   a hosted ML application or API; or
-   an automated supported BI publication workflow.

Until such a deployment target exists, project documentation should
describe the automation as **GitHub Actions CI**, not CI/CD.

------------------------------------------------------------------------

## 11. Architecture Summary

The architecture deliberately separates source storage, dimensional
transformation, analytical consumption, and repository validation.

The PostgreSQL warehouse is the common analytical foundation while SQL,
Python, Power BI, and machine learning remain independent downstream
workloads.

The editable Graphviz sources and rendered SVGs for the four portfolio
architecture diagrams are stored in `docs/diagrams/`.
