# Data Directory

This directory contains the local data used by the Olist E-Commerce Analytics project.

The project is based on the **Olist Brazilian E-Commerce Public Dataset**. Raw dataset files are
intentionally excluded from Git and must be obtained separately before running the ingestion
pipeline.

## Directory Structure

```text
data/
├── raw/          # Original Olist CSV files; excluded from Git
├── processed/    # Locally generated data artifacts; excluded from Git
└── README.md     # Data directory documentation
```

## Required Raw Files

Place the following nine CSV files in `data/raw/` without renaming them:

```text
olist_customers_dataset.csv
olist_geolocation_dataset.csv
olist_order_items_dataset.csv
olist_order_payments_dataset.csv
olist_order_reviews_dataset.csv
olist_orders_dataset.csv
olist_products_dataset.csv
olist_sellers_dataset.csv
product_category_name_translation.csv
```

The ingestion pipeline depends on these exact filenames.

## Docker Access

The local `data/raw/` directory is mounted read-only inside the PostgreSQL container at:

```text
/tmp/olist_raw
```

This allows the PostgreSQL ingestion scripts to read the source CSV files without copying them
into the container.

## Data Documentation

Column definitions, candidate keys, relationships, missing-value findings, and raw-data integrity
notes are documented in [`../docs/data_dictionary.md`](../docs/data_dictionary.md).

Raw and processed data are intentionally excluded from version control. Only this documentation
file is tracked from the `data/` directory.
